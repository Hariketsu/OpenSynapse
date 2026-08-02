#requires -Version 5.1

[CmdletBinding()]
param([string]$ResultPath = '')

$ErrorActionPreference = 'Stop'
trap {
    $failure = [pscustomobject]@{ Result = 'FAIL'; Message = $_.Exception.Message; CompletedAt = (Get-Date).ToString('o') }
    if ($ResultPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath), ($failure | ConvertTo-Json), [Text.UTF8Encoding]::new($false)) }
    Write-Error $_
    break
}

$mainScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'OpenSynapse.ps1'
. $mainScript -Mode SelfTest
$source = Get-Content -Raw -LiteralPath $mainScript
$config = Get-DefaultConfig
if ($config.Version -ne 14 -or -not [bool]$config.BatteryHighDrainAlertsEnabled -or
    $config.BatteryHighDrainSampleSeconds -ne 30 -or $config.BatteryHighDrainCpuPercent -ne 15 -or
    $config.BatteryHighDrainMinimumSamples -ne 2 -or $config.BatteryHighDrainMinimumDischargeW -ne 14 -or
    $config.BatteryHighDrainCooldownMinutes -ne 30) {
    throw 'Battery high-drain alert defaults are incorrect.'
}

$battery = [pscustomobject]@{
    Source = 'Battery'
    SupplyType = 'Battery'
    BatteryDischargeAverage10mW = 18.5
    BatteryDischargeEmaW = 19.0
    BatteryDischargeW = 20.0
}
$samples = @(
    [pscustomobject]@{ ProcessName = 'Thunder'; CpuPercentOneCore = 27.5; WorkingSetBytes = 300MB; ProcessCount = 2 },
    [pscustomobject]@{ ProcessName = 'ChatGPT'; CpuPercentOneCore = 17.0; WorkingSetBytes = 500MB; ProcessCount = 1 },
    [pscustomobject]@{ ProcessName = 'System'; CpuPercentOneCore = 95.0; WorkingSetBytes = 1MB; ProcessCount = 1 },
    [pscustomobject]@{ ProcessName = 'explorer'; CpuPercentOneCore = 2.0; WorkingSetBytes = 100MB; ProcessCount = 1 }
)
$start = [DateTime]'2026-08-02T10:00:00'
$state = New-SmartAutomationState Quiet
$first = Update-BatteryHighDrainState $config $battery $state $samples $start -ForceSample
if (-not $first.Sampled -or $first.Detected -or $first.ShouldNotify) { throw 'A single CPU sample incorrectly triggered an alert.' }
$second = Update-BatteryHighDrainState $config $battery $state $samples $start.AddSeconds(30) -ForceSample
if (-not $second.Detected -or -not $second.ShouldNotify -or $second.Confidence -ne 'High' -or
    @($second.Processes).Count -ne 2 -or 'System' -in @($second.Processes.ProcessName)) {
    throw 'Sustained high-CPU processes were not detected or ignored safely.'
}
$cooldown = Update-BatteryHighDrainState $config $battery $state $samples $start.AddSeconds(60) -ForceSample
if (-not $cooldown.Detected -or $cooldown.ShouldNotify) { throw 'Alert cooldown did not suppress a repeated notification.' }
$afterCooldown = Update-BatteryHighDrainState $config $battery $state $samples $start.AddMinutes(31) -ForceSample
if (-not $afterCooldown.ShouldNotify -or $state.BatteryHighDrainAlertCount -ne 2) { throw 'Alert did not resume after the configured cooldown.' }

$lowDrainState = New-SmartAutomationState Quiet
$lowDrain = [pscustomobject]@{
    Source = 'Battery'; SupplyType = 'Battery'; BatteryDischargeAverage10mW = 9.0
    BatteryDischargeEmaW = 10.0; BatteryDischargeW = 11.0
}
$null = Update-BatteryHighDrainState $config $lowDrain $lowDrainState $samples $start -ForceSample
$lowResult = Update-BatteryHighDrainState $config $lowDrain $lowDrainState $samples $start.AddSeconds(30) -ForceSample
if ($lowResult.Detected -or $lowResult.ShouldNotify) { throw 'CPU activity below the battery discharge gate produced a false positive.' }

$ac = [pscustomobject]@{ Source = 'AC'; SupplyType = 'HighPowerAC' }
$reset = Update-BatteryHighDrainState $config $ac $state $samples $start.AddMinutes(32) -ForceSample
if ($reset.Detected -or @($state.BatteryHighDrainProcesses).Count -ne 0 -or @($state.BatteryHighDrainSampleCounts.Keys).Count -ne 0) {
    throw 'Battery high-drain state did not reset when external power was connected.'
}

$idleTelemetry = New-SmartAutomationState Quiet
$activeTelemetry = New-SmartAutomationState Balance
$activeTelemetry.LastCpuPercent = 20
if ((Resolve-MonitorIntervalMilliseconds $battery $idleTelemetry Quiet) -ne 15000 -or
    (Resolve-MonitorIntervalMilliseconds $battery $idleTelemetry Auto) -ne 15000 -or
    (Resolve-MonitorIntervalMilliseconds $battery $activeTelemetry Auto) -ne 10000 -or
    (Resolve-MonitorIntervalMilliseconds $ac $activeTelemetry Auto) -ne 5000) {
    throw 'Dynamic battery monitor cadence did not resolve to 10/15 seconds and 5 seconds on AC.'
}

$functionStart = $source.IndexOf('function Update-BatteryHighDrainState', [StringComparison]::Ordinal)
$functionEnd = $source.IndexOf('function Get-SmartAutomationTelemetry', $functionStart, [StringComparison]::Ordinal)
if ($functionStart -lt 0 -or $functionEnd -le $functionStart) { throw 'Battery high-drain function definition is missing.' }
$functionBody = $source.Substring($functionStart, $functionEnd - $functionStart)
if ($functionBody -match '\bStop-Process\b') { throw 'Battery high-drain notification must never stop a process.' }
foreach ($required in @(
    'ProcessCpuSampler]::Sample()',
    'BatteryHighDrainCheck',
    'OpenSynapse battery usage',
    'nothing was stopped',
    'fell back to Eco 60 Hz',
    'ApplyInternalFixedRefresh(60)',
    '$script:MonitorBatteryIdleIntervalMs = 15000'
)) {
    if ($source.IndexOf($required, [StringComparison]::Ordinal) -lt 0) { throw "Missing battery optimization definition: $required" }
}

$nativeMethods = [OpenSynapseNative.ProcessCpuSampler].GetMethods().Name
if ('Sample' -notin $nativeMethods -or 'Reset' -notin $nativeMethods) { throw 'Native process CPU sampler is incomplete.' }

$result = [pscustomobject]@{
    Result = 'PASS'
    ConfigVersion = $config.Version
    TelemetrySchemaVersion = $script:TelemetrySchemaVersion
    SustainedSamples = $config.BatteryHighDrainMinimumSamples
    CpuThresholdOneCorePercent = $config.BatteryHighDrainCpuPercent
    MinimumDischargeW = $config.BatteryHighDrainMinimumDischargeW
    CooldownMinutes = $config.BatteryHighDrainCooldownMinutes
    BatteryMonitorIntervalsSeconds = @(10, 15)
    AcMonitorIntervalSeconds = 5
    DynamicRefreshFallback = 'Eco60'
    StopsProcesses = $false
    ChangedSystemSettings = $false
    CompletedAt = (Get-Date).ToString('o')
}
if ($ResultPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath), ($result | ConvertTo-Json), [Text.UTF8Encoding]::new($false)) }
$result | Format-List
