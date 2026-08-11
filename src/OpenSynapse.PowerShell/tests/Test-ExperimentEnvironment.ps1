#requires -Version 5.1

[CmdletBinding()]
param([string]$ResultPath = '')

$ErrorActionPreference = 'Stop'
trap {
    $failure = [pscustomobject]@{ Result = 'FAIL'; Message = $_.Exception.Message; CompletedAt = (Get-Date).ToString('o') }
    if ($ResultPath) {
        [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath), ($failure | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
    }
    Write-Error $_
    break
}

$mainScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'OpenSynapse.ps1'
. $mainScript -Mode SelfTest

$config = Get-DefaultConfig
if ($config.Version -ne 14 -or $config.ExperimentRefreshRate -ne 240 -or
    $config.ExperimentVerificationSeconds -ne 15 -or -not [bool]$config.ExperimentAutoReport) {
    throw 'Experiment configuration defaults are incomplete.'
}
$power = [pscustomobject]@{
    Source = 'AC'; SupplyType = 'HighPowerAC'; RawSupplyType = 'HighPowerAC'; SupplyConfirmationPending = $false
    BatteryPercent = 80; AdapterLimitW = 155; BatteryTelemetryAvailable = $false
    BatteryRemainingMwh = $null; BatteryVoltageMv = $null; BatteryDischargeW = $null
    BatteryDischargeEmaW = $null; BatteryDischargeAverage10mW = $null; BatteryEstimatedHours = $null
    BatteryEstimateConfidence = 'None'; BatteryChargeW = $null
}
if ((Get-DesiredProfile Experiment $power $config (New-SmartAutomationState Balance) Hyper) -ne 'Experiment') {
    throw 'Experiment did not override Smart Auto and temporary profile selection.'
}
if ((Resolve-SelectionAfterSupplyTransition Experiment Battery HighPowerAC) -ne 'Experiment') {
    throw 'Verified high-power AC incorrectly released the Experiment lock.'
}
$config.Selection = 'Experiment'
if ((Resolve-RefreshPolicy $config Experiment $power) -ne 'Fixed240') {
    throw 'Experiment did not resolve to its fixed verified refresh target.'
}

$requiredNative = @{
    'OpenSynapseNative.DisplayModeManager' = @('RestoreMode')
    'OpenSynapseNative.DynamicRefreshManager' = @('GetStatuses', 'RestoreStatus')
    'OpenSynapseNative.AdvancedColorManager' = @('GetStatus', 'SetEnabled')
    'OpenSynapseNative.ColorProfileManager' = @('GetStatus', 'SetProfile')
    'OpenSynapseNative.PhysicalMonitorBrightnessManager' = @('GetStatus', 'SetBrightness')
    'OpenSynapseNative.HardwareTelemetry' = @('Read')
}
foreach ($typeName in $requiredNative.Keys) {
    $type = $typeName -as [type]
    if ($null -eq $type) { throw "Missing native type: $typeName" }
    $methods = $type.GetMethods().Name
    foreach ($method in $requiredNative[$typeName]) {
        if ($method -notin $methods) { throw "Missing native method: $typeName.$method" }
    }
}

$mainSource = Get-Content -Raw -LiteralPath $mainScript
foreach ($requiredDefinition in @(
    "`$rollbackSelection = if (`$experimentClosed) { 'Auto' } else { `$previousSelection }",
    "`$null = Export-ExperimentEnvironmentReport `$Config `$State `$PowerSnapshot `$AutomationState End",
    "`$verificationTarget = if (`$null -ne `$State.ExperimentSession -and `$Phase -eq 'Restored'",
    '$restoreFrequency = if (Test-IsInternalDisplayMode $currentRefreshState $currentMode)',
    'if (-not [bool]$current.IsInternal) { continue }'
)) {
    if ($mainSource.IndexOf($requiredDefinition, [StringComparison]::Ordinal) -lt 0) {
        throw "Missing Experiment safety definition: $requiredDefinition"
    }
}

$display = Get-DisplayStateSnapshot
if (@($display.Modes).Count -lt 1 -or @($display.Scaling).Count -lt 1 -or
    @($display.DynamicRefresh).Count -lt 1 -or @($display.AdvancedColor).Count -lt 1 -or
    @($display.ColorProfiles).Count -lt 1 -or $null -eq $display.PSObject.Properties['PhysicalBrightness']) {
    throw 'The read-only per-display state snapshot is incomplete on this machine.'
}
$identical = Compare-DisplayStateSnapshot $display (Get-DisplayStateSnapshot)
if (-not [bool]$identical.Valid) { throw "An unchanged display snapshot did not verify: $($identical.Differences -join '; ')" }

$synthetic = [pscustomobject]@{
    Modes = @(
        [pscustomobject]@{ DeviceName = '\\.\DISPLAY1'; MonitorDeviceKey = 'internal'; Width = 2560; Height = 1600; BitsPerPixel = 32; Frequency = 60; PositionX = 0; PositionY = 0; Orientation = 0 },
        [pscustomobject]@{ DeviceName = '\\.\DISPLAY2'; MonitorDeviceKey = 'external'; Width = 2560; Height = 1440; BitsPerPixel = 32; Frequency = 165; PositionX = 2560; PositionY = 0; Orientation = 0 }
    )
    DynamicRefresh = @(
        [pscustomobject]@{ Key = 'internal'; GdiDeviceName = '\\.\DISPLAY1'; IsInternal = $true; Enabled = $false; BaseFrequency = 60; BoostFrequency = 60 },
        [pscustomobject]@{ Key = 'external'; GdiDeviceName = '\\.\DISPLAY2'; IsInternal = $false; Enabled = $false; BaseFrequency = 165; BoostFrequency = 165 }
    )
    Scaling = @(); AdvancedColor = @(); ColorProfiles = @(); Brightness = @(); PhysicalBrightness = @()
}
$changedInternal = ($synthetic | ConvertTo-Json -Depth 12 | ConvertFrom-Json)
$changedInternal.Modes[0].Frequency = 240
$internalDifference = Compare-DisplayStateSnapshot $changedInternal $synthetic
if ([bool]$internalDifference.Valid -or @($internalDifference.Differences).Count -lt 1) {
    throw 'Internal display-state drift detection did not report a refresh mismatch.'
}
$changedExternal = ($synthetic | ConvertTo-Json -Depth 12 | ConvertFrom-Json)
$changedExternal.Modes[1].Frequency = 240
$externalDifference = Compare-DisplayStateSnapshot $changedExternal $synthetic
if (-not [bool]$externalDifference.Valid) {
    throw "External refresh was incorrectly included in Experiment restoration verification: $($externalDifference.Differences -join '; ')"
}

$hardware = [OpenSynapseNative.HardwareTelemetry]::Read()
if (-not [bool]$hardware.Available -or @($hardware.ThermalZones).Count -lt 1) {
    throw "Hardware telemetry did not expose the local thermal zones: $($hardware.Error)"
}
if ([double]$hardware.MaximumTemperatureC -lt 0 -or [double]$hardware.MaximumTemperatureC -gt 150) {
    throw "Hardware telemetry returned an invalid temperature: $($hardware.MaximumTemperatureC)"
}

$state = [pscustomobject][ordered]@{
    Version = 11
    ExperimentSession = $null
    DisplayStateSnapshot = $null
}
$automation = New-SmartAutomationState Experiment
$reportRoot = Join-Path ([IO.Path]::GetTempPath()) ('OpenSynapse-experiment-test-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($reportRoot) | Out-Null
try {
    $reportPath = Join-Path $reportRoot 'environment.json'
    $report = Export-ExperimentEnvironmentReport $config $state $power $automation Manual $reportPath
    if (-not (Test-Path -LiteralPath $report.JsonPath) -or -not (Test-Path -LiteralPath $report.HtmlPath) -or
        -not (Test-Path -LiteralPath $report.HashPath) -or [string]::IsNullOrWhiteSpace([string]$report.JsonSha256)) {
        throw 'Experiment report did not create JSON, HTML and SHA-256 outputs.'
    }
    $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $report.JsonPath | ConvertFrom-Json
    if ($manifest.ReportSchemaVersion -ne 1 -or $manifest.OpenSynapseVersion -ne '0.2.0-preview.2' -or
        @($manifest.Display.Modes).Count -lt 1 -or $null -eq $manifest.HardwareTelemetry -or
        $null -eq $manifest.WindowsGpuTelemetry -or $null -eq $manifest.Machine -or
        $null -eq $manifest.Machine.PSObject.Properties['EmbeddedControllerVersion']) {
        throw 'Experiment report manifest is incomplete.'
    }
}
finally { Remove-Item -LiteralPath $reportRoot -Recurse -Force -ErrorAction SilentlyContinue }

$result = [pscustomobject]@{
    Result = 'PASS'
    ConfigVersion = $config.Version
    DisplayCount = @($display.Modes).Count
    ColorProfileCount = @($display.ColorProfiles | Where-Object { [bool]$_.Available }).Count
    ThermalZoneCount = @($hardware.ThermalZones).Count
    NpuAvailable = [bool]$hardware.NpuAvailable
    InternalRefreshDriftDetected = -not [bool]$internalDifference.Valid
    ExternalRefreshUnmanaged = [bool]$externalDifference.Valid
    ReportJsonHtmlAndHash = $true
    CompletedAt = (Get-Date).ToString('o')
}
if ($ResultPath) {
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath), ($result | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
}
$result
