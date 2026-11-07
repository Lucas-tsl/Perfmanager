; Installateur PerfManager (Inno Setup 6) : construit par windows\build.ps1
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{8F2C6B1E-4C3A-4E7B-9C2D-5A1F0E3B7D21}
AppName=PerfManager
AppVersion={#AppVersion}
AppVerName=PerfManager {#AppVersion}
AppPublisher=Lucas-tsl
DefaultDirName={localappdata}\PerfManager
DisableProgramGroupPage=yes
DisableDirPage=auto
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=PerfManager-Setup
SetupIconFile=perfmanager.ico
UninstallDisplayIcon={app}\PerfManager.exe
UninstallDisplayName=PerfManager
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=force
RestartApplications=no

[Languages]
Name: "fr"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "Créer une icône sur le bureau"
Name: "autostart"; Description: "Démarrer PerfManager avec Windows (en arrière-plan, près de l'horloge)"

[Files]
Source: "..\dist\PerfManager.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "perfmanager.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\PerfManager.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\PerfRemote.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\PerfUpdate.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\*.bat"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\LISEZMOI.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\remote\*"; DestDir: "{app}\remote"; Flags: ignoreversion recursesubdirs
Source: "..\release\*"; DestDir: "{app}\release"; Flags: ignoreversion recursesubdirs skipifsourcedoesntexist
; Tes profils ne sont jamais écrasés ni supprimés
Source: "..\profiles.json"; DestDir: "{app}"; Flags: onlyifdoesntexist uninsneveruninstall

[Icons]
Name: "{userprograms}\PerfManager"; Filename: "{app}\PerfManager.exe"; IconFilename: "{app}\perfmanager.ico"
Name: "{userprograms}\PerfManager - mise à jour"; Filename: "{app}\PerfUpdate.bat"; IconFilename: "{app}\perfmanager.ico"
Name: "{userdesktop}\PerfManager"; Filename: "{app}\PerfManager.exe"; IconFilename: "{app}\perfmanager.ico"; Tasks: desktopicon

[Run]
Filename: "{app}\PerfManager.exe"; Parameters: "{code:LaunchArgs}"; Description: "Lancer PerfManager"; Flags: postinstall nowait skipifsilent shellexec

[UninstallRun]
Filename: "schtasks.exe"; Parameters: "/Delete /TN PerfManager /F"; Flags: runhidden; RunOnceId: "DelTask"

[Code]
function LaunchArgs(Param: String): String;
begin
  if WizardIsTaskSelected('autostart') then
    Result := '--enable-autostart'
  else
    Result := '';
end;
