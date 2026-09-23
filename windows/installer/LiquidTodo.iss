#ifndef MyAppName
  #define MyAppName "贝卡の Todo list"
#endif
#ifndef MyAppVersion
  #define MyAppVersion "2.0.0"
#endif
#define MyAppPublisher "lyyrebecca"
#define MyAppExeName "LiquidTodo.exe"
[Setup]
AppId={{D2B4E263-53C7-4F7B-B702-5CD1A920B1F6}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\LiquidTodo
DefaultGroupName={#MyAppName}
OutputDir=..\..\release
OutputBaseFilename=LiquidTodo-Windows-x64-Setup-v{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
PrivilegesRequired=lowest
UninstallDisplayIcon={app}\{#MyAppExeName}
[Files]
Source: "..\publish\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion
[Tasks]
Name: "autostart"; Description: "登录 Windows 时自动启动"; Flags: checkedonce
Name: "desktopicon"; Description: "创建桌面快捷方式"
[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon
[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "LiquidTodo"; ValueData: """{app}\{#MyAppExeName}"" --autostart"; Tasks: autostart; Flags: uninsdeletevalue
[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "启动 {#MyAppName}"; Flags: nowait postinstall skipifsilent
