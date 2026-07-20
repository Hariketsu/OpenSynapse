[CmdletBinding()]
param(
    [ValidateSet('win-x64', 'win-arm64')][string]$Runtime = 'win-x64',
    [switch]$FrameworkDependent,
    [string]$DotnetPath
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$artifacts = [IO.Path]::GetFullPath((Join-Path $root 'artifacts'))
$output = [IO.Path]::GetFullPath((Join-Path $artifacts 'publish'))
$separator = [IO.Path]::DirectorySeparatorChar
$artifactsPrefix = $artifacts.TrimEnd($separator, [IO.Path]::AltDirectorySeparatorChar) + $separator
if (-not $output.StartsWith($artifactsPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Resolved publish output is outside the repository artifacts directory.'
}

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
$agentOutput = Join-Path $output 'Agent'
$appOutput = Join-Path $output 'App'
foreach ($directory in @($agentOutput, $appOutput)) {
    if (Test-Path -LiteralPath $directory) { Remove-Item -LiteralPath $directory -Recurse -Force }
}
$common = @(
    '--configuration', 'Release',
    '--runtime', $Runtime,
    '--self-contained', (-not $FrameworkDependent.IsPresent).ToString().ToLowerInvariant()
)

& $dotnetExecutable publish (Join-Path $root 'src\OpenSynapse.Agent\OpenSynapse.Agent.csproj') @common --output $agentOutput
if ($LASTEXITCODE -ne 0) { throw 'Agent publish failed.' }
& $dotnetExecutable publish (Join-Path $root 'src\OpenSynapse.App\OpenSynapse.App.csproj') @common --output $appOutput
if ($LASTEXITCODE -ne 0) { throw 'App publish failed.' }

Write-Host "OpenSynapse publish output: $output"
