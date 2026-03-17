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
DefaultDirName={autopf}\{#AppName}
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
PrivilegesRequired=admin

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
