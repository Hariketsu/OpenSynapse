#requires -Version 5.1
#requires -RunAsAdministrator

[CmdletBinding()]
param([string]$ResultPath = '')

$ErrorActionPreference = 'Stop'
trap {
    $failure = [pscustomobject]@{ Result = 'FAIL'; Message = $_.Exception.Message; CompletedAt = (Get-Date).ToString('o') }
    if ($ResultPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath), ($failure | ConvertTo-Json), [Text.UTF8Encoding]::new($false)) }
    Write-Error $_
    break
}

Import-Module ScheduledTasks -ErrorAction Stop
$exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$installed = Join-Path $env:ProgramFiles 'OpenSynapse\OpenSynapse.ps1'
$programDir = Split-Path -Parent $installed
$identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$action = New-ScheduledTaskAction -Execute $exe -Argument ('-NoProfile -WindowStyle Hidden -STA -ExecutionPolicy Bypass -File "{0}" -Mode Run' -f $installed) -WorkingDirectory $programDir
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $identity
$trigger.Delay = 'PT30S'
$principal = New-ScheduledTaskPrincipal -UserId $identity -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
$task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings

$result = [pscustomobject]@{
    Result = 'PASS'
    ActionOk = ($task.Actions.Execute -eq $exe)
    InstalledPathProtected = ($task.Actions.Arguments -like "*$installed*")
    RunLevel = $task.Principal.RunLevel.ToString()
    LogonType = $task.Principal.LogonType.ToString()
    UserId = $task.Principal.UserId
    LogonDelay = [string]$task.Triggers[0].Delay
    AllowBattery = -not [bool]$task.Settings.DisallowStartIfOnBatteries
    DontStopOnBattery = -not [bool]$task.Settings.StopIfGoingOnBatteries
    ExecutionLimit = $task.Settings.ExecutionTimeLimit.ToString()
    MultipleInstances = $task.Settings.MultipleInstances.ToString()
    RegisteredOrChangedSystem = $false
    CompletedAt = (Get-Date).ToString('o')
}
if (-not ($result.ActionOk -and $result.InstalledPathProtected -and $result.RunLevel -eq 'Highest' -and $result.LogonDelay -eq 'PT30S' -and $result.AllowBattery -and $result.DontStopOnBattery)) { throw 'Scheduled task definition verification failed.' }
if ($ResultPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath), ($result | ConvertTo-Json), [Text.UTF8Encoding]::new($false)) }
$result | Format-List
