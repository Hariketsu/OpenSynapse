#ifndef MyAppVersion
  #define MyAppVersion "0.2.0-preview.1"
#endif

#define MyAppName "OpenSynapse"
#define MyAppPublisher "Hariketsu"
#define MyAppUrl "https://github.com/Hariketsu/OpenSynapse"
#define MyAppExeName "OpenSynapse.ps1"

[Setup]
AppId={{B17DDFAF-4FA4-4D9D-8722-DC83146CEA02}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppUrl}
AppSupportURL={#MyAppUrl}/issues
AppUpdatesURL={#MyAppUrl}/releases
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=admin
LicenseFile=..\LICENSE
ArchitecturesInstallIn64BitMode=x64compatible
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupIconFile=..\artifacts\publish\OpenSynapse\assets\OpenSynapse.App.ico
OutputDir=..\artifacts
OutputBaseFilename=OpenSynapse-Setup-{#MyAppVersion}
UninstallDisplayIcon={app}\OpenSynapse.App.ico
UninstallDisplayName={#MyAppName} {#MyAppVersion}
VersionInfoVersion=0.2.0.1
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}
VersionInfoCompany={#MyAppPublisher}

[Files]
Source: "..\artifacts\publish\OpenSynapse\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Code]
function RunOpenSynapse(const Mode: String; const InstallerManagedFiles: Boolean): Boolean;
var
  Parameters: String;
  ResultCode: Integer;
begin
  Parameters :=
    '-NoProfile -ExecutionPolicy Bypass -File "' +
    ExpandConstant('{app}\{#MyAppExeName}') +
    '" -Mode ' + Mode;
  if InstallerManagedFiles then
    Parameters := Parameters + ' -InstallerManagedFiles';

  Result :=
    Exec(
      ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
      Parameters,
      '',
      SW_SHOW,
      ewWaitUntilTerminated,
      ResultCode) and
    (ResultCode = 0);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if (CurStep = ssPostInstall) and not RunOpenSynapse('Install', False) then
    RaiseException('OpenSynapse installation failed. Review the PowerShell output and OpenSynapse.log.');
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if (CurUninstallStep = usUninstall) and not RunOpenSynapse('Uninstall', True) then
    RaiseException('OpenSynapse could not restore its managed system state. Uninstallation was stopped.');
end;
