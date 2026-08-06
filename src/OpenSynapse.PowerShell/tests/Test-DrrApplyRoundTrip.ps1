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
$internalDeviceName = ''
$externalBefore = @{}

function Get-ExternalModeMap {
    param([object[]]$Modes, [string]$InternalDeviceName)
    $map = @{}
    foreach ($mode in @($Modes | Where-Object { [string]$_.DeviceName -ne $InternalDeviceName })) {
        $map[[string]$mode.DeviceName] = '{0}x{1}@{2}:{3}' -f $mode.Width, $mode.Height, $mode.Frequency, $mode.BitsPerPixel
    }
    return $map
}

function Test-ModeMapEqual {
    param([hashtable]$Expected, [hashtable]$Actual)
    if ($Expected.Count -ne $Actual.Count) { return $false }
    foreach ($key in $Expected.Keys) {
        if (-not $Actual.ContainsKey($key) -or $Actual[$key] -ne $Expected[$key]) { return $false }
    }
    return $true
}

try {
    . $MainScript -Mode SelfTest
    $beforeModes = @([OpenSynapseNative.DisplayModeManager]::GetActiveDisplays())
    if ($beforeModes.Count -lt 1) { throw 'No active displays were found.' }
    $beforeDynamic = [OpenSynapseNative.DynamicRefreshManager]::GetStatus()
    if (-not $beforeDynamic.InternalDisplayActive -or -not $beforeDynamic.Supported) {
        throw "Internal dynamic refresh is unavailable: $($beforeDynamic.Message)"
    }
    $internalDeviceName = [string]$beforeDynamic.GdiDeviceName
    $internalBefore = @($beforeModes | Where-Object { [string]$_.DeviceName -eq $internalDeviceName } | Select-Object -First 1)
    if ($internalBefore.Count -ne 1) { throw 'The active internal display mode could not be mapped.' }
    $restoreHz = [int]$internalBefore[0].Frequency
    $externalBefore = Get-ExternalModeMap $beforeModes $internalDeviceName
    if (-not [OpenSynapseNative.DynamicRefreshManager]::ValidateWindowsDynamic()) {
        throw 'Windows rejected the native dynamic refresh validation request.'
    }

    $null = [OpenSynapseNative.DynamicRefreshManager]::ApplyInternalFixedRefresh(120)
    Start-Sleep -Milliseconds 300
    $fixedModes = @([OpenSynapseNative.DisplayModeManager]::GetActiveDisplays())
    if (-not (Test-ModeMapEqual $externalBefore (Get-ExternalModeMap $fixedModes $internalDeviceName))) {
        throw 'An external display mode changed while applying the internal fixed refresh test.'
    }
    $fixedPath = [OpenSynapseNative.DynamicRefreshManager]::GetStatus()
    $null = [OpenSynapseNative.DynamicRefreshManager]::EnableWindowsDynamic()
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
        try { $null = [OpenSynapseNative.DynamicRefreshManager]::ApplyInternalFixedRefresh($restoreHz) } catch { }
    }
    Start-Sleep -Milliseconds 500
    try { $restored = [OpenSynapseNative.DynamicRefreshManager]::GetStatus() } catch { }
}

$afterModes = @([OpenSynapseNative.DisplayModeManager]::GetActiveDisplays())
$internalRestored = @($afterModes | Where-Object {
    [string]$_.DeviceName -eq $internalDeviceName -and [Math]::Abs([int]$_.Frequency - $restoreHz) -le 1
}).Count -eq 1
$externalRestored = Test-ModeMapEqual $externalBefore (Get-ExternalModeMap $afterModes $internalDeviceName)
$dynamicDisabled = $null -ne $restored -and -not $restored.Enabled
if (-not $internalRestored -or -not $externalRestored -or -not $dynamicDisabled) { throw 'Display refresh state was not fully restored after the dynamic refresh test.' }

$result = [pscustomobject]@{
    Result = 'PASS'
    ConfigurationApplied = $true
    InternalDisplayActive = [bool]$enabled.InternalDisplayActive
    DynamicRefreshSupported = [bool]$enabled.Supported
    EnabledBaseHz = [int]$enabled.BaseFrequency
    EnabledBoostHz = [int]$enabled.BoostFrequency
    RestoreHz = $restoreHz
    InternalDisplayRestored = $internalRestored
    ExternalDisplaysUnchanged = $externalRestored
    DynamicRefreshDisabledAfterTest = $dynamicDisabled
    CompletedAt = (Get-Date).ToString('o')
}
if ($ResultPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath), ($result | ConvertTo-Json), [Text.UTF8Encoding]::new($false)) }
$result | Format-List
