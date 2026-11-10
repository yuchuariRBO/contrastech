<#
.SYNOPSIS
Read/write RSEE brightness or set High/Low trigger mode over RS232.
.DESCRIPTION
Windows PowerShell 5.1, no external packages. Protocol: manual V2022, page 5.
Channel A = CH1; B = CH2. High/Low apply to the controller, not a channel.
Read and set require a responsive channel. Modes require their own H/L ACK.
Ramp leaves the target applied. Demo returns to the initial brightness on success.
Failures stop without retries or automatic restoration.
.EXAMPLE
.\rsee_serial.ps1 -Port COM8 -Action high
.EXAMPLE
.\rsee_serial.ps1 -Port COM8 -Action set -Channel A -Value 200
.EXAMPLE
.\rsee_serial.ps1 -Port COM8 -Action ramp -Value 100 -Step 10 -IntervalMs 200
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^COM[1-9][0-9]*$')]
    [string]$Port,
    [ValidateSet('read', 'set', 'high', 'low', 'ramp', 'demo')]
    [string]$Action = 'read',
    [ValidateSet('A', 'B')]
    [string]$Channel = 'A',
    [ValidateRange(0, 255)]
    [int]$Value,
    [ValidateRange(1, 255)]
    [int]$Step = 10,
    [ValidateRange(50, 10000)]
    [int]$IntervalMs = 300,
    [ValidateRange(0, 255)]
    [int]$Minimum = 150,
    [ValidateRange(0, 255)]
    [int]$Maximum = 250,
    [ValidateRange(100, 10000)]
    [int]$TimeoutMs = 1500,
    [string]$Log
)

$ErrorActionPreference = 'Stop'
if ($Action -in @('set', 'ramp') -and -not $PSBoundParameters.ContainsKey('Value')) {
    throw 'Use -Value 0..255 with -Action set or ramp.'
}
if ($Action -notin @('set', 'ramp') -and $PSBoundParameters.ContainsKey('Value')) {
    throw '-Value is only valid with -Action set or ramp.'
}
if ($Action -in @('high', 'low') -and $PSBoundParameters.ContainsKey('Channel')) {
    throw 'High/Low are controller-wide commands; omit -Channel.'
}
if ($Action -eq 'demo' -and $Minimum -ge $Maximum) {
    throw 'Demo requires Minimum < Maximum.'
}
if ($PSBoundParameters.ContainsKey('Step') -and $Action -notin @('ramp', 'demo')) {
    throw '-Step is only valid with ramp or demo.'
}
if ($PSBoundParameters.ContainsKey('IntervalMs') -and $Action -notin @('ramp', 'demo')) {
    throw '-IntervalMs is only valid with ramp or demo.'
}
if (($PSBoundParameters.ContainsKey('Minimum') -or $PSBoundParameters.ContainsKey('Maximum')) -and $Action -ne 'demo') {
    throw '-Minimum/-Maximum are only valid with demo.'
}

$serial = New-Object System.IO.Ports.SerialPort
$serial.PortName = $Port
$serial.BaudRate = 19200
$serial.DataBits = 8
$serial.Parity = [System.IO.Ports.Parity]::None
$serial.StopBits = [System.IO.Ports.StopBits]::One
$serial.Handshake = [System.IO.Ports.Handshake]::None
$serial.DtrEnable = $false
$serial.RtsEnable = $false
$serial.ReadTimeout = $TimeoutMs
$serial.WriteTimeout = $TimeoutMs
$serial.Encoding = [System.Text.Encoding]::ASCII

$result = [ordered]@{
    timestamp = [DateTimeOffset]::Now.ToString('o')
    port = $Port
    settings = '19200 8N1, no flow control'
    channel = $Channel
    action = $Action
    exchanges = [System.Collections.Generic.List[object]]::new()
    success = $false
}
if ($Action -in @('high', 'low')) { $result.channel = $null }

function Invoke-Exchange([string]$Command, [int]$Count) {
    $exchange = [ordered]@{ tx = $Command; rx = '' }
    $result.exchanges.Add($exchange)
    $serial.Write($Command)
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    while ($exchange.rx.Length -lt $Count) {
        $remaining = $TimeoutMs - [int]$timer.ElapsedMilliseconds
        if ($remaining -le 0) { throw "Response deadline exceeded for $Command" }
        $serial.ReadTimeout = $remaining
        $exchange.rx += [char]$serial.ReadChar()
    }
    return $exchange.rx
}

function Get-Brightness {
    $response = Invoke-Exchange "S${Channel}#" 5
    $prefix = $Channel.ToLowerInvariant()
    if ($response -cnotmatch "^${prefix}[0-9]{4}$") {
        throw "Unexpected response: $response"
    }
    $brightness = [int]$response.Substring(1)
    if ($brightness -gt 255) { throw "Brightness out of range: $brightness" }
    return $brightness
}

function Set-Brightness([int]$Target) {
    $ack = Invoke-Exchange ('S{0}{1:D4}#' -f $Channel, $Target) 1
    if ($ack -cne $Channel) { throw "Unexpected write acknowledgement: $ack" }
    $actual = Get-Brightness
    if ($actual -ne $Target) {
        throw "Readback mismatch: requested $Target, received $actual"
    }
    $result.steps.Add([ordered]@{
        timestamp = [DateTimeOffset]::Now.ToString('o')
        requested = $Target
        verified = $actual
    })
    $result.last_verified_brightness = $actual
    return $actual
}

function Move-Brightness([int]$Current, [int]$Target) {
    while ($Current -ne $Target) {
        $distance = [Math]::Min($Step, [Math]::Abs($Target - $Current))
        if ($Current -lt $Target) { $next = $Current + $distance }
        else { $next = $Current - $distance }
        $Current = Set-Brightness $next
        Start-Sleep -Milliseconds $IntervalMs
    }
    return $Current
}

try {
    $serial.Open()
    if ($Action -in @('high', 'low')) {
        $mode = if ($Action -eq 'high') { 'H' } else { 'L' }
        $result.requested_mode = $Action
        $ack = Invoke-Exchange "S${mode}#" 1
        if ($ack -cne $mode) { throw "Unexpected mode acknowledgement: $ack" }
        $result.mode_acknowledged = $true
    } else {
        $result.steps = [System.Collections.Generic.List[object]]::new()
        $result.initial_brightness = Get-Brightness
        $result.last_verified_brightness = $result.initial_brightness
        switch ($Action) {
            'read' { $result.final_brightness = $result.initial_brightness }
            'set' {
                $result.requested_brightness = $Value
                $result.final_brightness = Set-Brightness $Value
            }
            'ramp' {
                $result.requested_brightness = $Value
                $result.step = $Step
                $result.interval_ms = $IntervalMs
                $result.final_brightness = Move-Brightness $result.initial_brightness $Value
            }
            'demo' {
                $result.minimum = $Minimum
                $result.maximum = $Maximum
                $result.step = $Step
                $result.interval_ms = $IntervalMs
                $current = Move-Brightness $result.initial_brightness $Maximum
                $current = Move-Brightness $current $Minimum
                $result.final_brightness = Move-Brightness $current $result.initial_brightness
            }
        }
    }
    $result.success = $true
} catch {
    $result.error = $_.Exception.Message
    $result.note = 'Stopped without retries. Read device before another write.'
} finally {
    $serial.Dispose()
}
if (-not $Log) {
    $Log = Join-Path $PSScriptRoot ('operation_serial_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff') + '.json')
}
$json = $result | ConvertTo-Json -Depth 6
$json | Set-Content -LiteralPath $Log -Encoding UTF8
$json
if (-not $result.success) { exit 1 }
