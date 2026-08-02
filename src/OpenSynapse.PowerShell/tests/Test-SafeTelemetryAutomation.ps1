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
if ($config.Version -ne 13 -or $config.SmartGpuEnter -ne 20 -or -not $config.SmartFullscreenEnabled -or
    @($config.ApplicationRules).Count -lt 15 -or $config.DgpuLeakMinimumSamples -ne 6) {
    throw 'Safe telemetry defaults are incomplete.'
}

$nativeMethods = [OpenSynapseNative.AutomationTelemetry].GetMethods().Name
if ('GetForegroundWindowSample' -notin $nativeMethods) { throw 'Native fullscreen telemetry is missing.' }
$gpuMethods = [OpenSynapseNative.GpuTelemetry].GetMethods().Name
foreach ($method in @('SetInterval', 'GetInterval')) {
    if ($method -notin $gpuMethods) { throw "Adaptive GPU telemetry method is missing: $method" }
}
$battery = [OpenSynapseNative.BatteryTelemetry]::Read()
if ($battery.Available -and ($battery.BatteryCount -lt 1 -or $battery.RemainingCapacityMwh -le 0 -or $battery.VoltageMv -le 0)) {
    throw "Battery Class API did not return a valid local battery sample: $($battery.Error)"
}

[OpenSynapseNative.GpuTelemetry]::Start(2000)
try {
    $gpu = $null
    $gpuStartupAttempts = 0
    foreach ($attempt in 1..15) {
        $gpuStartupAttempts = $attempt
        Start-Sleep -Seconds 1
        $gpu = [OpenSynapseNative.GpuTelemetry]::ReadLatest()
        if ($gpu.Available) { break }
    }
    if ($null -eq $gpu -or -not $gpu.Available) {
        throw "Windows GPU telemetry did not initialize within 15 seconds: $($gpu.Error)"
    }
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    $gpu = [OpenSynapseNative.GpuTelemetry]::ReadLatest()
    $stopwatch.Stop()
    if (-not $gpu.Available -or $gpu.TotalUtilizationPercent -lt 0 -or $gpu.TotalUtilizationPercent -gt 100) {
        throw "Windows GPU telemetry returned an invalid sample: $($gpu.Error)"
    }
    if ($stopwatch.ElapsedMilliseconds -gt 50) { throw "Cached GPU telemetry blocked for $($stopwatch.ElapsedMilliseconds) ms." }
}
finally { [OpenSynapseNative.GpuTelemetry]::Stop() }

# The background sampler must survive an in-process stop/start cycle, and a
# cadence change must wake the worker instead of waiting for the old interval.
$previousSequence = [long]$gpu.Sequence
$gpuWorkerRestarted = $false
$gpuCadenceWakeApplied = $false
[OpenSynapseNative.GpuTelemetry]::Start(20000)
try {
    foreach ($attempt in 1..12) {
        Start-Sleep -Milliseconds 250
        $restartSample = [OpenSynapseNative.GpuTelemetry]::ReadLatest()
        if ([long]$restartSample.Sequence -gt $previousSequence) {
            $gpuWorkerRestarted = $true
            break
        }
    }
    if (-not $gpuWorkerRestarted) { throw 'GPU telemetry did not restart in the same process.' }
    $restartSequence = [long]$restartSample.Sequence
    [OpenSynapseNative.GpuTelemetry]::SetInterval(2000)
    foreach ($attempt in 1..12) {
        Start-Sleep -Milliseconds 250
        $cadenceSample = [OpenSynapseNative.GpuTelemetry]::ReadLatest()
        if ([long]$cadenceSample.Sequence -gt $restartSequence) {
            $gpuCadenceWakeApplied = $true
            break
        }
    }
    if (-not $gpuCadenceWakeApplied) { throw 'GPU telemetry cadence change did not wake the worker.' }
}
finally { [OpenSynapseNative.GpuTelemetry]::Stop() }

$start = [DateTime]'2026-07-22T10:00:00'
$high = [pscustomobject]@{ Source = 'AC'; SupplyType = 'HighPowerAC'; BatteryPercent = 80; AdapterLimitW = 155 }
$portable = [pscustomobject]@{ Source = 'Battery'; SupplyType = 'Battery'; BatteryPercent = 80; AdapterLimitW = $null }

# An unlisted background GPU workload promotes after the normal load hysteresis.
$gpuState = New-SmartAutomationState Balance
$gpuState.LastSupplyType = 'HighPowerAC'
$gpuState.LastTransitionAt = $start.AddMinutes(-5)
foreach ($sample in 1..3) {
    $decision = Resolve-SmartAutomationDecision $config $high $gpuState 2 '' $start.AddSeconds($sample * 5) 35 $false @()
    $gpuState.CurrentProfile = $decision.Profile
    $gpuState.CandidateProfile = $decision.CandidateProfile
    $gpuState.CandidateSamples = $decision.CandidateSamples
}
if ($decision.Profile -ne 'Hyper' -or $decision.TriggerKind -ne 'Load') { throw 'Unlisted GPU load did not promote HighPowerAC to Hyper.' }

# An unlisted fullscreen foreground app needs CPU/GPU corroboration, then uses
# the faster app hysteresis.
$fullscreenState = New-SmartAutomationState Balance
$fullscreenState.LastSupplyType = 'HighPowerAC'
$fullscreenState.LastTransitionAt = $start.AddMinutes(-5)
$first = Resolve-SmartAutomationDecision $config $high $fullscreenState 18 unknown-game $start 2 $true @()
$fullscreenState.CandidateProfile = $first.CandidateProfile
$fullscreenState.CandidateSamples = $first.CandidateSamples
$second = Resolve-SmartAutomationDecision $config $high $fullscreenState 18 unknown-game $start.AddSeconds(5) 2 $true @()
if ($first.Profile -ne 'Balance' -or $second.Profile -ne 'Hyper') { throw 'Fullscreen app recognition did not use app hysteresis.' }

# Browser maximization/video fullscreen is common and must not promote to Hyper
# on light UI/video-decode load. A genuine sustained browser workload uses its
# own higher threshold and three-sample confirmation.
$browserState = New-SmartAutomationState Balance
$browserState.LastSupplyType = 'HighPowerAC'
$browserState.LastTransitionAt = $start.AddMinutes(-5)
foreach ($sample in 1..4) {
    $browserLight = Resolve-SmartAutomationDecision $config $high $browserState 18 chrome $start.AddSeconds($sample * 5) 8 $true @()
    $browserState.CurrentProfile = $browserLight.Profile
    $browserState.CandidateProfile = $browserLight.CandidateProfile
    $browserState.CandidateSamples = $browserLight.CandidateSamples
}
if ($browserLight.Profile -ne 'Balance') { throw 'Light fullscreen browser activity promoted to Hyper.' }
foreach ($sample in 1..$config.SmartBrowserFullscreenSamples) {
    $browserHeavy = Resolve-SmartAutomationDecision $config $high $browserState 50 chrome $start.AddSeconds(30 + ($sample * 5)) 8 $true @()
    $browserState.CurrentProfile = $browserHeavy.Profile
    $browserState.CandidateProfile = $browserHeavy.CandidateProfile
    $browserState.CandidateSamples = $browserHeavy.CandidateSamples
}
if ($browserHeavy.Profile -ne 'Hyper') { throw 'Sustained heavy fullscreen browser activity did not promote after its dedicated hysteresis.' }

# A user-defined Running rule recognizes a background renderer with no foreground match.
$config.ApplicationRules = @([pscustomobject]@{ ProcessName = 'background-renderer'; Profile = 'Hyper'; Scope = 'Running'; Enabled = $true })
$ruleState = New-SmartAutomationState Balance
$ruleState.LastSupplyType = 'HighPowerAC'
$ruleState.LastTransitionAt = $start.AddMinutes(-5)
$ruleFirst = Resolve-SmartAutomationDecision $config $high $ruleState 2 explorer $start 0 $false @('background-renderer')
$ruleState.CandidateProfile = $ruleFirst.CandidateProfile
$ruleState.CandidateSamples = $ruleFirst.CandidateSamples
$ruleSecond = Resolve-SmartAutomationDecision $config $high $ruleState 2 explorer $start.AddSeconds(5) 0 $false @('background-renderer')
if ($ruleSecond.Profile -ne 'Hyper' -or $ruleSecond.MatchedRule -notmatch 'background-renderer') { throw 'Running application rule did not recognize a background workload.' }

# The same GPU load on portable power can only promote to Balance.
$portableState = New-SmartAutomationState Quiet
$portableState.LastSupplyType = 'Battery'
$portableState.LastTransitionAt = $start.AddMinutes(-5)
$config.ApplicationRules = @()
foreach ($sample in 1..3) {
    $portableDecision = Resolve-SmartAutomationDecision $config $portable $portableState 2 '' $start.AddSeconds($sample * 5) 35 $false @()
    $portableState.CurrentProfile = $portableDecision.Profile
    $portableState.CandidateProfile = $portableDecision.CandidateProfile
    $portableState.CandidateSamples = $portableDecision.CandidateSamples
}
if ($portableDecision.Profile -ne 'Balance') { throw 'Portable GPU load did not stay within the Balance ceiling.' }

# dGPU leakage requires consecutive samples instead of a single transient.
$leakState = New-SmartAutomationState Quiet
$leakState.LastSupplyType = 'Battery'
$leakState.LastTransitionAt = $start.AddMinutes(-5)
$telemetry = [pscustomobject]@{
    CpuPercent = 2.0; ForegroundProcess = 'explorer'; ForegroundFullscreen = $false; RunningProcesses = @()
    GpuAvailable = $true; GpuPercent = 0.5; DgpuPercent = 1.5; DgpuDedicatedMb = 256.0
    DgpuConsumers = @([pscustomobject]@{ ProcessName = 'leaky-app'; Discrete = $true; UtilizationPercent = 1.5; DedicatedBytes = 256MB })
    GpuSampleSequence = 0L; GpuSampledAtUtcTicks = 0L; GpuSampleAgeSeconds = 0.0
}
foreach ($sample in 1..$config.DgpuLeakMinimumSamples) {
    $telemetry.GpuSampleSequence = [long]$sample
    $telemetry.GpuSampledAtUtcTicks = $start.AddSeconds($sample * 10).ToUniversalTime().Ticks
    $null = Update-SmartAutomationState $config $portable $leakState $telemetry $start.AddSeconds($sample * 5)
}
if (-not $leakState.DgpuLeakDetected -or @($leakState.DgpuConsumers).Count -ne 1) { throw 'Consecutive dGPU leakage detection failed.' }
$staleState = New-SmartAutomationState Quiet
$telemetry.GpuSampleSequence = 99L
foreach ($repeat in 1..$config.DgpuLeakMinimumSamples) {
    $null = Update-DgpuActivityState $config $portable $staleState $telemetry
}
if ($staleState.DgpuLeakSamples -ne 1 -or $staleState.DgpuLeakDetected) {
    throw 'A cached GPU sample was counted repeatedly as sustained dGPU activity.'
}

if ((Resolve-GpuTelemetryIntervalMilliseconds $config $high Auto) -ne 5000 -or
    (Resolve-GpuTelemetryIntervalMilliseconds $config $portable Auto) -ne 10000 -or
    (Resolve-GpuTelemetryIntervalMilliseconds $config $portable Quiet) -ne 20000) {
    throw 'Adaptive GPU telemetry cadence mapping failed.'
}

$source = Get-Content -Raw -LiteralPath $mainScript
$smartStart = $source.IndexOf('function Get-SmartAutomationTelemetry', [StringComparison]::Ordinal)
$smartEnd = $source.IndexOf('function Test-BalanceEligible', $smartStart, [StringComparison]::Ordinal)
$smartSource = $source.Substring($smartStart, $smartEnd - $smartStart)
if ($smartSource -match 'nvidia-smi|Get-Counter|Get-CimInstance') { throw 'Smart Auto contains a forbidden vendor or heavyweight PowerShell poller.' }
foreach ($required in @('Temporary mode', 'Application rules', 'Export diagnostics', 'IoctlBatteryQueryStatus', 'CreateDXGIFactory1')) {
    if ($source -notmatch [regex]::Escape($required) -and (Get-Content -Raw (Join-Path (Split-Path -Parent $mainScript) 'OpenSynapse.Native.cs')) -notmatch [regex]::Escape($required)) {
        throw "Missing safe feature marker: $required"
    }
}

# Diagnostic export is an explicit, read-only snapshot and must produce a usable ZIP.
$exportRoot = Join-Path (Split-Path -Parent $PSScriptRoot) '.diagnostic-export-test'
if (Test-Path -LiteralPath $exportRoot) { throw "Diagnostic test directory already exists: $exportRoot" }
try {
    [IO.Directory]::CreateDirectory($exportRoot) | Out-Null
    $script:DataDir = $exportRoot
    $script:LogPath = Join-Path $exportRoot 'OpenSynapse.log'
    $script:TelemetryPath = Join-Path $exportRoot 'telemetry.jsonl'
    $script:RuntimePath = Join-Path $exportRoot 'runtime.json'
    [IO.File]::WriteAllText($script:LogPath, 'diagnostic export test')
    [IO.File]::WriteAllText($script:TelemetryPath, '{}')
    $archivePath = Join-Path $exportRoot 'OpenSynapse-diagnostics-test.zip'
    $diagnosticState = [pscustomobject]@{ OriginalPlanGuid = $script:Guids.Balanced; DisabledWakeDevices = @(); ServicesStoppedByUs = @() }
    $snapshot = Get-PowerSnapshot
    $null = Export-OpenSynapseDiagnostics $archivePath $config $diagnosticState $snapshot $leakState
    if (-not (Test-Path -LiteralPath $archivePath) -or (Get-Item -LiteralPath $archivePath).Length -lt 100) { throw 'Diagnostic ZIP was not created.' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        $entryNames = [string[]]@($archive.Entries | Select-Object -ExpandProperty FullName)
        foreach ($name in @('manifest.json', 'config.json', 'state.json', 'OpenSynapse.log', 'telemetry.jsonl')) {
            if ($name -notin $entryNames) { throw "Diagnostic ZIP is missing $name." }
        }
    }
    finally { $archive.Dispose() }
}
finally { Remove-Item -LiteralPath $exportRoot -Recurse -Force -ErrorAction SilentlyContinue }

$result = [pscustomobject]@{
    Result = 'PASS'
    ConfigVersion = 13
    BatteryClassApi = [bool]$battery.Available
    BatteryCount = $battery.BatteryCount
    GpuTelemetryStartupSeconds = $gpuStartupAttempts
    GpuTelemetryCachedReadMs = $stopwatch.ElapsedMilliseconds
    FullscreenRecognition = $true
    BrowserFullscreenGuard = $true
    BackgroundGpuRecognition = $true
    RunningApplicationRules = $true
    PortableHyperCeiling = $true
    DgpuLeakSamples = $config.DgpuLeakMinimumSamples
    CachedGpuSamplesIgnored = $true
    AdaptiveGpuCadenceSeconds = @(5, 10, 20)
    GpuWorkerRestarted = $gpuWorkerRestarted
    GpuCadenceWakeApplied = $gpuCadenceWakeApplied
    DiagnosticExport = $true
    VendorControlInSmartLoop = $false
    ChangedSystemSettings = $false
    CompletedAt = (Get-Date).ToString('o')
}
if ($ResultPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath), ($result | ConvertTo-Json), [Text.UTF8Encoding]::new($false)) }
$result | Format-List
