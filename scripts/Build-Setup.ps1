[CmdletBinding()]
param(
    [ValidatePattern('^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$')]
    [string]$Version = '0.2.0-preview.1',
    [string]$IsccPath
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$definition = Join-Path $root 'installer\OpenSynapse.iss'
$publishRoot = Join-Path $root 'artifacts\publish\OpenSynapse'
$output = Join-Path $root "artifacts\OpenSynapse-Setup-$Version.exe"

if (-not (Test-Path -LiteralPath $definition -PathType Leaf)) {
    throw "Inno Setup definition was not found: $definition"
}
if (-not (Test-Path -LiteralPath $publishRoot -PathType Container)) {
    throw "Publish output was not found: $publishRoot"
}

if ([string]::IsNullOrWhiteSpace($IsccPath)) {
    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
        (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe')
    )
    $IsccPath = $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($IsccPath)) {
        $command = Get-Command ISCC.exe -ErrorAction SilentlyContinue
        if ($null -ne $command) { $IsccPath = $command.Source }
    }
}
if ([string]::IsNullOrWhiteSpace($IsccPath) -or -not (Test-Path -LiteralPath $IsccPath -PathType Leaf)) {
    throw 'Inno Setup 6 compiler was not found. Install it or pass -IsccPath.'
}

if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output -Force }
& $IsccPath "/DMyAppVersion=$Version" $definition
if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed with exit code $LASTEXITCODE." }
if (-not (Test-Path -LiteralPath $output -PathType Leaf)) {
    throw "Setup executable was not created: $output"
}

Write-Host "OpenSynapse $Version setup: $output"
