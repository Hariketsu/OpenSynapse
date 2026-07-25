Set-StrictMode -Version Latest

function Test-OpenSynapseAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-OpenSynapseInstallLayout {
    param(
        [string]$ProgramFilesPath = $env:ProgramFiles,
        [string]$AppDataPath = $env:APPDATA,
        [string]$LocalAppDataPath = $env:LOCALAPPDATA
    )

    foreach ($value in @($ProgramFilesPath, $AppDataPath, $LocalAppDataPath)) {
        if ([string]::IsNullOrWhiteSpace($value)) { throw 'Windows application-data paths are unavailable.' }
    }
    $programFiles = [IO.Path]::GetFullPath($ProgramFilesPath)
    $appData = [IO.Path]::GetFullPath($AppDataPath)
    $localAppData = [IO.Path]::GetFullPath($LocalAppDataPath)
    $installDirectory = [IO.Path]::GetFullPath((Join-Path $programFiles 'OpenSynapse'))
    $shortcutPath = [IO.Path]::GetFullPath((Join-Path $appData 'Microsoft\Windows\Start Menu\Programs\OpenSynapse.lnk'))
    $dataDirectory = [IO.Path]::GetFullPath((Join-Path $localAppData 'OpenSynapse'))
    $separator = [IO.Path]::DirectorySeparatorChar
    $programFilesPrefix = $programFiles.TrimEnd($separator, [IO.Path]::AltDirectorySeparatorChar) + $separator
    $appDataPrefix = $appData.TrimEnd($separator, [IO.Path]::AltDirectorySeparatorChar) + $separator
    $localAppDataPrefix = $localAppData.TrimEnd($separator, [IO.Path]::AltDirectorySeparatorChar) + $separator
    if (-not $installDirectory.StartsWith($programFilesPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Resolved installation directory is outside Program Files.'
    }
    if (-not $shortcutPath.StartsWith($appDataPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Resolved shortcut path is outside the current user application-data directory.'
    }
    if (-not $dataDirectory.StartsWith($localAppDataPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Resolved data directory is outside the current user local application-data directory.'
    }

    return [pscustomobject]@{
        TaskName = 'OpenSynapse Agent'
        AppRunValueName = 'OpenSynapse'
        InstallDirectory = $installDirectory
        AgentDirectory = Join-Path $installDirectory 'Agent'
        AppDirectory = Join-Path $installDirectory 'App'
        AgentExecutable = Join-Path $installDirectory 'Agent\OpenSynapse.Agent.exe'
        AppExecutable = Join-Path $installDirectory 'App\OpenSynapse.App.exe'
        ShortcutPath = $shortcutPath
        DataDirectory = $dataDirectory
    }
}

function Set-OpenSynapseAppAutostart {
    param([Parameter(Mandatory)][object]$Layout)

    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    New-Item -Path $runKey -Force | Out-Null
    $quotedPath = '"' + [IO.Path]::GetFullPath($Layout.AppExecutable) + '"'
    Set-ItemProperty -Path $runKey -Name $Layout.AppRunValueName -Value $quotedPath -Type String
}

function Remove-OpenSynapseAppAutostart {
    param([Parameter(Mandatory)][object]$Layout)

    Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name $Layout.AppRunValueName -ErrorAction SilentlyContinue
}

function Get-OpenSynapseAgentTaskSpec {
    param(
        [Parameter(Mandatory)][string]$AgentExecutable,
        [Parameter(Mandatory)][string]$UserId
    )

    $agentPath = [IO.Path]::GetFullPath($AgentExecutable)
    return [pscustomobject]@{
        Execute = $agentPath
        Arguments = 'serve'
        WorkingDirectory = Split-Path -Parent $agentPath
        UserId = $UserId
        Delay = 'PT30S'
        RunLevel = 'Highest'
        AllowStartIfOnBatteries = $true
        DontStopIfGoingOnBatteries = $true
        StartWhenAvailable = $true
        MultipleInstances = 'IgnoreNew'
        ExecutionTimeLimit = [TimeSpan]::Zero
        RestartCount = 3
        RestartInterval = New-TimeSpan -Minutes 1
    }
}

function Assert-OpenSynapseTaskSpec {
    param(
        [Parameter(Mandatory)][object]$Spec,
        [Parameter(Mandatory)][string]$AgentExecutable
    )

    if (-not [string]::Equals([IO.Path]::GetFullPath($AgentExecutable), [string]$Spec.Execute, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Scheduled task specification executable is incorrect.'
    }
    if ($Spec.Arguments -ne 'serve' -or $Spec.Delay -ne 'PT30S' -or $Spec.RunLevel -ne 'Highest') {
        throw 'Scheduled task specification launch policy is incorrect.'
    }
    if (-not $Spec.AllowStartIfOnBatteries -or -not $Spec.DontStopIfGoingOnBatteries -or
        -not $Spec.StartWhenAvailable -or $Spec.MultipleInstances -ne 'IgnoreNew') {
        throw 'Scheduled task specification runtime policy is incorrect.'
    }
}

function New-OpenSynapseAgentTaskDefinition {
    param([Parameter(Mandatory)][object]$Spec)

    Import-Module ScheduledTasks -ErrorAction Stop
    $action = New-ScheduledTaskAction -Execute $Spec.Execute -Argument $Spec.Arguments -WorkingDirectory $Spec.WorkingDirectory
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $Spec.UserId
    $trigger.Delay = $Spec.Delay
    $principal = New-ScheduledTaskPrincipal -UserId $Spec.UserId -LogonType Interactive -RunLevel $Spec.RunLevel
    $settingsParameters = @{
        AllowStartIfOnBatteries = $Spec.AllowStartIfOnBatteries
        DontStopIfGoingOnBatteries = $Spec.DontStopIfGoingOnBatteries
        StartWhenAvailable = $Spec.StartWhenAvailable
        MultipleInstances = $Spec.MultipleInstances
        ExecutionTimeLimit = $Spec.ExecutionTimeLimit
        RestartCount = $Spec.RestartCount
        RestartInterval = $Spec.RestartInterval
    }
    $settings = New-ScheduledTaskSettingsSet @settingsParameters
    return New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'OpenSynapse per-user elevated policy and hardware agent.'
}

function Assert-OpenSynapseTaskDefinition {
    param(
        [Parameter(Mandatory)][object]$Task,
        [Parameter(Mandatory)][string]$AgentExecutable
    )

    $expected = [IO.Path]::GetFullPath($AgentExecutable)
    $actual = [IO.Path]::GetFullPath([string]$Task.Actions.Execute)
    if (-not [string]::Equals($expected, $actual, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Scheduled task executable verification failed.'
    }
    if ([string]$Task.Actions.Arguments -ne 'serve') { throw 'Scheduled task arguments verification failed.' }
    if ($Task.Principal.RunLevel.ToString() -ne 'Highest') { throw 'Scheduled task must use highest privileges.' }
    if ([string]$Task.Triggers[0].Delay -ne 'PT30S') { throw 'Scheduled task logon delay verification failed.' }
    if (-not $Task.Settings.AllowStartIfOnBatteries -or $Task.Settings.StopIfGoingOnBatteries) {
        throw 'Scheduled task battery behavior verification failed.'
    }
}

function Stop-OpenSynapseInstalledProcesses {
    param([Parameter(Mandatory)][string]$InstallDirectory)

    $root = [IO.Path]::GetFullPath($InstallDirectory).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $processes = @(Get-Process -Name 'OpenSynapse.Agent', 'OpenSynapse.App' -ErrorAction SilentlyContinue)
    foreach ($process in $processes) {
        try {
            $path = [IO.Path]::GetFullPath($process.Path)
            if ($path.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
                Stop-Process -Id $process.Id -Force -ErrorAction Stop
                $null = $process.WaitForExit(5000)
            }
        }
        catch [System.ComponentModel.Win32Exception] { }
    }
}

Export-ModuleMember -Function @(
    'Test-OpenSynapseAdministrator',
    'Get-OpenSynapseInstallLayout',
    'Set-OpenSynapseAppAutostart',
    'Remove-OpenSynapseAppAutostart',
    'Get-OpenSynapseAgentTaskSpec',
    'Assert-OpenSynapseTaskSpec',
    'New-OpenSynapseAgentTaskDefinition',
    'Assert-OpenSynapseTaskDefinition',
    'Stop-OpenSynapseInstalledProcesses'
)
