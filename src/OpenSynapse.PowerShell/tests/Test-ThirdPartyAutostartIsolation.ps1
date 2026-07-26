#requires -Version 5.1

[CmdletBinding()]
param([string]$ResultPath = '')

$ErrorActionPreference = 'Stop'
trap {
    $failure = [pscustomobject]@{ Result = 'FAIL'; Message = $_.Exception.Message; CompletedAt = (Get-Date).ToString('o') }
    if ($ResultPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath), ($failure | ConvertTo-Json), [Text.UTF8Encoding]::new($false)) }
    Write-Error $_
    break
}

$mainScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'OpenSynapse.ps1'
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($mainScript, [ref]$tokens, [ref]$errors)
if ($errors.Count -gt 0) { throw "Parser errors: $($errors.Message -join '; ')" }

$functionNames = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Name })
$requiredFunctions = @(
    'Get-InstalledOpenSynapseVersion',
    'Test-StartupCommandEqualsExecutable',
    'Test-SnipasteStoreAutostartEnabled',
    'Remove-OpenSynapse201DuplicateSnipasteAutostart'
)
$legacyFunctions = @('Get-CompanionAutostartDefinitions', 'Repair-CompanionAutostarts')
$migrationFunction = $ast.Find({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq 'Remove-OpenSynapse201DuplicateSnipasteAutostart'
}, $true)
if ($null -eq $migrationFunction) { throw 'The safe Snipaste migration function is missing.' }

$migrationSource = $migrationFunction.Extent.Text
$source = Get-Content -LiteralPath $mainScript -Raw -Encoding UTF8
$defaultsSource = ($ast.Find({
    param($node)
    $node -is [Management.Automation.Language.AssignmentStatementAst] -and
        $node.Left.Extent.Text -eq '$script:DefaultQuietProcesses'
}, $true)).Extent.Text

$result = [pscustomobject]@{
    Result = 'PASS'
    RequiredFunctionsPresent = @($requiredFunctions | Where-Object { $functionNames -contains $_ }).Count -eq $requiredFunctions.Count
    LegacyTakeoverFunctionsRemoved = @($legacyFunctions | Where-Object { $functionNames -contains $_ }).Count -eq 0
    StartupApprovedUntouched = ($source -notmatch 'StartupApproved')
    UpgradeSourceGuardPresent = ($migrationSource -match "PreviousVersion.+2\.0\.1")
    MigrationDoesNotReferenceFlClash = ($migrationSource -notmatch 'FlClash')
    MigrationOnlyRemovesSnipaste = ($migrationSource -match "Remove-ItemProperty[^\r\n]+-Name\s+'Snipaste'")
    ThirdPartyAppsProtectedFromQuiet = ($defaultsSource -notmatch 'FlClash|Snipaste')
    ChangedRegistry = $false
    CompletedAt = (Get-Date).ToString('o')
}

if (-not ($result.RequiredFunctionsPresent -and $result.LegacyTakeoverFunctionsRemoved -and
    $result.StartupApprovedUntouched -and $result.UpgradeSourceGuardPresent -and $result.MigrationDoesNotReferenceFlClash -and
    $result.MigrationOnlyRemovesSnipaste -and $result.ThirdPartyAppsProtectedFromQuiet)) {
    throw 'Third-party autostart isolation verification failed.'
}
if ($ResultPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath), ($result | ConvertTo-Json), [Text.UTF8Encoding]::new($false)) }
$result | Format-List
