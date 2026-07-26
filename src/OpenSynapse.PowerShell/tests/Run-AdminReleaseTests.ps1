#requires -Version 5.1
#requires -RunAsAdministrator

[CmdletBinding()]
param([string]$ResultDirectory = '')

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ResultDirectory)) { $ResultDirectory = Join-Path $PSScriptRoot 'results' }
$ResultDirectory = [IO.Path]::GetFullPath($ResultDirectory)
[IO.Directory]::CreateDirectory($ResultDirectory) | Out-Null

$tests = @(
    [pscustomobject]@{ Name = 'config-migration'; Script = 'Test-ConfigMigration.ps1' },
    [pscustomobject]@{ Name = 'icon-assets'; Script = 'Test-IconAssets.ps1' },
    [pscustomobject]@{ Name = 'taskbar-identity'; Script = 'Test-TaskbarIdentity.ps1' },
    [pscustomobject]@{ Name = 'dark-theme-definition'; Script = 'Test-DarkThemeDefinition.ps1' },
    [pscustomobject]@{ Name = 'razer-mouse-definition'; Script = 'Test-RazerMouseDefinition.ps1' },
    [pscustomobject]@{ Name = 'synapse-shell-definition'; Script = 'Test-SynapseShellDefinition.ps1' },
    [pscustomobject]@{ Name = 'smart-automation'; Script = 'Test-SmartAutomation.ps1' },
    [pscustomobject]@{ Name = 'automation-guards'; Script = 'Test-AutomationGuards.ps1' },
    [pscustomobject]@{ Name = 'safe-telemetry-automation'; Script = 'Test-SafeTelemetryAutomation.ps1' },
    [pscustomobject]@{ Name = 'battery-telemetry-trend'; Script = 'Test-BatteryTelemetryTrend.ps1' },
    [pscustomobject]@{ Name = 'stability-experience'; Script = 'Test-StabilityExperience.ps1' },
    [pscustomobject]@{ Name = 'power-policy-definition'; Script = 'Test-PowerPolicyDefinition.ps1' },
    [pscustomobject]@{ Name = 'hyper-performance'; Script = 'Test-HyperPerformance.ps1' },
    [pscustomobject]@{ Name = 'quiet-endurance'; Script = 'Test-QuietEndurance.ps1' },
    [pscustomobject]@{ Name = 'supply-refresh-definition'; Script = 'Test-SupplyRefreshDefinition.ps1' },
    [pscustomobject]@{ Name = 'supply-debounce'; Script = 'Test-SupplyDebounce.ps1' },
    [pscustomobject]@{ Name = 'power-event-coalescing'; Script = 'Test-PowerEventCoalescing.ps1' },
    [pscustomobject]@{ Name = 'scheduled-task-delay-definition'; Script = 'Test-ScheduledTaskDelayDefinition.ps1' },
    [pscustomobject]@{ Name = 'third-party-autostart-isolation'; Script = 'Test-ThirdPartyAutostartIsolation.ps1' },
    [pscustomobject]@{ Name = 'snipaste-autostart-migration'; Script = 'Test-SnipasteAutostartMigration.ps1' },
    [pscustomobject]@{ Name = 'scheduled-task-definition'; Script = 'Test-ScheduledTaskDefinition.ps1' },
    [pscustomobject]@{ Name = 'scheduled-task-roundtrip'; Script = 'Test-ScheduledTaskRoundTrip.ps1' },
    [pscustomobject]@{ Name = 'power-plan-roundtrip'; Script = 'Test-PowerPlanRoundTrip.ps1' }
)

$records = New-Object Collections.Generic.List[object]
foreach ($test in $tests) {
    $resultPath = Join-Path $ResultDirectory ($test.Name + '.json')
    Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue
    & (Join-Path $PSScriptRoot $test.Script) -ResultPath $resultPath
    if (-not (Test-Path -LiteralPath $resultPath)) { throw "$($test.Name) did not produce a result file." }
    $record = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    if ([string]$record.Result -ne 'PASS') { throw "$($test.Name) failed: $($record.Message)" }
    $records.Add([pscustomobject]@{ Name = $test.Name; Result = [string]$record.Result; ResultPath = $resultPath })
}

$summary = [pscustomobject]@{
    Result = 'PASS'
    Version = '2.4.1'
    Tests = $records.ToArray()
    CompletedAt = (Get-Date).ToString('o')
}
$summaryPath = Join-Path $ResultDirectory 'admin-release-tests.json'
[IO.File]::WriteAllText($summaryPath, ($summary | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
$summary | Format-List
