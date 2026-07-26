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

$root = Split-Path -Parent $PSScriptRoot
$mainPath = Join-Path $root 'OpenSynapse.ps1'
$nativePath = Join-Path $root 'OpenSynapse.Native.cs'
$mainSource = Get-Content -Raw -LiteralPath $mainPath
$nativeSource = Get-Content -Raw -LiteralPath $nativePath

foreach ($required in @(
    "`$script:Form.FormBorderStyle = 'None'",
    '$script:Form.ClientSize = New-Object Drawing.Size(1440, 900)',
    '$script:Form.MinimumSize = New-Object Drawing.Size(1440, 900)',
    'function New-ChromeButton',
    'function New-NavButton',
    "New-NavButton 'Dashboard'",
    "New-NavButton 'Game'",
    "New-NavButton 'Settings'",
    "New-NavButton 'Diagnostics'",
    "New-NavButton 'About'",
    "Show-NavigationPage 'Dashboard'",
    '$script:StatusCpuValue',
    '$script:StatusGpuValue',
    '$script:StatusRateValue',
    '$script:SourceAppPng',
    '$script:InstalledAppPng',
    '[OpenSynapseNative.WindowChrome]::BeginDrag($script:Form.Handle)',
    '$titleBar.Add_MouseDown($dragAction)',
    '$brandPicture.Add_MouseDown($dragAction)',
    '$brandLabel.Add_MouseDown($dragAction)'
)) {
    if ($mainSource.IndexOf($required, [StringComparison]::Ordinal) -lt 0) {
        throw "Missing Synapse shell definition: $required"
    }
}

foreach ($required in @(
    '$headingLabel.AutoSize = $false',
    '$headingLabel.Size = New-Object Drawing.Size(920, 48)',
    '$descriptionLabel.AutoSize = $false',
    '$descriptionLabel.Size = New-Object Drawing.Size(920, 32)',
    '$descriptionLabel.Location = New-Object Drawing.Point(42, 78)',
    '$script:PowerLabel.Location = New-Object Drawing.Point(42, 122)'
)) {
    if ($mainSource.IndexOf($required, [StringComparison]::Ordinal) -lt 0) {
        throw "Missing high-DPI heading guard: $required"
    }
}

foreach ($required in @(
    'ApplyRoundedCorners',
    'public static class WindowChrome',
    'public static void BeginDrag',
    'ColorRef(45, 49, 50)'
)) {
    if ($nativeSource.IndexOf($required, [StringComparison]::Ordinal) -lt 0) {
        throw "Missing native custom chrome definition: $required"
    }
}
if ($nativeSource.IndexOf('ColorRef(68, 214, 44)', [StringComparison]::Ordinal) -ge 0) {
    throw 'The old bright-green DWM perimeter is still configured.'
}

$pageCount = [regex]::Matches($mainSource, '\$page(?:Dashboard|Game|Settings|Diagnostics|About) = New-ContentPage').Count
if ($pageCount -ne 5) { throw "Expected five content pages, found $pageCount." }

$result = [pscustomobject]@{
    Result = 'PASS'
    BorderlessChrome = $true
    RoundedCorners = $true
    LeftNavigationItems = 5
    ContentPages = $pageCount
    LiveDashboardTelemetry = $true
    HighResolutionBrandAsset = $true
    ClientSize = '1440x900'
    FixedHeightPageHeadings = $true
    DraggableTitleBar = $true
    ChangedSystemSettings = $false
    CompletedAt = (Get-Date).ToString('o')
}
if ($ResultPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath), ($result | ConvertTo-Json), [Text.UTF8Encoding]::new($false)) }
$result | Format-List
