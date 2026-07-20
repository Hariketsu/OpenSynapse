[CmdletBinding()]
param(
    [ValidateSet('win-x64', 'win-arm64')][string]$Runtime = 'win-x64',
    [switch]$SelfContained,
    [string]$DotnetPath
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$output = Join-Path $root 'artifacts\publish'

if ([string]::IsNullOrWhiteSpace($DotnetPath)) {
    $dotnetCommand = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($null -ne $dotnetCommand) {
        $DotnetPath = $dotnetCommand.Source
    }
    else {
        $scoopDotnet = Join-Path $env:USERPROFILE 'scoop\apps\dotnet-sdk\current\dotnet.exe'
        if (Test-Path -LiteralPath $scoopDotnet -PathType Leaf) {
            $DotnetPath = $scoopDotnet
        }
    }
}

if ([string]::IsNullOrWhiteSpace($DotnetPath) -or
    -not (Test-Path -LiteralPath $DotnetPath -PathType Leaf)) {
    throw 'dotnet SDK was not found. Add dotnet to PATH or pass -DotnetPath.'
}

$dotnetExecutable = [System.IO.Path]::GetFullPath($DotnetPath)
$common = @(
    '--configuration', 'Release',
    '--runtime', $Runtime,
    '--self-contained', $SelfContained.IsPresent.ToString().ToLowerInvariant()
)

& $dotnetExecutable publish (Join-Path $root 'src\OpenSynapse.Agent\OpenSynapse.Agent.csproj') @common --output (Join-Path $output 'Agent')
if ($LASTEXITCODE -ne 0) { throw 'Agent publish failed.' }
& $dotnetExecutable publish (Join-Path $root 'src\OpenSynapse.App\OpenSynapse.App.csproj') @common --output (Join-Path $output 'App')
if ($LASTEXITCODE -ne 0) { throw 'App publish failed.' }

Write-Host "OpenSynapse publish output: $output"
