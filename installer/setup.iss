; ============================================================
;  Inno Setup — Embroidery MVP  v0.1.0
; ============================================================
;
; Pré-requisitos (rodar na ordem abaixo antes de chamar o iscc):
;
;   1. flutter build windows --release
;
;   2. cd embroidery_mvp\python
;      .venv\Scripts\python.exe -m PyInstaller embroidery_backend.spec
;
; Gerar o instalador:
;   iscc embroidery_mvp\installer\setup.iss
;
; Saída: embroidery_mvp\installer\dist\EmbroideryMVP_Setup_0.1.0.exe
; ============================================================

#define AppName      "Embroidery MVP"
#define AppVersion   "0.1.0"
#define AppPublisher "Carlúcio Jr"
#define AppExeName   "embroidery_mvp.exe"

; Caminhos relativos ao diretório do script (installer\)
#define FlutterOut   "..\build\windows\x64\runner\Release"
#define PythonDist   "..\python\dist\embroidery_backend"

[Setup]
; GUID único para este app — NÃO alterar após primeira distribuição
AppId={{D4E5F6A7-B8C9-4D0E-1F2A-3B4C5D6E7F80}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={localappdata}\Programs\{#AppName}
DefaultGroupName={#AppName}
AllowNoIcons=yes
; Não requer elevação — instala na pasta do usuário
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=dist
OutputBaseFilename=EmbroideryMVP_Setup_{#AppVersion}
; Compressão máxima (LZMA2)
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
; Windows 10 64-bit mínimo
MinVersion=10.0.17763
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#AppExeName}
UninstallDisplayName={#AppName}
; Desabilita criação de ícone na área de trabalho por padrão
DisableProgramGroupPage=yes

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; ── Flutter app ───────────────────────────────────────────
Source: "{#FlutterOut}\{#AppExeName}";   DestDir: "{app}";        Flags: ignoreversion
Source: "{#FlutterOut}\*.dll";           DestDir: "{app}";        Flags: ignoreversion
Source: "{#FlutterOut}\data\*";          DestDir: "{app}\data";   Flags: ignoreversion recursesubdirs createallsubdirs

; ── Python engine ──────────────────────────────────────────
; O Flutter espera o engine em:  <exe_dir>\engine\embroidery_backend.exe
Source: "{#PythonDist}\*"; DestDir: "{app}\engine"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}";               Filename: "{app}\{#AppExeName}"
Name: "{group}\Desinstalar {#AppName}";   Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}";         Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
; Oferece abrir o app ao final da instalação
Filename: "{app}\{#AppExeName}"; Description: "Abrir {#AppName}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Remove a pasta de sessões criada em runtime
Type: filesandordirs; Name: "{localappdata}\embroidery_mvp"
