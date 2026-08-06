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
$mainPath = Join-Path $project 'OpenSynapse.ps1'
$nativePath = Join-Path $project 'OpenSynapse.Native.cs'
. $mainPath -Mode SelfTest

$nativeMethods = [OpenSynapseNative.WindowTheme].GetMethods().Name
foreach ($method in @('ApplyDarkFrame', 'ApplyDarkControl', 'ApplyDarkCombo')) {
    if ($method -notin $nativeMethods) { throw "Missing native dark theme method: $method" }
}

$mainSource = Get-Content -LiteralPath $mainPath -Raw -Encoding UTF8
$nativeSource = Get-Content -LiteralPath $nativePath -Raw -Encoding UTF8
foreach ($required in @(
    'function Set-DarkComboStyle',
    'DrawMode = [Windows.Forms.DrawMode]::OwnerDrawFixed',
    'DarkMode_CFD',
    'ApplyDarkFrame($script:Form.Handle)',
    'Apply-DarkControlTheme $script:Form',
    '$menu.BackColor = $script:ControlDark',
    "`$script:AppVersion = '0.2.0'"
)) {
    $haystack = if ($required -eq 'DarkMode_CFD') { $nativeSource } else { $mainSource }
    if ($haystack.IndexOf($required, [StringComparison]::Ordinal) -lt 0) { throw "Missing dark theme definition: $required" }
}
if ($mainSource.IndexOf('New-Object Windows.Forms.NumericUpDown', [StringComparison]::Ordinal) -ge 0) {
    throw 'A light native NumericUpDown remains in the control panel.'
}
$comboCount = [regex]::Matches($mainSource, 'Set-DarkComboStyle \$script:').Count
if ($comboCount -ne 7) { throw "Expected seven dark selectors, including Razer polling, found $comboCount." }
if ($nativeSource.IndexOf('CaptionColorAttribute = 35', [StringComparison]::Ordinal) -lt 0 -or
    $nativeSource.IndexOf('BorderColorAttribute = 34', [StringComparison]::Ordinal) -lt 0) {
    throw 'DWM caption/border color definitions are incomplete.'
}

$result = [pscustomobject]@{
    Result = 'PASS'
    DarkSelectors = $comboCount
    DarkDwmFrame = $true
    DarkContextMenu = $true
    NativeNumericControlsRemaining = 0
    ChangedSystemSettings = $false
    CompletedAt = (Get-Date).ToString('o')
}
if ($ResultPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath), ($result | ConvertTo-Json), [Text.UTF8Encoding]::new($false)) }
$result | Format-List
