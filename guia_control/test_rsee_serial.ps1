# Offline protocol regression checks. No real serial port is opened.
$ErrorActionPreference = 'Stop'
$controlScript = Join-Path $PSScriptRoot 'rsee_serial.ps1'
$testLog = Join-Path ([System.IO.Path]::GetTempPath()) ('rsee_test_' + [guid]::NewGuid() + '.json')

function Assert-True($Condition, [string]$Message) {
    if (-not $Condition) { throw "FAILED: $Message" }
}

function New-FakeSerial {
    $fake = [pscustomobject]@{
        PortName = ''; BaudRate = 0; DataBits = 0; Parity = $null
        StopBits = $null; Handshake = $null; DtrEnable = $false
        RtsEnable = $false; ReadTimeout = 0; WriteTimeout = 0; Encoding = $null
        Brightness = 200; Buffer = ''; Opened = $false; Disposed = $false
        FailRead = $false; BadAck = $false; Mismatch = $false
        ReadOverride = $null
        Commands = [System.Collections.Generic.List[string]]::new()
    }
    $fake | Add-Member ScriptMethod Open { $this.Opened = $true }
    $fake | Add-Member ScriptMethod Dispose { $this.Disposed = $true }
    $fake | Add-Member ScriptMethod Write {
        param([string]$Command)
        $this.Commands.Add($Command)
        if ($Command -cmatch '^S([AB])#$') {
            if ($this.FailRead) { $this.Buffer = ''; return }
            if ($null -ne $this.ReadOverride) { $this.Buffer = $this.ReadOverride; return }
            $this.Buffer = '{0}{1:D4}' -f $Matches[1].ToLowerInvariant(), $this.Brightness
        } elseif ($Command -cmatch '^S([AB])([0-9]{4})#$') {
            $channelLetter = $Matches[1]
            if (-not $this.Mismatch) { $this.Brightness = [int]$Matches[2] }
            $this.Buffer = if ($this.BadAck) { '?' } else { $channelLetter }
        } elseif ($Command -cmatch '^S([HL])#$') {
            $this.Buffer = if ($this.BadAck) { '?' } else { $Matches[1] }
        } else { throw "Unexpected command: $Command" }
    }
    $fake | Add-Member ScriptMethod ReadChar {
        if ($this.Buffer.Length -eq 0) { throw [TimeoutException]::new('Simulated timeout') }
        $character = [int][char]$this.Buffer[0]
        $this.Buffer = $this.Buffer.Substring(1)
        return $character
    }
    return $fake
}

# Override only the constructor used by the CLI; all commands go to a fake device.
function New-Object {
    param([string]$TypeName)
    if ($TypeName -ne 'System.IO.Ports.SerialPort') { throw "Unexpected constructor: $TypeName" }
    return $global:RseeTestFakeSerial
}

function Invoke-Case([hashtable]$Arguments) {
    $global:LASTEXITCODE = 0
    $raw = & $controlScript -Port COM8 -Log $testLog @Arguments
    return ($raw -join [Environment]::NewLine) | ConvertFrom-Json
}

try {
    $global:RseeTestFakeSerial = New-FakeSerial
    $r = Invoke-Case @{ Action = 'read' }
    Assert-True ($r.success -and $r.final_brightness -eq 200) 'Read CH1'
    Assert-True (($global:RseeTestFakeSerial.Commands -join ',') -ceq 'SA#') 'Read sends only SA#'
    Assert-True ($global:RseeTestFakeSerial.BaudRate -eq 19200 -and $global:RseeTestFakeSerial.DataBits -eq 8 -and $global:RseeTestFakeSerial.Disposed) 'Connection settings and disposal'

    foreach ($channel in @('A', 'B')) {
        $global:RseeTestFakeSerial = New-FakeSerial
        $r = Invoke-Case @{ Action = 'set'; Channel = $channel; Value = 125 }
        Assert-True ($r.success -and $r.final_brightness -eq 125) "Set channel $channel"
        Assert-True (($global:RseeTestFakeSerial.Commands -join ',') -ceq "S${channel}#,S${channel}0125#,S${channel}#") 'Write and readback frames'
    }
    foreach ($boundary in @(0, 255)) {
        $global:RseeTestFakeSerial = New-FakeSerial
        $r = Invoke-Case @{ Action = 'set'; Value = $boundary }
        Assert-True ($r.success -and $r.final_brightness -eq $boundary) "Brightness boundary $boundary"
    }
    foreach ($mode in @('high', 'low')) {
        $global:RseeTestFakeSerial = New-FakeSerial
        $r = Invoke-Case @{ Action = $mode }
        $expected = if ($mode -eq 'high') { 'SH#' } else { 'SL#' }
        Assert-True ($r.success -and $r.mode_acknowledged -and $null -eq $r.channel) "Mode $mode ACK"
        Assert-True (($global:RseeTestFakeSerial.Commands -join ',') -ceq $expected) 'Mode does not depend on channel reading'
    }
    $global:RseeTestFakeSerial = New-FakeSerial
    $r = Invoke-Case @{ Action = 'ramp'; Value = 175; Step = 10; IntervalMs = 50 }
    Assert-True ($r.success -and $r.final_brightness -eq 175) 'Descending ramp reaches target'
    Assert-True (($r.steps.verified -join ',') -eq '190,180,175') 'Ramp clamps final step'

    $global:RseeTestFakeSerial = New-FakeSerial
    $r = Invoke-Case @{ Action = 'ramp'; Value = 225; Step = 10; IntervalMs = 50 }
    Assert-True ($r.success -and ($r.steps.verified -join ',') -eq '210,220,225') 'Ascending ramp'

    $global:RseeTestFakeSerial = New-FakeSerial
    $r = Invoke-Case @{ Action = 'ramp'; Value = 200; IntervalMs = 50 }
    Assert-True ($r.success -and $global:RseeTestFakeSerial.Commands.Count -eq 1) 'No write when ramp is already at target'

    $global:RseeTestFakeSerial = New-FakeSerial
    $r = Invoke-Case @{ Action = 'demo'; Minimum = 190; Maximum = 210; Step = 10; IntervalMs = 50 }
    Assert-True ($r.success -and $r.final_brightness -eq 200) 'Demo restores start'
    Assert-True (($r.steps.verified -join ',') -eq '210,200,190,200') 'Demo sequence'

    $global:RseeTestFakeSerial = New-FakeSerial
    $global:RseeTestFakeSerial.FailRead = $true
    $r = Invoke-Case @{ Action = 'set'; Channel = 'B'; Value = 100 }
    Assert-True (-not $r.success -and $LASTEXITCODE -eq 1) 'Timeout fails'
    Assert-True (($global:RseeTestFakeSerial.Commands -join ',') -ceq 'SB#') 'No writes after failed initial read'

    foreach ($invalidResponse in @('b0200', 'a9999', 'aX200')) {
        $global:RseeTestFakeSerial = New-FakeSerial
        $global:RseeTestFakeSerial.ReadOverride = $invalidResponse
        $r = Invoke-Case @{ Action = 'set'; Value = 100 }
        Assert-True (-not $r.success -and $global:RseeTestFakeSerial.Commands.Count -eq 1) 'Invalid initial response blocks writes'
    }

    $global:RseeTestFakeSerial = New-FakeSerial
    $global:RseeTestFakeSerial.BadAck = $true
    $r = Invoke-Case @{ Action = 'ramp'; Value = 150; IntervalMs = 50 }
    Assert-True (-not $r.success -and $global:RseeTestFakeSerial.Commands.Count -eq 2) 'Bad ACK stops ramp immediately'
    Assert-True ($null -eq $r.final_brightness) 'Failure does not claim final brightness'

    $global:RseeTestFakeSerial = New-FakeSerial
    $global:RseeTestFakeSerial.Mismatch = $true
    $r = Invoke-Case @{ Action = 'set'; Value = 125 }
    Assert-True (-not $r.success -and $global:RseeTestFakeSerial.Commands.Count -eq 3) 'Readback mismatch fails without retries'

    $global:RseeTestFakeSerial = New-FakeSerial
    $global:RseeTestFakeSerial.BadAck = $true
    $r = Invoke-Case @{ Action = 'low' }
    Assert-True (-not $r.success -and $global:RseeTestFakeSerial.Commands.Count -eq 1) 'Invalid mode ACK fails'

    foreach ($invalid in @(
        @{ Action = 'set' },
        @{ Action = 'set'; Value = 256 },
        @{ Action = 'high'; Channel = 'A' },
        @{ Action = 'read'; Value = 10 },
        @{ Action = 'demo'; Minimum = 220; Maximum = 100 },
        @{ Action = 'read'; Step = 5 }
    )) {
        $global:RseeTestFakeSerial = New-FakeSerial
        $rejected = $false
        try { $null = Invoke-Case $invalid } catch { $rejected = $true }
        Assert-True ($rejected -and -not $global:RseeTestFakeSerial.Opened) 'Reject invalid arguments before opening port'
    }
    Write-Output 'PASS: read, CH1/CH2 writes, H/L ACKs, ramp, demo, failures and argument validation (offline).'
} finally {
    if (Test-Path -LiteralPath $testLog) { Remove-Item -LiteralPath $testLog }
    Remove-Variable -Name RseeTestFakeSerial -Scope Global -ErrorAction SilentlyContinue
}
