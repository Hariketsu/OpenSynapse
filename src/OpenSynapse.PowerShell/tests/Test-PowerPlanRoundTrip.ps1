#requires -Version 5.1
#requires -RunAsAdministrator

[CmdletBinding()]
param([string]$ResultPath = '')

$ErrorActionPreference = 'Stop'
trap {
    $failure = [pscustomobject]@{
        Result = 'FAIL'
        Message = $_.Exception.Message
        Position = $_.InvocationInfo.PositionMessage
        CompletedAt = (Get-Date).ToString('o')
    }
    if (-not [string]::IsNullOrWhiteSpace($ResultPath)) {
        [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath), ($failure | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    }
    Write-Error $_
    break
}

$mainScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'OpenSynapse.ps1'
. $mainScript -Mode SelfTest

$cases = @(
    [pscustomobject]@{ Sub = $script:Guids.Processor; Setting = $script:Guids.ProcessorMinimum; Hyper = @(5, 5); Balance = @(5, 5); Quiet = @(5, 5) },
    [pscustomobject]@{ Sub = $script:Guids.Processor; Setting = $script:Guids.ProcessorMaximum; Hyper = @(100, 100); Balance = @(100, 100); Quiet = @(80, 75) },
    [pscustomobject]@{ Sub = $script:Guids.Processor; Setting = $script:Guids.ProcessorEpp; Hyper = @(0, 0); Balance = @(50, 70); Quiet = @(90, 95) },
    [pscustomobject]@{ Sub = $script:Guids.Processor; Setting = $script:Guids.ProcessorBoost; Hyper = @(2, 2); Balance = @(3, 3); Quiet = @(0, 0) },
    [pscustomobject]@{ Sub = $script:Guids.Processor; Setting = $script:Guids.CoolingPolicy; Hyper = @(1, 1); Balance = @(1, 0); Quiet = @(0, 0) },
    [pscustomobject]@{ Sub = $script:Guids.Wireless; Setting = $script:Guids.WirelessPowerSaving; Hyper = @(0, 0); Balance = @(1, 2); Quiet = @(3, 3) },
    [pscustomobject]@{ Sub = $script:Guids.PciExpress; Setting = $script:Guids.PciLinkState; Hyper = @(0, 0); Balance = @(1, 2); Quiet = @(2, 2) },
    [pscustomobject]@{ Sub = $script:Guids.Display; Setting = $script:Guids.DisplayTimeout; Hyper = @(900, 300); Balance = @(600, 300); Quiet = @(300, 120) },
    [pscustomobject]@{ Sub = $script:Guids.Usb; Setting = $script:Guids.UsbSelectiveSuspend; Hyper = @(0, 0); Balance = @(1, 1); Quiet = @(1, 1) },
    [pscustomobject]@{ Sub = $script:Guids.EnergySaver; Setting = $script:Guids.EnergySaverThreshold; Hyper = @(0, 0); Balance = @(0, 50); Quiet = @(0, 100) },
    [pscustomobject]@{ Sub = $script:Guids.Sleep; Setting = $script:Guids.StandbyIdle; Hyper = @(0, 900); Balance = @(900, 600); Quiet = @(600, 180) },
    [pscustomobject]@{ Sub = $script:Guids.Sleep; Setting = $script:Guids.HibernateIdle; Hyper = @(0, 3600); Balance = @(3600, 1800); Quiet = @(1800, 900) },
    [pscustomobject]@{ Sub = $script:Guids.Buttons; Setting = $script:Guids.LidAction; Hyper = @(1, 1); Balance = @(1, 2); Quiet = @(1, 2) }
)

$hyperOnlyCases = @(
    [pscustomobject]@{ Sub = $script:Guids.Processor; Setting = $script:Guids.ProcessorMinimum1; Expected = @(5, 5) },
    [pscustomobject]@{ Sub = $script:Guids.Processor; Setting = $script:Guids.ProcessorMinimum2; Expected = @(5, 5) },
    [pscustomobject]@{ Sub = $script:Guids.Processor; Setting = $script:Guids.ProcessorMaximum1; Expected = @(100, 100) },
    [pscustomobject]@{ Sub = $script:Guids.Processor; Setting = $script:Guids.ProcessorMaximum2; Expected = @(100, 100) },
    [pscustomobject]@{ Sub = $script:Guids.Processor; Setting = $script:Guids.ProcessorEpp1; Expected = @(0, 0) },
    [pscustomobject]@{ Sub = $script:Guids.Processor; Setting = $script:Guids.ProcessorEpp2; Expected = @(0, 0) },
    [pscustomobject]@{ Sub = $script:Guids.Processor; Setting = $script:Guids.ProcessorAutonomous; Expected = @(1, 1) },
    [pscustomobject]@{ Sub = $script:Guids.Processor; Setting = $script:Guids.ProcessorIncrease; Expected = @(2, 2) },
    [pscustomobject]@{ Sub = $script:Guids.Processor; Setting = $script:Guids.ProcessorIncrease1; Expected = @(3, 3) },
    [pscustomobject]@{ Sub = $script:Guids.Processor; Setting = $script:Guids.ProcessorBoostPolicy; Expected = @(100, 100) },
    [pscustomobject]@{ Sub = $script:Guids.Processor; Setting = $script:Guids.ProcessorMinCores; Expected = @(100, 100) },
    [pscustomobject]@{ Sub = $script:Guids.Processor; Setting = $script:Guids.ProcessorMinCores1; Expected = @(0, 0) },
    [pscustomobject]@{ Sub = $script:Guids.Graphics; Setting = $script:Guids.GpuPreference; Expected = @(0, 0) }
)

$quietOnlyCases = @(
    [pscustomobject]@{ Sub = $script:Guids.Processor; Setting = $script:Guids.ProcessorMinCores; Expected = @(10, 0) },
    [pscustomobject]@{ Sub = $script:Guids.Processor; Setting = $script:Guids.ProcessorMinCores1; Expected = @(10, 0) },
    [pscustomobject]@{ Sub = $script:Guids.Graphics; Setting = $script:Guids.GpuPreference; Expected = @(1, 1) },
    [pscustomobject]@{ Sub = $script:Guids.Sleep; Setting = $script:Guids.WakeTimers; Expected = @(0, 0) },
    [pscustomobject]@{ Sub = $script:Guids.NoSubgroup; Setting = $script:Guids.ConnectivityStandby; Expected = @(0, 0) }
)

function Get-PlanPair {
    param([string]$PlanGuid, [string]$Subgroup, [string]$Setting)
    $query = Invoke-PowerCfg @('/qh', $PlanGuid, $Subgroup, $Setting)
    $values = @([regex]::Matches($query, '0x[0-9a-fA-F]+') | ForEach-Object { [Convert]::ToInt32($_.Value.Substring(2), 16) })
    if ($values.Count -lt 2) { throw "Cannot parse AC/DC values for $Setting" }
    return @($values[$values.Count - 2], $values[$values.Count - 1])
}

function Assert-Profile {
    param([ValidateSet('Hyper', 'Balance', 'Quiet')][string]$Name, [string]$PlanGuid)
    Set-ProfilePolicy $Name $PlanGuid
    foreach ($case in $cases) {
        $actual = @(Get-PlanPair $PlanGuid $case.Sub $case.Setting)
        $expected = @($case.$Name)
        if ($actual[0] -ne $expected[0] -or $actual[1] -ne $expected[1]) {
            throw "$Name verification failed for $($case.Setting): expected $($expected -join '/'), got $($actual -join '/')"
        }
    }
    if ($Name -eq 'Hyper') {
        foreach ($case in $hyperOnlyCases) {
            $actual = @(Get-PlanPair $PlanGuid $case.Sub $case.Setting)
            $expected = @($case.Expected)
            if ($actual[0] -ne $expected[0] -or $actual[1] -ne $expected[1]) {
                throw "Hyper verification failed for $($case.Setting): expected $($expected -join '/'), got $($actual -join '/')"
            }
        }
    }
    if ($Name -eq 'Quiet') {
        foreach ($case in $quietOnlyCases) {
            $actual = @(Get-PlanPair $PlanGuid $case.Sub $case.Setting)
            $expected = @($case.Expected)
            if ($actual[0] -ne $expected[0] -or $actual[1] -ne $expected[1]) {
                throw "Quiet verification failed for $($case.Setting): expected $($expected -join '/'), got $($actual -join '/')"
            }
        }
    }
}

$original = Get-ActivePlanGuid
$temporary = $null
try {
    $temporary = New-CustomPlan 'OpenSynapse Release Test' 'Temporary verification plan; safe to delete.'
    Assert-Profile Hyper $temporary
    Invoke-PowerCfg @('/setactive', $temporary) | Out-Null
    if ((Get-ActivePlanGuid) -ne $temporary) { throw 'Hyper activation verification failed.' }
    Invoke-PowerCfg @('/setactive', $original) | Out-Null

    Assert-Profile Balance $temporary
    Invoke-PowerCfg @('/setactive', $temporary) | Out-Null
    if ((Get-ActivePlanGuid) -ne $temporary) { throw 'Balance activation verification failed.' }
    Invoke-PowerCfg @('/setactive', $original) | Out-Null

    Assert-Profile Quiet $temporary
    Invoke-PowerCfg @('/setactive', $temporary) | Out-Null
    if ((Get-ActivePlanGuid) -ne $temporary) { throw 'Quiet activation verification failed.' }
    $dynamicConfig = Get-DefaultConfig
    $dynamicState = [pscustomobject]@{ QuietPlanGuid = $temporary }
    $script:LastAppliedQuietCpuMax = $null
    foreach ($dynamicCase in @(
        [pscustomobject]@{ BatteryPercent = 35; Expected = 65 },
        [pscustomobject]@{ BatteryPercent = 15; Expected = 60 },
        [pscustomobject]@{ BatteryPercent = 80; Expected = 75 }
    )) {
        $snapshot = [pscustomobject]@{ Source = 'Battery'; BatteryPercent = $dynamicCase.BatteryPercent }
        $actualTarget = Apply-QuietDynamicCpuPolicy $dynamicConfig $dynamicState $snapshot
        $actualPair = @(Get-PlanPair $temporary $script:Guids.Processor $script:Guids.ProcessorMaximum)
        if ($actualTarget -ne $dynamicCase.Expected -or $actualPair[0] -ne 80 -or $actualPair[1] -ne $dynamicCase.Expected) {
            throw "Dynamic Quiet CPU verification failed at $($dynamicCase.BatteryPercent)%: target=$actualTarget pair=$($actualPair -join '/')"
        }
    }
    Invoke-PowerCfg @('/setactive', $original) | Out-Null

    $result = [pscustomobject]@{
        Result = 'PASS'
        SettingsVerifiedPerProfile = $cases.Count
        HyperAdditionalSettingsVerified = $hyperOnlyCases.Count
        QuietAdditionalSettingsVerified = $quietOnlyCases.Count
        DynamicQuietCpuTargetsVerified = 3
        ProfilesVerified = 3
        ActivePlanRestored = ((Get-ActivePlanGuid) -eq $original)
        WakeArmedDevicesReadable = (@(Get-WakeArmedDevices).Count -gt 0)
        NativeDisplayCount = @([OpenSynapseNative.DisplayScaling]::GetActiveDisplays()).Count
        CompletedAt = (Get-Date).ToString('o')
    }
    if (-not [string]::IsNullOrWhiteSpace($ResultPath)) {
        [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath), ($result | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    }
    $result | Format-List
}
finally {
    if ((Get-ActivePlanGuid) -ne $original) { Invoke-PowerCfg @('/setactive', $original) -AllowFailure | Out-Null }
    if ($temporary -and (Test-PlanExists $temporary)) { Invoke-PowerCfg @('/delete', $temporary) -AllowFailure | Out-Null }
    if ((Get-ActivePlanGuid) -ne $original) { throw 'The original active power plan was not restored.' }
}
