[CmdletBinding()]
param(
    [switch]$TestMouseWrites,
    [switch]$AdminRelease
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$project = Join-Path $root 'src\OpenSynapse.PowerShell'
$tests = Join-Path $project 'tests'
$resultDirectory = Join-Path $root 'artifacts\test-results\PowerShell'
[IO.Directory]::CreateDirectory($resultDirectory) | Out-Null

$definitionTests = @(
    'Test-ConfigMigration.ps1',
    'Test-IconAssets.ps1',
    'Test-TaskbarIdentity.ps1',
    'Test-DarkThemeDefinition.ps1',
    'Test-RazerMouseDefinition.ps1',
    'Test-SynapseShellDefinition.ps1',
    'Test-SmartAutomation.ps1',
    'Test-AutomationGuards.ps1',
    'Test-SafeTelemetryAutomation.ps1',
    'Test-BatteryTelemetryTrend.ps1',
    'Test-StabilityExperience.ps1',
    'Test-PowerPolicyDefinition.ps1',
    'Test-HyperPerformance.ps1',
    'Test-QuietEndurance.ps1',
    'Test-SupplyRefreshDefinition.ps1',
    'Test-SupplyDebounce.ps1',
    'Test-PowerEventCoalescing.ps1',
    'Test-ScheduledTaskDelayDefinition.ps1',
    'Test-ThirdPartyAutostartIsolation.ps1',
    'Test-SnipasteAutostartMigration.ps1'
)

foreach ($testName in $definitionTests) {
    $testPath = Join-Path $tests $testName
    $resultPath = Join-Path $resultDirectory ([IO.Path]::GetFileNameWithoutExtension($testName) + '.json')
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $testPath -ResultPath $resultPath
    if ($LASTEXITCODE -ne 0) { throw "$testName failed with exit code $LASTEXITCODE." }
    $record = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    if ([string]$record.Result -ne 'PASS') { throw "$testName failed: $($record.Message)" }
}

if ($TestMouseWrites) {
    $nativePath = Join-Path $project 'OpenSynapse.Native.cs'
    Add-Type -Path $nativePath
    $mouse = @([OpenSynapseNative.RazerMouse]::GetDevices()) | Select-Object -First 1
    if ($null -eq $mouse -or $null -eq $mouse.DpiX -or $null -eq $mouse.PollingRate) {
        throw 'A readable DeathAdder V3 Pro is required for mouse write verification.'
    }
    [OpenSynapseNative.RazerMouse]::SetDpi([int]$mouse.DpiX, [int]$mouse.DpiY)
    [OpenSynapseNative.RazerMouse]::SetPollingRate([int]$mouse.PollingRate)
    Write-Host "Razer mouse write round-trip passed: $($mouse.DpiX)x$($mouse.DpiY) DPI, $($mouse.PollingRate) Hz."
}

if ($AdminRelease) {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run -AdminRelease from an elevated PowerShell terminal.'
    }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $tests 'Run-AdminReleaseTests.ps1') `
        -ResultDirectory (Join-Path $resultDirectory 'admin')
    if ($LASTEXITCODE -ne 0) { throw "Administrator release tests failed with exit code $LASTEXITCODE." }
}

Write-Host "OpenSynapse PowerShell milestone tests passed: $($definitionTests.Count) definition/runtime tests." -ForegroundColor Green
