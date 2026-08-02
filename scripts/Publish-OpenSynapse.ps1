[CmdletBinding()]
param(
    [ValidateSet('win-x64', 'win-arm64')][string]$Runtime = 'win-x64',
    [switch]$FrameworkDependent,
    [string]$DotnetPath
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$source = Join-Path $root 'src\OpenSynapse.PowerShell'
$artifacts = [IO.Path]::GetFullPath((Join-Path $root 'artifacts'))
$publishRoot = [IO.Path]::GetFullPath((Join-Path $artifacts 'publish'))
$output = [IO.Path]::GetFullPath((Join-Path $publishRoot 'OpenSynapse'))
$zipPath = [IO.Path]::GetFullPath((Join-Path $artifacts 'OpenSynapse-2.4.6.zip'))
$separator = [IO.Path]::DirectorySeparatorChar
$artifactsPrefix = $artifacts.TrimEnd($separator, [IO.Path]::AltDirectorySeparatorChar) + $separator
if (-not $output.StartsWith($artifactsPrefix, [StringComparison]::OrdinalIgnoreCase) -or
    -not $zipPath.StartsWith($artifactsPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Resolved publish output is outside the repository artifacts directory.'
}
if (-not (Test-Path -LiteralPath $source -PathType Container)) {
    throw "OpenSynapse PowerShell source was not found: $source"
}

[IO.Directory]::CreateDirectory($publishRoot) | Out-Null
foreach ($legacyDirectory in @(
    (Join-Path $publishRoot 'Agent'),
    (Join-Path $publishRoot 'App'),
    $output
)) {
    if (Test-Path -LiteralPath $legacyDirectory) {
        Remove-Item -LiteralPath $legacyDirectory -Recurse -Force
    }
}
[IO.Directory]::CreateDirectory($output) | Out-Null

foreach ($fileName in @(
    'OpenSynapse.ps1',
    'OpenSynapse.Native.cs',
    'Install-OpenSynapse.cmd',
    'Uninstall-OpenSynapse.cmd',
    'README.md',
    'CHANGELOG.md',
    'TEST-REPORT.md'
)) {
    Copy-Item -LiteralPath (Join-Path $source $fileName) -Destination (Join-Path $output $fileName)
}
Copy-Item -LiteralPath (Join-Path $source 'assets') -Destination (Join-Path $output 'assets') -Recurse
Copy-Item -LiteralPath (Join-Path $source 'tests') -Destination (Join-Path $output 'tests') -Recurse

$publishedScript = Join-Path $output 'OpenSynapse.ps1'
$publishedNative = Join-Path $output 'OpenSynapse.Native.cs'
$parseErrors = $null
[void][Management.Automation.Language.Parser]::ParseFile($publishedScript, [ref]$null, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) {
    throw "Published script contains parser errors: $($parseErrors.Message -join '; ')"
}

$compileCommand = "& { `$ErrorActionPreference = 'Stop'; Add-Type -Path '$($publishedNative.Replace("'", "''"))' }"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $compileCommand
if ($LASTEXITCODE -ne 0) { throw "Published native helper compilation failed with exit code $LASTEXITCODE." }

if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
Compress-Archive -Path (Join-Path $output '*') -DestinationPath $zipPath -CompressionLevel Optimal

Write-Host "OpenSynapse 2.4.6 package: $output"
Write-Host "OpenSynapse 2.4.6 archive: $zipPath"
