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

if ($null -eq (Get-Variable -Name LastAppliedHyperCpuPolicy -Scope Script -ErrorAction SilentlyContinue) -or
    $null -eq (Get-Variable -Name LastAppliedQuietCpuMax -Scope Script -ErrorAction SilentlyContinue)) {
    throw 'Runtime policy caches were not initialized for non-tray command-line paths.'
}

$config = Get-DefaultConfig
if ($config.Version -ne 10 -or $config.HyperCpuPolicy -ne 'Sustained') {
    throw 'Hyper performance defaults are incomplete.'
}
$sustained = Resolve-HyperCpuPolicy $config
$config.HyperCpuPolicy = 'Latency'
$latency = Resolve-HyperCpuPolicy $config
if (($sustained.Minimum, $sustained.Minimum1, $sustained.Minimum2, $sustained.MinCores, $sustained.MinCores1 -join ',') -ne '5,5,5,100,0') {
    throw 'Sustained Hyper mapping is incorrect.'
}
if (($latency.Minimum, $latency.Minimum1, $latency.Minimum2, $latency.MinCores, $latency.MinCores1 -join ',') -ne '100,100,100,100,100') {
    throw 'Latency Hyper mapping is incorrect.'
}

$script:RecordedPairs = New-Object Collections.Generic.List[object]
$script:RecordedReactivations = 0
function Set-PlanPair {
    param([string]$PlanGuid, [string]$Subgroup, [string]$Setting, [int]$AcValue, [int]$DcValue, [switch]$Optional)
    $script:RecordedPairs.Add([pscustomobject]@{ PlanGuid = $PlanGuid; Setting = $Setting; Ac = $AcValue; Dc = $DcValue })
}
function Get-ActivePlanGuid { return '11111111-1111-1111-1111-111111111111' }
function Invoke-PowerCfg {
    param([string[]]$Arguments, [switch]$AllowFailure)
    if (($Arguments -join ' ') -ne '/setactive 11111111-1111-1111-1111-111111111111') {
        throw "Unexpected powercfg call: $($Arguments -join ' ')"
    }
    $script:RecordedReactivations++
    return ''
}
function Write-AppLog { param([string]$Message) }

$state = [pscustomobject]@{ HyperPlanGuid = '11111111-1111-1111-1111-111111111111' }
$script:LastAppliedHyperCpuPolicy = $null
$config.HyperCpuPolicy = 'Sustained'
$null = Apply-HyperCpuPolicy $config $state
$null = Apply-HyperCpuPolicy $config $state
$config.HyperCpuPolicy = 'Latency'
$null = Apply-HyperCpuPolicy $config $state
if ($script:RecordedPairs.Count -ne 10 -or $script:RecordedReactivations -ne 2) {
    throw 'Hyper CPU policy was not applied exactly once per selected mode.'
}
$first = @($script:RecordedPairs | Select-Object -First 5)
$second = @($script:RecordedPairs | Select-Object -Skip 5 -First 5)
if (($first.Ac -join ',') -ne '5,5,5,100,0' -or ($second.Ac -join ',') -ne '100,100,100,100,100') {
    throw 'Hyper CPU runtime writes are incorrect.'
}

$source = Get-Content -LiteralPath $mainScript -Raw -Encoding UTF8
foreach ($required in @(
    'ProcessorEpp1 0 0',
    'ProcessorEpp2 0 0',
    'ProcessorMaximum1 100 100',
    'ProcessorMaximum2 100 100',
    'ProcessorAutonomous 1 1',
    'ProcessorBoostPolicy 100 100',
    'ProcessorIncrease 2 2',
    'ProcessorIncrease1 3 3',
    'WirelessPowerSaving 0 0',
    'PciLinkState 0 0',
    'GpuPreference 0 0',
    'UsbSelectiveSuspend 0 0'
)) {
    if ($source.IndexOf($required, [StringComparison]::Ordinal) -lt 0) { throw "Missing Hyper performance definition: $required" }
}

$result = [pscustomobject]@{
    Result = 'PASS'
    ConfigVersion = $config.Version
    DefaultPolicy = 'Sustained'
    PoliciesVerified = 2
    RuntimeWrites = $script:RecordedPairs.Count
    Reactivations = $script:RecordedReactivations
    HeterogeneousEppClasses = 3
    ChangedSystemSettings = $false
    CompletedAt = (Get-Date).ToString('o')
}
if ($ResultPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath), ($result | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false)) }
$result | Format-List
