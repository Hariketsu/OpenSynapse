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

$project = Split-Path -Parent $PSScriptRoot
$mainScript = Join-Path $project 'OpenSynapse.ps1'
$nativeSourcePath = Join-Path $project 'OpenSynapse.Native.cs'
. $mainScript -Mode SelfTest

$config = Get-DefaultConfig
if ($config.Version -ne 13 -or -not $config.AdaptiveQuietBrightness -or -not $config.AdaptiveQuietCpu -or
    $config.ProcessMaintenanceSeconds -ne 180 -or $config.QuietCpuMediumThreshold -ne 70 -or
    $config.QuietCpuLowThreshold -ne 30) {
    throw 'Quiet endurance defaults are incomplete.'
}

$batteryHigh = [pscustomobject]@{ Source = 'Battery'; BatteryPercent = 80 }
$batteryMedium = [pscustomobject]@{ Source = 'Battery'; BatteryPercent = 35 }
$batteryCpuMedium = [pscustomobject]@{ Source = 'Battery'; BatteryPercent = 50 }
$batteryLow = [pscustomobject]@{ Source = 'Battery'; BatteryPercent = 15 }
$pd = [pscustomobject]@{ Source = 'AC'; BatteryPercent = 35 }
$targets = @(
    (Resolve-ProfileBrightnessTarget Quiet $config $batteryHigh),
    (Resolve-ProfileBrightnessTarget Quiet $config $batteryMedium),
    (Resolve-ProfileBrightnessTarget Quiet $config $batteryLow),
    (Resolve-ProfileBrightnessTarget Quiet $config $pd),
    (Resolve-ProfileBrightnessTarget Balance $config $batteryLow)
)
if (($targets -join ',') -ne '35,30,20,40,60') { throw "Adaptive brightness curve is incorrect: $($targets -join ',')" }

$config.QuietBrightness = 25
if ((Resolve-ProfileBrightnessTarget Quiet $config $batteryHigh) -ne 25) {
    throw 'Adaptive brightness exceeded the user Quiet ceiling.'
}

$cpuTargets = @(
    (Resolve-QuietCpuMaxPercent $config $batteryHigh),
    (Resolve-QuietCpuMaxPercent $config $batteryCpuMedium),
    (Resolve-QuietCpuMaxPercent $config $batteryLow)
)
if (($cpuTargets -join ',') -ne '65,60,50') { throw "Adaptive CPU curve is incorrect: $($cpuTargets -join ',')" }
$eppTargets = @(
    (Resolve-QuietCpuEppPercent $config $batteryHigh),
    (Resolve-QuietCpuEppPercent $config $batteryCpuMedium),
    (Resolve-QuietCpuEppPercent $config $batteryLow)
)
if (($eppTargets -join ',') -ne '90,95,100') { throw "Adaptive EPP curve is incorrect: $($eppTargets -join ',')" }
$boundaryTargets = @(
    "$(Resolve-QuietCpuMaxPercent $config ([pscustomobject]@{ BatteryPercent = 70 }))/$(Resolve-QuietCpuEppPercent $config ([pscustomobject]@{ BatteryPercent = 70 }))",
    "$(Resolve-QuietCpuMaxPercent $config ([pscustomobject]@{ BatteryPercent = 69 }))/$(Resolve-QuietCpuEppPercent $config ([pscustomobject]@{ BatteryPercent = 69 }))",
    "$(Resolve-QuietCpuMaxPercent $config ([pscustomobject]@{ BatteryPercent = 30 }))/$(Resolve-QuietCpuEppPercent $config ([pscustomobject]@{ BatteryPercent = 30 }))",
    "$(Resolve-QuietCpuMaxPercent $config ([pscustomobject]@{ BatteryPercent = 29 }))/$(Resolve-QuietCpuEppPercent $config ([pscustomobject]@{ BatteryPercent = 29 }))"
)
if (($boundaryTargets -join ',') -ne '65/90,60/95,60/95,50/100') {
    throw "Adaptive CPU/EPP boundary mapping is incorrect: $($boundaryTargets -join ',')"
}

$script:RecordedCpuWrites = New-Object Collections.Generic.List[object]
$script:RecordedReactivations = 0
function Set-PlanValue {
    param([string]$PlanGuid, [string]$Source, [string]$Subgroup, [string]$Setting, [int]$Value, [switch]$Optional)
    if ($PlanGuid -ne '11111111-1111-1111-1111-111111111111' -or $Source -ne 'DC' -or
        $Subgroup -ne $script:Guids.Processor -or $Setting -notin @(
            $script:Guids.ProcessorMaximum, $script:Guids.ProcessorMaximum1, $script:Guids.ProcessorMaximum2,
            $script:Guids.ProcessorEpp, $script:Guids.ProcessorEpp1, $script:Guids.ProcessorEpp2,
            $script:Guids.ProcessorScheduling, $script:Guids.ProcessorShortScheduling
        )) {
        throw 'Adaptive CPU wrote an unexpected power setting.'
    }
    $script:RecordedCpuWrites.Add([pscustomobject]@{ Setting = $Setting; Value = $Value })
}
function Get-ActivePlanGuid { return '11111111-1111-1111-1111-111111111111' }
function Invoke-PowerCfg {
    param([string[]]$Arguments, [switch]$AllowFailure)
    if ($Arguments[0] -ne '/setactive') { throw "Unexpected powercfg call: $($Arguments -join ' ')" }
    $script:RecordedReactivations++
    return ''
}
function Write-AppLog { param([string]$Message) }
$quietState = [pscustomobject]@{ QuietPlanGuid = '11111111-1111-1111-1111-111111111111' }
$script:LastAppliedQuietCpuMax = $null
$null = Apply-QuietDynamicCpuPolicy $config $quietState $batteryHigh
$null = Apply-QuietDynamicCpuPolicy $config $quietState $batteryHigh
$null = Apply-QuietDynamicCpuPolicy $config $quietState $batteryCpuMedium
$null = Apply-QuietDynamicCpuPolicy $config $quietState $batteryLow
if ($script:RecordedCpuWrites.Count -ne 24 -or $script:RecordedReactivations -ne 3) {
    throw 'Adaptive CPU did not apply exactly once per battery band.'
}
foreach ($classSetting in @($script:Guids.ProcessorMaximum, $script:Guids.ProcessorMaximum1, $script:Guids.ProcessorMaximum2)) {
    $values = @($script:RecordedCpuWrites | Where-Object { $_.Setting -eq $classSetting } | Select-Object -ExpandProperty Value)
    if (($values -join ',') -ne '65,60,50') { throw "Quiet maximum was not synchronized across processor classes: $($values -join ',')" }
}
foreach ($classSetting in @($script:Guids.ProcessorEpp, $script:Guids.ProcessorEpp1, $script:Guids.ProcessorEpp2)) {
    $values = @($script:RecordedCpuWrites | Where-Object { $_.Setting -eq $classSetting } | Select-Object -ExpandProperty Value)
    if (($values -join ',') -ne '90,95,100') { throw "Quiet EPP was not synchronized across processor classes: $($values -join ',')" }
}
foreach ($schedulerSetting in @($script:Guids.ProcessorScheduling, $script:Guids.ProcessorShortScheduling)) {
    $values = @($script:RecordedCpuWrites | Where-Object { $_.Setting -eq $schedulerSetting } | Select-Object -ExpandProperty Value)
    if (($values -join ',') -ne '4,4,4') { throw 'Quiet scheduler does not prefer efficient cores.' }
}

$nativeMethods = [OpenSynapseNative.PowerChangeSignal].GetMethods().Name
foreach ($method in @('Start', 'Stop', 'get_Version')) {
    if ($method -notin $nativeMethods) { throw "Missing power event signal method: $method" }
}

$nativeSource = Get-Content -LiteralPath $nativeSourcePath -Raw -Encoding UTF8
$displayStart = $nativeSource.IndexOf('public static class DisplayChangeSignal', [StringComparison]::Ordinal)
$powerStart = $nativeSource.IndexOf('public static class PowerChangeSignal', [StringComparison]::Ordinal)
if ($displayStart -lt 0 -or $powerStart -le $displayStart) { throw 'Separated display/power signal classes were not found.' }
$displaySection = $nativeSource.Substring($displayStart, $powerStart - $displayStart)
if ($displaySection.Contains('PowerModeChanged')) { throw 'Display change signal still receives power events.' }

$mainSource = Get-Content -LiteralPath $mainScript -Raw -Encoding UTF8
foreach ($required in @(
    '$script:MonitorBaseIntervalMs = 5000',
    '$script:PlanVerificationIntervalSeconds = 30',
    "ProcessorMaximum 80 65",
    "ProcessorEpp 90 90",
    'ProcessorScheduling 4',
    'ProcessorShortScheduling 4',
    "GpuPreference 1 1",
    "WakeTimers 0 0",
    "ConnectivityStandby 0 0",
    "`$Name -eq 'Balance' -and `$null -ne `$Snapshot -and [string]`$Snapshot.SupplyType -eq 'HighPowerAC'"
)) {
    if ($mainSource.IndexOf($required, [StringComparison]::Ordinal) -lt 0) { throw "Missing Quiet endurance definition: $required" }
}

$result = [pscustomobject]@{
    Result = 'PASS'
    ConfigVersion = $config.Version
    MaintenanceSeconds = $config.ProcessMaintenanceSeconds
    TimerMilliseconds = 5000
    PlanVerificationSeconds = $script:PlanVerificationIntervalSeconds
    BrightnessTargets = $targets
    CpuTargets = $cpuTargets
    EppTargets = $eppTargets
    BoundaryTargets = $boundaryTargets
    CpuBandWrites = $script:RecordedCpuWrites.Count
    PowerAndDisplayEventsSeparated = $true
    ChangedSystemSettings = $false
    CompletedAt = (Get-Date).ToString('o')
}
if ($ResultPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath), ($result | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false)) }
$result | Format-List
