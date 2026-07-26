[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$mainPath = Join-Path $root 'src\OpenSynapse.PowerShell\OpenSynapse.ps1'
$nativePath = Join-Path $root 'src\OpenSynapse.PowerShell\OpenSynapse.Native.cs'
$publishPath = Join-Path $PSScriptRoot 'Publish-OpenSynapse.ps1'
$installPath = Join-Path $PSScriptRoot 'Install-OpenSynapse.ps1'
$uninstallPath = Join-Path $PSScriptRoot 'Uninstall-OpenSynapse.ps1'

foreach ($path in @($mainPath, $nativePath, $publishPath, $installPath, $uninstallPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing installer input: $path" }
}

$parseErrors = $null
[void][Management.Automation.Language.Parser]::ParseFile($mainPath, [ref]$null, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw "Main script parser errors: $($parseErrors.Message -join '; ')" }

$mainSource = Get-Content -LiteralPath $mainPath -Raw -Encoding UTF8
$publishSource = Get-Content -LiteralPath $publishPath -Raw -Encoding UTF8
$installSource = Get-Content -LiteralPath $installPath -Raw -Encoding UTF8
$uninstallSource = Get-Content -LiteralPath $uninstallPath -Raw -Encoding UTF8
foreach ($required in @(
    "`$script:TaskName = 'OpenSynapse'",
    "`$script:LegacyAgentTaskName = 'OpenSynapse Agent'",
    'function Register-OpenSynapseTask',
    'RunLevel Highest',
    '-ExecutionTimeLimit ([TimeSpan]::Zero)',
    '-WindowStyle Hidden -STA',
    'function Remove-LegacyDotNetRuntime',
    'function Remove-LegacyPowerPilotRuntime',
    'PowerPilot-2.4.1-migration-',
    '-File $powerPilotScript -Mode Uninstall',
    "ValidateSet('Run', 'Open', 'Install', 'Uninstall', 'Status', 'Apply', 'SelfTest')"
)) {
    if ($mainSource.IndexOf($required, [StringComparison]::Ordinal) -lt 0) {
        throw "Installer runtime definition is missing: $required"
    }
}
foreach ($required in @('src\OpenSynapse.PowerShell', 'OpenSynapse-2.4.2.zip', 'Compress-Archive')) {
    if ($publishSource.IndexOf($required, [StringComparison]::Ordinal) -lt 0) {
        throw "Publisher definition is missing: $required"
    }
}
if ($installSource.IndexOf('-Mode Install', [StringComparison]::Ordinal) -lt 0) {
    throw 'Installer wrapper does not invoke OpenSynapse Install mode.'
}
if ($uninstallSource.IndexOf('-Mode Uninstall', [StringComparison]::Ordinal) -lt 0) {
    throw 'Uninstaller wrapper does not invoke OpenSynapse Uninstall mode.'
}

$ErrorActionPreference = 'Stop'
Add-Type -Path $nativePath
if ('SetDpi' -notin [OpenSynapseNative.RazerMouse].GetMethods().Name) {
    throw 'Published native helper does not include Razer mouse control.'
}

Write-Host 'OpenSynapse PowerShell installer definitions passed.'
