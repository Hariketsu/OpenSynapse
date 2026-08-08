#requires -Version 5.1
#requires -RunAsAdministrator

[CmdletBinding()]
param(
    [string]$ResultPath = '',
    [string]$PackageScript = ''
)

$ErrorActionPreference = 'Stop'
trap {
    $failure = [pscustomobject]@{ Result = 'FAIL'; Message = $_.Exception.Message; Position = $_.InvocationInfo.PositionMessage; CompletedAt = (Get-Date).ToString('o') }
    if ($ResultPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath), ($failure | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false)) }
    Write-Error $_
    break
}

$programDir = Join-Path $env:ProgramFiles 'OpenSynapse'
$installedScript = Join-Path $programDir 'OpenSynapse.ps1'
$dataDir = Join-Path $env:LOCALAPPDATA 'OpenSynapse'
$statePath = Join-Path $dataDir 'state.json'
$runtimePath = Join-Path $dataDir 'runtime.json'
$logPath = Join-Path $dataDir 'OpenSynapse.log'
$shortcutPath = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\OpenSynapse.lnk'
$installedAppIcon = Join-Path $programDir 'OpenSynapse.App.ico'
$installedTrayIcon = Join-Path $programDir 'OpenSynapse.Tray.ico'

if (-not (Test-Path -LiteralPath $installedScript)) { throw 'Installed script is missing.' }
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
. $installedScript -Mode SelfTest
$state = Get-InstalledState
$runtime = Read-JsonFile $runtimePath
$process = Get-Process -Id ([int]$runtime.ProcessId) -ErrorAction Stop
$task = Get-ScheduledTask -TaskName 'OpenSynapse' -ErrorAction Stop
$config = Get-AppConfig
$powerSnapshot = Get-PowerSnapshot
$quietDcMaximum = Resolve-QuietCpuMaxPercent $config $powerSnapshot

$cases = @(
    [pscustomobject]@{ Sub = $script:Guids.Processor; Setting = $script:Guids.ProcessorMinimum; Hyper = @(5, 5); Balance = @(5, 5); Quiet = @(5, 5) },
    [pscustomobject]@{ Sub = $script:Guids.Processor; Setting = $script:Guids.ProcessorMaximum; Hyper = @(100, 100); Balance = @(100, 100); Quiet = @(80, $quietDcMaximum) },
    [pscustomobject]@{ Sub = $script:Guids.Processor; Setting = $script:Guids.ProcessorEpp; Hyper = @(0, 0); Balance = @(50, 70); Quiet = @(90, 90) },
    [pscustomobject]@{ Sub = $script:Guids.Processor; Setting = $script:Guids.ProcessorBoost; Hyper = @(2, 2); Balance = @(3, 3); Quiet = @(0, 0) },
    [pscustomobject]@{ Sub = $script:Guids.Processor; Setting = $script:Guids.CoolingPolicy; Hyper = @(1, 1); Balance = @(1, 0); Quiet = @(0, 0) },
    [pscustomobject]@{ Sub = $script:Guids.Wireless; Setting = $script:Guids.WirelessPowerSaving; Hyper = @(0, 0); Balance = @(1, 2); Quiet = @(3, 3) },
    [pscustomobject]@{ Sub = $script:Guids.PciExpress; Setting = $script:Guids.PciLinkState; Hyper = @(0, 0); Balance = @(1, 2); Quiet = @(2, 2) },
    [pscustomobject]@{ Sub = $script:Guids.Display; Setting = $script:Guids.DisplayTimeout; Hyper = @(900, 300); Balance = @(600, 300); Quiet = @(300, 120) },
    [pscustomobject]@{ Sub = $script:Guids.Usb; Setting = $script:Guids.UsbSelectiveSuspend; Hyper = @(0, 0); Balance = @(1, 1); Quiet = @(1, 1) },
    [pscustomobject]@{ Sub = $script:Guids.EnergySaver; Setting = $script:Guids.EnergySaverThreshold; Hyper = @(0, 0); Balance = @(0, 50); Quiet = @(0, 100) },
    [pscustomobject]@{ Sub = $script:Guids.Sleep; Setting = $script:Guids.StandbyIdle; Hyper = @(0, 900); Balance = @(900, 600); Quiet = @(600, 180) },
    [pscustomobject]@{ Sub = $script:Guids.Sleep; Setting = $script:Guids.HibernateIdle; Hyper = @(0, 3600); Balance = @(3600, 1800); Quiet = @(1800, 900) },
    [pscustomobject]@{ Sub = $script:Guids.Buttons; Setting = $script:Guids.LidAction; Hyper = @(1, 1); Balance = @(1, 2); Quiet = @(1, 2) }
)

function Get-InstalledPair([string]$PlanGuid, [string]$Subgroup, [string]$Setting) {
    $query = Invoke-PowerCfg @('/qh', $PlanGuid, $Subgroup, $Setting)
    $values = @([regex]::Matches($query, '0x[0-9a-fA-F]+') | ForEach-Object { [Convert]::ToInt32($_.Value.Substring(2), 16) })
    if ($values.Count -lt 2) { throw "Cannot parse installed values for $Setting" }
    return @($values[$values.Count - 2], $values[$values.Count - 1])
}

$valueChecks = 0
foreach ($name in @('Hyper', 'Balance', 'Quiet')) {
    $guid = switch ($name) {
        'Hyper' { [string]$state.HyperPlanGuid; break }
        'Balance' { [string]$state.BalancePlanGuid; break }
        default { [string]$state.QuietPlanGuid }
    }
    foreach ($case in $cases) {
        $actual = @(Get-InstalledPair $guid $case.Sub $case.Setting)
        $expected = @($case.$name)
        if ($actual[0] -ne $expected[0] -or $actual[1] -ne $expected[1]) { throw "$name installed value mismatch for $($case.Setting)." }
        $valueChecks += 2
    }
}

$logLines = @(Get-Content -LiteralPath $logPath -ErrorAction SilentlyContinue)
$lastStartIndex = -1
for ($index = 0; $index -lt $logLines.Count; $index++) { if ($logLines[$index] -like '*Tray started*') { $lastStartIndex = $index } }
$postStartFailures = if ($lastStartIndex -ge 0) { @($logLines[($lastStartIndex + 1)..($logLines.Count - 1)] | Where-Object { $_ -like '*Apply failed*' }).Count } else { -1 }
if ($lastStartIndex -eq $logLines.Count - 1) { $postStartFailures = 0 }

$stateRaw = Get-Content -Raw -LiteralPath $statePath
$packageMatches = if ($PackageScript) { (Get-FileHash -LiteralPath $PackageScript).Hash -eq (Get-FileHash -LiteralPath $installedScript).Hash } else { $true }
$iconFilesExist = (Test-Path -LiteralPath $installedAppIcon) -and (Test-Path -LiteralPath $installedTrayIcon)
$iconFilesMatchPackage = $true
if ($PackageScript) {
    $packageRoot = Split-Path -Parent ([IO.Path]::GetFullPath($PackageScript))
    $packageAppIcon = Join-Path $packageRoot 'assets\OpenSynapse.App.ico'
    $packageTrayIcon = Join-Path $packageRoot 'assets\OpenSynapse.Tray.ico'
    $iconFilesMatchPackage = $iconFilesExist -and (Test-Path -LiteralPath $packageAppIcon) -and (Test-Path -LiteralPath $packageTrayIcon) -and
        ((Get-FileHash -LiteralPath $installedAppIcon).Hash -eq (Get-FileHash -LiteralPath $packageAppIcon).Hash) -and
        ((Get-FileHash -LiteralPath $installedTrayIcon).Hash -eq (Get-FileHash -LiteralPath $packageTrayIcon).Hash)
}
$shortcutUsesOpenSynapseIcon = $false
$shortcutUsesOpenSynapseIdentity = $false
if (Test-Path -LiteralPath $shortcutPath) {
    $shortcutShell = New-Object -ComObject WScript.Shell
    try {
        $shortcut = $shortcutShell.CreateShortcut($shortcutPath)
        $shortcutUsesOpenSynapseIcon = ([string]$shortcut.IconLocation -like "$installedAppIcon,*")
        $shortcutUsesOpenSynapseIdentity = ([OpenSynapseNative.AppIdentity]::GetShortcutAppId($shortcutPath) -eq $script:AppUserModelId)
    }
    finally { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shortcutShell) }
}
$activeProfile = Get-ActiveProfileName $state
$activeProfileAllowed = if ([string]$config.Selection -in @('Hyper', 'Balance', 'Quiet')) {
    $activeProfile -eq [string]$config.Selection
}
elseif (-not [bool]$config.SmartAutomationEnabled) {
    $activeProfile -eq (Get-DesiredProfile Auto $powerSnapshot)
}
elseif ([string]$powerSnapshot.SupplyType -eq 'HighPowerAC') {
    $activeProfile -in @('Balance', 'Hyper')
}
elseif ([string]$powerSnapshot.SupplyType -in @('LowPowerPD', 'Battery') -and [int]$powerSnapshot.BatteryPercent -ge [int]$config.BalanceBatteryThreshold) {
    $activeProfile -in @('Quiet', 'Balance')
}
else { $activeProfile -eq 'Quiet' }
$result = [pscustomobject]@{
    Result = 'PASS'
    Version = $script:AppVersion
    TaskState = $task.State.ToString()
    TaskRunLevel = $task.Principal.RunLevel.ToString()
    TaskInteractive = $task.Principal.LogonType.ToString()
    TaskActionProtected = ($task.Actions.Arguments -like "*$installedScript*")
    TaskLogonDelay = [string]$task.Triggers[0].Delay
    AllowBattery = -not [bool]$task.Settings.DisallowStartIfOnBatteries
    DontStopOnBattery = -not [bool]$task.Settings.StopIfGoingOnBatteries
    TrayPid = $runtime.ProcessId
    TrayAliveAndMatched = ($process.StartTime.ToUniversalTime().Ticks -eq [long]$runtime.StartTimeUtcTicks)
    TrayDpiMode = if ($runtime.PSObject.Properties['DpiMode']) { [string]$runtime.DpiMode } else { 'Missing' }
    TrayDpiAwareness = [OpenSynapseNative.HighDpi]::GetProcessAwareness($process.Handle)
    TrayAppUserModelId = if ($runtime.PSObject.Properties['AppUserModelId']) { [string]$runtime.AppUserModelId } else { 'Missing' }
    StateVersion = $state.Version
    ConfigVersion = $config.Version
    RuntimeVersion = $runtime.Version
    ActiveProfile = $activeProfile
    ActiveProfileAllowed = $activeProfileAllowed
    SupplyType = $powerSnapshot.SupplyType
    InstalledPowerValuesVerified = $valueChecks
    EmptyStateArraysValid = ($stateRaw -match '"DisabledWakeDevices"\s*:\s*\[' -and $stateRaw -match '"ServicesStoppedByUs"\s*:\s*\[' -and $stateRaw -match '"AdvancedColorStates"\s*:\s*\[')
    ShortcutExists = Test-Path -LiteralPath $shortcutPath
    IconFilesExist = $iconFilesExist
    IconFilesMatchPackage = $iconFilesMatchPackage
    ShortcutUsesOpenSynapseIcon = $shortcutUsesOpenSynapseIcon
    ShortcutUsesOpenSynapseIdentity = $shortcutUsesOpenSynapseIdentity
    PostStartApplyFailures = $postStartFailures
    InstalledMatchesPackage = $packageMatches
    CompletedAt = (Get-Date).ToString('o')
}

if (-not ($result.TaskState -eq 'Running' -and $result.TaskRunLevel -eq 'Highest' -and $result.TaskActionProtected -and $result.TaskLogonDelay -eq 'PT30S' -and $result.AllowBattery -and
    $result.DontStopOnBattery -and $result.TrayAliveAndMatched -and $result.TrayDpiMode -eq 'PerMonitorV2' -and
    $result.TrayDpiAwareness -eq 2 -and $result.TrayAppUserModelId -eq $script:AppUserModelId -and
    $result.StateVersion -eq 10 -and $result.ConfigVersion -eq 11 -and $result.RuntimeVersion -eq '0.2.0-preview.1' -and $result.ActiveProfileAllowed -and
    $result.InstalledPowerValuesVerified -eq 78 -and $result.EmptyStateArraysValid -and $result.ShortcutExists -and
    $result.IconFilesExist -and $result.IconFilesMatchPackage -and $result.ShortcutUsesOpenSynapseIcon -and $result.ShortcutUsesOpenSynapseIdentity -and
    $result.PostStartApplyFailures -eq 0 -and $result.InstalledMatchesPackage)) {
    throw 'One or more live installation assertions failed.'
}

if ($ResultPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath), ($result | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false)) }
$result | Format-List
