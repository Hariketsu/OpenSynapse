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
    @('AC', 85, 'LowPowerPD'),
    @('AC', 86, 'UnknownAC'),
    @('AC', 100, 'UnknownAC'),
    @('AC', 129, 'UnknownAC'),
    @('AC', 130, 'HighPowerAC'),
    @('AC', 160, 'HighPowerAC')
)
foreach ($case in $cases) {
    $actual = Resolve-SupplyType ([string]$case[0]) $case[1]
    if ($actual -ne [string]$case[2]) { throw "Supply classification failed for $($case[0])/$($case[1]): $actual" }
}

$high = [pscustomobject]@{ Source = 'AC'; SupplyType = 'HighPowerAC'; BatteryPercent = 50 }
$pd = [pscustomobject]@{ Source = 'AC'; SupplyType = 'LowPowerPD'; BatteryPercent = 50 }
$low = [pscustomobject]@{ Source = 'Battery'; SupplyType = 'Battery'; BatteryPercent = 49 }
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
$config.Selection = 'Auto'
foreach ($name in @('Hyper', 'Balance', 'Quiet')) {
    if ((Resolve-RefreshPolicy $config $name $high) -ne 'Fixed240' -or
        (Resolve-RefreshPolicy $config $name $pd) -ne 'DynamicNative' -or
        (Resolve-RefreshPolicy $config $name $low) -ne 'DynamicNative') {
        throw "Supply-aware Auto refresh mapping failed for $name."
    }
}
$config.Selection = 'Quiet'
if ((Resolve-RefreshPolicy $config Quiet $pd) -ne 'Fixed60' -or
    (Resolve-RefreshPolicy $config Quiet $low) -ne 'Fixed60' -or
    (Resolve-RefreshPolicy $config Quiet $high) -ne 'Fixed60') {
    throw 'Manual Quiet did not resolve to the Eco internal 60 Hz policy.'
}
$config.ManageRefreshRate = $false
$config.RefreshPolicy = 'Unmanaged'
if ((Resolve-RefreshPolicy $config Quiet $low) -ne 'Fixed60') {
    throw 'Eco did not enforce internal 60 Hz over an unmanaged refresh preference.'
}
$config.Selection = 'Auto'
foreach ($policy in @('Fixed60', 'Fixed240', 'Unmanaged')) {
    $config.RefreshPolicy = $policy
    $config.ManageRefreshRate = ($policy -ne 'Unmanaged')
    if ((Resolve-RefreshPolicy $config Quiet $low) -ne $policy) { throw "Persistent refresh override failed for $policy." }
}
if ((Resolve-RefreshPolicyAfterPowerTransition Fixed60 Battery AC) -ne 'Auto' -or
    (Resolve-RefreshPolicyAfterPowerTransition Fixed240 Battery AC) -ne 'Auto' -or
    (Resolve-RefreshPolicyAfterPowerTransition Fixed60 AC AC LowPowerPD HighPowerAC) -ne 'Auto' -or
    (Resolve-RefreshPolicyAfterPowerTransition Unmanaged Battery AC Battery HighPowerAC Quiet Auto) -ne 'Auto' -or
    (Resolve-RefreshPolicyAfterPowerTransition Fixed60 AC AC) -ne 'Fixed60' -or
    (Resolve-RefreshPolicyAfterPowerTransition Auto Battery AC) -ne 'Auto') {
    throw 'Manual fixed refresh did not return to Auto exactly when external power was newly connected.'
}

$nativeMethods = [OpenSynapseNative.DisplayModeManager].GetMethods().Name
foreach ($method in @('ApplyFixedRefresh', 'GetSupportedRefreshRates')) {
    if ($method -notin $nativeMethods) { throw "Missing native refresh method: $method" }
}
$dynamicMethods = [OpenSynapseNative.DynamicRefreshManager].GetMethods().Name
foreach ($method in @('GetStatus', 'GetStatuses', 'RestoreStatus', 'ValidateNativeDynamic', 'EnableNativeDynamic', 'Disable', 'ApplyExternalMaximumRefresh', 'ApplyInternalFixedRefresh', 'ApplyProfileRefresh')) {
    if ($method -notin $dynamicMethods) { throw "Missing dynamic refresh method: $method" }
}
$dynamicStatus = [OpenSynapseNative.DynamicRefreshManager]::GetStatus()

$mainSource = Get-Content -Raw -LiteralPath $mainScript
foreach ($required in @(
    "`$script:AppVersion = '2.5.1'",
    "New-CustomPlan 'OpenSynapse Balance'",
    'Set-ProfilePolicy Balance $balanceGuid',
    "New-CustomPlan 'OpenSynapse Experiment'",
    'Set-ProfilePolicy Experiment $experimentGuid',
    "@('HyperPlanGuid', 'BalancePlanGuid', 'QuietPlanGuid', 'ExperimentPlanGuid')",
    "'Fixed60' { [OpenSynapseNative.DynamicRefreshManager]::ApplyProfileRefresh(60); break }",
    "'Fixed240' { [OpenSynapseNative.DynamicRefreshManager]::ApplyProfileRefresh(240); break }",
    'ApplyExternalMaximumRefresh()'
)) {
    if ($mainSource.IndexOf($required, [StringComparison]::Ordinal) -lt 0) { throw "Missing install/upgrade/rollback definition: $required" }
}

$result = [pscustomobject]@{
    Result = 'PASS'
    SupplyCases = $cases.Count
    BalanceThresholdPercent = 50
    RefreshPolicies = 4
    AutoPortableDynamic = $true
    AutoHighPowerFixed240 = $true
    ManualQuietEcoFixed60 = $true
    EcoReleaseRestoresAutoRefresh = $true
    ManualFixedReturnsToAutoOnPowerConnect = $true
    BalanceInstallUpgradeRollbackDefined = $true
    InternalDisplayActive = [bool]$dynamicStatus.InternalDisplayActive
    DynamicRefreshSupported = [bool]$dynamicStatus.Supported
    ChangedSystemSettings = $false
    CompletedAt = (Get-Date).ToString('o')
}
if ($ResultPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath), ($result | ConvertTo-Json), [Text.UTF8Encoding]::new($false)) }
$result | Format-List
