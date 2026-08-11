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
$silentTaskAction = $source.IndexOf('-Mode Run -SilentStartup', [StringComparison]::Ordinal) -ge 0
$headlessMessageLoop = $source.IndexOf('New-Object Windows.Forms.ApplicationContext', [StringComparison]::Ordinal) -ge 0 -and
    $source.IndexOf('[Windows.Forms.Application]::Run($applicationContext)', [StringComparison]::Ordinal) -ge 0
$legacyVisibleMessageLoop = $source.IndexOf('[Windows.Forms.Application]::Run($script:Form)', [StringComparison]::Ordinal) -ge 0

$result = [pscustomobject]@{
    Result = 'PASS'
    DelayAssignmentCount = $delayAssignments.Count
    DelayValue = if ($delayAssignments.Count -eq 1) { 'PT30S' } else { '' }
    RegistrationVerificationPresent = $registrationVerification
    SilentTaskAction = $silentTaskAction
    HeadlessMessageLoop = $headlessMessageLoop
    LegacyVisibleMessageLoop = $legacyVisibleMessageLoop
    RegisteredOrChangedTask = $false
    CompletedAt = (Get-Date).ToString('o')
}
if (-not ($result.DelayAssignmentCount -eq 1 -and $result.DelayValue -eq 'PT30S' -and $result.RegistrationVerificationPresent -and
    $result.SilentTaskAction -and $result.HeadlessMessageLoop -and -not $result.LegacyVisibleMessageLoop)) {
    throw 'Scheduled task delay definition verification failed.'
}
if ($ResultPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath), ($result | ConvertTo-Json), [Text.UTF8Encoding]::new($false)) }
$result | Format-List
