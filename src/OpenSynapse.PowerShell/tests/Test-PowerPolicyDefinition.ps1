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

$script:RecordedPlanPairs = @()
$script:RecordedPlanValues = @()
function Set-PlanPair {
    param(
        [string]$PlanGuid,
        [string]$Subgroup,
        [string]$Setting,
        [int]$AcValue,
        [int]$DcValue,
        [switch]$Optional
    )
    $script:RecordedPlanPairs += [pscustomobject]@{
        PlanGuid = $PlanGuid
        Subgroup = $Subgroup
        Setting = $Setting
        AcValue = $AcValue
        DcValue = $DcValue
        Optional = [bool]$Optional
    }
}
function Set-PlanValue {
    param(
        [string]$PlanGuid,
        [string]$Source,
        [string]$Subgroup,
        [string]$Setting,
        [int]$Value,
        [switch]$Optional
    )
    $script:RecordedPlanValues += [pscustomobject]@{
        PlanGuid = $PlanGuid
        Source = $Source
        Subgroup = $Subgroup
        Setting = $Setting
        Value = $Value
        Optional = [bool]$Optional
    }
}

Set-ProfilePolicy Hyper '00000000-0000-0000-0000-000000000001'
$hyperPairs = @($script:RecordedPlanPairs)
$hyperDisplay = @($hyperPairs | Where-Object { $_.Setting -eq $script:Guids.DisplayTimeout })
$hyperLockDisplay = @($hyperPairs | Where-Object { $_.Setting -eq $script:Guids.ConsoleLockDisplayTimeout })
$hyperStandby = @($hyperPairs | Where-Object { $_.Setting -eq $script:Guids.StandbyIdle })
$hyperHibernate = @($hyperPairs | Where-Object { $_.Setting -eq $script:Guids.HibernateIdle })
$hyperEpp = @($hyperPairs | Where-Object { $_.Setting -eq $script:Guids.ProcessorEpp })
$hyperEpp1 = @($hyperPairs | Where-Object { $_.Setting -eq $script:Guids.ProcessorEpp1 })
$hyperEpp2 = @($hyperPairs | Where-Object { $_.Setting -eq $script:Guids.ProcessorEpp2 })
$hyperMinCores = @($hyperPairs | Where-Object { $_.Setting -eq $script:Guids.ProcessorMinCores })
$hyperMinCores1 = @($hyperPairs | Where-Object { $_.Setting -eq $script:Guids.ProcessorMinCores1 })
$hyperGpu = @($hyperPairs | Where-Object { $_.Setting -eq $script:Guids.GpuPreference })
$hyperBoostPolicy = @($hyperPairs | Where-Object { $_.Setting -eq $script:Guids.ProcessorBoostPolicy })
$script:RecordedPlanPairs = @()
Set-ProfilePolicy Balance '00000000-0000-0000-0000-000000000003'
$balancePairs = @($script:RecordedPlanPairs)
$balanceDisplay = @($balancePairs | Where-Object { $_.Setting -eq $script:Guids.DisplayTimeout })
$balanceLockDisplay = @($balancePairs | Where-Object { $_.Setting -eq $script:Guids.ConsoleLockDisplayTimeout })
$balanceStandby = @($balancePairs | Where-Object { $_.Setting -eq $script:Guids.StandbyIdle })
$balanceHibernate = @($balancePairs | Where-Object { $_.Setting -eq $script:Guids.HibernateIdle })
$balanceEpp = @($balancePairs | Where-Object { $_.Setting -eq $script:Guids.ProcessorEpp })
$script:RecordedPlanPairs = @()
Set-ProfilePolicy Quiet '00000000-0000-0000-0000-000000000002'
$quietPairs = @($script:RecordedPlanPairs)
$quietDcValues = @($script:RecordedPlanValues | Where-Object { $_.PlanGuid -eq '00000000-0000-0000-0000-000000000002' })
$quietDisplay = @($quietPairs | Where-Object { $_.Setting -eq $script:Guids.DisplayTimeout })
$quietLockDisplay = @($quietPairs | Where-Object { $_.Setting -eq $script:Guids.ConsoleLockDisplayTimeout })
$quietStandby = @($quietPairs | Where-Object { $_.Setting -eq $script:Guids.StandbyIdle })
$quietHibernate = @($quietPairs | Where-Object { $_.Setting -eq $script:Guids.HibernateIdle })
$quietCpuMax = @($quietPairs | Where-Object { $_.Setting -eq $script:Guids.ProcessorMaximum })
$quietEpp = @($quietPairs | Where-Object { $_.Setting -eq $script:Guids.ProcessorEpp })
$quietMinCores = @($quietPairs | Where-Object { $_.Setting -eq $script:Guids.ProcessorMinCores })
$quietMinCores1 = @($quietPairs | Where-Object { $_.Setting -eq $script:Guids.ProcessorMinCores1 })
$quietGpu = @($quietPairs | Where-Object { $_.Setting -eq $script:Guids.GpuPreference })
$quietWakeTimers = @($quietPairs | Where-Object { $_.Setting -eq $script:Guids.WakeTimers })
$quietStandbyNetwork = @($quietPairs | Where-Object { $_.Setting -eq $script:Guids.ConnectivityStandby })
$script:RecordedPlanPairs = @()
Set-ProfilePolicy Experiment '00000000-0000-0000-0000-000000000004'
$experimentPairs = @($script:RecordedPlanPairs)
$experimentDisplay = @($experimentPairs | Where-Object { $_.Setting -eq $script:Guids.DisplayTimeout } | Select-Object -Last 1)
$experimentLockDisplay = @($experimentPairs | Where-Object { $_.Setting -eq $script:Guids.ConsoleLockDisplayTimeout } | Select-Object -Last 1)
$experimentStandby = @($experimentPairs | Where-Object { $_.Setting -eq $script:Guids.StandbyIdle } | Select-Object -Last 1)
$experimentHibernate = @($experimentPairs | Where-Object { $_.Setting -eq $script:Guids.HibernateIdle } | Select-Object -Last 1)

$result = [pscustomobject]@{
    Result = 'PASS'
    HyperSettings = $hyperPairs.Count
    BalanceSettings = $balancePairs.Count
    QuietSettings = $quietPairs.Count
    ExperimentSettings = $experimentPairs.Count
    QuietDcClassSettings = $quietDcValues.Count
    HyperDisplayAcSeconds = if ($hyperDisplay.Count -eq 1) { $hyperDisplay[0].AcValue } else { -1 }
    HyperDisplayDcSeconds = if ($hyperDisplay.Count -eq 1) { $hyperDisplay[0].DcValue } else { -1 }
    HyperLockDisplay = if ($hyperLockDisplay.Count -eq 1) { @($hyperLockDisplay[0].AcValue, $hyperLockDisplay[0].DcValue) } else { @(-1, -1) }
    HyperStandby = if ($hyperStandby.Count -eq 1) { @($hyperStandby[0].AcValue, $hyperStandby[0].DcValue) } else { @(-1, -1) }
    HyperHibernate = if ($hyperHibernate.Count -eq 1) { @($hyperHibernate[0].AcValue, $hyperHibernate[0].DcValue) } else { @(-1, -1) }
    HyperEppClasses = @(
        if ($hyperEpp.Count -eq 1) { $hyperEpp[0].AcValue } else { -1 }
        if ($hyperEpp1.Count -eq 1) { $hyperEpp1[0].AcValue } else { -1 }
        if ($hyperEpp2.Count -eq 1) { $hyperEpp2[0].AcValue } else { -1 }
    )
    HyperMinCores = if ($hyperMinCores.Count -eq 1) { @($hyperMinCores[0].AcValue, $hyperMinCores[0].DcValue) } else { @(-1, -1) }
    HyperMinCores1 = if ($hyperMinCores1.Count -eq 1) { @($hyperMinCores1[0].AcValue, $hyperMinCores1[0].DcValue) } else { @(-1, -1) }
    HyperGpuPreference = if ($hyperGpu.Count -eq 1) { @($hyperGpu[0].AcValue, $hyperGpu[0].DcValue) } else { @(-1, -1) }
    HyperBoostPolicy = if ($hyperBoostPolicy.Count -eq 1) { @($hyperBoostPolicy[0].AcValue, $hyperBoostPolicy[0].DcValue) } else { @(-1, -1) }
    BalanceDisplayAcSeconds = if ($balanceDisplay.Count -eq 1) { $balanceDisplay[0].AcValue } else { -1 }
    BalanceDisplayDcSeconds = if ($balanceDisplay.Count -eq 1) { $balanceDisplay[0].DcValue } else { -1 }
    BalanceLockDisplay = if ($balanceLockDisplay.Count -eq 1) { @($balanceLockDisplay[0].AcValue, $balanceLockDisplay[0].DcValue) } else { @(-1, -1) }
    BalanceStandby = if ($balanceStandby.Count -eq 1) { @($balanceStandby[0].AcValue, $balanceStandby[0].DcValue) } else { @(-1, -1) }
    BalanceHibernate = if ($balanceHibernate.Count -eq 1) { @($balanceHibernate[0].AcValue, $balanceHibernate[0].DcValue) } else { @(-1, -1) }
    BalanceEppAc = if ($balanceEpp.Count -eq 1) { $balanceEpp[0].AcValue } else { -1 }
    BalanceEppDc = if ($balanceEpp.Count -eq 1) { $balanceEpp[0].DcValue } else { -1 }
    QuietDisplayAcSeconds = if ($quietDisplay.Count -eq 1) { $quietDisplay[0].AcValue } else { -1 }
    QuietDisplayDcSeconds = if ($quietDisplay.Count -eq 1) { $quietDisplay[0].DcValue } else { -1 }
    QuietLockDisplay = if ($quietLockDisplay.Count -eq 1) { @($quietLockDisplay[0].AcValue, $quietLockDisplay[0].DcValue) } else { @(-1, -1) }
    QuietStandby = if ($quietStandby.Count -eq 1) { @($quietStandby[0].AcValue, $quietStandby[0].DcValue) } else { @(-1, -1) }
    QuietHibernate = if ($quietHibernate.Count -eq 1) { @($quietHibernate[0].AcValue, $quietHibernate[0].DcValue) } else { @(-1, -1) }
    ExperimentDisplay = if ($experimentDisplay.Count -eq 1) { @($experimentDisplay[0].AcValue, $experimentDisplay[0].DcValue) } else { @(-1, -1) }
    ExperimentLockDisplay = if ($experimentLockDisplay.Count -eq 1) { @($experimentLockDisplay[0].AcValue, $experimentLockDisplay[0].DcValue) } else { @(-1, -1) }
    ExperimentStandby = if ($experimentStandby.Count -eq 1) { @($experimentStandby[0].AcValue, $experimentStandby[0].DcValue) } else { @(-1, -1) }
    ExperimentHibernate = if ($experimentHibernate.Count -eq 1) { @($experimentHibernate[0].AcValue, $experimentHibernate[0].DcValue) } else { @(-1, -1) }
    QuietCpuMaxDc = if ($quietCpuMax.Count -eq 1) { $quietCpuMax[0].DcValue } else { -1 }
    QuietEppDc = if ($quietEpp.Count -eq 1) { $quietEpp[0].DcValue } else { -1 }
    QuietMinCoresDc = if ($quietMinCores.Count -eq 1) { $quietMinCores[0].DcValue } else { -1 }
    QuietMinCores1Dc = if ($quietMinCores1.Count -eq 1) { $quietMinCores1[0].DcValue } else { -1 }
    QuietGpuPreferenceDc = if ($quietGpu.Count -eq 1) { $quietGpu[0].DcValue } else { -1 }
    QuietWakeTimersDc = if ($quietWakeTimers.Count -eq 1) { $quietWakeTimers[0].DcValue } else { -1 }
    QuietStandbyNetworkDc = if ($quietStandbyNetwork.Count -eq 1) { $quietStandbyNetwork[0].DcValue } else { -1 }
    ChangedPowerPlans = $false
    CompletedAt = (Get-Date).ToString('o')
}
if (-not ($result.HyperSettings -eq 27 -and $result.BalanceSettings -eq 14 -and $result.QuietSettings -eq 19 -and
    $result.ExperimentSettings -eq 20 -and
    $result.HyperDisplayAcSeconds -eq 900 -and $result.HyperDisplayDcSeconds -eq 300 -and
    ($result.HyperLockDisplay -join ',') -eq '900,30' -and
    ($result.HyperStandby -join ',') -eq '10800,900' -and ($result.HyperHibernate -join ',') -eq '0,3600' -and
    ($result.HyperEppClasses -join ',') -eq '0,0,0' -and
    ($result.HyperMinCores -join ',') -eq '100,100' -and ($result.HyperMinCores1 -join ',') -eq '0,0' -and
    ($result.HyperGpuPreference -join ',') -eq '0,0' -and
    ($result.HyperBoostPolicy -join ',') -eq '100,100' -and
    $result.BalanceDisplayAcSeconds -eq 900 -and $result.BalanceDisplayDcSeconds -eq 300 -and
    ($result.BalanceLockDisplay -join ',') -eq '900,30' -and
    ($result.BalanceStandby -join ',') -eq '10800,600' -and ($result.BalanceHibernate -join ',') -eq '0,1800' -and
    $result.BalanceEppAc -eq 50 -and $result.BalanceEppDc -eq 70 -and
    $result.QuietDisplayAcSeconds -eq 900 -and $result.QuietDisplayDcSeconds -eq 120 -and
    ($result.QuietLockDisplay -join ',') -eq '900,30' -and
    ($result.QuietStandby -join ',') -eq '10800,180' -and ($result.QuietHibernate -join ',') -eq '0,900' -and
    ($result.ExperimentDisplay -join ',') -eq '900,0' -and
    ($result.ExperimentLockDisplay -join ',') -eq '900,0' -and
    ($result.ExperimentStandby -join ',') -eq '10800,0' -and
    ($result.ExperimentHibernate -join ',') -eq '0,0' -and
    $result.QuietCpuMaxDc -eq 65 -and $result.QuietEppDc -eq 90 -and
    $result.QuietMinCoresDc -eq 0 -and $result.QuietMinCores1Dc -eq 0 -and
    $result.QuietGpuPreferenceDc -eq 1 -and $result.QuietWakeTimersDc -eq 0 -and
    $result.QuietStandbyNetworkDc -eq 0 -and $result.QuietDcClassSettings -eq 9 -and
    @($quietDcValues | Where-Object {
        $_.Setting -in @($script:Guids.ProcessorMaximum1, $script:Guids.ProcessorMaximum2) -and $_.Value -eq 65
    }).Count -eq 2 -and
    @($quietDcValues | Where-Object {
        $_.Setting -in @($script:Guids.ProcessorEpp1, $script:Guids.ProcessorEpp2) -and $_.Value -eq 90
    }).Count -eq 2 -and
    @($quietDcValues | Where-Object {
        $_.Setting -in @($script:Guids.ProcessorScheduling, $script:Guids.ProcessorShortScheduling) -and $_.Value -eq 4
    }).Count -eq 2)) {
    throw 'Power policy definition verification failed.'
}
if ($ResultPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath), ($result | ConvertTo-Json), [Text.UTF8Encoding]::new($false)) }
$result | Format-List
