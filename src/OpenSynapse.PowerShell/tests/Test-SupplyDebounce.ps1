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

$source = Get-Content -Raw -LiteralPath $mainScript
foreach ($required in @(
    '$script:AdapterStartupWarmupSeconds = 30',
    '$script:AdapterLowConfirmationSamples = 3',
    '$script:AdapterConfirmationIntervalSeconds = 7',
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
    SeamlessModeSwitchingDefault = $true
    ExplicitDisplayApplyPaths = $visualApplyCalls
    ChangedSystemSettings = $false
    CompletedAt = (Get-Date).ToString('o')
}
if ($ResultPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath), ($result | ConvertTo-Json), [Text.UTF8Encoding]::new($false)) }
$result | Format-List
