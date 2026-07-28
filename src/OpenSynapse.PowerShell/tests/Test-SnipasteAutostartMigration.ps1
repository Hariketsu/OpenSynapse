#requires -Version 5.1

[CmdletBinding()]
param([string]$ResultPath = '')

$ErrorActionPreference = 'Stop'
$testId = "OpenSynapse.AutostartMigrationTest.$PID"
$testRoot = "HKCU:\Software\OpenSynapse\Tests\$testId"
$testRunKey = Join-Path $testRoot 'Run'
$testStoreKey = Join-Path $testRoot 'SnipasteStartupTask'
$testApprovedKey = Join-Path $testRoot 'StartupApproved'
$testFiles = Join-Path $env:TEMP $testId

trap {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $testFiles -Recurse -Force -ErrorAction SilentlyContinue
    $failure = [pscustomobject]@{ Result = 'FAIL'; Message = $_.Exception.Message; CleanupComplete = (-not (Test-Path -LiteralPath $testRoot)); CompletedAt = (Get-Date).ToString('o') }
    if ($ResultPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath), ($failure | ConvertTo-Json), [Text.UTF8Encoding]::new($false)) }
    Write-Error $_
    break
}

$mainScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'OpenSynapse.ps1'
. $mainScript -Mode SelfTest

function Reset-TestRegistry {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -Path $testRoot -Force | Out-Null
}

try {
    [IO.Directory]::CreateDirectory($testFiles) | Out-Null
    $installedScriptPath = Join-Path $testFiles 'Installed-OpenSynapse.ps1'
    [IO.File]::WriteAllText($installedScriptPath, '$script:AppVersion = ''2.0.1''', [Text.UTF8Encoding]::new($false))
    $script:InstalledScript = $installedScriptPath
    $detectedPreviousVersion = Get-InstalledOpenSynapseVersion
    $desktopSnipastePath = Join-Path $testFiles 'Snipaste.exe'
    [IO.File]::WriteAllText($desktopSnipastePath, '')
    $script:RunKey = $testRunKey
    $script:SnipasteStoreStartupTaskKey = $testStoreKey
    $script:DesktopSnipasteExecutable = $desktopSnipastePath

    Reset-TestRegistry
    New-Item -Path $testRunKey -Force | Out-Null
    New-ItemProperty -Path $testRunKey -Name 'FlClash' -Value 'C:\Program Files\FlClash\FlClash.exe' -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $testRunKey -Name 'Snipaste' -Value ('"{0}"' -f $desktopSnipastePath) -PropertyType String -Force | Out-Null
    New-Item -Path $testStoreKey -Force | Out-Null
    New-ItemProperty -Path $testStoreKey -Name 'State' -Value 2 -PropertyType DWord -Force | Out-Null
    New-Item -Path $testApprovedKey -Force | Out-Null
    New-ItemProperty -Path $testApprovedKey -Name 'FlClash' -Value ([byte[]](3, 0, 0, 0)) -PropertyType Binary -Force | Out-Null
    New-ItemProperty -Path $testApprovedKey -Name 'Snipaste' -Value ([byte[]](3, 0, 0, 0)) -PropertyType Binary -Force | Out-Null

    $enabledResult = Remove-OpenSynapse201DuplicateSnipasteAutostart -PreviousVersion '2.0.1'
    $runAfterEnabled = Get-ItemProperty -LiteralPath $testRunKey
    $approvedAfterEnabled = Get-ItemProperty -LiteralPath $testApprovedKey
    $enabledStoreState = (Get-ItemProperty -LiteralPath $testStoreKey).State
    $duplicateRemoved = ($null -eq $runAfterEnabled.PSObject.Properties['Snipaste'])
    $flClashPreserved = ([string]$runAfterEnabled.FlClash -eq 'C:\Program Files\FlClash\FlClash.exe')
    $approvalsPreserved = (
        $null -ne $approvedAfterEnabled.PSObject.Properties['FlClash'] -and
        $null -ne $approvedAfterEnabled.PSObject.Properties['Snipaste']
    )

    Reset-TestRegistry
    New-Item -Path $testRunKey -Force | Out-Null
    New-ItemProperty -Path $testRunKey -Name 'Snipaste' -Value ('"{0}"' -f $desktopSnipastePath) -PropertyType String -Force | Out-Null
    New-Item -Path $testStoreKey -Force | Out-Null
    New-ItemProperty -Path $testStoreKey -Name 'State' -Value 0 -PropertyType DWord -Force | Out-Null
    $disabledResult = Remove-OpenSynapse201DuplicateSnipasteAutostart -PreviousVersion '2.0.1'
    $disabledStorePreserved = $null -ne (Get-ItemProperty -LiteralPath $testRunKey).PSObject.Properties['Snipaste']

    Reset-TestRegistry
    New-Item -Path $testRunKey -Force | Out-Null
    $customCommand = ('"{0}" --custom' -f $desktopSnipastePath)
    New-ItemProperty -Path $testRunKey -Name 'Snipaste' -Value $customCommand -PropertyType String -Force | Out-Null
    New-Item -Path $testStoreKey -Force | Out-Null
    New-ItemProperty -Path $testStoreKey -Name 'State' -Value 2 -PropertyType DWord -Force | Out-Null
    $customResult = Remove-OpenSynapse201DuplicateSnipasteAutostart -PreviousVersion '2.0.1'
    $customCommandPreserved = ([string](Get-ItemProperty -LiteralPath $testRunKey).Snipaste -eq $customCommand)

    Reset-TestRegistry
    New-Item -Path $testRunKey -Force | Out-Null
    New-ItemProperty -Path $testRunKey -Name 'Snipaste' -Value ('"{0}"' -f $desktopSnipastePath) -PropertyType String -Force | Out-Null
    New-Item -Path $testStoreKey -Force | Out-Null
    New-ItemProperty -Path $testStoreKey -Name 'State' -Value 2 -PropertyType DWord -Force | Out-Null
    $non201Result = Remove-OpenSynapse201DuplicateSnipasteAutostart -PreviousVersion '2.0.0'
    $non201EntryPreserved = $null -ne (Get-ItemProperty -LiteralPath $testRunKey).PSObject.Properties['Snipaste']

    Reset-TestRegistry
    New-Item -Path $testStoreKey -Force | Out-Null
    New-ItemProperty -Path $testStoreKey -Name 'State' -Value 2 -PropertyType DWord -Force | Out-Null
    $missingRunResult = Remove-OpenSynapse201DuplicateSnipasteAutostart -PreviousVersion '2.0.1'
    $missingRunKeyNotCreated = -not (Test-Path -LiteralPath $testRunKey)

    if (-not ($detectedPreviousVersion -eq '2.0.1' -and
        $enabledResult.DesktopRunEntryRemoved -and $duplicateRemoved -and $flClashPreserved -and
        $approvalsPreserved -and $enabledStoreState -eq 2 -and
        -not $disabledResult.DesktopRunEntryRemoved -and $disabledStorePreserved -and
        -not $customResult.DesktopRunEntryRemoved -and $customCommandPreserved -and
        -not $non201Result.DesktopRunEntryRemoved -and $non201EntryPreserved -and
        -not $missingRunResult.DesktopRunEntryRemoved -and $missingRunKeyNotCreated)) {
        throw 'Safe Snipaste autostart migration round trip failed.'
    }

    $result = [pscustomobject]@{
        Result = 'PASS'
        InstalledVersionDetected = $detectedPreviousVersion
        EnabledStoreDuplicateRemoved = $true
        StoreStartupTaskPreserved = $true
        FlClashPreserved = $true
        StartupApprovedPreserved = $true
        DisabledStoreDesktopEntryPreserved = $true
        CustomCommandPreserved = $true
        Non201UpgradePreserved = $true
        MissingRunKeyNotCreated = $true
        UsedTemporaryRegistry = $true
        CompletedAt = (Get-Date).ToString('o')
    }
}
finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $testFiles -Recurse -Force -ErrorAction SilentlyContinue
}

if (Test-Path -LiteralPath $testRoot) { throw 'Temporary registry cleanup failed.' }
if (Test-Path -LiteralPath $testFiles) { throw 'Temporary file cleanup failed.' }
if ($ResultPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath), ($result | ConvertTo-Json), [Text.UTF8Encoding]::new($false)) }
$result | Format-List
