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
$start = [DateTime]'2026-07-24T10:00:00'
$high = [pscustomobject]@{ Source = 'AC'; SupplyType = 'HighPowerAC'; BatteryPercent = 80; AdapterLimitW = 160 }
$portable = [pscustomobject]@{ Source = 'Battery'; SupplyType = 'Battery'; BatteryPercent = 80; AdapterLimitW = $null }

# Shell and lock-screen windows can cover a monitor but are not application
# workload evidence.
foreach ($processName in @('explorer', 'LockApp', 'ShellExperienceHost')) {
    $state = New-SmartAutomationState Balance
    $state.LastSupplyType = 'HighPowerAC'
    $state.LastTransitionAt = $start.AddMinutes(-5)
    foreach ($sample in 1..$config.SmartAppEnterSamples) {
        $decision = Resolve-SmartAutomationDecision $config $high $state 18 $processName $start.AddSeconds($sample * 5) 2 $true @()
        $state.CurrentProfile = $decision.Profile
        $state.CandidateProfile = $decision.CandidateProfile
        $state.CandidateSamples = $decision.CandidateSamples
    }
    if ($decision.Profile -ne 'Balance' -or $decision.TriggerKind -eq 'App') {
        throw "$processName fullscreen shell signal promoted Smart Auto."
    }
}

# An unknown fullscreen app needs CPU/GPU corroboration, while a known explicit
# app rule remains authoritative.
$state = New-SmartAutomationState Balance
$state.LastSupplyType = 'HighPowerAC'
$state.LastTransitionAt = $start.AddMinutes(-5)
$first = Resolve-SmartAutomationDecision $config $high $state 2 unknown-game $start 2 $true @()
$state.CandidateProfile = $first.CandidateProfile
$state.CandidateSamples = $first.CandidateSamples
$second = Resolve-SmartAutomationDecision $config $high $state 2 unknown-game $start.AddSeconds(5) 2 $true @()
if ($first.Profile -ne 'Balance' -or $second.Profile -ne 'Balance') {
    throw 'Uncorroborated generic fullscreen signal promoted Smart Auto.'
}

$state = New-SmartAutomationState Balance
$state.LastSupplyType = 'HighPowerAC'
$state.LastTransitionAt = $start.AddMinutes(-5)
$first = Resolve-SmartAutomationDecision $config $high $state 2 unknown-game $start 20 $true @()
$state.CandidateProfile = $first.CandidateProfile
$state.CandidateSamples = $first.CandidateSamples
$second = Resolve-SmartAutomationDecision $config $high $state 2 unknown-game $start.AddSeconds(5) 20 $true @()
if ($second.Profile -ne 'Hyper' -or $second.TriggerKind -ne 'App') {
    throw 'Corroborated fullscreen workload did not promote Smart Auto.'
}

# Session lock is a hard, immediate boundary even if stale load/app signals are
# still high at the moment Windows locks.
$state = New-SmartAutomationState Hyper
$state.LastSupplyType = 'HighPowerAC'
$state.LastTransitionAt = $start
$locked = Resolve-SmartAutomationDecision $config $high $state 95 blender $start.AddSeconds(1) 95 $true @() $true
if ($locked.Profile -ne 'Balance' -or -not $locked.Transitioned -or $locked.Reason -notmatch 'locked') {
    throw 'High-power session lock did not immediately leave Hyper.'
}
$state = New-SmartAutomationState Balance
$state.LastSupplyType = 'Battery'
$state.LastTransitionAt = $start
$lockedPortable = Resolve-SmartAutomationDecision $config $portable $state 95 blender $start.AddSeconds(1) 95 $true @() $true
if ($lockedPortable.Profile -ne 'Quiet' -or -not $lockedPortable.Transitioned) {
    throw 'Portable session lock did not immediately enter Quiet.'
}

$nativeProperties = [OpenSynapseNative.PowerChangeSignal].GetProperties().Name
foreach ($property in @('EventCount', 'CoalescedEventCount', 'SessionLocked', 'IsSuspended', 'WakeVersion')) {
    if ($property -notin $nativeProperties) { throw "Power/session signal is missing $property." }
}

$result = [pscustomobject]@{
    Result = 'PASS'
    IgnoredShellProcesses = @($config.SmartIgnoredFullscreenProcesses).Count
    FullscreenRequiresLoad = $true
    LockedHighPowerProfile = $locked.Profile
    LockedPortableProfile = $lockedPortable.Profile
    SessionSwitchSignal = $true
    ChangedSystemSettings = $false
    CompletedAt = (Get-Date).ToString('o')
}
if ($ResultPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath), ($result | ConvertTo-Json), [Text.UTF8Encoding]::new($false)) }
$result | Format-List
