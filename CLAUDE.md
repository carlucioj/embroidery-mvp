# CLAUDE.md — Embroidery MVP

Plataforma de edição de bordado estilo PE-DESIGN NEXT com IA, para Windows Desktop (foco) + Android/iOS.

## Stack

- **Flutter 3.16+** — Windows desktop + mobile
- **Dart** — linguagem principal
- **Python 3.11+** — backend de processamento (rembg, pyembroidery, opencv)
- **BLoC** (`flutter_bloc`) — gerenciamento de estado
- **go_router** — navegação
- **pyembroidery** — geração de arquivos de bordado
- **rembg** — remoção de fundo com IA (U2Net)

## Como rodar

### Modo desenvolvimento (sem instalador)
```powershell
# Terminal 1 — engine Python
cd embroidery_mvp/python
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install rembg opencv-python-headless pyembroidery Pillow numpy fastapi uvicorn
python api_server.py  # HTTP server em localhost:8000

# Terminal 2 — Flutter
cd embroidery_mvp
flutter pub get
flutter run -d windows
```

### Gerar instalador
```powershell
# Requer: Inno Setup 6, Python venv configurado
flutter build windows --release   # usar drive sem acento se username tiver ú/ã/etc.
cd python && .\.venv\Scripts\python.exe -m PyInstaller embroidery_backend.spec -y
iscc installer\setup.iss          # → installer\dist\EmbroideryMVP_Setup_0.1.0.exe
```

> **Nota buildpath:** `flutter build windows` falha se o path contiver caracteres
> não-ASCII (bug MSBuild). Workaround: `subst B: "C:\Users\<user>\bordado"` e
> buildar em `B:\embroidery_mvp`.

### Testes
```powershell
flutter test                  # todos
flutter test test/domain/     # só domínio
flutter test test/application/ # só BLoC
```

## Arquitetura

Clean Architecture com 4 camadas:

```
lib/
├── domain/          # Modelos e interfaces abstratas (regras de negócio)
├── application/     # BLoC (workflow_bloc.dart) — máquina de estados de 6 etapas
├── infrastructure/  # Implementações concretas (Python bridge, HTTP, export)
└── presentation/    # Screens + widgets Flutter
```

**Fluxo de estado:** Onboarding → ImageCapture → ImageCleaning → Parameters → Generation → Export

**Comunicação Python:**
- Desktop (instalado): subprocess `engine\embroidery_backend.exe` spawned por `EngineLauncher` em localhost:8000
- Desktop (dev): `python api_server.py` rodando manualmente
- Mobile: HTTP REST API (`lib/infrastructure/http/processing_api_client.dart`)
- Fallback: Dart puro (`lib/infrastructure/image/dart_image_processor.dart`)

## Máquinas-alvo

**Prioridade:** Brother / Babylock → formatos `.PES`, `.PHC`
**Secundário:** Tajima → `.DST`
**Demais:** JEF, EXP, HUS, VIP, VP3, XXX, SEW, CSD, EMB, OFM (via pyembroidery)

## Decisões de escopo

- **Remoção de fundo:** sempre manual — o usuário escolhe a cada imagem (não automático)
- **Canvas:** interativo — design arrastável e redimensionável dentro do bastidor
- **Preview do bordado:** canvas Flutter com `CustomPainter` renderizando `StitchPath`
- **Exportação:** file_picker nativo (Windows) com detecção de USB

## Bugs conhecidos (NÃO introduzir regressões)

1. ~~ColorMapper race condition~~ — **CORRIGIDO** (`Completer` lock em `color_mapper.dart`).
2. ~~Preview não implementado~~ — **CORRIGIDO** (`HoopCanvas._paintStitchPaths` + `GenerationScreen` já conectados).
3. ~~Feedback sem backend~~ — **CORRIGIDO** (`_FeedbackDialogState._submit()` chama `WorkflowPersistence.savePendingFeedback()`; dados persistidos localmente em SharedPreferences, prontos para envio quando um backend for adicionado).
4. ~~Geração scanline simples~~ — **CORRIGIDO** (tatami fill diagonal + outline via `cv2.findContours` em `embroidery_converter.py`). Resize usa `Image.NEAREST` para preservar cores quantizadas.
5. ~~Estado não persiste~~ — **CORRIGIDO** (`WorkflowPersistence` salva sessão completa: bytes em `embroidery_session/`, metadados em SharedPreferences; debounce 500ms; restaurado no startup via `main.dart`).

## Convenções de código

- Sem comentários óbvios — só quando o "por quê" não é óbvio
- Strings de UI em português (o app é PT-BR)
- Erros customizados: usar as classes em `domain/` (`ImageProcessingException`, etc.)
- Estado: sempre via BLoC events, nunca `setState` em lógica de negócio
- Novos processamentos pesados: usar `compute()` (isolate) para não travar a UI

## Assets

- `assets/colors/madeira.json` — tabela de cores Madeira
- `assets/colors/isacord.json` — tabela de cores Isacord
- `assets/colors/brother.json` — tabela de cores Brother

Usados pelo `ColorMapper` para mapear cores ARGB para códigos de linha via distância CIE Lab.

## Prioridades de implementação

1. ~~Canvas interativo com bastidor~~ — FEITO
2. ~~Preview real dos pontos de bordado~~ — FEITO
3. ~~Conversão de imagem com seleção manual de remoção de fundo~~ — FEITO
4. ~~Algoritmo de fill tatami + outline (qualidade de máquina)~~ — FEITO
5. ~~Tipos de ponto editáveis~~ — FEITO (`StitchType` enum, seletor na ParametersScreen, 3 modos: fill/outline/satin)
6. ~~Exportação .PES validada~~ — FEITO (`_validate_output` em Python; `ValidationSeverity`/`DesignValidation` em Dart; `_ValidationCard` na ExportScreen; botão desabilitado em caso de erro)
7. ~~Persistência de sessão~~ — FEITO (sessão completa sobrevive reinicializações; PR #6)
8. ~~Vectorização via vtracer~~ — FEITO (`_vectorize_outline()` em `embroidery_converter.py`; vtracer polygon mode → contornos suaves; fallback automático para cv2.findContours se não instalado)
9. ~~Detecção de USB~~ — FEITO (`UsbDriveDetector` via PowerShell/WMI; `_UsbDrivesCard` na ExportScreen com polling 3s; cópia direta sem file picker)
10. ~~Instalador Windows~~ — FEITO (`installer/setup.iss`; `engine_launcher.dart`; PyInstaller spec; `EmbroideryMVP_Setup_0.1.0.exe` 96 MB)
11. **Geração via IA (Claude API)** — próximo (text prompt → embroidery design; maior diferencial competitivo)
