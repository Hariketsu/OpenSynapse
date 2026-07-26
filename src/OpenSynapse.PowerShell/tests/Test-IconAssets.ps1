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
$appIconPath = Join-Path $root 'assets\OpenSynapse.App.ico'
$trayIconPath = Join-Path $root 'assets\OpenSynapse.Tray.ico'
$appPngPath = Join-Path $root 'assets\OpenSynapse.App.png'
$trayPngPath = Join-Path $root 'assets\OpenSynapse.Tray.png'
$mainScript = Join-Path $root 'OpenSynapse.ps1'

function Get-IcoSizes([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 6 -or [BitConverter]::ToUInt16($bytes, 0) -ne 0 -or [BitConverter]::ToUInt16($bytes, 2) -ne 1) {
        throw "Invalid ICO header: $Path"
    }
    $count = [BitConverter]::ToUInt16($bytes, 4)
    if ($bytes.Length -lt (6 + 16 * $count)) { throw "Truncated ICO directory: $Path" }
    $sizes = New-Object Collections.Generic.List[int]
    foreach ($index in 0..($count - 1)) {
        $offset = 6 + 16 * $index
        $width = if ($bytes[$offset] -eq 0) { 256 } else { [int]$bytes[$offset] }
        $height = if ($bytes[$offset + 1] -eq 0) { 256 } else { [int]$bytes[$offset + 1] }
        if ($width -ne $height) { throw "Non-square ICO frame in ${Path}: ${width}x$height" }
        $sizes.Add($width)
    }
    return @($sizes.ToArray() | Sort-Object -Unique)
}

Add-Type -AssemblyName System.Drawing
$requiredSizes = @(16, 20, 24, 32, 40, 48, 64, 96, 128, 256)
$appSizes = @(Get-IcoSizes $appIconPath)
$traySizes = @(Get-IcoSizes $trayIconPath)
foreach ($size in $requiredSizes) {
    if ($size -notin $appSizes) { throw "App icon is missing ${size}px frame." }
    if ($size -notin $traySizes) { throw "Tray icon is missing ${size}px frame." }
}

foreach ($iconPath in @($appIconPath, $trayIconPath)) {
    $icon = [Drawing.Icon]::new($iconPath)
    try { if ($icon.Width -lt 16 -or $icon.Height -lt 16) { throw "Icon cannot be loaded: $iconPath" } }
    finally { $icon.Dispose() }
}

foreach ($pngPath in @($appPngPath, $trayPngPath)) {
    $bitmap = [Drawing.Bitmap]::new($pngPath)
    try {
        if ($bitmap.Width -ne 512 -or $bitmap.Height -ne 512) { throw "Unexpected PNG size: $pngPath" }
        if ($bitmap.GetPixel(0, 0).A -ne 0) { throw "PNG corner is not transparent: $pngPath" }
    }
    finally { $bitmap.Dispose() }
}

$mainSource = Get-Content -Raw -LiteralPath $mainScript
foreach ($required in @(
    '$script:InstalledAppIcon', '$script:InstalledTrayIcon', '$script:TrayIconResource',
    '$script:FormIconResource', '$script:InstalledAppPng', '$script:SourceAppPng',
    '$shortcut.IconLocation = $script:InstalledAppIcon'
)) {
    if ($mainSource.IndexOf($required, [StringComparison]::Ordinal) -lt 0) { throw "Missing icon integration definition: $required" }
}

$result = [pscustomobject]@{
    Result = 'PASS'
    AppFrames = $appSizes.Count
    TrayFrames = $traySizes.Count
    MinimumSize = $requiredSizes[0]
    MaximumSize = $requiredSizes[-1]
    TransparentPngSources = $true
    WindowTrayShortcutIntegration = $true
    ChangedSystemSettings = $false
    CompletedAt = (Get-Date).ToString('o')
}
if ($ResultPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath), ($result | ConvertTo-Json), [Text.UTF8Encoding]::new($false)) }
$result | Format-List
