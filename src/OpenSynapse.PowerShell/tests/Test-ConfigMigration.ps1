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
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
$mainScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'OpenSynapse.ps1'
. $mainScript -Mode SelfTest
$source = Get-Content -Raw -LiteralPath $mainScript
$installStart = $source.IndexOf('function Install-OpenSynapse', [StringComparison]::Ordinal)
$installEnd = $source.IndexOf('function Uninstall-OpenSynapse', $installStart, [StringComparison]::Ordinal)
if ($installStart -lt 0 -or $installEnd -le $installStart -or
    $source.Substring($installStart, $installEnd - $installStart) -notmatch 'Version\s*=\s*10') {
    throw 'Installer state schema version is stale.'
}

$temporary = Join-Path (Split-Path -Parent $PSScriptRoot) '.config-test'
if (Test-Path -LiteralPath $temporary) { throw "Test directory already exists: $temporary" }
[IO.Directory]::CreateDirectory($temporary) | Out-Null

$oldPaths = @{
    DataDir = $script:DataDir; ConfigPath = $script:ConfigPath; StatePath = $script:StatePath
    RuntimePath = $script:RuntimePath; LogPath = $script:LogPath
}
try {
    $script:DataDir = $temporary
    $script:ConfigPath = Join-Path $temporary 'config.json'
    $script:StatePath = Join-Path $temporary 'state.json'
    $script:RuntimePath = Join-Path $temporary 'runtime.json'
    $script:LogPath = Join-Path $temporary 'OpenSynapse.log'

    $v1Config = [pscustomobject]@{ Selection = 'Auto'; CloseHighDrainAppsInQuiet = $true; QuietProcessNames = @('HWiNFO64') }
    Write-JsonFile $script:ConfigPath $v1Config
    $migratedConfig = Get-AppConfig
    if ($migratedConfig.Version -ne 11 -or $migratedConfig.InternalScale -ne 150 -or $migratedConfig.ExternalScale -ne 125) { throw 'v1 config migration failed.' }
    if (-not $migratedConfig.ManageWakeDevices -or -not $migratedConfig.ManageRefreshRate) { throw 'v2 config defaults were not added.' }
    if ('ArmourySocketServer' -notin @($migratedConfig.QuietProcessNames)) { throw 'The v2 process list was not merged into the legacy config.' }
    if ($migratedConfig.RefreshPolicy -ne 'FollowProfile' -or $migratedConfig.BalanceBrightness -ne 60 -or $migratedConfig.BalanceBatteryThreshold -ne 50) {
        throw 'v3 config defaults were not added.'
    }
    if (-not $migratedConfig.SeamlessModeSwitching) { throw 'v4 seamless mode switching default was not added.' }
    if (-not $migratedConfig.AdaptiveQuietBrightness -or $migratedConfig.ProcessMaintenanceSeconds -ne 180) {
        throw 'v5 Quiet endurance defaults were not added.'
    }
    if (-not $migratedConfig.AdaptiveQuietCpu -or $migratedConfig.QuietCpuMaxHighBattery -ne 65 -or
        $migratedConfig.QuietCpuMaxMediumBattery -ne 60 -or $migratedConfig.QuietCpuMaxLowBattery -ne 50) {
        throw 'v6 adaptive Quiet CPU defaults were not added.'
    }
    if ($migratedConfig.HyperCpuPolicy -ne 'Sustained') { throw 'v7 Hyper CPU policy default was not added.' }
    if (-not $migratedConfig.SmartAutomationEnabled -or $migratedConfig.SmartHighPowerCpuEnter -ne 45 -or
        @($migratedConfig.SmartHyperProcessNames).Count -lt 8 -or @($migratedConfig.SmartBalanceProcessNames).Count -lt 6) {
        throw 'v8 smart automation defaults were not added.'
    }
    if ($migratedConfig.SmartGpuEnter -ne 20 -or -not $migratedConfig.SmartFullscreenEnabled -or
        @($migratedConfig.ApplicationRules).Count -lt 15 -or $migratedConfig.DgpuLeakMinimumSamples -ne 6) {
        throw 'v9 GPU/fullscreen/rule/leak defaults were not added.'
    }
    if ($migratedConfig.SmartFullscreenCpuFloor -ne 15 -or $migratedConfig.SmartFullscreenGpuFloor -ne 15 -or
        'LockApp' -notin @($migratedConfig.SmartIgnoredFullscreenProcesses) -or
        $migratedConfig.DgpuActivityDischargeThresholdW -ne 8) {
        throw 'v10 fullscreen guard and correlated dGPU activity defaults were not added.'
    }

    $legacyDotNetConfig = [pscustomobject][ordered]@{
        schemaVersion = 10
        selection = 'Performance'
        balancedBatteryThresholdPercent = 57
        manageAdvancedColor = $false
        manageBrightness = $false
        manageDisplayScaling = $false
        refreshPolicy = 'Fixed120'
        internalDisplayScalePercent = 175
        externalDisplayScalePercent = 150
        balancedBrightnessPercent = 65
        quietBrightnessPercent = 35
        manageWakeDevices = $true
        quietWakeDeviceNames = @('Test wake device')
        smartAutomationEnabled = $false
        smartHighPowerCpuEnter = 55
        hyperCpuPolicy = 'Latency'
        adaptiveQuietCpu = $false
        quietCpuMaxHighBattery = 70
        applicationRules = @(
            [pscustomobject]@{
                processName = 'legacy-editor.exe'
                profile = 'Balanced'
                scope = 'Foreground'
                enabled = $true
            }
        )
    }
    Write-JsonFile $script:ConfigPath $legacyDotNetConfig
    $dotNetMigratedConfig = Get-AppConfig
    if (-not $script:LegacyDotNetConfigDetected -or $dotNetMigratedConfig.Version -ne 11 -or
        $dotNetMigratedConfig.Selection -ne 'Hyper' -or $dotNetMigratedConfig.BalanceBatteryThreshold -ne 57 -or
        $dotNetMigratedConfig.ManageAdvancedColor -or $dotNetMigratedConfig.ManageBrightness -or
        $dotNetMigratedConfig.DisplayScalingEnabled -or $dotNetMigratedConfig.RefreshPolicy -ne 'Fixed120' -or
        $dotNetMigratedConfig.InternalScale -ne 175 -or $dotNetMigratedConfig.ExternalScale -ne 150 -or
        $dotNetMigratedConfig.BalanceBrightness -ne 65 -or $dotNetMigratedConfig.QuietBrightness -ne 35 -or
        -not $dotNetMigratedConfig.ManageWakeDevices -or 'Test wake device' -notin @($dotNetMigratedConfig.QuietWakeDevicePatterns) -or
        $dotNetMigratedConfig.SmartAutomationEnabled -or $dotNetMigratedConfig.SmartHighPowerCpuEnter -ne 55 -or
        $dotNetMigratedConfig.HyperCpuPolicy -ne 'Latency' -or $dotNetMigratedConfig.AdaptiveQuietCpu -or
        $dotNetMigratedConfig.QuietCpuMaxHighBattery -ne 70) {
        throw 'Legacy .NET configuration mapping failed.'
    }
    if (@($dotNetMigratedConfig.ApplicationRules).Count -ne 1 -or
        $dotNetMigratedConfig.ApplicationRules[0].ProcessName -ne 'legacy-editor' -or
        $dotNetMigratedConfig.ApplicationRules[0].Profile -ne 'Balance') {
        throw 'Legacy .NET application-rule mapping failed.'
    }

    Write-JsonFile $script:ConfigPath @('PowerPilot uninstaller output', $migratedConfig)
    $interruptedTakeoverConfig = Get-AppConfig
    if ($interruptedTakeoverConfig.Version -ne 11 -or $interruptedTakeoverConfig.Selection -ne 'Auto' -or
        @($interruptedTakeoverConfig.ApplicationRules).Count -lt 15) {
        throw 'Interrupted PowerPilot takeover configuration recovery failed.'
    }

    $v10QuietConfig = Get-DefaultConfig
    $v10QuietConfig.Version = 10
    $v10QuietConfig.QuietCpuMaxHighBattery = 75
    $v10QuietConfig.QuietCpuMaxMediumBattery = 65
    $v10QuietConfig.QuietCpuMaxLowBattery = 60
    $v10QuietConfig.QuietCpuMediumThreshold = 50
    $v10QuietConfig.QuietCpuLowThreshold = 20
    Write-JsonFile $script:ConfigPath $v10QuietConfig
    $v11QuietConfig = Get-AppConfig
    if ($v11QuietConfig.Version -ne 11 -or $v11QuietConfig.QuietCpuMaxHighBattery -ne 65 -or
        $v11QuietConfig.QuietCpuMaxMediumBattery -ne 60 -or $v11QuietConfig.QuietCpuMaxLowBattery -ne 50 -or
        $v11QuietConfig.QuietCpuMediumThreshold -ne 70 -or $v11QuietConfig.QuietCpuLowThreshold -ne 30 -or
        $v11QuietConfig.QuietProcessRestartWindowSeconds -ne 600 -or $v11QuietConfig.QuietProcessCooldownSeconds -ne 1800) {
        throw 'v11 Ryzen AI 9 365 Quiet curve or restart cooling defaults were not migrated.'
    }

    Write-JsonFile ($script:ConfigPath + '.bak') $legacyDotNetConfig
    $configArchive = Move-LegacyDotNetJsonFile -Path ($script:ConfigPath + '.bak') -Stem 'config'
    if (-not $configArchive -or -not (Test-Path -LiteralPath $configArchive) -or
        (Test-Path -LiteralPath ($script:ConfigPath + '.bak'))) {
        throw 'Legacy .NET configuration backup was not archived.'
    }

    $migratedConfig.SmartHighPowerCpuEnter = 5
    $migratedConfig.SmartHighPowerCpuExit = 90
    $migratedConfig.SmartLoadEnterSamples = 0
    $migratedConfig.SmartExitSamples = 100
    $migratedConfig.SmartHyperProcessNames = @('blender', 'BLENDER', '', ('x' * 129))
    Write-JsonFile $script:ConfigPath $migratedConfig
    $healedSmartConfig = Get-AppConfig
    if ($healedSmartConfig.SmartHighPowerCpuEnter -ne 10 -or $healedSmartConfig.SmartHighPowerCpuExit -ne 9 -or
        $healedSmartConfig.SmartLoadEnterSamples -ne 1 -or $healedSmartConfig.SmartExitSamples -ne 60 -or
        @($healedSmartConfig.SmartHyperProcessNames).Count -ne 1) {
        throw 'Invalid Smart Auto thresholds or process names were not normalized.'
    }

    $legacyDotNetState = [pscustomobject][ordered]@{
        schemaVersion = 10
        originalPowerPlan = $null
        performancePowerPlan = $null
        balancedPowerPlan = $null
        quietPowerPlan = $null
        originalBrightness = $null
        advancedColors = @()
        displayScales = @()
        disabledWakeDevices = @()
    }
    Write-JsonFile $script:StatePath $legacyDotNetState
    Write-JsonFile ($script:StatePath + '.bak') $legacyDotNetState
    $stateArchives = @(Move-LegacyDotNetStateFiles)
    if ($stateArchives.Count -ne 2 -or (Test-Path -LiteralPath $script:StatePath) -or
        (Test-Path -LiteralPath ($script:StatePath + '.bak'))) {
        throw 'Legacy .NET state files were not isolated from the PowerShell state schema.'
    }

    $legacyCleanupStart = $source.IndexOf('function Remove-LegacyDotNetRuntime', [StringComparison]::Ordinal)
    $legacyCleanupEnd = $source.IndexOf('function Stop-LegacyScaleWatcher', $legacyCleanupStart, [StringComparison]::Ordinal)
    $legacyCleanupBody = $source.Substring($legacyCleanupStart, $legacyCleanupEnd - $legacyCleanupStart)
    $agentCleanupIndex = $legacyCleanupBody.IndexOf("'uninstall-cleanup'", [StringComparison]::Ordinal)
    $unregisterIndex = $legacyCleanupBody.IndexOf('Unregister-ScheduledTask', [StringComparison]::Ordinal)
    if ($source -notmatch 'function Restore-LegacyDotNetState' -or
        $legacyCleanupBody -notmatch 'Restore-LegacyDotNetState' -or
        $agentCleanupIndex -lt 0 -or $unregisterIndex -le $agentCleanupIndex) {
        throw 'Legacy .NET cleanup is not ordered before task/file removal.'
    }
    $installBody = $source.Substring($installStart, $installEnd - $installStart)
    $dotNetMigrationIndex = $installBody.IndexOf('Remove-LegacyDotNetRuntime', [StringComparison]::Ordinal)
    $powerPilotMigrationIndex = $installBody.IndexOf('Remove-LegacyPowerPilotRuntime', [StringComparison]::Ordinal)
    $newStateIndex = $installBody.IndexOf('$existing = Get-AppState', [StringComparison]::Ordinal)
    if ($source -notmatch 'function Remove-LegacyPowerPilotRuntime' -or
        $source -notmatch 'PowerPilot-2\.4\.1-migration-' -or
        $source -notmatch '\$uninstallOutput\s*=\s*@\(& powershell\.exe' -or
        $dotNetMigrationIndex -lt 0 -or $powerPilotMigrationIndex -le $dotNetMigrationIndex -or
        $newStateIndex -le $powerPilotMigrationIndex) {
        throw 'PowerPilot takeover is not ordered between legacy .NET rollback and new state capture.'
    }

    $v1State = [pscustomobject]@{ Version = 1; OriginalPlanGuid = $script:Guids.Balanced; HyperPlanGuid = '11111111-1111-1111-1111-111111111111'; QuietPlanGuid = '22222222-2222-2222-2222-222222222222' }
    Write-JsonFile $script:StatePath $v1State
    $migratedState = Get-AppState
    if ($migratedState.Version -ne 10) { throw 'v1 state version migration failed.' }
    foreach ($property in @('BalancePlanGuid', 'DisabledWakeDevices', 'ServicesStoppedByUs', 'AdvancedColorStates', 'CapturedBrightness')) {
        if ($null -eq $migratedState.PSObject.Properties[$property]) { throw "Missing migrated state property: $property" }
    }

    $brokenEmptyState = [pscustomobject]@{
        Version = 2; OriginalPlanGuid = $script:Guids.Balanced
        HyperPlanGuid = '11111111-1111-1111-1111-111111111111'; QuietPlanGuid = '22222222-2222-2222-2222-222222222222'
        DisabledWakeDevices = [pscustomobject]@{}; ServicesStoppedByUs = [pscustomobject]@{}
        AdvancedColorStates = [pscustomobject]@{}; CapturedBrightness = $null
    }
    Write-JsonFile $script:StatePath $brokenEmptyState
    $healedState = Get-AppState
    if (@($healedState.DisabledWakeDevices).Count -ne 0 -or @($healedState.ServicesStoppedByUs).Count -ne 0 -or @($healedState.AdvancedColorStates).Count -ne 0) {
        throw 'Malformed empty state objects were not normalized to empty arrays.'
    }
    $brokenEmptyState.DisabledWakeDevices = @(('x' * 513), 'HID-compliant mouse')
    Write-JsonFile $script:StatePath $brokenEmptyState
    $healedWakeState = Get-AppState
    if (@($healedWakeState.DisabledWakeDevices).Count -ne 1 -or $healedWakeState.DisabledWakeDevices[0] -ne 'HID-compliant mouse') {
        throw 'Corrupt oversized wake-device state was not discarded.'
    }
    $healedState = $healedWakeState
    $healedState.DisabledWakeDevices = @()
    Save-AppState $healedState
    $roundTripState = Read-JsonFile $script:StatePath
    if (@($roundTripState.DisabledWakeDevices).Count -ne 0 -or @($roundTripState.ServicesStoppedByUs).Count -ne 0 -or @($roundTripState.AdvancedColorStates).Count -ne 0) {
        throw 'Normalized empty arrays did not survive JSON round trip.'
    }

    $bytes = [IO.File]::ReadAllBytes($script:ConfigPath)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    if ($hasBom) { throw 'PowerShell JSON files unexpectedly contain a UTF-8 BOM.' }

    $result = [pscustomobject]@{
        Result = 'PASS'
        ConfigVersion = $migratedConfig.Version
        StateVersion = $migratedState.Version
        LegacyDotNetMapped = $true
        LegacyDotNetStateArchived = $true
        PowerPilotTakeoverOrdered = $true
        NewConfigProperties = @($migratedConfig.PSObject.Properties).Count
        Utf8WithoutBom = $true
        CompletedAt = (Get-Date).ToString('o')
    }
}
finally {
    $script:DataDir = $oldPaths.DataDir
    $script:ConfigPath = $oldPaths.ConfigPath
    $script:StatePath = $oldPaths.StatePath
    $script:RuntimePath = $oldPaths.RuntimePath
    $script:LogPath = $oldPaths.LogPath
    $resolvedTemporary = [IO.Path]::GetFullPath($temporary)
    $resolvedProject = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)) + [IO.Path]::DirectorySeparatorChar
    if ($resolvedTemporary.StartsWith($resolvedProject, [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolvedTemporary -Recurse -Force -ErrorAction SilentlyContinue
    }
}
if ($ResultPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath), ($result | ConvertTo-Json), [Text.UTF8Encoding]::new($false)) }
$result | Format-List
