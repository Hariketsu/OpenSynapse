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
$config = Get-DefaultConfig
$portable = [pscustomobject]@{
    Source = 'Battery'
    SupplyType = 'Battery'
    BatteryPercent = 80
    BatteryDischargeW = 18.0
    BatteryDischargeAverage10mW = 17.0
}
$start = [DateTime]'2026-07-26T10:00:00'

# Auto is allowed to promote portable workloads to Balance.
$autoState = New-SmartAutomationState Quiet
$autoState.LastSupplyType = 'Battery'
$autoState.LastTransitionAt = $start.AddMinutes(-5)
foreach ($sample in 1..$config.SmartLoadEnterSamples) {
    $autoDecision = Resolve-SmartAutomationDecision $config $portable $autoState 50 'workload' $start.AddSeconds($sample * 5) 5 $false @()
    $autoState.CurrentProfile = $autoDecision.Profile
    $autoState.CandidateProfile = $autoDecision.CandidateProfile
    $autoState.CandidateSamples = $autoDecision.CandidateSamples
}
if ($autoDecision.Profile -ne 'Balance') { throw 'Auto did not promote a sustained portable workload to Balance.' }

# Manual Quiet is authoritative even when the automation state still says Balance.
if ((Get-DesiredProfile Quiet $portable $config $autoState) -ne 'Quiet') {
    throw 'Manual Quiet did not override the automatic Balance decision.'
}

$script:RecordedQuietLogs = New-Object Collections.Generic.List[string]
function Write-AppLog {
    param([string]$Message)
    $script:RecordedQuietLogs.Add($Message)
}
$manualState = New-SmartAutomationState Quiet
$manualTelemetry = [pscustomobject]@{
    CpuPercent = 90.0
    ForegroundProcess = 'workload'
    ForegroundFullscreen = $true
    RunningProcesses = @()
    SessionLocked = $false
    GpuAvailable = $true
    GpuPercent = 50.0
    DgpuPercent = 0.0
    DgpuDedicatedMb = 0.0
    DgpuConsumers = @()
}
$null = Update-ManualTelemetryState $config $portable $manualState Quiet $manualTelemetry
if ($manualState.CurrentProfile -ne 'Quiet' -or $manualState.LastReason -notmatch 'decisions paused' -or
    @($script:RecordedQuietLogs | Where-Object { $_ -match '^Smart Auto decision:' }).Count -ne 0) {
    throw 'Manual Quiet telemetry updated or logged a Smart Auto decision.'
}

# A helper that immediately respawns is closed once, then receives a cooldown
# instead of entering a repeated stop/restart loop.
$script:FakeProcessRunning = $true
$script:FakeStopCount = 0
function Get-Process {
    param([string]$Name, [int]$Id, [object]$ErrorAction)
    if ($script:FakeProcessRunning -and $Name -eq 'NVIDIA Overlay') {
        return [pscustomobject]@{ Id = 4242; ProcessName = 'NVIDIA Overlay' }
    }
    return $null
}
function Stop-Process {
    param([int]$Id, [switch]$Force, [object]$ErrorAction)
    $script:FakeStopCount++
}
$script:QuietProcessGuard = @{}
$firstMaintenance = Stop-TrackedProcess @('NVIDIA Overlay') $config $start
$restartMaintenance = Stop-TrackedProcess @('NVIDIA Overlay') $config $start.AddMinutes(3)
$cooldownMaintenance = Stop-TrackedProcess @('NVIDIA Overlay') $config $start.AddMinutes(5)
if ($script:FakeStopCount -ne 1 -or @($firstMaintenance.Closed).Count -ne 1 -or
    @($restartMaintenance.Restarted).Count -ne 1 -or @($restartMaintenance.CoolingDown).Count -ne 1 -or
    @($cooldownMaintenance.Closed).Count -ne 0) {
    throw 'Quiet process restart detection did not prevent a repeated termination loop.'
}
if (@($script:RecordedQuietLogs | Where-Object { $_ -match 'restart detected.*cooling down' }).Count -ne 1) {
    throw 'Quiet process restart cooldown was not logged exactly once.'
}

# Telemetry schema v2 records the actual plan and the battery fields needed for
# endurance analysis.
$temporary = Join-Path (Split-Path -Parent $PSScriptRoot) '.quiet-control-test'
if (Test-Path -LiteralPath $temporary) { throw "Test directory already exists: $temporary" }
$oldDataDir = $script:DataDir
$oldTelemetryPath = $script:TelemetryPath
try {
    [IO.Directory]::CreateDirectory($temporary) | Out-Null
    $script:DataDir = $temporary
    $script:TelemetryPath = Join-Path $temporary 'telemetry.jsonl'
    $telemetrySnapshot = [pscustomobject]@{
        Source = 'Battery'
        SupplyType = 'Battery'
        BatteryPercent = 80
        BatteryRemainingMwh = 64000
        BatteryVoltageMv = 16335
        BatteryDischargeW = 16.5
        BatteryDischargeEmaW = 16.2
        BatteryDischargeAverage10mW = 16.0
        BatteryEstimatedHours = 4.0
        BatteryEstimateConfidence = 'High'
        BatteryChargeW = 0.0
    }
    Write-TelemetryRecord $telemetrySnapshot $manualState Quiet Quiet '' Quiet
    $record = Get-Content -LiteralPath $script:TelemetryPath -Raw | ConvertFrom-Json
    if ($record.SchemaVersion -ne 2 -or $record.ActiveProfile -ne 'Quiet' -or
        $record.BatteryRemainingMwh -ne 64000 -or $record.BatteryVoltageMv -ne 16335 -or
        $record.EstimatedHours -ne 4.0) {
        throw 'Telemetry schema v2 is missing an active-profile or battery endurance field.'
    }
}
finally {
    $script:DataDir = $oldDataDir
    $script:TelemetryPath = $oldTelemetryPath
    Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
}

$source = Get-Content -LiteralPath $mainScript -Raw -Encoding UTF8
$policyStart = $source.IndexOf('function Set-ProfilePolicy', [StringComparison]::Ordinal)
$policyEnd = $source.IndexOf('function Get-DefaultConfig', $policyStart, [StringComparison]::Ordinal)
if ($policyStart -lt 0 -or $policyEnd -le $policyStart) { throw 'Profile policy source boundary was not found.' }
$profilePolicySource = $source.Substring($policyStart, $policyEnd - $policyStart)
$quietStart = $profilePolicySource.LastIndexOf('Set-PlanPair $PlanGuid $script:Guids.Processor $script:Guids.ProcessorMinimum 5 5', [StringComparison]::Ordinal)
if ($quietStart -lt 0) { throw 'Quiet policy source boundary was not found.' }
$quietPolicySource = $profilePolicySource.Substring($quietStart)
if ($quietPolicySource -match 'ProcessorIncrease|ProcessorDecrease|TGP|Fan|EmbeddedController|\bEC\b') {
    throw 'Quiet policy changed an OEM heterogeneous threshold, TGP, fan or EC control.'
}

$result = [pscustomobject]@{
    Result = 'PASS'
    AutoPortableBalance = $true
    ManualQuietLocked = $true
    ManualDecisionLoggingPaused = $true
    RestartCooldownMinutes = [int]($config.QuietProcessCooldownSeconds / 60)
    TelemetrySchemaVersion = $script:TelemetrySchemaVersion
    OemControlsUntouched = $true
    ChangedSystemSettings = $false
    CompletedAt = (Get-Date).ToString('o')
}
if ($ResultPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath), ($result | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false)) }
$result | Format-List
