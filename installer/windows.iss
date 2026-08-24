; AudioVault Editor — Windows installer (Inno Setup 6)
; Build: install Inno Setup, then run:
;   ISCC.exe installer\windows.iss
; Requires a prior `flutter build windows --release`.

#define MyAppName "AudioVault Editor"
#define MyAppVersion "3.0.0"
#define MyAppExeName "audiovault_editor.exe"

[Setup]
AppId={{8E1B2C64-6F3A-4B7D-9C21-AVAEDITOR000}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
DefaultDirName={autopf}\AudioVaultEditor
DefaultGroupName={#MyAppName}
OutputBaseFilename=audiovault-editor-{#MyAppVersion}-setup
OutputDir=..\build\installer
Compression=lzma2
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
PrivilegesRequiredOverridesAllowed=dialog

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop icon"; GroupDescription: "Additional icons:"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent
