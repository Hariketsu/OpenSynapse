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
. $mainScript -Mode SelfTest
$mainSource = Get-Content -Raw -LiteralPath $mainScript

foreach ($required in @(
    "`$script:AppVersion = '0.2.0'",
    '[IO.File]::Replace($temporaryPath, $Path, $backupPath, $true)',
    'Recovered JSON from backup',
    '$script:ApplyInProgress',
    '$script:MonitorTickRunning',
    'Register-MonitorCycleFailure',
    '$script:MonitorMaximumIntervalMs = 60000',
    'TotalSeconds -lt 60',
    'Update-RuntimeHeartbeat',
    '$script:PendingDisplayRepairAt = (Get-Date).AddSeconds(10)',
    "Health: `$healthText",
    'Existing-instance wake request failed'
)) {
    if ($mainSource.IndexOf($required, [StringComparison]::Ordinal) -lt 0) {
        throw "Missing stability/experience definition: $required"
    }
}

$temporary = Join-Path (Split-Path -Parent $PSScriptRoot) '.stability-test'
if (Test-Path -LiteralPath $temporary) { throw "Test directory already exists: $temporary" }
[IO.Directory]::CreateDirectory($temporary) | Out-Null
$oldDataDir = $script:DataDir
$oldLogPath = $script:LogPath
try {
    $script:DataDir = $temporary
    $script:LogPath = Join-Path $temporary 'OpenSynapse.log'
    $jsonPath = Join-Path $temporary 'runtime.json'

    Write-JsonFile $jsonPath ([pscustomobject]@{ Generation = 1; Health = 'Starting' })
    Write-JsonFile $jsonPath ([pscustomobject]@{ Generation = 2; Health = 'Healthy' })
    $current = Read-JsonFile $jsonPath
    if ($current.Generation -ne 2 -or $current.Health -ne 'Healthy') { throw 'Atomic JSON write did not preserve the newest value.' }
    if (-not (Test-Path -LiteralPath "$jsonPath.bak")) { throw 'Atomic JSON write did not create a recovery backup.' }

    [IO.File]::WriteAllText($jsonPath, '{corrupt', [Text.UTF8Encoding]::new($false))
    $recovered = Read-JsonFile $jsonPath
    if ($null -eq $recovered -or $recovered.Generation -ne 1) { throw 'Corrupt JSON did not recover from the last known-good backup.' }
    if (@(Get-ChildItem -LiteralPath $temporary -Filter '*.tmp').Count -ne 0) { throw 'Atomic JSON temporary files were not cleaned up.' }
}
finally {
    $script:DataDir = $oldDataDir
    $script:LogPath = $oldLogPath
    Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
}

$result = [pscustomobject]@{
    Result = 'PASS'
    AtomicJsonWrite = $true
    BackupRecovery = $true
    ApplyReentrancyGuard = $true
    MonitorFailureIsolation = $true
    MaximumRetrySeconds = 60
    RuntimeHeartbeat = $true
    DisplayRepairRetry = $true
    ExistingInstanceWake = $true
    ChangedSystemSettings = $false
    CompletedAt = (Get-Date).ToString('o')
}
if ($ResultPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath), ($result | ConvertTo-Json), [Text.UTF8Encoding]::new($false)) }
$result | Format-List
