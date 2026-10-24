param(
    [ValidateSet(
        'push', 'push-rtl', 'push-sim', 'push-sw',
        'pull', 'pull-sim', 'pull-sw'
    )]
    [string]$Action = 'push',

    [string]$Vm = 'edward',
    [string]$RemoteRoot = '~/File/EdRV32-Competition-2026'
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Invoke-External {
    param(
        [string]$Program,
        [string[]]$Arguments
    )

    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Program failed with exit code $LASTEXITCODE"
    }
}

function Push-Directories {
    param([string[]]$Names)

    $archiveName = "edrv32-source-$PID.tar.gz"
    $archivePath = Join-Path ([IO.Path]::GetTempPath()) $archiveName
    $remoteArchive = "/tmp/$archiveName"
    $remoteRootShell = $RemoteRoot -replace '^~', '$HOME'
    $nameList = $Names -join ' '

    try {
        Push-Location $ProjectRoot
        try {
            $tarArguments = @(
                '-czf', $archivePath,
                '--exclude=*/build',
                '--exclude=*/build/*'
            ) + $Names + @('Makefile')
            Invoke-External 'tar' $tarArguments
        }
        finally {
            Pop-Location
        }

        Invoke-External 'scp' @($archivePath, "${Vm}:$remoteArchive")

        $remoteCommand = @'
set -eu
remote_root="__REMOTE_ROOT__"
archive="__ARCHIVE__"
stage=$(mktemp -d)
trap 'rm -rf "$stage" "$archive"' EXIT
mkdir -p "$remote_root"
tar -xzf "$archive" -C "$stage"
for name in __NAMES__; do
    mkdir -p "$remote_root/$name"
    rsync -a --delete --exclude='build/' "$stage/$name/" "$remote_root/$name/"
done
cp "$stage/Makefile" "$remote_root/Makefile"
'@
        $remoteCommand = $remoteCommand.Replace('__REMOTE_ROOT__', $remoteRootShell)
        $remoteCommand = $remoteCommand.Replace('__ARCHIVE__', $remoteArchive)
        $remoteCommand = $remoteCommand.Replace('__NAMES__', $nameList)
        Invoke-External 'ssh' @($Vm, $remoteCommand)

        Write-Host "Synced $nameList -> ${Vm}:$RemoteRoot"
    }
    finally {
        if (Test-Path -LiteralPath $archivePath) {
            Remove-Item -LiteralPath $archivePath
        }
    }
}

function Pull-SimBuild {
    $remotePath = "$RemoteRoot/sim/build"
    & ssh $Vm "test -d $remotePath"
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'No remote sim/build directory.'
        return
    }

    $localSim = Join-Path $ProjectRoot 'sim'
    Invoke-External 'scp' @('-r', "${Vm}:$remotePath", $localSim)
    Write-Host "Synced ${Vm}:$remotePath -> $localSim"
}

function Pull-SwBuilds {
    $findCommand = "cd $RemoteRoot && find sw -type d -name build -print"
    $buildDirectories = @(& ssh $Vm $findCommand)
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to list software build directories on $Vm"
    }

    foreach ($relativePath in $buildDirectories) {
        if ([string]::IsNullOrWhiteSpace($relativePath)) {
            continue
        }

        $windowsPath = $relativePath.Replace('/', [IO.Path]::DirectorySeparatorChar)
        $localParent = Join-Path $ProjectRoot (Split-Path $windowsPath -Parent)
        New-Item -ItemType Directory -Force -Path $localParent | Out-Null
        Invoke-External 'scp' @(
            '-r',
            "${Vm}:$RemoteRoot/$relativePath",
            $localParent
        )
    }

    Write-Host "Synced software build directories from ${Vm}:$RemoteRoot/sw"
}

switch ($Action) {
    'push'      { Push-Directories @('rtl', 'sim', 'sw', 'third_party/coremark') }
    'push-rtl'  { Push-Directories @('rtl') }
    'push-sim'  { Push-Directories @('sim') }
    'push-sw'   { Push-Directories @('sw', 'third_party/coremark') }
    'pull'      { Pull-SimBuild; Pull-SwBuilds }
    'pull-sim'  { Pull-SimBuild }
    'pull-sw'   { Pull-SwBuilds }
}
