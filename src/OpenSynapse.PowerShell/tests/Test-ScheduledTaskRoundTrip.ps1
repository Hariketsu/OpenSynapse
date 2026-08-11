#requires -Version 5.1
#requires -RunAsAdministrator

[CmdletBinding()]
param([string]$ResultPath = '')

$ErrorActionPreference = 'Stop'
$testName = "OpenSynapse Release Test $PID"
$registered = $false

trap {
    Unregister-ScheduledTask -TaskName $testName -Confirm:$false -ErrorAction SilentlyContinue
    $failure = [pscustomobject]@{ Result = 'FAIL'; Message = $_.Exception.Message; TaskRemoved = (-not [bool](Get-ScheduledTask -TaskName $testName -ErrorAction SilentlyContinue)); CompletedAt = (Get-Date).ToString('o') }
    if ($ResultPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath), ($failure | ConvertTo-Json), [Text.UTF8Encoding]::new($false)) }
    Write-Error $_
    break
}

Import-Module ScheduledTasks -ErrorAction Stop
$exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$installed = Join-Path $env:ProgramFiles 'OpenSynapse\OpenSynapse.ps1'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$action = New-ScheduledTaskAction -Execute $exe -Argument ('-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -STA -ExecutionPolicy Bypass -File "{0}" -Mode Run -SilentStartup' -f $installed) -WorkingDirectory (Split-Path -Parent $installed)
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $identity
$trigger.Delay = 'PT30S'
$principal = New-ScheduledTaskPrincipal -UserId $identity -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
$definition = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'Temporary OpenSynapse registration test.'

try {
    Register-ScheduledTask -TaskName $testName -InputObject $definition -Force | Out-Null
    $registered = $true
    $actual = Get-ScheduledTask -TaskName $testName -ErrorAction Stop
    if ($actual.Principal.RunLevel.ToString() -ne 'Highest') { throw 'Registered task lost its highest run level.' }
    if ($actual.Actions.Arguments -notlike "*$installed*") { throw 'Registered task lost its protected action path.' }
    if ($actual.Actions.Arguments -notlike '*-SilentStartup*') { throw 'Registered task lost its silent-startup switch.' }
    if ([string]$actual.Triggers[0].Delay -ne 'PT30S') { throw 'Registered task lost its 30-second logon delay.' }
}
finally {
    Unregister-ScheduledTask -TaskName $testName -Confirm:$false -ErrorAction SilentlyContinue
}

$removed = -not [bool](Get-ScheduledTask -TaskName $testName -ErrorAction SilentlyContinue)
if (-not ($registered -and $removed)) { throw 'Temporary task registration or cleanup verification failed.' }
$result = [pscustomobject]@{ Result = 'PASS'; Registered = $registered; HighestRunLevel = $true; ProtectedActionPath = $true; SilentStartup = $true; LogonDelay = 'PT30S'; TaskRemoved = $removed; CompletedAt = (Get-Date).ToString('o') }
if ($ResultPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath), ($result | ConvertTo-Json), [Text.UTF8Encoding]::new($false)) }
$result | Format-List
