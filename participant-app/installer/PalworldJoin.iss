#ifndef MyAppVersion
  #define MyAppVersion "0.2.0"
#endif

#define MyAppName "Palworld Join"
#define MyAppExeName "PalworldJoin.exe"

[Setup]
AppId={{D6B30B9B-7C39-4D39-91BA-F02FC4CE04AA}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=Woollest
AppPublisherURL=https://github.com/Woollest/palworld-unlim-server
DefaultDirName={localappdata}\Programs\Palworld Join
DefaultGroupName=Palworld Join
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..\..\dist\installer
OutputBaseFilename=Palworld-Join-Setup-PREVIEW-{#MyAppVersion}
SetupIconFile=..\..\desktop\src-tauri\icons\icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
RestartApplications=no
VersionInfoVersion={#MyAppVersion}.0
VersionInfoDescription=Palworld Join PREVIEW installer
VersionInfoProductName=Palworld Join
VersionInfoCompany=Woollest
VersionInfoCopyright=Powered by Unlim

[Languages]
Name: "japanese"; MessagesFile: "compiler:Languages\Japanese.isl"

[Tasks]
Name: "desktopicon"; Description: "デスクトップにショートカットを作成する"; GroupDescription: "追加アイコン:"; Flags: checkedonce

[Files]
Source: "..\..\dist\PalworldJoin\PalworldJoin.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}"; DestName: "README.txt"; Flags: ignoreversion

[Icons]
Name: "{group}\Palworld Join"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{group}\アンインストール"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Palworld Join"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Palworld Joinを起動する"; Flags: nowait postinstall skipifsilent
