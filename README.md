# Embroidery MVP

> **Converta qualquer imagem em arquivo de bordado — sem pagar R$1.500 em software proprietário.**

Aplicação Flutter multiplataforma que transforma fotos e ilustrações em arquivos de bordado compatíveis com as principais máquinas do mercado (Brother, Tajima, Janome, Singer e outras 8 marcas), com validação automática antes da exportação para garantir que o arquivo funcione na máquina.

---

## Por que esse app existe

Software profissional de digitização de bordado (PE-Design Next, Hatch Embroidery, Wilcom) custa entre **R$1.200 e R$5.000** e roda apenas no Windows. Para quem tem uma máquina Brother em casa ou num pequeno ateliê e quer bordar uma foto de família, um logotipo ou uma arte personalizada, a única alternativa acessível hoje é pagar por uma conversão online de qualidade duvidosa ou aprender uma ferramenta industrial complexa.

Este projeto é a alternativa: **gratuita, open-source, guiada por IA, e que funciona no celular**.

---

## Demonstração do fluxo

```
📷 Importar Imagem
        ↓
🎨 Limpar Arte (IA remove fundo, escolha de refinamento)
        ↓
📐 Parâmetros (bastidor, tecido, tamanho, tipo de ponto)
        ↓
🪡 Gerar Bordado (tatami fill + preview interativo)
        ↓
✅ Validar + Exportar (.PES, .DST, .JEF e mais 9 formatos)
```

---

## Funcionalidades

### Processamento de imagem com IA
- Remoção de fundo automática via **U2Net** (rembg) — sem fundo branco residual
- Redução de cores por **K-means clustering** — mantém fidelidade às cores reais
- **Análise de complexidade** antes de decidir o nível de processamento:
  - Score 0–135 com três níveis: Simples / Moderado / Complexo
  - Métricas: cores únicas, densidade de bordas, regiões conectadas
- **Refinamento por escolha do usuário** — sem surpresas:
  - *Sem refinamento* — resultado básico, rápido
  - *Refinamento Leve* — kernel 3×3, remove ruído sem apagar traços finos (ideal para arte em chalk, stickers)
  - *Refinamento Intenso* — kernel 5×5 + simplificação de polígonos (ideal para fotos)

### Geração de pontos profissional
- **Tatami fill diagonal** (45°, boustrophedon) — padrão industrial, sem listras
- **Contorno em ponto de corrida** por região de cor
- **Satim horizontal** para formas estreitas e letras
- Preview interativo dos caminhos de ponto no canvas do bastidor

### Exportação com validação
Antes de salvar, o app valida automaticamente o arquivo contra as especificações das máquinas:

| Verificação | Tipo | Detalhe |
|-------------|------|---------|
| Nenhuma cor encontrada | Erro | Bloqueia exportação |
| Mais de 64 cores | Erro | Bloqueia exportação |
| Mais de 16 cores | Aviso | Máquinas Brother consumer suportam até 16 |
| Nenhum ponto gerado | Erro | Bloqueia exportação |
| Mais de 500K pontos | Aviso | Pode exceder limite de algumas máquinas |
| Cabeçalho `.PES` inválido (`#PES`) | Erro | Bloqueia exportação |

### 12 formatos de saída
| Formato | Fabricante / Compatibilidade |
|---------|------------------------------|
| `.PES` | **Brother, Babylock** — validado contra magic bytes `#PES` |
| `.DST` | **Tajima** — padrão industrial mundial |
| `.JEF` | **Janome** |
| `.EXP` | **Melco, Bernina** |
| `.HUS` | **Husqvarna Viking** |
| `.VIP` | **Husqvarna Viking, Pfaff** |
| `.VP3` | **Husqvarna Viking, Pfaff** |
| `.XXX` | **Singer** |
| `.SEW` | **Elna, Janome** |
| `.CSD` | **Poem, Singer, Husqvarna** |
| `.EMB` | **Wilcom** |
| `.OFM` | **Barudan** |

---

## Plataformas

| Plataforma | Status | Método de processamento |
|------------|--------|------------------------|
| **Windows Desktop** | ✅ Suportado | Engine Python embutido (subprocess automático) |
| **Android** | ✅ Suportado | HTTP REST API (servidor local ou nuvem) |
| **iOS** | ✅ Suportado | HTTP REST API (servidor local ou nuvem) |

---

## Requisitos

### Usuário Final (Windows) — instalador
- Windows 10 64-bit (build 17763+) ou superior
- 4 GB RAM (mínimo), 8 GB RAM (recomendado para rembg)
- ~200 MB de espaço livre

### Desenvolvedor — build from source
- Flutter 3.16+, Python 3.11+, PyInstaller, Inno Setup 6

### Mobile
- Android 8.0+ / iOS 13+
- Servidor Python rodando em rede local ou VPS

---

## Instalação

### Modo fácil — instalador pré-compilado (recomendado)

1. Baixe `EmbroideryMVP_Setup_0.1.0.exe` da página de releases
2. Execute o instalador (não requer admin — instala em `%LOCALAPPDATA%`)
3. Abra o app pelo atalho criado

> **Primeira execução:** o modelo de IA U2Net (~170 MB) é baixado automaticamente
> em `~\.u2net\` na primeira vez que você processar uma imagem.

### Modo desenvolvedor — build from source

#### 1. Clonar e instalar dependências Flutter

```bash
git clone https://github.com/carlucioj/embroidery-mvp.git
cd embroidery-mvp/embroidery_mvp
flutter pub get
```

#### 2. Configurar backend Python

```powershell
cd python
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install rembg opencv-python-headless pyembroidery Pillow numpy fastapi uvicorn
```

#### 3. Rodar em modo desenvolvimento

**Terminal 1 — servidor Python (obrigatório):**
```powershell
# Dentro da pasta python/, com o venv ativado:
python api_server.py
# Ou: duplo clique em INICIAR_SERVIDOR.bat
```

**Terminal 2 — app Flutter:**
```bash
flutter run -d windows   # Desktop
flutter run -d android   # Mobile
```

#### 4. Gerar o instalador (opcional)

```powershell
# 1. Build Flutter
flutter build windows --release

# 2. Build engine Python
cd python
.\.venv\Scripts\python.exe -m PyInstaller embroidery_backend.spec -y

# 3. Gerar Setup.exe
iscc installer\setup.iss
# → installer\dist\EmbroideryMVP_Setup_0.1.0.exe (≈ 96 MB)
```

---

## Testes

### Flutter
```bash
flutter test                  # todos os testes
flutter test test/domain/     # somente domínio
flutter test test/application/ # somente BLoC
```

### Python
```bash
cd python
pytest test_image_processor.py -v
```

---

## Arquitetura

Clean Architecture em 4 camadas:

```
lib/
├── domain/          # Modelos e interfaces (regras de negócio)
├── application/     # BLoC (workflow_bloc.dart) — máquina de 6 estados
├── infrastructure/  # Implementações (Python bridge, HTTP, export)
└── presentation/    # Screens + widgets Flutter
```

```
python/
├── image_processor.py        # rembg + K-means + análise de complexidade
├── embroidery_converter.py   # tatami fill + validação de saída
├── api_server.py             # FastAPI REST (Desktop embutido + Mobile remoto)
├── embroidery_backend.spec   # PyInstaller — empacota api_server.py → .exe
└── main.py                   # Entry point MethodChannel (legado)
```

```
installer/
└── setup.iss                 # Inno Setup — gera EmbroideryMVP_Setup_X.Y.Z.exe
```

**Comunicação Python:**
- Desktop (instalado) → subprocess `engine\embroidery_backend.exe` spawned pelo Flutter, HTTP loopback 127.0.0.1:8000
- Desktop (dev) → `python api_server.py` rodando manualmente
- Mobile → HTTP REST API (FastAPI, pode rodar em VPS)
- Fallback → Dart puro (processamento simplificado sem rembg)

---

## Roadmap

| Prioridade | Feature | Status |
|-----------|---------|--------|
| 1 | Canvas interativo com bastidor | ✅ Feito |
| 2 | Preview real dos pontos de bordado | ✅ Feito |
| 3 | Conversão com remoção de fundo por IA | ✅ Feito |
| 4 | Tatami fill diagonal + outline (qualidade industrial) | ✅ Feito |
| 5 | Tipos de ponto editáveis (fill / outline / satin) | ✅ Feito |
| 6 | Análise de complexidade + refinamento por escolha | ✅ Feito |
| 7 | Exportação `.PES` validada contra specs Brother | ✅ Feito |
| 8 | Vectorização automática via vtracer | ✅ Feito |
| 9 | Detecção de USB para exportação automática | ✅ Feito |
| 10 | Pipeline completo para todos os 12 formatos | ✅ Feito |
| 11 | Instalador Windows (.exe) com engine embutido | ✅ Feito |
| 12 | Geração via IA (Claude API) | 🔜 Em planejamento |

---

## Contribuição

Issues e PRs são bem-vindos. Use o fluxo Gitflow:

- `main` — versão estável
- `develop` — integração contínua
- `feature/<nome>` — funcionalidades em desenvolvimento

Veja o arquivo [SPRINT.md](SPRINT.md) para tarefas em andamento e [CLAUDE.md](CLAUDE.md) para convenções do projeto.

---

## Licença

MIT — use, modifique e distribua livremente.
