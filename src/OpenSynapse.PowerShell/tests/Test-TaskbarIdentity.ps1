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

$root = Split-Path -Parent $PSScriptRoot
$nativePath = Join-Path $root 'OpenSynapse.Native.cs'
$mainPath = Join-Path $root 'OpenSynapse.ps1'
Add-Type -Path $nativePath
Add-Type -AssemblyName System.Windows.Forms

$appId = 'OpenSynapse.Desktop'
$actualProcessId = [OpenSynapseNative.AppIdentity]::SetCurrentProcessAppId($appId)
if ($actualProcessId -ne $appId) { throw "Process AppUserModelID mismatch: $actualProcessId" }

$form = New-Object Windows.Forms.Form
$form.Text = 'OpenSynapse taskbar identity probe'
try {
    [OpenSynapseNative.AppIdentity]::SetWindowAppId($form.Handle, $appId)
    $actualWindowId = [OpenSynapseNative.AppIdentity]::GetWindowAppId($form.Handle)
    if ($actualWindowId -ne $appId) { throw "Window AppUserModelID mismatch: $actualWindowId" }
}
finally {
    $form.Dispose()
}

$temporaryShortcut = Join-Path ([IO.Path]::GetTempPath()) ("OpenSynapse-Identity-{0}.lnk" -f [Guid]::NewGuid().ToString('N'))
try {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($temporaryShortcut)
    $shortcut.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $shortcut.Save()
    [OpenSynapseNative.AppIdentity]::SetShortcutAppId($temporaryShortcut, $appId)
    $actualShortcutId = [OpenSynapseNative.AppIdentity]::GetShortcutAppId($temporaryShortcut)
    if ($actualShortcutId -ne $appId) { throw "Shortcut AppUserModelID mismatch: $actualShortcutId" }
}
finally {
    Remove-Item -LiteralPath $temporaryShortcut -Force -ErrorAction SilentlyContinue
}

$mainSource = Get-Content -Raw -LiteralPath $mainPath
foreach ($required in @(
    "`$script:AppUserModelId = 'OpenSynapse.Desktop'",
    '[OpenSynapseNative.AppIdentity]::SetCurrentProcessAppId',
    '[OpenSynapseNative.AppIdentity]::SetWindowAppId',
    '[OpenSynapseNative.AppIdentity]::SetShortcutAppId'
)) {
    if ($mainSource.IndexOf($required, [StringComparison]::Ordinal) -lt 0) {
        throw "Missing taskbar identity integration: $required"
    }
}

$result = [pscustomobject]@{
    Result = 'PASS'
    AppUserModelId = $appId
    ProcessIdentityVerified = $true
    WindowIdentityApplied = $true
    ShortcutIdentityApplied = $true
    ChangedSystemSettings = $false
    CompletedAt = (Get-Date).ToString('o')
}
if ($ResultPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath), ($result | ConvertTo-Json), [Text.UTF8Encoding]::new($false)) }
$result | Format-List
