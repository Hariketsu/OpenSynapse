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

$project = Split-Path -Parent $PSScriptRoot
$mainPath = Join-Path $project 'OpenSynapse.ps1'
$nativePath = Join-Path $project 'OpenSynapse.Native.cs'
. $mainPath -Mode SelfTest

$mouseType = [OpenSynapseNative.RazerMouse]
$publicMethods = $mouseType.GetMethods().Name
foreach ($method in @('GetDevices', 'SetDpi', 'SetPollingRate')) {
    if ($method -notin $publicMethods) { throw "Missing Razer mouse API: $method" }
}

$bindingFlags = [Reflection.BindingFlags]::Static -bor [Reflection.BindingFlags]::NonPublic
$dpiBuilder = $mouseType.GetMethod('BuildSetDpi', $bindingFlags)
$pollingBuilder = $mouseType.GetMethod('BuildSetPollingRate', $bindingFlags)
$checksumMethod = $mouseType.GetMethod('CalculateChecksum', $bindingFlags)
if ($null -eq $dpiBuilder -or $null -eq $pollingBuilder -or $null -eq $checksumMethod) {
    throw 'Razer feature-report builders are incomplete.'
}

$dpiReport = [byte[]]$dpiBuilder.Invoke($null, [object[]]@([byte]0x12, [int]1600, [int]3200))
if ($dpiReport.Length -ne 90 -or $dpiReport[1] -ne 0x12 -or $dpiReport[5] -ne 0x07 -or
    $dpiReport[6] -ne 0x04 -or $dpiReport[7] -ne 0x05) {
    throw 'Razer DPI feature-report header is invalid.'
}
$expectedDpiPayload = [byte[]]@(0x01, 0x06, 0x40, 0x0C, 0x80, 0x00, 0x00)
for ($index = 0; $index -lt $expectedDpiPayload.Length; $index++) {
    if ($dpiReport[8 + $index] -ne $expectedDpiPayload[$index]) {
        throw "Razer DPI payload mismatch at index $index."
    }
}
$checksumArguments = New-Object object[] 1
$checksumArguments[0] = $dpiReport
$dpiChecksum = [byte]$checksumMethod.Invoke($null, $checksumArguments)
if ($dpiChecksum -ne $dpiReport[88]) { throw 'Razer DPI checksum is invalid.' }

$pollingCodes = @{ 125 = 0x08; 500 = 0x02; 1000 = 0x01 }
foreach ($hertz in $pollingCodes.Keys) {
    $report = [byte[]]$pollingBuilder.Invoke($null, [object[]]@([byte]0x01, [int]$hertz))
    if ($report[8] -ne [byte]$pollingCodes[$hertz]) {
        throw "Razer polling code is invalid for $hertz Hz."
    }
}

$mainSource = Get-Content -LiteralPath $mainPath -Raw -Encoding UTF8
$nativeSource = Get-Content -LiteralPath $nativePath -Raw -Encoding UTF8
foreach ($required in @(
    'Razer DeathAdder V3 Pro HID control',
    'function Get-RazerMouseDevices',
    'function Set-RazerMouseDpi',
    'function Set-RazerMousePollingRate',
    '$razerApplyDpiButton.Add_Click',
    '$razerApplyPollingButton.Add_Click'
)) {
    if ($mainSource.IndexOf($required, [StringComparison]::Ordinal) -lt 0) {
        throw "Missing Razer mouse UI definition: $required"
    }
}
foreach ($productId in @('0x00B6', '0x00B7', '0x00C2', '0x00C3')) {
    if ($nativeSource.IndexOf($productId, [StringComparison]::Ordinal) -lt 0) {
        throw "Missing supported DeathAdder product ID: $productId"
    }
}

$devices = @([OpenSynapseNative.RazerMouse]::GetDevices())
$result = [pscustomobject]@{
    Result = 'PASS'
    SupportedProductIds = 4
    DetectedDevices = $devices.Count
    DpiReportValidated = $true
    PollingReportsValidated = $true
    ChangedSystemSettings = $false
    CompletedAt = (Get-Date).ToString('o')
}
if ($ResultPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath), ($result | ConvertTo-Json), [Text.UTF8Encoding]::new($false)) }
$result | Format-List
