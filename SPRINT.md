# SPRINT — Análise de Complexidade + Refinamento por Escolha do Usuário

## Objetivo

Após a quantização de cores, o app analisa a imagem processada e classifica sua
complexidade (Simples / Moderada / Complexa). O usuário vê o resultado e decide:
- Prosseguir diretamente (qualquer nível)
- Ativar refinamento avançado (limpeza morfológica + simplificação de regiões)
- Buscar outra imagem (se complexidade alta e não quiser esperar)

**Princípio:** mostrar sempre o resultado básico primeiro. Refinamento é opt-in.

---

## HOJE — a implementar agora

### 1. `python/image_processor.py` ✅ FEITO
- [x] `analyze_complexity()` — score 0–135, níveis ≤30/≤60/>60
- [x] `_morphological_cleanup()` — open+close por cor, kernel elipse 5×5
- [x] `_simplify_regions()` — approxPolyDP + fillPoly por contorno
- [x] `process_image()` → retorna dict `{image_bytes, dominant_colors, complexity}`
- [x] Aceita `mode: "basic" | "advanced"`

### 2. `python/api_server.py` ✅ FEITO
- [x] Aceita campo `mode` no form
- [x] Retorna JSON `{imageBase64, dominantColors, complexity}`

### 3. `python/method_channel_handler.py` ✅ FEITO
- [x] `_handle_process_image()`: lê `mode`, extrai `image_bytes` do novo dict

### 4. `lib/domain/models/image_data.dart` ✅ FEITO
- [x] `ComplexityLevel` enum + `ImageComplexity` classe com `fromJson` + labels
- [x] `ProcessedImage.complexity: ImageComplexity?`

### 5. `lib/domain/interfaces/image_processor.dart` ✅ FEITO
- [x] `ProcessingOptions.advancedRefinement: bool = false`

### 6. `lib/infrastructure/http/processing_api_client.dart` ✅ FEITO
- [x] `ProcessingApiResult { imageBytes, dominantColors, complexity }`
- [x] `processImage()` → `ProcessingApiResult`, parse JSON, passa `mode`

### 7. `lib/infrastructure/image/remote_image_processor.dart` ✅ FEITO
- [x] Usa `ProcessingApiResult`, popula `complexity` em `ProcessedImage`

### 8. `lib/presentation/screens/image_cleaning_screen.dart` ✅ FEITO
- [x] `_ComplexityBadge` — badge colorido (verde/amarelo/vermelho) com score
- [x] `_RefinementCard` — visível para medium/complex, botões "Refinar" e "Trocar imagem"
- [x] `_refineImage()` — seta `_advancedRefinement = true`, re-processa
- [x] Botão "Aplicar Ajustes" reseta `_advancedRefinement = false`

---

## ESTA SEMANA

- [x] Exportação `.PES` validada contra specs Brother (CLAUDE.md prioridade #6) ✅ FEITO
  - `embroidery_converter.py`: `_validate_output()` — 6 checks (cores 0/64+/16+, pontos 0/500K+, PES magic bytes)
  - `embroidery_design.dart`: `ValidationSeverity`, `ValidationIssue`, `DesignValidation`, campo `validation` em `EmbroideryDesign`
  - `py_embroidery_converter.dart`: parse `validation` em `_buildDesign()`
  - `export_screen.dart`: `_ValidationCard` (verde/amarelo/vermelho), botão bloqueado em erro, tempo estimado no resumo
- [ ] Feedback backend — implementar envio real (`adaptive_scaffold.dart:278`)

---

## BACKLOG

- [x] Persistência de estado — FEITO (PR #6, `WorkflowPersistence`)
- [x] Feedback persistido localmente — FEITO (PR #7, `savePendingFeedback`)
- [x] Vectorização via vtracer — FEITO (`_vectorize_outline` em `embroidery_converter.py`)
- [ ] Detecção de USB para exportação automática
- [ ] Geração via Claude API (fase futura)

---

## Decisões de design

| Questão | Decisão |
|---|---|
| Quando analisar? | Após quantização, antes de mostrar preview |
| Score threshold | ≤30 simples, ≤60 moderado, >60 complexo |
| Refinamento é automático? | Não — opt-in pelo usuário |
| Mostrar resultado antes de refinar? | Sim — sempre mostrar básico primeiro |
| Kernel morfológico | Elipse 5×5 (balanceado ruído vs. detalhe) |
