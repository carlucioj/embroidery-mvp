# Embroidery MVP

Aplicação multiplataforma Flutter que converte imagens em arquivos de bordado compatíveis com máquinas industriais e domésticas.

## Visão Geral

O Embroidery MVP guia o artesão passo a passo em cinco etapas:

1. **Importar Imagem** — Captura de foto (Mobile) ou importação de arquivo (Desktop)
2. **Limpar Arte** — Remoção automática de fundo e redução de cores
3. **Parâmetros** — Seleção de bastidor, tecido, tamanho e formato de saída
4. **Gerar Bordado** — Conversão para caminhos de pontos com pré-visualização
5. **Exportar** — Salvar arquivo de bordado no pendrive ou dispositivo

## Plataformas Suportadas

| Plataforma | Status |
|------------|--------|
| Windows Desktop | ✅ Suportado |
| Android | ✅ Suportado |
| iOS | ✅ Suportado |

## Requisitos

### Desktop (Windows)
- Windows 10 64-bit ou superior
- 8 GB RAM (mínimo)
- Processador Intel Core i3 8ª geração ou equivalente
- Flutter 3.16+
- Python 3.11+

### Mobile (Android/iOS)
- Android 8.0+ / iOS 13+
- 2 GB RAM (para processamento local)

## Instalação e Execução

### 1. Instalar Flutter

Siga as instruções em [flutter.dev/docs/get-started/install](https://flutter.dev/docs/get-started/install).

Verifique a instalação:
```bash
flutter doctor
```

### 2. Instalar dependências Flutter

```bash
cd embroidery_mvp
flutter pub get
```

### 3. Instalar dependências Python

```bash
cd python
pip install -r requirements.txt
```

### 4. Executar o app

**Desktop (Windows):**
```bash
flutter run -d windows
```

**Android:**
```bash
flutter run -d android
```

**iOS:**
```bash
flutter run -d ios
```

## Estrutura do Projeto

```
embroidery_mvp/
├── lib/
│   ├── main.dart                    # Entry point
│   ├── app.dart                     # Root widget
│   ├── core/
│   │   ├── theme.dart               # Tema visual (cores, tipografia)
│   │   ├── constants.dart           # Constantes do app
│   │   └── app_router.dart          # Roteamento
│   ├── domain/
│   │   ├── models/                  # Modelos de dados
│   │   │   ├── workflow_state.dart  # Estados do fluxo
│   │   │   ├── image_data.dart      # Dados de imagem
│   │   │   ├── embroidery_parameters.dart
│   │   │   └── embroidery_design.dart
│   │   └── interfaces/              # Interfaces abstratas
│   │       ├── image_processor.dart
│   │       ├── embroidery_converter.dart
│   │       └── export_manager.dart
│   ├── application/
│   │   └── workflow/                # BLoC de workflow
│   │       ├── workflow_bloc.dart
│   │       ├── workflow_event.dart
│   │       └── workflow_state_data.dart
│   ├── infrastructure/
│   │   ├── python/                  # Comunicação com Python (Desktop)
│   │   │   └── python_bridge.dart
│   │   └── http/                    # Cliente HTTP (Mobile)
│   │       └── processing_api_client.dart
│   └── presentation/
│       └── screens/                 # Telas do app
├── test/
│   ├── domain/                      # Testes de domínio
│   ├── application/                 # Testes de BLoC
│   ├── infrastructure/              # Testes de integração
│   └── presentation/                # Testes de widget
└── python/
    ├── requirements.txt             # Dependências Python
    ├── main.py                      # Entry point Python
    ├── image_processor.py           # Processamento de imagem
    ├── embroidery_converter.py      # Conversão para bordado
    └── method_channel_handler.py    # Handler MethodChannel
```

## Formatos de Saída Suportados

| Formato | Fabricante |
|---------|------------|
| `.DST`  | Tajima |
| `.PES`  | Brother / Babylock |
| `.JEF`  | Janome |
| `.EXP`  | Melco / Bernina |
| `.HUS`  | Husqvarna Viking |
| `.VIP`  | Husqvarna Viking / Pfaff |
| `.VP3`  | Husqvarna Viking / Pfaff |
| `.XXX`  | Singer |
| `.SEW`  | Elna / Janome |
| `.CSD`  | Poem / Singer / Husqvarna |
| `.EMB`  | Wilcom |
| `.OFM`  | Barudan |

## Executar Testes

```bash
# Todos os testes
flutter test

# Testes específicos
flutter test test/domain/
flutter test test/application/
```

## Arquitetura

O app segue uma arquitetura em camadas:

- **Apresentação** (`lib/presentation/`) — Telas e widgets Flutter
- **Aplicação** (`lib/application/`) — BLoCs e controllers
- **Domínio** (`lib/domain/`) — Modelos e interfaces
- **Infraestrutura** (`lib/infrastructure/`) — Implementações concretas

O processamento de imagem é delegado ao backend Python:
- **Desktop**: via MethodChannel (Python local)
- **Mobile**: via HTTP REST API (servidor remoto) com fallback local

## Contribuição

Este projeto está em desenvolvimento ativo. Consulte o arquivo `.kiro/specs/embroidery-mvp/tasks.md` para ver as tarefas pendentes.
