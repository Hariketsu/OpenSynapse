[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'OpenSynapse.Install.psm1') -Force
$layout = Get-OpenSynapseInstallLayout -ProgramFilesPath 'C:\Program Files' -AppDataPath 'C:\Users\Test\AppData\Roaming' -LocalAppDataPath 'C:\Users\Test\AppData\Local'
$taskSpec = Get-OpenSynapseAgentTaskSpec -AgentExecutable $layout.AgentExecutable -UserId 'DOMAIN\TestUser'
Assert-OpenSynapseTaskSpec -Spec $taskSpec -AgentExecutable $layout.AgentExecutable

if ($layout.InstallDirectory -ne 'C:\Program Files\OpenSynapse') { throw 'Install directory definition is incorrect.' }
if ($layout.ShortcutPath -ne 'C:\Users\Test\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\OpenSynapse.lnk') {
    throw 'Shortcut definition is incorrect.'
}
$installSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Install-OpenSynapse.ps1') -Raw
$uninstallSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Uninstall-OpenSynapse.ps1') -Raw
foreach ($required in @('uninstall-cleanup', 'Remove-Item', 'Register-ScheduledTask', 'Assert-OpenSynapseTaskDefinition', 'OpenSynapse.App.exe', 'Set-OpenSynapseAppAutostart')) {
    if ($installSource.IndexOf($required, [StringComparison]::Ordinal) -lt 0) { throw "Installer is missing $required." }
}
foreach ($required in @('uninstall-cleanup', 'Unregister-ScheduledTask', 'KeepUserData', 'Remove-OpenSynapseAppAutostart')) {
    if ($uninstallSource.IndexOf($required, [StringComparison]::Ordinal) -lt 0) { throw "Uninstaller is missing $required." }
}

Write-Host 'Installer definitions passed.'
