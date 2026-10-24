param(
    [string]$PortName = 'COM7',
    [int]$BaudRate = 62500,
    [int]$SamplesPerMode = 16,
    [switch]$ProbeOnly
)

$ErrorActionPreference = 'Stop'
$serial = [System.IO.Ports.SerialPort]::new(
    $PortName, $BaudRate, [System.IO.Ports.Parity]::None, 8,
    [System.IO.Ports.StopBits]::One
)
$serial.ReadTimeout = 3000
$serial.WriteTimeout = 3000
$serial.Handshake = [System.IO.Ports.Handshake]::None
$serial.DtrEnable = $false
$serial.RtsEnable = $false

function Read-DemoRegister {
    param([byte]$Address)
    $serial.DiscardInBuffer()
    [byte[]]$command = @(0x72, $Address, 0x00, 0x00)
    $serial.Write($command, 0, 4)
    [byte[]]$response = New-Object byte[] 4
    $received = 0
    while ($received -lt 4) {
        $received += $serial.Read($response, $received, 4 - $received)
    }
    return [BitConverter]::ToUInt32($response, 0)
}

function Write-DemoRegister {
    param([byte]$Address, [uint32]$Value)
    ('WRITE_BEGIN addr=0x{0:x2} value=0x{1:x8}' -f $Address, $Value)
    Write-DemoRegisterNoRead -Address $Address -Value $Value
    $readback = Read-DemoRegister -Address $Address
    if ($readback -ne $Value) {
        throw ('Control register 0x{0:x2} readback 0x{1:x8}, expected 0x{2:x8}' -f $Address, $readback, $Value)
    }
    ('WRITE_CONFIRMED addr=0x{0:x2} value=0x{1:x8}' -f $Address, $Value)
}

function Write-DemoRegisterNoRead {
    param([byte]$Address, [uint32]$Value)
    [byte[]]$valueBytes = [BitConverter]::GetBytes($Value)
    [byte[]]$command = @(0x77, $Address, 0x00, 0x00) + $valueBytes
    $serial.Write($command, 0, $command.Length)
    Start-Sleep -Milliseconds 30
}

function Invoke-DemoMode {
    param([string]$Name, [uint32]$Control)
    Write-DemoRegister -Address 0x0d -Value 1
    # A read command during core reset waits forever for the core-clock ACK.
    # Keep the UART command stream write-only until core reset is released.
    Write-DemoRegisterNoRead -Address 0x00 -Value 0x00001000
    Start-Sleep -Milliseconds 100
    Write-DemoRegisterNoRead -Address 0x01 -Value ($Control -bor 2)
    Write-DemoRegisterNoRead -Address 0x01 -Value $Control
    Write-DemoRegisterNoRead -Address 0x0d -Value 0
    Write-DemoRegisterNoRead -Address 0x00 -Value 0x00001001
    Start-Sleep -Milliseconds 100
    if ((Read-DemoRegister -Address 0xff) -ne 0x20200729) {
        throw "UART version lost after reset in $Name"
    }
    if ((Read-DemoRegister -Address 0x00) -ne 0x00001001 -or
        (Read-DemoRegister -Address 0x01) -ne $Control) {
        throw "Control readback failed after reset in $Name"
    }

    $initialized = $false
    for ($attempt = 0; $attempt -lt 100; $attempt++) {
        $status80 = Read-DemoRegister -Address 0x80
        if ((($status80 -shr 12) -band 1) -eq 1) {
            $initialized = $true
            break
        }
        Start-Sleep -Milliseconds 100
    }
    if (-not $initialized) { throw "DDR init timeout in $Name" }

    $runStates = @{}
    $mainStates = @{}
    $readWords = @{}
    for ($sample = 0; $sample -lt $SamplesPerMode; $sample++) {
        $status80 = Read-DemoRegister -Address 0x80
        $status8b = Read-DemoRegister -Address 0x8b
        $recentRead = Read-DemoRegister -Address 0xe0
        $initDone = ($status80 -shr 12) -band 1
        $runBit = ($status80 -shr 1) -band 1
        $errorFlag = $status80 -band 1
        $errorCount = $status8b -band 0xff
        $mainState = ($status8b -shr 8) -band 0xf
        $runStates[$runBit] = $true
        $mainStates[$mainState] = $true
        $readWords[$recentRead] = $true
        if ($initDone -ne 1 -or $errorFlag -ne 0 -or $errorCount -ne 0) {
            throw ('DDR mismatch in {0}: sample={1} status80=0x{2:x8} status8b=0x{3:x8} recent_read=0x{4:x8}' -f $Name, $sample, $status80, $status8b, $recentRead)
        }
        Start-Sleep -Milliseconds 250
    }
    if ($mainStates.Count -lt 2) { throw "BIST main FSM did not advance in $Name" }
    ('VENDOR_DDR_MODE_PASS name={0} ctrl=0x{1:x8} samples={2} run_states={3} main_states={4} recent_read_values={5}' -f $Name, $Control, $SamplesPerMode, $runStates.Count, $mainStates.Count, $readWords.Count)
}

try {
    $serial.Open()
    $version = Read-DemoRegister -Address 0xff
    if ($version -ne 0x20200729) { throw ('Wrong demo version: 0x{0:x8}' -f $version) }
    $originalControl0 = Read-DemoRegister -Address 0x00
    if ($originalControl0 -ne 0x00001001) { throw ('Unexpected reset control: 0x{0:x8}' -f $originalControl0) }
    if ($ProbeOnly) {
        $originalControl1 = Read-DemoRegister -Address 0x01
        Write-DemoRegister -Address 0x01 -Value $originalControl1
        $postWriteVersion = Read-DemoRegister -Address 0xff
        if ($postWriteVersion -ne $version) { throw 'UART stopped responding after same-value write' }
        'VENDOR_DDR_UART_WRITE_PROBE_PASS'
    } else {
        # write-to-read mode, pattern data, fixed AWLEN/ARLEN of 0 or 15.
        Invoke-DemoMode -Name 'one_beat_pattern' -Control 0x00000e00
        Invoke-DemoMode -Name 'sixteen_beats_pattern' -Control 0x00000ef0
        # Restore the vendor demo's default continuous random-length mode.
        Write-DemoRegister -Address 0x0d -Value 1
        Write-DemoRegisterNoRead -Address 0x00 -Value 0x00001000
        Write-DemoRegisterNoRead -Address 0x01 -Value 0x00000001
        Write-DemoRegisterNoRead -Address 0x0d -Value 0
        Write-DemoRegisterNoRead -Address 0x00 -Value 0x00001001
        'VENDOR_DDR_MODES_PASS'
    }
} finally {
    if ($serial.IsOpen) { $serial.Close() }
    $serial.Dispose()
}
