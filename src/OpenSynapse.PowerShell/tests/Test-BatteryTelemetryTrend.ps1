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
Reset-BatteryPowerTrend
$start = [DateTime]'2026-07-24T10:00:00'

foreach ($sample in 0..120) {
    $watts = if ($sample -lt 60) { 10.0 } else { 20.0 }
    $trend = Update-BatteryPowerTrend $true $watts 80000 'Battery' $start.AddSeconds($sample * 5)
}
if ($trend.Confidence -ne 'High' -or $trend.SampleCount -ne 121) {
    throw 'Ten-minute battery trend did not reach high confidence.'
}
if ($trend.Average10mW -lt 14.5 -or $trend.Average10mW -gt 15.5) {
    throw "Ten-minute discharge average is incorrect: $($trend.Average10mW) W."
}
if ($trend.EmaW -le $trend.Average10mW -or $trend.EmaW -ge 20) {
    throw "Two-minute EMA did not react faster than the ten-minute average: $($trend.EmaW) W."
}
if ($trend.EstimatedHours -lt 5.0 -or $trend.EstimatedHours -gt 5.5) {
    throw "Smoothed runtime estimate is outside the expected range: $($trend.EstimatedHours) h."
}

$reset = Update-BatteryPowerTrend $true 5.0 80000 'AC' $start.AddMinutes(11)
if ($reset.SampleCount -ne 1 -or $reset.Confidence -ne 'Low' -or $reset.Average10mW -ne 5.0) {
    throw 'Battery trend did not reset across an AC/DC source change.'
}
$unavailable = Update-BatteryPowerTrend $false 0 0 'Unknown' $start.AddMinutes(12)
if ($unavailable.Confidence -ne 'Unavailable' -or $null -ne $unavailable.EstimatedHours) {
    throw 'Unavailable battery telemetry did not fail safely.'
}

$result = [pscustomobject]@{
    Result = 'PASS'
    EmaW = $trend.EmaW
    Average10mW = $trend.Average10mW
    EstimatedHours = $trend.EstimatedHours
    Confidence = $trend.Confidence
    SourceChangeReset = $true
    ChangedSystemSettings = $false
    CompletedAt = (Get-Date).ToString('o')
}
if ($ResultPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath), ($result | ConvertTo-Json), [Text.UTF8Encoding]::new($false)) }
$result | Format-List
