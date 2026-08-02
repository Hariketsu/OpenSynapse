[CmdletBinding()]
param(
    [ValidateSet('Run', 'Open', 'Install', 'Uninstall', 'Status', 'Apply', 'SelfTest')]
    [string]$Mode = 'Run',

    [ValidateSet('Auto', 'Hyper', 'Balance', 'Quiet', 'Experiment')]
    [string]$Profile = 'Auto',

    [string]$CaptureUiPath = '',

    [ValidateSet('Dashboard', 'Game', 'Settings', 'Diagnostics', 'About')]
    [string]$CaptureUiPage = 'Dashboard'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:AppName = 'OpenSynapse'
$script:AppVersion = '2.5.0'
$script:AppUserModelId = 'OpenSynapse.Desktop'
$script:TaskName = 'OpenSynapse'
$script:LegacyAgentTaskName = 'OpenSynapse Agent'
$script:LegacyPowerPilotTaskName = 'PowerPilot'
$script:ProgramDir = Join-Path $env:ProgramFiles $script:AppName
$script:DataDir = if ($Mode -eq 'SelfTest') {
    Join-Path ([IO.Path]::GetTempPath()) 'OpenSynapse-SelfTest'
}
else {
    Join-Path $env:LOCALAPPDATA $script:AppName
}
$script:InstalledScript = Join-Path $script:ProgramDir 'OpenSynapse.ps1'
$script:InstalledNative = Join-Path $script:ProgramDir 'OpenSynapse.Native.cs'
$script:SourceDir = Split-Path -Parent $PSCommandPath
$script:SourceNative = Join-Path $script:SourceDir 'OpenSynapse.Native.cs'
$script:InstalledAppIcon = Join-Path $script:ProgramDir 'OpenSynapse.App.ico'
$script:InstalledTrayIcon = Join-Path $script:ProgramDir 'OpenSynapse.Tray.ico'
$script:InstalledAppPng = Join-Path $script:ProgramDir 'OpenSynapse.App.png'
$script:SourceAppIcon = Join-Path $script:SourceDir 'assets\OpenSynapse.App.ico'
$script:SourceTrayIcon = Join-Path $script:SourceDir 'assets\OpenSynapse.Tray.ico'
$script:SourceAppPng = Join-Path $script:SourceDir 'assets\OpenSynapse.App.png'
$script:ConfigPath = Join-Path $script:DataDir 'config.json'
$script:StatePath = Join-Path $script:DataDir 'state.json'
$script:RuntimePath = Join-Path $script:DataDir 'runtime.json'
$script:ShowRequestPath = Join-Path $script:DataDir 'show.request'
$script:LogPath = Join-Path $script:DataDir 'OpenSynapse.log'
$script:TelemetryPath = Join-Path $script:DataDir 'telemetry.jsonl'
$script:ExperimentReportDir = Join-Path $script:DataDir 'experiment-reports'
$script:TelemetrySchemaVersion = 6
$script:SupplyClassifierVersion = 2
$script:ShortcutPath = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\OpenSynapse.lnk'
$script:LegacyDotNetConfigDetected = $false
$script:RunKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$script:DesktopSnipasteExecutable = Join-Path $env:ProgramFiles 'Snipaste\Snipaste.exe'
$script:SnipasteStoreStartupTaskKey = 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\45479liulios.17062D84F7C46_p7pnf6hceqser\SnipasteStartupTask'
$script:PowerCfg = Join-Path $env:SystemRoot 'System32\powercfg.exe'
$script:HighPowerAdapterThresholdW = 130.0
$script:LowPowerAdapterThresholdW = 85.0
$script:AdapterProbeIntervalSeconds = 300
$script:AdapterConfirmationIntervalSeconds = 7
$script:AdapterLowConfirmationSamples = 3
$script:AdapterStartupWarmupSeconds = 30
$script:PowerEventProbeDelaySeconds = 4
$script:PlanVerificationIntervalSeconds = 30
$script:CachedSupplyType = $null
$script:CachedAdapterLimitW = $null
$script:LastAdapterProbe = [DateTime]::MinValue
$script:AdapterProbeSequence = 0
$script:StableAcSupplyType = $null
$script:PendingLowPowerSamples = 0
$script:PendingLowPowerSince = [DateTime]::MinValue
$script:LastStabilizedProbeSequence = -1
$script:SupplyStabilizerStartedAt = Get-Date
$script:NextAdapterConfirmationProbe = [DateTime]::MaxValue
$script:LastDynamicRefreshDeferredLog = [DateTime]::MinValue
$script:LastGpuTelemetryIntervalMs = 0
$script:LastHardwareTelemetry = $null
$script:LastHardwareTelemetryAt = [DateTime]::MinValue
$script:LastNvidiaHardwareSnapshot = $null
$script:LastNvidiaHardwareSnapshotAt = [DateTime]::MinValue
$script:LastDisplayTelemetry = $null
$script:LastDisplayTelemetryAt = [DateTime]::MinValue
$script:LastExperimentVerificationAt = [DateTime]::MinValue
$script:LastPolicyVerification = [pscustomobject][ordered]@{
    Profile = ''; PlanVerified = $false; RefreshPolicy = ''; EffectiveRefreshPolicy = ''
    RefreshVerified = $null; RefreshWarning = ''; VerifiedAtUtc = ''
}
$script:LastAppliedQuietCpuMax = $null
$script:LastAppliedHyperCpuPolicy = $null
$script:BatteryPowerSamples = New-Object Collections.Generic.List[object]
$script:BatteryDischargeEmaW = $null
$script:LastBatteryTrendSampleAt = [DateTime]::MinValue
$script:LastBatteryTrendSource = ''
$script:LastPowerEventCount = 0
$script:PendingPowerProbeAt = [DateTime]::MaxValue
$script:PowerEventsObserved = 0
$script:PowerEventsCoalesced = 0
$script:PowerEventTriggeredProbes = 0
$script:QuietProcessGuard = @{}

$script:Guids = @{
    Balanced             = '381b4222-f694-41f0-9685-ff5bb260df2e'
    Processor            = '54533251-82be-4824-96c1-47b60b740d00'
    ProcessorMinimum     = '893dee8e-2bef-41e0-89c6-b55d0929964c'
    ProcessorMinimum1    = '893dee8e-2bef-41e0-89c6-b55d0929964d'
    ProcessorMinimum2    = '893dee8e-2bef-41e0-89c6-b55d0929964e'
    ProcessorMaximum     = 'bc5038f7-23e0-4960-96da-33abaf5935ec'
    ProcessorMaximum1    = 'bc5038f7-23e0-4960-96da-33abaf5935ed'
    ProcessorMaximum2    = 'bc5038f7-23e0-4960-96da-33abaf5935ee'
    ProcessorEpp         = '36687f9e-e3a5-4dbf-b1dc-15eb381c6863'
    ProcessorEpp1        = '36687f9e-e3a5-4dbf-b1dc-15eb381c6864'
    ProcessorEpp2        = '36687f9e-e3a5-4dbf-b1dc-15eb381c6865'
    ProcessorBoost       = 'be337238-0d82-4146-a960-4f3749d470c7'
    ProcessorBoostPolicy = '45bcc044-d885-43e2-8605-ee0ec6e96b59'
    ProcessorAutonomous  = '8baa4a8a-14c6-4451-8e8b-14bdbd197537'
    ProcessorIncrease    = '465e1f50-b610-473a-ab58-00d1077dc418'
    ProcessorIncrease1   = '465e1f50-b610-473a-ab58-00d1077dc419'
    ProcessorScheduling  = '93b8b6dc-0698-4d1c-9ee4-0644e900c85d'
    ProcessorShortScheduling = 'bae08b81-2d5e-4688-ad6a-13243356654b'
    CoolingPolicy        = '94d3a615-a899-4ac5-ae2b-e4d8f634367f'
    Wireless             = '19cbb8fa-5279-450e-9fac-8a3d5fedd0c1'
    WirelessPowerSaving  = '12bbebe6-58d6-4636-95bb-3217ef867c1a'
    PciExpress           = '501a4d13-42af-4429-9fd1-a8218c268e20'
    PciLinkState         = 'ee12f906-d277-404b-b6da-e5fa1a576df5'
    Display              = '7516b95f-f776-4464-8c53-06167f40cc99'
    DisplayTimeout       = '3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e'
    Usb                  = '2a737441-1930-4402-8d77-b2bebba308a3'
    UsbSelectiveSuspend  = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'
    EnergySaver          = 'de830923-a562-41af-a086-e3a2c6bad2da'
    EnergySaverThreshold = 'e69653ca-cf7f-4f05-aa73-cb833fa90ad4'
    Sleep                = '238c9fa8-0aad-41ed-83f4-97be242c8f20'
    StandbyIdle          = '29f6c1db-86da-48c5-9fdb-f2b67b1f44da'
    HibernateIdle        = '9d7815a6-7ee4-497e-8888-515a05f02364'
    Buttons              = '4f971e89-eebd-4455-a8de-9e59040e7347'
    LidAction            = '5ca83367-6e45-459f-a27b-476b1d01c936'
    ProcessorMinCores   = '0cc5b647-c1df-4637-891a-dec35c318583'
    ProcessorMinCores1  = '0cc5b647-c1df-4637-891a-dec35c318584'
    Graphics            = '5fb4938d-1ee8-4b0f-9a3c-5036b0ab995c'
    GpuPreference       = 'dd848b2a-8a5d-4451-9ae2-39cd41658f6c'
    WakeTimers          = 'bd3b718a-0680-4d9d-8ab2-e1d2b4ac806d'
    ConnectivityStandby = 'f15576e8-98b7-4186-b944-eafa664402d9'
    NoSubgroup          = 'fea3413e-7e05-4911-9a71-700331f1c294'
}

$script:DefaultQuietProcesses = @(
    'NVIDIA Overlay',
    'MSIAfterburner',
    'HWiNFO64',
    'HWiNFO32',
    'DownloadSDKServer',
    'ArmouryCrate.UserSessionHelper',
    'ArmourySocketServer',
    'ArmourySwAgent',
    'asus_framework'
)

$script:DefaultBatteryHighDrainIgnoredProcesses = @(
    'Idle',
    'System',
    'Registry',
    'Secure System',
    'Memory Compression',
    'Interrupts',
    'powershell',
    'pwsh',
    'OpenSynapse',
    'OpenSynapse.App',
    'OpenSynapse.Agent',
    'conhost',
    'csrss',
    'wininit',
    'winlogon',
    'services',
    'lsass',
    'svchost',
    'dwm'
)

$script:DefaultQuietServices = @(
    'ArmouryCrateService',
    'ROG Live Service',
    'AsusROGLSLService',
    'ArmouryCrateDownloadTool',
    'asus',
    'asusm'
)

$script:DefaultWakePatterns = @(
    'MediaTek Wi-Fi',
    'HID-compliant mouse',
    'USB4'
)

function Write-AppLog {
    param([string]$Message)

    try {
        if (-not (Test-Path -LiteralPath $script:DataDir)) {
            [IO.Directory]::CreateDirectory($script:DataDir) | Out-Null
        }
        if ((Test-Path -LiteralPath $script:LogPath) -and
            (Get-Item -LiteralPath $script:LogPath).Length -gt 1048576) {
            $old = $script:LogPath + '.old'
            Move-Item -LiteralPath $script:LogPath -Destination $old -Force
        }
        $line = '{0} [{1}] {2}{3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $PID, $Message, [Environment]::NewLine
        [IO.File]::AppendAllText($script:LogPath, $line, [Text.UTF8Encoding]::new($false))
    }
    catch { }
}

function Write-JsonFile {
    param([string]$Path, [object]$Value)
    $directory = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory)) {
        [IO.Directory]::CreateDirectory($directory) | Out-Null
    }
    $json = $Value | ConvertTo-Json -Depth 8
    $temporaryPath = "$Path.$PID.$([Guid]::NewGuid().ToString('N')).tmp"
    $backupPath = "$Path.bak"
    try {
        [IO.File]::WriteAllText($temporaryPath, $json, [Text.UTF8Encoding]::new($false))
        if (Test-Path -LiteralPath $Path) {
            try { [IO.File]::Replace($temporaryPath, $Path, $backupPath, $true) }
            catch [PlatformNotSupportedException] {
                Copy-Item -LiteralPath $Path -Destination $backupPath -Force
                Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
            }
        }
        else {
            Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
        }
    }
    finally {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json }
    catch {
        Write-AppLog "Invalid JSON at ${Path}: $($_.Exception.Message)"
        $backupPath = "$Path.bak"
        if (Test-Path -LiteralPath $backupPath) {
            try {
                $recovered = Get-Content -Raw -LiteralPath $backupPath | ConvertFrom-Json
                Write-AppLog "Recovered JSON from backup: $backupPath"
                return $recovered
            }
            catch { Write-AppLog "Invalid JSON backup at ${backupPath}: $($_.Exception.Message)" }
        }
        return $null
    }
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-ElevatedOperation {
    param([string]$Operation, [string]$RequestedProfile = 'Auto')
    $args = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Mode {1} -Profile {2}' -f $PSCommandPath, $Operation, $RequestedProfile
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $args -Verb RunAs -Wait -PassThru
    return $process.ExitCode
}

function Invoke-PowerCfg {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$AllowFailure
    )

    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & $script:PowerCfg @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    $text = ($output | Out-String).Trim()
    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "powercfg $($Arguments -join ' ') failed ($exitCode): $text"
    }
    if ($exitCode -ne 0) {
        Write-AppLog "Optional powercfg failed: $($Arguments -join ' ') :: $text"
    }
    $script:LastPowerCfgExitCode = $exitCode
    return $text
}

function Get-ActivePlanGuid {
    $text = Invoke-PowerCfg @('/getactivescheme')
    $match = [regex]::Match($text, '[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}')
    if (-not $match.Success) { throw 'Cannot determine the active power plan.' }
    return $match.Value.ToLowerInvariant()
}

function Test-PlanExists {
    param([string]$Guid)
    if ([string]::IsNullOrWhiteSpace($Guid)) { return $false }
    return (Invoke-PowerCfg @('/list')).IndexOf($Guid, [StringComparison]::OrdinalIgnoreCase) -ge 0
}

function New-CustomPlan {
    param([string]$Name, [string]$Description)
    $text = Invoke-PowerCfg @('/duplicatescheme', $script:Guids.Balanced)
    $match = [regex]::Match($text, '[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}')
    if (-not $match.Success) { throw "Cannot parse duplicated plan GUID: $text" }
    $guid = $match.Value.ToLowerInvariant()
    Invoke-PowerCfg @('/changename', $guid, $Name, $Description) | Out-Null
    return $guid
}

function Set-PlanValue {
    param(
        [string]$PlanGuid,
        [ValidateSet('AC', 'DC')][string]$Source,
        [string]$Subgroup,
        [string]$Setting,
        [int]$Value,
        [switch]$Optional
    )
    $verb = if ($Source -eq 'AC') { '/setacvalueindex' } else { '/setdcvalueindex' }
    Invoke-PowerCfg @($verb, $PlanGuid, $Subgroup, $Setting, [string]$Value) -AllowFailure:$Optional | Out-Null
}

function Set-PlanPair {
    param(
        [string]$PlanGuid,
        [string]$Subgroup,
        [string]$Setting,
        [int]$AcValue,
        [int]$DcValue,
        [switch]$Optional
    )
    Set-PlanValue $PlanGuid AC $Subgroup $Setting $AcValue -Optional:$Optional
    Set-PlanValue $PlanGuid DC $Subgroup $Setting $DcValue -Optional:$Optional
}

function Set-ProfilePolicy {
    param([ValidateSet('Hyper', 'Balance', 'Quiet', 'Experiment')][string]$Name, [string]$PlanGuid)

    if ($Name -eq 'Hyper') {
        Set-PlanPair $PlanGuid $script:Guids.Processor $script:Guids.ProcessorMinimum 5 5
        Set-PlanPair $PlanGuid $script:Guids.Processor $script:Guids.ProcessorMinimum1 5 5 -Optional
        Set-PlanPair $PlanGuid $script:Guids.Processor $script:Guids.ProcessorMinimum2 5 5 -Optional
        Set-PlanPair $PlanGuid $script:Guids.Processor $script:Guids.ProcessorMaximum 100 100
        Set-PlanPair $PlanGuid $script:Guids.Processor $script:Guids.ProcessorMaximum1 100 100 -Optional
        Set-PlanPair $PlanGuid $script:Guids.Processor $script:Guids.ProcessorMaximum2 100 100 -Optional
        Set-PlanPair $PlanGuid $script:Guids.Processor $script:Guids.ProcessorEpp 0 0 -Optional
        Set-PlanPair $PlanGuid $script:Guids.Processor $script:Guids.ProcessorEpp1 0 0 -Optional
        Set-PlanPair $PlanGuid $script:Guids.Processor $script:Guids.ProcessorEpp2 0 0 -Optional
        Set-PlanPair $PlanGuid $script:Guids.Processor $script:Guids.ProcessorBoost 2 2 -Optional
        Set-PlanPair $PlanGuid $script:Guids.Processor $script:Guids.ProcessorBoostPolicy 100 100 -Optional
        Set-PlanPair $PlanGuid $script:Guids.Processor $script:Guids.ProcessorAutonomous 1 1 -Optional
        Set-PlanPair $PlanGuid $script:Guids.Processor $script:Guids.ProcessorIncrease 2 2 -Optional
        Set-PlanPair $PlanGuid $script:Guids.Processor $script:Guids.ProcessorIncrease1 3 3 -Optional
        Set-PlanPair $PlanGuid $script:Guids.Processor $script:Guids.CoolingPolicy 1 1 -Optional
        Set-PlanPair $PlanGuid $script:Guids.Processor $script:Guids.ProcessorMinCores 100 100 -Optional
        Set-PlanPair $PlanGuid $script:Guids.Processor $script:Guids.ProcessorMinCores1 0 0 -Optional
        Set-PlanPair $PlanGuid $script:Guids.Wireless $script:Guids.WirelessPowerSaving 0 0 -Optional
        Set-PlanPair $PlanGuid $script:Guids.PciExpress $script:Guids.PciLinkState 0 0 -Optional
        Set-PlanPair $PlanGuid $script:Guids.Graphics $script:Guids.GpuPreference 0 0 -Optional
        Set-PlanPair $PlanGuid $script:Guids.Display $script:Guids.DisplayTimeout 900 300
        Set-PlanPair $PlanGuid $script:Guids.Usb $script:Guids.UsbSelectiveSuspend 0 0 -Optional
        Set-PlanPair $PlanGuid $script:Guids.EnergySaver $script:Guids.EnergySaverThreshold 0 0 -Optional
        Set-PlanPair $PlanGuid $script:Guids.Sleep $script:Guids.StandbyIdle 0 900
        Set-PlanPair $PlanGuid $script:Guids.Sleep $script:Guids.HibernateIdle 0 3600
        Set-PlanPair $PlanGuid $script:Guids.Buttons $script:Guids.LidAction 1 1
    }
    elseif ($Name -in @('Balance', 'Experiment')) {
        Set-PlanPair $PlanGuid $script:Guids.Processor $script:Guids.ProcessorMinimum 5 5
        Set-PlanPair $PlanGuid $script:Guids.Processor $script:Guids.ProcessorMaximum 100 100
        Set-PlanPair $PlanGuid $script:Guids.Processor $script:Guids.ProcessorEpp 50 70 -Optional
        Set-PlanPair $PlanGuid $script:Guids.Processor $script:Guids.ProcessorBoost 3 3 -Optional
        Set-PlanPair $PlanGuid $script:Guids.Processor $script:Guids.CoolingPolicy 1 0 -Optional
        Set-PlanPair $PlanGuid $script:Guids.Wireless $script:Guids.WirelessPowerSaving 1 2 -Optional
        Set-PlanPair $PlanGuid $script:Guids.PciExpress $script:Guids.PciLinkState 1 2 -Optional
        Set-PlanPair $PlanGuid $script:Guids.Display $script:Guids.DisplayTimeout 600 300
        Set-PlanPair $PlanGuid $script:Guids.Usb $script:Guids.UsbSelectiveSuspend 1 1 -Optional
        Set-PlanPair $PlanGuid $script:Guids.EnergySaver $script:Guids.EnergySaverThreshold 0 50 -Optional
        Set-PlanPair $PlanGuid $script:Guids.Sleep $script:Guids.StandbyIdle 900 600
        Set-PlanPair $PlanGuid $script:Guids.Sleep $script:Guids.HibernateIdle 3600 1800
        Set-PlanPair $PlanGuid $script:Guids.Buttons $script:Guids.LidAction 1 2
        if ($Name -eq 'Experiment') {
            # Prevent an unattended research session from changing display or sleep state.
            # CPU behavior stays close to Balance to avoid heat-driven timing drift.
            Set-PlanPair $PlanGuid $script:Guids.Display $script:Guids.DisplayTimeout 0 0
            Set-PlanPair $PlanGuid $script:Guids.Sleep $script:Guids.StandbyIdle 0 0
            Set-PlanPair $PlanGuid $script:Guids.Sleep $script:Guids.HibernateIdle 0 0
            Set-PlanPair $PlanGuid $script:Guids.Processor $script:Guids.ProcessorEpp 40 60 -Optional
            Set-PlanPair $PlanGuid $script:Guids.Processor $script:Guids.CoolingPolicy 1 1 -Optional
        }
    }
    else {
        Set-PlanPair $PlanGuid $script:Guids.Processor $script:Guids.ProcessorMinimum 5 5
        Set-PlanValue $PlanGuid DC $script:Guids.Processor $script:Guids.ProcessorMinimum1 5 -Optional
        Set-PlanValue $PlanGuid DC $script:Guids.Processor $script:Guids.ProcessorMinimum2 5 -Optional
        Set-PlanPair $PlanGuid $script:Guids.Processor $script:Guids.ProcessorMaximum 80 65
        Set-PlanValue $PlanGuid DC $script:Guids.Processor $script:Guids.ProcessorMaximum1 65 -Optional
        Set-PlanValue $PlanGuid DC $script:Guids.Processor $script:Guids.ProcessorMaximum2 65 -Optional
        Set-PlanPair $PlanGuid $script:Guids.Processor $script:Guids.ProcessorEpp 90 90 -Optional
        Set-PlanValue $PlanGuid DC $script:Guids.Processor $script:Guids.ProcessorEpp1 90 -Optional
        Set-PlanValue $PlanGuid DC $script:Guids.Processor $script:Guids.ProcessorEpp2 90 -Optional
        Set-PlanPair $PlanGuid $script:Guids.Processor $script:Guids.ProcessorBoost 0 0 -Optional
        Set-PlanValue $PlanGuid DC $script:Guids.Processor $script:Guids.ProcessorAutonomous 1 -Optional
        Set-PlanValue $PlanGuid DC $script:Guids.Processor $script:Guids.ProcessorScheduling 4 -Optional
        Set-PlanValue $PlanGuid DC $script:Guids.Processor $script:Guids.ProcessorShortScheduling 4 -Optional
        Set-PlanPair $PlanGuid $script:Guids.Processor $script:Guids.CoolingPolicy 0 0 -Optional
        Set-PlanPair $PlanGuid $script:Guids.Processor $script:Guids.ProcessorMinCores 10 0 -Optional
        Set-PlanPair $PlanGuid $script:Guids.Processor $script:Guids.ProcessorMinCores1 10 0 -Optional
        Set-PlanPair $PlanGuid $script:Guids.Wireless $script:Guids.WirelessPowerSaving 3 3 -Optional
        Set-PlanPair $PlanGuid $script:Guids.PciExpress $script:Guids.PciLinkState 2 2 -Optional
        Set-PlanPair $PlanGuid $script:Guids.Graphics $script:Guids.GpuPreference 1 1 -Optional
        Set-PlanPair $PlanGuid $script:Guids.Display $script:Guids.DisplayTimeout 300 120
        Set-PlanPair $PlanGuid $script:Guids.Usb $script:Guids.UsbSelectiveSuspend 1 1 -Optional
        Set-PlanPair $PlanGuid $script:Guids.EnergySaver $script:Guids.EnergySaverThreshold 0 100 -Optional
        Set-PlanPair $PlanGuid $script:Guids.Sleep $script:Guids.StandbyIdle 600 180
        Set-PlanPair $PlanGuid $script:Guids.Sleep $script:Guids.HibernateIdle 1800 900
        Set-PlanPair $PlanGuid $script:Guids.Sleep $script:Guids.WakeTimers 0 0 -Optional
        Set-PlanPair $PlanGuid $script:Guids.NoSubgroup $script:Guids.ConnectivityStandby 0 0 -Optional
        Set-PlanPair $PlanGuid $script:Guids.Buttons $script:Guids.LidAction 1 2
    }
}

function Get-DefaultConfig {
    $applicationRules = @(
        foreach ($name in @('blender', 'Resolve', 'Adobe Premiere Pro', 'AfterFX', 'UnrealEditor', 'UE4Editor', 'Unity', '3dsmax', 'maya', 'Cinebench', 'occt', 'FurMark', 'FurMark_GUI')) {
            [pscustomobject][ordered]@{ ProcessName = $name; Profile = 'Hyper'; Scope = 'Foreground'; Enabled = $true }
        }
        foreach ($name in @('Codex', 'Code', 'devenv', 'WINWORD', 'EXCEL', 'POWERPNT', 'Acrobat', 'AcroRd32')) {
            [pscustomobject][ordered]@{ ProcessName = $name; Profile = 'Balance'; Scope = 'Foreground'; Enabled = $true }
        }
    )
    return [pscustomobject][ordered]@{
        Version = 14
        Selection = 'Auto'
        SmartAutomationEnabled = $true
        SmartHighPowerCpuEnter = 45
        SmartHighPowerCpuExit = 25
        SmartPortableCpuEnter = 35
        SmartPortableCpuExit = 18
        SmartLoadEnterSamples = 3
        SmartAppEnterSamples = 2
        SmartExitSamples = 12
        SmartMinimumDwellSeconds = 30
        SmartAppCpuFloor = 8
        SmartGpuEnter = 20
        SmartGpuExit = 5
        SmartFullscreenEnabled = $true
        SmartFullscreenCpuFloor = 15
        SmartFullscreenGpuFloor = 15
        SmartIgnoredFullscreenProcesses = @('LockApp', 'LogonUI', 'explorer', 'ShellExperienceHost', 'StartMenuExperienceHost', 'SearchHost', 'SearchApp', 'TextInputHost', 'SystemSettings', 'dwm', 'Idle')
        SmartBrowserProcesses = @('chrome', 'msedge', 'firefox', 'brave', 'opera', 'vivaldi')
        SmartBrowserFullscreenCpuFloor = 45
        SmartBrowserFullscreenGpuFloor = 20
        SmartBrowserFullscreenSamples = 3
        SmartHyperProcessNames = @('blender', 'Resolve', 'Adobe Premiere Pro', 'AfterFX', 'UnrealEditor', 'UE4Editor', 'Unity', '3dsmax', 'maya', 'Cinebench', 'occt', 'FurMark', 'FurMark_GUI')
        SmartBalanceProcessNames = @('Codex', 'Code', 'devenv', 'WINWORD', 'EXCEL', 'POWERPNT', 'Acrobat', 'AcroRd32')
        ApplicationRules = $applicationRules
        DgpuLeakMemoryMb = 128
        DgpuLeakUtilizationPercent = 1
        DgpuLeakMinimumSamples = 6
        DgpuActivityDischargeThresholdW = 8
        GpuTelemetryHighPowerIntervalSeconds = 5
        GpuTelemetryPortableIntervalSeconds = 10
        GpuTelemetryManualQuietIntervalSeconds = 20
        BatteryHighDrainAlertsEnabled = $true
        BatteryHighDrainSampleSeconds = 30
        BatteryHighDrainCpuPercent = 15
        BatteryHighDrainMinimumSamples = 2
        BatteryHighDrainMinimumDischargeW = 14
        BatteryHighDrainCooldownMinutes = 30
        BatteryHighDrainMaximumProcesses = 3
        BatteryHighDrainIgnoredProcesses = @($script:DefaultBatteryHighDrainIgnoredProcesses)
        HyperCpuPolicy = 'Sustained'
        CloseHighDrainAppsInQuiet = $true
        QuietProcessNames = @($script:DefaultQuietProcesses)
        ManageAsusServices = $true
        QuietServiceNames = @($script:DefaultQuietServices)
        ProcessMaintenanceSeconds = 180
        QuietProcessRestartWindowSeconds = 600
        QuietProcessCooldownSeconds = 1800
        AdaptiveQuietCpu = $true
        QuietCpuMaxHighBattery = 65
        QuietCpuMaxMediumBattery = 60
        QuietCpuMaxLowBattery = 50
        QuietCpuMediumThreshold = 70
        QuietCpuLowThreshold = 30
        ManageWakeDevices = $true
        QuietWakeDevicePatterns = @($script:DefaultWakePatterns)
        DisplayScalingEnabled = $true
        InternalScale = 150
        ExternalScale = 125
        ManageRefreshRate = $true
        QuietRefreshRate = 60
        RefreshPolicy = 'Auto'
        ExperimentRefreshRate = 240
        ExperimentVerificationSeconds = 15
        ExperimentAutoReport = $true
        ManageAdvancedColor = $true
        ManageBrightness = $true
        QuietBrightness = 40
        AdaptiveQuietBrightness = $true
        BalanceBrightness = 60
        BalanceBatteryThreshold = 50
        SeamlessModeSwitching = $true
    }
}

function Add-DefaultProperty {
    param([object]$Object, [string]$Name, [object]$Value)
    if ($null -eq $Object.PSObject.Properties[$Name]) {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Get-ObjectProperty {
    param([AllowNull()][object]$Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    foreach ($property in $Object.PSObject.Properties) {
        if ([string]::Equals($property.Name, $Name, [StringComparison]::OrdinalIgnoreCase)) {
            return $property
        }
    }
    return $null
}

function Convert-LegacyDotNetConfig {
    param([AllowNull()][object]$Config)

    if ($null -eq $Config -or
        $null -eq (Get-ObjectProperty $Config 'SchemaVersion') -or
        $null -ne (Get-ObjectProperty $Config 'Version')) {
        return $Config
    }

    $migrated = Get-DefaultConfig
    $directMappings = [ordered]@{
        'BalancedBatteryThresholdPercent' = 'BalanceBatteryThreshold'
        'ManageAdvancedColor' = 'ManageAdvancedColor'
        'ManageBrightness' = 'ManageBrightness'
        'ManageDisplayScaling' = 'DisplayScalingEnabled'
        'InternalDisplayScalePercent' = 'InternalScale'
        'ExternalDisplayScalePercent' = 'ExternalScale'
        'BalancedBrightnessPercent' = 'BalanceBrightness'
        'QuietBrightnessPercent' = 'QuietBrightness'
        'QuietRefreshRateHz' = 'QuietRefreshRate'
        'ManageWakeDevices' = 'ManageWakeDevices'
        'QuietWakeDeviceNames' = 'QuietWakeDevicePatterns'
        'SmartAutomationEnabled' = 'SmartAutomationEnabled'
        'SmartHighPowerCpuEnter' = 'SmartHighPowerCpuEnter'
        'SmartHighPowerCpuExit' = 'SmartHighPowerCpuExit'
        'SmartPortableCpuEnter' = 'SmartPortableCpuEnter'
        'SmartPortableCpuExit' = 'SmartPortableCpuExit'
        'SmartLoadEnterSamples' = 'SmartLoadEnterSamples'
        'SmartAppEnterSamples' = 'SmartAppEnterSamples'
        'SmartExitSamples' = 'SmartExitSamples'
        'SmartMinimumDwellSeconds' = 'SmartMinimumDwellSeconds'
        'SmartAppCpuFloor' = 'SmartAppCpuFloor'
        'SmartGpuEnter' = 'SmartGpuEnter'
        'SmartGpuExit' = 'SmartGpuExit'
        'SmartFullscreenEnabled' = 'SmartFullscreenEnabled'
        'SmartFullscreenCpuFloor' = 'SmartFullscreenCpuFloor'
        'SmartFullscreenGpuFloor' = 'SmartFullscreenGpuFloor'
        'SmartIgnoredFullscreenProcesses' = 'SmartIgnoredFullscreenProcesses'
        'SmartBrowserProcesses' = 'SmartBrowserProcesses'
        'SmartBrowserFullscreenCpuFloor' = 'SmartBrowserFullscreenCpuFloor'
        'SmartBrowserFullscreenGpuFloor' = 'SmartBrowserFullscreenGpuFloor'
        'SmartBrowserFullscreenSamples' = 'SmartBrowserFullscreenSamples'
        'SmartHyperProcessNames' = 'SmartHyperProcessNames'
        'SmartBalanceProcessNames' = 'SmartBalanceProcessNames'
        'DgpuLeakMemoryMb' = 'DgpuLeakMemoryMb'
        'DgpuLeakUtilizationPercent' = 'DgpuLeakUtilizationPercent'
        'DgpuLeakMinimumSamples' = 'DgpuLeakMinimumSamples'
        'DgpuActivityDischargeThresholdW' = 'DgpuActivityDischargeThresholdW'
        'GpuTelemetryHighPowerIntervalSeconds' = 'GpuTelemetryHighPowerIntervalSeconds'
        'GpuTelemetryPortableIntervalSeconds' = 'GpuTelemetryPortableIntervalSeconds'
        'GpuTelemetryManualQuietIntervalSeconds' = 'GpuTelemetryManualQuietIntervalSeconds'
        'BatteryHighDrainAlertsEnabled' = 'BatteryHighDrainAlertsEnabled'
        'BatteryHighDrainSampleSeconds' = 'BatteryHighDrainSampleSeconds'
        'BatteryHighDrainCpuPercent' = 'BatteryHighDrainCpuPercent'
        'BatteryHighDrainMinimumSamples' = 'BatteryHighDrainMinimumSamples'
        'BatteryHighDrainMinimumDischargeW' = 'BatteryHighDrainMinimumDischargeW'
        'BatteryHighDrainCooldownMinutes' = 'BatteryHighDrainCooldownMinutes'
        'BatteryHighDrainMaximumProcesses' = 'BatteryHighDrainMaximumProcesses'
        'BatteryHighDrainIgnoredProcesses' = 'BatteryHighDrainIgnoredProcesses'
        'HyperCpuPolicy' = 'HyperCpuPolicy'
        'AdaptiveQuietCpu' = 'AdaptiveQuietCpu'
        'QuietCpuMaxHighBattery' = 'QuietCpuMaxHighBattery'
        'QuietCpuMaxMediumBattery' = 'QuietCpuMaxMediumBattery'
        'QuietCpuMaxLowBattery' = 'QuietCpuMaxLowBattery'
        'QuietCpuMediumThreshold' = 'QuietCpuMediumThreshold'
        'QuietCpuLowThreshold' = 'QuietCpuLowThreshold'
        'AdaptiveQuietBrightness' = 'AdaptiveQuietBrightness'
        'SeamlessModeSwitching' = 'SeamlessModeSwitching'
        'ProcessMaintenanceSeconds' = 'ProcessMaintenanceSeconds'
        'QuietProcessRestartWindowSeconds' = 'QuietProcessRestartWindowSeconds'
        'QuietProcessCooldownSeconds' = 'QuietProcessCooldownSeconds'
    }
    foreach ($sourceName in $directMappings.Keys) {
        $sourceProperty = Get-ObjectProperty $Config $sourceName
        if ($null -ne $sourceProperty) {
            $targetName = [string]$directMappings[$sourceName]
            $migrated.$targetName = $sourceProperty.Value
        }
    }

    $selectionProperty = Get-ObjectProperty $Config 'Selection'
    if ($null -ne $selectionProperty) {
        $migrated.Selection = switch ([string]$selectionProperty.Value) {
            'Performance' { 'Hyper'; break }
            'Balanced' { 'Balance'; break }
            'Hyper' { 'Hyper'; break }
            'Balance' { 'Balance'; break }
            'Quiet' { 'Quiet'; break }
            'Experiment' { 'Experiment'; break }
            default { 'Auto' }
        }
    }

    $refreshProperty = Get-ObjectProperty $Config 'RefreshPolicy'
    if ($null -ne $refreshProperty) {
        $migrated.RefreshPolicy = switch ([string]$refreshProperty.Value) {
            'Auto' { 'Auto'; break }
            'FollowMode' { 'Auto'; break }
            'FollowProfile' { 'Auto'; break }
            'Maximum' { 'Fixed240'; break }
            'Fixed60' { 'Fixed60'; break }
            'Fixed120' { 'Auto'; break }
            'Fixed240' { 'Fixed240'; break }
            'DynamicNative' { 'Auto'; break }
            'Unmanaged' { 'Unmanaged'; break }
            default { 'Auto' }
        }
        $migrated.ManageRefreshRate = ([string]$migrated.RefreshPolicy -ne 'Unmanaged')
    }

    $rulesProperty = Get-ObjectProperty $Config 'ApplicationRules'
    if ($null -ne $rulesProperty) {
        $rules = New-Object Collections.Generic.List[object]
        foreach ($rule in @($rulesProperty.Value)) {
            if ($null -eq $rule) { continue }
            $processProperty = Get-ObjectProperty $rule 'ProcessName'
            $profileProperty = Get-ObjectProperty $rule 'Profile'
            $scopeProperty = Get-ObjectProperty $rule 'Scope'
            if ($null -eq $processProperty -or $null -eq $profileProperty -or $null -eq $scopeProperty) { continue }
            $profileName = switch ([string]$profileProperty.Value) {
                'Performance' { 'Hyper'; break }
                'Balanced' { 'Balance'; break }
                'Hyper' { 'Hyper'; break }
                'Balance' { 'Balance'; break }
                'Quiet' { 'Quiet'; break }
                default { '' }
            }
            if (-not $profileName) { continue }
            $enabledProperty = Get-ObjectProperty $rule 'Enabled'
            $rules.Add([pscustomobject][ordered]@{
                ProcessName = [string]$processProperty.Value
                Profile = $profileName
                Scope = [string]$scopeProperty.Value
                Enabled = if ($null -eq $enabledProperty) { $true } else { [bool]$enabledProperty.Value }
            })
        }
        $migrated.ApplicationRules = $rules.ToArray()
    }

    $script:LegacyDotNetConfigDetected = $true
    Write-AppLog 'Detected and mapped the legacy .NET OpenSynapse configuration.'
    return $migrated
}

function Get-AppConfig {
    $script:LegacyDotNetConfigDetected = $false
    $config = Read-JsonFile $script:ConfigPath
    $defaults = Get-DefaultConfig
    if ($null -eq $config) { return $defaults }
    if ($config -is [array]) {
        $recoveredConfig = @($config | Where-Object {
            $null -ne (Get-ObjectProperty $_ 'Version')
        }) | Select-Object -Last 1
        if ($null -eq $recoveredConfig) {
            throw 'Configuration JSON is an unsupported array and contains no recoverable OpenSynapse configuration.'
        }
        $config = $recoveredConfig
        Write-AppLog 'Recovered a valid OpenSynapse configuration from an interrupted PowerPilot takeover document.'
    }
    $config = Convert-LegacyDotNetConfig $config
    $oldVersion = if ($null -eq $config.PSObject.Properties['Version']) { 1 } else { [int]$config.Version }
    $isLegacy = $oldVersion -lt 2
    foreach ($property in $defaults.PSObject.Properties) {
        Add-DefaultProperty $config $property.Name $property.Value
    }
    if ($isLegacy) {
        $mergedProcesses = New-Object Collections.Generic.List[string]
        foreach ($name in @($config.QuietProcessNames) + @($script:DefaultQuietProcesses)) {
            if ($name -and -not $mergedProcesses.Contains([string]$name)) { $mergedProcesses.Add([string]$name) }
        }
        $config.QuietProcessNames = @($mergedProcesses)
    }
    if ($oldVersion -lt 3) {
        $config.RefreshPolicy = if ([bool]$config.ManageRefreshRate) { 'Auto' } else { 'Unmanaged' }
    }
    if ([string]$config.Selection -notin @('Auto', 'Hyper', 'Balance', 'Quiet', 'Experiment')) { $config.Selection = 'Auto' }
    if ([string]$config.HyperCpuPolicy -notin @('Sustained', 'Latency')) { $config.HyperCpuPolicy = 'Sustained' }
    if ($oldVersion -lt 12 -and [string]$config.RefreshPolicy -in @('FollowProfile', 'FollowMode', 'Fixed120', 'DynamicNative', 'Dynamic60To120')) {
        $config.RefreshPolicy = 'Auto'
    }
    if ([string]$config.RefreshPolicy -notin @('Auto', 'Fixed60', 'Fixed240', 'Unmanaged')) {
        $config.RefreshPolicy = 'Auto'
    }
    $config.ManageRefreshRate = ([string]$config.RefreshPolicy -ne 'Unmanaged')
    $config.ExperimentRefreshRate = if ([int]$config.ExperimentRefreshRate -in @(60, 120, 240)) {
        [int]$config.ExperimentRefreshRate
    }
    else { 240 }
    $config.ExperimentVerificationSeconds = [Math]::Max(5, [Math]::Min(120, [int]$config.ExperimentVerificationSeconds))
    if ($oldVersion -lt 5 -and [int]$config.ProcessMaintenanceSeconds -eq 30) {
        $config.ProcessMaintenanceSeconds = 180
    }
    if ($oldVersion -lt 11 -and
        [int]$config.QuietCpuMaxHighBattery -eq 75 -and
        [int]$config.QuietCpuMaxMediumBattery -eq 65 -and
        [int]$config.QuietCpuMaxLowBattery -eq 60 -and
        [int]$config.QuietCpuMediumThreshold -eq 50 -and
        [int]$config.QuietCpuLowThreshold -eq 20) {
        $config.QuietCpuMaxHighBattery = 65
        $config.QuietCpuMaxMediumBattery = 60
        $config.QuietCpuMaxLowBattery = 50
        $config.QuietCpuMediumThreshold = 70
        $config.QuietCpuLowThreshold = 30
        Write-AppLog 'Migrated the default Quiet battery curve to the Ryzen AI 9 365 endurance profile.'
    }
    $config.ProcessMaintenanceSeconds = [Math]::Max(60, [Math]::Min(3600, [int]$config.ProcessMaintenanceSeconds))
    $config.QuietProcessRestartWindowSeconds = [Math]::Max(60, [Math]::Min(3600, [int]$config.QuietProcessRestartWindowSeconds))
    $config.QuietProcessCooldownSeconds = [Math]::Max(
        [int]$config.QuietProcessRestartWindowSeconds,
        [Math]::Min(21600, [int]$config.QuietProcessCooldownSeconds))
    $config.QuietCpuMaxHighBattery = [Math]::Max(25, [Math]::Min(100, [int]$config.QuietCpuMaxHighBattery))
    $config.QuietCpuMaxMediumBattery = [Math]::Max(25, [Math]::Min([int]$config.QuietCpuMaxHighBattery, [int]$config.QuietCpuMaxMediumBattery))
    $config.QuietCpuMaxLowBattery = [Math]::Max(25, [Math]::Min([int]$config.QuietCpuMaxMediumBattery, [int]$config.QuietCpuMaxLowBattery))
    $config.QuietCpuLowThreshold = [Math]::Max(5, [Math]::Min(90, [int]$config.QuietCpuLowThreshold))
    $config.QuietCpuMediumThreshold = [Math]::Max(
        ([int]$config.QuietCpuLowThreshold + 1),
        [Math]::Min(95, [int]$config.QuietCpuMediumThreshold))
    $config.SmartHighPowerCpuEnter = [Math]::Max(10, [Math]::Min(100, [int]$config.SmartHighPowerCpuEnter))
    $config.SmartHighPowerCpuExit = [Math]::Max(0, [Math]::Min(($config.SmartHighPowerCpuEnter - 1), [int]$config.SmartHighPowerCpuExit))
    $config.SmartPortableCpuEnter = [Math]::Max(10, [Math]::Min(100, [int]$config.SmartPortableCpuEnter))
    $config.SmartPortableCpuExit = [Math]::Max(0, [Math]::Min(($config.SmartPortableCpuEnter - 1), [int]$config.SmartPortableCpuExit))
    $config.SmartLoadEnterSamples = [Math]::Max(1, [Math]::Min(12, [int]$config.SmartLoadEnterSamples))
    $config.SmartAppEnterSamples = [Math]::Max(1, [Math]::Min(6, [int]$config.SmartAppEnterSamples))
    $config.SmartExitSamples = [Math]::Max(2, [Math]::Min(60, [int]$config.SmartExitSamples))
    $config.SmartMinimumDwellSeconds = [Math]::Max(0, [Math]::Min(600, [int]$config.SmartMinimumDwellSeconds))
    $config.SmartAppCpuFloor = [Math]::Max(0, [Math]::Min(100, [int]$config.SmartAppCpuFloor))
    $config.SmartGpuEnter = [Math]::Max(1, [Math]::Min(100, [int]$config.SmartGpuEnter))
    $config.SmartGpuExit = [Math]::Max(0, [Math]::Min(($config.SmartGpuEnter - 1), [int]$config.SmartGpuExit))
    $config.SmartFullscreenCpuFloor = [Math]::Max(1, [Math]::Min(100, [int]$config.SmartFullscreenCpuFloor))
    $config.SmartFullscreenGpuFloor = [Math]::Max(1, [Math]::Min(100, [int]$config.SmartFullscreenGpuFloor))
    $config.SmartBrowserFullscreenCpuFloor = [Math]::Max(1, [Math]::Min(100, [int]$config.SmartBrowserFullscreenCpuFloor))
    $config.SmartBrowserFullscreenGpuFloor = [Math]::Max(1, [Math]::Min(100, [int]$config.SmartBrowserFullscreenGpuFloor))
    $config.SmartBrowserFullscreenSamples = [Math]::Max(2, [Math]::Min(12, [int]$config.SmartBrowserFullscreenSamples))
    $config.DgpuLeakMemoryMb = [Math]::Max(32, [Math]::Min(16384, [int]$config.DgpuLeakMemoryMb))
    $config.DgpuLeakUtilizationPercent = [Math]::Max(0, [Math]::Min(100, [double]$config.DgpuLeakUtilizationPercent))
    $config.DgpuLeakMinimumSamples = [Math]::Max(2, [Math]::Min(60, [int]$config.DgpuLeakMinimumSamples))
    $config.DgpuActivityDischargeThresholdW = [Math]::Max(1, [Math]::Min(100, [double]$config.DgpuActivityDischargeThresholdW))
    $config.GpuTelemetryHighPowerIntervalSeconds = [Math]::Max(2, [Math]::Min(60, [int]$config.GpuTelemetryHighPowerIntervalSeconds))
    $config.GpuTelemetryPortableIntervalSeconds = [Math]::Max(5, [Math]::Min(120, [int]$config.GpuTelemetryPortableIntervalSeconds))
    $config.GpuTelemetryManualQuietIntervalSeconds = [Math]::Max(
        [int]$config.GpuTelemetryPortableIntervalSeconds,
        [Math]::Min(300, [int]$config.GpuTelemetryManualQuietIntervalSeconds))
    $config.BatteryHighDrainSampleSeconds = [Math]::Max(15, [Math]::Min(300, [int]$config.BatteryHighDrainSampleSeconds))
    $config.BatteryHighDrainCpuPercent = [Math]::Max(5, [Math]::Min(400, [double]$config.BatteryHighDrainCpuPercent))
    $config.BatteryHighDrainMinimumSamples = [Math]::Max(2, [Math]::Min(10, [int]$config.BatteryHighDrainMinimumSamples))
    $config.BatteryHighDrainMinimumDischargeW = [Math]::Max(5, [Math]::Min(100, [double]$config.BatteryHighDrainMinimumDischargeW))
    $config.BatteryHighDrainCooldownMinutes = [Math]::Max(5, [Math]::Min(240, [int]$config.BatteryHighDrainCooldownMinutes))
    $config.BatteryHighDrainMaximumProcesses = [Math]::Max(1, [Math]::Min(5, [int]$config.BatteryHighDrainMaximumProcesses))
    foreach ($propertyName in @('SmartHyperProcessNames', 'SmartBalanceProcessNames', 'SmartIgnoredFullscreenProcesses', 'SmartBrowserProcesses', 'BatteryHighDrainIgnoredProcesses')) {
        $normalizedNames = New-Object Collections.Generic.List[string]
        foreach ($item in @($config.$propertyName)) {
            $value = ([string]$item).Trim()
            if (-not [string]::IsNullOrWhiteSpace($value) -and $value.Length -le 128 -and $value -notin @($normalizedNames)) {
                $normalizedNames.Add($value)
            }
        }
        $config.$propertyName = [string[]]@($normalizedNames)
    }
    $normalizedRules = New-Object Collections.Generic.List[object]
    foreach ($rule in @($config.ApplicationRules)) {
        if ($null -eq $rule) { continue }
        $processName = ([string]$rule.ProcessName).Trim()
        if ($processName.EndsWith('.exe', [StringComparison]::OrdinalIgnoreCase)) {
            $processName = $processName.Substring(0, $processName.Length - 4)
        }
        $profileName = [string]$rule.Profile
        $scopeName = [string]$rule.Scope
        if ([string]::IsNullOrWhiteSpace($processName) -or $processName.Length -gt 128 -or
            $profileName -notin @('Hyper', 'Balance', 'Quiet') -or
            $scopeName -notin @('Foreground', 'Fullscreen', 'Running')) { continue }
        $enabled = if ($null -eq $rule.PSObject.Properties['Enabled']) { $true } else { [bool]$rule.Enabled }
        $normalizedRules.Add([pscustomobject][ordered]@{
            ProcessName = $processName
            Profile = $profileName
            Scope = $scopeName
            Enabled = $enabled
        })
    }
    $config.ApplicationRules = $normalizedRules.ToArray()
    $config.Version = 14
    return $config
}

function Save-AppConfig {
    param([object]$Config)
    Write-JsonFile $script:ConfigPath $Config
}

function Get-AppState {
    $state = Read-JsonFile $script:StatePath
    if ($null -eq $state) { return $null }
    Add-DefaultProperty $state 'DisabledWakeDevices' @()
    Add-DefaultProperty $state 'ServicesStoppedByUs' @()
    Add-DefaultProperty $state 'AdvancedColorStates' @()
    Add-DefaultProperty $state 'CapturedBrightness' $null
    Add-DefaultProperty $state 'BalancePlanGuid' ''
    Add-DefaultProperty $state 'ExperimentPlanGuid' ''
    Add-DefaultProperty $state 'DisplayStateSnapshot' $null
    Add-DefaultProperty $state 'ExperimentSession' $null
    Add-DefaultProperty $state 'Version' 11
    $state.Version = 11

    $wakeDevices = @()
    foreach ($item in @($state.DisabledWakeDevices)) {
        $value = [string]$item
        # Old Windows PowerShell builds could repeatedly misdecode a localized powercfg
        # device name, growing it on every launch. Real PnP display names stay well below
        # this bound, so discard corrupt/stale records instead of retrying them forever.
        if (-not [string]::IsNullOrWhiteSpace($value) -and $value.Length -le 512) { $wakeDevices += $value }
    }
    $state.DisabledWakeDevices = [string[]]$wakeDevices

    $services = @()
    foreach ($item in @($state.ServicesStoppedByUs)) {
        $value = [string]$item
        if (-not [string]::IsNullOrWhiteSpace($value)) { $services += $value }
    }
    $state.ServicesStoppedByUs = [string[]]$services

    $colorStates = @()
    foreach ($item in @($state.AdvancedColorStates)) {
        if ($null -ne $item -and $null -ne $item.PSObject.Properties['Key'] -and
            -not [string]::IsNullOrWhiteSpace([string]$item.Key)) {
            $colorStates += $item
        }
    }
    $state.AdvancedColorStates = [object[]]$colorStates
    return $state
}

function Save-AppState {
    param([object]$State)
    Write-JsonFile $script:StatePath $State
}

function Import-NativeHelpers {
    $runningInstalled = [string]::Equals(
        [IO.Path]::GetFullPath($PSCommandPath),
        [IO.Path]::GetFullPath($script:InstalledScript),
        [StringComparison]::OrdinalIgnoreCase)
    $path = if ($runningInstalled) { $script:InstalledNative } else { $script:SourceNative }
    if (-not (Test-Path -LiteralPath $path) -and (Test-Path -LiteralPath $script:InstalledNative)) { $path = $script:InstalledNative }
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing native helper: $path" }
    if (-not ('OpenSynapseNative.DisplayScaling' -as [type])) {
        Add-Type -Path $path
    }
}

function Add-UiAssemblies {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
}

function Get-RazerMouseDevices {
    try {
        Import-NativeHelpers
        return @([OpenSynapseNative.RazerMouse]::GetDevices())
    }
    catch {
        Write-AppLog "Razer mouse detection failed: $($_.Exception.Message)"
        return @()
    }
}

function Set-RazerMouseDpi {
    param([ValidateRange(100, 30000)][int]$Dpi)
    Import-NativeHelpers
    [OpenSynapseNative.RazerMouse]::SetDpi($Dpi, $Dpi)
    Write-AppLog "Razer DeathAdder V3 Pro DPI set to $Dpi."
}

function Set-RazerMousePollingRate {
    param([ValidateSet(125, 500, 1000)][int]$Hertz)
    Import-NativeHelpers
    [OpenSynapseNative.RazerMouse]::SetPollingRate($Hertz)
    Write-AppLog "Razer DeathAdder V3 Pro polling rate set to $Hertz Hz."
}

function Get-NvidiaEnforcedPowerLimit {
    $command = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
    if ($null -eq $command) { return $null }
    try {
        $line = & $command.Source '--query-gpu=enforced.power.limit' '--format=csv,noheader,nounits' 2>$null | Select-Object -First 1
        if ([string]::IsNullOrWhiteSpace([string]$line)) { return $null }
        $value = 0.0
        if ([double]::TryParse(([string]$line).Trim(), [Globalization.NumberStyles]::Float,
            [Globalization.CultureInfo]::InvariantCulture, [ref]$value)) { return $value }
    }
    catch { Write-AppLog "Adapter probe failed: $($_.Exception.Message)" }
    return $null
}

function Resolve-SupplyType {
    param([string]$PowerSource, [AllowNull()][object]$EnforcedLimitW)
    if ($PowerSource -eq 'Battery') { return 'Battery' }
    if ($PowerSource -ne 'AC') { return 'Unknown' }
    if ($null -eq $EnforcedLimitW) { return 'UnknownAC' }
    $limit = [double]$EnforcedLimitW
    if ($limit -ge $script:HighPowerAdapterThresholdW) { return 'HighPowerAC' }
    if ($limit -le $script:LowPowerAdapterThresholdW) { return 'LowPowerPD' }
    return 'UnknownAC'
}

function Initialize-SupplyStabilizer {
    param([ValidateSet('Hyper', 'Balance', 'Quiet', 'Other')][string]$ActiveProfile = 'Other')
    $script:StableAcSupplyType = switch ($ActiveProfile) {
        'Hyper' { 'HighPowerAC'; break }
        default { $null }
    }
    $script:PendingLowPowerSamples = 0
    $script:PendingLowPowerSince = [DateTime]::MinValue
    $script:LastStabilizedProbeSequence = -1
    $script:SupplyStabilizerStartedAt = Get-Date
    $script:NextAdapterConfirmationProbe = [DateTime]::MaxValue
}

function Resolve-StableSupplyType {
    param(
        [string]$PowerSource,
        [string]$RawSupplyType,
        [int]$ProbeSequence,
        [DateTime]$Now = (Get-Date)
    )
    if ($PowerSource -eq 'Battery') {
        $script:StableAcSupplyType = $null
        $script:PendingLowPowerSamples = 0
        $script:NextAdapterConfirmationProbe = [DateTime]::MaxValue
        return 'Battery'
    }
    if ($PowerSource -ne 'AC') { return 'Unknown' }

    if ($RawSupplyType -eq 'HighPowerAC') {
        if ($script:StableAcSupplyType -ne 'HighPowerAC') {
            Write-AppLog 'Supply confirmed immediately: HighPowerAC.'
        }
        $script:StableAcSupplyType = 'HighPowerAC'
        $script:PendingLowPowerSamples = 0
        $script:PendingLowPowerSince = [DateTime]::MinValue
        $script:NextAdapterConfirmationProbe = [DateTime]::MaxValue
        $script:LastStabilizedProbeSequence = $ProbeSequence
        return 'HighPowerAC'
    }

    if ($RawSupplyType -eq 'UnknownAC') {
        $script:PendingLowPowerSamples = 0
        $script:PendingLowPowerSince = [DateTime]::MinValue
        $script:NextAdapterConfirmationProbe = [DateTime]::MaxValue
        $script:LastStabilizedProbeSequence = $ProbeSequence
        if ($script:StableAcSupplyType -in @('HighPowerAC', 'LowPowerPD')) {
            return [string]$script:StableAcSupplyType
        }
        return 'UnknownAC'
    }

    if ($RawSupplyType -ne 'LowPowerPD') {
        if ($script:StableAcSupplyType) { return [string]$script:StableAcSupplyType }
        return 'UnknownAC'
    }

    if ($script:StableAcSupplyType -eq 'LowPowerPD') {
        $warmupUntil = $script:SupplyStabilizerStartedAt.AddSeconds($script:AdapterStartupWarmupSeconds)
        if ($Now -lt $warmupUntil) { $script:NextAdapterConfirmationProbe = $warmupUntil }
        $script:LastStabilizedProbeSequence = $ProbeSequence
        return 'LowPowerPD'
    }
    $warmupUntil = $script:SupplyStabilizerStartedAt.AddSeconds($script:AdapterStartupWarmupSeconds)
    $heldSupplyType = if ($script:StableAcSupplyType -eq 'HighPowerAC') { 'HighPowerAC' } else { 'UnknownAC' }
    if ($Now -lt $warmupUntil) {
        $script:NextAdapterConfirmationProbe = $warmupUntil
        $script:LastStabilizedProbeSequence = $ProbeSequence
        return $heldSupplyType
    }

    if ($ProbeSequence -ne $script:LastStabilizedProbeSequence) {
        if ($script:PendingLowPowerSamples -eq 0) { $script:PendingLowPowerSince = $Now }
        $script:PendingLowPowerSamples++
        $script:LastStabilizedProbeSequence = $ProbeSequence
        $script:NextAdapterConfirmationProbe = $Now.AddSeconds($script:AdapterConfirmationIntervalSeconds)
        Write-AppLog "Supply downgrade pending: LowPowerPD sample $($script:PendingLowPowerSamples)/$($script:AdapterLowConfirmationSamples); holding $heldSupplyType."
    }
    $minimumSpan = $script:AdapterConfirmationIntervalSeconds * ($script:AdapterLowConfirmationSamples - 1)
    if ($script:PendingLowPowerSamples -ge $script:AdapterLowConfirmationSamples -and
        ($Now - $script:PendingLowPowerSince).TotalSeconds -ge $minimumSpan) {
        $script:StableAcSupplyType = 'LowPowerPD'
        $script:PendingLowPowerSamples = 0
        $script:PendingLowPowerSince = [DateTime]::MinValue
        $script:NextAdapterConfirmationProbe = [DateTime]::MaxValue
        Write-AppLog 'Supply downgrade confirmed: LowPowerPD after three consecutive samples.'
        return 'LowPowerPD'
    }
    return $heldSupplyType
}

function Get-SupplyDisplayName {
    param([string]$SupplyType)
    switch ($SupplyType) {
        'HighPowerAC' { return '280W-class AC' }
        'LowPowerPD' { return 'USB-C PD / low-power AC' }
        'Battery' { return 'Battery' }
        'UnknownAC' { return 'AC (unverified)' }
        default { return 'Unknown' }
    }
}

function Reset-BatteryPowerTrend {
    $script:BatteryPowerSamples.Clear()
    $script:BatteryDischargeEmaW = $null
    $script:LastBatteryTrendSampleAt = [DateTime]::MinValue
    $script:LastBatteryTrendSource = ''
}

function Register-PowerEventObservation {
    param(
        [int]$EventCount,
        [DateTime]$Now = (Get-Date)
    )
    if ($EventCount -le [int]$script:LastPowerEventCount) { return $false }
    $newEvents = $EventCount - [int]$script:LastPowerEventCount
    $script:LastPowerEventCount = $EventCount
    $script:PowerEventsObserved += $newEvents
    if ($script:PendingPowerProbeAt -eq [DateTime]::MaxValue) {
        $script:PendingPowerProbeAt = $Now.AddSeconds($script:PowerEventProbeDelaySeconds)
        Write-AppLog "Power event observed ($newEvents new); one supply refresh scheduled after ${script:PowerEventProbeDelaySeconds}s."
    }
    else {
        $script:PowerEventsCoalesced += $newEvents
    }
    return $true
}

function Invoke-PendingPowerProbe {
    param([DateTime]$Now = (Get-Date))
    if ($script:PendingPowerProbeAt -eq [DateTime]::MaxValue -or $Now -lt $script:PendingPowerProbeAt) {
        return $false
    }
    $script:CachedSupplyType = $null
    $script:CachedAdapterLimitW = $null
    $script:LastAdapterProbe = [DateTime]::MinValue
    $script:PendingPowerProbeAt = [DateTime]::MaxValue
    $script:PowerEventTriggeredProbes++
    Write-AppLog "Coalesced power-event supply refresh is due; observed=$script:PowerEventsObserved coalesced=$script:PowerEventsCoalesced probes=$script:PowerEventTriggeredProbes."
    return $true
}

function Update-BatteryPowerTrend {
    param(
        [bool]$Available,
        [double]$DischargeWatts,
        [uint32]$RemainingCapacityMwh,
        [string]$Source,
        [DateTime]$Now = (Get-Date)
    )
    if (-not $Available) {
        return [pscustomobject]@{
            EmaW = $null; Average10mW = $null; EstimatedHours = $null
            Confidence = 'Unavailable'; SampleCount = 0
        }
    }
    if (-not [string]::Equals($script:LastBatteryTrendSource, $Source, [StringComparison]::OrdinalIgnoreCase)) {
        Reset-BatteryPowerTrend
        $script:LastBatteryTrendSource = $Source
    }
    $watts = [Math]::Round([Math]::Max(0.0, $DischargeWatts), 2)
    $elapsedSeconds = if ($script:LastBatteryTrendSampleAt -eq [DateTime]::MinValue) {
        0.0
    } else {
        [Math]::Max(0.0, ($Now - $script:LastBatteryTrendSampleAt).TotalSeconds)
    }
    if ($null -eq $script:BatteryDischargeEmaW -or $elapsedSeconds -le 0) {
        $script:BatteryDischargeEmaW = $watts
    }
    else {
        $alpha = 1.0 - [Math]::Exp(-$elapsedSeconds / 120.0)
        $script:BatteryDischargeEmaW = ([double]$script:BatteryDischargeEmaW * (1.0 - $alpha)) + ($watts * $alpha)
    }
    $script:LastBatteryTrendSampleAt = $Now
    $script:BatteryPowerSamples.Add([pscustomobject]@{ Timestamp = $Now; Watts = $watts })
    $cutoff = $Now.AddMinutes(-10)
    while ($script:BatteryPowerSamples.Count -gt 0 -and [DateTime]$script:BatteryPowerSamples[0].Timestamp -lt $cutoff) {
        $script:BatteryPowerSamples.RemoveAt(0)
    }
    $average = if ($script:BatteryPowerSamples.Count -gt 0) {
        [double](($script:BatteryPowerSamples | Measure-Object -Property Watts -Average).Average)
    } else { 0.0 }
    $spanSeconds = if ($script:BatteryPowerSamples.Count -ge 2) {
        ($Now - [DateTime]$script:BatteryPowerSamples[0].Timestamp).TotalSeconds
    } else { 0.0 }
    $confidence = if ($spanSeconds -ge 480 -and $script:BatteryPowerSamples.Count -ge 20) {
        'High'
    } elseif ($spanSeconds -ge 90 -and $script:BatteryPowerSamples.Count -ge 6) {
        'Medium'
    } else {
        'Low'
    }
    $estimateBase = if ($spanSeconds -ge 90) { $average } else { [double]$script:BatteryDischargeEmaW }
    $estimatedHours = if ($estimateBase -ge 0.3 -and $RemainingCapacityMwh -gt 0) {
        [Math]::Round(([double]$RemainingCapacityMwh / ($estimateBase * 1000.0)), 1)
    } else { $null }
    return [pscustomobject]@{
        EmaW = [Math]::Round([double]$script:BatteryDischargeEmaW, 2)
        Average10mW = [Math]::Round($average, 2)
        EstimatedHours = $estimatedHours
        Confidence = $confidence
        SampleCount = $script:BatteryPowerSamples.Count
    }
}

function Get-PowerSnapshot {
    param([switch]$UseCachedAdapter)
    $status = [Windows.Forms.SystemInformation]::PowerStatus
    $source = switch ($status.PowerLineStatus.ToString()) {
        'Online' { 'AC' }
        'Offline' { 'Battery' }
        default { 'Unknown' }
    }
    $percent = if ($status.BatteryLifePercent -ge 0 -and $status.BatteryLifePercent -le 1) {
        [math]::Round($status.BatteryLifePercent * 100)
    } else { -1 }
    $limit = $null
    $rawSupplyType = Resolve-SupplyType $source $null
    $supplyType = $rawSupplyType
    if ($source -eq 'AC') {
        $now = Get-Date
        $cacheFresh = $null -ne $script:CachedSupplyType -and
            ($now - $script:LastAdapterProbe).TotalSeconds -lt $script:AdapterProbeIntervalSeconds
        $confirmationDue = $now -ge $script:NextAdapterConfirmationProbe
        if ($UseCachedAdapter -and $cacheFresh -and -not $confirmationDue) {
            $limit = $script:CachedAdapterLimitW
            $rawSupplyType = [string]$script:CachedSupplyType
        }
        else {
            $limit = Get-NvidiaEnforcedPowerLimit
            $rawSupplyType = Resolve-SupplyType $source $limit
            $script:CachedAdapterLimitW = $limit
            $script:CachedSupplyType = $rawSupplyType
            $script:LastAdapterProbe = $now
            $script:AdapterProbeSequence++
            Write-AppLog "Supply probe: rawType=$rawSupplyType enforcedLimit=$(if ($null -eq $limit) { 'unavailable' } else { "$limit W" }) sequence=$script:AdapterProbeSequence."
        }
        $supplyType = Resolve-StableSupplyType $source $rawSupplyType $script:AdapterProbeSequence $now
    }
    else {
        $supplyType = Resolve-StableSupplyType $source $rawSupplyType $script:AdapterProbeSequence (Get-Date)
        if ($source -eq 'Battery') {
            $script:CachedSupplyType = $null
            $script:CachedAdapterLimitW = $null
            $script:LastAdapterProbe = [DateTime]::MinValue
        }
    }
    $batteryTelemetry = $null
    try { $batteryTelemetry = [OpenSynapseNative.BatteryTelemetry]::Read() }
    catch { Write-AppLog "Battery telemetry failed: $($_.Exception.Message)" }
    $batteryAvailable = ($null -ne $batteryTelemetry -and [bool]$batteryTelemetry.Available)
    $trendArguments = @{
        Available = $batteryAvailable
        DischargeWatts = $(if ($batteryAvailable) { [double]$batteryTelemetry.DischargeWatts } else { 0.0 })
        RemainingCapacityMwh = $(if ($batteryAvailable) { [uint32]$batteryTelemetry.RemainingCapacityMwh } else { [uint32]0 })
        Source = $source
    }
    $batteryTrend = Update-BatteryPowerTrend @trendArguments
    return [pscustomobject]@{
        Source = $source
        SupplyType = $supplyType
        RawSupplyType = $rawSupplyType
        BatteryPercent = $percent
        AdapterLimitW = $limit
        BatteryTelemetryAvailable = $batteryAvailable
        BatterySignedRateW = if ($batteryAvailable) { [double]$batteryTelemetry.SignedRateWatts } else { $null }
        BatteryDischargeW = if ($batteryAvailable) { [double]$batteryTelemetry.DischargeWatts } else { $null }
        BatteryChargeW = if ($batteryAvailable) { [double]$batteryTelemetry.ChargeWatts } else { $null }
        BatteryRemainingMwh = if ($batteryAvailable) { [uint32]$batteryTelemetry.RemainingCapacityMwh } else { $null }
        BatteryVoltageMv = if ($batteryAvailable) { [uint32]$batteryTelemetry.VoltageMv } else { $null }
        BatteryDischargeEmaW = $batteryTrend.EmaW
        BatteryDischargeAverage10mW = $batteryTrend.Average10mW
        BatteryEstimatedHours = $batteryTrend.EstimatedHours
        BatteryEstimateConfidence = $batteryTrend.Confidence
        BatteryTrendSampleCount = $batteryTrend.SampleCount
        SupplyConfirmationPending = ($source -eq 'AC' -and $rawSupplyType -eq 'LowPowerPD' -and $supplyType -ne 'LowPowerPD')
    }
}

function Get-DesiredProfile {
    param(
        [string]$Selection,
        [object]$Snapshot,
        [AllowNull()][object]$Config = $null,
        [AllowNull()][object]$AutomationState = $null,
        [string]$TemporaryProfile = ''
    )
    if ($Selection -eq 'Experiment') { return 'Experiment' }
    if ($TemporaryProfile -in @('Hyper', 'Balance', 'Quiet')) { return $TemporaryProfile }
    if ($Selection -in @('Hyper', 'Balance', 'Quiet')) { return $Selection }
    if ($null -ne $Config -and [bool]$Config.SmartAutomationEnabled) {
        if ($null -ne $AutomationState -and [string]$AutomationState.CurrentProfile -in @('Hyper', 'Balance', 'Quiet')) {
            return [string]$AutomationState.CurrentProfile
        }
        if ([string]$Snapshot.SupplyType -eq 'HighPowerAC') { return 'Balance' }
        return 'Quiet'
    }
    if ([string]$Snapshot.SupplyType -eq 'HighPowerAC') { return 'Hyper' }
    return 'Quiet'
}

function Resolve-SelectionAfterSupplyTransition {
    param(
        [ValidateSet('Auto', 'Hyper', 'Balance', 'Quiet', 'Experiment')][string]$Selection,
        [AllowEmptyString()][string]$PreviousSupplyType,
        [AllowEmptyString()][string]$CurrentSupplyType
    )
    $verifiedHighPowerBecameAvailable =
        ([string]::IsNullOrWhiteSpace($PreviousSupplyType) -or
         -not [string]::Equals($PreviousSupplyType, 'HighPowerAC', [StringComparison]::OrdinalIgnoreCase)) -and
        [string]::Equals($CurrentSupplyType, 'HighPowerAC', [StringComparison]::OrdinalIgnoreCase)
    if ($Selection -eq 'Quiet' -and $verifiedHighPowerBecameAvailable) { return 'Auto' }
    return $Selection
}

function Resolve-RefreshPolicyAfterPowerTransition {
    param(
        [ValidateSet('Auto', 'Fixed60', 'Fixed240', 'Unmanaged')][string]$RefreshPolicy,
        [AllowEmptyString()][string]$PreviousPowerSource,
        [AllowEmptyString()][string]$CurrentPowerSource,
        [AllowEmptyString()][string]$PreviousSupplyType = '',
        [AllowEmptyString()][string]$CurrentSupplyType = '',
        [AllowEmptyString()][string]$PreviousSelection = '',
        [AllowEmptyString()][string]$CurrentSelection = ''
    )
    $manualEcoWasReleased =
        [string]::Equals($PreviousSelection, 'Quiet', [StringComparison]::OrdinalIgnoreCase) -and
        [string]::Equals($CurrentSelection, 'Auto', [StringComparison]::OrdinalIgnoreCase) -and
        [string]::Equals($CurrentSupplyType, 'HighPowerAC', [StringComparison]::OrdinalIgnoreCase)
    if ($manualEcoWasReleased) { return 'Auto' }

    $externalPowerWasConnected =
        -not [string]::IsNullOrWhiteSpace($PreviousPowerSource) -and
        -not [string]::Equals($PreviousPowerSource, 'AC', [StringComparison]::OrdinalIgnoreCase) -and
        [string]::Equals($CurrentPowerSource, 'AC', [StringComparison]::OrdinalIgnoreCase)
    $verifiedHighPowerWasConnected =
        -not [string]::IsNullOrWhiteSpace($PreviousSupplyType) -and
        -not [string]::Equals($PreviousSupplyType, 'HighPowerAC', [StringComparison]::OrdinalIgnoreCase) -and
        [string]::Equals($CurrentSupplyType, 'HighPowerAC', [StringComparison]::OrdinalIgnoreCase)
    if ($RefreshPolicy -in @('Fixed60', 'Fixed240') -and ($externalPowerWasConnected -or $verifiedHighPowerWasConnected)) { return 'Auto' }
    return $RefreshPolicy
}

function Resolve-GpuTelemetryIntervalMilliseconds {
    param(
        [object]$Config,
        [object]$Snapshot,
        [ValidateSet('Auto', 'Hyper', 'Balance', 'Quiet', 'Experiment')][string]$Selection
    )
    $seconds = if ($Selection -eq 'Quiet') {
        [int]$Config.GpuTelemetryManualQuietIntervalSeconds
    }
    elseif ([string]$Snapshot.SupplyType -eq 'HighPowerAC') {
        [int]$Config.GpuTelemetryHighPowerIntervalSeconds
    }
    else {
        [int]$Config.GpuTelemetryPortableIntervalSeconds
    }
    return [Math]::Max(2000, $seconds * 1000)
}

function Update-GpuTelemetryCadence {
    param(
        [object]$Config,
        [object]$Snapshot,
        [ValidateSet('Auto', 'Hyper', 'Balance', 'Quiet', 'Experiment')][string]$Selection
    )
    $interval = Resolve-GpuTelemetryIntervalMilliseconds $Config $Snapshot $Selection
    if ($interval -ne [int]$script:LastGpuTelemetryIntervalMs) {
        [OpenSynapseNative.GpuTelemetry]::SetInterval($interval)
        $script:LastGpuTelemetryIntervalMs = $interval
        Write-AppLog "GPU telemetry cadence changed to $($interval / 1000)s for selection=$Selection supply=$($Snapshot.SupplyType)."
    }
    return $interval
}

function Resolve-MonitorIntervalMilliseconds {
    param(
        [AllowNull()][object]$Snapshot,
        [AllowNull()][object]$AutomationState,
        [ValidateSet('Auto', 'Hyper', 'Balance', 'Quiet', 'Experiment')][string]$Selection = 'Auto'
    )
    if ($null -eq $Snapshot -or [string]$Snapshot.Source -ne 'Battery') { return 5000 }
    if ($Selection -eq 'Quiet' -or ($null -ne $AutomationState -and [bool]$AutomationState.SessionLocked)) { return 15000 }
    $cpu = if ($null -ne $AutomationState) { [double]$AutomationState.LastCpuPercent } else { -1.0 }
    $gpu = if ($null -ne $AutomationState) { [double]$AutomationState.LastGpuPercent } else { -1.0 }
    $fullscreen = $null -ne $AutomationState -and [bool]$AutomationState.ForegroundFullscreen
    if ($cpu -ge 15 -or $gpu -ge 5 -or $fullscreen) { return 10000 }
    return 15000
}

function New-SmartAutomationState {
    param([string]$InitialProfile = '')
    if ($InitialProfile -notin @('Hyper', 'Balance', 'Quiet', 'Experiment')) { $InitialProfile = '' }
    return [pscustomobject]@{
        CurrentProfile = $InitialProfile
        CandidateProfile = ''
        CandidateSamples = 0
        LastTransitionAt = [DateTime]::MinValue
        LastSupplyType = ''
        LastReason = 'waiting for first telemetry sample'
        LastCpuPercent = -1.0
        LastGpuPercent = -1.0
        ForegroundProcess = ''
        ForegroundFullscreen = $false
        SessionLocked = $false
        MatchedRule = ''
        DgpuLeakSamples = 0
        DgpuLeakDetected = $false
        DgpuActivityConfidence = 'None'
        DgpuConsumers = @()
        LastGpuSampleSequence = 0L
        LastGpuSampledAtUtcTicks = 0L
        LastGpuSampleAgeSeconds = -1.0
        BatteryHighDrainDetected = $false
        BatteryHighDrainConfidence = 'None'
        BatteryHighDrainDischargeW = 0.0
        BatteryHighDrainProcesses = @()
        BatteryHighDrainSampleCounts = @{}
        BatteryHighDrainLastReason = 'inactive'
        BatteryHighDrainLastSource = ''
        LastBatteryHighDrainSampleAt = [DateTime]::MinValue
        LastBatteryHighDrainAlertAt = [DateTime]::MinValue
        BatteryHighDrainAlertCount = 0
    }
}

function Reset-BatteryHighDrainState {
    param([object]$AutomationState, [switch]$ResetSampler)
    $AutomationState.BatteryHighDrainDetected = $false
    $AutomationState.BatteryHighDrainConfidence = 'None'
    $AutomationState.BatteryHighDrainDischargeW = 0.0
    $AutomationState.BatteryHighDrainProcesses = @()
    $AutomationState.BatteryHighDrainSampleCounts = @{}
    $AutomationState.BatteryHighDrainLastReason = 'inactive'
    $AutomationState.LastBatteryHighDrainSampleAt = [DateTime]::MinValue
    if ($ResetSampler) {
        try { [OpenSynapseNative.ProcessCpuSampler]::Reset() } catch { }
    }
}

function Update-BatteryHighDrainState {
    param(
        [object]$Config,
        [object]$Snapshot,
        [object]$AutomationState,
        [AllowNull()][object[]]$ProcessSamples = $null,
        [DateTime]$Now = (Get-Date),
        [switch]$ForceSample
    )
    $source = [string]$Snapshot.Source
    $sourceChanged = -not [string]::Equals([string]$AutomationState.BatteryHighDrainLastSource, $source, [StringComparison]::OrdinalIgnoreCase)
    $AutomationState.BatteryHighDrainLastSource = $source
    if (-not [bool]$Config.BatteryHighDrainAlertsEnabled -or $source -ne 'Battery' -or [bool]$AutomationState.SessionLocked) {
        if ($sourceChanged -or [bool]$AutomationState.BatteryHighDrainDetected -or
            @($AutomationState.BatteryHighDrainSampleCounts.Keys).Count -gt 0 -or
            [string]$AutomationState.BatteryHighDrainLastReason -ne 'inactive') {
            Reset-BatteryHighDrainState $AutomationState -ResetSampler
        }
        return [pscustomobject]@{ Sampled = $false; ShouldNotify = $false; Detected = $false; Confidence = 'None'; DischargeW = 0.0; Processes = @(); Reason = 'inactive' }
    }

    if ($sourceChanged) { Reset-BatteryHighDrainState $AutomationState -ResetSampler }
    if (-not $ForceSample -and [DateTime]$AutomationState.LastBatteryHighDrainSampleAt -ne [DateTime]::MinValue -and
        ($Now - [DateTime]$AutomationState.LastBatteryHighDrainSampleAt).TotalSeconds -lt [int]$Config.BatteryHighDrainSampleSeconds) {
        return [pscustomobject]@{
            Sampled = $false
            ShouldNotify = $false
            Detected = [bool]$AutomationState.BatteryHighDrainDetected
            Confidence = [string]$AutomationState.BatteryHighDrainConfidence
            DischargeW = [double]$AutomationState.BatteryHighDrainDischargeW
            Processes = [object[]]@($AutomationState.BatteryHighDrainProcesses)
            Reason = [string]$AutomationState.BatteryHighDrainLastReason
        }
    }

    if ($null -eq $ProcessSamples) {
        try { $ProcessSamples = [object[]]@([OpenSynapseNative.ProcessCpuSampler]::Sample()) }
        catch { $ProcessSamples = @() }
    }
    $AutomationState.LastBatteryHighDrainSampleAt = $Now
    $ignored = [string[]]@($Config.BatteryHighDrainIgnoredProcesses | ForEach-Object {
        ([string]$_).Trim()
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $current = @{}
    foreach ($sample in @($ProcessSamples | Sort-Object -Property CpuPercentOneCore -Descending)) {
        if ($null -eq $sample) { continue }
        $name = ([string]$sample.ProcessName).Trim()
        if ($name.EndsWith('.exe', [StringComparison]::OrdinalIgnoreCase)) { $name = $name.Substring(0, $name.Length - 4) }
        if ([string]::IsNullOrWhiteSpace($name) -or $name -in $ignored) { continue }
        $cpu = [double]$sample.CpuPercentOneCore
        if ($cpu -lt [double]$Config.BatteryHighDrainCpuPercent) { continue }
        if ($current.ContainsKey($name)) {
            $current[$name].CpuPercentOneCore = [Math]::Round([double]$current[$name].CpuPercentOneCore + $cpu, 1)
            $current[$name].WorkingSetBytes = [long]$current[$name].WorkingSetBytes + [long]$sample.WorkingSetBytes
            $current[$name].ProcessCount = [int]$current[$name].ProcessCount + [int]$sample.ProcessCount
        }
        else {
            $current[$name] = [pscustomobject]@{
                ProcessName = $name
                CpuPercentOneCore = [Math]::Round($cpu, 1)
                WorkingSetBytes = [long]$sample.WorkingSetBytes
                ProcessCount = [Math]::Max(1, [int]$sample.ProcessCount)
                ConsecutiveSamples = 0
            }
        }
    }

    $counts = $AutomationState.BatteryHighDrainSampleCounts
    foreach ($oldName in @($counts.Keys)) {
        if (-not $current.ContainsKey([string]$oldName)) { [void]$counts.Remove([string]$oldName) }
    }
    foreach ($name in @($current.Keys)) {
        $counts[$name] = if ($counts.ContainsKey($name)) { [int]$counts[$name] + 1 } else { 1 }
        $current[$name].ConsecutiveSamples = [int]$counts[$name]
    }
    $sustained = [object[]]@($current.Values |
        Where-Object { [int]$_.ConsecutiveSamples -ge [int]$Config.BatteryHighDrainMinimumSamples } |
        Sort-Object -Property CpuPercentOneCore -Descending |
        Select-Object -First ([int]$Config.BatteryHighDrainMaximumProcesses))

    $dischargeW = 0.0
    $confidence = 'None'
    foreach ($candidate in @(
        [pscustomobject]@{ Name = 'BatteryDischargeAverage10mW'; Confidence = 'High' },
        [pscustomobject]@{ Name = 'BatteryDischargeEmaW'; Confidence = 'Medium' },
        [pscustomobject]@{ Name = 'BatteryDischargeW'; Confidence = 'Medium' }
    )) {
        $property = Get-ObjectProperty $Snapshot ([string]$candidate.Name)
        if ($null -ne $property -and $null -ne $property.Value -and [double]$property.Value -gt 0) {
            $dischargeW = [Math]::Round([double]$property.Value, 1)
            $confidence = [string]$candidate.Confidence
            break
        }
    }
    $detected = $sustained.Count -gt 0 -and $dischargeW -ge [double]$Config.BatteryHighDrainMinimumDischargeW
    $AutomationState.BatteryHighDrainDetected = $detected
    $AutomationState.BatteryHighDrainConfidence = if ($detected) { $confidence } else { 'None' }
    $AutomationState.BatteryHighDrainDischargeW = $dischargeW
    $AutomationState.BatteryHighDrainProcesses = if ($detected) { $sustained } else { @() }
    $AutomationState.BatteryHighDrainLastReason = if ($detected) {
        "sustained process CPU with battery discharge above $($Config.BatteryHighDrainMinimumDischargeW) W"
    }
    elseif ($sustained.Count -gt 0) { 'sustained process CPU observed, but battery discharge is below the alert threshold or unavailable' }
    else { 'sampling sustained process CPU' }

    $cooldownElapsed = [DateTime]$AutomationState.LastBatteryHighDrainAlertAt -eq [DateTime]::MinValue -or
        ($Now - [DateTime]$AutomationState.LastBatteryHighDrainAlertAt).TotalMinutes -ge [int]$Config.BatteryHighDrainCooldownMinutes
    $shouldNotify = $detected -and $cooldownElapsed
    if ($shouldNotify) {
        $AutomationState.LastBatteryHighDrainAlertAt = $Now
        $AutomationState.BatteryHighDrainAlertCount = [int]$AutomationState.BatteryHighDrainAlertCount + 1
    }
    return [pscustomobject]@{
        Sampled = $true
        ShouldNotify = $shouldNotify
        Detected = $detected
        Confidence = [string]$AutomationState.BatteryHighDrainConfidence
        DischargeW = $dischargeW
        Processes = [object[]]@($AutomationState.BatteryHighDrainProcesses)
        Reason = [string]$AutomationState.BatteryHighDrainLastReason
    }
}

function Get-SmartAutomationTelemetry {
    param([AllowNull()][object]$Config = $null)
    $cpuPercent = [OpenSynapseNative.AutomationTelemetry]::SampleCpuPercent()
    $foreground = ''
    $fullscreen = $false
    try {
        $window = [OpenSynapseNative.AutomationTelemetry]::GetForegroundWindowSample()
        $foregroundId = [int]$window.ProcessId
        $fullscreen = [bool]$window.IsFullscreen
        if ($foregroundId -gt 0) {
            $foreground = [string](Get-Process -Id $foregroundId -ErrorAction Stop).ProcessName
        }
    }
    catch { }
    $running = @()
    if ($null -ne $Config -and @($Config.ApplicationRules | Where-Object { [bool]$_.Enabled -and [string]$_.Scope -eq 'Running' }).Count -gt 0) {
        try { $running = [string[]]@(Get-Process -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ProcessName -Unique) }
        catch { }
    }
    $gpu = $null
    try { $gpu = [OpenSynapseNative.GpuTelemetry]::ReadLatest() } catch { }
    $gpuConsumers = @()
    if ($null -ne $gpu -and [bool]$gpu.Available) {
        $gpuConsumers = [object[]]@($gpu.Consumers | Where-Object { [bool]$_.Discrete -and ([double]$_.UtilizationPercent -ge 0.5 -or [long]$_.DedicatedBytes -ge 64MB) } | Select-Object -First 8)
    }
    $sessionLocked = [OpenSynapseNative.PowerChangeSignal]::SessionLocked -or
        $foreground -in @('LockApp', 'LogonUI')
    $gpuSampledAtTicks = if ($null -ne $gpu -and $null -ne $gpu.PSObject.Properties['SampledAtUtcTicks']) { [long]$gpu.SampledAtUtcTicks } else { 0L }
    $gpuSampleAgeSeconds = if ($gpuSampledAtTicks -gt 0) {
        [Math]::Max(0.0, [Math]::Round(((Get-Date).ToUniversalTime().Ticks - $gpuSampledAtTicks) / [double][TimeSpan]::TicksPerSecond, 1))
    }
    else { -1.0 }
    return [pscustomobject]@{
        CpuPercent = if ($cpuPercent -lt 0) { -1.0 } else { [Math]::Round($cpuPercent, 1) }
        ForegroundProcess = $foreground
        ForegroundFullscreen = $fullscreen
        SessionLocked = $sessionLocked
        RunningProcesses = $running
        GpuAvailable = ($null -ne $gpu -and [bool]$gpu.Available)
        GpuPercent = if ($null -ne $gpu -and [bool]$gpu.Available) { [double]$gpu.TotalUtilizationPercent } else { -1.0 }
        DgpuPercent = if ($null -ne $gpu -and [bool]$gpu.Available) { [double]$gpu.DiscreteUtilizationPercent } else { -1.0 }
        DgpuDedicatedMb = if ($null -ne $gpu -and [bool]$gpu.Available) { [Math]::Round(([double]$gpu.DiscreteDedicatedBytes / 1MB), 1) } else { -1.0 }
        DgpuConsumers = $gpuConsumers
        GpuSampleSequence = if ($null -ne $gpu -and $null -ne $gpu.PSObject.Properties['Sequence']) { [long]$gpu.Sequence } else { 0L }
        GpuSampledAtUtcTicks = $gpuSampledAtTicks
        GpuSampleAgeSeconds = $gpuSampleAgeSeconds
    }
}

function Test-IgnoredFullscreenProcess {
    param([object]$Config, [string]$ProcessName)
    return Test-SmartProcessMatch $ProcessName @($Config.SmartIgnoredFullscreenProcesses)
}

function Resolve-ApplicationRule {
    param(
        [object]$Config,
        [string]$ForegroundProcess,
        [bool]$ForegroundFullscreen,
        [object[]]$RunningProcesses = @()
    )
    $lastMatch = $null
    foreach ($rule in @($Config.ApplicationRules)) {
        if ($null -eq $rule -or -not [bool]$rule.Enabled) { continue }
        $matched = switch ([string]$rule.Scope) {
            'Foreground' { Test-SmartProcessMatch $ForegroundProcess @($rule.ProcessName); break }
            'Fullscreen' { $ForegroundFullscreen -and (Test-SmartProcessMatch $ForegroundProcess @($rule.ProcessName)); break }
            'Running' {
                $found = $false
                foreach ($running in @($RunningProcesses)) {
                    if (Test-SmartProcessMatch ([string]$running) @($rule.ProcessName)) { $found = $true; break }
                }
                $found
                break
            }
            default { $false }
        }
        if ($matched) { $lastMatch = $rule }
    }
    return $lastMatch
}

function Test-SmartProcessMatch {
    param([string]$ProcessName, [object[]]$ConfiguredNames)
    if ([string]::IsNullOrWhiteSpace($ProcessName)) { return $false }
    foreach ($name in @($ConfiguredNames)) {
        if ([string]::Equals($ProcessName, [string]$name, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Get-ProfileRank {
    param([string]$ProfileName)
    switch ($ProfileName) {
        'Hyper' { return 3 }
        'Balance' { return 2 }
        'Quiet' { return 1 }
        default { return 0 }
    }
}

function Resolve-SmartAutomationDecision {
    param(
        [object]$Config,
        [object]$Snapshot,
        [object]$AutomationState,
        [double]$CpuPercent,
        [string]$ForegroundProcess,
        [DateTime]$Now = (Get-Date),
        [double]$GpuPercent = -1.0,
        [bool]$ForegroundFullscreen = $false,
        [object[]]$RunningProcesses = @(),
        [bool]$SessionLocked = $false
    )

    $current = [string]$AutomationState.CurrentProfile
    if ($current -notin @('Hyper', 'Balance', 'Quiet')) { $current = '' }
    $supplyType = [string]$Snapshot.SupplyType
    $batteryPercent = [int]$Snapshot.BatteryPercent
    $hyperApp = Test-SmartProcessMatch $ForegroundProcess @($Config.SmartHyperProcessNames)
    $balanceApp = Test-SmartProcessMatch $ForegroundProcess @($Config.SmartBalanceProcessNames)
    $applicationRule = Resolve-ApplicationRule $Config $ForegroundProcess $ForegroundFullscreen $RunningProcesses
    $ruleProfile = if ($null -ne $applicationRule) { [string]$applicationRule.Profile } else { '' }
    $ruleDescription = if ($null -ne $applicationRule) { "$($applicationRule.ProcessName) [$($applicationRule.Scope)] -> $ruleProfile" } else { '' }
    $ignoredFullscreen = $ForegroundFullscreen -and (Test-IgnoredFullscreenProcess $Config $ForegroundProcess)
    $effectiveFullscreen = [bool]$Config.SmartFullscreenEnabled -and $ForegroundFullscreen -and
        -not $SessionLocked -and -not $ignoredFullscreen
    $browserFullscreen = $effectiveFullscreen -and (Test-SmartProcessMatch $ForegroundProcess @($Config.SmartBrowserProcesses))
    $fullscreenCpuFloor = if ($browserFullscreen) { [double]$Config.SmartBrowserFullscreenCpuFloor } else { [double]$Config.SmartFullscreenCpuFloor }
    $fullscreenGpuFloor = if ($browserFullscreen) { [double]$Config.SmartBrowserFullscreenGpuFloor } else { [double]$Config.SmartFullscreenGpuFloor }
    $fullscreenCorroborated = $effectiveFullscreen -and
        ($CpuPercent -ge $fullscreenCpuFloor -or $GpuPercent -ge $fullscreenGpuFloor)
    $rawProfile = 'Quiet'
    $reason = 'unverified power source uses Quiet fail-safe'
    $triggerKind = 'Safety'
    $hardTransition = $false

    if ($SessionLocked) {
        $rawProfile = if ($supplyType -eq 'HighPowerAC') { 'Balance' } else { 'Quiet' }
        $reason = 'Windows session is locked'
        $triggerKind = 'Safety'
        $hardTransition = $true
    }
    elseif ($supplyType -eq 'HighPowerAC') {
        if ($ruleProfile -in @('Hyper', 'Balance', 'Quiet')) {
            $rawProfile = $ruleProfile
            $reason = "application rule: $ruleDescription"
            $triggerKind = 'App'
        }
        elseif ($hyperApp) {
            $rawProfile = 'Hyper'
            $reason = "foreground performance app: $ForegroundProcess"
            $triggerKind = 'App'
        }
        elseif ($fullscreenCorroborated) {
            $rawProfile = 'Hyper'
            $reason = "fullscreen workload: $ForegroundProcess at CPU $CpuPercent% / GPU $GpuPercent%"
            $triggerKind = if ($browserFullscreen) { 'BrowserFullscreen' } else { 'App' }
        }
        elseif ($GpuPercent -ge [double]$Config.SmartGpuEnter) {
            $rawProfile = 'Hyper'
            $reason = "sustained GPU load $GpuPercent% on high-power AC"
            $triggerKind = 'Load'
        }
        elseif ($CpuPercent -ge [double]$Config.SmartHighPowerCpuEnter) {
            $rawProfile = 'Hyper'
            $reason = "sustained CPU load $CpuPercent% on high-power AC"
            $triggerKind = 'Load'
        }
        elseif ($current -eq 'Hyper' -and ($CpuPercent -ge [double]$Config.SmartHighPowerCpuExit -or $GpuPercent -ge [double]$Config.SmartGpuExit)) {
            $rawProfile = 'Hyper'
            $reason = "holding Hyper while CPU/GPU remains above exit thresholds"
            $triggerKind = 'Hold'
        }
        else {
            $rawProfile = 'Balance'
            $reason = 'high-power AC is idle or lightly loaded'
            $triggerKind = 'Idle'
        }
    }
    elseif ($supplyType -in @('LowPowerPD', 'Battery')) {
        if ($batteryPercent -ge 0 -and $batteryPercent -lt [int]$Config.BalanceBatteryThreshold) {
            $rawProfile = 'Quiet'
            $reason = "battery below $($Config.BalanceBatteryThreshold)%"
            $triggerKind = 'Safety'
            $hardTransition = $true
        }
        elseif ($ruleProfile -in @('Hyper', 'Balance', 'Quiet')) {
            $rawProfile = if ($ruleProfile -eq 'Hyper') { 'Balance' } else { $ruleProfile }
            $reason = "portable application rule: $ruleDescription"
            $triggerKind = 'App'
        }
        elseif ($fullscreenCorroborated) {
            $rawProfile = 'Balance'
            $reason = "fullscreen workload on portable power: $ForegroundProcess at CPU $CpuPercent% / GPU $GpuPercent%"
            $triggerKind = if ($browserFullscreen) { 'BrowserFullscreen' } else { 'App' }
        }
        elseif ($balanceApp -and $CpuPercent -ge [double]$Config.SmartAppCpuFloor) {
            $rawProfile = 'Balance'
            $reason = "active productivity app: $ForegroundProcess at $CpuPercent% CPU"
            $triggerKind = 'App'
        }
        elseif ($GpuPercent -ge [double]$Config.SmartGpuEnter) {
            $rawProfile = 'Balance'
            $reason = "sustained GPU load $GpuPercent% on portable power"
            $triggerKind = 'Load'
        }
        elseif ($CpuPercent -ge [double]$Config.SmartPortableCpuEnter) {
            $rawProfile = 'Balance'
            $reason = "sustained CPU load $CpuPercent% on portable power"
            $triggerKind = 'Load'
        }
        elseif ($current -eq 'Balance' -and ($CpuPercent -ge [double]$Config.SmartPortableCpuExit -or $GpuPercent -ge [double]$Config.SmartGpuExit)) {
            $rawProfile = 'Balance'
            $reason = "holding Balance until CPU falls below $($Config.SmartPortableCpuExit)%"
            $triggerKind = 'Hold'
        }
        else {
            $rawProfile = 'Quiet'
            $reason = 'portable power is idle or lightly loaded'
            $triggerKind = 'Idle'
        }
        if ($current -eq 'Hyper') { $hardTransition = $true }
    }
    else {
        $hardTransition = $true
    }

    $supplyChanged = -not [string]::IsNullOrWhiteSpace([string]$AutomationState.LastSupplyType) -and
        -not [string]::Equals([string]$AutomationState.LastSupplyType, $supplyType, [StringComparison]::OrdinalIgnoreCase)
    if ([string]::IsNullOrWhiteSpace($current)) { $hardTransition = $true }
    if ($supplyChanged) { $hardTransition = $true }

    $nextProfile = $current
    $candidateProfile = [string]$AutomationState.CandidateProfile
    $candidateSamples = [int]$AutomationState.CandidateSamples
    $transitioned = $false
    if ($rawProfile -eq $current) {
        $candidateProfile = ''
        $candidateSamples = 0
    }
    elseif ($hardTransition) {
        $nextProfile = $rawProfile
        $candidateProfile = ''
        $candidateSamples = 0
        $transitioned = $true
    }
    else {
        $dwellSeconds = ($Now - [DateTime]$AutomationState.LastTransitionAt).TotalSeconds
        if ($dwellSeconds -lt [int]$Config.SmartMinimumDwellSeconds) {
            $reason = "minimum dwell active; $reason"
            $candidateProfile = ''
            $candidateSamples = 0
        }
        else {
            if ($candidateProfile -eq $rawProfile) { $candidateSamples++ }
            else { $candidateProfile = $rawProfile; $candidateSamples = 1 }
            $isPromotion = (Get-ProfileRank $rawProfile) -gt (Get-ProfileRank $current)
            $requiredSamples = if (-not $isPromotion) {
                [int]$Config.SmartExitSamples
            }
            elseif ($triggerKind -eq 'App') {
                [int]$Config.SmartAppEnterSamples
            }
            elseif ($triggerKind -eq 'BrowserFullscreen') {
                [int]$Config.SmartBrowserFullscreenSamples
            }
            else {
                [int]$Config.SmartLoadEnterSamples
            }
            if ($candidateSamples -ge $requiredSamples) {
                $nextProfile = $rawProfile
                $candidateProfile = ''
                $candidateSamples = 0
                $transitioned = $true
            }
            else {
                $reason = "pending $rawProfile sample $candidateSamples/$requiredSamples; $reason"
            }
        }
    }

    return [pscustomobject]@{
        Profile = if ([string]::IsNullOrWhiteSpace($nextProfile)) { $rawProfile } else { $nextProfile }
        RawProfile = $rawProfile
        Reason = $reason
        TriggerKind = $triggerKind
        CandidateProfile = $candidateProfile
        CandidateSamples = $candidateSamples
        Transitioned = $transitioned
        SupplyType = $supplyType
        CpuPercent = $CpuPercent
        GpuPercent = $GpuPercent
        ForegroundProcess = $ForegroundProcess
        ForegroundFullscreen = $ForegroundFullscreen
        EffectiveFullscreen = $effectiveFullscreen
        SessionLocked = $SessionLocked
        MatchedRule = $ruleDescription
    }
}

function Update-DgpuActivityState {
    param(
        [object]$Config,
        [object]$Snapshot,
        [object]$AutomationState,
        [object]$Telemetry
    )
    $previousLeakDetected = [bool]$AutomationState.DgpuLeakDetected
    $hasGpuSequence = $null -ne $Telemetry.PSObject.Properties['GpuSampleSequence']
    $gpuSequence = if ($hasGpuSequence) { [long]$Telemetry.GpuSampleSequence } else { 0L }
    $isNewGpuSample = -not $hasGpuSequence -or ($gpuSequence -gt 0 -and $gpuSequence -ne [long]$AutomationState.LastGpuSampleSequence)
    $leakSignal = [string]$Snapshot.SupplyType -in @('Battery', 'LowPowerPD') -and [bool]$Telemetry.GpuAvailable -and
        ([double]$Telemetry.DgpuPercent -ge [double]$Config.DgpuLeakUtilizationPercent -or [double]$Telemetry.DgpuDedicatedMb -ge [double]$Config.DgpuLeakMemoryMb)
    if ($isNewGpuSample) {
        if ($leakSignal) { $AutomationState.DgpuLeakSamples = [int]$AutomationState.DgpuLeakSamples + 1 }
        else { $AutomationState.DgpuLeakSamples = 0 }
        if ($hasGpuSequence) { $AutomationState.LastGpuSampleSequence = $gpuSequence }
        if ($null -ne $Telemetry.PSObject.Properties['GpuSampledAtUtcTicks']) {
            $AutomationState.LastGpuSampledAtUtcTicks = [long]$Telemetry.GpuSampledAtUtcTicks
        }
        if ($null -ne $Telemetry.PSObject.Properties['GpuSampleAgeSeconds']) {
            $AutomationState.LastGpuSampleAgeSeconds = [double]$Telemetry.GpuSampleAgeSeconds
        }
    }
    $AutomationState.DgpuLeakDetected = ([int]$AutomationState.DgpuLeakSamples -ge [int]$Config.DgpuLeakMinimumSamples)
    $smoothedDischarge = if ($null -ne $Snapshot.PSObject.Properties['BatteryDischargeAverage10mW'] -and
        $null -ne $Snapshot.BatteryDischargeAverage10mW) {
        [double]$Snapshot.BatteryDischargeAverage10mW
    } elseif ($null -ne $Snapshot.PSObject.Properties['BatteryDischargeW'] -and $null -ne $Snapshot.BatteryDischargeW) {
        [double]$Snapshot.BatteryDischargeW
    } else { 0.0 }
    $AutomationState.DgpuActivityConfidence = if (-not [bool]$AutomationState.DgpuLeakDetected) {
        'None'
    } elseif ([double]$Telemetry.DgpuPercent -ge 5 -and $smoothedDischarge -ge [double]$Config.DgpuActivityDischargeThresholdW) {
        'High'
    } elseif ([double]$Telemetry.DgpuPercent -ge [double]$Config.DgpuLeakUtilizationPercent -or
        $smoothedDischarge -ge [double]$Config.DgpuActivityDischargeThresholdW) {
        'Medium'
    } else {
        'Low'
    }
    $AutomationState.DgpuConsumers = [object[]]@($Telemetry.DgpuConsumers)
    if (-not $previousLeakDetected -and [bool]$AutomationState.DgpuLeakDetected) {
        $consumerNames = [string[]]@($Telemetry.DgpuConsumers | ForEach-Object { [string]$_.ProcessName } | Select-Object -Unique)
        Write-AppLog "Sustained dGPU activity suspected on portable power after $($AutomationState.DgpuLeakSamples) samples; confidence=$($AutomationState.DgpuActivityConfidence); consumers=$($consumerNames -join ',')."
    }
    elseif ($previousLeakDetected -and -not [bool]$AutomationState.DgpuLeakDetected) {
        Write-AppLog 'Suspected dGPU activity signal cleared.'
    }
}

function Update-ManualTelemetryState {
    param(
        [object]$Config,
        [object]$Snapshot,
        [object]$AutomationState,
        [ValidateSet('Auto', 'Hyper', 'Balance', 'Quiet', 'Experiment')][string]$Selection,
        [AllowNull()][object]$Telemetry = $null
    )
    if ($null -eq $Telemetry) { $Telemetry = Get-SmartAutomationTelemetry $Config }
    $sessionLocked = $null -ne $Telemetry.PSObject.Properties['SessionLocked'] -and [bool]$Telemetry.SessionLocked
    if ($Selection -in @('Hyper', 'Balance', 'Quiet', 'Experiment')) { $AutomationState.CurrentProfile = $Selection }
    $AutomationState.CandidateProfile = ''
    $AutomationState.CandidateSamples = 0
    $AutomationState.LastSupplyType = [string]$Snapshot.SupplyType
    $AutomationState.LastReason = if ($Selection -eq 'Auto') {
        'Smart Auto switching disabled; telemetry only'
    } else {
        "manual $Selection selected; Smart Auto decisions paused"
    }
    $AutomationState.LastCpuPercent = [double]$Telemetry.CpuPercent
    $AutomationState.LastGpuPercent = [double]$Telemetry.GpuPercent
    $AutomationState.ForegroundProcess = [string]$Telemetry.ForegroundProcess
    $AutomationState.ForegroundFullscreen = [bool]$Telemetry.ForegroundFullscreen
    $AutomationState.SessionLocked = $sessionLocked
    $AutomationState.MatchedRule = ''
    Update-DgpuActivityState $Config $Snapshot $AutomationState $Telemetry
    return $Telemetry
}

function Update-SmartAutomationState {
    param(
        [object]$Config,
        [object]$Snapshot,
        [object]$AutomationState,
        [AllowNull()][object]$Telemetry = $null,
        [DateTime]$Now = (Get-Date)
    )
    if ($null -eq $Telemetry) { $Telemetry = Get-SmartAutomationTelemetry $Config }
    $sessionLocked = $null -ne $Telemetry.PSObject.Properties['SessionLocked'] -and [bool]$Telemetry.SessionLocked
    $decision = Resolve-SmartAutomationDecision $Config $Snapshot $AutomationState ([double]$Telemetry.CpuPercent) ([string]$Telemetry.ForegroundProcess) $Now ([double]$Telemetry.GpuPercent) ([bool]$Telemetry.ForegroundFullscreen) @($Telemetry.RunningProcesses) $sessionLocked
    $previous = [string]$AutomationState.CurrentProfile
    $AutomationState.CurrentProfile = [string]$decision.Profile
    $AutomationState.CandidateProfile = [string]$decision.CandidateProfile
    $AutomationState.CandidateSamples = [int]$decision.CandidateSamples
    $AutomationState.LastSupplyType = [string]$decision.SupplyType
    $AutomationState.LastReason = [string]$decision.Reason
    $AutomationState.LastCpuPercent = [double]$decision.CpuPercent
    $AutomationState.LastGpuPercent = [double]$decision.GpuPercent
    $AutomationState.ForegroundProcess = [string]$decision.ForegroundProcess
    $AutomationState.ForegroundFullscreen = [bool]$decision.EffectiveFullscreen
    $AutomationState.SessionLocked = [bool]$decision.SessionLocked
    $AutomationState.MatchedRule = [string]$decision.MatchedRule
    Update-DgpuActivityState $Config $Snapshot $AutomationState $Telemetry
    if ([bool]$decision.Transitioned -or [string]::IsNullOrWhiteSpace($previous)) {
        $AutomationState.LastTransitionAt = $Now
        Write-AppLog "Smart Auto decision: $previous -> $($decision.Profile); reason=$($decision.Reason); supply=$($decision.SupplyType); CPU=$($decision.CpuPercent)%; GPU=$($decision.GpuPercent)%; foreground=$($decision.ForegroundProcess); fullscreen=$($decision.ForegroundFullscreen)."
    }
    return $decision
}

function Test-BalanceEligible {
    param([object]$Snapshot, [int]$Threshold = 50)
    return ($Snapshot.BatteryPercent -ge $Threshold)
}

function Resolve-HyperCpuPolicy {
    param([object]$Config)
    $name = if ([string]$Config.HyperCpuPolicy -eq 'Latency') { 'Latency' } else { 'Sustained' }
    if ($name -eq 'Latency') {
        return [pscustomobject]@{
            Name = $name
            Minimum = 100
            Minimum1 = 100
            Minimum2 = 100
            MinCores = 100
            MinCores1 = 100
        }
    }
    return [pscustomobject]@{
        Name = $name
        Minimum = 5
        Minimum1 = 5
        Minimum2 = 5
        MinCores = 100
        MinCores1 = 0
    }
}

function Apply-HyperCpuPolicy {
    param([object]$Config, [object]$State)
    $policy = Resolve-HyperCpuPolicy $Config
    $hyperGuid = [string]$State.HyperPlanGuid
    $signature = "$hyperGuid|$($policy.Name)"
    if ([string]$script:LastAppliedHyperCpuPolicy -eq $signature) { return $policy }

    Set-PlanPair $hyperGuid $script:Guids.Processor $script:Guids.ProcessorMinimum $policy.Minimum $policy.Minimum
    Set-PlanPair $hyperGuid $script:Guids.Processor $script:Guids.ProcessorMinimum1 $policy.Minimum1 $policy.Minimum1 -Optional
    Set-PlanPair $hyperGuid $script:Guids.Processor $script:Guids.ProcessorMinimum2 $policy.Minimum2 $policy.Minimum2 -Optional
    Set-PlanPair $hyperGuid $script:Guids.Processor $script:Guids.ProcessorMinCores $policy.MinCores $policy.MinCores -Optional
    Set-PlanPair $hyperGuid $script:Guids.Processor $script:Guids.ProcessorMinCores1 $policy.MinCores1 $policy.MinCores1 -Optional
    if ([string]::Equals((Get-ActivePlanGuid), $hyperGuid, [StringComparison]::OrdinalIgnoreCase)) {
        Invoke-PowerCfg @('/setactive', $hyperGuid) | Out-Null
    }
    $script:LastAppliedHyperCpuPolicy = $signature
    Write-AppLog "Hyper CPU policy applied: $($policy.Name), minimum=$($policy.Minimum)/$($policy.Minimum1)/$($policy.Minimum2)%, unpark=$($policy.MinCores)/$($policy.MinCores1)%."
    return $policy
}

function Resolve-QuietCpuMaxPercent {
    param([object]$Config, [AllowNull()][object]$Snapshot)
    if (-not [bool]$Config.AdaptiveQuietCpu) { return 80 }

    $batteryPercent = if ($null -ne $Snapshot -and [int]$Snapshot.BatteryPercent -ge 0) {
        [int]$Snapshot.BatteryPercent
    } else { 100 }
    if ($batteryPercent -lt [int]$Config.QuietCpuLowThreshold) {
        return [int]$Config.QuietCpuMaxLowBattery
    }
    if ($batteryPercent -lt [int]$Config.QuietCpuMediumThreshold) {
        return [int]$Config.QuietCpuMaxMediumBattery
    }
    return [int]$Config.QuietCpuMaxHighBattery
}

function Resolve-QuietCpuEppPercent {
    param([object]$Config, [AllowNull()][object]$Snapshot)
    if (-not [bool]$Config.AdaptiveQuietCpu) { return 90 }

    $batteryPercent = if ($null -ne $Snapshot -and [int]$Snapshot.BatteryPercent -ge 0) {
        [int]$Snapshot.BatteryPercent
    } else { 100 }
    if ($batteryPercent -lt [int]$Config.QuietCpuLowThreshold) { return 100 }
    if ($batteryPercent -lt [int]$Config.QuietCpuMediumThreshold) { return 95 }
    return 90
}

function Apply-QuietDynamicCpuPolicy {
    param([object]$Config, [object]$State, [AllowNull()][object]$Snapshot)
    $target = Resolve-QuietCpuMaxPercent $Config $Snapshot
    $quietGuid = [string]$State.QuietPlanGuid
    $epp = Resolve-QuietCpuEppPercent $Config $Snapshot
    $signature = "$quietGuid|$target|$epp|4"
    if ([string]$script:LastAppliedQuietCpuMax -eq $signature) { return $target }

    foreach ($setting in @(
        $script:Guids.ProcessorMaximum,
        $script:Guids.ProcessorMaximum1,
        $script:Guids.ProcessorMaximum2
    )) {
        Set-PlanValue $quietGuid DC $script:Guids.Processor $setting $target -Optional:($setting -ne $script:Guids.ProcessorMaximum)
    }
    foreach ($setting in @(
        $script:Guids.ProcessorEpp,
        $script:Guids.ProcessorEpp1,
        $script:Guids.ProcessorEpp2
    )) {
        Set-PlanValue $quietGuid DC $script:Guids.Processor $setting $epp -Optional
    }
    Set-PlanValue $quietGuid DC $script:Guids.Processor $script:Guids.ProcessorScheduling 4 -Optional
    Set-PlanValue $quietGuid DC $script:Guids.Processor $script:Guids.ProcessorShortScheduling 4 -Optional
    if ([string]::Equals((Get-ActivePlanGuid), $quietGuid, [StringComparison]::OrdinalIgnoreCase)) {
        Invoke-PowerCfg @('/setactive', $quietGuid) | Out-Null
    }
    $script:LastAppliedQuietCpuMax = $signature
    Write-AppLog "Quiet DC CPU policy set across all efficiency classes: maximum=$target%, EPP=$epp, scheduler=prefer-efficient, battery=$($Snapshot.BatteryPercent)%."
    return $target
}

function Get-InstalledState {
    $state = Get-AppState
    if ($null -eq $state) { throw 'OpenSynapse is not installed.' }
    if (-not (Test-PlanExists ([string]$state.HyperPlanGuid)) -or
        -not (Test-PlanExists ([string]$state.BalancePlanGuid)) -or
        -not (Test-PlanExists ([string]$state.QuietPlanGuid)) -or
        -not (Test-PlanExists ([string]$state.ExperimentPlanGuid))) {
        throw 'OpenSynapse plans are missing. Run the installer to repair them.'
    }
    return $state
}

function Stop-TrackedProcess {
    param(
        [string[]]$Names,
        [AllowNull()][object]$Config = $null,
        [DateTime]$Now = (Get-Date)
    )
    $closed = New-Object Collections.Generic.List[string]
    $restarted = New-Object Collections.Generic.List[string]
    $cooling = New-Object Collections.Generic.List[string]
    $restartWindowSeconds = if ($null -ne $Config) { [int]$Config.QuietProcessRestartWindowSeconds } else { 600 }
    $cooldownSeconds = if ($null -ne $Config) { [int]$Config.QuietProcessCooldownSeconds } else { 1800 }
    foreach ($name in $Names) {
        $processName = [string]$name
        if ([string]::IsNullOrWhiteSpace($processName)) { continue }
        $guard = if ($script:QuietProcessGuard.ContainsKey($processName)) {
            $script:QuietProcessGuard[$processName]
        } else { $null }
        if ($null -ne $guard -and [DateTime]$guard.CooldownUntil -gt $Now) {
            continue
        }
        $runningProcesses = @(Get-Process -Name $processName -ErrorAction SilentlyContinue)
        if ($runningProcesses.Count -eq 0) { continue }
        if ($null -ne $guard -and [DateTime]$guard.LastStoppedAt -ne [DateTime]::MinValue -and
            ($Now - [DateTime]$guard.LastStoppedAt).TotalSeconds -le $restartWindowSeconds) {
            $guard.RestartCount = [int]$guard.RestartCount + 1
            $guard.CooldownUntil = $Now.AddSeconds($cooldownSeconds)
            $script:QuietProcessGuard[$processName] = $guard
            $restarted.Add($processName)
            $cooling.Add($processName)
            Write-AppLog "Quiet restart detected for $processName; process enforcement cooling down until $($guard.CooldownUntil.ToString('s')) to avoid a restart/termination loop."
            continue
        }
        $processClosed = $false
        foreach ($process in $runningProcesses) {
            try {
                Stop-Process -Id $process.Id -Force -ErrorAction Stop
                $processClosed = $true
                if (-not $closed.Contains($process.ProcessName)) { $closed.Add($process.ProcessName) }
            }
            catch { Write-AppLog "Cannot stop process $($process.ProcessName): $($_.Exception.Message)" }
        }
        if ($processClosed) {
            $script:QuietProcessGuard[$processName] = [pscustomobject]@{
                LastStoppedAt = $Now
                CooldownUntil = [DateTime]::MinValue
                RestartCount = if ($null -eq $guard) { 0 } else { [int]$guard.RestartCount }
            }
        }
    }
    if ($closed.Count -gt 0) { Write-AppLog "Quiet closed processes: $($closed -join ', ')" }
    return [pscustomobject]@{
        Closed = [string[]]@($closed)
        Restarted = [string[]]@($restarted)
        CoolingDown = [string[]]@($cooling)
    }
}

function Stop-QuietServices {
    param([object]$Config, [object]$State)
    if (-not [bool]$Config.ManageAsusServices) { return }
    $tracked = New-Object Collections.Generic.List[string]
    foreach ($existing in @($State.ServicesStoppedByUs)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$existing)) { $tracked.Add([string]$existing) }
    }
    foreach ($name in @($Config.QuietServiceNames)) {
        $service = Get-Service -Name ([string]$name) -ErrorAction SilentlyContinue
        if ($null -ne $service -and $service.Status -ne 'Stopped') {
            try {
                Stop-Service -Name $service.Name -Force -ErrorAction Stop
                if (-not $tracked.Contains($service.Name)) { $tracked.Add($service.Name) }
                Write-AppLog "Quiet stopped service $($service.Name)."
            }
            catch { Write-AppLog "Cannot stop service $($service.Name): $($_.Exception.Message)" }
        }
    }
    $State.ServicesStoppedByUs = @($tracked)
    Save-AppState $State
}

function Restore-QuietServices {
    param([object]$State)
    $remaining = New-Object Collections.Generic.List[string]
    foreach ($name in @($State.ServicesStoppedByUs)) {
        if ([string]::IsNullOrWhiteSpace([string]$name)) { continue }
        try {
            $service = Get-Service -Name ([string]$name) -ErrorAction Stop
            if ($service.Status -eq 'Stopped') { Start-Service -Name $service.Name -ErrorAction Stop }
            Write-AppLog "Restored service $name."
        }
        catch {
            $remaining.Add([string]$name)
            Write-AppLog "Cannot restore service ${name}: $($_.Exception.Message)"
        }
    }
    $State.ServicesStoppedByUs = @($remaining)
    Save-AppState $State
}

function Get-WakeArmedDevices {
    $text = Invoke-PowerCfg @('/devicequery', 'wake_armed') -AllowFailure
    return @($text -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object {
        $_ -and $_ -notmatch 'permission|error|none|not supported'
    })
}

function Disable-QuietWakeDevices {
    param([object]$Config, [object]$State)
    if (-not [bool]$Config.ManageWakeDevices) { return }
    $tracked = New-Object Collections.Generic.List[string]
    foreach ($existing in @($State.DisabledWakeDevices)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$existing)) { $tracked.Add([string]$existing) }
    }
    foreach ($device in @(Get-WakeArmedDevices)) {
        $matches = $false
        foreach ($pattern in @($Config.QuietWakeDevicePatterns)) {
            if ($device -like "*$pattern*") { $matches = $true; break }
        }
        if (-not $matches -or $tracked.Contains($device)) { continue }
        $null = Invoke-PowerCfg @('/devicedisablewake', $device) -AllowFailure
        if ($script:LastPowerCfgExitCode -eq 0) {
            $tracked.Add($device)
            Write-AppLog "Quiet disabled wake: $device"
        }
    }
    $State.DisabledWakeDevices = @($tracked)
    Save-AppState $State
}

function Restore-WakeDevices {
    param([object]$State)
    $remaining = New-Object Collections.Generic.List[string]
    foreach ($device in @($State.DisabledWakeDevices)) {
        if ([string]::IsNullOrWhiteSpace([string]$device)) { continue }
        $null = Invoke-PowerCfg @('/deviceenablewake', [string]$device) -AllowFailure
        if ($script:LastPowerCfgExitCode -ne 0) { $remaining.Add([string]$device) }
        else { Write-AppLog "Restored wake: $device" }
    }
    $State.DisabledWakeDevices = @($remaining)
    Save-AppState $State
}

function Repair-DisplayScaling {
    param([object]$Config)
    if (-not [bool]$Config.DisplayScalingEnabled) { return 0 }
    $changed = 0
    foreach ($display in [OpenSynapseNative.DisplayScaling]::GetActiveDisplays()) {
        $target = if ($display.IsInternal) { [int]$Config.InternalScale } else { [int]$Config.ExternalScale }
        try {
            if ([OpenSynapseNative.DisplayScaling]::SetScale($display, $target)) {
                $changed++
                Write-AppLog "Scale repaired $($display.Role): $($display.CurrentPercent)% -> $target% ($($display.Key))."
            }
        }
        catch { Write-AppLog "Scale repair failed for $($display.Key): $($_.Exception.Message)" }
    }
    $verification = @([OpenSynapseNative.DisplayScaling]::GetActiveDisplays())
    foreach ($display in $verification) {
        $target = if ($display.IsInternal) { [int]$Config.InternalScale } else { [int]$Config.ExternalScale }
        if ([int]$display.CurrentPercent -ne $target) {
            throw "Display scaling verification failed for $($display.GdiDeviceName): expected $target%, actual $($display.CurrentPercent)%."
        }
    }
    return $changed
}

function Get-InternalBrightness {
    try {
        $item = Get-WmiObject -Namespace root\wmi -Class WmiMonitorBrightness -ErrorAction Stop |
            Where-Object { $_.Active } | Select-Object -First 1
        if ($null -ne $item) { return [int]$item.CurrentBrightness }
    }
    catch { Write-AppLog "Brightness read unavailable: $($_.Exception.Message)" }
    return $null
}

function Set-InternalBrightness {
    param([int]$Percent)
    try {
        $methods = @(Get-WmiObject -Namespace root\wmi -Class WmiMonitorBrightnessMethods -ErrorAction Stop |
            Where-Object { $_.Active })
        foreach ($method in $methods) { $null = $method.WmiSetBrightness(1, [byte]$Percent) }
        if ($methods.Count -gt 0) { Write-AppLog "Brightness set to $Percent%." }
        return $methods.Count
    }
    catch {
        Write-AppLog "Brightness control unavailable: $($_.Exception.Message)"
        return 0
    }
}

function Get-MonitorBrightnessStates {
    $result = New-Object Collections.Generic.List[object]
    try {
        foreach ($item in @(Get-WmiObject -Namespace root\wmi -Class WmiMonitorBrightness -ErrorAction Stop)) {
            $result.Add([pscustomobject][ordered]@{
                InstanceName = [string]$item.InstanceName
                CurrentPercent = [int]$item.CurrentBrightness
                Supported = $true
            })
        }
    }
    catch { Write-AppLog "Per-monitor brightness read unavailable: $($_.Exception.Message)" }
    return $result.ToArray()
}

function Restore-MonitorBrightnessStates {
    param([AllowNull()][object[]]$BrightnessStates)
    $changes = 0
    $warnings = New-Object Collections.Generic.List[string]
    $methods = @()
    try { $methods = @(Get-WmiObject -Namespace root\wmi -Class WmiMonitorBrightnessMethods -ErrorAction Stop) }
    catch {
        if (@($BrightnessStates).Count -gt 0) { $warnings.Add("Brightness methods unavailable: $($_.Exception.Message)") }
        return [pscustomobject]@{ Changes = 0; Warnings = $warnings.ToArray() }
    }
    foreach ($captured in @($BrightnessStates)) {
        $method = @($methods | Where-Object { [string]$_.InstanceName -eq [string]$captured.InstanceName }) | Select-Object -First 1
        if ($null -eq $method) {
            $warnings.Add("Brightness target is no longer active: $($captured.InstanceName)")
            continue
        }
        try {
            $current = @(Get-WmiObject -Namespace root\wmi -Class WmiMonitorBrightness -ErrorAction Stop |
                Where-Object { [string]$_.InstanceName -eq [string]$captured.InstanceName }) | Select-Object -First 1
            if ($null -eq $current -or [int]$current.CurrentBrightness -ne [int]$captured.CurrentPercent) {
                $null = $method.WmiSetBrightness(1, [byte]$captured.CurrentPercent)
                $changes++
            }
        }
        catch { $warnings.Add("Brightness restore failed for $($captured.InstanceName): $($_.Exception.Message)") }
    }
    return [pscustomobject]@{ Changes = $changes; Warnings = $warnings.ToArray() }
}

function Get-DisplayStateSnapshot {
    $modes = @([OpenSynapseNative.DisplayModeManager]::GetActiveDisplays() | ForEach-Object {
        [pscustomobject][ordered]@{
            DeviceName = [string]$_.DeviceName
            FriendlyName = [string]$_.FriendlyName
            DeviceId = [string]$_.DeviceId
            DeviceKey = [string]$_.DeviceKey
            MonitorName = [string]$_.MonitorName
            MonitorDeviceId = [string]$_.MonitorDeviceId
            MonitorDeviceKey = [string]$_.MonitorDeviceKey
            Width = [int]$_.Width
            Height = [int]$_.Height
            BitsPerPixel = [int]$_.BitsPerPixel
            Frequency = [int]$_.Frequency
            PositionX = [int]$_.PositionX
            PositionY = [int]$_.PositionY
            Orientation = [int]$_.Orientation
            IsPrimary = [bool]$_.IsPrimary
        }
    })
    $scaling = @([OpenSynapseNative.DisplayScaling]::GetActiveDisplays() | ForEach-Object {
        [pscustomobject][ordered]@{
            Key = [string]$_.Key
            GdiDeviceName = [string]$_.GdiDeviceName
            IsInternal = [bool]$_.IsInternal
            CurrentPercent = [int]$_.CurrentPercent
            RecommendedPercent = [int]$_.RecommendedPercent
        }
    })
    $drr = @([OpenSynapseNative.DynamicRefreshManager]::GetStatuses() | ForEach-Object {
        [pscustomobject][ordered]@{
            Key = [string]$_.Key
            GdiDeviceName = [string]$_.GdiDeviceName
            IsInternal = [bool]$_.IsInternal
            Supported = [bool]$_.Supported
            Enabled = [bool]$_.Enabled
            BaseFrequency = [int]$_.BaseFrequency
            BoostFrequency = [int]$_.BoostFrequency
        }
    })
    $colors = @([OpenSynapseNative.AdvancedColorManager]::GetStatus() | ForEach-Object {
        [pscustomobject][ordered]@{
            Key = [string]$_.Key
            GdiDeviceName = [string]$_.GdiDeviceName
            Supported = [bool]$_.Supported
            Enabled = [bool]$_.Enabled
            BitsPerColorChannel = [uint32]$_.BitsPerColorChannel
        }
    })
    $profiles = @([OpenSynapseNative.ColorProfileManager]::GetStatus() | ForEach-Object {
        $profilePath = [string]$_.ProfilePath
        $profileHash = ''
        if ([bool]$_.Available -and (Test-Path -LiteralPath $profilePath)) {
            try { $profileHash = [string](Get-FileHash -LiteralPath $profilePath -Algorithm SHA256 -ErrorAction Stop).Hash }
            catch { $profileHash = '' }
        }
        [pscustomobject][ordered]@{
            GdiDeviceName = [string]$_.GdiDeviceName
            Available = [bool]$_.Available
            ProfilePath = $profilePath
            ProfileSha256 = $profileHash
            Error = [string]$_.Error
        }
    })
    $physicalBrightness = @()
    try {
        $physicalBrightness = @([OpenSynapseNative.PhysicalMonitorBrightnessManager]::GetStatus() | ForEach-Object {
            [pscustomobject][ordered]@{
                GdiDeviceName = [string]$_.GdiDeviceName
                PhysicalIndex = [int]$_.PhysicalIndex
                Description = [string]$_.Description
                Supported = [bool]$_.Supported
                Minimum = [uint32]$_.Minimum
                Current = [uint32]$_.Current
                Maximum = [uint32]$_.Maximum
                CurrentPercent = [int]$_.CurrentPercent
                Error = [string]$_.Error
            }
        })
    }
    catch { $physicalBrightness = @([pscustomobject]@{ GdiDeviceName = ''; PhysicalIndex = -1; Description = ''; Supported = $false; Minimum = 0; Current = 0; Maximum = 0; CurrentPercent = 0; Error = $_.Exception.Message }) }
    return [pscustomobject][ordered]@{
        Version = 2
        CapturedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        Modes = $modes
        Scaling = $scaling
        DynamicRefresh = $drr
        AdvancedColor = $colors
        ColorProfiles = $profiles
        Brightness = @(Get-MonitorBrightnessStates)
        PhysicalBrightness = $physicalBrightness
    }
}

function Compare-DisplayStateSnapshot {
    param([object]$ExpectedSnapshot, [AllowNull()][object]$ActualSnapshot = $null)
    if ($null -eq $ActualSnapshot) { $ActualSnapshot = Get-DisplayStateSnapshot }
    $differences = New-Object Collections.Generic.List[string]

    foreach ($expectedMode in @($ExpectedSnapshot.Modes)) {
        $hasStableMonitorKey = $null -ne $expectedMode.PSObject.Properties['MonitorDeviceKey'] -and
            -not [string]::IsNullOrWhiteSpace([string]$expectedMode.MonitorDeviceKey)
        $currentMode = @($ActualSnapshot.Modes | Where-Object {
            ($hasStableMonitorKey -and [string]$_.MonitorDeviceKey -eq [string]$expectedMode.MonitorDeviceKey) -or
            (-not $hasStableMonitorKey -and [string]$_.DeviceName -eq [string]$expectedMode.DeviceName)
        }) | Select-Object -First 1
        if ($null -eq $currentMode) { $differences.Add("Display missing: $($expectedMode.DeviceName)"); continue }
        if ([int]$currentMode.Width -ne [int]$expectedMode.Width -or [int]$currentMode.Height -ne [int]$expectedMode.Height -or
            [int]$currentMode.BitsPerPixel -ne [int]$expectedMode.BitsPerPixel -or
            [Math]::Abs([int]$currentMode.Frequency - [int]$expectedMode.Frequency) -gt 1 -or
            [int]$currentMode.PositionX -ne [int]$expectedMode.PositionX -or [int]$currentMode.PositionY -ne [int]$expectedMode.PositionY -or
            [int]$currentMode.Orientation -ne [int]$expectedMode.Orientation) {
            $differences.Add("Mode differs on $($expectedMode.DeviceName): expected $($expectedMode.Width)x$($expectedMode.Height)@$($expectedMode.Frequency), actual $($currentMode.Width)x$($currentMode.Height)@$($currentMode.Frequency)")
        }
    }
    foreach ($actualMode in @($ActualSnapshot.Modes)) {
        $hasStableMonitorKey = $null -ne $actualMode.PSObject.Properties['MonitorDeviceKey'] -and
            -not [string]::IsNullOrWhiteSpace([string]$actualMode.MonitorDeviceKey)
        if (@($ExpectedSnapshot.Modes | Where-Object {
            ($hasStableMonitorKey -and $null -ne $_.PSObject.Properties['MonitorDeviceKey'] -and
                [string]$_.MonitorDeviceKey -eq [string]$actualMode.MonitorDeviceKey) -or
            (-not $hasStableMonitorKey -and [string]$_.DeviceName -eq [string]$actualMode.DeviceName)
        }).Count -eq 0) {
            $differences.Add("Unexpected display became active: $($actualMode.DeviceName)")
        }
    }
    foreach ($expectedScale in @($ExpectedSnapshot.Scaling)) {
        $currentScale = @($ActualSnapshot.Scaling | Where-Object {
            [string]$_.GdiDeviceName -eq [string]$expectedScale.GdiDeviceName -or [string]$_.Key -eq [string]$expectedScale.Key
        }) | Select-Object -First 1
        if ($null -eq $currentScale) { $differences.Add("Scaling path missing: $($expectedScale.GdiDeviceName)") }
        elseif ([int]$currentScale.CurrentPercent -ne [int]$expectedScale.CurrentPercent) {
            $differences.Add("Scaling differs on $($expectedScale.GdiDeviceName): expected $($expectedScale.CurrentPercent)%, actual $($currentScale.CurrentPercent)%")
        }
    }
    foreach ($expectedDrr in @($ExpectedSnapshot.DynamicRefresh)) {
        $currentDrr = @($ActualSnapshot.DynamicRefresh | Where-Object {
            [string]$_.Key -eq [string]$expectedDrr.Key -or [string]$_.GdiDeviceName -eq [string]$expectedDrr.GdiDeviceName
        }) | Select-Object -First 1
        if ($null -eq $currentDrr) { $differences.Add("DRR path missing: $($expectedDrr.GdiDeviceName)") }
        elseif ([bool]$currentDrr.Enabled -ne [bool]$expectedDrr.Enabled -or
            [Math]::Abs([int]$currentDrr.BaseFrequency - [int]$expectedDrr.BaseFrequency) -gt 1 -or
            ([bool]$expectedDrr.Enabled -and [Math]::Abs([int]$currentDrr.BoostFrequency - [int]$expectedDrr.BoostFrequency) -gt 1)) {
            $differences.Add("DRR differs on $($expectedDrr.GdiDeviceName): expected enabled=$($expectedDrr.Enabled) $($expectedDrr.BaseFrequency)-$($expectedDrr.BoostFrequency), actual enabled=$($currentDrr.Enabled) $($currentDrr.BaseFrequency)-$($currentDrr.BoostFrequency)")
        }
    }
    foreach ($expectedColor in @($ExpectedSnapshot.AdvancedColor | Where-Object { [bool]$_.Supported })) {
        $currentColor = @($ActualSnapshot.AdvancedColor | Where-Object { [string]$_.Key -eq [string]$expectedColor.Key }) | Select-Object -First 1
        if ($null -eq $currentColor) { $differences.Add("Advanced Color path missing: $($expectedColor.GdiDeviceName)") }
        elseif ([bool]$currentColor.Enabled -ne [bool]$expectedColor.Enabled) {
            $differences.Add("Advanced Color differs on $($expectedColor.GdiDeviceName): expected $($expectedColor.Enabled), actual $($currentColor.Enabled)")
        }
    }
    foreach ($expectedProfile in @($ExpectedSnapshot.ColorProfiles | Where-Object { [bool]$_.Available })) {
        $expectedMode = @($ExpectedSnapshot.Modes | Where-Object { [string]$_.DeviceName -eq [string]$expectedProfile.GdiDeviceName }) | Select-Object -First 1
        $currentDeviceName = [string]$expectedProfile.GdiDeviceName
        if ($null -ne $expectedMode -and $null -ne $expectedMode.PSObject.Properties['MonitorDeviceKey'] -and
            -not [string]::IsNullOrWhiteSpace([string]$expectedMode.MonitorDeviceKey)) {
            $currentIdentityMode = @($ActualSnapshot.Modes | Where-Object { [string]$_.MonitorDeviceKey -eq [string]$expectedMode.MonitorDeviceKey }) | Select-Object -First 1
            $currentDeviceName = if ($null -ne $currentIdentityMode) { [string]$currentIdentityMode.DeviceName } else { '' }
        }
        $currentProfile = @($ActualSnapshot.ColorProfiles | Where-Object { [string]$_.GdiDeviceName -eq $currentDeviceName }) | Select-Object -First 1
        if ($null -eq $currentProfile -or -not [bool]$currentProfile.Available) { $differences.Add("ICC profile unavailable: $($expectedProfile.GdiDeviceName)") }
        elseif (-not [string]::Equals([string]$currentProfile.ProfilePath, [string]$expectedProfile.ProfilePath, [StringComparison]::OrdinalIgnoreCase)) {
            $differences.Add("ICC profile differs on $($expectedProfile.GdiDeviceName)")
        }
        elseif ($null -ne $expectedProfile.PSObject.Properties['ProfileSha256'] -and
            -not [string]::IsNullOrWhiteSpace([string]$expectedProfile.ProfileSha256) -and
            -not [string]::Equals([string]$currentProfile.ProfileSha256, [string]$expectedProfile.ProfileSha256, [StringComparison]::OrdinalIgnoreCase)) {
            $differences.Add("ICC profile file hash differs on $($expectedProfile.GdiDeviceName)")
        }
    }
    foreach ($expectedBrightness in @($ExpectedSnapshot.Brightness)) {
        $currentBrightness = @($ActualSnapshot.Brightness | Where-Object { [string]$_.InstanceName -eq [string]$expectedBrightness.InstanceName }) | Select-Object -First 1
        if ($null -eq $currentBrightness) { $differences.Add("Brightness endpoint missing: $($expectedBrightness.InstanceName)") }
        elseif ([int]$currentBrightness.CurrentPercent -ne [int]$expectedBrightness.CurrentPercent) {
            $differences.Add("Brightness differs on $($expectedBrightness.InstanceName): expected $($expectedBrightness.CurrentPercent)%, actual $($currentBrightness.CurrentPercent)%")
        }
    }
    if ($null -ne $ExpectedSnapshot.PSObject.Properties['PhysicalBrightness']) {
        foreach ($expectedBrightness in @($ExpectedSnapshot.PhysicalBrightness | Where-Object { [bool]$_.Supported })) {
            $expectedMode = @($ExpectedSnapshot.Modes | Where-Object { [string]$_.DeviceName -eq [string]$expectedBrightness.GdiDeviceName }) | Select-Object -First 1
            $currentDeviceName = [string]$expectedBrightness.GdiDeviceName
            if ($null -ne $expectedMode -and $null -ne $expectedMode.PSObject.Properties['MonitorDeviceKey'] -and
                -not [string]::IsNullOrWhiteSpace([string]$expectedMode.MonitorDeviceKey)) {
                $currentIdentityMode = @($ActualSnapshot.Modes | Where-Object { [string]$_.MonitorDeviceKey -eq [string]$expectedMode.MonitorDeviceKey }) | Select-Object -First 1
                $currentDeviceName = if ($null -ne $currentIdentityMode) { [string]$currentIdentityMode.DeviceName } else { '' }
            }
            $currentBrightness = @($ActualSnapshot.PhysicalBrightness | Where-Object {
                [string]$_.GdiDeviceName -eq $currentDeviceName -and
                [int]$_.PhysicalIndex -eq [int]$expectedBrightness.PhysicalIndex
            }) | Select-Object -First 1
            if ($null -eq $currentBrightness -or -not [bool]$currentBrightness.Supported) {
                $differences.Add("DDC/CI brightness endpoint missing: $($expectedBrightness.GdiDeviceName)#$($expectedBrightness.PhysicalIndex)")
            }
            elseif ([uint32]$currentBrightness.Current -ne [uint32]$expectedBrightness.Current) {
                $differences.Add("DDC/CI brightness differs on $($expectedBrightness.GdiDeviceName)#$($expectedBrightness.PhysicalIndex): expected $($expectedBrightness.Current), actual $($currentBrightness.Current)")
            }
        }
    }
    return [pscustomobject][ordered]@{
        Valid = $differences.Count -eq 0
        DifferenceCount = $differences.Count
        Differences = $differences.ToArray()
        Actual = $ActualSnapshot
    }
}

function Restore-DisplayStateSnapshot {
    param([object]$Snapshot)
    $warnings = New-Object Collections.Generic.List[string]
    $changes = 0
    if ($null -eq $Snapshot) { return [pscustomobject]@{ Verified = $true; Changes = 0; Warnings = @(); Differences = @() } }

    try { $changes += [int][OpenSynapseNative.DynamicRefreshManager]::Disable() }
    catch { $warnings.Add("DRR disable before restore failed: $($_.Exception.Message)") }
    $currentModes = @([OpenSynapseNative.DisplayModeManager]::GetActiveDisplays())
    foreach ($mode in @($Snapshot.Modes)) {
        $hasStableMonitorKey = $null -ne $mode.PSObject.Properties['MonitorDeviceKey'] -and
            -not [string]::IsNullOrWhiteSpace([string]$mode.MonitorDeviceKey)
        $currentMode = @($currentModes | Where-Object {
            ($hasStableMonitorKey -and [string]$_.MonitorDeviceKey -eq [string]$mode.MonitorDeviceKey) -or
            (-not $hasStableMonitorKey -and [string]$_.DeviceName -eq [string]$mode.DeviceName)
        }) | Select-Object -First 1
        if ($null -eq $currentMode) { $warnings.Add("Captured physical display is no longer active: $($mode.DeviceName)"); continue }
        try {
            if ([OpenSynapseNative.DisplayModeManager]::RestoreMode(
                [string]$currentMode.DeviceName, [int]$mode.Width, [int]$mode.Height, [int]$mode.BitsPerPixel,
                [int]$mode.Frequency, [int]$mode.PositionX, [int]$mode.PositionY, [int]$mode.Orientation)) { $changes++ }
        }
        catch { $warnings.Add("Mode restore failed for $($mode.DeviceName): $($_.Exception.Message)") }
    }
    $currentScaling = @([OpenSynapseNative.DisplayScaling]::GetActiveDisplays())
    foreach ($captured in @($Snapshot.Scaling)) {
        $target = @($currentScaling | Where-Object {
            [string]$_.GdiDeviceName -eq [string]$captured.GdiDeviceName -or [string]$_.Key -eq [string]$captured.Key
        }) | Select-Object -First 1
        if ($null -eq $target) { $warnings.Add("Scaling path is no longer active: $($captured.GdiDeviceName)"); continue }
        try { if ([OpenSynapseNative.DisplayScaling]::SetScale($target, [int]$captured.CurrentPercent)) { $changes++ } }
        catch { $warnings.Add("Scaling restore failed for $($captured.GdiDeviceName): $($_.Exception.Message)") }
    }
    foreach ($captured in @($Snapshot.AdvancedColor | Where-Object { [bool]$_.Supported })) {
        try { if ([OpenSynapseNative.AdvancedColorManager]::SetEnabled([string]$captured.Key, [bool]$captured.Enabled)) { $changes++ } }
        catch { $warnings.Add("Advanced Color restore failed for $($captured.GdiDeviceName): $($_.Exception.Message)") }
    }
    foreach ($captured in @($Snapshot.ColorProfiles | Where-Object { [bool]$_.Available })) {
        $capturedMode = @($Snapshot.Modes | Where-Object { [string]$_.DeviceName -eq [string]$captured.GdiDeviceName }) | Select-Object -First 1
        $currentDeviceName = [string]$captured.GdiDeviceName
        if ($null -ne $capturedMode -and $null -ne $capturedMode.PSObject.Properties['MonitorDeviceKey'] -and
            -not [string]::IsNullOrWhiteSpace([string]$capturedMode.MonitorDeviceKey)) {
            $currentIdentityMode = @($currentModes | Where-Object { [string]$_.MonitorDeviceKey -eq [string]$capturedMode.MonitorDeviceKey }) | Select-Object -First 1
            $currentDeviceName = if ($null -ne $currentIdentityMode) { [string]$currentIdentityMode.DeviceName } else { '' }
        }
        if ([string]::IsNullOrWhiteSpace($currentDeviceName)) { $warnings.Add("ICC display is no longer active: $($captured.GdiDeviceName)"); continue }
        try { if ([OpenSynapseNative.ColorProfileManager]::SetProfile($currentDeviceName, [string]$captured.ProfilePath)) { $changes++ } }
        catch { $warnings.Add("ICC restore failed for $($captured.GdiDeviceName): $($_.Exception.Message)") }
    }
    $brightnessResult = Restore-MonitorBrightnessStates @($Snapshot.Brightness)
    $changes += [int]$brightnessResult.Changes
    foreach ($warning in @($brightnessResult.Warnings)) { $warnings.Add([string]$warning) }
    if ($null -ne $Snapshot.PSObject.Properties['PhysicalBrightness']) {
        foreach ($captured in @($Snapshot.PhysicalBrightness | Where-Object { [bool]$_.Supported })) {
            $capturedMode = @($Snapshot.Modes | Where-Object { [string]$_.DeviceName -eq [string]$captured.GdiDeviceName }) | Select-Object -First 1
            $currentDeviceName = [string]$captured.GdiDeviceName
            if ($null -ne $capturedMode -and $null -ne $capturedMode.PSObject.Properties['MonitorDeviceKey'] -and
                -not [string]::IsNullOrWhiteSpace([string]$capturedMode.MonitorDeviceKey)) {
                $currentIdentityMode = @($currentModes | Where-Object { [string]$_.MonitorDeviceKey -eq [string]$capturedMode.MonitorDeviceKey }) | Select-Object -First 1
                $currentDeviceName = if ($null -ne $currentIdentityMode) { [string]$currentIdentityMode.DeviceName } else { '' }
            }
            if ([string]::IsNullOrWhiteSpace($currentDeviceName)) { $warnings.Add("DDC/CI display is no longer active: $($captured.GdiDeviceName)"); continue }
            try {
                if ([OpenSynapseNative.PhysicalMonitorBrightnessManager]::SetBrightness(
                    $currentDeviceName, [int]$captured.PhysicalIndex, [uint32]$captured.Current)) { $changes++ }
            }
            catch { $warnings.Add("DDC/CI brightness restore failed for $($captured.GdiDeviceName)#$($captured.PhysicalIndex): $($_.Exception.Message)") }
        }
    }

    $currentDrr = @([OpenSynapseNative.DynamicRefreshManager]::GetStatuses())
    foreach ($captured in @($Snapshot.DynamicRefresh)) {
        $current = @($currentDrr | Where-Object {
            [string]$_.Key -eq [string]$captured.Key -or [string]$_.GdiDeviceName -eq [string]$captured.GdiDeviceName
        }) | Select-Object -First 1
        if ($null -eq $current) { $warnings.Add("DRR path is no longer active: $($captured.GdiDeviceName)"); continue }
        $needsRestore = [bool]$current.Enabled -ne [bool]$captured.Enabled -or
            [Math]::Abs([int]$current.BaseFrequency - [int]$captured.BaseFrequency) -gt 1 -or
            ([bool]$captured.Enabled -and [Math]::Abs([int]$current.BoostFrequency - [int]$captured.BoostFrequency) -gt 1)
        if (-not $needsRestore) { continue }
        try {
            if ([OpenSynapseNative.DynamicRefreshManager]::RestoreStatus(
                [string]$current.GdiDeviceName, [bool]$captured.Enabled,
                [int]$captured.BaseFrequency, [int]$captured.BoostFrequency)) { $changes++ }
        }
        catch { $warnings.Add("DRR restore failed for $($captured.GdiDeviceName): $($_.Exception.Message)") }
    }
    Start-Sleep -Milliseconds 300
    $verification = Compare-DisplayStateSnapshot $Snapshot
    foreach ($difference in @($verification.Differences)) { $warnings.Add([string]$difference) }
    return [pscustomobject][ordered]@{
        Verified = [bool]$verification.Valid
        Changes = $changes
        Warnings = $warnings.ToArray()
        Differences = @($verification.Differences)
    }
}

function Ensure-DisplayStateCaptured {
    param([object]$State)
    if ($null -eq $State.DisplayStateSnapshot) {
        $State.DisplayStateSnapshot = Get-DisplayStateSnapshot
        Save-AppState $State
        Write-AppLog "Captured complete display state for $(@($State.DisplayStateSnapshot.Modes).Count) active display(s)."
    }
    return $State.DisplayStateSnapshot
}

function Resolve-ProfileBrightnessTarget {
    param(
        [ValidateSet('Balance', 'Quiet')][string]$Name,
        [object]$Config,
        [AllowNull()][object]$Snapshot
    )
    if ($Name -eq 'Balance') { return [int]$Config.BalanceBrightness }

    $target = [int]$Config.QuietBrightness
    if ([bool]$Config.AdaptiveQuietBrightness -and $null -ne $Snapshot -and
        [string]$Snapshot.Source -eq 'Battery' -and [int]$Snapshot.BatteryPercent -ge 0) {
        $batteryCap = if ([int]$Snapshot.BatteryPercent -lt 20) { 20 }
            elseif ([int]$Snapshot.BatteryPercent -lt 50) { 30 }
            else { 35 }
        $target = [Math]::Min($target, $batteryCap)
    }
    return [Math]::Max(10, [Math]::Min(100, $target))
}

function Apply-ManagedBrightness {
    param(
        [ValidateSet('Hyper', 'Balance', 'Quiet', 'Experiment')][string]$Name,
        [object]$Config,
        [object]$State,
        [AllowNull()][object]$Snapshot
    )
    if (-not [bool]$Config.ManageBrightness) { return }

    # Smart Auto uses Balance as the efficient idle baseline on the original
    # high-power adapter. Do not dim a plugged-in desktop session merely because
    # CPU demand fell; Balance brightness remains active on PD and battery.
    if ($Name -eq 'Balance' -and $null -ne $Snapshot -and [string]$Snapshot.SupplyType -eq 'HighPowerAC') {
        if ($null -ne $State.CapturedBrightness) {
            $null = Set-InternalBrightness ([int]$State.CapturedBrightness)
            $State.CapturedBrightness = $null
            $script:LastAppliedBrightnessTarget = $null
            Save-AppState $State
        }
        return
    }

    if ($Name -in @('Balance', 'Quiet')) {
        if ($null -eq $State.CapturedBrightness) {
            $State.CapturedBrightness = Get-InternalBrightness
            Save-AppState $State
        }
        $target = Resolve-ProfileBrightnessTarget $Name $Config $Snapshot
        if ($script:LastAppliedBrightnessTarget -ne $target) {
            if ((Set-InternalBrightness $target) -gt 0) { $script:LastAppliedBrightnessTarget = $target }
        }
    }
    elseif ($null -ne $State.CapturedBrightness) {
        $null = Set-InternalBrightness ([int]$State.CapturedBrightness)
        $State.CapturedBrightness = $null
        $script:LastAppliedBrightnessTarget = $null
        Save-AppState $State
    }
}

function Resolve-RefreshPolicy {
    param(
        [object]$Config,
        [ValidateSet('Hyper', 'Balance', 'Quiet', 'Experiment')][string]$ProfileName,
        [AllowNull()][object]$Snapshot = $null
    )
    if ($ProfileName -eq 'Experiment') { return "Fixed$([int]$Config.ExperimentRefreshRate)" }
    if ($ProfileName -eq 'Quiet' -and [string]$Config.Selection -eq 'Quiet') {
        return 'Fixed60'
    }
    if (-not [bool]$Config.ManageRefreshRate -or [string]$Config.RefreshPolicy -eq 'Unmanaged') { return 'Unmanaged' }
    $policy = [string]$Config.RefreshPolicy
    if ($policy -eq 'Auto') {
        if ($null -ne $Snapshot -and [string]$Snapshot.SupplyType -eq 'HighPowerAC') { return 'Fixed240' }
        return 'DynamicNative'
    }
    return $policy
}

function Test-RefreshPolicyApplied {
    param([string]$RefreshPolicy)
    $differences = New-Object Collections.Generic.List[string]
    if ($RefreshPolicy -eq 'Unmanaged' -or [string]::IsNullOrWhiteSpace($RefreshPolicy)) {
        return [pscustomobject]@{ Valid = $true; Differences = @(); State = Get-DisplayStateSnapshot }
    }
    $state = Get-DisplayStateSnapshot
    $drrByName = @{}
    foreach ($item in @($state.DynamicRefresh)) { $drrByName[[string]$item.GdiDeviceName] = $item }

    if ($RefreshPolicy -eq 'DynamicNative') {
        $internal = @($state.DynamicRefresh | Where-Object { [bool]$_.IsInternal })
        if ($internal.Count -gt 0) {
            foreach ($item in $internal) {
                if (-not [bool]$item.Enabled -or [Math]::Abs([int]$item.BaseFrequency - 60) -gt 1 -or [int]$item.BoostFrequency -le 60) {
                    $differences.Add("Native DRR verification failed on $($item.GdiDeviceName): enabled=$($item.Enabled), range=$($item.BaseFrequency)-$($item.BoostFrequency).")
                }
            }
        }
    }
    elseif ($RefreshPolicy -match '^Fixed(?<Hz>60|120|240)$') {
        $targetHz = [int]$Matches.Hz
        foreach ($mode in @($state.Modes)) {
            $drr = if ($drrByName.ContainsKey([string]$mode.DeviceName)) { $drrByName[[string]$mode.DeviceName] } else { $null }
            if ($null -ne $drr -and [bool]$drr.Enabled) {
                $differences.Add("DRR remained enabled on $($mode.DeviceName) after fixed refresh was requested.")
                continue
            }
            $isInternal = $null -ne $drr -and [bool]$drr.IsInternal
            if ($isInternal) {
                if ([Math]::Abs([int]$mode.Frequency - $targetHz) -gt 1) {
                    $differences.Add("Refresh verification failed on $($mode.DeviceName): expected $targetHz Hz, actual $($mode.Frequency) Hz.")
                }
            }
            else {
                $rates = @([OpenSynapseNative.DisplayModeManager]::GetSupportedRefreshRates([string]$mode.DeviceName))
                $maximum = if ($rates.Count -gt 0) { [int]($rates | Measure-Object -Maximum).Maximum } else { [int]$mode.Frequency }
                if ([Math]::Abs([int]$mode.Frequency - $maximum) -gt 1) {
                    $differences.Add("External refresh verification failed on $($mode.DeviceName): expected maximum $maximum Hz, actual $($mode.Frequency) Hz.")
                }
            }
        }
    }
    return [pscustomobject][ordered]@{
        Valid = $differences.Count -eq 0
        Differences = $differences.ToArray()
        State = $state
    }
}

function Apply-DisplayPolicy {
    param(
        [ValidateSet('Hyper', 'Balance', 'Quiet', 'Experiment')][string]$Name,
        [object]$Config,
        [object]$State,
        [switch]$Full,
        [switch]$ApplyVisualPolicy,
        [switch]$ApplyRefreshPolicy,
        [switch]$RepairScaling,
        [AllowNull()][object]$Snapshot
    )
    $refreshWarning = ''
    $refreshPolicy = ''
    $effectiveRefreshPolicy = ''
    $refreshVerified = $null
    if ($ApplyVisualPolicy -or $ApplyRefreshPolicy -or $RepairScaling -or ($Full -and [bool]$Config.ManageBrightness)) {
        $null = Ensure-DisplayStateCaptured $State
    }
    try {
        if ($ApplyVisualPolicy -or $ApplyRefreshPolicy) {
            $refreshPolicy = Resolve-RefreshPolicy $Config $Name $Snapshot
            $effectiveRefreshPolicy = $refreshPolicy
            if ($refreshPolicy -ne 'Unmanaged') {
                Write-AppLog "$Name refresh policy=$refreshPolicy applying."
                if ($refreshPolicy -eq 'DynamicNative') {
                    $dynamicStatus = [OpenSynapseNative.DynamicRefreshManager]::GetStatus()
                    if ([bool]$dynamicStatus.InternalDisplayActive) {
                        $count = [OpenSynapseNative.DynamicRefreshManager]::EnableNativeDynamic()
                    }
                    else {
                        $count = [OpenSynapseNative.DynamicRefreshManager]::ApplyExternalMaximumRefresh()
                        if (((Get-Date) - $script:LastDynamicRefreshDeferredLog).TotalMinutes -ge 30) {
                            Write-AppLog 'Dynamic refresh deferred because the internal panel is inactive; active external displays remain at maximum refresh.'
                            $script:LastDynamicRefreshDeferredLog = Get-Date
                        }
                    }
                }
                else {
                    $null = [OpenSynapseNative.DynamicRefreshManager]::Disable()
                    $count = switch ($refreshPolicy) {
                        'Maximum' { [OpenSynapseNative.DisplayModeManager]::ApplyMaximumRefresh(); break }
                        'Fixed60' { [OpenSynapseNative.DynamicRefreshManager]::ApplyProfileRefresh(60); break }
                        'Fixed120' { [OpenSynapseNative.DynamicRefreshManager]::ApplyProfileRefresh(120); break }
                        'Fixed240' { [OpenSynapseNative.DynamicRefreshManager]::ApplyProfileRefresh(240); break }
                        default { 0 }
                    }
                }
                Start-Sleep -Milliseconds 250
                $refreshVerification = Test-RefreshPolicyApplied $refreshPolicy
                if (-not [bool]$refreshVerification.Valid) {
                    throw "Refresh policy verification failed: $($refreshVerification.Differences -join ' ')"
                }
                $refreshVerified = $true
                Write-AppLog "$Name refresh policy=$refreshPolicy changed=$count."
            }
        }
    }
    catch {
        $dynamicFailure = $_.Exception.Message
        if ($refreshPolicy -eq 'DynamicNative') {
            try {
                $null = [OpenSynapseNative.DynamicRefreshManager]::Disable()
                try { $null = [OpenSynapseNative.DynamicRefreshManager]::ApplyExternalMaximumRefresh() }
                catch { Write-AppLog "External maximum refresh was preserved on a best-effort basis during Eco fallback: $($_.Exception.Message)" }
                $fallbackCount = [OpenSynapseNative.DynamicRefreshManager]::ApplyInternalFixedRefresh(60)
                Start-Sleep -Milliseconds 250
                $fallbackVerification = Test-RefreshPolicyApplied Fixed60
                if (-not [bool]$fallbackVerification.Valid) {
                    throw "Eco 60 Hz fallback verification failed: $($fallbackVerification.Differences -join ' ')"
                }
                $effectiveRefreshPolicy = 'Fixed60'
                $refreshVerified = $true
                $refreshWarning = "$dynamicFailure Auto dynamic refresh failed; the internal display fell back to Eco 60 Hz."
                Write-AppLog "Dynamic refresh failed and safely fell back to Eco 60 Hz; changed=$fallbackCount; error=$dynamicFailure"
            }
            catch {
                $refreshVerified = $false
                $refreshWarning = "$dynamicFailure Eco 60 Hz fallback also failed: $($_.Exception.Message)"
                Write-AppLog "Refresh policy and Eco 60 Hz fallback failed: $refreshWarning"
            }
        }
        else {
            $refreshVerified = $false
            $refreshWarning = $dynamicFailure
            Write-AppLog "Refresh policy failed: $refreshWarning"
        }
    }

    try {
        $manualEco = $Name -eq 'Quiet' -and [string]$Config.Selection -eq 'Quiet'
        $advancedColorNeedsRestore = @($State.AdvancedColorStates).Count -gt 0
        if ($ApplyVisualPolicy -and ([bool]$Config.ManageAdvancedColor -or $manualEco -or $advancedColorNeedsRestore)) {
            if ($Name -in @('Balance', 'Quiet')) {
                if (@($State.AdvancedColorStates).Count -eq 0) {
                    $captured = @()
                    foreach ($item in [OpenSynapseNative.AdvancedColorManager]::GetStatus()) {
                        if ($item.Supported) {
                            $captured += [pscustomobject]@{ Key = $item.Key; Enabled = [bool]$item.Enabled }
                        }
                    }
                    $State.AdvancedColorStates = @($captured)
                    Save-AppState $State
                }
                $count = 0
                foreach ($item in @($State.AdvancedColorStates)) {
                    if ($null -ne $item.PSObject.Properties['Key'] -and
                        -not [string]::IsNullOrWhiteSpace([string]$item.Key) -and
                        [OpenSynapseNative.AdvancedColorManager]::SetEnabled([string]$item.Key, $false)) { $count++ }
                }
            } else {
                $count = 0
                foreach ($item in @($State.AdvancedColorStates)) {
                    if ($null -ne $item.PSObject.Properties['Key'] -and
                        -not [string]::IsNullOrWhiteSpace([string]$item.Key) -and
                        [OpenSynapseNative.AdvancedColorManager]::SetEnabled([string]$item.Key, [bool]$item.Enabled)) { $count++ }
                }
                $State.AdvancedColorStates = @()
                Save-AppState $State
            }
            if ($count -gt 0) { Write-AppLog "$Name changed advanced color on $count display(s)." }
        }
    }
    catch { Write-AppLog "Advanced color policy failed: $($_.Exception.Message)" }

    if ($Full) { Apply-ManagedBrightness $Name $Config $State $Snapshot }

    $scaleChanges = 0
    if ($RepairScaling) {
        Start-Sleep -Milliseconds 250
        $scaleChanges = Repair-DisplayScaling $Config
    }
    return [pscustomobject]@{
        ScaleChanges = $scaleChanges
        RefreshPolicy = $refreshPolicy
        EffectiveRefreshPolicy = $effectiveRefreshPolicy
        RefreshVerified = $refreshVerified
        RefreshWarning = $refreshWarning
    }
}

function Restore-DisplayPolicy {
    param([object]$State)
    $hadCompleteSnapshot = $null -ne $State.DisplayStateSnapshot
    $completeSnapshotRestored = $false
    if ($hadCompleteSnapshot) {
        try {
            $result = Restore-DisplayStateSnapshot $State.DisplayStateSnapshot
            if (-not [bool]$result.Verified) {
                Write-AppLog "Complete display-state restore finished with verification differences: $($result.Differences -join '; ')"
            }
            else {
                Write-AppLog "Complete display state restored and verified; changes=$($result.Changes)."
                $State.DisplayStateSnapshot = $null
                $completeSnapshotRestored = $true
            }
        }
        catch { Write-AppLog "Complete display-state restore failed: $($_.Exception.Message)" }
    }
    if (-not $hadCompleteSnapshot) {
        try {
            foreach ($item in @($State.AdvancedColorStates)) {
                if ($null -ne $item.PSObject.Properties['Key'] -and -not [string]::IsNullOrWhiteSpace([string]$item.Key)) {
                    $null = [OpenSynapseNative.AdvancedColorManager]::SetEnabled([string]$item.Key, [bool]$item.Enabled)
                }
            }
            $State.AdvancedColorStates = @()
        } catch { }
        # Legacy fields remain as a migration fallback for pre-2.5 state files.
        try { $null = [OpenSynapseNative.DynamicRefreshManager]::Disable() } catch { }
        try { [OpenSynapseNative.DisplayModeManager]::RestoreRegistryModes() } catch { }
        if ($null -ne $State.CapturedBrightness) {
            $null = Set-InternalBrightness ([int]$State.CapturedBrightness)
            $State.CapturedBrightness = $null
        }
    }
    elseif ($completeSnapshotRestored) {
        # A verified complete restore is authoritative. Discard migration-era
        # fields without applying them a second time over the restored snapshot.
        $State.AdvancedColorStates = @()
        $State.CapturedBrightness = $null
    }
    Save-AppState $State
}

function Get-NvidiaSnapshot {
    $command = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
    if ($null -eq $command) { return $null }
    try {
        $line = & $command.Source '--query-gpu=name,pstate,power.draw,utilization.gpu,temperature.gpu,clocks.current.graphics,clocks.current.memory,clocks_throttle_reasons.active,display_active,enforced.power.limit,power.default_limit,power.max_limit' '--format=csv,noheader,nounits' 2>$null | Select-Object -First 1
        if (-not $line) { return $null }
        $parts = $line -split ',' | ForEach-Object { $_.Trim() }
        if ($parts.Count -lt 12) { return $null }
        return [pscustomobject]@{
            Name = $parts[0]; PState = $parts[1]; PowerW = $parts[2]; Utilization = $parts[3]
            TemperatureC = $parts[4]; GraphicsClockMhz = $parts[5]; MemoryClockMhz = $parts[6]
            ThrottleReasons = $parts[7]; ThrottlingDetected = $parts[7] -notin @('0x0000000000000000', '0x00000000', '0', 'N/A')
            DisplayActive = $parts[8]; EnforcedLimitW = $parts[9]; DefaultLimitW = $parts[10]; MaximumLimitW = $parts[11]
        }
    }
    catch { return $null }
}

function Get-HardwareTelemetrySnapshot {
    param([AllowNull()][object]$PowerSnapshot = $null, [switch]$Force)
    $minimumSeconds = if ($null -ne $PowerSnapshot -and [string]$PowerSnapshot.Source -eq 'Battery') { 60 } else { 15 }
    if (-not $Force -and $null -ne $script:LastHardwareTelemetry -and
        ((Get-Date) - $script:LastHardwareTelemetryAt).TotalSeconds -lt $minimumSeconds) {
        return $script:LastHardwareTelemetry
    }
    try {
        $script:LastHardwareTelemetry = [OpenSynapseNative.HardwareTelemetry]::Read()
        $script:LastHardwareTelemetryAt = Get-Date
    }
    catch {
        $script:LastHardwareTelemetry = [pscustomobject]@{ Available = $false; Error = $_.Exception.Message }
        $script:LastHardwareTelemetryAt = Get-Date
    }
    return $script:LastHardwareTelemetry
}

function Get-NvidiaHardwareSnapshot {
    param([AllowNull()][object]$PowerSnapshot = $null, [switch]$Force)
    $minimumSeconds = if ($null -ne $PowerSnapshot -and [string]$PowerSnapshot.Source -eq 'Battery') { 60 } else { 30 }
    if (-not $Force -and $null -ne $PowerSnapshot -and [string]$PowerSnapshot.Source -eq 'Battery') {
        $windowsGpu = try { [OpenSynapseNative.GpuTelemetry]::ReadLatest() } catch { $null }
        if ($null -eq $windowsGpu -or -not [bool]$windowsGpu.DiscreteActive) {
            return $script:LastNvidiaHardwareSnapshot
        }
    }
    if (-not $Force -and $null -ne $script:LastNvidiaHardwareSnapshot -and
        ((Get-Date) - $script:LastNvidiaHardwareSnapshotAt).TotalSeconds -lt $minimumSeconds) {
        return $script:LastNvidiaHardwareSnapshot
    }
    $script:LastNvidiaHardwareSnapshot = Get-NvidiaSnapshot
    $script:LastNvidiaHardwareSnapshotAt = Get-Date
    return $script:LastNvidiaHardwareSnapshot
}

function Get-DisplayTelemetrySnapshot {
    param([AllowNull()][object]$PowerSnapshot = $null, [switch]$Force)
    $minimumSeconds = if ($null -ne $PowerSnapshot -and [string]$PowerSnapshot.Source -eq 'Battery') { 60 } else { 30 }
    if (-not $Force -and $null -ne $script:LastDisplayTelemetry -and
        ((Get-Date) - $script:LastDisplayTelemetryAt).TotalSeconds -lt $minimumSeconds) {
        return $script:LastDisplayTelemetry
    }
    try { $script:LastDisplayTelemetry = Get-DisplayStateSnapshot }
    catch {
        $script:LastDisplayTelemetry = [pscustomobject][ordered]@{
            Version = 2
            CapturedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
            Modes = @()
            Scaling = @()
            DynamicRefresh = @()
            AdvancedColor = @()
            ColorProfiles = @()
            Brightness = @()
            PhysicalBrightness = @()
            Error = $_.Exception.Message
        }
    }
    $script:LastDisplayTelemetryAt = Get-Date
    return $script:LastDisplayTelemetry
}

function Get-MachineEnvironmentSnapshot {
    $computer = try { Get-CimInstance Win32_ComputerSystem -ErrorAction Stop } catch { $null }
    $bios = try { Get-CimInstance Win32_BIOS -ErrorAction Stop } catch { $null }
    $processor = try { Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1 } catch { $null }
    $operatingSystem = try { Get-CimInstance Win32_OperatingSystem -ErrorAction Stop } catch { $null }
    $video = try { @(Get-CimInstance Win32_VideoController -ErrorAction Stop | ForEach-Object {
        [pscustomobject][ordered]@{
            Name = [string]$_.Name
            DriverVersion = [string]$_.DriverVersion
            PnpDeviceId = [string]$_.PNPDeviceID
        }
    }) } catch { @() }
    $npuDevices = try { @(Get-CimInstance Win32_PnPEntity -ErrorAction Stop | Where-Object {
        [string]$_.Name -match '(?i)\bNPU\b|neural processing|AI engine|compute accelerator'
    } | ForEach-Object {
        [pscustomobject][ordered]@{ Name = [string]$_.Name; PnpDeviceId = [string]$_.PNPDeviceID; Status = [string]$_.Status }
    }) } catch { @() }
    $ecVersion = 'Unavailable'
    if ($null -ne $bios -and $null -ne $bios.PSObject.Properties['EmbeddedControllerMajorVersion'] -and
        $null -ne $bios.PSObject.Properties['EmbeddedControllerMinorVersion']) {
        $ecMajor = [int]$bios.EmbeddedControllerMajorVersion
        $ecMinor = [int]$bios.EmbeddedControllerMinorVersion
        if ($ecMajor -ge 0 -and $ecMajor -lt 255 -and $ecMinor -ge 0 -and $ecMinor -lt 255) { $ecVersion = "$ecMajor.$ecMinor" }
    }
    return [pscustomobject][ordered]@{
        Manufacturer = if ($null -ne $computer) { [string]$computer.Manufacturer } else { 'Unavailable' }
        Model = if ($null -ne $computer) { [string]$computer.Model } else { 'Unavailable' }
        SystemSku = if ($null -ne $computer -and $null -ne $computer.PSObject.Properties['SystemSKUNumber']) { [string]$computer.SystemSKUNumber } else { '' }
        Processor = if ($null -ne $processor) { [string]$processor.Name } else { 'Unavailable' }
        BiosVersion = if ($null -ne $bios) { [string]$bios.SMBIOSBIOSVersion } else { 'Unavailable' }
        EmbeddedControllerVersion = $ecVersion
        WindowsCaption = if ($null -ne $operatingSystem) { [string]$operatingSystem.Caption } else { [Environment]::OSVersion.VersionString }
        WindowsVersion = if ($null -ne $operatingSystem) { [string]$operatingSystem.Version } else { [Environment]::OSVersion.VersionString }
        WindowsBuild = if ($null -ne $operatingSystem) { [string]$operatingSystem.BuildNumber } else { '' }
        VideoControllers = $video
        NpuDevices = $npuDevices
    }
}

function Export-ExperimentEnvironmentReport {
    param(
        [object]$Config,
        [object]$State,
        [object]$PowerSnapshot,
        [object]$AutomationState,
        [ValidateSet('Manual', 'Start', 'End', 'Restored', 'Drift')][string]$Phase = 'Manual',
        [string]$DestinationPath = ''
    )
    if (-not (Test-Path -LiteralPath $script:ExperimentReportDir)) {
        [IO.Directory]::CreateDirectory($script:ExperimentReportDir) | Out-Null
    }
    $sessionId = if ($null -ne $State.ExperimentSession -and
        $null -ne $State.ExperimentSession.PSObject.Properties['SessionId']) { [string]$State.ExperimentSession.SessionId } else { 'manual' }
    $baseName = 'OpenSynapse-experiment-{0}-{1}-{2}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $sessionId, $Phase.ToLowerInvariant()
    $jsonPath = if ([string]::IsNullOrWhiteSpace($DestinationPath)) {
        Join-Path $script:ExperimentReportDir ($baseName + '.json')
    }
    else { [IO.Path]::GetFullPath($DestinationPath) }
    $htmlPath = [IO.Path]::ChangeExtension($jsonPath, '.html')
    $display = Get-DisplayTelemetrySnapshot $PowerSnapshot -Force
    $verificationTarget = if ($null -ne $State.ExperimentSession -and $Phase -eq 'Restored' -and
        $null -ne $State.ExperimentSession.PSObject.Properties['OriginalDisplayState']) { $State.ExperimentSession.OriginalDisplayState }
        elseif ($null -ne $State.ExperimentSession -and
            $null -ne $State.ExperimentSession.PSObject.Properties['BaselineDisplayState']) { $State.ExperimentSession.BaselineDisplayState }
        else { $null }
    $displayVerification = if ($null -ne $verificationTarget) { Compare-DisplayStateSnapshot $verificationTarget $display } else { $null }
    $hardware = Get-HardwareTelemetrySnapshot $PowerSnapshot -Force
    $nvidia = Get-NvidiaHardwareSnapshot $PowerSnapshot
    $windowsGpu = try { [OpenSynapseNative.GpuTelemetry]::ReadLatest() } catch { [pscustomobject]@{ Available = $false; Error = $_.Exception.Message } }
    $activePlanGuid = try { Get-ActivePlanGuid } catch { 'Unavailable' }
    $manifest = [pscustomobject][ordered]@{
        ReportSchemaVersion = 1
        OpenSynapseVersion = $script:AppVersion
        TelemetrySchemaVersion = $script:TelemetrySchemaVersion
        SessionId = $sessionId
        Phase = $Phase
        GeneratedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        SafetyBoundary = 'Public Windows interfaces only; no EC, fan, OEM heterogeneous-core thresholds, TGP or MUX writes.'
        Machine = Get-MachineEnvironmentSnapshot
        Power = $PowerSnapshot
        Selection = [string]$Config.Selection
        ActivePlanGuid = $activePlanGuid
        Experiment = [pscustomobject][ordered]@{
            Locked = [string]$Config.Selection -eq 'Experiment'
            RefreshTargetHz = [int]$Config.ExperimentRefreshRate
            VerificationSeconds = [int]$Config.ExperimentVerificationSeconds
            StartedAtUtc = if ($null -ne $State.ExperimentSession) { [string]$State.ExperimentSession.StartedAtUtc } else { '' }
        }
        Display = $display
        DisplayVerification = $displayVerification
        PolicyVerification = $script:LastPolicyVerification
        HardwareTelemetry = $hardware
        WindowsGpuTelemetry = $windowsGpu
        NvidiaTelemetry = $nvidia
        AutomationTelemetry = $AutomationState
    }
    $directory = Split-Path -Parent $jsonPath
    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory)) {
        [IO.Directory]::CreateDirectory($directory) | Out-Null
    }
    [IO.File]::WriteAllText($jsonPath, ($manifest | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
    $jsonSha256 = [string](Get-FileHash -LiteralPath $jsonPath -Algorithm SHA256 -ErrorAction Stop).Hash
    $hashPath = $jsonPath + '.sha256'
    [IO.File]::WriteAllText($hashPath, "$jsonSha256  $([IO.Path]::GetFileName($jsonPath))`r`n", [Text.UTF8Encoding]::new($false))

    $encode = { param([object]$Value) [Net.WebUtility]::HtmlEncode([string]$Value) }
    $displayRows = @($display.Modes | ForEach-Object {
        $mode = $_
        $scale = @($display.Scaling | Where-Object { [string]$_.GdiDeviceName -eq [string]$mode.DeviceName }) | Select-Object -First 1
        $drr = @($display.DynamicRefresh | Where-Object { [string]$_.GdiDeviceName -eq [string]$mode.DeviceName }) | Select-Object -First 1
        $color = @($display.AdvancedColor | Where-Object { [string]$_.GdiDeviceName -eq [string]$mode.DeviceName }) | Select-Object -First 1
        $profile = @($display.ColorProfiles | Where-Object { [string]$_.GdiDeviceName -eq [string]$mode.DeviceName }) | Select-Object -First 1
        $physicalBrightness = @($display.PhysicalBrightness | Where-Object { [string]$_.GdiDeviceName -eq [string]$mode.DeviceName -and [bool]$_.Supported })
        $brightnessText = if ($physicalBrightness.Count -gt 0) { @($physicalBrightness | ForEach-Object { "DDC/CI $($_.CurrentPercent)%" }) -join ', ' } else { 'Windows endpoint/unsupported' }
        '<tr><td>{0}</td><td>{1}x{2} @ {3} Hz</td><td>{4}%</td><td>{5}</td><td>{6}</td><td>{7}</td><td>{8}</td></tr>' -f
            (& $encode $mode.DeviceName), $mode.Width, $mode.Height, $mode.Frequency,
            $(if ($null -ne $scale) { $scale.CurrentPercent } else { 'N/A' }),
            $(if ($null -ne $drr) { "enabled=$($drr.Enabled), $($drr.BaseFrequency)-$($drr.BoostFrequency)" } else { 'N/A' }),
            $(if ($null -ne $color) { "enabled=$($color.Enabled), $($color.BitsPerColorChannel)-bit" } else { 'N/A' }),
            (& $encode $(if ($null -ne $profile) { $profile.ProfilePath } else { 'Unavailable' })),
            (& $encode $brightnessText)
    }) -join [Environment]::NewLine
    $verificationText = if ($null -eq $displayVerification) { 'No experiment baseline was active.' }
        elseif ([bool]$displayVerification.Valid) { 'PASS - current display state matches the locked baseline.' }
        else { 'FAIL - ' + (@($displayVerification.Differences) -join '; ') }
    $maximumTemperatureText = if ($null -ne $hardware.PSObject.Properties['MaximumTemperatureC']) { "$($hardware.MaximumTemperatureC) C" } else { 'Unavailable' }
    $thermalThrottleText = if ($null -ne $hardware.PSObject.Properties['ThermalThrottlingDetected']) { [string]$hardware.ThermalThrottlingDetected } else { 'Unavailable' }
    $npuText = if ($null -ne $hardware.PSObject.Properties['NpuAvailable'] -and [bool]$hardware.NpuAvailable) { "$($hardware.NpuUtilizationPercent)% via $($hardware.NpuCounterSet)" } else { 'Not exposed by Windows performance counters' }
    $gpuText = if ($null -ne $windowsGpu -and $null -ne $windowsGpu.PSObject.Properties['Available'] -and [bool]$windowsGpu.Available) { "total=$($windowsGpu.TotalUtilizationPercent)%, dGPU=$($windowsGpu.DiscreteUtilizationPercent)%" } else { 'Windows GPU sample unavailable' }
    $html = @"
<!doctype html><html><head><meta charset="utf-8"><title>OpenSynapse experiment environment</title>
<style>body{font-family:Segoe UI,Arial;background:#0b0f0d;color:#f4f4f4;margin:32px}h1,h2{color:#39df21}table{border-collapse:collapse;width:100%}th,td{border:1px solid #485048;padding:8px;text-align:left}code{color:#b7f7ac}.muted{color:#aab4aa}</style></head><body>
<h1>OpenSynapse experiment environment report</h1><p>Phase: <code>$(& $encode $Phase)</code> | Session: <code>$(& $encode $sessionId)</code> | Generated: <code>$(& $encode $manifest.GeneratedAtUtc)</code></p>
<h2>Verification</h2><p>$(& $encode $verificationText)</p>
<h2>Machine and power</h2><p>$(& $encode $manifest.Machine.Manufacturer) $(& $encode $manifest.Machine.Model) | $(& $encode $manifest.Machine.Processor)</p><p>Selection: <code>$(& $encode $manifest.Selection)</code> | Supply: <code>$(& $encode $PowerSnapshot.SupplyType)</code> | Battery: <code>$(& $encode $PowerSnapshot.BatteryPercent)%</code></p>
<h2>Displays</h2><table><thead><tr><th>Display</th><th>Mode</th><th>Scale</th><th>DRR</th><th>Advanced Color</th><th>ICC profile</th><th>Brightness</th></tr></thead><tbody>$displayRows</tbody></table>
<h2>Hardware telemetry</h2><p>Maximum thermal-zone temperature: <code>$(& $encode $maximumTemperatureText)</code> | Thermal throttling: <code>$(& $encode $thermalThrottleText)</code> | GPU: <code>$(& $encode $gpuText)</code> | NPU: <code>$(& $encode $npuText)</code></p>
<p class="muted">The JSON report beside this file is the machine-readable source of record. SHA-256: <code>$jsonSha256</code>. OpenSynapse does not write EC, fan, OEM heterogeneous-core thresholds, TGP or MUX settings.</p></body></html>
"@
    [IO.File]::WriteAllText($htmlPath, $html, [Text.UTF8Encoding]::new($false))
    Write-AppLog "Experiment environment report exported: phase=$Phase path=$jsonPath"
    return [pscustomobject][ordered]@{ JsonPath = $jsonPath; HtmlPath = $htmlPath; HashPath = $hashPath; JsonSha256 = $jsonSha256; Manifest = $manifest }
}

function Initialize-ExperimentSession {
    param([object]$State)
    if ($null -ne $State.ExperimentSession) { return $false }
    $State.ExperimentSession = [pscustomobject][ordered]@{
        Version = 1
        SessionId = [Guid]::NewGuid().ToString('N').Substring(0, 12)
        StartedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        OriginalDisplayState = Get-DisplayStateSnapshot
        BaselineDisplayState = $null
        StartReportJson = ''
        StartReportHtml = ''
    }
    Save-AppState $State
    Write-AppLog "Experiment session initialized: $($State.ExperimentSession.SessionId)."
    return $true
}

function Complete-ExperimentSessionStart {
    param([object]$Config, [object]$State, [object]$PowerSnapshot, [object]$AutomationState, [switch]$NewSession)
    if ($NewSession -or $null -eq $State.ExperimentSession.BaselineDisplayState) {
        $State.ExperimentSession.BaselineDisplayState = Get-DisplayStateSnapshot
    }
    $verification = Test-RefreshPolicyApplied "Fixed$([int]$Config.ExperimentRefreshRate)"
    if (-not [bool]$verification.Valid) { throw "Experiment refresh lock verification failed: $($verification.Differences -join ' ')" }
    $baselineVerification = Compare-DisplayStateSnapshot $State.ExperimentSession.BaselineDisplayState
    if (-not [bool]$baselineVerification.Valid) {
        throw "Experiment display baseline verification failed: $($baselineVerification.Differences -join ' ')"
    }
    if ($NewSession -and [bool]$Config.ExperimentAutoReport) {
        $report = Export-ExperimentEnvironmentReport $Config $State $PowerSnapshot $AutomationState Start
        $State.ExperimentSession.StartReportJson = [string]$report.JsonPath
        $State.ExperimentSession.StartReportHtml = [string]$report.HtmlPath
    }
    Save-AppState $State
    $script:LastExperimentVerificationAt = Get-Date
}

function Stop-ExperimentSession {
    param([object]$Config, [object]$State, [object]$PowerSnapshot, [object]$AutomationState)
    if ($null -eq $State.ExperimentSession) { return [pscustomobject]@{ Verified = $true; Differences = @() } }
    if ([bool]$Config.ExperimentAutoReport) {
        try { $null = Export-ExperimentEnvironmentReport $Config $State $PowerSnapshot $AutomationState End }
        catch { Write-AppLog "Experiment end report failed; display restoration will continue: $($_.Exception.Message)" }
    }
    $result = Restore-DisplayStateSnapshot $State.ExperimentSession.OriginalDisplayState
    if ([bool]$result.Verified) {
        if ([bool]$Config.ExperimentAutoReport) {
            try { $null = Export-ExperimentEnvironmentReport $Config $State $PowerSnapshot $AutomationState Restored }
            catch { Write-AppLog "Experiment restored-state report failed: $($_.Exception.Message)" }
        }
        Write-AppLog "Experiment session restored and closed: $($State.ExperimentSession.SessionId)."
        $State.ExperimentSession = $null
        Save-AppState $State
    }
    else { Write-AppLog "Experiment restore remains pending: $($result.Differences -join '; ')" }
    return $result
}

function Test-AndRepairExperimentEnvironment {
    param([object]$Config, [object]$State, [object]$PowerSnapshot, [object]$AutomationState)
    if ([string]$Config.Selection -ne 'Experiment' -or $null -eq $State.ExperimentSession -or
        $null -eq $State.ExperimentSession.BaselineDisplayState) { return $null }
    if (((Get-Date) - $script:LastExperimentVerificationAt).TotalSeconds -lt [int]$Config.ExperimentVerificationSeconds) { return $null }
    $script:LastExperimentVerificationAt = Get-Date
    $verification = Compare-DisplayStateSnapshot $State.ExperimentSession.BaselineDisplayState
    if ([bool]$verification.Valid) { return $verification }
    Write-AppLog "Experiment environment drift detected: $($verification.Differences -join '; ')"
    if ([bool]$Config.ExperimentAutoReport) {
        try { $null = Export-ExperimentEnvironmentReport $Config $State $PowerSnapshot $AutomationState Drift }
        catch { Write-AppLog "Experiment drift report failed: $($_.Exception.Message)" }
    }
    $restore = Restore-DisplayStateSnapshot $State.ExperimentSession.BaselineDisplayState
    if (-not [bool]$restore.Verified) {
        Write-AppLog "Experiment environment remains out of lock after repair: $($restore.Differences -join '; ')"
        return [pscustomobject]@{ Valid = $false; Differences = @($restore.Differences); Restore = $restore }
    }
    Write-AppLog "Experiment environment was re-locked after drift; changes=$($restore.Changes)."
    return Compare-DisplayStateSnapshot $State.ExperimentSession.BaselineDisplayState
}

function Write-TelemetryRecord {
    param(
        [object]$Snapshot,
        [object]$AutomationState,
        [string]$DesiredProfile,
        [string]$Selection,
        [string]$TemporaryProfile = '',
        [string]$ActiveProfile = ''
    )
    try {
        if (-not (Test-Path -LiteralPath $script:DataDir)) { [IO.Directory]::CreateDirectory($script:DataDir) | Out-Null }
        if ((Test-Path -LiteralPath $script:TelemetryPath) -and (Get-Item -LiteralPath $script:TelemetryPath).Length -gt 2097152) {
            Move-Item -LiteralPath $script:TelemetryPath -Destination ($script:TelemetryPath + '.old') -Force
        }
        $configVariable = Get-Variable -Name Config -Scope Script -ErrorAction SilentlyContinue
        $telemetryRefreshPolicy = if ($null -ne $configVariable) { [string]$configVariable.Value.RefreshPolicy } else { '' }
        $timerVariable = Get-Variable -Name Timer -Scope Script -ErrorAction SilentlyContinue
        $policyVerification = $script:LastPolicyVerification
        $hardware = Get-HardwareTelemetrySnapshot $Snapshot
        $nvidia = Get-NvidiaHardwareSnapshot $Snapshot
        $display = Get-DisplayTelemetrySnapshot $Snapshot
        $record = [pscustomobject][ordered]@{
            SchemaVersion = $script:TelemetrySchemaVersion
            OpenSynapseVersion = $script:AppVersion
            SupplyClassifierVersion = $script:SupplyClassifierVersion
            Timestamp = (Get-Date).ToUniversalTime().ToString('o')
            Source = [string]$Snapshot.Source
            SupplyType = [string]$Snapshot.SupplyType
            RawSupplyType = [string]$Snapshot.RawSupplyType
            SupplyConfirmationPending = [bool]$Snapshot.SupplyConfirmationPending
            AdapterLimitW = $Snapshot.AdapterLimitW
            BatteryPercent = [int]$Snapshot.BatteryPercent
            BatteryRemainingMwh = $Snapshot.BatteryRemainingMwh
            BatteryVoltageMv = $Snapshot.BatteryVoltageMv
            BatteryDischargeW = $Snapshot.BatteryDischargeW
            BatteryDischargeEmaW = $Snapshot.BatteryDischargeEmaW
            BatteryDischargeAverage10mW = $Snapshot.BatteryDischargeAverage10mW
            EstimatedHours = $Snapshot.BatteryEstimatedHours
            BatteryEstimateConfidence = [string]$Snapshot.BatteryEstimateConfidence
            BatteryChargeW = $Snapshot.BatteryChargeW
            Selection = $Selection
            TemporaryProfile = $TemporaryProfile
            DesiredProfile = $DesiredProfile
            ActiveProfile = if ([string]::IsNullOrWhiteSpace($ActiveProfile)) { $DesiredProfile } else { $ActiveProfile }
            PolicyPlanVerified = [bool]$policyVerification.PlanVerified
            PolicyRequestedRefresh = [string]$policyVerification.RefreshPolicy
            PolicyEffectiveRefresh = [string]$policyVerification.EffectiveRefreshPolicy
            PolicyRefreshVerified = $policyVerification.RefreshVerified
            PolicyVerifiedAtUtc = [string]$policyVerification.VerifiedAtUtc
            CpuPercent = [double]$AutomationState.LastCpuPercent
            GpuPercent = [double]$AutomationState.LastGpuPercent
            GpuSampleSequence = [long]$AutomationState.LastGpuSampleSequence
            GpuSampledAtUtc = if ([long]$AutomationState.LastGpuSampledAtUtcTicks -gt 0) {
                [DateTime]::new([long]$AutomationState.LastGpuSampledAtUtcTicks, [DateTimeKind]::Utc).ToString('o')
            } else { '' }
            GpuSampleAgeSeconds = [double]$AutomationState.LastGpuSampleAgeSeconds
            GpuTelemetryIntervalSeconds = [Math]::Round([int]$script:LastGpuTelemetryIntervalMs / 1000.0, 1)
            NvidiaTemperatureC = if ($null -ne $nvidia) { $nvidia.TemperatureC } else { $null }
            NvidiaPowerW = if ($null -ne $nvidia) { $nvidia.PowerW } else { $null }
            NvidiaPState = if ($null -ne $nvidia) { [string]$nvidia.PState } else { '' }
            NvidiaGraphicsClockMhz = if ($null -ne $nvidia) { $nvidia.GraphicsClockMhz } else { $null }
            NvidiaMemoryClockMhz = if ($null -ne $nvidia) { $nvidia.MemoryClockMhz } else { $null }
            NvidiaThrottleReasons = if ($null -ne $nvidia) { [string]$nvidia.ThrottleReasons } else { '' }
            NvidiaThrottlingDetected = $null -ne $nvidia -and [bool]$nvidia.ThrottlingDetected
            MaximumThermalZoneTemperatureC = if ($null -ne $hardware.PSObject.Properties['MaximumTemperatureC']) { [double]$hardware.MaximumTemperatureC } else { $null }
            ThermalThrottlingDetected = $null -ne $hardware.PSObject.Properties['ThermalThrottlingDetected'] -and [bool]$hardware.ThermalThrottlingDetected
            ThermalZones = if ($null -ne $hardware.PSObject.Properties['ThermalZones']) { @($hardware.ThermalZones | ForEach-Object { "$($_.Name):$($_.TemperatureC)C:throttle=$($_.ThrottleReasons)" }) } else { @() }
            CpuActualFrequencyMhz = if ($null -ne $hardware.PSObject.Properties['CpuActualFrequencyMhz']) { [double]$hardware.CpuActualFrequencyMhz } else { $null }
            CpuPercentMaximumFrequency = if ($null -ne $hardware.PSObject.Properties['CpuPercentMaximumFrequency']) { [double]$hardware.CpuPercentMaximumFrequency } else { $null }
            NpuAvailable = $null -ne $hardware.PSObject.Properties['NpuAvailable'] -and [bool]$hardware.NpuAvailable
            NpuUtilizationPercent = if ($null -ne $hardware.PSObject.Properties['NpuUtilizationPercent']) { [double]$hardware.NpuUtilizationPercent } else { $null }
            NpuCounterSet = if ($null -ne $hardware.PSObject.Properties['NpuCounterSet']) { [string]$hardware.NpuCounterSet } else { '' }
            DisplayModes = if ($null -ne $display.PSObject.Properties['Modes']) { @($display.Modes | ForEach-Object { "$($_.DeviceName):$($_.Width)x$($_.Height)@$($_.Frequency)Hz:$($_.BitsPerPixel)bpp" }) } else { @() }
            DisplayScaling = if ($null -ne $display.PSObject.Properties['Scaling']) { @($display.Scaling | ForEach-Object { "$($_.GdiDeviceName):$($_.CurrentPercent)%" }) } else { @() }
            DisplayDynamicRefresh = if ($null -ne $display.PSObject.Properties['DynamicRefresh']) { @($display.DynamicRefresh | ForEach-Object { "$($_.GdiDeviceName):enabled=$($_.Enabled):$($_.BaseFrequency)-$($_.BoostFrequency)Hz" }) } else { @() }
            DisplayAdvancedColor = if ($null -ne $display.PSObject.Properties['AdvancedColor']) { @($display.AdvancedColor | ForEach-Object { "$($_.GdiDeviceName):enabled=$($_.Enabled):$($_.BitsPerColorChannel)bpc" }) } else { @() }
            DisplayColorProfiles = if ($null -ne $display.PSObject.Properties['ColorProfiles']) { @($display.ColorProfiles | ForEach-Object { "$($_.GdiDeviceName):$([IO.Path]::GetFileName([string]$_.ProfilePath))" }) } else { @() }
            DisplayBrightness = if ($null -ne $display.PSObject.Properties['Brightness']) { @($display.Brightness | ForEach-Object { "$($_.InstanceName):$($_.CurrentPercent)%" }) } else { @() }
            DisplayPhysicalBrightness = if ($null -ne $display.PSObject.Properties['PhysicalBrightness']) { @($display.PhysicalBrightness | ForEach-Object { "$($_.GdiDeviceName)#$($_.PhysicalIndex):supported=$($_.Supported):$($_.CurrentPercent)%" }) } else { @() }
            ExperimentLocked = [string]$Selection -eq 'Experiment'
            MonitorIntervalSeconds = if ($null -ne $timerVariable -and $null -ne $timerVariable.Value) { [Math]::Round([int]$timerVariable.Value.Interval / 1000.0, 1) } else { 0 }
            RefreshPolicy = $telemetryRefreshPolicy
            ForegroundProcess = [string]$AutomationState.ForegroundProcess
            ForegroundFullscreen = [bool]$AutomationState.ForegroundFullscreen
            SessionLocked = [bool]$AutomationState.SessionLocked
            DgpuLeakDetected = [bool]$AutomationState.DgpuLeakDetected
            DgpuActivitySuspected = [bool]$AutomationState.DgpuLeakDetected
            DgpuActivityConfidence = [string]$AutomationState.DgpuActivityConfidence
            DgpuConsumers = [string[]]@($AutomationState.DgpuConsumers | ForEach-Object { [string]$_.ProcessName } | Select-Object -Unique)
            BatteryHighDrainDetected = [bool]$AutomationState.BatteryHighDrainDetected
            BatteryHighDrainConfidence = [string]$AutomationState.BatteryHighDrainConfidence
            BatteryHighDrainDischargeW = [double]$AutomationState.BatteryHighDrainDischargeW
            BatteryHighDrainProcesses = [string[]]@($AutomationState.BatteryHighDrainProcesses | ForEach-Object {
                "$($_.ProcessName):$($_.CpuPercentOneCore)%"
            })
            BatteryHighDrainAlertCount = [int]$AutomationState.BatteryHighDrainAlertCount
            Reason = [string]$AutomationState.LastReason
        }
        $line = ($record | ConvertTo-Json -Compress -Depth 5) + [Environment]::NewLine
        [IO.File]::AppendAllText($script:TelemetryPath, $line, [Text.UTF8Encoding]::new($false))
    }
    catch { Write-AppLog "Telemetry history write failed: $($_.Exception.Message)" }
}

function Export-OpenSynapseDiagnostics {
    param(
        [Parameter(Mandatory = $true)][string]$DestinationPath,
        [object]$Config,
        [object]$State,
        [object]$Snapshot,
        [object]$AutomationState
    )
    $destination = [IO.Path]::GetFullPath($DestinationPath)
    $staging = Join-Path ([IO.Path]::GetTempPath()) ("OpenSynapse-diagnostics-" + [Guid]::NewGuid().ToString('N'))
    try {
        [IO.Directory]::CreateDirectory($staging) | Out-Null
        $gpu = try { [OpenSynapseNative.GpuTelemetry]::ReadLatest() } catch { $null }
        $hardware = Get-HardwareTelemetrySnapshot $Snapshot -Force
        $nvidia = Get-NvidiaHardwareSnapshot $Snapshot -Force
        $display = Get-DisplayTelemetrySnapshot $Snapshot -Force
        $computerModel = try { (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).Model } catch { 'Unavailable' }
        $activePlanGuid = try { Get-ActivePlanGuid } catch { 'Unavailable' }
        $manifest = [pscustomobject][ordered]@{
            ExportedAt = (Get-Date).ToUniversalTime().ToString('o')
            OpenSynapseVersion = $script:AppVersion
            ComputerModel = $computerModel
            Windows = [Environment]::OSVersion.VersionString
            PowerSnapshot = $Snapshot
            SmartAutomation = $AutomationState
            GpuTelemetry = $gpu
            NvidiaTelemetry = $nvidia
            HardwareTelemetry = $hardware
            DisplayState = $display
            ActivePlanGuid = $activePlanGuid
            SafetyBoundary = 'Public Windows interfaces only; no EC, fan, TGP or MUX control.'
        }
        [IO.File]::WriteAllText((Join-Path $staging 'manifest.json'), ($manifest | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $staging 'config.json'), ($Config | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $staging 'state.json'), ($State | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
        foreach ($file in @($script:LogPath, ($script:LogPath + '.old'), $script:TelemetryPath, ($script:TelemetryPath + '.old'), $script:RuntimePath)) {
            if (Test-Path -LiteralPath $file) { Copy-Item -LiteralPath $file -Destination (Join-Path $staging ([IO.Path]::GetFileName($file))) -Force }
        }
        foreach ($command in @(
            [pscustomobject]@{ Name = 'active-power-plan.txt'; Args = @('/getactivescheme') },
            [pscustomobject]@{ Name = 'power-requests.txt'; Args = @('/requests') },
            [pscustomobject]@{ Name = 'wake-timers.txt'; Args = @('/waketimers') }
        )) {
            try {
                $output = Invoke-PowerCfg @($command.Args) -AllowFailure
                [IO.File]::WriteAllLines((Join-Path $staging $command.Name), [string[]]@($output), [Text.UTF8Encoding]::new($false))
            }
            catch { [IO.File]::WriteAllText((Join-Path $staging $command.Name), $_.Exception.Message) }
        }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Force }
        [IO.Compression.ZipFile]::CreateFromDirectory($staging, $destination, [IO.Compression.CompressionLevel]::Optimal, $false)
        Write-AppLog "Diagnostics exported to $destination."
        return $destination
    }
    finally { Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue }
}

function Invoke-QuietMaintenance {
    param([object]$Config, [object]$State)
    $processResult = [pscustomobject]@{
        Closed = [string[]]@()
        Restarted = [string[]]@()
        CoolingDown = [string[]]@()
    }
    if ([bool]$Config.CloseHighDrainAppsInQuiet) {
        $processResult = Stop-TrackedProcess @($Config.QuietProcessNames) $Config
    }
    Stop-QuietServices $Config $State
    return $processResult
}

function Set-ActiveProfile {
    param(
        [ValidateSet('Hyper', 'Balance', 'Quiet', 'Experiment')][string]$Name,
        [object]$State,
        [object]$Config,
        [switch]$Full,
        [switch]$ApplyVisualPolicy,
        [switch]$ApplyRefreshPolicy,
        [switch]$RepairScaling,
        [AllowNull()][object]$Snapshot
    )

    $targetGuid = switch ($Name) {
        'Hyper' { [string]$State.HyperPlanGuid; break }
        'Balance' { [string]$State.BalancePlanGuid; break }
        'Experiment' { [string]$State.ExperimentPlanGuid; break }
        default { [string]$State.QuietPlanGuid }
    }
    if ($Name -eq 'Hyper') {
        $null = Apply-HyperCpuPolicy $Config $State
    }
    $active = Get-ActivePlanGuid
    if (-not [string]::Equals($active, $targetGuid, [StringComparison]::OrdinalIgnoreCase)) {
        Invoke-PowerCfg @('/setactive', $targetGuid) | Out-Null
        Write-AppLog "Activated $Name plan $targetGuid."
    }

    if ($Name -eq 'Quiet') {
        $null = Apply-QuietDynamicCpuPolicy $Config $State $Snapshot
        if ($Full) { $null = Invoke-QuietMaintenance $Config $State }
        Disable-QuietWakeDevices $Config $State
    }
    else {
        Restore-WakeDevices $State
        Restore-QuietServices $State
    }

    $displayResult = Apply-DisplayPolicy $Name $Config $State -Full:$Full -ApplyVisualPolicy:$ApplyVisualPolicy -ApplyRefreshPolicy:$ApplyRefreshPolicy -RepairScaling:$RepairScaling -Snapshot $Snapshot
    $verified = [string]::Equals((Get-ActivePlanGuid), $targetGuid, [StringComparison]::OrdinalIgnoreCase)
    if (-not $verified) { throw "$Name plan verification failed." }
    return [pscustomobject]@{
        Name = $Name
        PlanVerified = $verified
        ScaleChanges = [int]$displayResult.ScaleChanges
        RefreshPolicy = [string]$displayResult.RefreshPolicy
        EffectiveRefreshPolicy = [string]$displayResult.EffectiveRefreshPolicy
        RefreshVerified = $displayResult.RefreshVerified
        RefreshWarning = [string]$displayResult.RefreshWarning
    }
}

function Stop-ExistingInstance {
    if (-not (Test-Path -LiteralPath $script:RuntimePath)) { return }
    try {
        $record = Read-JsonFile $script:RuntimePath
        if ($null -eq $record) { return }
        $process = Get-Process -Id ([int]$record.ProcessId) -ErrorAction Stop
        if ($process.StartTime.ToUniversalTime().Ticks -eq [long]$record.StartTimeUtcTicks) {
            Stop-Process -Id $process.Id -Force -ErrorAction Stop
            Start-Sleep -Milliseconds 500
        }
    }
    catch { }
    finally {
        Remove-Item -LiteralPath $script:RuntimePath -Force -ErrorAction SilentlyContinue
    }
}

function Test-LegacyDotNetJsonObject {
    param([AllowNull()][object]$Value)
    return (
        $null -ne $Value -and
        $null -ne (Get-ObjectProperty $Value 'SchemaVersion') -and
        $null -eq (Get-ObjectProperty $Value 'Version')
    )
}

function Move-LegacyDotNetJsonFile {
    param(
        [string]$Path,
        [string]$Stem
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    try {
        $value = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
        if (-not (Test-LegacyDotNetJsonObject $value)) { return '' }
    }
    catch {
        Write-AppLog "Legacy JSON archive skipped for invalid file ${Path}: $($_.Exception.Message)"
        return ''
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $destination = Join-Path $script:DataDir ("{0}.dotnet-v10-{1}-{2}.json" -f $Stem, $timestamp, [Guid]::NewGuid().ToString('N').Substring(0, 8))
    Move-Item -LiteralPath $Path -Destination $destination -Force -ErrorAction Stop
    Write-AppLog "Archived legacy .NET data: $destination"
    return $destination
}

function Move-LegacyDotNetStateFiles {
    $archives = New-Object Collections.Generic.List[string]
    $mainArchive = Move-LegacyDotNetJsonFile -Path $script:StatePath -Stem 'state'
    if ($mainArchive) { $archives.Add($mainArchive) }
    $backupArchive = Move-LegacyDotNetJsonFile -Path ($script:StatePath + '.bak') -Stem 'state-backup'
    if ($backupArchive) { $archives.Add($backupArchive) }
    return $archives.ToArray()
}

function Restore-LegacyDotNetState {
    $legacyState = Read-JsonFile $script:StatePath
    if (-not (Test-LegacyDotNetJsonObject $legacyState)) { return $false }

    Write-AppLog 'Restoring captured state from the legacy .NET OpenSynapse runtime.'
    Import-NativeHelpers
    $warnings = New-Object Collections.Generic.List[string]

    try { $null = [OpenSynapseNative.DynamicRefreshManager]::Disable() }
    catch { $warnings.Add("Dynamic refresh reset failed: $($_.Exception.Message)") }
    try { [OpenSynapseNative.DisplayModeManager]::RestoreRegistryModes() }
    catch { $warnings.Add("Refresh-rate restore failed: $($_.Exception.Message)") }

    $colorsProperty = Get-ObjectProperty $legacyState 'AdvancedColors'
    if ($null -ne $colorsProperty) {
        foreach ($captured in @($colorsProperty.Value)) {
            $keyProperty = Get-ObjectProperty $captured 'Key'
            $enabledProperty = Get-ObjectProperty $captured 'Enabled'
            if ($null -eq $keyProperty -or $null -eq $enabledProperty) { continue }
            try {
                $key = [string]$keyProperty.Value
                $target = @([OpenSynapseNative.AdvancedColorManager]::GetStatus() |
                    Where-Object { [string]::Equals([string]$_.Key, $key, [StringComparison]::Ordinal) }) |
                    Select-Object -First 1
                if ($null -eq $target) {
                    $warnings.Add("Advanced Color display is not currently connected: $key")
                }
                elseif ([bool]$target.Enabled -ne [bool]$enabledProperty.Value) {
                    $null = [OpenSynapseNative.AdvancedColorManager]::SetEnabled($key, [bool]$enabledProperty.Value)
                }
            }
            catch { $warnings.Add("Advanced Color restore failed: $($_.Exception.Message)") }
        }
    }

    $scalesProperty = Get-ObjectProperty $legacyState 'DisplayScales'
    if ($null -ne $scalesProperty) {
        foreach ($captured in @($scalesProperty.Value)) {
            $keyProperty = Get-ObjectProperty $captured 'Key'
            $scaleProperty = Get-ObjectProperty $captured 'ScalePercent'
            if ($null -eq $keyProperty -or $null -eq $scaleProperty) { continue }
            try {
                $key = [string]$keyProperty.Value
                $display = @([OpenSynapseNative.DisplayScaling]::GetActiveDisplays() |
                    Where-Object { [string]::Equals([string]$_.Key, $key, [StringComparison]::Ordinal) }) |
                    Select-Object -First 1
                if ($null -eq $display) {
                    $warnings.Add("Scaled display is not currently connected: $key")
                }
                else {
                    $null = [OpenSynapseNative.DisplayScaling]::SetScale($display, [int]$scaleProperty.Value)
                }
            }
            catch { $warnings.Add("Display-scale restore failed: $($_.Exception.Message)") }
        }
    }

    $brightnessProperty = Get-ObjectProperty $legacyState 'OriginalBrightness'
    if ($null -ne $brightnessProperty -and $null -ne $brightnessProperty.Value) {
        if ((Set-InternalBrightness ([int]$brightnessProperty.Value)) -eq 0) {
            $warnings.Add('Internal brightness could not be restored on the current display topology.')
        }
    }

    $wakeProperty = Get-ObjectProperty $legacyState 'DisabledWakeDevices'
    if ($null -ne $wakeProperty) {
        foreach ($device in @($wakeProperty.Value)) {
            if ([string]::IsNullOrWhiteSpace([string]$device)) { continue }
            $null = Invoke-PowerCfg @('/deviceenablewake', [string]$device) -AllowFailure
            if ($script:LastPowerCfgExitCode -ne 0) {
                $warnings.Add("Wake permission could not be restored: $device")
            }
        }
    }

    $originalProperty = Get-ObjectProperty $legacyState 'OriginalPowerPlan'
    $originalGuid = if ($null -eq $originalProperty) { '' } else { [string]$originalProperty.Value }
    $managedGuids = New-Object Collections.Generic.List[string]
    foreach ($propertyName in @('PerformancePowerPlan', 'BalancedPowerPlan', 'QuietPowerPlan')) {
        $property = Get-ObjectProperty $legacyState $propertyName
        if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value) -and
            -not $managedGuids.Contains([string]$property.Value)) {
            $managedGuids.Add([string]$property.Value)
        }
    }
    if ([string]::IsNullOrWhiteSpace($originalGuid) -and $managedGuids.Count -gt 0) {
        throw 'Legacy OpenSynapse state contains managed power plans but no original plan; installation stopped without deleting the recovery state.'
    }
    if (-not [string]::IsNullOrWhiteSpace($originalGuid)) {
        if (-not (Test-PlanExists $originalGuid)) {
            throw "Legacy original power plan no longer exists: $originalGuid"
        }
        Invoke-PowerCfg @('/setactive', $originalGuid) | Out-Null
        if (-not [string]::Equals((Get-ActivePlanGuid), $originalGuid, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Legacy power plan restoration verification failed: $originalGuid"
        }
    }
    foreach ($guid in $managedGuids) {
        if ([string]::Equals($guid, $originalGuid, [StringComparison]::OrdinalIgnoreCase)) { continue }
        if (Test-PlanExists $guid) {
            $null = Invoke-PowerCfg @('/delete', $guid) -AllowFailure
            if ($script:LastPowerCfgExitCode -ne 0) {
                throw "Could not remove the legacy managed power plan: $guid"
            }
        }
    }

    foreach ($warning in $warnings) { Write-AppLog "Legacy state migration warning: $warning" }
    $null = Move-LegacyDotNetStateFiles
    Write-AppLog "Legacy .NET state restore completed with $($warnings.Count) non-fatal warning(s)."
    return $true
}

function Remove-LegacyDotNetRuntime {
    Stop-ScheduledTask -TaskName $script:LegacyAgentTaskName -ErrorAction SilentlyContinue
    foreach ($processName in @('OpenSynapse.Agent', 'OpenSynapse.App')) {
        Get-Process -Name $processName -ErrorAction SilentlyContinue | ForEach-Object {
            try { Stop-Process -Id $_.Id -Force -ErrorAction Stop }
            catch { Write-AppLog "Could not stop legacy process ${processName}: $($_.Exception.Message)" }
        }
    }

    $legacyAgent = Join-Path $script:ProgramDir 'Agent\OpenSynapse.Agent.exe'
    if (Test-Path -LiteralPath $legacyAgent -PathType Leaf) {
        & $legacyAgent 'uninstall-cleanup'
        $cleanupExitCode = $LASTEXITCODE
        if ($cleanupExitCode -ne 0) {
            throw "Legacy Agent cleanup failed with exit code $cleanupExitCode; installation stopped without deleting its recovery files."
        }
        $null = Move-LegacyDotNetStateFiles
        Write-AppLog 'Legacy .NET Agent completed uninstall-cleanup.'
    }
    else {
        $null = Restore-LegacyDotNetState
    }

    Unregister-ScheduledTask -TaskName $script:LegacyAgentTaskName -Confirm:$false -ErrorAction SilentlyContinue
    foreach ($directoryName in @('Agent', 'App')) {
        $legacyDirectory = Join-Path $script:ProgramDir $directoryName
        if (Test-Path -LiteralPath $legacyDirectory -PathType Container) {
            Remove-Item -LiteralPath $legacyDirectory -Recurse -Force -ErrorAction Stop
        }
    }
}

function Remove-LegacyPowerPilotRuntime {
    $powerPilotProgramDir = Join-Path $env:ProgramFiles 'PowerPilot'
    $powerPilotDataDir = Join-Path $env:LOCALAPPDATA 'PowerPilot'
    $powerPilotScript = Join-Path $powerPilotProgramDir 'PowerPilot.ps1'
    $powerPilotConfigPath = Join-Path $powerPilotDataDir 'config.json'
    $powerPilotStatePath = Join-Path $powerPilotDataDir 'state.json'
    $powerPilotRuntimePath = Join-Path $powerPilotDataDir 'runtime.json'

    $task = Get-ScheduledTask -TaskName $script:LegacyPowerPilotTaskName -ErrorAction SilentlyContinue
    $hasRuntime = Test-Path -LiteralPath $powerPilotRuntimePath -PathType Leaf
    $hasState = Test-Path -LiteralPath $powerPilotStatePath -PathType Leaf
    $hasProgram = Test-Path -LiteralPath $powerPilotProgramDir -PathType Container
    if ($null -eq $task -and -not $hasRuntime -and -not $hasState -and -not $hasProgram) { return $null }
    if (-not (Test-Path -LiteralPath $powerPilotScript -PathType Leaf)) {
        throw 'A PowerPilot runtime or recovery state exists, but its uninstaller is missing. OpenSynapse stopped to avoid running two policy engines or losing rollback state.'
    }

    $powerPilotConfig = $null
    if (Test-Path -LiteralPath $powerPilotConfigPath -PathType Leaf) {
        try { $powerPilotConfig = Get-Content -Raw -LiteralPath $powerPilotConfigPath | ConvertFrom-Json }
        catch { throw "PowerPilot configuration cannot be migrated: $($_.Exception.Message)" }
    }
    $powerPilotState = $null
    if ($hasState) {
        try { $powerPilotState = Get-Content -Raw -LiteralPath $powerPilotStatePath | ConvertFrom-Json }
        catch { throw "PowerPilot recovery state cannot be archived: $($_.Exception.Message)" }
    }

    $migrationRecord = [pscustomobject][ordered]@{
        MigratedAt = (Get-Date).ToString('o')
        Source = $powerPilotProgramDir
        Config = $powerPilotConfig
        State = $powerPilotState
    }
    $migrationPath = Join-Path $script:DataDir ("PowerPilot-2.4.1-migration-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Write-JsonFile $migrationPath $migrationRecord

    $uninstallOutput = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $powerPilotScript -Mode Uninstall)
    $uninstallExitCode = $LASTEXITCODE
    if ($uninstallExitCode -ne 0) {
        throw "PowerPilot uninstall/restore failed with exit code $uninstallExitCode; OpenSynapse installation stopped."
    }
    foreach ($line in $uninstallOutput) {
        if (-not [string]::IsNullOrWhiteSpace([string]$line)) { Write-AppLog "PowerPilot uninstaller: $line" }
    }
    if (Get-ScheduledTask -TaskName $script:LegacyPowerPilotTaskName -ErrorAction SilentlyContinue) {
        throw 'PowerPilot scheduled task still exists after its uninstall/restore operation.'
    }
    if (Test-Path -LiteralPath $powerPilotRuntimePath -PathType Leaf) {
        throw 'PowerPilot runtime still reports active after its uninstall/restore operation.'
    }
    Write-AppLog "PowerPilot was restored and removed; migration archive: $migrationPath"
    return $powerPilotConfig
}

function Stop-LegacyScaleWatcher {
    $legacyDir = Join-Path $env:LOCALAPPDATA 'RazerDisplayScaleFix'
    $pidFile = Join-Path $legacyDir 'watcher.json'
    if (Test-Path -LiteralPath $pidFile) {
        try {
            $record = Read-JsonFile $pidFile
            $process = Get-Process -Id ([int]$record.ProcessId) -ErrorAction Stop
            if ($process.StartTime.ToUniversalTime().Ticks -eq [long]$record.StartTimeUtcTicks) {
                Stop-Process -Id $process.Id -Force -ErrorAction Stop
                Start-Sleep -Milliseconds 300
            }
        }
        catch { }
        Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    }
    Remove-ItemProperty -Path $script:RunKey -Name 'RazerDisplayScaleFix' -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $legacyDir 'Fix-RazerDisplayScaling.ps1') -Force -ErrorAction SilentlyContinue
}

function Remove-LegacyAutostarts {
    Remove-ItemProperty -Path $script:RunKey -Name 'OpenSynapse' -Force -ErrorAction SilentlyContinue
    Stop-LegacyScaleWatcher
}

function Get-InstalledOpenSynapseVersion {
    if (-not (Test-Path -LiteralPath $script:InstalledScript -PathType Leaf)) { return '' }
    try {
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($script:InstalledScript, [ref]$tokens, [ref]$errors)
        if ($errors.Count -gt 0) { return '' }
        $assignment = $ast.Find({
            param($node)
            $node -is [Management.Automation.Language.AssignmentStatementAst] -and
                $node.Left.Extent.Text -eq '$script:AppVersion'
        }, $true)
        if ($null -eq $assignment) { return '' }
        $versionExpression = $assignment.Right
        if ($versionExpression -is [Management.Automation.Language.CommandExpressionAst]) { $versionExpression = $versionExpression.Expression }
        if ($versionExpression -isnot [Management.Automation.Language.StringConstantExpressionAst]) { return '' }
        return [string]$versionExpression.Value
    }
    catch {
        Write-AppLog "Unable to identify the installed OpenSynapse version: $($_.Exception.Message)"
        return ''
    }
}

function Test-StartupCommandEqualsExecutable {
    param([string]$Command, [string]$Executable)

    if ([string]::IsNullOrWhiteSpace($Command) -or [string]::IsNullOrWhiteSpace($Executable)) { return $false }
    $trimmed = $Command.Trim()
    return (
        [string]::Equals($trimmed, $Executable, [StringComparison]::OrdinalIgnoreCase) -or
        [string]::Equals($trimmed, ('"{0}"' -f $Executable), [StringComparison]::OrdinalIgnoreCase)
    )
}

function Test-SnipasteStoreAutostartEnabled {
    if (-not (Test-Path -LiteralPath $script:SnipasteStoreStartupTaskKey)) { return $false }
    try {
        $startupTask = Get-ItemProperty -LiteralPath $script:SnipasteStoreStartupTaskKey -ErrorAction Stop
        $stateProperty = $startupTask.PSObject.Properties['State']
        return ($null -ne $stateProperty -and [int]$stateProperty.Value -eq 2)
    }
    catch {
        Write-AppLog "Unable to read the Snipaste Store startup task: $($_.Exception.Message)"
        return $false
    }
}

function Remove-OpenSynapse201DuplicateSnipasteAutostart {
    param([string]$PreviousVersion)

    $result = [pscustomobject][ordered]@{
        PreviousVersion = $PreviousVersion
        StoreAutostartEnabled = $false
        DesktopRunEntryFound = $false
        DesktopRunEntryRemoved = $false
        Reason = 'The installed version is not OpenSynapse 2.0.1.'
    }

    if (-not [string]::Equals($PreviousVersion, '2.0.1', [StringComparison]::OrdinalIgnoreCase)) { return $result }
    $result.Reason = 'Store startup task is not enabled.'
    if (-not (Test-SnipasteStoreAutostartEnabled)) { return $result }
    $result.StoreAutostartEnabled = $true
    if (-not (Test-Path -LiteralPath $script:RunKey)) {
        $result.Reason = 'The user Run key does not exist.'
        return $result
    }

    $runValues = Get-ItemProperty -LiteralPath $script:RunKey -ErrorAction SilentlyContinue
    if ($null -eq $runValues) {
        $result.Reason = 'The user Run key could not be read.'
        return $result
    }
    $snipasteProperty = $runValues.PSObject.Properties['Snipaste']
    if ($null -eq $snipasteProperty) {
        $result.Reason = 'No desktop Snipaste Run entry exists.'
        return $result
    }

    $result.DesktopRunEntryFound = $true
    $existingCommand = [string]$snipasteProperty.Value
    if (-not (Test-StartupCommandEqualsExecutable $existingCommand $script:DesktopSnipasteExecutable)) {
        $result.Reason = 'The desktop Snipaste Run entry is custom and was preserved.'
        Write-AppLog "Preserved custom Snipaste autostart command: $existingCommand"
        return $result
    }

    Remove-ItemProperty -LiteralPath $script:RunKey -Name 'Snipaste' -Force -ErrorAction Stop
    $remaining = Get-ItemProperty -LiteralPath $script:RunKey -Name 'Snipaste' -ErrorAction SilentlyContinue
    if ($null -ne $remaining) { throw 'Duplicate desktop Snipaste autostart removal verification failed.' }

    $result.DesktopRunEntryRemoved = $true
    $result.Reason = 'Removed the duplicate desktop Snipaste Run entry created by OpenSynapse 2.0.1; the enabled Store startup task was preserved.'
    Write-AppLog $result.Reason
    return $result
}

function Register-OpenSynapseTask {
    Import-Module ScheduledTasks -ErrorAction Stop
    Unregister-ScheduledTask -TaskName $script:TaskName -Confirm:$false -ErrorAction SilentlyContinue

    $powerShellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments = '-NoProfile -WindowStyle Hidden -STA -ExecutionPolicy Bypass -File "{0}" -Mode Run' -f $script:InstalledScript
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $action = New-ScheduledTaskAction -Execute $powerShellPath -Argument $arguments -WorkingDirectory $script:ProgramDir
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $identity
    $trigger.Delay = 'PT30S'
    $principal = New-ScheduledTaskPrincipal -UserId $identity -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) `
        -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
    $task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings `
        -Description "OpenSynapse $script:AppVersion adapter-aware Hyper, Balance and Quiet controller."
    Register-ScheduledTask -TaskName $script:TaskName -InputObject $task -Force | Out-Null

    $registered = Get-ScheduledTask -TaskName $script:TaskName -ErrorAction Stop
    if ($registered.Principal.RunLevel.ToString() -ne 'Highest') { throw 'Scheduled task is not configured for highest privileges.' }
    if ($registered.Actions.Execute -notmatch 'powershell\.exe$' -or $registered.Actions.Arguments -notlike "*$script:InstalledScript*") {
        throw 'Scheduled task action verification failed.'
    }
    if ([string]$registered.Triggers[0].Delay -ne 'PT30S') { throw 'Scheduled task logon delay verification failed.' }
}

function New-AppShortcut {
    Import-NativeHelpers
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($script:ShortcutPath)
    $shortcut.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $shortcut.Arguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -Mode Open' -f $script:InstalledScript
    $shortcut.WorkingDirectory = $script:ProgramDir
    $shortcut.Description = 'Open OpenSynapse control panel'
    $shortcut.IconLocation = $script:InstalledAppIcon + ',0'
    $shortcut.Save()
    [OpenSynapseNative.AppIdentity]::SetShortcutAppId($script:ShortcutPath, $script:AppUserModelId)
    $shortcutAppId = [OpenSynapseNative.AppIdentity]::GetShortcutAppId($script:ShortcutPath)
    if ($shortcutAppId -ne $script:AppUserModelId) { throw "Shortcut taskbar identity verification failed: $shortcutAppId" }
}

function Install-OpenSynapse {
    if (-not (Test-IsAdministrator)) { exit (Invoke-ElevatedOperation 'Install') }

    $previousVersion = Get-InstalledOpenSynapseVersion
    [IO.Directory]::CreateDirectory($script:ProgramDir) | Out-Null
    [IO.Directory]::CreateDirectory($script:DataDir) | Out-Null
    Stop-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue
    Stop-ExistingInstance
    Remove-LegacyDotNetRuntime
    $powerPilotConfig = Remove-LegacyPowerPilotRuntime
    if ($null -ne $powerPilotConfig) {
        $null = Move-LegacyDotNetJsonFile -Path $script:ConfigPath -Stem 'config'
        $null = Move-LegacyDotNetJsonFile -Path ($script:ConfigPath + '.bak') -Stem 'config-backup'
        Write-JsonFile $script:ConfigPath $powerPilotConfig
        Write-AppLog 'PowerPilot configuration was promoted to OpenSynapse.'
    }
    Remove-LegacyAutostarts

    $existing = Get-AppState
    $originalGuid = Get-ActivePlanGuid
    if ($null -ne $existing -and $existing.PSObject.Properties['OriginalPlanGuid']) {
        $candidate = [string]$existing.OriginalPlanGuid
        if (Test-PlanExists $candidate) { $originalGuid = $candidate }
    }

    $hyperGuid = if ($null -ne $existing -and $existing.PSObject.Properties['HyperPlanGuid']) { [string]$existing.HyperPlanGuid } else { '' }
    $balanceGuid = if ($null -ne $existing -and $existing.PSObject.Properties['BalancePlanGuid']) { [string]$existing.BalancePlanGuid } else { '' }
    $quietGuid = if ($null -ne $existing -and $existing.PSObject.Properties['QuietPlanGuid']) { [string]$existing.QuietPlanGuid } else { '' }
    $experimentGuid = if ($null -ne $existing -and $existing.PSObject.Properties['ExperimentPlanGuid']) { [string]$existing.ExperimentPlanGuid } else { '' }
    if (-not (Test-PlanExists $hyperGuid)) { $hyperGuid = New-CustomPlan 'OpenSynapse Hyper' 'AC maximum-performance policy.' }
    if (-not (Test-PlanExists $balanceGuid)) { $balanceGuid = New-CustomPlan 'OpenSynapse Balance' 'Responsive efficiency policy for battery and USB-C PD.' }
    if (-not (Test-PlanExists $quietGuid)) { $quietGuid = New-CustomPlan 'OpenSynapse Quiet' 'Battery endurance policy.' }
    if (-not (Test-PlanExists $experimentGuid)) { $experimentGuid = New-CustomPlan 'OpenSynapse Experiment' 'Locked and reproducible visual research policy.' }

    Set-ProfilePolicy Hyper $hyperGuid
    Set-ProfilePolicy Balance $balanceGuid
    Set-ProfilePolicy Quiet $quietGuid
    Set-ProfilePolicy Experiment $experimentGuid

    $disabledWakeDevices = [string[]]@()
    $servicesStoppedByUs = [string[]]@()
    $advancedColorStates = [object[]]@()
    if ($null -ne $existing) {
        $disabledWakeDevices = [string[]]@($existing.DisabledWakeDevices)
        $servicesStoppedByUs = [string[]]@($existing.ServicesStoppedByUs)
        $advancedColorStates = [object[]]@($existing.AdvancedColorStates)
    }

    $state = [pscustomobject][ordered]@{
        Version = 11
        OriginalPlanGuid = $originalGuid
        HyperPlanGuid = $hyperGuid
        BalancePlanGuid = $balanceGuid
        QuietPlanGuid = $quietGuid
        ExperimentPlanGuid = $experimentGuid
        DisabledWakeDevices = $disabledWakeDevices
        ServicesStoppedByUs = $servicesStoppedByUs
        AdvancedColorStates = $advancedColorStates
        CapturedBrightness = if ($null -ne $existing) { $existing.CapturedBrightness } else { $null }
        DisplayStateSnapshot = if ($null -ne $existing) { $existing.DisplayStateSnapshot } else { $null }
        ExperimentSession = if ($null -ne $existing) { $existing.ExperimentSession } else { $null }
        InstalledAt = (Get-Date).ToString('o')
    }
    Save-AppState $state
    $config = Get-AppConfig
    Save-AppConfig $config
    if ($script:LegacyDotNetConfigDetected) {
        $null = Move-LegacyDotNetJsonFile -Path ($script:ConfigPath + '.bak') -Stem 'config'
    }

    foreach ($pair in @(
        @([IO.Path]::GetFullPath($PSCommandPath), [IO.Path]::GetFullPath($script:InstalledScript)),
        @([IO.Path]::GetFullPath($script:SourceNative), [IO.Path]::GetFullPath($script:InstalledNative)),
        @([IO.Path]::GetFullPath($script:SourceAppIcon), [IO.Path]::GetFullPath($script:InstalledAppIcon)),
        @([IO.Path]::GetFullPath($script:SourceTrayIcon), [IO.Path]::GetFullPath($script:InstalledTrayIcon)),
        @([IO.Path]::GetFullPath($script:SourceAppPng), [IO.Path]::GetFullPath($script:InstalledAppPng))
    )) {
        if (-not [string]::Equals($pair[0], $pair[1], [StringComparison]::OrdinalIgnoreCase)) {
            Copy-Item -LiteralPath $pair[0] -Destination $pair[1] -Force
        }
    }

    $legacyV1Script = Join-Path $script:DataDir 'OpenSynapse.ps1'
    if (-not [string]::Equals([IO.Path]::GetFullPath($legacyV1Script), [IO.Path]::GetFullPath($PSCommandPath), [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $legacyV1Script -Force -ErrorAction SilentlyContinue
    }

    $snipasteMigration = Remove-OpenSynapse201DuplicateSnipasteAutostart -PreviousVersion $previousVersion
    Register-OpenSynapseTask
    New-AppShortcut
    if (-not (Test-Path -LiteralPath $script:ShortcutPath)) { throw 'Start menu shortcut verification failed.' }
    Start-ScheduledTask -TaskName $script:TaskName
    $runtimeReady = $false
    $runtimeFailure = ''
    foreach ($attempt in 1..240) {
        if (Test-Path -LiteralPath $script:RuntimePath) {
            $runtimeRecord = Read-JsonFile $script:RuntimePath
            if ($null -ne $runtimeRecord) {
                $runtimeProcess = Get-Process -Id ([int]$runtimeRecord.ProcessId) -ErrorAction SilentlyContinue
                if ($null -eq $runtimeProcess -or $runtimeProcess.StartTime.ToUniversalTime().Ticks -ne [long]$runtimeRecord.StartTimeUtcTicks) {
                    $runtimeFailure = 'The tray process exited before reporting healthy.'
                    break
                }
                $healthy = $runtimeRecord.PSObject.Properties['Health'] -and [string]$runtimeRecord.Health -eq 'Healthy'
                $successfulTick = $runtimeRecord.PSObject.Properties['LastSuccessfulTickUtc'] -and
                    -not [string]::IsNullOrWhiteSpace([string]$runtimeRecord.LastSuccessfulTickUtc)
                if ($healthy -and $successfulTick) { $runtimeReady = $true; break }
            }
        }
        Start-Sleep -Milliseconds 250
    }
    if (-not $runtimeReady) {
        if ([string]::IsNullOrWhiteSpace($runtimeFailure)) {
            $runtimeFailure = 'The tray process did not reach Healthy with a successful monitor tick within 60 seconds.'
        }
        throw "The scheduled task was registered, but startup validation failed: $runtimeFailure Check OpenSynapse.log."
    }
    $runtimeRecord = Read-JsonFile $script:RuntimePath
    if ($null -eq $runtimeRecord) { throw 'The tray runtime record is invalid.' }
    $runtimeProcess = Get-Process -Id ([int]$runtimeRecord.ProcessId) -ErrorAction SilentlyContinue
    if ($null -eq $runtimeProcess -or $runtimeProcess.StartTime.ToUniversalTime().Ticks -ne [long]$runtimeRecord.StartTimeUtcTicks) {
        throw 'The tray runtime process verification failed.'
    }
    Write-AppLog "Installed v$script:AppVersion. Hyper=$hyperGuid Balance=$balanceGuid Quiet=$quietGuid Original=$originalGuid"
    Write-Host "OpenSynapse $script:AppVersion installed and started."
    Write-Host 'Smart Auto: high-power AC uses Balance at light load and Hyper for sustained app/CPU/GPU load; PD/battery stays within Quiet or Balance.'
    if ($snipasteMigration.DesktopRunEntryRemoved) { Write-Host 'Removed the duplicate desktop Snipaste startup entry; the Microsoft Store startup task was preserved.' }
    Write-Host 'FlClash, Snipaste and other third-party startup settings are no longer managed by OpenSynapse.'
    Write-Host 'The legacy v1 autostart and standalone display-scaling watcher were migrated.'
}

function Uninstall-OpenSynapse {
    if (-not (Test-IsAdministrator)) { exit (Invoke-ElevatedOperation 'Uninstall') }

    Stop-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue
    Stop-ExistingInstance
    Remove-LegacyDotNetRuntime
    $state = Get-AppState
    if ($null -ne $state) {
        try { Import-NativeHelpers; Restore-DisplayPolicy $state } catch { Write-AppLog "Display restore failed: $($_.Exception.Message)" }
        try { Restore-WakeDevices $state } catch { Write-AppLog "Wake restore failed: $($_.Exception.Message)" }
        try { Restore-QuietServices $state } catch { Write-AppLog "Service restore failed: $($_.Exception.Message)" }

        $restoreGuid = [string]$state.OriginalPlanGuid
        if (-not (Test-PlanExists $restoreGuid)) { $restoreGuid = $script:Guids.Balanced }
        Invoke-PowerCfg @('/setactive', $restoreGuid) -AllowFailure | Out-Null
        foreach ($property in @('HyperPlanGuid', 'BalancePlanGuid', 'QuietPlanGuid', 'ExperimentPlanGuid')) {
            $guid = [string]$state.$property
            if (Test-PlanExists $guid) { Invoke-PowerCfg @('/delete', $guid) -AllowFailure | Out-Null }
        }
    }

    Unregister-ScheduledTask -TaskName $script:TaskName -Confirm:$false -ErrorAction SilentlyContinue
    if (Get-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue) { throw 'Scheduled task removal verification failed.' }
    Remove-LegacyAutostarts
    Remove-Item -LiteralPath $script:ShortcutPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $script:ShowRequestPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $script:ProgramDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $script:DataDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host 'OpenSynapse was removed; original power, wake, display, brightness and service states were restored.'
}

function Open-OpenSynapse {
    [IO.Directory]::CreateDirectory($script:DataDir) | Out-Null
    [IO.File]::WriteAllText($script:ShowRequestPath, (Get-Date).ToString('o'))
    try { Start-ScheduledTask -TaskName $script:TaskName -ErrorAction Stop }
    catch {
        $task = Get-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue
        if ($null -eq $task) { throw 'OpenSynapse is not installed.' }
    }
}

function Get-ActiveProfileName {
    param([object]$State)
    $active = Get-ActivePlanGuid
    if ([string]::Equals($active, [string]$State.HyperPlanGuid, [StringComparison]::OrdinalIgnoreCase)) { return 'Hyper' }
    if ([string]::Equals($active, [string]$State.BalancePlanGuid, [StringComparison]::OrdinalIgnoreCase)) { return 'Balance' }
    if ([string]::Equals($active, [string]$State.QuietPlanGuid, [StringComparison]::OrdinalIgnoreCase)) { return 'Quiet' }
    if ([string]::Equals($active, [string]$State.ExperimentPlanGuid, [StringComparison]::OrdinalIgnoreCase)) { return 'Experiment' }
    return 'Other'
}

function Show-Status {
    Add-UiAssemblies
    Import-NativeHelpers
    $state = Get-InstalledState
    $config = Get-AppConfig
    $snapshot = Get-PowerSnapshot
    try { $task = Get-ScheduledTask -TaskName $script:TaskName -ErrorAction Stop } catch { $task = $null }
    $nvidia = Get-NvidiaSnapshot
    $runtimeStatus = Read-JsonFile $script:RuntimePath
    try { $model = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).Model }
    catch {
        try { $model = (Get-ItemProperty -LiteralPath 'HKLM:\HARDWARE\DESCRIPTION\System\BIOS' -ErrorAction Stop).SystemProductName }
        catch { $model = 'Unavailable' }
    }

    [pscustomobject][ordered]@{
        Version = $script:AppVersion
        Model = $model
        PowerSource = $snapshot.Source
        SupplyType = $snapshot.SupplyType
        AdapterEnforcedLimitW = $snapshot.AdapterLimitW
        BatteryPercent = $snapshot.BatteryPercent
        BatteryDischargeW = $snapshot.BatteryDischargeW
        BatteryChargeW = $snapshot.BatteryChargeW
        BatteryRemainingMwh = $snapshot.BatteryRemainingMwh
        BatteryEstimatedHours = $snapshot.BatteryEstimatedHours
        Selection = [string]$config.Selection
        ApplicationRulesEnabled = @($config.ApplicationRules | Where-Object { [bool]$_.Enabled }).Count
        ActiveProfile = Get-ActiveProfileName $state
        TaskState = if ($task) { $task.State.ToString() } else { 'Missing' }
        TaskPrivilege = if ($task) { $task.Principal.RunLevel.ToString() } else { 'Missing' }
        DpiMode = if ($runtimeStatus -and $runtimeStatus.PSObject.Properties['DpiMode']) { [string]$runtimeStatus.DpiMode } else { 'Unavailable' }
        WakeDisabledByOpenSynapse = @($state.DisabledWakeDevices) -join '; '
        ServicesStoppedByOpenSynapse = @($state.ServicesStoppedByUs) -join '; '
        Nvidia = if ($nvidia) { "$($nvidia.Name); $($nvidia.PState); $($nvidia.PowerW) W; display=$($nvidia.DisplayActive); enforced/default/max=$($nvidia.EnforcedLimitW)/$($nvidia.DefaultLimitW)/$($nvidia.MaximumLimitW) W" } else { 'Unavailable' }
        Displays = @([OpenSynapseNative.DisplayModeManager]::GetActiveDisplays() | ForEach-Object { "$($_.DeviceName) $($_.Width)x$($_.Height) $($_.Frequency)Hz $($_.FriendlyName)" }) -join '; '
        Scaling = @([OpenSynapseNative.DisplayScaling]::GetActiveDisplays() | ForEach-Object { "$($_.Role)=$($_.CurrentPercent)% (target $(if ($_.IsInternal) { $config.InternalScale } else { $config.ExternalScale })%)" }) -join '; '
        AdvancedColor = @([OpenSynapseNative.AdvancedColorManager]::GetStatus() | ForEach-Object { "$($_.Key): supported=$($_.Supported), enabled=$($_.Enabled), $($_.BitsPerColorChannel)bpc" }) -join '; '
    } | Format-List
}

function Apply-ProfileOnce {
    param([ValidateSet('Auto', 'Hyper', 'Balance', 'Quiet', 'Experiment')][string]$Selection)
    if (-not (Test-IsAdministrator)) { exit (Invoke-ElevatedOperation 'Apply' $Selection) }
    Add-UiAssemblies
    Import-NativeHelpers
    $state = Get-InstalledState
    $config = Get-AppConfig
    $config.Selection = $Selection
    Save-AppConfig $config
    $snapshot = Get-PowerSnapshot
    if ($Selection -eq 'Balance' -and -not (Test-BalanceEligible $snapshot ([int]$config.BalanceBatteryThreshold))) {
        throw "Balance requires at least $($config.BalanceBatteryThreshold)% battery; current charge is $($snapshot.BatteryPercent)%."
    }
    $automationState = New-SmartAutomationState (Get-ActiveProfileName $state)
    if ($Selection -eq 'Auto' -and [bool]$config.SmartAutomationEnabled) {
        $null = Update-SmartAutomationState $config $snapshot $automationState
    }
    $desired = Get-DesiredProfile $Selection $snapshot $config $automationState
    $result = Set-ActiveProfile $desired $state $config -Full -Snapshot $snapshot
    Write-Host "Applied $desired on $($snapshot.SupplyType); plan verified=$($result.PlanVerified), scaling repairs=$($result.ScaleChanges)."
    if (-not [string]::IsNullOrWhiteSpace([string]$result.RefreshWarning)) {
        Write-Warning "Refresh policy was not applied: $($result.RefreshWarning)"
    }
}

function Test-OpenSynapse {
    $guidPattern = '^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$'
    foreach ($entry in $script:Guids.GetEnumerator()) {
        if ([string]$entry.Value -notmatch $guidPattern) { throw "Invalid GUID: $($entry.Key)=$($entry.Value)" }
    }
    $highPower = [pscustomobject]@{ Source = 'AC'; SupplyType = 'HighPowerAC'; BatteryPercent = 76; AdapterLimitW = 160 }
    $pdPower = [pscustomobject]@{ Source = 'AC'; SupplyType = 'LowPowerPD'; BatteryPercent = 76; AdapterLimitW = 70 }
    $batteryPower = [pscustomobject]@{ Source = 'Battery'; SupplyType = 'Battery'; BatteryPercent = 76; AdapterLimitW = $null }
    $unknownPower = [pscustomobject]@{ Source = 'AC'; SupplyType = 'UnknownAC'; BatteryPercent = 76; AdapterLimitW = $null }
    if ((Resolve-SupplyType AC 160) -ne 'HighPowerAC') { throw 'High-power adapter classification failed.' }
    if ((Resolve-SupplyType AC 70) -ne 'LowPowerPD') { throw 'PD adapter classification failed.' }
    if ((Resolve-SupplyType AC 85) -ne 'LowPowerPD' -or (Resolve-SupplyType AC 91.86) -ne 'UnknownAC') {
        throw 'PD evidence threshold classification failed.'
    }
    if ((Resolve-SupplyType AC $null) -ne 'UnknownAC') { throw 'Unknown AC classification failed.' }
    if ((Get-DesiredProfile Auto $highPower) -ne 'Hyper') { throw 'Auto high-power mapping failed.' }
    if ((Get-DesiredProfile Auto $pdPower) -ne 'Quiet') { throw 'Auto PD mapping failed.' }
    if ((Get-DesiredProfile Auto $batteryPower) -ne 'Quiet') { throw 'Auto battery mapping failed.' }
    if ((Get-DesiredProfile Auto $unknownPower) -ne 'Quiet') { throw 'Auto unknown-source fail-safe mapping failed.' }
    if ((Get-DesiredProfile Hyper $pdPower) -ne 'Hyper') { throw 'Manual Hyper override mapping failed.' }
    if ((Get-DesiredProfile Balance $pdPower) -ne 'Balance') { throw 'Manual Balance mapping failed.' }
    if ((Get-DesiredProfile Quiet $highPower) -ne 'Quiet') { throw 'Manual Quiet mapping failed.' }
    if (-not (Test-BalanceEligible $pdPower 50)) { throw 'Balance eligibility failed.' }
    $lowBattery = [pscustomobject]@{ BatteryPercent = 49 }
    if (Test-BalanceEligible $lowBattery 50) { throw 'Low-battery Balance lock failed.' }
    $defaults = Get-DefaultConfig
    if ($defaults.InternalScale -ne 150 -or $defaults.ExternalScale -ne 125) { throw 'Scaling defaults are incorrect.' }
    if (@($defaults.QuietProcessNames).Count -lt 4 -or @($defaults.QuietWakeDevicePatterns).Count -lt 2) { throw 'Quiet policy lists are incomplete.' }
    if (@($defaults.QuietProcessNames | Where-Object { $_ -match '^(FlClash|FlClashCore|Snipaste)$' }).Count -ne 0) {
        throw 'Third-party startup apps must not be included in Quiet process maintenance.'
    }
    if ((Resolve-RefreshPolicy $defaults Hyper $highPower) -ne 'Fixed240' -or
        (Resolve-RefreshPolicy $defaults Balance $pdPower) -ne 'DynamicNative' -or
        (Resolve-RefreshPolicy $defaults Quiet $batteryPower) -ne 'DynamicNative') {
        throw 'Default refresh policy mapping failed.'
    }
    if ($defaults.ProcessMaintenanceSeconds -ne 180 -or -not [bool]$defaults.AdaptiveQuietBrightness -or
        (Resolve-ProfileBrightnessTarget Quiet $defaults ([pscustomobject]@{ Source = 'Battery'; BatteryPercent = 80 })) -ne 35 -or
        (Resolve-ProfileBrightnessTarget Quiet $defaults ([pscustomobject]@{ Source = 'Battery'; BatteryPercent = 15 })) -ne 20) {
        throw 'Quiet endurance default mapping failed.'
    }
    if (-not [bool]$defaults.AdaptiveQuietCpu -or
        (Resolve-QuietCpuMaxPercent $defaults ([pscustomobject]@{ BatteryPercent = 80 })) -ne 65 -or
        (Resolve-QuietCpuMaxPercent $defaults ([pscustomobject]@{ BatteryPercent = 50 })) -ne 60 -or
        (Resolve-QuietCpuMaxPercent $defaults ([pscustomobject]@{ BatteryPercent = 15 })) -ne 50 -or
        (Resolve-QuietCpuEppPercent $defaults ([pscustomobject]@{ BatteryPercent = 80 })) -ne 90 -or
        (Resolve-QuietCpuEppPercent $defaults ([pscustomobject]@{ BatteryPercent = 50 })) -ne 95 -or
        (Resolve-QuietCpuEppPercent $defaults ([pscustomobject]@{ BatteryPercent = 15 })) -ne 100) {
        throw 'Quiet adaptive CPU mapping failed.'
    }
    $hyperSustained = Resolve-HyperCpuPolicy $defaults
    $defaults.HyperCpuPolicy = 'Latency'
    $hyperLatency = Resolve-HyperCpuPolicy $defaults
    if ($hyperSustained.Name -ne 'Sustained' -or $hyperSustained.Minimum -ne 5 -or $hyperSustained.MinCores1 -ne 0 -or
        $hyperLatency.Name -ne 'Latency' -or $hyperLatency.Minimum -ne 100 -or $hyperLatency.MinCores1 -ne 100) {
        throw 'Hyper CPU policy mapping failed.'
    }
    $sampleSnipastePath = 'C:\Program Files\Snipaste\Snipaste.exe'
    if (-not (Test-StartupCommandEqualsExecutable $sampleSnipastePath $sampleSnipastePath) -or
        -not (Test-StartupCommandEqualsExecutable ('"{0}"' -f $sampleSnipastePath) $sampleSnipastePath) -or
        (Test-StartupCommandEqualsExecutable ('"{0}" --custom' -f $sampleSnipastePath) $sampleSnipastePath)) {
        throw 'Safe startup command matching failed.'
    }

    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($PSCommandPath, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) { throw "Parser errors: $($errors.Message -join '; ')" }
    Import-NativeHelpers
    $dpiMode = [OpenSynapseNative.HighDpi]::EnablePerMonitorV2()
    if ($dpiMode -notin @('PerMonitorV2', 'PerMonitorV1', 'PerMonitor', 'SystemAware')) { throw "High DPI initialization failed: $dpiMode" }
    foreach ($display in [OpenSynapseNative.DisplayScaling]::GetActiveDisplays()) {
        if ([OpenSynapseNative.DisplayScaling]::SetScale($display, $display.CurrentPercent)) { throw 'No-op scaling verification unexpectedly changed a display.' }
    }
    [void][OpenSynapseNative.DisplayModeManager]::GetActiveDisplays()
    [void][OpenSynapseNative.DynamicRefreshManager]::GetStatus()
    [void][OpenSynapseNative.AdvancedColorManager]::GetStatus()
    [OpenSynapseNative.DisplayChangeSignal]::Start()
    [OpenSynapseNative.DisplayChangeSignal]::Stop()
    [OpenSynapseNative.PowerChangeSignal]::Start()
    [OpenSynapseNative.PowerChangeSignal]::Stop()
    $razerMethods = [OpenSynapseNative.RazerMouse].GetMethods().Name
    foreach ($method in @('GetDevices', 'SetDpi', 'SetPollingRate')) {
        if ($method -notin $razerMethods) { throw "Missing Razer mouse method: $method" }
    }
    [void][OpenSynapseNative.RazerMouse]::GetDevices()
    Add-UiAssemblies
    foreach ($iconPair in @(
        @($script:SourceAppIcon, $script:InstalledAppIcon),
        @($script:SourceTrayIcon, $script:InstalledTrayIcon)
    )) {
        $iconPath = if (Test-Path -LiteralPath $iconPair[0]) { $iconPair[0] } else { $iconPair[1] }
        if (-not (Test-Path -LiteralPath $iconPath)) { throw "OpenSynapse icon is missing: $iconPath" }
        $icon = [Drawing.Icon]::new($iconPath)
        try {
            if ($icon.Width -lt 16 -or $icon.Height -lt 16) { throw "OpenSynapse icon is invalid: $iconPath" }
        }
        finally { $icon.Dispose() }
    }
    [void](Get-PowerSnapshot)
    [void](Invoke-PowerCfg @('/getactivescheme'))
    Write-Host "OpenSynapse $script:AppVersion self-test passed. No system setting was changed."
}

function Get-DisplayStatusText {
    param([object]$Config)
    try {
        $lines = New-Object Collections.Generic.List[string]
        $dpiVariable = Get-Variable -Name DpiMode -Scope Script -ErrorAction SilentlyContinue
        if ($dpiVariable) { $lines.Add("UI DPI mode: $($dpiVariable.Value)") }
        foreach ($mode in [OpenSynapseNative.DisplayModeManager]::GetActiveDisplays()) {
            $rates = [OpenSynapseNative.DisplayModeManager]::GetSupportedRefreshRates([string]$mode.DeviceName) -join '/'
            $lines.Add("$($mode.DeviceName): $($mode.Width)x$($mode.Height) at $($mode.Frequency) Hz (available $rates) - $($mode.FriendlyName)")
        }
        foreach ($scale in [OpenSynapseNative.DisplayScaling]::GetActiveDisplays()) {
            $target = if ($scale.IsInternal) { $Config.InternalScale } else { $Config.ExternalScale }
            $lines.Add("$($scale.Role) scale: $($scale.CurrentPercent)% (target $target%, recommended $($scale.RecommendedPercent)%)")
        }
        foreach ($color in [OpenSynapseNative.AdvancedColorManager]::GetStatus()) {
            $lines.Add("Advanced color $($color.GdiDeviceName): supported=$($color.Supported), enabled=$($color.Enabled), $($color.BitsPerColorChannel) bpc")
        }
        foreach ($profile in [OpenSynapseNative.ColorProfileManager]::GetStatus()) {
            $lines.Add("ICC $($profile.GdiDeviceName): $(if ($profile.Available) { $profile.ProfilePath } else { "unavailable ($($profile.Error))" })")
        }
        foreach ($dynamic in [OpenSynapseNative.DynamicRefreshManager]::GetStatuses()) {
            $lines.Add("Dynamic refresh $($dynamic.GdiDeviceName): internal=$($dynamic.IsInternal), supported=$($dynamic.Supported), enabled=$($dynamic.Enabled), range=$($dynamic.BaseFrequency)-$($dynamic.BoostFrequency) Hz")
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$script:LastPolicyVerification.VerifiedAtUtc)) {
            $lines.Add("Policy verification: profile=$($script:LastPolicyVerification.Profile), plan=$($script:LastPolicyVerification.PlanVerified), requestedRefresh=$($script:LastPolicyVerification.RefreshPolicy), effectiveRefresh=$($script:LastPolicyVerification.EffectiveRefreshPolicy), refreshVerified=$($script:LastPolicyVerification.RefreshVerified), at=$($script:LastPolicyVerification.VerifiedAtUtc)")
        }
        foreach ($brightnessState in @(Get-MonitorBrightnessStates)) {
            $lines.Add("Windows brightness $($brightnessState.InstanceName): $($brightnessState.CurrentPercent)%")
        }
        foreach ($brightnessState in @([OpenSynapseNative.PhysicalMonitorBrightnessManager]::GetStatus())) {
            $endpoint = "$($brightnessState.GdiDeviceName)#$($brightnessState.PhysicalIndex)"
            if ([bool]$brightnessState.Supported) {
                $lines.Add("DDC/CI brightness ${endpoint}: $($brightnessState.CurrentPercent)% (raw $($brightnessState.Current)/$($brightnessState.Maximum))")
            }
            else { $lines.Add("DDC/CI brightness ${endpoint}: unavailable ($($brightnessState.Error))") }
        }
        $hyperPolicy = Resolve-HyperCpuPolicy $Config
        $lines.Add("Hyper CPU: $($hyperPolicy.Name), EPP 0 on classes 0/1/2, minimum $($hyperPolicy.Minimum)/$($hyperPolicy.Minimum1)/$($hyperPolicy.Minimum2)%, unpark $($hyperPolicy.MinCores)/$($hyperPolicy.MinCores1)%")
        $automationVariable = Get-Variable -Name AutomationState -Scope Script -ErrorAction SilentlyContinue
        if ($null -ne $automationVariable) {
            $automationStatus = $automationVariable.Value
            $automationLabel = if ([bool]$Config.SmartAutomationEnabled) { 'Smart Auto' } else { 'Automation telemetry (switching disabled)' }
            $lines.Add("${automationLabel}: profile=$($automationStatus.CurrentProfile), CPU=$($automationStatus.LastCpuPercent)%, GPU=$($automationStatus.LastGpuPercent)%, foreground=$($automationStatus.ForegroundProcess), fullscreen=$($automationStatus.ForegroundFullscreen), reason=$($automationStatus.LastReason)")
            $consumerNames = [string[]]@($automationStatus.DgpuConsumers | ForEach-Object { [string]$_.ProcessName } | Select-Object -Unique)
            $activityStatus = if ([bool]$automationStatus.DgpuLeakDetected) { "SUSPECTED ($($automationStatus.DgpuActivityConfidence) confidence)" } else { "observing ($($automationStatus.DgpuLeakSamples)/$($Config.DgpuLeakMinimumSamples))" }
            $lines.Add("dGPU activity: $activityStatus; consumers=$(if ($consumerNames.Count) { $consumerNames -join ', ' } else { 'none' })")
            $highDrainNames = [string[]]@($automationStatus.BatteryHighDrainProcesses | ForEach-Object { "$($_.ProcessName) $($_.CpuPercentOneCore)%" })
            $highDrainStatus = if ([bool]$automationStatus.BatteryHighDrainDetected) {
                "DETECTED ($($automationStatus.BatteryHighDrainConfidence) confidence, $($automationStatus.BatteryHighDrainDischargeW) W)"
            } else { [string]$automationStatus.BatteryHighDrainLastReason }
            $lines.Add("Battery high-drain processes: $highDrainStatus; candidates=$(if ($highDrainNames.Count) { $highDrainNames -join ', ' } else { 'none' }); alerts=$($automationStatus.BatteryHighDrainAlertCount)")
        }
        $powerSnapshot = Get-PowerSnapshot -UseCachedAdapter
        if ([bool]$powerSnapshot.BatteryTelemetryAvailable) {
            $estimateText = if ($null -ne $powerSnapshot.BatteryEstimatedHours) { "$($powerSnapshot.BatteryEstimatedHours) h ($($powerSnapshot.BatteryEstimateConfidence))" } else { 'calculating' }
            $lines.Add("Battery telemetry: instant=$($powerSnapshot.BatteryDischargeW) W, EMA=$($powerSnapshot.BatteryDischargeEmaW) W, 10m-average=$($powerSnapshot.BatteryDischargeAverage10mW) W, charge=$($powerSnapshot.BatteryChargeW) W, remaining=$($powerSnapshot.BatteryRemainingMwh) mWh, estimate=$estimateText, voltage=$($powerSnapshot.BatteryVoltageMv) mV")
        }
        else { $lines.Add('Battery telemetry: unavailable (no compatible battery status returned)') }
        $gpuSnapshot = try { [OpenSynapseNative.GpuTelemetry]::ReadLatest() } catch { $null }
        if ($null -ne $gpuSnapshot -and [bool]$gpuSnapshot.Available) {
            $lines.Add("Windows GPU telemetry: total=$($gpuSnapshot.TotalUtilizationPercent)%, dGPU=$($gpuSnapshot.DiscreteUtilizationPercent)%, dGPU dedicated=$([Math]::Round($gpuSnapshot.DiscreteDedicatedBytes / 1MB, 1)) MB")
        }
        $hardware = Get-HardwareTelemetrySnapshot $powerSnapshot
        if ($null -ne $hardware.PSObject.Properties['ThermalZones']) {
            foreach ($zone in @($hardware.ThermalZones)) {
                $lines.Add("Thermal $($zone.Name): $($zone.TemperatureC) C, throttleReasons=$($zone.ThrottleReasons)")
            }
            $cpuActualText = if ([double]$hardware.CpuActualFrequencyMhz -gt 0) { "$($hardware.CpuActualFrequencyMhz) MHz" } else { 'not exposed' }
            $lines.Add("CPU frequency: actual=$cpuActualText, maximum ratio=$($hardware.CpuPercentMaximumFrequency)%")
            if ([bool]$hardware.NpuAvailable) {
                $lines.Add("NPU telemetry: $($hardware.NpuUtilizationPercent)%, counter=$($hardware.NpuCounterSet)")
            }
            else { $lines.Add('NPU telemetry: not exposed by an installed Windows performance counter set') }
        }
        $razerDevices = @(Get-RazerMouseDevices)
        if ($razerDevices.Count -eq 0) {
            $lines.Add('Razer mouse: no supported DeathAdder V3 Pro HID control interface detected')
        }
        else {
            foreach ($mouse in $razerDevices) {
                $mouseDpi = if ($null -ne $mouse.DpiX) { "$($mouse.DpiX)x$($mouse.DpiY) DPI" } else { 'DPI unavailable' }
                $mousePolling = if ($null -ne $mouse.PollingRate) { "$($mouse.PollingRate) Hz" } else { 'polling unavailable' }
                $mouseBattery = if ($null -ne $mouse.BatteryPercent) { "$($mouse.BatteryPercent)%" } else { 'battery unavailable' }
                $lines.Add("Razer mouse: $($mouse.Name), $($mouse.Connection), $mouseDpi, $mousePolling, $mouseBattery")
            }
        }
        $lines.Add("Application rules: $(@($Config.ApplicationRules | Where-Object { [bool]$_.Enabled }).Count) enabled")
        $healthVariable = Get-Variable -Name RuntimeHealth -Scope Script -ErrorAction SilentlyContinue
        if ($null -ne $healthVariable) {
            $failureVariable = Get-Variable -Name ConsecutiveMonitorFailures -Scope Script -ErrorAction SilentlyContinue
            $lastSuccessVariable = Get-Variable -Name LastSuccessfulMonitorTick -Scope Script -ErrorAction SilentlyContinue
            $failureCount = if ($null -ne $failureVariable) { [int]$failureVariable.Value } else { 0 }
            $lastSuccess = if ($null -ne $lastSuccessVariable -and [DateTime]$lastSuccessVariable.Value -ne [DateTime]::MinValue) {
                ([DateTime]$lastSuccessVariable.Value).ToString('HH:mm:ss')
            } else { 'waiting' }
            $monitorInterval = if ($null -ne (Get-Variable -Name Timer -Scope Script -ErrorAction SilentlyContinue) -and $null -ne $script:Timer) { "$($script:Timer.Interval / 1000)s" } else { 'not running' }
            $lines.Add("Runtime health: $($healthVariable.Value), failures=$failureCount, last successful tick=$lastSuccess, monitor interval=$monitorInterval")
        }
        $brightness = Get-InternalBrightness
        if ($null -ne $brightness) { $lines.Add("Internal brightness: $brightness%") }
        if ([string]$powerSnapshot.SupplyType -eq 'HighPowerAC') {
            $nvidia = Get-NvidiaHardwareSnapshot $powerSnapshot
            if ($nvidia) {
                $lines.Add("NVIDIA: $($nvidia.PState), $($nvidia.PowerW) W, $($nvidia.TemperatureC) C, clocks=$($nvidia.GraphicsClockMhz)/$($nvidia.MemoryClockMhz) MHz, throttle=$($nvidia.ThrottleReasons), display=$($nvidia.DisplayActive), enforced/default/max $($nvidia.EnforcedLimitW)/$($nvidia.DefaultLimitW)/$($nvidia.MaximumLimitW) W")
            }
        }
        else { $lines.Add('NVIDIA vendor probe: skipped on portable power to avoid waking the dGPU') }
        return $lines -join [Environment]::NewLine
    }
    catch { return "Display status unavailable: $($_.Exception.Message)" }
}

function Start-TrayApplication {
    $captureUi = -not [string]::IsNullOrWhiteSpace($CaptureUiPath)
    if (-not $captureUi -and -not (Test-IsAdministrator)) {
        Open-OpenSynapse
        return
    }

    Import-NativeHelpers
    $script:EffectiveAppUserModelId = [OpenSynapseNative.AppIdentity]::SetCurrentProcessAppId($script:AppUserModelId)
    if ($script:EffectiveAppUserModelId -ne $script:AppUserModelId) {
        throw "Taskbar identity verification failed: $script:EffectiveAppUserModelId"
    }
    $script:DpiMode = [OpenSynapseNative.HighDpi]::EnablePerMonitorV2()
    Add-UiAssemblies
    [Windows.Forms.Application]::EnableVisualStyles()
    [Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)
    $script:RazerGreen = [Drawing.Color]::FromArgb(68, 214, 44)
    $script:WindowDark = [Drawing.Color]::FromArgb(8, 10, 11)
    $script:PanelDark = [Drawing.Color]::FromArgb(15, 18, 19)
    $script:ControlDark = [Drawing.Color]::FromArgb(23, 26, 27)
    $script:BorderDark = [Drawing.Color]::FromArgb(45, 49, 50)
    $script:TextLight = [Drawing.Color]::FromArgb(230, 232, 230)
    $script:TextMuted = [Drawing.Color]::FromArgb(142, 147, 144)

    function Set-RazerButtonStyle([Windows.Forms.Button]$Button, [bool]$Primary) {
        $Button.FlatStyle = [Windows.Forms.FlatStyle]::Flat
        $Button.FlatAppearance.BorderSize = 1
        $Button.FlatAppearance.BorderColor = if ($Primary) { $script:RazerGreen } else { $script:BorderDark }
        $Button.FlatAppearance.MouseOverBackColor = [Drawing.Color]::FromArgb(31, 42, 31)
        $Button.FlatAppearance.MouseDownBackColor = [Drawing.Color]::FromArgb(42, 92, 35)
        if ($Primary) {
            $Button.BackColor = $script:RazerGreen
            $Button.ForeColor = [Drawing.Color]::Black
        }
        else {
            $Button.BackColor = $script:ControlDark
            $Button.ForeColor = $script:TextLight
        }
    }

    function Set-DarkComboStyle([Windows.Forms.ComboBox]$Control) {
        $Control.DrawMode = [Windows.Forms.DrawMode]::OwnerDrawFixed
        $Control.ItemHeight = 24
        $Control.FlatStyle = [Windows.Forms.FlatStyle]::Flat
        $Control.BackColor = $script:ControlDark
        $Control.ForeColor = $script:TextLight
        $Control.Add_DrawItem({
            param($sender, $eventArgs)
            if ($eventArgs.Index -lt 0) { return }
            $selected = (($eventArgs.State -band [Windows.Forms.DrawItemState]::Selected) -ne 0)
            $background = if ($selected) { [Drawing.Color]::FromArgb(48, 72, 44) } else { $script:ControlDark }
            $foreground = if ($selected) { [Drawing.Color]::White } else { $script:TextLight }
            $brush = New-Object Drawing.SolidBrush($background)
            try { $eventArgs.Graphics.FillRectangle($brush, $eventArgs.Bounds) }
            finally { $brush.Dispose() }
            $textBounds = New-Object Drawing.Rectangle(($eventArgs.Bounds.X + 7), $eventArgs.Bounds.Y, ([Math]::Max(1, $eventArgs.Bounds.Width - 10)), $eventArgs.Bounds.Height)
            $flags = [Windows.Forms.TextFormatFlags]::Left -bor [Windows.Forms.TextFormatFlags]::VerticalCenter -bor [Windows.Forms.TextFormatFlags]::NoPrefix -bor [Windows.Forms.TextFormatFlags]::EndEllipsis
            [Windows.Forms.TextRenderer]::DrawText($eventArgs.Graphics, [string]$sender.Items[$eventArgs.Index], $sender.Font, $textBounds, $foreground, $flags)
        })
    }

    function Apply-DarkControlTheme([Windows.Forms.Control]$Control) {
        try {
            if ($Control -is [Windows.Forms.ComboBox]) { $null = [OpenSynapseNative.WindowTheme]::ApplyDarkCombo($Control.Handle) }
            else { $null = [OpenSynapseNative.WindowTheme]::ApplyDarkControl($Control.Handle) }
        } catch { }
        foreach ($child in $Control.Controls) { Apply-DarkControlTheme $child }
    }

    $createdNew = $false
    $mutexName = if ($captureUi) { "Local\OpenSynapse.UiCapture.$PID" } else { 'Local\OpenSynapse.Tray.2' }
    $mutex = [Threading.Mutex]::new($true, $mutexName, [ref]$createdNew)
    $hasHandle = $createdNew
    if (-not $hasHandle) {
        try { $hasHandle = $mutex.WaitOne(0, $false) }
        catch [Threading.AbandonedMutexException] { $hasHandle = $true }
    }
    if (-not $hasHandle) {
        if (-not $captureUi) {
            try {
                [IO.Directory]::CreateDirectory($script:DataDir) | Out-Null
                [IO.File]::WriteAllText($script:ShowRequestPath, (Get-Date).ToString('o'))
            }
            catch { Write-AppLog "Existing-instance wake request failed: $($_.Exception.Message)" }
        }
        $mutex.Dispose()
        return
    }

    if ($captureUi) {
        $currentGuid = Get-ActivePlanGuid
        $script:State = [pscustomobject]@{
            OriginalPlanGuid = $currentGuid; HyperPlanGuid = $currentGuid; BalancePlanGuid = $currentGuid
            QuietPlanGuid = '00000000-0000-0000-0000-000000000000'; ExperimentPlanGuid = $currentGuid
            DisabledWakeDevices = @(); ServicesStoppedByUs = @(); AdvancedColorStates = @(); CapturedBrightness = $null
        }
        $script:Config = Get-DefaultConfig
    }
    else {
        $script:State = Get-InstalledState
        $script:Config = Get-AppConfig
    }
    $script:LastPowerSource = $null
    $script:LastSupplyType = $null
    $script:LastDesiredProfile = $null
    $script:LastMaintenance = [DateTime]::MinValue
    $script:AllowFormClose = $false
    $script:IgnoreDisplayEventsUntil = [DateTime]::MinValue
    $script:PendingDisplayRepairAt = [DateTime]::MaxValue
    $script:LastDisplayVersion = 0
    $script:LastPowerEventVersion = 0
    $script:LastPowerEventCount = 0
    $script:PendingPowerProbeAt = [DateTime]::MaxValue
    $script:PowerEventsObserved = 0
    $script:PowerEventsCoalesced = 0
    $script:PowerEventTriggeredProbes = 0
    $script:LastPlanVerification = [DateTime]::MinValue
    $script:LastPolicyVerification = [pscustomobject][ordered]@{
        Profile = ''
        PlanVerified = $false
        RefreshPolicy = ''
        EffectiveRefreshPolicy = ''
        RefreshVerified = $null
        RefreshWarning = ''
        VerifiedAtUtc = ''
    }
    $script:LastAppliedBrightnessTarget = $null
    $script:LastAppliedQuietCpuMax = $null
    $script:LastAppliedHyperCpuPolicy = $null
    $script:QuietProcessGuard = @{}
    $script:ApplyInProgress = $false
    $script:SuppressOptionSave = $false
    $script:LastApplyErrorNotification = [DateTime]::MinValue
    $script:MonitorTickRunning = $false
    $script:MonitorBaseIntervalMs = 5000
    $script:MonitorBatteryActiveIntervalMs = 10000
    $script:MonitorBatteryIdleIntervalMs = 15000
    $script:MonitorMaximumIntervalMs = 60000
    $script:LastMonitorSnapshot = $null
    $script:ConsecutiveMonitorFailures = 0
    $script:RuntimeHealth = 'Starting'
    $script:LastRuntimeError = ''
    $script:LastSuccessfulMonitorTick = [DateTime]::MinValue
    $script:LastRuntimeHeartbeat = [DateTime]::MinValue
    $script:LastTelemetryRecord = [DateTime]::MinValue
    $script:LastExternalForegroundProcess = ''
    $script:TemporaryOverride = $null
    $initialAutomationProfile = if ($captureUi) { 'Balance' } else { Get-ActiveProfileName $script:State }
    $script:LastVerifiedActiveProfile = $initialAutomationProfile
    $script:AutomationState = New-SmartAutomationState $initialAutomationProfile

    $runtime = [pscustomobject]@{
        ProcessId = $PID
        StartTimeUtcTicks = (Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks
        Version = $script:AppVersion
        DpiMode = $script:DpiMode
        AppUserModelId = $script:EffectiveAppUserModelId
        Health = $script:RuntimeHealth
        ConsecutiveFailures = 0
        LastHeartbeatUtc = (Get-Date).ToUniversalTime().ToString('o')
        LastSuccessfulTickUtc = ''
        LastError = ''
    }
    $script:RuntimeRecord = $runtime
    if (-not $captureUi) { Write-JsonFile $script:RuntimePath $runtime }
    [OpenSynapseNative.DisplayChangeSignal]::Start()
    $script:LastDisplayVersion = [OpenSynapseNative.DisplayChangeSignal]::Version
    [OpenSynapseNative.PowerChangeSignal]::Start()
    $script:LastPowerEventVersion = [OpenSynapseNative.PowerChangeSignal]::Version
    $script:LastPowerEventCount = [OpenSynapseNative.PowerChangeSignal]::EventCount
    [OpenSynapseNative.GpuTelemetry]::Start(10000)

    $trayIconPath = if (Test-Path -LiteralPath $script:SourceTrayIcon) { $script:SourceTrayIcon } else { $script:InstalledTrayIcon }
    $appIconPath = if (Test-Path -LiteralPath $script:SourceAppIcon) { $script:SourceAppIcon } else { $script:InstalledAppIcon }
    $script:TrayIconResource = if (Test-Path -LiteralPath $trayIconPath) { [Drawing.Icon]::new($trayIconPath) } else { $null }
    $script:FormIconResource = if (Test-Path -LiteralPath $appIconPath) { [Drawing.Icon]::new($appIconPath) } else { $null }
    $appPngPath = if (Test-Path -LiteralPath $script:SourceAppPng) { $script:SourceAppPng } else { $script:InstalledAppPng }

    $script:TrayIcon = New-Object Windows.Forms.NotifyIcon
    $script:TrayIcon.Icon = if ($null -ne $script:TrayIconResource) { $script:TrayIconResource } else { [Drawing.SystemIcons]::Shield }
    $script:TrayIcon.Visible = $true
    $script:TrayIcon.Text = "OpenSynapse $script:AppVersion"

    $menu = New-Object Windows.Forms.ContextMenuStrip
    $menu.BackColor = $script:ControlDark
    $menu.ForeColor = $script:TextLight
    $menu.ShowImageMargin = $false
    $script:StatusMenu = $menu.Items.Add("OpenSynapse $script:AppVersion")
    $script:StatusMenu.Enabled = $false
    [void]$menu.Items.Add('-')
    $script:AutoMenu = $menu.Items.Add('Smart Auto: supply + app + CPU/GPU load')
    $script:HyperMenu = $menu.Items.Add('Lock Hyper (manual override)')
    $script:BalanceMenu = $menu.Items.Add('Lock Balance (battery >= 50%)')
    $script:QuietMenu = $menu.Items.Add('Lock Eco')
    $script:ExperimentMenu = $menu.Items.Add('Lock Experiment (verified display state)')
    $script:TemporaryMenu = $menu.Items.Add('Temporary mode')
    $script:TemporaryHyperMenu = $script:TemporaryMenu.DropDownItems.Add('Hyper for 30 minutes')
    $script:TemporaryBalanceMenu = $script:TemporaryMenu.DropDownItems.Add('Balance for 30 minutes')
    $script:TemporaryQuietMenu = $script:TemporaryMenu.DropDownItems.Add('Eco for 30 minutes')
    $script:TemporaryCancelMenu = $script:TemporaryMenu.DropDownItems.Add('Cancel temporary mode')
    [void]$menu.Items.Add('-')
    $openMenu = $menu.Items.Add('Open control panel')
    $logMenu = $menu.Items.Add('Open log')
    $exitMenu = $menu.Items.Add('Exit and restore')
    $script:TrayIcon.ContextMenuStrip = $menu
    foreach ($item in $menu.Items) {
        $item.BackColor = $script:ControlDark
        $item.ForeColor = $script:TextLight
    }

    $script:Form = New-Object Windows.Forms.Form
    $script:Form.Text = "OpenSynapse $script:AppVersion"
    $script:Form.ClientSize = New-Object Drawing.Size(1440, 900)
    $script:Form.StartPosition = 'CenterScreen'
    $script:Form.FormBorderStyle = 'None'
    $script:Form.MaximizeBox = $true
    $script:Form.MinimumSize = New-Object Drawing.Size(1440, 900)
    # PerMonitorV2 plus pixel-stable geometry keeps the custom chrome sharp on
    # both the 150% internal panel and the 125% external display.
    $script:Form.AutoScaleMode = [Windows.Forms.AutoScaleMode]::None
    $script:Form.Icon = if ($null -ne $script:FormIconResource) { $script:FormIconResource } else { [Drawing.SystemIcons]::Shield }
    [OpenSynapseNative.AppIdentity]::SetWindowAppId($script:Form.Handle, $script:AppUserModelId)
    $null = [OpenSynapseNative.WindowTheme]::ApplyDarkFrame($script:Form.Handle)
    $null = [OpenSynapseNative.WindowTheme]::ApplyRoundedCorners($script:Form.Handle)
    $script:Form.BackColor = $script:BorderDark
    $script:Form.ForeColor = $script:TextLight
    $script:Form.Font = New-Object Drawing.Font('Segoe UI', 10)

    $shell = New-Object Windows.Forms.Panel
    $shell.Location = New-Object Drawing.Point(1, 1)
    $shell.Size = New-Object Drawing.Size(1438, 898)
    $shell.Anchor = 'Top, Bottom, Left, Right'
    $shell.BackColor = $script:WindowDark
    $script:Form.Controls.Add($shell)

    $titleBar = New-Object Windows.Forms.Panel
    $titleBar.Location = New-Object Drawing.Point(0, 0)
    $titleBar.Size = New-Object Drawing.Size(1438, 48)
    $titleBar.Anchor = 'Top, Left, Right'
    $titleBar.BackColor = [Drawing.Color]::FromArgb(5, 6, 7)
    $shell.Controls.Add($titleBar)

    $script:BrandImageResource = if (Test-Path -LiteralPath $appPngPath) {
        [Drawing.Image]::FromFile($appPngPath)
    }
    elseif ($null -ne $script:FormIconResource) { $script:FormIconResource.ToBitmap() }
    else { $null }
    $brandPicture = New-Object Windows.Forms.PictureBox
    $brandPicture.Location = New-Object Drawing.Point(18, 9)
    $brandPicture.Size = New-Object Drawing.Size(30, 30)
    $brandPicture.SizeMode = [Windows.Forms.PictureBoxSizeMode]::Zoom
    $brandPicture.BackColor = [Drawing.Color]::Transparent
    if ($null -ne $script:BrandImageResource) { $brandPicture.Image = $script:BrandImageResource }
    $titleBar.Controls.Add($brandPicture)

    $brandLabel = New-Object Windows.Forms.Label
    $brandLabel.Text = 'OpenSynapse'
    $brandLabel.Font = New-Object Drawing.Font('Segoe UI', 10, [Drawing.FontStyle]::Bold)
    $brandLabel.AutoSize = $true
    $brandLabel.Location = New-Object Drawing.Point(56, 14)
    $brandLabel.ForeColor = $script:RazerGreen
    $titleBar.Controls.Add($brandLabel)

    function New-ChromeButton([string]$Text, [int]$RightOffset) {
        $button = New-Object Windows.Forms.Button
        $button.Text = $Text
        $button.Font = New-Object Drawing.Font('Segoe UI Symbol', 11)
        $button.Size = New-Object Drawing.Size(46, 47)
        $button.Location = New-Object Drawing.Point(($titleBar.Width - $RightOffset), 0)
        $button.Anchor = 'Top, Right'
        $button.FlatStyle = [Windows.Forms.FlatStyle]::Flat
        $button.FlatAppearance.BorderSize = 0
        $button.FlatAppearance.MouseOverBackColor = $script:ControlDark
        $button.FlatAppearance.MouseDownBackColor = [Drawing.Color]::FromArgb(45, 48, 49)
        $button.BackColor = $titleBar.BackColor
        $button.ForeColor = $script:TextMuted
        $titleBar.Controls.Add($button)
        return $button
    }

    $minimizeButton = New-ChromeButton ([char]0x2212) 138
    $maximizeButton = New-ChromeButton ([char]0x25A1) 92
    $closeWindowButton = New-ChromeButton ([char]0x00D7) 46
    $closeWindowButton.FlatAppearance.MouseOverBackColor = [Drawing.Color]::FromArgb(170, 35, 35)
    $closeWindowButton.ForeColor = $script:TextLight
    $minimizeButton.Add_Click({ $script:Form.WindowState = [Windows.Forms.FormWindowState]::Minimized })
    $maximizeButton.Add_Click({
        $script:Form.WindowState = if ($script:Form.WindowState -eq [Windows.Forms.FormWindowState]::Maximized) {
            [Windows.Forms.FormWindowState]::Normal
        } else { [Windows.Forms.FormWindowState]::Maximized }
    })
    $closeWindowButton.Add_Click({ $script:Form.Hide() })
    $dragAction = {
        param($sender, $eventArgs)
        if ($eventArgs.Button -eq [Windows.Forms.MouseButtons]::Left) {
            [OpenSynapseNative.WindowChrome]::BeginDrag($script:Form.Handle)
        }
    }
    $titleBar.Add_MouseDown($dragAction)
    $brandPicture.Add_MouseDown($dragAction)
    $brandLabel.Add_MouseDown($dragAction)
    $titleBar.Add_DoubleClick({
        $script:Form.WindowState = if ($script:Form.WindowState -eq [Windows.Forms.FormWindowState]::Maximized) {
            [Windows.Forms.FormWindowState]::Normal
        } else { [Windows.Forms.FormWindowState]::Maximized }
    })

    $navigationPanel = New-Object Windows.Forms.Panel
    $navigationPanel.Location = New-Object Drawing.Point(0, 48)
    $navigationPanel.Size = New-Object Drawing.Size(80, 850)
    $navigationPanel.Anchor = 'Top, Bottom, Left'
    $navigationPanel.BackColor = [Drawing.Color]::FromArgb(6, 8, 9)
    $shell.Controls.Add($navigationPanel)

    $contentHost = New-Object Windows.Forms.Panel
    $contentHost.Location = New-Object Drawing.Point(80, 48)
    $contentHost.Size = New-Object Drawing.Size(1358, 850)
    $contentHost.Anchor = 'Top, Bottom, Left, Right'
    $contentHost.BackColor = $script:WindowDark
    $shell.Controls.Add($contentHost)

    function New-ContentPage {
        $page = New-Object Windows.Forms.Panel
        $page.Size = $contentHost.ClientSize
        $page.Dock = [Windows.Forms.DockStyle]::Fill
        $page.BackColor = $script:WindowDark
        $page.Visible = $false
        $contentHost.Controls.Add($page)
        return $page
    }

    $pageDashboard = New-ContentPage
    $pageGame = New-ContentPage
    $pageSettings = New-ContentPage
    $pageDiagnostics = New-ContentPage
    $pageAbout = New-ContentPage
    $script:NavigationPages = @{
        Dashboard = $pageDashboard
        Game = $pageGame
        Settings = $pageSettings
        Diagnostics = $pageDiagnostics
        About = $pageAbout
    }
    $script:NavigationButtons = @{}
    $navigationToolTip = New-Object Windows.Forms.ToolTip
    $navigationToolTip.InitialDelay = 250

    function New-NavButton([string]$Name, [int]$Glyph, [string]$ToolTip, [int]$Top) {
        $button = New-Object Windows.Forms.Button
        $button.Name = "Nav$Name"
        $button.Tag = $Name
        $button.Text = [char]$Glyph
        $button.Font = New-Object Drawing.Font('Segoe MDL2 Assets', 15)
        $button.Location = New-Object Drawing.Point(8, $Top)
        $button.Size = New-Object Drawing.Size(64, 54)
        $button.FlatStyle = [Windows.Forms.FlatStyle]::Flat
        $button.FlatAppearance.BorderSize = 0
        $button.FlatAppearance.MouseOverBackColor = $script:ControlDark
        $button.FlatAppearance.MouseDownBackColor = [Drawing.Color]::FromArgb(31, 47, 30)
        $button.BackColor = $navigationPanel.BackColor
        $button.ForeColor = $script:TextMuted
        $navigationToolTip.SetToolTip($button, $ToolTip)
        $navigationPanel.Controls.Add($button)
        $script:NavigationButtons[$Name] = $button
        return $button
    }

    $dashboardNav = New-NavButton 'Dashboard' 0xE80F 'Control panel' 20
    $gameNav = New-NavButton 'Game' 0xE7FC 'Game mode' 84
    $settingsNav = New-NavButton 'Settings' 0xE713 'Settings' 148
    $diagnosticsNav = New-NavButton 'Diagnostics' 0xE9D9 'Diagnostics' 212
    $aboutNav = New-NavButton 'About' 0xE946 'About OpenSynapse' 276

    function Show-NavigationPage([ValidateSet('Dashboard', 'Game', 'Settings', 'Diagnostics', 'About')][string]$Name) {
        foreach ($entry in $script:NavigationPages.GetEnumerator()) {
            $entry.Value.Visible = ([string]$entry.Key -eq $Name)
        }
        foreach ($entry in $script:NavigationButtons.GetEnumerator()) {
            $selected = ([string]$entry.Key -eq $Name)
            $entry.Value.BackColor = if ($selected) { [Drawing.Color]::FromArgb(18, 29, 18) } else { $navigationPanel.BackColor }
            $entry.Value.ForeColor = if ($selected) { $script:RazerGreen } else { $script:TextMuted }
        }
        $script:NavigationPages[$Name].BringToFront()
    }
    foreach ($button in @($dashboardNav, $gameNav, $settingsNav, $diagnosticsNav, $aboutNav)) {
        $button.Add_Click({ param($sender, $eventArgs) Show-NavigationPage ([string]$sender.Tag) })
    }

    function New-PageHeading([Windows.Forms.Control]$Parent, [string]$Heading, [string]$Description) {
        $headingLabel = New-Object Windows.Forms.Label
        $headingLabel.Text = $Heading
        $headingLabel.Font = New-Object Drawing.Font('Segoe UI Semibold', 19)
        $headingLabel.AutoSize = $false
        $headingLabel.Location = New-Object Drawing.Point(40, 26)
        $headingLabel.Size = New-Object Drawing.Size(920, 48)
        $headingLabel.ForeColor = [Drawing.Color]::White
        $Parent.Controls.Add($headingLabel)
        $descriptionLabel = New-Object Windows.Forms.Label
        $descriptionLabel.Text = $Description
        $descriptionLabel.Font = New-Object Drawing.Font('Segoe UI', 9)
        $descriptionLabel.AutoSize = $false
        $descriptionLabel.AutoEllipsis = $true
        $descriptionLabel.Location = New-Object Drawing.Point(42, 78)
        $descriptionLabel.Size = New-Object Drawing.Size(920, 32)
        $descriptionLabel.ForeColor = $script:TextMuted
        $Parent.Controls.Add($descriptionLabel)
    }

    # Dashboard
    New-PageHeading $pageDashboard 'OPENSYNAPSE' 'Razer Blade 16 power and display policy controller'
    $script:PowerLabel = New-Object Windows.Forms.Label
    $script:PowerLabel.Font = New-Object Drawing.Font('Segoe UI', 10, [Drawing.FontStyle]::Bold)
    $script:PowerLabel.AutoEllipsis = $true
    $script:PowerLabel.Location = New-Object Drawing.Point(42, 122)
    $script:PowerLabel.Size = New-Object Drawing.Size(980, 32)
    $script:PowerLabel.ForeColor = $script:RazerGreen
    $pageDashboard.Controls.Add($script:PowerLabel)

    $script:ModeLabel = New-Object Windows.Forms.Label
    $script:ModeLabel.Font = New-Object Drawing.Font('Segoe UI', 9)
    $script:ModeLabel.AutoEllipsis = $true
    $script:ModeLabel.Location = New-Object Drawing.Point(42, 158)
    $script:ModeLabel.Size = New-Object Drawing.Size(930, 28)
    $script:ModeLabel.ForeColor = $script:TextLight
    $pageDashboard.Controls.Add($script:ModeLabel)

    $autoButton = New-Object Windows.Forms.Button
    $autoButton.Text = 'Auto'
    $autoButton.Size = New-Object Drawing.Size(176, 44)
    $autoButton.Location = New-Object Drawing.Point(40, 196)
    $autoButton.Font = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Bold)
    Set-RazerButtonStyle $autoButton $true
    $pageDashboard.Controls.Add($autoButton)

    $hyperButton = New-Object Windows.Forms.Button
    $hyperButton.Text = 'Hyper'
    $hyperButton.Size = New-Object Drawing.Size(176, 44)
    $hyperButton.Location = New-Object Drawing.Point(226, 196)
    $hyperButton.Font = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Bold)
    Set-RazerButtonStyle $hyperButton $false
    $pageDashboard.Controls.Add($hyperButton)

    $balanceButton = New-Object Windows.Forms.Button
    $balanceButton.Text = 'Balance'
    $balanceButton.Size = New-Object Drawing.Size(176, 44)
    $balanceButton.Location = New-Object Drawing.Point(412, 196)
    $balanceButton.Font = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Bold)
    Set-RazerButtonStyle $balanceButton $false
    $pageDashboard.Controls.Add($balanceButton)

    $quietButton = New-Object Windows.Forms.Button
    $quietButton.Text = 'Eco'
    $quietButton.Size = New-Object Drawing.Size(176, 44)
    $quietButton.Location = New-Object Drawing.Point(598, 196)
    $quietButton.Font = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Bold)
    Set-RazerButtonStyle $quietButton $false
    $pageDashboard.Controls.Add($quietButton)

    $experimentButton = New-Object Windows.Forms.Button
    $experimentButton.Text = 'Experiment'
    $experimentButton.Size = New-Object Drawing.Size(176, 44)
    $experimentButton.Location = New-Object Drawing.Point(784, 196)
    $experimentButton.Font = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Bold)
    Set-RazerButtonStyle $experimentButton $false
    $pageDashboard.Controls.Add($experimentButton)

    $automationPanel = New-Object Windows.Forms.Panel
    $automationPanel.Location = New-Object Drawing.Point(40, 264)
    $automationPanel.Size = New-Object Drawing.Size(924, 324)
    $automationPanel.BackColor = $script:PanelDark
    $automationPanel.BorderStyle = [Windows.Forms.BorderStyle]::FixedSingle
    $pageDashboard.Controls.Add($automationPanel)
    $automationHeading = New-Object Windows.Forms.Label
    $automationHeading.Text = 'SMART AUTOMATION'
    $automationHeading.Font = New-Object Drawing.Font('Segoe UI Semibold', 10)
    $automationHeading.AutoSize = $true
    $automationHeading.Location = New-Object Drawing.Point(20, 18)
    $automationHeading.ForeColor = $script:RazerGreen
    $automationPanel.Controls.Add($automationHeading)
    $script:PolicyHintLabel = New-Object Windows.Forms.Label
    $script:PolicyHintLabel.AutoEllipsis = $true
    $script:PolicyHintLabel.Location = New-Object Drawing.Point(20, 52)
    $script:PolicyHintLabel.Size = New-Object Drawing.Size(876, 64)
    $script:PolicyHintLabel.ForeColor = $script:TextMuted
    $automationPanel.Controls.Add($script:PolicyHintLabel)
    $automationRule = New-Object Windows.Forms.Label
    $automationRule.Text = "POWER INPUT`r`n280W-class AC -> Hyper`r`nUSB-C PD / battery -> Eco or eligible Balance"
    $automationRule.Location = New-Object Drawing.Point(20, 150)
    $automationRule.Size = New-Object Drawing.Size(410, 110)
    $automationRule.ForeColor = $script:TextLight
    $automationPanel.Controls.Add($automationRule)
    $automationLoad = New-Object Windows.Forms.Label
    $automationLoad.Text = "WORKLOAD SIGNALS`r`nForeground and fullscreen app rules`r`nCPU / GPU load with hysteresis"
    $automationLoad.Location = New-Object Drawing.Point(476, 150)
    $automationLoad.Size = New-Object Drawing.Size(410, 110)
    $automationLoad.ForeColor = $script:TextLight
    $automationPanel.Controls.Add($automationLoad)

    $dashboardFooter = New-Object Windows.Forms.Label
    $dashboardFooter.Text = 'OpenSynapse uses public Windows interfaces. EC, fan, TGP and MUX controls remain untouched.'
    $dashboardFooter.Location = New-Object Drawing.Point(42, 620)
    $dashboardFooter.Size = New-Object Drawing.Size(920, 52)
    $dashboardFooter.ForeColor = $script:TextMuted
    $pageDashboard.Controls.Add($dashboardFooter)

    $statusPanel = New-Object Windows.Forms.Panel
    $statusPanel.Dock = [Windows.Forms.DockStyle]::Right
    $statusPanel.Width = 340
    $statusPanel.BackColor = [Drawing.Color]::FromArgb(12, 15, 16)
    $pageDashboard.Controls.Add($statusPanel)
    $statusHeading = New-Object Windows.Forms.Label
    $statusHeading.Text = 'STATUS'
    $statusHeading.Font = New-Object Drawing.Font('Segoe UI Semibold', 11)
    $statusHeading.AutoSize = $true
    $statusHeading.Location = New-Object Drawing.Point(32, 32)
    $statusHeading.ForeColor = $script:TextLight
    $statusPanel.Controls.Add($statusHeading)

    function New-StatusRow([string]$Name, [int]$Top) {
        $dot = New-Object Windows.Forms.Label
        $dot.Text = [char]0x25CF
        $dot.Font = New-Object Drawing.Font('Segoe UI Symbol', 9)
        $dot.AutoSize = $true
        $dot.Location = New-Object Drawing.Point(32, ($Top + 1))
        $dot.ForeColor = $script:RazerGreen
        $statusPanel.Controls.Add($dot)
        $nameLabel = New-Object Windows.Forms.Label
        $nameLabel.Text = $Name
        $nameLabel.Location = New-Object Drawing.Point(58, $Top)
        $nameLabel.Size = New-Object Drawing.Size(92, 26)
        $nameLabel.ForeColor = $script:TextMuted
        $statusPanel.Controls.Add($nameLabel)
        $valueLabel = New-Object Windows.Forms.Label
        $valueLabel.Text = '--'
        $valueLabel.Location = New-Object Drawing.Point(160, $Top)
        $valueLabel.Size = New-Object Drawing.Size(154, 26)
        $valueLabel.AutoEllipsis = $true
        $valueLabel.ForeColor = $script:TextLight
        $statusPanel.Controls.Add($valueLabel)
        return $valueLabel
    }
    $script:StatusProfileValue = New-StatusRow 'Profile' 88
    $script:StatusCpuValue = New-StatusRow 'CPU load' 132
    $script:StatusGpuValue = New-StatusRow 'GPU load' 176
    $script:StatusBatteryValue = New-StatusRow 'Battery' 220
    $script:StatusRateValue = New-StatusRow 'Rate' 264
    $script:StatusSupplyValue = New-StatusRow 'Supply' 308
    $script:StatusDgpuValue = New-StatusRow 'dGPU' 352
    $script:StatusHealthValue = New-StatusRow 'Health' 396
    $script:StatusThermalValue = New-StatusRow 'Thermal' 440
    $script:StatusNpuValue = New-StatusRow 'NPU' 484

    # Game mode
    New-PageHeading $pageGame 'GAME MODE' 'Workload-aware automation, Hyper tuning and temporary overrides'
    $gameAutomationPanel = New-Object Windows.Forms.Panel
    $gameAutomationPanel.Location = New-Object Drawing.Point(40, 130)
    $gameAutomationPanel.Size = New-Object Drawing.Size(840, 230)
    $gameAutomationPanel.BackColor = $script:PanelDark
    $gameAutomationPanel.BorderStyle = [Windows.Forms.BorderStyle]::FixedSingle
    $pageGame.Controls.Add($gameAutomationPanel)
    $script:SmartAutomationCheck = New-Object Windows.Forms.CheckBox
    $script:SmartAutomationCheck.Text = 'Enable Smart Auto: application, fullscreen and CPU/GPU load'
    $script:SmartAutomationCheck.Location = New-Object Drawing.Point(24, 25)
    $script:SmartAutomationCheck.Size = New-Object Drawing.Size(650, 30)
    $script:SmartAutomationCheck.Checked = [bool]$script:Config.SmartAutomationEnabled
    $script:SmartAutomationCheck.ForeColor = $script:TextLight
    $script:SmartAutomationCheck.BackColor = $script:PanelDark
    $script:SmartAutomationCheck.FlatStyle = [Windows.Forms.FlatStyle]::Flat
    $gameAutomationPanel.Controls.Add($script:SmartAutomationCheck)
    $hyperPolicyLabel = New-Object Windows.Forms.Label
    $hyperPolicyLabel.Text = 'Hyper CPU tuning'
    $hyperPolicyLabel.AutoSize = $true
    $hyperPolicyLabel.Location = New-Object Drawing.Point(24, 84)
    $hyperPolicyLabel.ForeColor = $script:TextMuted
    $gameAutomationPanel.Controls.Add($hyperPolicyLabel)
    $script:HyperPolicyValues = @('Sustained', 'Latency')
    $script:HyperPolicyBox = New-Object Windows.Forms.ComboBox
    $script:HyperPolicyBox.DropDownStyle = 'DropDownList'
    [void]$script:HyperPolicyBox.Items.AddRange(@(
        'Sustained maximum (recommended)',
        'Maximum responsiveness (more heat at idle)'
    ))
    $hyperPolicyIndex = [Array]::IndexOf([object[]]$script:HyperPolicyValues, [string]$script:Config.HyperCpuPolicy)
    if ($hyperPolicyIndex -lt 0) { $hyperPolicyIndex = 0 }
    $script:HyperPolicyBox.SelectedIndex = $hyperPolicyIndex
    $script:HyperPolicyBox.Location = New-Object Drawing.Point(180, 79)
    $script:HyperPolicyBox.Size = New-Object Drawing.Size(440, 30)
    Set-DarkComboStyle $script:HyperPolicyBox
    $gameAutomationPanel.Controls.Add($script:HyperPolicyBox)
    $gameNote = New-Object Windows.Forms.Label
    $gameNote.Text = 'Smart Auto uses hysteresis and supply verification to prevent rapid profile switching.'
    $gameNote.Location = New-Object Drawing.Point(24, 142)
    $gameNote.Size = New-Object Drawing.Size(650, 48)
    $gameNote.ForeColor = $script:TextMuted
    $gameAutomationPanel.Controls.Add($gameNote)

    $temporaryButton = New-Object Windows.Forms.Button
    $temporaryButton.Text = 'Temporary mode'
    $temporaryButton.Location = New-Object Drawing.Point(40, 390)
    $temporaryButton.Size = New-Object Drawing.Size(280, 46)
    Set-RazerButtonStyle $temporaryButton $true
    $pageGame.Controls.Add($temporaryButton)
    $rulesButton = New-Object Windows.Forms.Button
    $rulesButton.Text = 'Application rules'
    $rulesButton.Location = New-Object Drawing.Point(340, 390)
    $rulesButton.Size = New-Object Drawing.Size(280, 46)
    Set-RazerButtonStyle $rulesButton $false
    $pageGame.Controls.Add($rulesButton)
    $gameBoundary = New-Object Windows.Forms.Label
    $gameBoundary.Text = "Hyper prioritizes maximum output on verified 280W-class AC.`r`nOn USB-C PD or battery, manual Hyper remains input-power limited."
    $gameBoundary.Location = New-Object Drawing.Point(42, 476)
    $gameBoundary.Size = New-Object Drawing.Size(840, 76)
    $gameBoundary.ForeColor = $script:TextMuted
    $pageGame.Controls.Add($gameBoundary)

    # Settings
    New-PageHeading $pageSettings 'SETTINGS' 'Eco efficiency, display behavior and vendor control shortcuts'
    $optionsGroup = New-Object Windows.Forms.GroupBox
    $optionsGroup.Text = 'Power and display automation'
    $optionsGroup.Location = New-Object Drawing.Point(32, 126)
    $optionsGroup.Size = New-Object Drawing.Size(1290, 336)
    $optionsGroup.Anchor = 'Top, Left, Right'
    $optionsGroup.BackColor = $script:PanelDark
    $optionsGroup.ForeColor = $script:RazerGreen
    $pageSettings.Controls.Add($optionsGroup)

    function New-OptionCheck([string]$Text, [int]$X, [int]$Y, [bool]$Checked) {
        $control = New-Object Windows.Forms.CheckBox
        $control.Text = $Text
        $control.Location = New-Object Drawing.Point($X, $Y)
        $control.Size = New-Object Drawing.Size(520, 30)
        $control.Checked = $Checked
        $control.ForeColor = $script:TextLight
        $control.BackColor = $script:PanelDark
        $control.FlatStyle = [Windows.Forms.FlatStyle]::Flat
        $optionsGroup.Controls.Add($control)
        return $control
    }

    $script:CloseAppsCheck = New-OptionCheck 'Eco: close high-drain helper apps' 20 28 ([bool]$script:Config.CloseHighDrainAppsInQuiet)
    $script:ServicesCheck = New-OptionCheck 'Eco: pause Armoury Crate services' 20 64 ([bool]$script:Config.ManageAsusServices)
    $script:WakeCheck = New-OptionCheck 'Eco: disable selected wake devices' 20 100 ([bool]$script:Config.ManageWakeDevices)
    $script:ColorCheck = New-OptionCheck 'HDR by profile (applied only with display button)' 575 28 ([bool]$script:Config.ManageAdvancedColor)
    $script:BrightnessCheck = New-OptionCheck 'Manage brightness (Eco adapts on battery)' 575 64 ([bool]$script:Config.ManageBrightness)
    $script:BatteryHighDrainCheck = New-OptionCheck 'Battery: notify sustained high-CPU processes (never closes them)' 575 136 ([bool]$script:Config.BatteryHighDrainAlertsEnabled)
    $script:BatteryHighDrainCheck.Size = New-Object Drawing.Size(690, 30)
    $scaleLabel = New-Object Windows.Forms.Label
    $scaleLabel.Text = 'Scaling: internal'
    $scaleLabel.AutoSize = $true
    $scaleLabel.Location = New-Object Drawing.Point(20, 191)
    $scaleLabel.ForeColor = $script:TextMuted
    $optionsGroup.Controls.Add($scaleLabel)
    $script:InternalScaleBox = New-Object Windows.Forms.ComboBox
    $script:InternalScaleBox.DropDownStyle = 'DropDownList'
    [void]$script:InternalScaleBox.Items.AddRange(@(100, 125, 150, 175, 200, 225, 250, 300))
    $script:InternalScaleBox.SelectedItem = [int]$script:Config.InternalScale
    $script:InternalScaleBox.Location = New-Object Drawing.Point(175, 186)
    $script:InternalScaleBox.Size = New-Object Drawing.Size(92, 30)
    $script:InternalScaleBox.BackColor = $script:ControlDark
    $script:InternalScaleBox.ForeColor = $script:TextLight
    $script:InternalScaleBox.FlatStyle = [Windows.Forms.FlatStyle]::Flat
    Set-DarkComboStyle $script:InternalScaleBox
    $optionsGroup.Controls.Add($script:InternalScaleBox)

    $externalLabel = New-Object Windows.Forms.Label
    $externalLabel.Text = 'external'
    $externalLabel.AutoSize = $true
    $externalLabel.Location = New-Object Drawing.Point(300, 191)
    $externalLabel.ForeColor = $script:TextMuted
    $optionsGroup.Controls.Add($externalLabel)
    $script:ExternalScaleBox = New-Object Windows.Forms.ComboBox
    $script:ExternalScaleBox.DropDownStyle = 'DropDownList'
    [void]$script:ExternalScaleBox.Items.AddRange(@(100, 125, 150, 175, 200, 225, 250, 300))
    $script:ExternalScaleBox.SelectedItem = [int]$script:Config.ExternalScale
    $script:ExternalScaleBox.Location = New-Object Drawing.Point(390, 186)
    $script:ExternalScaleBox.Size = New-Object Drawing.Size(92, 30)
    $script:ExternalScaleBox.BackColor = $script:ControlDark
    $script:ExternalScaleBox.ForeColor = $script:TextLight
    $script:ExternalScaleBox.FlatStyle = [Windows.Forms.FlatStyle]::Flat
    Set-DarkComboStyle $script:ExternalScaleBox
    $optionsGroup.Controls.Add($script:ExternalScaleBox)

    $script:ScalingCheck = New-OptionCheck 'Repair scaling after display changes' 575 100 ([bool]$script:Config.DisplayScalingEnabled)

    $quietPolicyLabel = New-Object Windows.Forms.Label
    $quietPolicyLabel.Text = 'Eco CPU policy'
    $quietPolicyLabel.AutoSize = $true
    $quietPolicyLabel.Location = New-Object Drawing.Point(20, 146)
    $quietPolicyLabel.ForeColor = $script:TextMuted
    $optionsGroup.Controls.Add($quietPolicyLabel)
    $quietPolicyValue = New-Object Windows.Forms.Label
    $quietPolicyValue.Text = '65 / 60 / 50%; EPP 90 / 95 / 100; Boost off'
    $quietPolicyValue.Location = New-Object Drawing.Point(175, 146)
    $quietPolicyValue.Size = New-Object Drawing.Size(390, 30)
    $quietPolicyValue.ForeColor = $script:TextLight
    $optionsGroup.Controls.Add($quietPolicyValue)

    $brightnessLabel = New-Object Windows.Forms.Label
    $brightnessLabel.Text = 'Eco ceiling'
    $brightnessLabel.AutoSize = $true
    $brightnessLabel.Location = New-Object Drawing.Point(575, 191)
    $brightnessLabel.ForeColor = $script:TextMuted
    $optionsGroup.Controls.Add($brightnessLabel)
    $script:BrightnessBox = New-Object Windows.Forms.ComboBox
    $script:BrightnessBox.DropDownStyle = 'DropDownList'
    [void]$script:BrightnessBox.Items.AddRange([object[]](10..100 | Where-Object { $_ % 5 -eq 0 }))
    $script:BrightnessBox.SelectedItem = [int]$script:Config.QuietBrightness
    $script:BrightnessBox.Location = New-Object Drawing.Point(765, 186)
    $script:BrightnessBox.Size = New-Object Drawing.Size(80, 30)
    $script:BrightnessBox.BackColor = $script:ControlDark
    $script:BrightnessBox.ForeColor = $script:TextLight
    Set-DarkComboStyle $script:BrightnessBox
    $optionsGroup.Controls.Add($script:BrightnessBox)

    $balanceBrightnessLabel = New-Object Windows.Forms.Label
    $balanceBrightnessLabel.Text = 'Balance'
    $balanceBrightnessLabel.AutoSize = $true
    $balanceBrightnessLabel.Location = New-Object Drawing.Point(875, 191)
    $balanceBrightnessLabel.ForeColor = $script:TextMuted
    $optionsGroup.Controls.Add($balanceBrightnessLabel)
    $script:BalanceBrightnessBox = New-Object Windows.Forms.ComboBox
    $script:BalanceBrightnessBox.DropDownStyle = 'DropDownList'
    [void]$script:BalanceBrightnessBox.Items.AddRange([object[]](10..100 | Where-Object { $_ % 5 -eq 0 }))
    $script:BalanceBrightnessBox.SelectedItem = [int]$script:Config.BalanceBrightness
    $script:BalanceBrightnessBox.Location = New-Object Drawing.Point(970, 186)
    $script:BalanceBrightnessBox.Size = New-Object Drawing.Size(80, 30)
    $script:BalanceBrightnessBox.BackColor = $script:ControlDark
    $script:BalanceBrightnessBox.ForeColor = $script:TextLight
    Set-DarkComboStyle $script:BalanceBrightnessBox
    $optionsGroup.Controls.Add($script:BalanceBrightnessBox)

    $refreshLabel = New-Object Windows.Forms.Label
    $refreshLabel.Text = 'Refresh policy'
    $refreshLabel.AutoSize = $true
    $refreshLabel.Location = New-Object Drawing.Point(20, 255)
    $refreshLabel.ForeColor = $script:TextMuted
    $optionsGroup.Controls.Add($refreshLabel)
    $script:RefreshPolicyValues = @('Auto', 'Fixed60', 'Fixed240', 'Unmanaged')
    $script:RefreshPolicyBox = New-Object Windows.Forms.ComboBox
    $script:RefreshPolicyBox.DropDownStyle = 'DropDownList'
    [void]$script:RefreshPolicyBox.Items.AddRange(@(
        'Auto: battery / PD dynamic 60-240 Hz; verified 280W fixed 240 Hz',
        'Eco: internal fixed 60 Hz (returns to Auto when power is connected)',
        'Internal fixed 240 Hz (returns to Auto when power is connected)',
        'Do not manage refresh rate'
    ))
    $policyIndex = [Array]::IndexOf([object[]]$script:RefreshPolicyValues, [string]$script:Config.RefreshPolicy)
    if ($policyIndex -lt 0) { $policyIndex = 0 }
    $script:RefreshPolicyBox.SelectedIndex = $policyIndex
    $script:RefreshPolicyBox.Location = New-Object Drawing.Point(150, 250)
    $script:RefreshPolicyBox.Size = New-Object Drawing.Size(640, 30)
    $script:RefreshPolicyBox.Anchor = 'Top, Left, Right'
    $script:RefreshPolicyBox.BackColor = $script:ControlDark
    $script:RefreshPolicyBox.ForeColor = $script:TextLight
    $script:RefreshPolicyBox.FlatStyle = [Windows.Forms.FlatStyle]::Flat
    Set-DarkComboStyle $script:RefreshPolicyBox
    $optionsGroup.Controls.Add($script:RefreshPolicyBox)

    $applyDisplayButton = New-Object Windows.Forms.Button
    $applyDisplayButton.Text = 'Apply display now (may blink)'
    $applyDisplayButton.Location = New-Object Drawing.Point(830, 247)
    $applyDisplayButton.Size = New-Object Drawing.Size(360, 38)
    $applyDisplayButton.Anchor = 'Top, Right'
    Set-RazerButtonStyle $applyDisplayButton $false
    $optionsGroup.Controls.Add($applyDisplayButton)

    $manualGroup = New-Object Windows.Forms.GroupBox
    $manualGroup.Text = 'Vendor controls (one-time hardware setup)'
    $manualGroup.Location = New-Object Drawing.Point(32, 490)
    $manualGroup.Size = New-Object Drawing.Size(1290, 122)
    $manualGroup.Anchor = 'Top, Left, Right'
    $manualGroup.BackColor = $script:PanelDark
    $manualGroup.ForeColor = $script:RazerGreen
    $pageSettings.Controls.Add($manualGroup)

    $manualNote = New-Object Windows.Forms.Label
    $manualNote.Text = 'Synapse: Custom CPU/GPU High. NVIDIA: Automatic Select or Optimus.'
    $manualNote.AutoSize = $true
    $manualNote.Location = New-Object Drawing.Point(20, 31)
    $manualNote.ForeColor = $script:TextMuted
    $manualGroup.Controls.Add($manualNote)

    $synapseButton = New-Object Windows.Forms.Button
    $synapseButton.Text = 'Open Razer Synapse'
    $synapseButton.Location = New-Object Drawing.Point(20, 68)
    $synapseButton.Size = New-Object Drawing.Size(380, 38)
    Set-RazerButtonStyle $synapseButton $false
    $manualGroup.Controls.Add($synapseButton)

    $nvidiaButton = New-Object Windows.Forms.Button
    $nvidiaButton.Text = 'NVIDIA Control Panel'
    $nvidiaButton.Location = New-Object Drawing.Point(454, 68)
    $nvidiaButton.Size = New-Object Drawing.Size(380, 38)
    Set-RazerButtonStyle $nvidiaButton $false
    $manualGroup.Controls.Add($nvidiaButton)

    $displayButton = New-Object Windows.Forms.Button
    $displayButton.Text = 'Windows Display Settings'
    $displayButton.Location = New-Object Drawing.Point(888, 68)
    $displayButton.Size = New-Object Drawing.Size(380, 38)
    $displayButton.Anchor = 'Top, Right'
    Set-RazerButtonStyle $displayButton $false
    $manualGroup.Controls.Add($displayButton)

    $razerMouseGroup = New-Object Windows.Forms.GroupBox
    $razerMouseGroup.Text = 'Razer DeathAdder V3 Pro HID control'
    $razerMouseGroup.Location = New-Object Drawing.Point(32, 632)
    $razerMouseGroup.Size = New-Object Drawing.Size(1290, 154)
    $razerMouseGroup.Anchor = 'Top, Left, Right'
    $razerMouseGroup.BackColor = $script:PanelDark
    $razerMouseGroup.ForeColor = $script:RazerGreen
    $pageSettings.Controls.Add($razerMouseGroup)

    $script:RazerMouseStatusLabel = New-Object Windows.Forms.Label
    $script:RazerMouseStatusLabel.Text = 'Detecting supported Razer mouse...'
    $script:RazerMouseStatusLabel.Location = New-Object Drawing.Point(20, 28)
    $script:RazerMouseStatusLabel.Size = New-Object Drawing.Size(1200, 42)
    $script:RazerMouseStatusLabel.AutoEllipsis = $true
    $script:RazerMouseStatusLabel.ForeColor = $script:TextMuted
    $razerMouseGroup.Controls.Add($script:RazerMouseStatusLabel)

    $razerDpiLabel = New-Object Windows.Forms.Label
    $razerDpiLabel.Text = 'DPI'
    $razerDpiLabel.AutoSize = $true
    $razerDpiLabel.Location = New-Object Drawing.Point(20, 94)
    $razerDpiLabel.ForeColor = $script:TextMuted
    $razerMouseGroup.Controls.Add($razerDpiLabel)

    $script:RazerDpiBox = New-Object Windows.Forms.TextBox
    $script:RazerDpiBox.Text = '1600'
    $script:RazerDpiBox.Location = New-Object Drawing.Point(72, 88)
    $script:RazerDpiBox.Size = New-Object Drawing.Size(110, 30)
    $script:RazerDpiBox.BackColor = $script:ControlDark
    $script:RazerDpiBox.ForeColor = $script:TextLight
    $script:RazerDpiBox.BorderStyle = [Windows.Forms.BorderStyle]::FixedSingle
    $razerMouseGroup.Controls.Add($script:RazerDpiBox)

    $razerApplyDpiButton = New-Object Windows.Forms.Button
    $razerApplyDpiButton.Text = 'Apply DPI'
    $razerApplyDpiButton.Location = New-Object Drawing.Point(198, 84)
    $razerApplyDpiButton.Size = New-Object Drawing.Size(120, 38)
    Set-RazerButtonStyle $razerApplyDpiButton $false
    $razerMouseGroup.Controls.Add($razerApplyDpiButton)

    $razerPollingLabel = New-Object Windows.Forms.Label
    $razerPollingLabel.Text = 'Polling'
    $razerPollingLabel.AutoSize = $true
    $razerPollingLabel.Location = New-Object Drawing.Point(354, 94)
    $razerPollingLabel.ForeColor = $script:TextMuted
    $razerMouseGroup.Controls.Add($razerPollingLabel)

    $script:RazerPollingBox = New-Object Windows.Forms.ComboBox
    $script:RazerPollingBox.DropDownStyle = 'DropDownList'
    [void]$script:RazerPollingBox.Items.AddRange(@(125, 500, 1000))
    $script:RazerPollingBox.SelectedItem = 1000
    $script:RazerPollingBox.Location = New-Object Drawing.Point(432, 88)
    $script:RazerPollingBox.Size = New-Object Drawing.Size(120, 30)
    Set-DarkComboStyle $script:RazerPollingBox
    $razerMouseGroup.Controls.Add($script:RazerPollingBox)

    $razerApplyPollingButton = New-Object Windows.Forms.Button
    $razerApplyPollingButton.Text = 'Apply polling'
    $razerApplyPollingButton.Location = New-Object Drawing.Point(568, 84)
    $razerApplyPollingButton.Size = New-Object Drawing.Size(140, 38)
    Set-RazerButtonStyle $razerApplyPollingButton $false
    $razerMouseGroup.Controls.Add($razerApplyPollingButton)

    $razerRefreshButton = New-Object Windows.Forms.Button
    $razerRefreshButton.Text = 'Refresh device'
    $razerRefreshButton.Location = New-Object Drawing.Point(1088, 84)
    $razerRefreshButton.Size = New-Object Drawing.Size(180, 38)
    $razerRefreshButton.Anchor = 'Top, Right'
    Set-RazerButtonStyle $razerRefreshButton $false
    $razerMouseGroup.Controls.Add($razerRefreshButton)

    # Diagnostics
    New-PageHeading $pageDiagnostics 'DIAGNOSTICS' 'Live display, battery, dGPU and automation evidence'
    $script:DetailBox = New-Object Windows.Forms.TextBox
    $script:DetailBox.Multiline = $true
    $script:DetailBox.ReadOnly = $true
    $script:DetailBox.ScrollBars = 'Vertical'
    $script:DetailBox.BackColor = [Drawing.Color]::FromArgb(10, 10, 10)
    $script:DetailBox.ForeColor = [Drawing.Color]::FromArgb(185, 235, 178)
    $script:DetailBox.BorderStyle = [Windows.Forms.BorderStyle]::FixedSingle
    $script:DetailBox.Font = New-Object Drawing.Font('Consolas', 9)
    $script:DetailBox.Location = New-Object Drawing.Point(40, 130)
    $script:DetailBox.Size = New-Object Drawing.Size(1278, 600)
    $script:DetailBox.Anchor = 'Top, Bottom, Left, Right'
    $pageDiagnostics.Controls.Add($script:DetailBox)

    $refreshStatusButton = New-Object Windows.Forms.Button
    $refreshStatusButton.Text = 'Refresh status'
    $refreshStatusButton.Location = New-Object Drawing.Point(40, 756)
    $refreshStatusButton.Size = New-Object Drawing.Size(220, 42)
    Set-RazerButtonStyle $refreshStatusButton $false
    $pageDiagnostics.Controls.Add($refreshStatusButton)

    $openLogButton = New-Object Windows.Forms.Button
    $openLogButton.Text = 'Open log'
    $openLogButton.Location = New-Object Drawing.Point(280, 756)
    $openLogButton.Size = New-Object Drawing.Size(220, 42)
    Set-RazerButtonStyle $openLogButton $false
    $pageDiagnostics.Controls.Add($openLogButton)

    $exportButton = New-Object Windows.Forms.Button
    $exportButton.Text = 'Export diagnostics'
    $exportButton.Location = New-Object Drawing.Point(520, 756)
    $exportButton.Size = New-Object Drawing.Size(220, 42)
    Set-RazerButtonStyle $exportButton $true
    $pageDiagnostics.Controls.Add($exportButton)

    $experimentReportButton = New-Object Windows.Forms.Button
    $experimentReportButton.Text = 'Experiment report'
    $experimentReportButton.Location = New-Object Drawing.Point(760, 756)
    $experimentReportButton.Size = New-Object Drawing.Size(220, 42)
    Set-RazerButtonStyle $experimentReportButton $false
    $pageDiagnostics.Controls.Add($experimentReportButton)

    # About
    New-PageHeading $pageAbout 'ABOUT' 'OpenSynapse safe power and display policy controller'
    $aboutLogo = New-Object Windows.Forms.PictureBox
    $aboutLogo.Location = New-Object Drawing.Point(100, 156)
    $aboutLogo.Size = New-Object Drawing.Size(320, 320)
    $aboutLogo.SizeMode = [Windows.Forms.PictureBoxSizeMode]::Zoom
    $aboutLogo.BackColor = [Drawing.Color]::Transparent
    if ($null -ne $script:BrandImageResource) { $aboutLogo.Image = $script:BrandImageResource }
    $pageAbout.Controls.Add($aboutLogo)
    $aboutTitle = New-Object Windows.Forms.Label
    $aboutTitle.Text = "OpenSynapse $script:AppVersion"
    $aboutTitle.Font = New-Object Drawing.Font('Segoe UI Semibold', 22)
    $aboutTitle.AutoSize = $true
    $aboutTitle.Location = New-Object Drawing.Point(480, 176)
    $aboutTitle.ForeColor = [Drawing.Color]::White
    $pageAbout.Controls.Add($aboutTitle)
    $aboutBody = New-Object Windows.Forms.Label
    $aboutBody.Text = "Designed for the Razer Blade 16 (2025).`r`n`r`nPublic Windows APIs only. OpenSynapse does not write the EC and does not control fan curves, TGP or MUX state. DeathAdder V3 Pro settings use its standard HID feature-report interface.`r`n`r`nClose hides the control panel; the tray automation remains active."
    $aboutBody.Location = New-Object Drawing.Point(484, 242)
    $aboutBody.Size = New-Object Drawing.Size(700, 200)
    $aboutBody.ForeColor = $script:TextMuted
    $pageAbout.Controls.Add($aboutBody)
    $restoreButton = New-Object Windows.Forms.Button
    $restoreButton.Text = 'Exit and restore'
    $restoreButton.Location = New-Object Drawing.Point(484, 474)
    $restoreButton.Size = New-Object Drawing.Size(260, 44)
    Set-RazerButtonStyle $restoreButton $false
    $pageAbout.Controls.Add($restoreButton)
    $aboutVersion = New-Object Windows.Forms.Label
    $aboutVersion.Text = 'Power / automation core preserved from 2.3.1'
    $aboutVersion.Location = New-Object Drawing.Point(484, 540)
    $aboutVersion.Size = New-Object Drawing.Size(420, 32)
    $aboutVersion.ForeColor = $script:TextMuted
    $pageAbout.Controls.Add($aboutVersion)

    Show-NavigationPage 'Dashboard'

    function Clear-TemporaryOverride([string]$Reason = 'cancelled') {
        if ($null -ne $script:TemporaryOverride) { Write-AppLog "Temporary mode ${Reason}: $($script:TemporaryOverride.Profile)." }
        $script:TemporaryOverride = $null
    }

    function Get-TemporaryProfile([object]$Snapshot) {
        if ($null -eq $script:TemporaryOverride) { return '' }
        if ([DateTime]$script:TemporaryOverride.ExpiresAt -ne [DateTime]::MaxValue -and (Get-Date) -ge [DateTime]$script:TemporaryOverride.ExpiresAt) {
            Clear-TemporaryOverride 'expired'
            return ''
        }
        if ([bool]$script:TemporaryOverride.EndOnSupplyChange -and
            -not [string]::Equals([string]$script:TemporaryOverride.SupplyType, [string]$Snapshot.SupplyType, [StringComparison]::OrdinalIgnoreCase)) {
            Clear-TemporaryOverride 'ended after power source changed'
            return ''
        }
        if ([string]$script:TemporaryOverride.Profile -eq 'Balance' -and
            [int]$Snapshot.BatteryPercent -ge 0 -and [int]$Snapshot.BatteryPercent -lt [int]$script:Config.BalanceBatteryThreshold) {
            $script:TemporaryOverride.Profile = 'Quiet'
            Write-AppLog "Temporary Balance fell below $($script:Config.BalanceBatteryThreshold)% and was latched to Quiet."
        }
        return [string]$script:TemporaryOverride.Profile
    }

    function Set-TemporaryProfile([ValidateSet('Hyper', 'Balance', 'Quiet')][string]$ProfileName, [int]$Minutes = 30, [bool]$EndOnSupplyChange = $false) {
        if ([string]$script:Config.Selection -eq 'Experiment') {
            $script:TrayIcon.BalloonTipTitle = 'Experiment is locked'
            $script:TrayIcon.BalloonTipText = 'End Experiment before applying a temporary power override.'
            $script:TrayIcon.ShowBalloonTip(3000)
            return
        }
        $snapshot = Get-PowerSnapshot -UseCachedAdapter
        if ($ProfileName -eq 'Hyper' -and [string]$snapshot.SupplyType -ne 'HighPowerAC') {
            $answer = [Windows.Forms.MessageBox]::Show(
                'Hyper on battery, USB-C PD or unverified AC remains power-limited. Start this temporary override?',
                'OpenSynapse temporary Hyper', [Windows.Forms.MessageBoxButtons]::YesNo, [Windows.Forms.MessageBoxIcon]::Warning)
            if ($answer -ne [Windows.Forms.DialogResult]::Yes) { return }
        }
        if ($ProfileName -eq 'Balance' -and -not (Test-BalanceEligible $snapshot ([int]$script:Config.BalanceBatteryThreshold))) {
            [Windows.Forms.MessageBox]::Show("Balance requires at least $($script:Config.BalanceBatteryThreshold)% battery.", 'OpenSynapse', 'OK', 'Information') | Out-Null
            return
        }
        $script:TemporaryOverride = [pscustomobject][ordered]@{
            Profile = $ProfileName
            StartedAt = Get-Date
            ExpiresAt = if ($EndOnSupplyChange) { [DateTime]::MaxValue } else { (Get-Date).AddMinutes([Math]::Max(1, $Minutes)) }
            EndOnSupplyChange = $EndOnSupplyChange
            SupplyType = [string]$snapshot.SupplyType
        }
        Write-AppLog "Temporary mode started: $ProfileName; minutes=$Minutes; endOnSupplyChange=$EndOnSupplyChange; supply=$($snapshot.SupplyType)."
        Apply-CurrentSelection -Full -Notify -Snapshot $snapshot
    }

    function Show-TemporaryModeDialog {
        $dialog = New-Object Windows.Forms.Form
        $dialog.Text = 'OpenSynapse temporary mode'
        $dialog.ClientSize = New-Object Drawing.Size(500, 230)
        $dialog.FormBorderStyle = 'FixedDialog'
        $dialog.StartPosition = 'CenterParent'
        $dialog.MaximizeBox = $false
        $dialog.MinimizeBox = $false
        $dialog.BackColor = $script:WindowDark
        $dialog.ForeColor = $script:TextLight
        $dialog.Font = $script:Form.Font
        $profileBox = New-Object Windows.Forms.ComboBox
        $profileBox.DropDownStyle = 'DropDownList'
        [void]$profileBox.Items.AddRange(@('Hyper', 'Balance', 'Eco'))
        $profileBox.SelectedIndex = 2
        $profileBox.Location = New-Object Drawing.Point(28, 46)
        $profileBox.Size = New-Object Drawing.Size(200, 30)
        Set-DarkComboStyle $profileBox
        $durationBox = New-Object Windows.Forms.ComboBox
        $durationBox.DropDownStyle = 'DropDownList'
        [void]$durationBox.Items.AddRange(@('30 minutes', '60 minutes', '120 minutes', 'Until power source changes'))
        $durationBox.SelectedIndex = 0
        $durationBox.Location = New-Object Drawing.Point(252, 46)
        $durationBox.Size = New-Object Drawing.Size(220, 30)
        Set-DarkComboStyle $durationBox
        $note = New-Object Windows.Forms.Label
        $note.Text = 'The previous persistent selection resumes automatically when this override ends.'
        $note.Location = New-Object Drawing.Point(28, 96)
        $note.Size = New-Object Drawing.Size(444, 46)
        $note.ForeColor = $script:TextMuted
        $startButton = New-Object Windows.Forms.Button
        $startButton.Text = 'Start temporary mode'
        $startButton.Location = New-Object Drawing.Point(252, 166)
        $startButton.Size = New-Object Drawing.Size(220, 38)
        Set-RazerButtonStyle $startButton $true
        $cancelButton = New-Object Windows.Forms.Button
        $cancelButton.Text = 'Cancel current override'
        $cancelButton.Location = New-Object Drawing.Point(28, 166)
        $cancelButton.Size = New-Object Drawing.Size(200, 38)
        Set-RazerButtonStyle $cancelButton $false
        $dialog.Controls.AddRange(@($profileBox, $durationBox, $note, $startButton, $cancelButton))
        $startButton.Add_Click({
            $endOnPower = $durationBox.SelectedIndex -eq 3
            $minutes = @(30, 60, 120, 30)[$durationBox.SelectedIndex]
            $dialog.DialogResult = [Windows.Forms.DialogResult]::OK
            $dialog.Close()
            $selectedProfile = if ([string]$profileBox.SelectedItem -eq 'Eco') { 'Quiet' } else { [string]$profileBox.SelectedItem }
            Set-TemporaryProfile $selectedProfile $minutes $endOnPower
        })
        $cancelButton.Add_Click({ Clear-TemporaryOverride; $dialog.Close(); Apply-CurrentSelection -Full -Notify })
        $null = $dialog.ShowDialog($script:Form)
        $dialog.Dispose()
    }

    function Show-ApplicationRulesEditor {
        $dialog = New-Object Windows.Forms.Form
        $dialog.Text = 'OpenSynapse application rules'
        $dialog.ClientSize = New-Object Drawing.Size(850, 560)
        $dialog.MinimumSize = $dialog.Size
        $dialog.StartPosition = 'CenterParent'
        $dialog.BackColor = $script:WindowDark
        $dialog.ForeColor = $script:TextLight
        $dialog.Font = $script:Form.Font
        $grid = New-Object Windows.Forms.DataGridView
        $grid.Location = New-Object Drawing.Point(24, 24)
        $grid.Size = New-Object Drawing.Size(802, 445)
        $grid.Anchor = 'Top, Bottom, Left, Right'
        $grid.AllowUserToAddRows = $false
        $grid.AllowUserToDeleteRows = $true
        $grid.SelectionMode = [Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
        $grid.MultiSelect = $true
        $grid.AutoSizeColumnsMode = 'Fill'
        $grid.BackgroundColor = $script:PanelDark
        $grid.GridColor = [Drawing.Color]::FromArgb(70, 70, 70)
        $grid.EnableHeadersVisualStyles = $false
        $grid.ColumnHeadersDefaultCellStyle.BackColor = $script:ControlDark
        $grid.ColumnHeadersDefaultCellStyle.ForeColor = $script:TextLight
        $grid.RowHeadersDefaultCellStyle.BackColor = $script:ControlDark
        $grid.RowHeadersDefaultCellStyle.ForeColor = $script:TextLight
        $grid.DefaultCellStyle.BackColor = $script:ControlDark
        $grid.DefaultCellStyle.ForeColor = $script:TextLight
        $grid.DefaultCellStyle.SelectionBackColor = [Drawing.Color]::FromArgb(48, 72, 44)
        $enabledColumn = New-Object Windows.Forms.DataGridViewCheckBoxColumn
        $enabledColumn.Name = 'Enabled'; $enabledColumn.HeaderText = 'Enabled'; $enabledColumn.FillWeight = 18
        $processColumn = New-Object Windows.Forms.DataGridViewTextBoxColumn
        $processColumn.Name = 'ProcessName'; $processColumn.HeaderText = 'Process (without .exe)'; $processColumn.FillWeight = 48
        $profileColumn = New-Object Windows.Forms.DataGridViewComboBoxColumn
        $profileColumn.Name = 'Profile'; $profileColumn.HeaderText = 'Profile'; $profileColumn.FillWeight = 24
        [void]$profileColumn.Items.AddRange(@('Hyper', 'Balance', 'Eco'))
        $scopeColumn = New-Object Windows.Forms.DataGridViewComboBoxColumn
        $scopeColumn.Name = 'Scope'; $scopeColumn.HeaderText = 'Trigger'; $scopeColumn.FillWeight = 32
        [void]$scopeColumn.Items.AddRange(@('Foreground', 'Fullscreen', 'Running'))
        foreach ($column in @($enabledColumn, $processColumn, $profileColumn, $scopeColumn)) { [void]$grid.Columns.Add($column) }
        foreach ($rule in @($script:Config.ApplicationRules)) {
            $profileDisplayName = if ([string]$rule.Profile -eq 'Quiet') { 'Eco' } else { [string]$rule.Profile }
            [void]$grid.Rows.Add([bool]$rule.Enabled, [string]$rule.ProcessName, $profileDisplayName, [string]$rule.Scope)
        }
        $addCurrentButton = New-Object Windows.Forms.Button
        $addCurrentButton.Text = 'Add last active app'
        $addCurrentButton.Location = New-Object Drawing.Point(24, 493)
        $addCurrentButton.Size = New-Object Drawing.Size(190, 38)
        Set-RazerButtonStyle $addCurrentButton $false
        $addButton = New-Object Windows.Forms.Button
        $addButton.Text = 'Add blank rule'
        $addButton.Location = New-Object Drawing.Point(230, 493)
        $addButton.Size = New-Object Drawing.Size(150, 38)
        Set-RazerButtonStyle $addButton $false
        $removeButton = New-Object Windows.Forms.Button
        $removeButton.Text = 'Remove selected'
        $removeButton.Location = New-Object Drawing.Point(396, 493)
        $removeButton.Size = New-Object Drawing.Size(160, 38)
        Set-RazerButtonStyle $removeButton $false
        $saveButton = New-Object Windows.Forms.Button
        $saveButton.Text = 'Save rules'
        $saveButton.Location = New-Object Drawing.Point(666, 493)
        $saveButton.Size = New-Object Drawing.Size(160, 38)
        $saveButton.Anchor = 'Bottom, Right'
        Set-RazerButtonStyle $saveButton $true
        $dialog.Controls.AddRange(@($grid, $addCurrentButton, $addButton, $removeButton, $saveButton))
        $addCurrentButton.Add_Click({
            $foregroundName = [string]$script:LastExternalForegroundProcess
            if ([string]::IsNullOrWhiteSpace($foregroundName)) { $foregroundName = 'process-name' }
            [void]$grid.Rows.Add($true, $foregroundName, 'Balance', 'Foreground')
        })
        $addButton.Add_Click({ [void]$grid.Rows.Add($true, 'process-name', 'Balance', 'Foreground') })
        $removeButton.Add_Click({ foreach ($row in @($grid.SelectedRows)) { if (-not $row.IsNewRow) { $grid.Rows.Remove($row) } } })
        $saveButton.Add_Click({
            $rules = New-Object Collections.Generic.List[object]
            foreach ($row in $grid.Rows) {
                if ($row.IsNewRow) { continue }
                $processName = ([string]$row.Cells['ProcessName'].Value).Trim()
                if ($processName.EndsWith('.exe', [StringComparison]::OrdinalIgnoreCase)) { $processName = $processName.Substring(0, $processName.Length - 4) }
                $profileDisplayName = [string]$row.Cells['Profile'].Value
                $profileName = if ($profileDisplayName -eq 'Eco') { 'Quiet' } else { $profileDisplayName }
                $scopeName = [string]$row.Cells['Scope'].Value
                if ([string]::IsNullOrWhiteSpace($processName) -or $profileName -notin @('Hyper', 'Balance', 'Quiet') -or $scopeName -notin @('Foreground', 'Fullscreen', 'Running')) {
                    [Windows.Forms.MessageBox]::Show('Every rule needs a process name, profile and trigger.', 'OpenSynapse rules', 'OK', 'Warning') | Out-Null
                    return
                }
                $rules.Add([pscustomobject][ordered]@{ ProcessName = $processName; Profile = $profileName; Scope = $scopeName; Enabled = [bool]$row.Cells['Enabled'].Value })
            }
            $script:Config.ApplicationRules = $rules.ToArray()
            Save-AppConfig $script:Config
            Write-AppLog "Application rules saved: $($rules.Count)."
            $dialog.DialogResult = [Windows.Forms.DialogResult]::OK
            $dialog.Close()
        })
        $null = $dialog.ShowDialog($script:Form)
        $dialog.Dispose()
    }

    function Update-ApplicationUi {
        param(
            [AllowNull()][object]$Snapshot = $null,
            [string]$Desired = '',
            [string]$TemporaryProfile = '',
            [string]$ActiveName = ''
        )
        $snapshot = if ($null -eq $Snapshot) { Get-PowerSnapshot -UseCachedAdapter } else { $Snapshot }
        $temporaryProfile = if ([string]::IsNullOrWhiteSpace($TemporaryProfile)) { Get-TemporaryProfile $snapshot } else { $TemporaryProfile }
        $desired = if ([string]::IsNullOrWhiteSpace($Desired)) {
            Get-DesiredProfile ([string]$script:Config.Selection) $snapshot $script:Config $script:AutomationState $temporaryProfile
        }
        else { $Desired }
        $batteryText = if ($snapshot.BatteryPercent -ge 0) { " / $($snapshot.BatteryPercent)%" } else { '' }
        $runtimeEstimateText = if ($null -ne $snapshot.BatteryEstimatedHours) { " / est. $($snapshot.BatteryEstimatedHours)h $($snapshot.BatteryEstimateConfidence)" } else { '' }
        $batteryRateText = if ($null -ne $snapshot.BatteryDischargeW -and [double]$snapshot.BatteryDischargeW -gt 0) { " / discharge $($snapshot.BatteryDischargeW)W (avg $($snapshot.BatteryDischargeAverage10mW)W)$runtimeEstimateText" }
            elseif ($null -ne $snapshot.BatteryChargeW -and [double]$snapshot.BatteryChargeW -gt 0) { " / charging $($snapshot.BatteryChargeW)W" }
            else { '' }
        $sourceText = Get-SupplyDisplayName $snapshot.SupplyType
        if ($snapshot.SupplyConfirmationPending) {
            $verificationState = if ([string]$snapshot.SupplyType -eq 'HighPowerAC') {
                'holding verified high-power AC'
            }
            else { 'AC not yet classified' }
            $sourceText += " (verifying PD; $verificationState)"
        }
        $limitText = if ($null -ne $snapshot.AdapterLimitW) { " / GPU limit $($snapshot.AdapterLimitW)W" } else { '' }
        $quietCpuText = if ($desired -eq 'Quiet') { " / CPU max $(Resolve-QuietCpuMaxPercent $script:Config $snapshot)%" } else { '' }
        $hyperCpuText = if ($desired -eq 'Hyper') { " / Hyper $((Resolve-HyperCpuPolicy $script:Config).Name)" } else { '' }
        $activeName = if (-not [string]::IsNullOrWhiteSpace($ActiveName)) { $ActiveName }
            elseif (-not [string]::IsNullOrWhiteSpace([string]$script:LastVerifiedActiveProfile)) { [string]$script:LastVerifiedActiveProfile }
            else { 'Unknown' }
        $manualEco = [string]$script:Config.Selection -eq 'Quiet' -and $desired -eq 'Quiet'
        $selectionDisplayName = if ([string]$script:Config.Selection -eq 'Quiet') { 'Eco' } else { [string]$script:Config.Selection }
        $desiredDisplayName = if ($desired -eq 'Quiet') { 'Eco' } else { $desired }
        $activeDisplayName = if ($activeName -eq 'Quiet') { 'Eco' } else { $activeName }
        $healthText = if ($script:RuntimeHealth -eq 'Healthy') { 'Healthy' } elseif ($script:RuntimeHealth -eq 'Starting') { 'Starting' } else { 'Recovering' }
        $script:StatusMenu.Text = "$sourceText$batteryText - $desiredDisplayName - $healthText"
        $script:TrayIcon.Text = "OpenSynapse - $desiredDisplayName - $healthText"
        $script:AutoMenu.Checked = ([string]$script:Config.Selection -eq 'Auto')
        $script:HyperMenu.Checked = ([string]$script:Config.Selection -eq 'Hyper')
        $script:BalanceMenu.Checked = ([string]$script:Config.Selection -eq 'Balance')
        $script:QuietMenu.Checked = ([string]$script:Config.Selection -eq 'Quiet')
        $script:ExperimentMenu.Checked = ([string]$script:Config.Selection -eq 'Experiment')
        $script:TemporaryMenu.Enabled = ([string]$script:Config.Selection -ne 'Experiment')
        if (-not $script:Form.Visible -and -not $captureUi) { return }
        $script:PowerLabel.Text = "Power: $sourceText$batteryText$batteryRateText$limitText$quietCpuText$hyperCpuText"
        $temporaryDisplayName = if ($temporaryProfile -eq 'Quiet') { 'Eco' } else { $temporaryProfile }
        $temporaryText = if ($temporaryDisplayName) { "    Temporary: $temporaryDisplayName" } else { '' }
        $script:ModeLabel.Text = "Selection: $selectionDisplayName$temporaryText    Target: $desiredDisplayName    Active: $activeDisplayName    Health: $healthText"
        $script:StatusProfileValue.Text = $desiredDisplayName
        $script:StatusCpuValue.Text = if ([double]$script:AutomationState.LastCpuPercent -ge 0) { "$($script:AutomationState.LastCpuPercent)%" } else { 'Sampling' }
        $script:StatusGpuValue.Text = if ([double]$script:AutomationState.LastGpuPercent -ge 0) { "$($script:AutomationState.LastGpuPercent)%" } else { 'Sampling' }
        $script:StatusBatteryValue.Text = if ($snapshot.BatteryPercent -ge 0) { "$($snapshot.BatteryPercent)%" } else { 'Unavailable' }
        $script:StatusRateValue.Text = if ($null -ne $snapshot.BatteryDischargeW -and [double]$snapshot.BatteryDischargeW -gt 0) {
            "-$($snapshot.BatteryDischargeW) W"
        }
        elseif ($null -ne $snapshot.BatteryChargeW -and [double]$snapshot.BatteryChargeW -gt 0) { "+$($snapshot.BatteryChargeW) W" }
        else { '0 W' }
        $script:StatusSupplyValue.Text = $sourceText
        $script:StatusDgpuValue.Text = if ([bool]$script:AutomationState.DgpuLeakDetected) {
            "Active ($($script:AutomationState.DgpuActivityConfidence))"
        } else { 'No leak' }
        $script:StatusDgpuValue.ForeColor = if ([bool]$script:AutomationState.DgpuLeakDetected) {
            [Drawing.Color]::FromArgb(255, 180, 65)
        } else { $script:TextLight }
        $script:StatusHealthValue.Text = $healthText
        $hardwareStatus = Get-HardwareTelemetrySnapshot $snapshot
        $script:StatusThermalValue.Text = if ($null -ne $hardwareStatus.PSObject.Properties['MaximumTemperatureC'] -and [double]$hardwareStatus.MaximumTemperatureC -gt 0) {
            "$($hardwareStatus.MaximumTemperatureC) C"
        } else { 'Unavailable' }
        $script:StatusThermalValue.ForeColor = if ($null -ne $hardwareStatus.PSObject.Properties['ThermalThrottlingDetected'] -and [bool]$hardwareStatus.ThermalThrottlingDetected) {
            [Drawing.Color]::FromArgb(255, 180, 65)
        } else { $script:TextLight }
        $script:StatusNpuValue.Text = if ($null -ne $hardwareStatus.PSObject.Properties['NpuAvailable'] -and [bool]$hardwareStatus.NpuAvailable) {
            "$($hardwareStatus.NpuUtilizationPercent)%"
        } else { 'Not exposed' }
        Set-RazerButtonStyle $autoButton ([string]$script:Config.Selection -eq 'Auto')
        Set-RazerButtonStyle $hyperButton ([string]$script:Config.Selection -eq 'Hyper')
        Set-RazerButtonStyle $balanceButton ([string]$script:Config.Selection -eq 'Balance')
        Set-RazerButtonStyle $quietButton ([string]$script:Config.Selection -eq 'Quiet')
        Set-RazerButtonStyle $experimentButton ([string]$script:Config.Selection -eq 'Experiment')
        if ($script:RuntimeHealth -eq 'Recovering') {
            $script:PolicyHintLabel.Text = "Automatic monitoring is recovering after $script:ConsecutiveMonitorFailures failure(s); retry interval $($script:Timer.Interval / 1000)s."
            $script:PolicyHintLabel.ForeColor = [Drawing.Color]::FromArgb(255, 180, 65)
        }
        elseif ([string]$script:Config.Selection -eq 'Hyper' -and $snapshot.SupplyType -ne 'HighPowerAC') {
            $script:PolicyHintLabel.Text = 'Warning: Hyper is manually overriding a battery, PD or unverified adapter; performance may be power-limited.'
            $script:PolicyHintLabel.ForeColor = [Drawing.Color]::FromArgb(255, 180, 65)
        }
        elseif ([string]$script:Config.Selection -eq 'Experiment') {
            $verificationAge = [Math]::Round(((Get-Date) - $script:LastExperimentVerificationAt).TotalSeconds)
            $script:PolicyHintLabel.Text = "Experiment locked: fixed $($script:Config.ExperimentRefreshRate) Hz, ICC/HDR/DRR/scaling/brightness baseline enforced; Auto, temporary overrides and supply switching are paused. Last verification ${verificationAge}s ago."
            $script:PolicyHintLabel.ForeColor = $script:RazerGreen
        }
        elseif ([bool]$script:AutomationState.BatteryHighDrainDetected) {
            $highDrainNames = [string[]]@($script:AutomationState.BatteryHighDrainProcesses | ForEach-Object { "$($_.ProcessName) $($_.CpuPercentOneCore)%" })
            $script:PolicyHintLabel.Text = "Battery usage warning: sustained CPU from $($highDrainNames -join ', ') while discharging at $($script:AutomationState.BatteryHighDrainDischargeW) W. OpenSynapse did not stop any process."
            $script:PolicyHintLabel.ForeColor = [Drawing.Color]::FromArgb(255, 180, 65)
        }
        elseif ([string]$script:Config.Selection -eq 'Auto' -and -not [bool]$script:Config.SmartAutomationEnabled) {
            $script:PolicyHintLabel.Text = 'Simple Auto: HighPowerAC uses Hyper; PD, battery and unverified AC use Eco. Telemetry and dGPU diagnosis remain active.'
            $script:PolicyHintLabel.ForeColor = $script:TextMuted
        }
        elseif ([string]$script:Config.Selection -eq 'Auto') {
            $cpuText = if ([double]$script:AutomationState.LastCpuPercent -ge 0) { "$($script:AutomationState.LastCpuPercent)% CPU" } else { 'CPU sampling' }
            $gpuText = if ([double]$script:AutomationState.LastGpuPercent -ge 0) { "$($script:AutomationState.LastGpuPercent)% GPU" } else { 'GPU sampling' }
            $appText = if ([string]::IsNullOrWhiteSpace([string]$script:AutomationState.ForegroundProcess)) { 'no foreground app' } else { [string]$script:AutomationState.ForegroundProcess }
            $fullscreenText = if ([bool]$script:AutomationState.ForegroundFullscreen) { ' / fullscreen' } else { '' }
            $leakText = if ([bool]$script:AutomationState.DgpuLeakDetected) { " / dGPU activity suspected ($($script:AutomationState.DgpuActivityConfidence))" } else { '' }
            $script:PolicyHintLabel.Text = "Smart Auto: $cpuText / $gpuText / $appText$fullscreenText$leakText / $($script:AutomationState.LastReason)"
            $script:PolicyHintLabel.ForeColor = if ([bool]$script:AutomationState.DgpuLeakDetected) { [Drawing.Color]::FromArgb(255, 180, 65) } else { $script:TextMuted }
        }
        elseif ($desired -eq 'Hyper') {
            $hyperPolicy = Resolve-HyperCpuPolicy $script:Config
            $script:PolicyHintLabel.Text = if ($hyperPolicy.Name -eq 'Latency') {
                'Hyper Latency: 100% CPU minimum and all core classes unparked; fastest response, with higher idle heat and fan use.'
            } else {
                'Hyper Sustained: all CPU classes use EPP 0 and 100% ceiling; idle clocks may fall to preserve thermal headroom.'
            }
            $script:PolicyHintLabel.ForeColor = $script:TextMuted
        }
        elseif ($desired -eq 'Quiet') {
            $quietModeName = if ([string]$script:Config.Selection -eq 'Quiet') { 'Eco: internal 60 Hz, HDR off' } else { 'Eco profile' }
            $script:PolicyHintLabel.Text = "$quietModeName; adaptive CPU $($script:Config.QuietCpuMaxHighBattery)% at >=$($script:Config.QuietCpuMediumThreshold)%, $($script:Config.QuietCpuMaxMediumBattery)% at $($script:Config.QuietCpuLowThreshold)-$([int]$script:Config.QuietCpuMediumThreshold - 1)%, $($script:Config.QuietCpuMaxLowBattery)% below $($script:Config.QuietCpuLowThreshold)%; Boost stays disabled."
            $script:PolicyHintLabel.ForeColor = $script:TextMuted
        }
        else {
            $script:PolicyHintLabel.Text = 'Balance keeps full CPU range with efficient boost, 120 Hz by profile and conservative power behavior.'
            $script:PolicyHintLabel.ForeColor = $script:TextMuted
        }
    }

    function Update-DetailBox {
        $script:DetailBox.Text = Get-DisplayStatusText $script:Config
    }

    function Update-RazerMouseUi {
        $devices = @(Get-RazerMouseDevices)
        if ($devices.Count -eq 0) {
            $script:RazerMouseStatusLabel.Text = 'No supported DeathAdder V3 Pro detected. Connect the wired mouse or wireless receiver, then refresh.'
            $script:RazerMouseStatusLabel.ForeColor = [Drawing.Color]::FromArgb(255, 180, 65)
            return
        }
        $mouse = $devices | Select-Object -First 1
        $dpiText = if ($null -ne $mouse.DpiX) { "$($mouse.DpiX)x$($mouse.DpiY) DPI" } else { 'DPI unavailable' }
        $pollingText = if ($null -ne $mouse.PollingRate) { "$($mouse.PollingRate) Hz" } else { 'polling unavailable' }
        $batteryText = if ($null -ne $mouse.BatteryPercent) { "$($mouse.BatteryPercent)% battery" } else { 'battery unavailable' }
        $script:RazerMouseStatusLabel.Text = "$($mouse.Name) / $($mouse.Connection) / $dpiText / $pollingText / $batteryText"
        $script:RazerMouseStatusLabel.ForeColor = $script:TextLight
        if ($null -ne $mouse.DpiX) { $script:RazerDpiBox.Text = [string]$mouse.DpiX }
        if ($null -ne $mouse.PollingRate -and $mouse.PollingRate -in @(125, 500, 1000)) {
            $script:RazerPollingBox.SelectedItem = [int]$mouse.PollingRate
        }
    }

    function Show-ControlPanel {
        Remove-Item -LiteralPath $script:ShowRequestPath -Force -ErrorAction SilentlyContinue
        Show-NavigationPage 'Dashboard'
        $script:Form.Show()
        $script:Form.WindowState = 'Normal'
        $script:Form.Activate()
        Update-ApplicationUi
        Update-RazerMouseUi
        Update-DetailBox
    }

    function Apply-CurrentSelection {
        param(
            [switch]$Full,
            [switch]$Notify,
            [switch]$ApplyVisualPolicy,
            [switch]$ApplyRefreshPolicy,
            [switch]$RepairScaling,
            [AllowNull()][object]$Snapshot = $null,
            [switch]$AutomationAlreadyUpdated,
            [switch]$ThrowOnError,
            [switch]$SilentError
        )
        if ($script:ApplyInProgress) {
            Write-AppLog 'Apply request skipped because another profile operation is already in progress.'
            return $false
        }
        $script:ApplyInProgress = $true
        try {
            if ($Full -and -not [bool]$script:Config.SeamlessModeSwitching) {
                $ApplyVisualPolicy = $true
                $RepairScaling = $true
            }
            $snapshot = if ($null -eq $Snapshot) { Get-PowerSnapshot } else { $Snapshot }
            $null = Update-GpuTelemetryCadence $script:Config $snapshot ([string]$script:Config.Selection)
            if ([string]$script:Config.Selection -eq 'Balance' -and
                -not (Test-BalanceEligible $snapshot ([int]$script:Config.BalanceBatteryThreshold))) {
                $script:Config.Selection = 'Quiet'
                Save-AppConfig $script:Config
                Write-AppLog "Balance latched to Quiet below $($script:Config.BalanceBatteryThreshold)% (battery=$($snapshot.BatteryPercent)%)."
                $Notify = $true
            }
            if ([string]$script:Config.Selection -eq 'Auto' -and [bool]$script:Config.SmartAutomationEnabled -and -not $AutomationAlreadyUpdated) {
                $null = Update-SmartAutomationState $script:Config $snapshot $script:AutomationState
            }
            $temporaryProfile = Get-TemporaryProfile $snapshot
            $desired = Get-DesiredProfile ([string]$script:Config.Selection) $snapshot $script:Config $script:AutomationState $temporaryProfile
            $result = Set-ActiveProfile $desired $script:State $script:Config -Full:$Full -ApplyVisualPolicy:$ApplyVisualPolicy -ApplyRefreshPolicy:$ApplyRefreshPolicy -RepairScaling:$RepairScaling -Snapshot $snapshot
            $script:LastPlanVerification = Get-Date
            $script:LastVerifiedActiveProfile = $desired
            $script:LastPolicyVerification = [pscustomobject][ordered]@{
                Profile = $desired
                PlanVerified = [bool]$result.PlanVerified
                RefreshPolicy = [string]$result.RefreshPolicy
                EffectiveRefreshPolicy = [string]$result.EffectiveRefreshPolicy
                RefreshVerified = $result.RefreshVerified
                RefreshWarning = [string]$result.RefreshWarning
                VerifiedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
            }
            $script:LastPowerSource = $snapshot.Source
            $script:LastSupplyType = $snapshot.SupplyType
            $script:LastDesiredProfile = $desired
            if ($desired -eq 'Quiet') { $script:LastMaintenance = Get-Date }
            if ($Full) {
                $script:IgnoreDisplayEventsUntil = (Get-Date).AddSeconds(5)
                $script:LastDisplayVersion = [OpenSynapseNative.DisplayChangeSignal]::Version
            }
            Update-ApplicationUi -Snapshot $snapshot -Desired $desired -TemporaryProfile $temporaryProfile -ActiveName $script:LastVerifiedActiveProfile
            if ($script:Form.Visible) { Update-DetailBox }
            if ($Notify) {
                $appliedDisplayName = if ($desired -eq 'Quiet') { 'Eco' } else { $desired }
                if (-not [string]::IsNullOrWhiteSpace([string]$result.RefreshWarning)) {
                    $script:TrayIcon.BalloonTipTitle = 'OpenSynapse display warning'
                    $script:TrayIcon.BalloonTipText = "Applied $appliedDisplayName, but refresh policy failed: $($result.RefreshWarning)"
                    $script:TrayIcon.ShowBalloonTip(4500)
                }
                else {
                    $script:TrayIcon.BalloonTipTitle = 'OpenSynapse'
                    $script:TrayIcon.BalloonTipText = "Applied $appliedDisplayName; plan verified=$($result.PlanVerified)."
                    $script:TrayIcon.ShowBalloonTip(2200)
                }
            }
            return $true
        }
        catch {
            Write-AppLog "Apply failed: $($_.Exception.Message)"
            $script:LastRuntimeError = [string]$_.Exception.Message
            if (-not $SilentError -and ((Get-Date) - $script:LastApplyErrorNotification).TotalSeconds -ge 30) {
                $script:LastApplyErrorNotification = Get-Date
                $script:TrayIcon.BalloonTipTitle = 'OpenSynapse error'
                $script:TrayIcon.BalloonTipText = $_.Exception.Message
                $script:TrayIcon.ShowBalloonTip(3500)
            }
            if ($ThrowOnError) { throw }
            return $false
        }
        finally { $script:ApplyInProgress = $false }
    }

    function Set-SelectionFromUi([ValidateSet('Auto', 'Hyper', 'Balance', 'Quiet', 'Experiment')][string]$Selection) {
        $snapshot = Get-PowerSnapshot -UseCachedAdapter
        $previousSelection = [string]$script:Config.Selection
        if ($Selection -eq 'Hyper' -and $snapshot.SupplyType -ne 'HighPowerAC') {
            $answer = [Windows.Forms.MessageBox]::Show(
                'The current source is battery, USB-C PD or unverified AC. Hyper can be selected, but CPU/GPU performance will remain limited by the available input power. Continue?',
                'OpenSynapse manual Hyper override',
                [Windows.Forms.MessageBoxButtons]::YesNo,
                [Windows.Forms.MessageBoxIcon]::Warning)
            if ($answer -ne [Windows.Forms.DialogResult]::Yes) { return }
        }
        if ($Selection -eq 'Balance') {
            if (-not (Test-BalanceEligible $snapshot ([int]$script:Config.BalanceBatteryThreshold))) {
                $script:TrayIcon.BalloonTipTitle = 'Balance unavailable'
                $script:TrayIcon.BalloonTipText = "Balance requires at least $($script:Config.BalanceBatteryThreshold)% battery."
                $script:TrayIcon.ShowBalloonTip(3000)
                return
            }
        }
        Clear-TemporaryOverride 'replaced by a persistent selection'
        $newExperimentSession = $false
        $experimentClosed = $false
        try {
            if ($previousSelection -eq 'Experiment' -and $Selection -ne 'Experiment') {
                $restore = Stop-ExperimentSession $script:Config $script:State $snapshot $script:AutomationState
                if (-not [bool]$restore.Verified) {
                    throw "Experiment display state could not be restored: $($restore.Differences -join '; ')"
                }
                $experimentClosed = $true
            }
            if ($Selection -eq 'Experiment' -and $previousSelection -ne 'Experiment') {
                $newExperimentSession = Initialize-ExperimentSession $script:State
            }
            $script:Config.Selection = $Selection
            Save-AppConfig $script:Config
            $visualTransition = $Selection -in @('Quiet', 'Experiment') -or $previousSelection -in @('Quiet', 'Experiment')
            $null = Apply-CurrentSelection -Full -ApplyVisualPolicy:$visualTransition -ApplyRefreshPolicy:$visualTransition -Notify -ThrowOnError
            if ($Selection -eq 'Experiment') {
                Complete-ExperimentSessionStart $script:Config $script:State $snapshot $script:AutomationState -NewSession:$newExperimentSession
            }
        }
        catch {
            $selectionError = $_.Exception.Message
            Write-AppLog "Selection change to $Selection failed: $selectionError"
            if ($Selection -eq 'Experiment' -and $null -ne $script:State.ExperimentSession) {
                try {
                    $null = Restore-DisplayStateSnapshot $script:State.ExperimentSession.OriginalDisplayState
                    $script:State.ExperimentSession = $null
                    Save-AppState $script:State
                }
                catch { Write-AppLog "Experiment entry rollback failed: $($_.Exception.Message)" }
            }
            # Once a prior Experiment session has been successfully closed, its
            # lock cannot be represented by merely restoring the old selection
            # string. Fall back to Auto and apply it; all other failures restore
            # the prior selection and its verified power/display policy.
            $rollbackSelection = if ($experimentClosed) { 'Auto' } else { $previousSelection }
            $script:Config.Selection = $rollbackSelection
            Save-AppConfig $script:Config
            try {
                $null = Apply-CurrentSelection -Full -ApplyVisualPolicy -ApplyRefreshPolicy -Snapshot $snapshot -ThrowOnError -SilentError
            }
            catch { Write-AppLog "Selection rollback to $rollbackSelection also failed: $($_.Exception.Message)" }
            [Windows.Forms.MessageBox]::Show($selectionError, 'OpenSynapse Experiment', 'OK', 'Error') | Out-Null
        }
    }

    function Save-OptionControls {
        if ($script:SuppressOptionSave) { return }
        $script:Config.SmartAutomationEnabled = $script:SmartAutomationCheck.Checked
        $script:Config.CloseHighDrainAppsInQuiet = $script:CloseAppsCheck.Checked
        $script:Config.BatteryHighDrainAlertsEnabled = $script:BatteryHighDrainCheck.Checked
        $script:Config.ManageAsusServices = $script:ServicesCheck.Checked
        $script:Config.ManageWakeDevices = $script:WakeCheck.Checked
        if ($script:HyperPolicyBox.SelectedIndex -ge 0) {
            $script:Config.HyperCpuPolicy = [string]$script:HyperPolicyValues[$script:HyperPolicyBox.SelectedIndex]
        }
        if ($script:RefreshPolicyBox.SelectedIndex -ge 0) {
            $script:Config.RefreshPolicy = [string]$script:RefreshPolicyValues[$script:RefreshPolicyBox.SelectedIndex]
        }
        $script:Config.ManageRefreshRate = ([string]$script:Config.RefreshPolicy -ne 'Unmanaged')
        $script:Config.ManageAdvancedColor = $script:ColorCheck.Checked
        $script:Config.ManageBrightness = $script:BrightnessCheck.Checked
        $script:Config.DisplayScalingEnabled = $script:ScalingCheck.Checked
        if ($null -ne $script:InternalScaleBox.SelectedItem) { $script:Config.InternalScale = [int]$script:InternalScaleBox.SelectedItem }
        if ($null -ne $script:ExternalScaleBox.SelectedItem) { $script:Config.ExternalScale = [int]$script:ExternalScaleBox.SelectedItem }
        if ($null -ne $script:BrightnessBox.SelectedItem) { $script:Config.QuietBrightness = [int]$script:BrightnessBox.SelectedItem }
        if ($null -ne $script:BalanceBrightnessBox.SelectedItem) { $script:Config.BalanceBrightness = [int]$script:BalanceBrightnessBox.SelectedItem }
        Save-AppConfig $script:Config

        if (-not $script:ServicesCheck.Checked) { Restore-QuietServices $script:State }
        if (-not $script:WakeCheck.Checked) { Restore-WakeDevices $script:State }
        if ([string]$script:Config.RefreshPolicy -eq 'Unmanaged') {
            try { $null = [OpenSynapseNative.DynamicRefreshManager]::Disable() } catch { }
            try { [OpenSynapseNative.DisplayModeManager]::RestoreRegistryModes() } catch { }
        }
        if (-not $script:ColorCheck.Checked -and @($script:State.AdvancedColorStates).Count -gt 0) {
            foreach ($item in @($script:State.AdvancedColorStates)) {
                try {
                    if ($null -ne $item.PSObject.Properties['Key'] -and -not [string]::IsNullOrWhiteSpace([string]$item.Key)) {
                        $null = [OpenSynapseNative.AdvancedColorManager]::SetEnabled([string]$item.Key, [bool]$item.Enabled)
                    }
                } catch { }
            }
            $script:State.AdvancedColorStates = @()
            Save-AppState $script:State
        }
        if (-not $script:BrightnessCheck.Checked -and $null -ne $script:State.CapturedBrightness) {
            $null = Set-InternalBrightness ([int]$script:State.CapturedBrightness)
            $script:State.CapturedBrightness = $null
            $script:LastAppliedBrightnessTarget = $null
            Save-AppState $script:State
        }
        elseif (-not $script:BrightnessCheck.Checked) { $script:LastAppliedBrightnessTarget = $null }
    }

    $autoButton.Add_Click({ Set-SelectionFromUi Auto })
    $hyperButton.Add_Click({ Set-SelectionFromUi Hyper })
    $balanceButton.Add_Click({ Set-SelectionFromUi Balance })
    $quietButton.Add_Click({ Set-SelectionFromUi Quiet })
    $experimentButton.Add_Click({ Set-SelectionFromUi Experiment })
    $script:AutoMenu.Add_Click({ Set-SelectionFromUi Auto })
    $script:HyperMenu.Add_Click({ Set-SelectionFromUi Hyper })
    $script:BalanceMenu.Add_Click({ Set-SelectionFromUi Balance })
    $script:QuietMenu.Add_Click({ Set-SelectionFromUi Quiet })
    $script:ExperimentMenu.Add_Click({ Set-SelectionFromUi Experiment })
    $script:TemporaryHyperMenu.Add_Click({ Set-TemporaryProfile Hyper 30 $false })
    $script:TemporaryBalanceMenu.Add_Click({ Set-TemporaryProfile Balance 30 $false })
    $script:TemporaryQuietMenu.Add_Click({ Set-TemporaryProfile Quiet 30 $false })
    $script:TemporaryCancelMenu.Add_Click({ Clear-TemporaryOverride; Apply-CurrentSelection -Full -Notify })
    $openMenu.Add_Click({ Show-ControlPanel })
    $script:TrayIcon.Add_DoubleClick({ Show-ControlPanel })
    $refreshStatusButton.Add_Click({ Update-ApplicationUi; Update-DetailBox })
    $applyDisplayButton.Add_Click({ Save-OptionControls; Apply-CurrentSelection -Full -ApplyVisualPolicy -RepairScaling -Notify })
    $temporaryButton.Add_Click({ Show-TemporaryModeDialog })
    $rulesButton.Add_Click({ Show-ApplicationRulesEditor; Update-ApplicationUi; Update-DetailBox })
    $exportButton.Add_Click({
        $dialog = New-Object Windows.Forms.SaveFileDialog
        $dialog.Title = 'Export OpenSynapse diagnostics'
        $dialog.Filter = 'ZIP archive (*.zip)|*.zip'
        $dialog.FileName = "OpenSynapse-diagnostics-$((Get-Date).ToString('yyyyMMdd-HHmmss')).zip"
        if ($dialog.ShowDialog($script:Form) -eq [Windows.Forms.DialogResult]::OK) {
            try {
                $snapshot = Get-PowerSnapshot -UseCachedAdapter
                $path = Export-OpenSynapseDiagnostics $dialog.FileName $script:Config $script:State $snapshot $script:AutomationState
                [Windows.Forms.MessageBox]::Show("Diagnostics exported to:`r`n$path", 'OpenSynapse', 'OK', 'Information') | Out-Null
            }
            catch { [Windows.Forms.MessageBox]::Show("Diagnostic export failed:`r`n$($_.Exception.Message)", 'OpenSynapse', 'OK', 'Error') | Out-Null }
        }
        $dialog.Dispose()
    })
    $experimentReportButton.Add_Click({
        $dialog = New-Object Windows.Forms.SaveFileDialog
        $dialog.Title = 'Export OpenSynapse experiment environment report'
        $dialog.Filter = 'JSON report (*.json)|*.json'
        $dialog.FileName = "OpenSynapse-experiment-$((Get-Date).ToString('yyyyMMdd-HHmmss')).json"
        if ($dialog.ShowDialog($script:Form) -eq [Windows.Forms.DialogResult]::OK) {
            try {
                $snapshot = Get-PowerSnapshot -UseCachedAdapter
                $report = Export-ExperimentEnvironmentReport $script:Config $script:State $snapshot $script:AutomationState Manual $dialog.FileName
                [Windows.Forms.MessageBox]::Show("Experiment report exported to:`r`n$($report.JsonPath)`r`n$($report.HtmlPath)", 'OpenSynapse', 'OK', 'Information') | Out-Null
            }
            catch { [Windows.Forms.MessageBox]::Show("Experiment report failed:`r`n$($_.Exception.Message)", 'OpenSynapse', 'OK', 'Error') | Out-Null }
        }
        $dialog.Dispose()
    })

    foreach ($control in @($script:CloseAppsCheck, $script:ServicesCheck, $script:WakeCheck, $script:BatteryHighDrainCheck,
        $script:ColorCheck, $script:BrightnessCheck, $script:ScalingCheck)) {
        $control.Add_CheckedChanged({ Save-OptionControls })
    }
    $script:SmartAutomationCheck.Add_CheckedChanged({
        Save-OptionControls
        try { Apply-CurrentSelection -Full -Notify }
        catch { Write-AppLog "Smart automation toggle failed: $($_.Exception.Message)" }
    })
    $script:InternalScaleBox.Add_SelectedIndexChanged({ Save-OptionControls })
    $script:ExternalScaleBox.Add_SelectedIndexChanged({ Save-OptionControls })
    $script:BrightnessBox.Add_SelectedIndexChanged({ $script:LastAppliedBrightnessTarget = $null; Save-OptionControls })
    $script:BalanceBrightnessBox.Add_SelectedIndexChanged({ Save-OptionControls })
    $script:RefreshPolicyBox.Add_SelectedIndexChanged({ Save-OptionControls })
    $script:HyperPolicyBox.Add_SelectedIndexChanged({
        Save-OptionControls
        $script:LastAppliedHyperCpuPolicy = $null
        try {
            $snapshot = Get-PowerSnapshot -UseCachedAdapter
            if ((Get-DesiredProfile ([string]$script:Config.Selection) $snapshot $script:Config $script:AutomationState (Get-TemporaryProfile $snapshot)) -eq 'Hyper') {
                Apply-CurrentSelection -Notify
            }
        }
        catch { Write-AppLog "Hyper CPU tuning apply failed: $($_.Exception.Message)" }
    })

    Update-RazerMouseUi
    Apply-DarkControlTheme $script:Form
    try { $null = [OpenSynapseNative.WindowTheme]::ApplyDarkControl($menu.Handle) } catch { }

    $synapseButton.Add_Click({
        $shortcut = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Razer\Razer Synapse.lnk'
        $executable = Join-Path $env:ProgramFiles 'Razer\RazerAppEngine\RazerAppEngine.exe'
        if (Test-Path -LiteralPath $shortcut) { Start-Process explorer.exe -ArgumentList ('"{0}"' -f $shortcut) }
        elseif (Test-Path -LiteralPath $executable) { Start-Process explorer.exe -ArgumentList ('"{0}"' -f $executable) }
        else { [Windows.Forms.MessageBox]::Show('Razer Synapse was not found.') | Out-Null }
    })
    $nvidiaButton.Add_Click({ Start-Process (Join-Path $env:SystemRoot 'System32\control.exe') -ArgumentList '/name NVIDIA.Display' })
    $displayButton.Add_Click({ Start-Process 'ms-settings:display' })
    $razerRefreshButton.Add_Click({ Update-RazerMouseUi; Update-DetailBox })
    $razerApplyDpiButton.Add_Click({
        $dpi = 0
        if (-not [int]::TryParse($script:RazerDpiBox.Text.Trim(), [ref]$dpi) -or $dpi -lt 100 -or $dpi -gt 30000) {
            [Windows.Forms.MessageBox]::Show('DPI must be a whole number from 100 to 30000.', 'OpenSynapse mouse', 'OK', 'Warning') | Out-Null
            return
        }
        try {
            Set-RazerMouseDpi $dpi
            Update-RazerMouseUi
            Update-DetailBox
        }
        catch {
            Write-AppLog "Razer DPI apply failed: $($_.Exception.Message)"
            [Windows.Forms.MessageBox]::Show("Could not apply DPI:`r`n$($_.Exception.Message)", 'OpenSynapse mouse', 'OK', 'Error') | Out-Null
        }
    })
    $razerApplyPollingButton.Add_Click({
        if ($null -eq $script:RazerPollingBox.SelectedItem) { return }
        try {
            Set-RazerMousePollingRate ([int]$script:RazerPollingBox.SelectedItem)
            Update-RazerMouseUi
            Update-DetailBox
        }
        catch {
            Write-AppLog "Razer polling apply failed: $($_.Exception.Message)"
            [Windows.Forms.MessageBox]::Show("Could not apply polling rate:`r`n$($_.Exception.Message)", 'OpenSynapse mouse', 'OK', 'Error') | Out-Null
        }
    })

    $openLogAction = {
        if (-not (Test-Path -LiteralPath $script:LogPath)) { [IO.File]::WriteAllText($script:LogPath, '') }
        Start-Process notepad.exe -ArgumentList ('"{0}"' -f $script:LogPath)
    }
    $openLogButton.Add_Click($openLogAction)
    $logMenu.Add_Click($openLogAction)

    $exitAction = {
        try {
            $exitSnapshot = Get-PowerSnapshot -UseCachedAdapter
            if ($null -ne $script:State.ExperimentSession) {
                $null = Stop-ExperimentSession $script:Config $script:State $exitSnapshot $script:AutomationState
            }
            Restore-WakeDevices $script:State
            Restore-QuietServices $script:State
            Restore-DisplayPolicy $script:State
            $restoreGuid = [string]$script:State.OriginalPlanGuid
            if (-not (Test-PlanExists $restoreGuid)) { $restoreGuid = $script:Guids.Balanced }
            Invoke-PowerCfg @('/setactive', $restoreGuid) -AllowFailure | Out-Null
            Write-AppLog "Exit restored original state and plan $restoreGuid."
        }
        catch { Write-AppLog "Exit restore failed: $($_.Exception.Message)" }
        $script:AllowFormClose = $true
        $script:Timer.Stop()
        try { [OpenSynapseNative.GpuTelemetry]::Stop() } catch { }
        $script:TrayIcon.Visible = $false
        $script:Form.Close()
        [Windows.Forms.Application]::Exit()
    }
    $exitMenu.Add_Click($exitAction)
    $restoreButton.Add_Click($exitAction)

    $script:Form.Add_FormClosing({
        param($sender, $eventArgs)
        if (-not $script:AllowFormClose) {
            $eventArgs.Cancel = $true
            $script:Form.Hide()
        }
    })
    $script:Form.Add_Resize({ if ($script:Form.WindowState -eq 'Minimized') { $script:Form.Hide() } })

    function Update-RuntimeHeartbeat {
        param([switch]$Force)
        if ($captureUi) { return }
        $now = Get-Date
        if (-not $Force -and ($now - $script:LastRuntimeHeartbeat).TotalSeconds -lt 60) { return }
        $script:RuntimeRecord.Health = [string]$script:RuntimeHealth
        $script:RuntimeRecord.ConsecutiveFailures = [int]$script:ConsecutiveMonitorFailures
        $script:RuntimeRecord.LastHeartbeatUtc = $now.ToUniversalTime().ToString('o')
        $script:RuntimeRecord.LastSuccessfulTickUtc = if ($script:LastSuccessfulMonitorTick -eq [DateTime]::MinValue) {
            ''
        } else { $script:LastSuccessfulMonitorTick.ToUniversalTime().ToString('o') }
        $script:RuntimeRecord.LastError = [string]$script:LastRuntimeError
        Write-JsonFile $script:RuntimePath $script:RuntimeRecord
        $script:LastRuntimeHeartbeat = $now
    }

    function Set-MonitorCycleHealthy {
        $previousFailures = [int]$script:ConsecutiveMonitorFailures
        if ($previousFailures -gt 0) {
            Write-AppLog "Automatic monitoring recovered after $previousFailures consecutive failure(s)."
            if ($previousFailures -ge 3) {
                $script:TrayIcon.BalloonTipTitle = 'OpenSynapse recovered'
                $script:TrayIcon.BalloonTipText = 'Automatic power monitoring is healthy again.'
                $script:TrayIcon.ShowBalloonTip(2500)
            }
        }
        $script:ConsecutiveMonitorFailures = 0
        $script:RuntimeHealth = 'Healthy'
        $script:LastRuntimeError = ''
        $script:LastSuccessfulMonitorTick = Get-Date
        $nextInterval = Resolve-MonitorIntervalMilliseconds $script:LastMonitorSnapshot $script:AutomationState ([string]$script:Config.Selection)
        if ([int]$script:Timer.Interval -ne $nextInterval) {
            $script:Timer.Interval = $nextInterval
            Write-AppLog "Monitor cadence changed to $($nextInterval / 1000)s for source=$($script:LastMonitorSnapshot.Source) selection=$($script:Config.Selection)."
        }
        try { Update-RuntimeHeartbeat } catch { Write-AppLog "Runtime heartbeat failed: $($_.Exception.Message)" }
    }

    function Register-MonitorCycleFailure {
        param([Parameter(Mandatory = $true)][Management.Automation.ErrorRecord]$Failure)
        $script:ConsecutiveMonitorFailures++
        $script:RuntimeHealth = 'Recovering'
        $script:LastRuntimeError = [string]$Failure.Exception.Message
        $power = [Math]::Min(3, [int]$script:ConsecutiveMonitorFailures)
        $script:Timer.Interval = [Math]::Min($script:MonitorMaximumIntervalMs, $script:MonitorBaseIntervalMs * [Math]::Pow(2, $power))
        Write-AppLog "Monitor cycle failed ($script:ConsecutiveMonitorFailures consecutive); retry=$($script:Timer.Interval)ms: $script:LastRuntimeError"
        if ($script:ConsecutiveMonitorFailures -eq 3) {
            $script:CachedSupplyType = $null
            $script:CachedAdapterLimitW = $null
            $script:LastAdapterProbe = [DateTime]::MinValue
            $script:PendingDisplayRepairAt = [DateTime]::MaxValue
            $script:TrayIcon.BalloonTipTitle = 'OpenSynapse is recovering'
            $script:TrayIcon.BalloonTipText = 'Automatic monitoring hit repeated errors. Current mode is being preserved while OpenSynapse retries.'
            $script:TrayIcon.ShowBalloonTip(4000)
        }
        try { Update-RuntimeHeartbeat -Force } catch { Write-AppLog "Failure heartbeat failed: $($_.Exception.Message)" }
        try {
            $script:StatusMenu.Text = "OpenSynapse - recovering ($script:ConsecutiveMonitorFailures)"
            $script:TrayIcon.Text = 'OpenSynapse - Recovering'
            $script:PolicyHintLabel.Text = "Automatic monitoring is recovering; retrying in $($script:Timer.Interval / 1000)s. Current power plan is preserved."
            $script:PolicyHintLabel.ForeColor = [Drawing.Color]::FromArgb(255, 180, 65)
        }
        catch { }
    }

    function Invoke-MonitorCycle {
        if (Test-Path -LiteralPath $script:ShowRequestPath) { Show-ControlPanel }

        $powerEventVersion = [OpenSynapseNative.PowerChangeSignal]::Version
        if ($powerEventVersion -ne $script:LastPowerEventVersion) { $script:LastPowerEventVersion = $powerEventVersion }
        $null = Register-PowerEventObservation ([OpenSynapseNative.PowerChangeSignal]::EventCount)
        $null = Invoke-PendingPowerProbe
        $snapshot = Get-PowerSnapshot -UseCachedAdapter
        $null = Update-GpuTelemetryCadence $script:Config $snapshot ([string]$script:Config.Selection)
        $selectionBeforeSupplyTransition = [string]$script:Config.Selection
        $selectionTransition = @{
            Selection = $selectionBeforeSupplyTransition
            PreviousSupplyType = [string]$script:LastSupplyType
            CurrentSupplyType = [string]$snapshot.SupplyType
        }
        $selectionAfterSupplyTransition = Resolve-SelectionAfterSupplyTransition @selectionTransition
        if ($selectionAfterSupplyTransition -ne [string]$script:Config.Selection) {
            $script:Config.Selection = $selectionAfterSupplyTransition
            $script:TemporaryOverride = $null
            Save-AppConfig $script:Config
            Write-AppLog 'Verified 280W-class adapter connection released the manual Quiet lock and restored Smart Auto.'
        }
        $refreshTransition = @{
            RefreshPolicy = [string]$script:Config.RefreshPolicy
            PreviousPowerSource = [string]$script:LastPowerSource
            CurrentPowerSource = [string]$snapshot.Source
            PreviousSupplyType = [string]$script:LastSupplyType
            CurrentSupplyType = [string]$snapshot.SupplyType
            PreviousSelection = $selectionBeforeSupplyTransition
            CurrentSelection = [string]$script:Config.Selection
        }
        $refreshPolicyAfterPowerTransition = Resolve-RefreshPolicyAfterPowerTransition @refreshTransition
        $refreshPolicyRestoredToAuto = $refreshPolicyAfterPowerTransition -ne [string]$script:Config.RefreshPolicy
        if ($refreshPolicyRestoredToAuto) {
            $script:Config.RefreshPolicy = $refreshPolicyAfterPowerTransition
            $script:Config.ManageRefreshRate = $true
            Save-AppConfig $script:Config
            if ($null -ne $script:RefreshPolicyBox) {
                $script:SuppressOptionSave = $true
                try { $script:RefreshPolicyBox.SelectedIndex = [Array]::IndexOf([object[]]$script:RefreshPolicyValues, 'Auto') }
                finally { $script:SuppressOptionSave = $false }
            }
            Write-AppLog 'External power connection restored the internal refresh policy from a manual fixed mode to Auto.'
        }
        $leakWasDetected = [bool]$script:AutomationState.DgpuLeakDetected
        try {
            if ([string]$script:Config.Selection -eq 'Auto' -and [bool]$script:Config.SmartAutomationEnabled) {
                $null = Update-SmartAutomationState $script:Config $snapshot $script:AutomationState
            }
            else {
                $null = Update-ManualTelemetryState $script:Config $snapshot $script:AutomationState ([string]$script:Config.Selection)
            }
            if (-not $leakWasDetected -and [bool]$script:AutomationState.DgpuLeakDetected) {
                $consumerNames = [string[]]@($script:AutomationState.DgpuConsumers | ForEach-Object { [string]$_.ProcessName } | Select-Object -Unique)
                $script:TrayIcon.BalloonTipTitle = 'OpenSynapse dGPU activity'
                $script:TrayIcon.BalloonTipText = "Sustained dGPU activity is suspected ($($script:AutomationState.DgpuActivityConfidence) confidence). Check: $($consumerNames -join ', ')."
                $script:TrayIcon.ShowBalloonTip(5000)
            }
        }
        catch { Write-AppLog "Smart automation telemetry failed: $($_.Exception.Message)" }
        try {
            $highDrain = Update-BatteryHighDrainState $script:Config $snapshot $script:AutomationState
            if ([bool]$highDrain.ShouldNotify) {
                $processText = [string[]]@($highDrain.Processes | ForEach-Object {
                    $displayName = [string]$_.ProcessName
                    if ($displayName.Length -gt 24) { $displayName = $displayName.Substring(0, 24) }
                    "$displayName $($_.CpuPercentOneCore)%"
                })
                $message = "Sustained CPU while battery discharge is $($highDrain.DischargeW) W: $($processText -join ', ') (one-core scale). Review before closing; nothing was stopped."
                if ($message.Length -gt 240) { $message = $message.Substring(0, 237) + '...' }
                $script:TrayIcon.BalloonTipTitle = 'OpenSynapse battery usage'
                $script:TrayIcon.BalloonTipText = $message
                $script:TrayIcon.ShowBalloonTip(6000)
                Write-AppLog "Battery high-drain process alert: confidence=$($highDrain.Confidence); discharge=$($highDrain.DischargeW)W; processes=$($processText -join ', '); no process was stopped."
            }
        }
        catch { Write-AppLog "Battery high-drain sampling failed: $($_.Exception.Message)" }
        if (-not [string]::IsNullOrWhiteSpace([string]$script:AutomationState.ForegroundProcess) -and
            [string]$script:AutomationState.ForegroundProcess -notin @('powershell', 'pwsh')) {
            $script:LastExternalForegroundProcess = [string]$script:AutomationState.ForegroundProcess
        }
        if ([string]$script:Config.Selection -eq 'Balance' -and
            -not (Test-BalanceEligible $snapshot ([int]$script:Config.BalanceBatteryThreshold))) {
            $script:Config.Selection = 'Quiet'
            Save-AppConfig $script:Config
            Write-AppLog "Balance latched to Quiet below $($script:Config.BalanceBatteryThreshold)% (battery=$($snapshot.BatteryPercent)%)."
        }
        $temporaryProfile = Get-TemporaryProfile $snapshot
        $desired = Get-DesiredProfile ([string]$script:Config.Selection) $snapshot $script:Config $script:AutomationState $temporaryProfile
        $powerChanged = $snapshot.Source -ne $script:LastPowerSource -or $snapshot.SupplyType -ne $script:LastSupplyType
        $profileChanged = $desired -ne $script:LastDesiredProfile
        $expectedGuid = switch ($desired) {
            'Hyper' { [string]$script:State.HyperPlanGuid; break }
            'Balance' { [string]$script:State.BalancePlanGuid; break }
            'Experiment' { [string]$script:State.ExperimentPlanGuid; break }
            default { [string]$script:State.QuietPlanGuid }
        }
        $planOverridden = $false
        $planVerificationDue = ((Get-Date) - $script:LastPlanVerification).TotalSeconds -ge $script:PlanVerificationIntervalSeconds
        if ($powerChanged -or $profileChanged -or $planVerificationDue) {
            try {
                $planOverridden = -not [string]::Equals((Get-ActivePlanGuid), $expectedGuid, [StringComparison]::OrdinalIgnoreCase)
                if (-not $planOverridden) { $script:LastVerifiedActiveProfile = $desired }
                $script:LastPlanVerification = Get-Date
            }
            catch { Write-AppLog "Active plan verification deferred: $($_.Exception.Message)" }
        }

        if ($powerChanged -or $profileChanged) {
            $applyAutomaticRefresh = $powerChanged -and [string]$script:Config.RefreshPolicy -eq 'Auto'
            $ecoReleased = $selectionBeforeSupplyTransition -eq 'Quiet' -and [string]$script:Config.Selection -eq 'Auto'
            $ecoEntered = $selectionBeforeSupplyTransition -ne 'Quiet' -and [string]$script:Config.Selection -eq 'Quiet'
            $applyEcoVisualPolicy = $ecoEntered -or $ecoReleased
            $applyProfileRefresh = $applyAutomaticRefresh -or $applyEcoVisualPolicy
            $null = Apply-CurrentSelection -Full -ApplyVisualPolicy:$applyEcoVisualPolicy -ApplyRefreshPolicy:$applyProfileRefresh -Notify -Snapshot $snapshot -AutomationAlreadyUpdated -ThrowOnError -SilentError
        }
        elseif ($planOverridden) {
            $null = Apply-CurrentSelection -Snapshot $snapshot -AutomationAlreadyUpdated -ThrowOnError -SilentError
        }
        elseif ($desired -eq 'Quiet' -and ((Get-Date) - $script:LastMaintenance).TotalSeconds -ge [int]$script:Config.ProcessMaintenanceSeconds) {
            try {
                $maintenanceResult = Invoke-QuietMaintenance $script:Config $script:State
                Disable-QuietWakeDevices $script:Config $script:State
                $script:LastMaintenance = Get-Date
                if (@($maintenanceResult.CoolingDown).Count -gt 0) {
                    $coolingNames = [string[]]@($maintenanceResult.CoolingDown)
                    $cooldownMinutes = [Math]::Round([int]$script:Config.QuietProcessCooldownSeconds / 60)
                    $script:TrayIcon.BalloonTipTitle = 'OpenSynapse Eco cooling'
                    $script:TrayIcon.BalloonTipText = "$($coolingNames -join ', ') restarted after Eco closed it. Process enforcement is paused for $cooldownMinutes minutes to avoid a restart loop; disable its auto-start to keep it off."
                    $script:TrayIcon.ShowBalloonTip(6000)
                }
            }
            catch { Write-AppLog "Quiet maintenance failed: $($_.Exception.Message)" }
        }
        if ($desired -eq 'Quiet') {
            try { $null = Apply-QuietDynamicCpuPolicy $script:Config $script:State $snapshot }
            catch { Write-AppLog "Adaptive Quiet CPU failed: $($_.Exception.Message)" }
            try { Apply-ManagedBrightness Quiet $script:Config $script:State $snapshot }
            catch { Write-AppLog "Adaptive Quiet brightness failed: $($_.Exception.Message)" }
        }
        elseif ($desired -eq 'Experiment') {
            $null = Test-AndRepairExperimentEnvironment $script:Config $script:State $snapshot $script:AutomationState
        }

        if (((Get-Date) - $script:LastTelemetryRecord).TotalSeconds -ge 30) {
            # Set-ActiveProfile verifies every transition and the monitor checks the
            # active GUID on the same cadence, so the enforced profile is available
            # without spawning an extra powercfg process on battery.
            Write-TelemetryRecord $snapshot $script:AutomationState $desired ([string]$script:Config.Selection) $temporaryProfile $desired
            $script:LastTelemetryRecord = Get-Date
        }

        $displayVersion = [OpenSynapseNative.DisplayChangeSignal]::Version
        if ($displayVersion -ne $script:LastDisplayVersion) {
            $script:LastDisplayVersion = $displayVersion
            if ((Get-Date) -ge $script:IgnoreDisplayEventsUntil) { $script:PendingDisplayRepairAt = (Get-Date).AddSeconds(2) }
        }
        if ((Get-Date) -ge $script:PendingDisplayRepairAt) {
            $script:PendingDisplayRepairAt = [DateTime]::MaxValue
            try {
                if ([string]$script:Config.Selection -eq 'Experiment') {
                    $script:LastExperimentVerificationAt = [DateTime]::MinValue
                    $experimentCheck = Test-AndRepairExperimentEnvironment $script:Config $script:State $snapshot $script:AutomationState
                    if ($null -ne $experimentCheck -and -not [bool]$experimentCheck.Valid) {
                        $script:TrayIcon.BalloonTipTitle = 'Experiment environment changed'
                        $script:TrayIcon.BalloonTipText = 'The display topology or a locked display property changed and could not be fully restored. Review Diagnostics before continuing data collection.'
                        $script:TrayIcon.ShowBalloonTip(6000)
                    }
                }
                else {
                    $null = Apply-CurrentSelection -Full -ApplyVisualPolicy -RepairScaling -Snapshot $snapshot -AutomationAlreadyUpdated -ThrowOnError -SilentError
                }
            }
            catch {
                $script:PendingDisplayRepairAt = (Get-Date).AddSeconds(10)
                throw
            }
        }
        $script:LastMonitorSnapshot = $snapshot
        Update-ApplicationUi -Snapshot $snapshot -Desired $desired -TemporaryProfile $temporaryProfile -ActiveName $script:LastVerifiedActiveProfile
    }

    $script:Timer = New-Object Windows.Forms.Timer
    $script:Timer.Interval = $script:MonitorBaseIntervalMs
    $script:Timer.Add_Tick({
        if ($script:MonitorTickRunning) { return }
        $script:MonitorTickRunning = $true
        try {
            Invoke-MonitorCycle
            Set-MonitorCycleHealthy
        }
        catch { Register-MonitorCycleFailure $_ }
        finally { $script:MonitorTickRunning = $false }
    })

    if ($captureUi) {
        $captureFullPath = [IO.Path]::GetFullPath($CaptureUiPath)
        $captureDirectory = Split-Path -Parent $captureFullPath
        if (-not (Test-Path -LiteralPath $captureDirectory)) { [IO.Directory]::CreateDirectory($captureDirectory) | Out-Null }
        Show-NavigationPage $CaptureUiPage
        Update-ApplicationUi
        Update-DetailBox
        $script:Form.Show()
        $darkFrameApplied = [OpenSynapseNative.WindowTheme]::ApplyDarkFrame($script:Form.Handle)
        Apply-DarkControlTheme $script:Form
        Write-Host "UI dark frame applied=$darkFrameApplied"
        $script:Form.Refresh()
        1..5 | ForEach-Object {
            [Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 120
        }
        $layoutViolations = New-Object 'System.Collections.Generic.List[string]'
        function Test-UiControlBounds([Windows.Forms.Control]$Parent, [string]$Path) {
            foreach ($control in $Parent.Controls) {
                if (-not $control.Visible) { continue }
                $controlPath = "$Path/$($control.GetType().Name)"
                if ($control.Left -lt 0 -or $control.Top -lt 0 -or
                    $control.Right -gt $Parent.ClientSize.Width -or $control.Bottom -gt $Parent.ClientSize.Height) {
                    $layoutViolations.Add("$controlPath bounds=$($control.Bounds) parent=$($Parent.ClientSize)")
                }
                if ($control.HasChildren) { Test-UiControlBounds $control $controlPath }
            }
        }
        foreach ($screen in [Windows.Forms.Screen]::AllScreens) {
            $workArea = $screen.WorkingArea
            $screenX = $workArea.Left + [Math]::Max(0, [int](($workArea.Width - $script:Form.Width) / 2))
            $screenY = $workArea.Top + [Math]::Max(0, [int](($workArea.Height - $script:Form.Height) / 2))
            $script:Form.StartPosition = 'Manual'
            $script:Form.Location = New-Object Drawing.Point($screenX, $screenY)
            [Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 150
            Test-UiControlBounds $script:Form "Form[$($screen.DeviceName)]"
            $deviceDpi = if ($script:Form.PSObject.Properties['DeviceDpi']) { $script:Form.DeviceDpi } else { 'unknown' }
            Write-Host "UI layout probe: $($screen.DeviceName) DPI=$deviceDpi size=$($script:Form.Width)x$($script:Form.Height)"
        }
        if ($layoutViolations.Count -gt 0) {
            throw "UI layout validation failed: $($layoutViolations -join '; ')"
        }
        $bitmap = New-Object Drawing.Bitmap($script:Form.Width, $script:Form.Height)
        $captureMethod = 'screen'
        try {
            $script:Form.TopMost = $true
            $script:Form.BringToFront()
            $script:Form.Activate()
            [Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 200
            $graphics = [Drawing.Graphics]::FromImage($bitmap)
            try {
                $graphics.CopyFromScreen($script:Form.Bounds.Location, [Drawing.Point]::Empty, $script:Form.Size)
            }
            finally { $graphics.Dispose() }
        }
        catch {
            $captureMethod = 'DrawToBitmap fallback'
            $script:Form.DrawToBitmap($bitmap, (New-Object Drawing.Rectangle(0, 0, $bitmap.Width, $bitmap.Height)))
        }
        finally { $script:Form.TopMost = $false }
        $bitmap.Save($captureFullPath, [Drawing.Imaging.ImageFormat]::Png)
        $bitmap.Dispose()
        Write-Host "UI capture method: $captureMethod"
        $script:Form.Close()
        $script:TrayIcon.Visible = $false
        $script:TrayIcon.Dispose()
        if ($null -ne $script:BrandImageResource) { $script:BrandImageResource.Dispose() }
        if ($null -ne $script:TrayIconResource) { $script:TrayIconResource.Dispose() }
        if ($null -ne $script:FormIconResource) { $script:FormIconResource.Dispose() }
        [OpenSynapseNative.DisplayChangeSignal]::Stop()
        [OpenSynapseNative.PowerChangeSignal]::Stop()
        [OpenSynapseNative.GpuTelemetry]::Stop()
        if ($hasHandle) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
        Write-Host "UI capture saved with all controls inside their parent bounds: $captureFullPath"
        return
    }

    $showOnStart = Test-Path -LiteralPath $script:ShowRequestPath
    Remove-Item -LiteralPath $script:ShowRequestPath -Force -ErrorAction SilentlyContinue
    Initialize-SupplyStabilizer (Get-ActiveProfileName $script:State)
    $startupSnapshot = Get-PowerSnapshot
    $startupSelectionBeforeSupplyTransition = [string]$script:Config.Selection
    $startupSelection = Resolve-SelectionAfterSupplyTransition $startupSelectionBeforeSupplyTransition '' ([string]$startupSnapshot.SupplyType)
    if ($startupSelection -ne [string]$script:Config.Selection) {
        $script:Config.Selection = $startupSelection
        $script:TemporaryOverride = $null
        $script:Config.RefreshPolicy = Resolve-RefreshPolicyAfterPowerTransition ([string]$script:Config.RefreshPolicy) '' ([string]$startupSnapshot.Source) '' ([string]$startupSnapshot.SupplyType) $startupSelectionBeforeSupplyTransition $startupSelection
        $script:Config.ManageRefreshRate = ([string]$script:Config.RefreshPolicy -ne 'Unmanaged')
        Save-AppConfig $script:Config
        Write-AppLog 'Verified 280W-class adapter at startup released Eco, restored Smart Auto and selected the 240 Hz Auto refresh policy before Quiet maintenance ran.'
    }
    Write-AppLog "Tray started. Version=$script:AppVersion Selection=$($script:Config.Selection) Dpi=$script:DpiMode seamlessModeSwitching=$($script:Config.SeamlessModeSwitching)"
    $startupEcoSelected = $startupSelectionBeforeSupplyTransition -eq 'Quiet'
    $startupExperiment = [string]$script:Config.Selection -eq 'Experiment'
    $newStartupExperiment = $false
    if ($startupExperiment) {
        $newStartupExperiment = Initialize-ExperimentSession $script:State
        if (-not $newStartupExperiment -and $null -ne $script:State.ExperimentSession.BaselineDisplayState) {
            $startupRestore = Restore-DisplayStateSnapshot $script:State.ExperimentSession.BaselineDisplayState
            if (-not [bool]$startupRestore.Verified) {
                throw "The locked Experiment display state could not be restored at startup: $($startupRestore.Differences -join '; ')"
            }
        }
    }
    $applyStartupRefresh = [string]$script:Config.RefreshPolicy -eq 'Auto' -or $startupExperiment
    Write-AppLog "Startup profile apply beginning: selection=$($script:Config.Selection) supply=$($startupSnapshot.SupplyType) refresh=$($script:Config.RefreshPolicy)."
    Apply-CurrentSelection -Full -ApplyVisualPolicy:($startupEcoSelected -or $startupExperiment) -ApplyRefreshPolicy:($applyStartupRefresh -or $startupEcoSelected) -Snapshot $startupSnapshot
    if ($startupExperiment) {
        Complete-ExperimentSessionStart $script:Config $script:State $startupSnapshot $script:AutomationState -NewSession:$newStartupExperiment
    }
    Write-AppLog 'Startup profile apply completed.'
    $script:Timer.Start()
    $script:Form.Add_Shown({
        $null = [OpenSynapseNative.WindowTheme]::ApplyDarkFrame($script:Form.Handle)
        Apply-DarkControlTheme $script:Form
        Update-ApplicationUi
        if (-not $showOnStart) { $script:Form.Hide() } else { Update-DetailBox }
    })

    try { [Windows.Forms.Application]::Run($script:Form) }
    finally {
        try { [OpenSynapseNative.DisplayChangeSignal]::Stop() } catch { }
        try { [OpenSynapseNative.PowerChangeSignal]::Stop() } catch { }
        try { [OpenSynapseNative.GpuTelemetry]::Stop() } catch { }
        if ($null -ne $script:Timer) { $script:Timer.Stop(); $script:Timer.Dispose() }
        $script:TrayIcon.Visible = $false
        $script:TrayIcon.Dispose()
        if ($null -ne $script:BrandImageResource) { $script:BrandImageResource.Dispose() }
        if ($null -ne $script:TrayIconResource) { $script:TrayIconResource.Dispose() }
        if ($null -ne $script:FormIconResource) { $script:FormIconResource.Dispose() }
        Remove-Item -LiteralPath $script:RuntimePath -Force -ErrorAction SilentlyContinue
        Write-AppLog 'Tray stopped.'
        if ($hasHandle) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

switch ($Mode) {
    'Open' { Open-OpenSynapse; break }
    'Install' { Install-OpenSynapse; break }
    'Uninstall' { Uninstall-OpenSynapse; break }
    'Status' { Show-Status; break }
    'Apply' { Apply-ProfileOnce $Profile; break }
    'SelfTest' { Test-OpenSynapse; break }
    default { Start-TrayApplication; break }
}
