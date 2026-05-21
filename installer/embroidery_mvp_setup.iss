; Inno Setup Script — Embroidery MVP Installer
; Requires Inno Setup 6.x: https://jrsoftware.org/isinfo.php
;
; Build steps:
;   1. Run: pyinstaller python/embroidery_backend.spec
;   2. Run: flutter build windows --release
;   3. Open this file in Inno Setup Compiler and click Build
;
; Output: installer/Output/EmbroideryMVP_Setup.exe

#define AppName      "Embroidery MVP"
#define AppVersion   "0.1.0"
#define AppPublisher "Accio"
#define AppURL       "https://embroidery-mvp.com"
#define AppExeName   "embroidery_mvp.exe"
#define AlphaExpDays 90

[Setup]
AppId={{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
AppUpdatesURL={#AppURL}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
AllowNoIcons=yes
; Require Windows 10 64-bit or later
MinVersion=10.0.17763
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
OutputDir=Output
OutputBaseFilename=EmbroideryMVP_Setup_v{#AppVersion}
SetupIconFile=assets\app_icon.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
; Preserve user settings on upgrade
UsePreviousAppDir=yes

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "quicklaunchicon"; Description: "{cm:CreateQuickLaunchIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked; OnlyBelowVersion: 6.1; Check: not IsAdminInstallMode

[Files]
; Flutter Windows app
Source: "..\build\windows\x64\runner\Release\{#AppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\*.dll"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs
Source: "..\build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs

; Python backend (PyInstaller bundle)
Source: "..\python\dist\embroidery_backend\*"; DestDir: "{app}\python"; Flags: ignoreversion recursesubdirs

; Assets
Source: "..\assets\*"; DestDir: "{app}\assets"; Flags: ignoreversion recursesubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon
Name: "{userappdata}\Microsoft\Internet Explorer\Quick Launch\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: quicklaunchicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Registry]
; Store installation date for Alpha expiration check
Root: HKCU; Subkey: "Software\{#AppPublisher}\{#AppName}"; ValueType: string; ValueName: "InstallDate"; ValueData: "{code:GetInstallDate}"; Flags: createvalueifdoesntexist

[Code]
var
  InstallDateStr: string;

function GetInstallDate(Param: string): string;
var
  Y, M, D, H, Mi, S, MS: Word;
begin
  DecodeDate(Now, Y, M, D);
  Result := Format('%d-%2.2d-%2.2d', [Y, M, D]);
end;

function InitializeSetup(): Boolean;
begin
  Result := True;
  // Check for existing installation and warn about upgrade
  if RegValueExists(HKCU, 'Software\{#AppPublisher}\{#AppName}', 'InstallDate') then
  begin
    MsgBox(
      'Uma versão anterior do Embroidery MVP foi encontrada.' + #13#10 +
      'Suas configurações serão preservadas durante a atualização.',
      mbInformation,
      MB_OK
    );
  end;
end;
