param(
    [string]$PortName = 'COM7',
    [int]$BaudRate = 62500,
    [int]$Samples = 3
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
    $serial.Write($command, 0, $command.Length)
    [byte[]]$response = New-Object byte[] 4
    $received = 0
    while ($received -lt $response.Length) {
        $received += $serial.Read($response, $received, $response.Length - $received)
    }
    return [BitConverter]::ToUInt32($response, 0)
}

try {
    $serial.Open()
    $version = Read-DemoRegister -Address 0xff
    if ($version -ne 0x20200729) {
        throw ('Wrong UART/demo version: 0x{0:x8}' -f $version)
    }
    for ($sample = 0; $sample -lt $Samples; $sample++) {
        $status80 = Read-DemoRegister -Address 0x80
        $status8b = Read-DemoRegister -Address 0x8b
        $initDone = ($status80 -shr 12) -band 1
        $bistRun = ($status80 -shr 1) -band 1
        $errorFlag = $status80 -band 1
        $errorCount = $status8b -band 0xff
        ('VENDOR_DDR_UART sample={0} version=0x{1:x8} status80=0x{2:x8} status8b=0x{3:x8} init={4} bist_run={5} err_flag={6} err_count={7}' -f $sample, $version, $status80, $status8b, $initDone, $bistRun, $errorFlag, $errorCount)
        Start-Sleep -Milliseconds 500
    }
} finally {
    if ($serial.IsOpen) { $serial.Close() }
    $serial.Dispose()
}
