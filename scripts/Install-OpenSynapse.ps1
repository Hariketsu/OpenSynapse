[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$published = Join-Path $root 'artifacts\publish\OpenSynapse\OpenSynapse.ps1'
$source = Join-Path $root 'src\OpenSynapse.PowerShell\OpenSynapse.ps1'
$mainScript = if (Test-Path -LiteralPath $published -PathType Leaf) { $published } else { $source }
if (-not (Test-Path -LiteralPath $mainScript -PathType Leaf)) {
    throw 'OpenSynapse package was not found. Run scripts\Publish-OpenSynapse.ps1 first.'
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $mainScript -Mode Install
exit $LASTEXITCODE
