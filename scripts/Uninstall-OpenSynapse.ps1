[CmdletBinding()]
param([switch]$KeepUserData)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'OpenSynapse.Install.psm1') -Force
if (-not (Test-OpenSynapseAdministrator)) { throw 'Run the uninstaller from an elevated PowerShell terminal.' }

$layout = Get-OpenSynapseInstallLayout
Remove-OpenSynapseAppAutostart -Layout $layout
$task = Get-ScheduledTask -TaskName $layout.TaskName -ErrorAction SilentlyContinue
if ($null -ne $task) { Stop-ScheduledTask -TaskName $layout.TaskName -ErrorAction SilentlyContinue }
Stop-OpenSynapseInstalledProcesses -InstallDirectory $layout.InstallDirectory

if (Test-Path -LiteralPath $layout.AgentExecutable -PathType Leaf) {
    & $layout.AgentExecutable uninstall-cleanup
    if ($LASTEXITCODE -ne 0) {
        throw 'Captured state or managed power plans could not be restored; uninstall was stopped and files were preserved.'
    }
}
elseif (Test-Path -LiteralPath (Join-Path $layout.DataDirectory 'state.json') -PathType Leaf) {
    throw 'Captured state exists but the cleanup agent is missing; repair the installation before uninstalling.'
}

Unregister-ScheduledTask -TaskName $layout.TaskName -Confirm:$false -ErrorAction SilentlyContinue
if (Get-ScheduledTask -TaskName $layout.TaskName -ErrorAction SilentlyContinue) {
    throw 'Scheduled task removal verification failed.'
}
Remove-Item -LiteralPath $layout.ShortcutPath -Force -ErrorAction SilentlyContinue
if (Test-Path -LiteralPath $layout.InstallDirectory) {
    Remove-Item -LiteralPath $layout.InstallDirectory -Recurse -Force
}
if (-not $KeepUserData -and (Test-Path -LiteralPath $layout.DataDirectory)) {
    Remove-Item -LiteralPath $layout.DataDirectory -Recurse -Force
}

Write-Host 'OpenSynapse was removed after confirmed state restoration.'
