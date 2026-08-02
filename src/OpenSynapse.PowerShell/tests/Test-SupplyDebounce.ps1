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

$start = [DateTime]'2026-07-22T09:00:00'
Initialize-SupplyStabilizer Hyper
$script:SupplyStabilizerStartedAt = $start

# A false low reading during the 30-second GPU/EC warm-up must hold Hyper.
$warmup = Resolve-StableSupplyType AC LowPowerPD 1 $start.AddSeconds(2)
if ($warmup -ne 'HighPowerAC' -or $script:PendingLowPowerSamples -ne 0) {
    throw 'Startup warm-up did not suppress a transient low-power reading.'
}

# After warm-up, two low samples still hold Hyper. The third sample, spaced across
# two seven-second confirmation intervals, confirms PD.
$first = Resolve-StableSupplyType AC LowPowerPD 2 $start.AddSeconds(30)
$second = Resolve-StableSupplyType AC LowPowerPD 3 $start.AddSeconds(37)
$third = Resolve-StableSupplyType AC LowPowerPD 4 $start.AddSeconds(44)
if ($first -ne 'HighPowerAC' -or $second -ne 'HighPowerAC' -or $third -ne 'LowPowerPD') {
    throw "Low-power debounce failed: $first/$second/$third"
}

# Promotion is asymmetric: one verified >=130W reading restores Hyper immediately.
$promoted = Resolve-StableSupplyType AC HighPowerAC 5 $start.AddSeconds(45)
if ($promoted -ne 'HighPowerAC') { throw 'High-power promotion was not immediate.' }

# Ambiguous and unavailable readings retain the last trusted AC class.
$held = Resolve-StableSupplyType AC UnknownAC 6 $start.AddSeconds(46)
if ($held -ne 'HighPowerAC') { throw 'Unknown AC did not retain the trusted high-power class.' }

# A real AC disconnect must bypass all debounce and switch to battery immediately.
$battery = Resolve-StableSupplyType Battery Battery 6 $start.AddSeconds(47)
if ($battery -ne 'Battery') { throw 'Battery transition was not immediate.' }

# Regression trace from the target machine: a 280W adapter briefly exposed a
# 91.86W NVIDIA enforced limit, then settled at 105W. Neither value is strong PD
# evidence and a Balance/Other cold start must never classify this trace as PD.
Initialize-SupplyStabilizer Balance
$script:SupplyStabilizerStartedAt = $start
$falseHighAdapterTrace = @(
    (Resolve-StableSupplyType AC (Resolve-SupplyType AC 91.86) 1 $start.AddSeconds(2)),
    (Resolve-StableSupplyType AC (Resolve-SupplyType AC 105.0) 2 $start.AddSeconds(30)),
    (Resolve-StableSupplyType AC (Resolve-SupplyType AC 105.0) 3 $start.AddSeconds(37)),
    (Resolve-StableSupplyType AC (Resolve-SupplyType AC 105.0) 4 $start.AddSeconds(44))
)
if (@($falseHighAdapterTrace | Where-Object { $_ -eq 'LowPowerPD' }).Count -ne 0) {
    throw "280W regression trace was classified as PD: $($falseHighAdapterTrace -join '/')"
}

# A genuine PD trace in the observed 76-79W cluster is confirmed only after the
# common startup warm-up and three spaced samples, even without a seeded profile.
Initialize-SupplyStabilizer Other
$script:SupplyStabilizerStartedAt = $start
$coldLow = Resolve-StableSupplyType AC (Resolve-SupplyType AC 78.74) 1 $start.AddSeconds(2)
$realPdFirst = Resolve-StableSupplyType AC (Resolve-SupplyType AC 78.74) 2 $start.AddSeconds(30)
$realPdSecond = Resolve-StableSupplyType AC (Resolve-SupplyType AC 76.09) 3 $start.AddSeconds(37)
$realPdThird = Resolve-StableSupplyType AC (Resolve-SupplyType AC 79.32) 4 $start.AddSeconds(44)
if ($coldLow -ne 'UnknownAC' -or $realPdFirst -ne 'UnknownAC' -or
    $realPdSecond -ne 'UnknownAC' -or $realPdThird -ne 'LowPowerPD') {
    throw "Cold-start PD debounce failed: $coldLow/$realPdFirst/$realPdSecond/$realPdThird"
}

# Manual Quiet is not pre-seeded as PD. A real >=130W adapter reading therefore
# still releases the Quiet lock immediately instead of waiting for a later probe.
Initialize-SupplyStabilizer Quiet
$script:SupplyStabilizerStartedAt = $start
$quietColdLow = Resolve-StableSupplyType AC (Resolve-SupplyType AC 80.0) 1 $start.AddSeconds(2)
$quietHigh = Resolve-StableSupplyType AC (Resolve-SupplyType AC 151.62) 2 $start.AddSeconds(3)
if ($quietColdLow -ne 'UnknownAC' -or $quietHigh -ne 'HighPowerAC') {
    throw "Manual Quiet adapter recovery failed: $quietColdLow/$quietHigh"
}

$source = Get-Content -Raw -LiteralPath $mainScript
foreach ($required in @(
    '$script:AdapterStartupWarmupSeconds = 30',
    '$script:AdapterLowConfirmationSamples = 3',
    '$script:AdapterConfirmationIntervalSeconds = 7',
    '$script:LowPowerAdapterThresholdW = 85.0',
    'Apply-CurrentSelection -Full -ApplyVisualPolicy -RepairScaling',
    'SeamlessModeSwitching = $true'
)) {
    if ($source.IndexOf($required, [StringComparison]::Ordinal) -lt 0) { throw "Missing debounce/seamless definition: $required" }
}
$visualApplyCalls = [regex]::Matches($source, 'Apply-CurrentSelection -Full -ApplyVisualPolicy -RepairScaling').Count
if ($visualApplyCalls -ne 2) {
    throw "Display-link reconfiguration escaped its two explicit paths: found $visualApplyCalls calls."
}
foreach ($seamlessCall in @(
    'Apply-CurrentSelection -Full -Notify',
    'Apply-CurrentSelection -Full'
)) {
    if ($source.IndexOf($seamlessCall, [StringComparison]::Ordinal) -lt 0) {
        throw "Missing seamless profile/startup call: $seamlessCall"
    }
}

$result = [pscustomobject]@{
    Result = 'PASS'
    StartupWarmupSeconds = 30
    LowPowerSamplesRequired = 3
    ConfirmationSpanSeconds = 14
    ImmediateHighPowerPromotion = $true
    ImmediateBatteryFallback = $true
    ColdStartFalseHighAdapterTraceRejected = $true
    ColdStartRealPdDebounced = $true
    ManualQuietHighPowerRecovery = $true
    SeamlessModeSwitchingDefault = $true
    ExplicitDisplayApplyPaths = $visualApplyCalls
    ChangedSystemSettings = $false
    CompletedAt = (Get-Date).ToString('o')
}
if ($ResultPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath), ($result | ConvertTo-Json), [Text.UTF8Encoding]::new($false)) }
$result | Format-List
