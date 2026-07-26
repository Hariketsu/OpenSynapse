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

$delayAssignments = @($ast.FindAll({
    param($node)
    $node -is [Management.Automation.Language.AssignmentStatementAst] -and
        $node.Left.Extent.Text -eq '$trigger.Delay' -and
        $node.Right.Extent.Text -eq "'PT30S'"
}, $true))
$source = Get-Content -LiteralPath $mainScript -Raw
$registrationVerification = $source -match "registered\.Triggers\[0\]\.Delay\s+-ne\s+'PT30S'"

$result = [pscustomobject]@{
    Result = 'PASS'
    DelayAssignmentCount = $delayAssignments.Count
    DelayValue = if ($delayAssignments.Count -eq 1) { 'PT30S' } else { '' }
    RegistrationVerificationPresent = $registrationVerification
    RegisteredOrChangedTask = $false
    CompletedAt = (Get-Date).ToString('o')
}
if (-not ($result.DelayAssignmentCount -eq 1 -and $result.DelayValue -eq 'PT30S' -and $result.RegistrationVerificationPresent)) {
    throw 'Scheduled task delay definition verification failed.'
}
if ($ResultPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath), ($result | ConvertTo-Json), [Text.UTF8Encoding]::new($false)) }
$result | Format-List
