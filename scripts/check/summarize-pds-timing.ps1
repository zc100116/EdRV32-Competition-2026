param(
    [Parameter(Mandatory = $true)]
    [string]$ReportPath,
    [string]$CsvPath = "",
    [int]$TopCount = 20,
    [switch]$IncludeMet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-TimingBucket {
    param([string]$Point)

    switch -Regex ($Point) {
        '/u_if1_stage/'             { return 'IF1_STAGE' }
        '/u_pipe_if1_to_if2/'       { return 'IF1_TO_IF2_PIPE' }
        '/u_if2_stage/'             { return 'IF2_STAGE' }
        '/u_pipe_if2_to_align/'     { return 'IF2_TO_ALIGN_PIPE' }
        '/u_align_stage/'           { return 'ALIGN_STAGE' }
        '/u_pipe_align_to_decode/'  { return 'ALIGN_TO_DECODE_PIPE' }
        '/u_decode_stage/'          { return 'DECODE_STAGE' }
        '/u_pipe_decode_to_ex/'     { return 'DECODE_TO_EX_PIPE' }
        '/u_ex_stage/'              { return 'EX_STAGE' }
        '/u_pipe_ex_to_mem1/'       { return 'EX_TO_MEM1_PIPE' }
        '/u_mem1_stage/'            { return 'MEM1_STAGE' }
        '/u_pipe_mem1_to_mem2/'     { return 'MEM1_TO_MEM2_PIPE' }
        '/u_mem2_stage/'            { return 'MEM2_STAGE' }
        '/u_pipe_mem2_to_commit/'   { return 'MEM2_TO_COMMIT_PIPE' }
        '/u_commit_stage/'          { return 'COMMIT_STAGE' }
        '/u_branch_predictor/'      { return 'BRANCH_PREDICTOR' }
        '/u_redirect_ctrl/'         { return 'REDIRECT_CTRL' }
        '/u_mdu_scoreboard/'        { return 'MDU_SCOREBOARD' }
        '/u_mdu/'                   { return 'MDU' }
        '/u_dcache/'                { return 'DCACHE' }
        '/u_icache/'                { return 'ICACHE' }
        '/u_cache_maint/'           { return 'CACHE_MAINT' }
        '\(port\)$'                 { return 'TOP_IO' }
        default                    { return 'OTHER' }
    }
}

$resolvedReport = (Resolve-Path -LiteralPath $ReportPath).Path
$records = [System.Collections.Generic.List[object]]::new()
$current = $null

foreach ($line in [System.IO.File]::ReadLines($resolvedReport)) {
    if ($line -match '^Startpoint\s*:\s*(.+)$') {
        $current = [ordered]@{
            Startpoint = $Matches[1].Trim()
            Endpoint = ''
            Corner = ''
            ArrivalNs = [double]::NaN
            LogicLevels = -1
            LogicNs = [double]::NaN
            RouteNs = [double]::NaN
        }
        continue
    }
    if ($null -eq $current) {
        continue
    }
    if ($line -match '^Endpoint\s*:\s*(.+)$') {
        $current.Endpoint = $Matches[1].Trim()
        continue
    }
    if ($line -match '^Path Type\s*:\s*max \((slow|fast) corner\)$') {
        $current.Corner = $Matches[1]
        continue
    }
    if (($current.LogicLevels -lt 0) -and
        ($line -match 'Data arrival time\s+(-?[0-9.]+)\s+Logic Levels:\s*([0-9]+)')) {
        $current.ArrivalNs = [double]$Matches[1]
        $current.LogicLevels = [int]$Matches[2]
        continue
    }
    if ($line -match 'Logic:\s*([0-9.]+)ns\([^)]*\), Route:\s*([0-9.]+)ns') {
        $current.LogicNs = [double]$Matches[1]
        $current.RouteNs = [double]$Matches[2]
        continue
    }
    if ($line -match 'Slack \((VIOLATED|MET)\)\s+(-?[0-9.]+)') {
        $records.Add([pscustomobject]@{
            Status = $Matches[1]
            Corner = $current.Corner
            SlackNs = [double]$Matches[2]
            ArrivalNs = $current.ArrivalNs
            LogicLevels = $current.LogicLevels
            LogicNs = $current.LogicNs
            RouteNs = $current.RouteNs
            StartBucket = Get-TimingBucket $current.Startpoint
            EndBucket = Get-TimingBucket $current.Endpoint
            Startpoint = $current.Startpoint
            Endpoint = $current.Endpoint
        })
        $current = $null
    }
}

$violations = @($records | Where-Object Status -eq 'VIOLATED')
$selected = if ($IncludeMet) { @($records) } else { $violations }
if ($CsvPath) {
    $csvParent = Split-Path -Parent $CsvPath
    if ($csvParent) {
        New-Item -ItemType Directory -Force -Path $csvParent | Out-Null
    }
    $selected | Sort-Object SlackNs, Corner, Endpoint |
        Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Encoding UTF8
}

Write-Output "PDS_TIMING_REPORT=$resolvedReport"
Write-Output "PARSED_PATHS=$($records.Count)"
Write-Output "VIOLATING_PATHS=$($violations.Count)"
Write-Output "SELECTED_PATHS=$($selected.Count)"

Write-Output "TOP_PATHS"
$selected | Sort-Object SlackNs, Corner, Endpoint | Select-Object -First $TopCount |
    Format-Table Corner, SlackNs, ArrivalNs, LogicLevels, LogicNs, RouteNs,
        StartBucket, EndBucket, Startpoint, Endpoint -AutoSize | Out-String -Width 360 |
    Write-Output

Write-Output "SELECTED_PATHS_BY_CORNER"
$selected | Group-Object Corner | Sort-Object Name | ForEach-Object {
    $minimum = ($_.Group | Measure-Object SlackNs -Minimum).Minimum
    $sum = ($_.Group | Measure-Object SlackNs -Sum).Sum
    [pscustomobject]@{Corner = $_.Name; Count = $_.Count;
        WorstSlackNs = $minimum; SumSlackNs = [math]::Round($sum, 3)}
} | Format-Table -AutoSize | Out-String | Write-Output

Write-Output "SELECTED_PATHS_BY_START_END_BUCKET"
$selected | Group-Object StartBucket, EndBucket | Sort-Object Count -Descending |
    Select-Object -First 30 | ForEach-Object {
        $minimum = ($_.Group | Measure-Object SlackNs -Minimum).Minimum
        [pscustomobject]@{
            StartBucket = $_.Group[0].StartBucket
            EndBucket = $_.Group[0].EndBucket
            Count = $_.Count
            WorstSlackNs = $minimum
        }
    } | Format-Table -AutoSize | Out-String | Write-Output

Write-Output "SELECTED_PATHS_BY_LOGIC_LEVELS"
$selected | Group-Object LogicLevels | Sort-Object {[int]$_.Name} | ForEach-Object {
    $minimum = ($_.Group | Measure-Object SlackNs -Minimum).Minimum
    [pscustomobject]@{LogicLevels = [int]$_.Name; Count = $_.Count;
        WorstSlackNs = $minimum}
} | Format-Table -AutoSize | Out-String | Write-Output
