#requires -Version 5.1
#requires -RunAsAdministrator

[CmdletBinding()]
param(
    [string]$ResultPath = '',
    [string]$MainScript = 'C:\Program Files\OpenSynapse\OpenSynapse.ps1'
)

$ErrorActionPreference = 'Stop'
$beforeModes = @()
$restoreHz = 0
$enabled = $null
$restored = $null
$fixedModes = @()
$fixedPath = $null

try {
    . $MainScript -Mode SelfTest
    $beforeModes = @([OpenSynapseNative.DisplayModeManager]::GetActiveDisplays())
    if ($beforeModes.Count -lt 1) { throw 'No active displays were found.' }
    $frequencies = @($beforeModes | Select-Object -ExpandProperty Frequency -Unique)
    if ($frequencies.Count -ne 1) { throw 'This safe round-trip test requires all active displays to start at the same refresh rate.' }
    $restoreHz = [int]$frequencies[0]

    $beforeDynamic = [OpenSynapseNative.DynamicRefreshManager]::GetStatus()
    if (-not $beforeDynamic.InternalDisplayActive -or -not $beforeDynamic.Supported) {
        throw "Internal dynamic refresh is unavailable: $($beforeDynamic.Message)"
    }
    if (-not [OpenSynapseNative.DynamicRefreshManager]::ValidateNativeDynamic()) {
        throw 'Windows rejected the native dynamic refresh validation request.'
    }

    $null = [OpenSynapseNative.DisplayModeManager]::ApplyFixedRefresh(120)
    Start-Sleep -Milliseconds 300
    $fixedModes = @([OpenSynapseNative.DisplayModeManager]::GetActiveDisplays())
    $fixedPath = [OpenSynapseNative.DynamicRefreshManager]::GetStatus()
    $null = [OpenSynapseNative.DynamicRefreshManager]::EnableNativeDynamic()
    $enabled = [OpenSynapseNative.DynamicRefreshManager]::GetStatus()
    if (-not $enabled.Enabled -or [Math]::Abs($enabled.BaseFrequency - 60) -gt 1 -or
        [Math]::Abs($enabled.BoostFrequency - 240) -gt 1) {
        throw 'Dynamic refresh did not read back as the enabled native 60-to-240 Hz range.'
    }
}
catch {
    $failure = [pscustomobject]@{
        Result = 'FAIL'
        ErrorType = $_.Exception.GetType().FullName
        FixedModeFrequencies = @($fixedModes | ForEach-Object { [int]$_.Frequency })
        FixedPathBaseHz = if ($null -ne $fixedPath) { [int]$fixedPath.BaseFrequency } else { -1 }
        FixedPathBoostHz = if ($null -ne $fixedPath) { [int]$fixedPath.BoostFrequency } else { -1 }
        RestoreHz = $restoreHz
        CompletedAt = (Get-Date).ToString('o')
    }
    if ($ResultPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath), ($failure | ConvertTo-Json), [Text.UTF8Encoding]::new($false)) }
    throw
}
finally {
    try { $null = [OpenSynapseNative.DynamicRefreshManager]::Disable() } catch { }
    if ($restoreHz -gt 0) {
        try { $null = [OpenSynapseNative.DisplayModeManager]::ApplyFixedRefresh($restoreHz) } catch { }
    }
    Start-Sleep -Milliseconds 500
    try { $restored = [OpenSynapseNative.DynamicRefreshManager]::GetStatus() } catch { }
}

$afterModes = @([OpenSynapseNative.DisplayModeManager]::GetActiveDisplays())
$frequenciesRestored = @($afterModes | Where-Object { $_.Frequency -ne $restoreHz }).Count -eq 0
$dynamicDisabled = $null -ne $restored -and -not $restored.Enabled
if (-not $frequenciesRestored -or -not $dynamicDisabled) { throw 'Display refresh state was not fully restored after the dynamic refresh test.' }

$result = [pscustomobject]@{
    Result = 'PASS'
    ConfigurationApplied = $true
    InternalDisplayActive = [bool]$enabled.InternalDisplayActive
    DynamicRefreshSupported = [bool]$enabled.Supported
    EnabledBaseHz = [int]$enabled.BaseFrequency
    EnabledBoostHz = [int]$enabled.BoostFrequency
    RestoreHz = $restoreHz
    ActiveDisplaysRestored = $frequenciesRestored
    DynamicRefreshDisabledAfterTest = $dynamicDisabled
    CompletedAt = (Get-Date).ToString('o')
}
if ($ResultPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath), ($result | ConvertTo-Json), [Text.UTF8Encoding]::new($false)) }
$result | Format-List
