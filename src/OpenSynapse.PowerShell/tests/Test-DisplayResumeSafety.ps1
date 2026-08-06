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
. $mainScript -Mode SelfTest

function New-TestMode([string]$monitorKey, [int]$width, [int]$height) {
    return [pscustomobject]@{
        DeviceName = '\\.\DISPLAY1'
        DeviceKey = 'adapter-key'
        DeviceId = 'adapter-id'
        MonitorDeviceKey = $monitorKey
        MonitorDeviceId = "monitor-id-$monitorKey"
        Width = $width
        Height = $height
        Frequency = 240
        PositionX = 0
        PositionY = 0
        Orientation = 0
    }
}

$externalMode = New-TestMode 'external-monitor-key' 2560 1440
$internalMode = New-TestMode 'internal-panel-key' 2560 1600
$externalState = [pscustomobject]@{
    Modes = @($externalMode)
    DynamicRefresh = @([pscustomobject]@{ GdiDeviceName = '\\.\DISPLAY1'; IsInternal = $false })
    PhysicalBrightness = @([pscustomobject]@{ GdiDeviceName = '\\.\DISPLAY1'; Supported = $true })
}
$internalState = [pscustomobject]@{
    Modes = @($internalMode)
    DynamicRefresh = @([pscustomobject]@{ GdiDeviceName = '\\.\DISPLAY1'; IsInternal = $true })
    PhysicalBrightness = @([pscustomobject]@{ GdiDeviceName = '\\.\DISPLAY1'; Supported = $false })
}
$unresponsiveExternalState = [pscustomobject]@{
    Modes = @($externalMode)
    DynamicRefresh = @([pscustomobject]@{ GdiDeviceName = '\\.\DISPLAY1'; IsInternal = $false })
    PhysicalBrightness = @([pscustomobject]@{ GdiDeviceName = '\\.\DISPLAY1'; Supported = $false })
}
$externalKey = Get-DisplayIdentityKey $externalMode
if ((Get-DisplayTopologyFingerprint @($externalMode)) -eq (Get-DisplayTopologyFingerprint @($internalMode))) {
    throw 'Topology fingerprint did not distinguish different monitor identities sharing DISPLAY1.'
}
if (@(Get-ExternalMonitorIdentityKeys $externalState).Count -ne 1 -or
    @(Get-ExternalMonitorIdentityKeys $internalState).Count -ne 0) {
    throw 'External monitor identity classification failed.'
}
$responsiveExternalKeys = @(Get-ResponsiveExternalMonitorIdentityKeys $externalState)
if ($responsiveExternalKeys.Count -ne 1 -or @(Get-ResponsiveExternalMonitorIdentityKeys $unresponsiveExternalState).Count -ne 0) {
    throw 'Responsive external monitor classification failed.'
}

$start = [DateTime]'2026-08-03T20:08:30'
$script:DisplayTopologyFingerprint = ''
$script:DisplayTopologyStableSamples = 0
$locked = Test-DisplayRepairReadiness -Now $start -SessionLocked $true -Suspended $false `
    -DisplayState $externalState -ExpectedMonitorKeys @($externalKey) -ExpectedMonitorDeadline $start.AddSeconds(30)
if ($locked.Ready -or $locked.Reason -ne 'SessionLocked') { throw 'Locked-session display repair was not blocked.' }

$suspended = Test-DisplayRepairReadiness -Now $start -SessionLocked $false -Suspended $true `
    -DisplayState $externalState -ExpectedMonitorKeys @($externalKey) -ExpectedMonitorDeadline $start.AddSeconds(30)
if ($suspended.Ready -or $suspended.Reason -ne 'SystemSuspended') { throw 'Suspended display repair was not blocked.' }

$missing = Test-DisplayRepairReadiness -Now $start.AddSeconds(12) -SessionLocked $false -Suspended $false `
    -DisplayState $internalState -ExpectedMonitorKeys @($externalKey) -ExpectedResponsiveMonitorKeys $responsiveExternalKeys -ExpectedMonitorDeadline $start.AddSeconds(30)
if ($missing.Ready -or $missing.Reason -ne 'ExpectedMonitorMissing') {
    throw 'Internal DISPLAY1 incorrectly satisfied the expected external monitor identity.'
}

$unresponsive = Test-DisplayRepairReadiness -Now $start.AddSeconds(12) -SessionLocked $false -Suspended $false `
    -DisplayState $unresponsiveExternalState -ExpectedMonitorKeys @($externalKey) -ExpectedResponsiveMonitorKeys $responsiveExternalKeys -ExpectedMonitorDeadline $start.AddSeconds(30)
if ($unresponsive.Ready -or $unresponsive.Reason -ne 'ExpectedMonitorUnresponsive') {
    throw 'A previously DDC-responsive external monitor was accepted while unresponsive.'
}

$firstStable = Test-DisplayRepairReadiness -Now $start.AddSeconds(15) -SessionLocked $false -Suspended $false `
    -DisplayState $externalState -ExpectedMonitorKeys @($externalKey) -ExpectedResponsiveMonitorKeys $responsiveExternalKeys -ExpectedMonitorDeadline $start.AddSeconds(30)
$secondStable = Test-DisplayRepairReadiness -Now $start.AddSeconds(18) -SessionLocked $false -Suspended $false `
    -DisplayState $externalState -ExpectedMonitorKeys @($externalKey) -ExpectedResponsiveMonitorKeys $responsiveExternalKeys -ExpectedMonitorDeadline $start.AddSeconds(30)
if ($firstStable.Ready -or $firstStable.Reason -ne 'TopologyStabilizing' -or
    -not $secondStable.Ready -or $secondStable.Reason -ne 'Stable') {
    throw 'Two-sample stable topology gate failed.'
}

$script:DisplayTopologyFingerprint = ''
$script:DisplayTopologyStableSamples = 0
$expiredFirst = Test-DisplayRepairReadiness -Now $start.AddSeconds(31) -SessionLocked $false -Suspended $false `
    -DisplayState $internalState -ExpectedMonitorKeys @($externalKey) -ExpectedMonitorDeadline $start.AddSeconds(30)
$expiredSecond = Test-DisplayRepairReadiness -Now $start.AddSeconds(34) -SessionLocked $false -Suspended $false `
    -DisplayState $internalState -ExpectedMonitorKeys @($externalKey) -ExpectedMonitorDeadline $start.AddSeconds(30)
if ($expiredFirst.Ready -or -not $expiredSecond.Ready -or $expiredSecond.Reason -ne 'ExpectedMonitorGraceExpired') {
    throw 'Missing external monitor grace expiry did not converge on the stable current topology.'
}

$nativeProperties = [OpenSynapseNative.PowerChangeSignal].GetProperties().Name
foreach ($property in @('SessionLocked', 'IsSuspended', 'WakeVersion')) {
    if ($property -notin $nativeProperties) { throw "Power signal is missing $property." }
}
if ('RequestWake' -notin [OpenSynapseNative.DisplayWakeManager].GetMethods().Name) {
    throw 'One-shot display wake request is missing.'
}
$source = Get-Content -Raw -LiteralPath $mainScript
foreach ($marker in @('Display topology changed while the refresh policy was being applied',
    'No fallback mode was written while topology was unstable', 'Test-DisplayRepairReadiness',
    'OpenSynapse cannot reset a monitor controller that is absent from Windows')) {
    if ($source.IndexOf($marker, [StringComparison]::Ordinal) -lt 0) { throw "Missing display resume safety marker: $marker" }
}

$result = [pscustomobject]@{
    Result = 'PASS'
    LockedRepairBlocked = $true
    SuspendedRepairBlocked = $true
    SameGdiDifferentMonitorDetected = $true
    UnresponsiveExternalBlocked = $true
    StableSamplesRequired = $script:DisplayTopologyStableSamplesRequired
    WakeSettleSeconds = $script:DisplayWakeSettleSeconds
    MissingMonitorGraceSeconds = $script:DisplayWakeGraceSeconds
    OneShotWakeRequest = $true
    MonitorControllerBoundaryPrompt = $true
    ChangedSystemSettings = $false
    CompletedAt = (Get-Date).ToString('o')
}
if ($ResultPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath), ($result | ConvertTo-Json), [Text.UTF8Encoding]::new($false)) }
$result | Format-List
