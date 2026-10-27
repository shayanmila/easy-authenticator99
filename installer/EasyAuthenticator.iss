#define AppName "Easy Authenticator"
#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\build\windows\x64\runner\Release"
#endif
[Setup]
AppId={{D6C6F52D-11AB-47B4-947A-3C47C8A96D15}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=MasoomDev
DefaultDirName={localappdata}\Programs\Easy Authenticator
DefaultGroupName=Easy Authenticator
OutputDir=..\dist
OutputBaseFilename=Easy-Authenticator-Setup-{#AppVersion}-Windows-x64
Compression=lzma2
SolidCompression=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
LicenseFile=..\legal\TERMS-OF-USE.txt
UninstallDisplayName=Easy Authenticator
CloseApplications=yes
RestartApplications=no
DisableProgramGroupPage=yes
[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion
[Icons]
Name: "{group}\Easy Authenticator"; Filename: "{app}\easy_authenticator.exe"
Name: "{autodesktop}\Easy Authenticator"; Filename: "{app}\easy_authenticator.exe"; Tasks: desktopicon
[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"
[Run]
Filename: "{app}\easy_authenticator.exe"; Description: "Launch Easy Authenticator"; Flags: nowait postinstall skipifsilent
