#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif
[Setup]
AppId={{34BE8EE5-6500-4E17-9751-67F449CEFA0C}
AppName=DeAI for Windows
AppVersion={#AppVersion}
AppPublisher=DeAI
AppPublisherURL=https://github.com/YouAI-Liu/deai-writer
DefaultDirName={localappdata}\Programs\DeAI
DefaultGroupName=DeAI
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64os
ArchitecturesInstallIn64BitMode=x64os
MinVersion=10.0.17763
OutputDir=artifacts
OutputBaseFilename=DeAI-Windows-x64-{#AppVersion}-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\DeAI.exe
AppMutex=DeAI.Windows
CloseApplications=yes
RestartApplications=no
[Tasks]
Name: desktopicon; Description: "Create a desktop shortcut"; Flags: unchecked
Name: startup; Description: "Start DeAI when I sign in"; Flags: unchecked
[Files]
Source: "artifacts\win-x64\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{group}\DeAI"; Filename: "{app}\DeAI.exe"
Name: "{userdesktop}\DeAI"; Filename: "{app}\DeAI.exe"; Tasks: desktopicon
Name: "{userstartup}\DeAI"; Filename: "{app}\DeAI.exe"; Tasks: startup
[Run]
Filename: "{app}\DeAI.exe"; Description: "Start DeAI"; Flags: nowait postinstall skipifsilent
