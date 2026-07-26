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
$config = Get-DefaultConfig
$start = [DateTime]'2026-07-22T10:00:00'
$high = [pscustomobject]@{ Source = 'AC'; SupplyType = 'HighPowerAC'; BatteryPercent = 80; AdapterLimitW = 155 }
$pd = [pscustomobject]@{ Source = 'AC'; SupplyType = 'LowPowerPD'; BatteryPercent = 80; AdapterLimitW = 70 }
$batteryLow = [pscustomobject]@{ Source = 'Battery'; SupplyType = 'Battery'; BatteryPercent = 49; AdapterLimitW = $null }
$unknown = [pscustomobject]@{ Source = 'AC'; SupplyType = 'UnknownAC'; BatteryPercent = 80; AdapterLimitW = $null }

if ($config.Version -ne 11 -or -not [bool]$config.SmartAutomationEnabled -or
    $config.SmartLoadEnterSamples -ne 3 -or $config.SmartExitSamples -ne 12 -or
    $config.SmartMinimumDwellSeconds -ne 30) {
    throw 'Smart automation defaults are incomplete.'
}

# High-power AC starts in Balance and needs three sustained load samples to enter Hyper.
$state = New-SmartAutomationState Balance
$state.LastSupplyType = 'HighPowerAC'
$state.LastTransitionAt = $start.AddMinutes(-5)
$loadDecisions = @()
foreach ($offset in @(0, 5, 10)) {
    $decision = Resolve-SmartAutomationDecision $config $high $state 55 '' $start.AddSeconds($offset)
    $state.CurrentProfile = $decision.Profile
    $state.CandidateProfile = $decision.CandidateProfile
    $state.CandidateSamples = $decision.CandidateSamples
    if ($decision.Transitioned) { $state.LastTransitionAt = $start.AddSeconds($offset) }
    $loadDecisions += $decision.Profile
}
if (($loadDecisions -join ',') -ne 'Balance,Balance,Hyper') { throw "High-power load promotion failed: $($loadDecisions -join ',')" }

# Hyper needs twelve low-load samples before returning to Balance.
$demotion = @()
foreach ($sample in 1..12) {
    $now = $start.AddSeconds(60 + ($sample * 5))
    $decision = Resolve-SmartAutomationDecision $config $high $state 5 '' $now
    $state.CurrentProfile = $decision.Profile
    $state.CandidateProfile = $decision.CandidateProfile
    $state.CandidateSamples = $decision.CandidateSamples
    if ($decision.Transitioned) { $state.LastTransitionAt = $now }
    $demotion += $decision.Profile
}
if ($demotion[10] -ne 'Hyper' -or $demotion[11] -ne 'Balance') { throw 'Hyper idle demotion hysteresis failed.' }

# A foreground performance app promotes faster, but still requires two samples.
$appState = New-SmartAutomationState Balance
$appState.LastSupplyType = 'HighPowerAC'
$appState.LastTransitionAt = $start.AddMinutes(-5)
$appFirst = Resolve-SmartAutomationDecision $config $high $appState 5 blender $start
$appState.CandidateProfile = $appFirst.CandidateProfile
$appState.CandidateSamples = $appFirst.CandidateSamples
$appSecond = Resolve-SmartAutomationDecision $config $high $appState 5 blender $start.AddSeconds(5)
if ($appFirst.Profile -ne 'Balance' -or $appSecond.Profile -ne 'Hyper') { throw 'Foreground performance-app promotion failed.' }

# PD/battery can reach Balance for interactive work, never Hyper, and <50% is an immediate Quiet boundary.
$portableState = New-SmartAutomationState Quiet
$portableState.LastSupplyType = 'LowPowerPD'
$portableState.LastTransitionAt = $start.AddMinutes(-5)
$portableFirst = Resolve-SmartAutomationDecision $config $pd $portableState 12 Codex $start
$portableState.CandidateProfile = $portableFirst.CandidateProfile
$portableState.CandidateSamples = $portableFirst.CandidateSamples
$portableSecond = Resolve-SmartAutomationDecision $config $pd $portableState 12 Codex $start.AddSeconds(5)
if ($portableFirst.Profile -ne 'Quiet' -or $portableSecond.Profile -ne 'Balance') { throw 'Portable productivity-app promotion failed.' }

$lowState = New-SmartAutomationState Balance
$lowState.LastSupplyType = 'Battery'
$lowState.LastTransitionAt = $start
$lowDecision = Resolve-SmartAutomationDecision $config $batteryLow $lowState 90 blender $start.AddSeconds(1)
if ($lowDecision.Profile -ne 'Quiet' -or -not $lowDecision.Transitioned) { throw 'Low-battery Quiet safety boundary failed.' }

$unplugState = New-SmartAutomationState Hyper
$unplugState.LastSupplyType = 'HighPowerAC'
$unplugState.LastTransitionAt = $start
$unplugDecision = Resolve-SmartAutomationDecision $config $pd $unplugState 90 blender $start.AddSeconds(1)
if ($unplugDecision.Profile -eq 'Hyper') { throw 'Portable power was allowed to retain automatic Hyper.' }

$unknownState = New-SmartAutomationState Hyper
$unknownState.LastSupplyType = 'HighPowerAC'
$unknownDecision = Resolve-SmartAutomationDecision $config $unknown $unknownState 90 blender $start
if ($unknownDecision.Profile -ne 'Quiet') { throw 'Unknown power source did not fail safe to Quiet.' }

if ((Get-DesiredProfile Hyper $pd $config $portableState) -ne 'Hyper' -or
    (Get-DesiredProfile Quiet $high $config $portableState) -ne 'Quiet') {
    throw 'Manual profile locks no longer override Smart Auto.'
}

# High-power idle Balance must not dim the panel, while portable Balance keeps
# its configured brightness behavior.
$script:BrightnessWrites = New-Object Collections.Generic.List[int]
function Set-InternalBrightness([int]$Percent) { $script:BrightnessWrites.Add($Percent); return 1 }
function Get-InternalBrightness { return 77 }
function Save-AppState([object]$State) { }
$brightnessState = [pscustomobject]@{ CapturedBrightness = 77 }
Apply-ManagedBrightness Balance $config $brightnessState $high
if (($script:BrightnessWrites -join ',') -ne '77' -or $null -ne $brightnessState.CapturedBrightness) {
    throw 'High-power Balance did not preserve the user brightness.'
}
$brightnessState.CapturedBrightness = $null
Apply-ManagedBrightness Balance $config $brightnessState $pd
if (($script:BrightnessWrites -join ',') -ne '77,60' -or $brightnessState.CapturedBrightness -ne 77) {
    throw 'Portable Balance no longer applies its configured brightness.'
}

$nativeMethods = [OpenSynapseNative.AutomationTelemetry].GetMethods().Name
if ('SampleCpuPercent' -notin $nativeMethods -or 'GetForegroundProcessId' -notin $nativeMethods) {
    throw 'Low-overhead native telemetry methods are missing.'
}
$null = [OpenSynapseNative.AutomationTelemetry]::SampleCpuPercent()
Start-Sleep -Milliseconds 50
$nativeCpuSample = [OpenSynapseNative.AutomationTelemetry]::SampleCpuPercent()
if ($nativeCpuSample -lt 0 -or $nativeCpuSample -gt 100) { throw "Native CPU telemetry returned an invalid sample: $nativeCpuSample" }
$foregroundProcessId = [OpenSynapseNative.AutomationTelemetry]::GetForegroundProcessId()
if ($foregroundProcessId -lt 0) { throw "Foreground process telemetry returned an invalid PID: $foregroundProcessId" }
$source = Get-Content -Raw -LiteralPath $mainScript
$telemetryStart = $source.IndexOf('function Get-SmartAutomationTelemetry', [StringComparison]::Ordinal)
$telemetryEnd = $source.IndexOf('function Test-SmartProcessMatch', $telemetryStart, [StringComparison]::Ordinal)
$telemetrySource = $source.Substring($telemetryStart, $telemetryEnd - $telemetryStart)
if ($telemetrySource -match 'nvidia-smi|Get-Counter|Get-CimInstance') {
    throw 'Smart telemetry contains a battery-expensive polling mechanism.'
}

$result = [pscustomobject]@{
    Result = 'PASS'
    HighPowerIdleProfile = 'Balance'
    HyperLoadEnterSamples = 3
    HyperIdleExitSamples = 12
    AppEnterSamples = 2
    PortableHyperBlocked = $true
    LowBatteryQuietBoundary = 50
    HighPowerBrightnessPreserved = $true
    NativeCpuTelemetry = $true
    NativeCpuSample = [Math]::Round($nativeCpuSample, 1)
    NvidiaPollingInDecisionLoop = $false
    ChangedSystemSettings = $false
    CompletedAt = (Get-Date).ToString('o')
}
if ($ResultPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath), ($result | ConvertTo-Json), [Text.UTF8Encoding]::new($false)) }
$result | Format-List
