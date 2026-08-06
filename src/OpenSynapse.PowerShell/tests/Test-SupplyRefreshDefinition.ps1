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

$cases = @(
    @('Battery', $null, 'Battery'),
    @('Unknown', $null, 'Unknown'),
    @('AC', $null, 'UnknownAC'),
    @('AC', 70, 'LowPowerPD'),
    @('AC', 100, 'LowPowerPD'),
    @('AC', 101, 'UnknownAC'),
    @('AC', 129, 'UnknownAC'),
    @('AC', 130, 'HighPowerAC'),
    @('AC', 160, 'HighPowerAC')
)
foreach ($case in $cases) {
    $actual = Resolve-SupplyType ([string]$case[0]) $case[1]
    if ($actual -ne [string]$case[2]) { throw "Supply classification failed for $($case[0])/$($case[1]): $actual" }
}

$high = [pscustomobject]@{ SupplyType = 'HighPowerAC'; BatteryPercent = 50 }
$pd = [pscustomobject]@{ SupplyType = 'LowPowerPD'; BatteryPercent = 50 }
$low = [pscustomobject]@{ SupplyType = 'Battery'; BatteryPercent = 49 }
if ((Get-DesiredProfile Auto $high) -ne 'Hyper' -or (Get-DesiredProfile Auto $pd) -ne 'Quiet') {
    throw 'Auto supply mapping failed.'
}
if ((Get-DesiredProfile Hyper $pd) -ne 'Hyper' -or (Get-DesiredProfile Balance $pd) -ne 'Balance') {
    throw 'Manual override mapping failed.'
}
if (-not (Test-BalanceEligible $pd 50) -or (Test-BalanceEligible $low 50)) {
    throw 'Balance 50% threshold is not inclusive/exclusive at the correct boundary.'
}

$config = Get-DefaultConfig
$expectedByProfile = @{ Hyper = 'Maximum'; Balance = 'Fixed120'; Quiet = 'Fixed60' }
foreach ($name in $expectedByProfile.Keys) {
    if ((Resolve-RefreshPolicy $config $name) -ne $expectedByProfile[$name]) { throw "Follow-profile refresh mapping failed for $name." }
}
foreach ($policy in @('Fixed60', 'Fixed120', 'Fixed240', 'DynamicNative', 'Unmanaged')) {
    $config.RefreshPolicy = $policy
    $config.ManageRefreshRate = ($policy -ne 'Unmanaged')
    if ((Resolve-RefreshPolicy $config Quiet) -ne $policy) { throw "Persistent refresh override failed for $policy." }
}

$nativeMethods = [OpenSynapseNative.DisplayModeManager].GetMethods().Name
foreach ($method in @('ApplyFixedRefresh', 'GetSupportedRefreshRates')) {
    if ($method -notin $nativeMethods) { throw "Missing native refresh method: $method" }
}
$dynamicMethods = [OpenSynapseNative.DynamicRefreshManager].GetMethods().Name
foreach ($method in @('GetStatus', 'ValidateNativeDynamic', 'EnableNativeDynamic', 'Disable')) {
    if ($method -notin $dynamicMethods) { throw "Missing dynamic refresh method: $method" }
}
$dynamicStatus = [OpenSynapseNative.DynamicRefreshManager]::GetStatus()

$mainSource = Get-Content -Raw -LiteralPath $mainScript
foreach ($required in @(
    "`$script:AppVersion = '0.2.0'",
    "New-CustomPlan 'OpenSynapse Balance'",
    'Set-ProfilePolicy Balance $balanceGuid',
    "@('HyperPlanGuid', 'BalancePlanGuid', 'QuietPlanGuid')"
)) {
    if ($mainSource.IndexOf($required, [StringComparison]::Ordinal) -lt 0) { throw "Missing install/upgrade/rollback definition: $required" }
}

$result = [pscustomobject]@{
    Result = 'PASS'
    SupplyCases = $cases.Count
    BalanceThresholdPercent = 50
    RefreshPolicies = 6
    BalanceInstallUpgradeRollbackDefined = $true
    InternalDisplayActive = [bool]$dynamicStatus.InternalDisplayActive
    DynamicRefreshSupported = [bool]$dynamicStatus.Supported
    ChangedSystemSettings = $false
    CompletedAt = (Get-Date).ToString('o')
}
if ($ResultPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath), ($result | ConvertTo-Json), [Text.UTF8Encoding]::new($false)) }
$result | Format-List
