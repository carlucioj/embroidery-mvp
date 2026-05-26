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

### Flutter
```powershell
cd embroidery_mvp
flutter pub get
flutter run -d windows
```

### Python backend (obrigatório para processamento de qualidade)
```powershell
cd embroidery_mvp/python
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install rembg opencv-python-headless pyembroidery Pillow numpy fastapi uvicorn
python main.py  # modo MethodChannel (Desktop)
```

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
- Desktop: MethodChannel (`lib/infrastructure/python/python_bridge.dart`)
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
3. **Feedback sem backend** — UI coleta dados mas nunca envia. `TODO` em `adaptive_scaffold.dart:278`.
4. ~~Geração scanline simples~~ — **CORRIGIDO** (tatami fill diagonal + outline via `cv2.findContours` em `embroidery_converter.py`). Resize usa `Image.NEAREST` para preservar cores quantizadas.
5. **Estado não persiste** — fechar o app apaga o workflow. `workflow_persistence.dart` só salva prefs leves.

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
6. **Exportação .PES validada** contra specs Brother — próximo
7. Geração via IA (Claude API) — fase futura
