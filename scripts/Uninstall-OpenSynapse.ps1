[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$installed = Join-Path $env:ProgramFiles 'OpenSynapse\OpenSynapse.ps1'
$root = Split-Path -Parent $PSScriptRoot
$source = Join-Path $root 'src\OpenSynapse.PowerShell\OpenSynapse.ps1'
$mainScript = if (Test-Path -LiteralPath $installed -PathType Leaf) { $installed } else { $source }
if (-not (Test-Path -LiteralPath $mainScript -PathType Leaf)) {
    throw 'OpenSynapse installation or source package was not found.'
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $mainScript -Mode Uninstall
exit $LASTEXITCODE
