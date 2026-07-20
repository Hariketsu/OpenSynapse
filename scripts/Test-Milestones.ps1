[CmdletBinding()]
param([switch]$TestMouseWrites)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$agent = Join-Path $root 'src\OpenSynapse.Agent\bin\Debug\net10.0-windows\OpenSynapse.Agent.dll'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this smoke test from an elevated PowerShell terminal.'
}

dotnet build (Join-Path $root 'OpenSynapse.sln')
if ($LASTEXITCODE -ne 0) { throw 'Build failed.' }

function Invoke-Agent {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    $json = & dotnet $agent @Arguments
    if ($LASTEXITCODE -ne 0) { throw ($json -join [Environment]::NewLine) }
    return ($json -join [Environment]::NewLine) | ConvertFrom-Json
}

function Invoke-AgentPipe {
    param([string]$Operation, [int]$ConnectTimeout = 1000)
    $pipe = [IO.Pipes.NamedPipeClientStream]::new('.', 'OpenSynapse.Agent', [IO.Pipes.PipeDirection]::InOut)
    try {
        $pipe.Connect($ConnectTimeout)
        $writer = [IO.StreamWriter]::new($pipe)
        $reader = [IO.StreamReader]::new($pipe)
        $writer.AutoFlush = $true
        $writer.WriteLine((@{ operation = $Operation } | ConvertTo-Json -Compress))
        $read = $reader.ReadLineAsync()
        if (-not $read.Wait(5000)) { throw 'OpenSynapse.Agent pipe response timed out.' }
        if ($null -eq $read.Result) { throw 'OpenSynapse.Agent closed the pipe without a response.' }
        return $read.Result | ConvertFrom-Json
    }
    finally { $pipe.Dispose() }
}

$originalText = & powercfg /getactivescheme
$originalGuid = [regex]::Match(($originalText | Out-String), '[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}').Value
if (-not $originalGuid) { throw 'Cannot read the original Windows power plan.' }

function Assert-Restored {
    $restoredText = & powercfg /getactivescheme
    $restoredGuid = [regex]::Match(($restoredText | Out-String), '[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}').Value
    if (-not [string]::Equals($originalGuid, $restoredGuid, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Power plan rollback failed: expected $originalGuid, got $restoredGuid."
    }
    $state = Get-Content (Join-Path $env:LOCALAPPDATA 'OpenSynapse\state.json') -Raw | ConvertFrom-Json
    if ($null -ne $state.OriginalPowerPlan) { throw 'Restored power plan snapshot was not cleared.' }
}

try {
    $status = Invoke-Agent status
    if (-not $status.Success) { throw $status.Message }

    $performance = Invoke-Agent apply Performance
    if (-not $performance.Success -or $performance.Status.ActiveMode -ne 'Performance') {
        throw 'Performance mode verification failed.'
    }

    if ($status.Status.BatteryPercent -ge 50) {
        $balanced = Invoke-Agent apply Balanced
        if (-not $balanced.Success -or $balanced.Status.ActiveMode -ne 'Balanced') {
            throw 'Balanced mode verification failed.'
        }
    }
    else {
        Write-Warning 'Balanced mode verification skipped because battery is below 50% or unavailable.'
    }

    $quiet = Invoke-Agent apply Quiet
    if (-not $quiet.Success -or $quiet.Status.ActiveMode -ne 'Quiet') {
        throw 'Quiet mode verification failed.'
    }

    if ($TestMouseWrites) {
        $mouse = $quiet.Status.RazerDevices | Select-Object -First 1
        if ($null -eq $mouse -or $null -eq $mouse.DpiX -or $null -eq $mouse.PollingRate) {
            throw 'A readable DeathAdder V3 Pro is required for mouse write verification.'
        }
        $dpi = Invoke-Agent mouse-dpi ([string]$mouse.DpiX)
        $polling = Invoke-Agent mouse-polling ([string]$mouse.PollingRate)
        if (-not $dpi.Success -or -not $polling.Success) { throw 'DeathAdder write verification failed.' }
    }
}
finally {
    $restore = Invoke-Agent restore
    Assert-Restored
}

$server = $null
try {
    $server = Start-Process -FilePath dotnet -ArgumentList ('"{0}" serve' -f $agent) -WindowStyle Hidden -PassThru
    $pipeStatus = $null
    for ($attempt = 0; $attempt -lt 10 -and $null -eq $pipeStatus; $attempt++) {
        try { $pipeStatus = Invoke-AgentPipe Status }
        catch {
            if ($server.HasExited) { throw 'OpenSynapse.Agent exited before accepting a pipe connection.' }
            Start-Sleep -Milliseconds 500
        }
    }
    if ($null -eq $pipeStatus -or -not $pipeStatus.Success) { throw 'Named-pipe status verification failed.' }
    $shutdown = Invoke-AgentPipe Shutdown 3000
    if (-not $shutdown.Success) { throw $shutdown.Message }
    if (-not $server.WaitForExit(5000)) { throw 'OpenSynapse.Agent did not exit after Shutdown.' }
    Assert-Restored
}
finally {
    if ($null -ne $server -and -not $server.HasExited) {
        try { $restore = Invoke-Agent restore } catch { }
        Stop-Process -Id $server.Id -Force
    }
}

Write-Host 'M0-M3 Windows smoke test passed.' -ForegroundColor Green
