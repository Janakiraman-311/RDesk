; RDesk InnoSetup Template
; This script is used by rdesk::build_app() to generate a Windows installer.
; Placeholders like {{AppName}} are replaced by R logic or via Command Line Defines.

#define AppName "{{AppName}}"
#define AppVersion "{{AppVersion}}"
#define AppPublisher "{{AppPublisher}}"
#define AppURL "{{AppURL}}"
#define AppExeName "{{AppExeName}}"
#define AppID "{{AppID}}"
#define LicenseFile "{{LicenseFile}}"
#define AppIconFile "{{AppIconFile}}"
#define SourceDir "{{SourceDir}}"
#define OutputDir "{{OutputDir}}"
#define SetupBaseName "{{SetupBaseName}}"

[Setup]
; NOTE: The value of AppId uniquely identifies this application.
; Do not use the same AppId value in installers for other applications.
AppId={#AppID}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
AppUpdatesURL={#AppURL}
DefaultDirName={{DefaultDirName}}
DisableDirPage=no
AlwaysShowDirOnReadyPage=yes
DisableProgramGroupPage=yes
; License file is optional
#if LicenseFile != ""
LicenseFile={#LicenseFile}
#endif
; Info after install could be handled here
OutputDir={#OutputDir}
OutputBaseFilename={#SetupBaseName}
#if AppIconFile != ""
SetupIconFile={#AppIconFile}
#endif
Compression=lzma
SolidCompression=yes
WizardStyle=modern
; Per-user install by default (no UAC prompt); user may elevate for all users
PrivilegesRequired={{PrivilegesRequired}}
PrivilegesRequiredOverridesAllowed=dialog commandline
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#AppExeName}
CloseApplications=force

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Copy all files from the staging directory (the ZIP source)
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Code]
function IsWebView2Installed(): Boolean;
var
  Ver: String;
  SubKey: String;
begin
  SubKey := 'Software\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}';
  Result :=
    (RegQueryStringValue(HKLM, SubKey, 'pv', Ver) and (Ver <> '')) or
    (RegQueryStringValue(HKCU, SubKey, 'pv', Ver) and (Ver <> ''));
end;

function InitializeSetup(): Boolean;
begin
  Result := True;
  if (not IsWebView2Installed()) and (not WizardSilent()) then
  begin
    if MsgBox(
      'This application requires the Microsoft Edge WebView2 Runtime, which was not detected on this system.' + #13#10 + #13#10 +
      'Download URL: https://go.microsoft.com/fwlink/p/?LinkId=2124703' + #13#10 + #13#10 +
      'Do you want to continue with installation anyway?',
      mbConfirmation, MB_YESNO) = IDNO then
    begin
      Result := False;
    end;
  end;
end;
