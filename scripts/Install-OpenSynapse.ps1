[CmdletBinding()]
param([string]$SourceDirectory)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'OpenSynapse.Install.psm1') -Force
if (-not (Test-OpenSynapseAdministrator)) { throw 'Run the installer from an elevated PowerShell terminal.' }

$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($SourceDirectory)) {
    $SourceDirectory = Join-Path $root 'artifacts\publish'
}
$source = [IO.Path]::GetFullPath($SourceDirectory)
$sourceAgent = Join-Path $source 'Agent\OpenSynapse.Agent.exe'
$sourceApp = Join-Path $source 'App\OpenSynapse.App.exe'
if (-not (Test-Path -LiteralPath $sourceAgent -PathType Leaf) -or -not (Test-Path -LiteralPath $sourceApp -PathType Leaf)) {
    throw 'Publish output is incomplete. Run scripts\Publish-OpenSynapse.ps1 first.'
}

$layout = Get-OpenSynapseInstallLayout
$separator = [IO.Path]::DirectorySeparatorChar
$installPrefix = $layout.InstallDirectory.TrimEnd($separator, [IO.Path]::AltDirectorySeparatorChar) + $separator
$sourcePrefix = $source.TrimEnd($separator, [IO.Path]::AltDirectorySeparatorChar) + $separator
if ($sourcePrefix.StartsWith($installPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Publish output must be outside the installation directory.'
}

$existingTask = Get-ScheduledTask -TaskName $layout.TaskName -ErrorAction SilentlyContinue
if ($null -ne $existingTask) { Stop-ScheduledTask -TaskName $layout.TaskName -ErrorAction SilentlyContinue }
Stop-OpenSynapseInstalledProcesses -InstallDirectory $layout.InstallDirectory
if (Test-Path -LiteralPath $layout.AgentExecutable -PathType Leaf) {
    & $layout.AgentExecutable uninstall-cleanup
    if ($LASTEXITCODE -ne 0) {
        throw 'Existing installation could not restore captured state and remove its managed power plans; upgrade was stopped.'
    }
}

foreach ($directory in @($layout.AgentDirectory, $layout.AppDirectory)) {
    if (Test-Path -LiteralPath $directory) { Remove-Item -LiteralPath $directory -Recurse -Force }
}
[IO.Directory]::CreateDirectory($layout.AgentDirectory) | Out-Null
[IO.Directory]::CreateDirectory($layout.AppDirectory) | Out-Null
Copy-Item -Path (Join-Path $source 'Agent\*') -Destination $layout.AgentDirectory -Recurse -Force
Copy-Item -Path (Join-Path $source 'App\*') -Destination $layout.AppDirectory -Recurse -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'OpenSynapse.Install.psm1') -Destination $layout.InstallDirectory -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Uninstall-OpenSynapse.ps1') -Destination $layout.InstallDirectory -Force

$identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$taskSpec = Get-OpenSynapseAgentTaskSpec -AgentExecutable $layout.AgentExecutable -UserId $identity
Assert-OpenSynapseTaskSpec -Spec $taskSpec -AgentExecutable $layout.AgentExecutable
$task = New-OpenSynapseAgentTaskDefinition -Spec $taskSpec
Assert-OpenSynapseTaskDefinition -Task $task -AgentExecutable $layout.AgentExecutable
Register-ScheduledTask -TaskName $layout.TaskName -InputObject $task -Force | Out-Null
$registered = Get-ScheduledTask -TaskName $layout.TaskName -ErrorAction Stop
Assert-OpenSynapseTaskDefinition -Task $registered -AgentExecutable $layout.AgentExecutable

$shell = New-Object -ComObject WScript.Shell
try {
    $shortcut = $shell.CreateShortcut($layout.ShortcutPath)
    $shortcut.TargetPath = $layout.AppExecutable
    $shortcut.WorkingDirectory = $layout.AppDirectory
    $shortcut.Description = 'Open the OpenSynapse control panel'
    $shortcut.IconLocation = $layout.AppExecutable + ',0'
    $shortcut.Save()
}
finally { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell) }
if (-not (Test-Path -LiteralPath $layout.ShortcutPath -PathType Leaf)) { throw 'Start menu shortcut verification failed.' }

Set-OpenSynapseAppAutostart -Layout $layout

Start-ScheduledTask -TaskName $layout.TaskName
Write-Host "OpenSynapse installed at $($layout.InstallDirectory)."
