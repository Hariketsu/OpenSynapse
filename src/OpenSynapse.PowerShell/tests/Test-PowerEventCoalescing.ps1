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
$start = [DateTime]'2026-07-24T10:00:00'
$script:LastPowerEventCount = 0
$script:PendingPowerProbeAt = [DateTime]::MaxValue
$script:PowerEventsObserved = 0
$script:PowerEventsCoalesced = 0
$script:PowerEventTriggeredProbes = 0
$script:CachedSupplyType = 'HighPowerAC'
$script:CachedAdapterLimitW = 160
$script:LastAdapterProbe = $start

if (-not (Register-PowerEventObservation 5 $start)) { throw 'Initial event batch was not observed.' }
$firstDue = $script:PendingPowerProbeAt
if (-not (Register-PowerEventObservation 8 $start.AddSeconds(1))) { throw 'Follow-up event batch was not observed.' }
if ($script:PendingPowerProbeAt -ne $firstDue -or $script:PowerEventsObserved -ne 8 -or $script:PowerEventsCoalesced -ne 3) {
    throw 'Power event batch was not coalesced into its original deadline.'
}
if (Invoke-PendingPowerProbe $start.AddSeconds(3)) { throw 'Power-event probe ran before the debounce deadline.' }
if (-not (Invoke-PendingPowerProbe $start.AddSeconds(4))) { throw 'Power-event probe did not run at the debounce deadline.' }
if ($null -ne $script:CachedSupplyType -or $null -ne $script:CachedAdapterLimitW -or
    $script:PowerEventTriggeredProbes -ne 1 -or $script:PendingPowerProbeAt -ne [DateTime]::MaxValue) {
    throw 'Coalesced power-event probe did not invalidate the cache exactly once.'
}
if (Invoke-PendingPowerProbe $start.AddSeconds(10)) { throw 'Power-event probe repeated without another event.' }

$nativeSource = Get-Content -Raw -LiteralPath (Join-Path (Split-Path -Parent $mainScript) 'OpenSynapse.Native.cs')
foreach ($marker in @('DebounceMilliseconds = 3000', 'CoalescedEventCount', 'SystemEvents.SessionSwitch')) {
    if ($nativeSource.IndexOf($marker, [StringComparison]::Ordinal) -lt 0) { throw "Missing native coalescing marker: $marker" }
}

$result = [pscustomobject]@{
    Result = 'PASS'
    ObservedEvents = $script:PowerEventsObserved
    CoalescedEvents = $script:PowerEventsCoalesced
    TriggeredProbes = $script:PowerEventTriggeredProbes
    ProbeDelaySeconds = $script:PowerEventProbeDelaySeconds
    NativeDebounceMilliseconds = 3000
    ChangedSystemSettings = $false
    CompletedAt = (Get-Date).ToString('o')
}
if ($ResultPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath), ($result | ConvertTo-Json), [Text.UTF8Encoding]::new($false)) }
$result | Format-List
