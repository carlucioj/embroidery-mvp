import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../application/workflow/workflow_bloc.dart';
import '../../core/app_router.dart';
import '../../core/server_config.dart';
import '../../domain/interfaces/image_processor.dart';
import '../../domain/models/image_data.dart';
import '../../domain/models/workflow_state.dart';
import '../../infrastructure/image/dart_image_processor.dart';
import '../../infrastructure/image/remote_image_processor.dart';
import '../widgets/contextual_help_button.dart';

/// Step 2: Image cleaning screen.
///
/// Asks the user explicitly whether to remove the background, how many colors
/// to use, and what to include/exclude from the final embroidery.
/// Tries the remote server first (rembg quality), falls back to pure-Dart.
class ImageCleaningScreen extends StatefulWidget {
  const ImageCleaningScreen({super.key});

  @override
  State<ImageCleaningScreen> createState() => _ImageCleaningScreenState();
}

class _ImageCleaningScreenState extends State<ImageCleaningScreen> {
  // ── User options ────────────────────────────────────────────────────────────
  // Defaults to OFF — user must explicitly choose to remove background.
  bool _removeBackground = false;
  int _maxColors = 8;

  // ── Processing state ────────────────────────────────────────────────────────
  bool _isProcessing = false;
  double _progress = 0;
  String _progressStage = '';
  String? _errorMessage;
  ProcessedImage? _result;
  bool _usedServer = false;
  bool? _serverAvailable;

  @override
  void initState() {
    super.initState();
    _checkServer();
  }

  Future<void> _checkServer() async {
    final ok = await ServerConfig.checkHealth();
    if (mounted) setState(() => _serverAvailable = ok);
  }

  // ── Processing ──────────────────────────────────────────────────────────────

  Future<void> _cleanArt(ImageData image) async {
    setState(() {
      _isProcessing = true;
      _progress = 0;
      _progressStage = 'Iniciando...';
      _errorMessage = null;
      _result = null;
      _usedServer = false;
    });

    if (_serverAvailable == true) {
      final ok = await _tryServerProcessing(image);
      if (ok) return;
      setState(() => _progressStage = 'Servidor indisponível. Usando processamento local...');
    }

    await _dartProcessing(image);
  }

  Future<bool> _tryServerProcessing(ImageData image) async {
    final remote = RemoteImageProcessor();
    final sub = remote.progressStream.listen((p) {
      if (mounted) setState(() { _progress = p.percentage * 0.9; _progressStage = p.stage; });
    });
    try {
      setState(() => _progressStage = 'Enviando para o servidor...');
      final result = await remote.processImage(
        image,
        ProcessingOptions(
          removeBackground: _removeBackground,
          maxColors: _maxColors,
          mode: ProcessingMode.remote,
        ),
      );
      if (mounted) {
        setState(() { _isProcessing = false; _result = result.processedImage; _usedServer = true; });
        context.read<WorkflowBloc>().add(WorkflowImageCleaned(result.processedImage));
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      await sub.cancel();
      remote.dispose();
    }
  }

  Future<void> _dartProcessing(ImageData image) async {
    final dart = DartImageProcessor();
    final sub = dart.progressStream.listen((p) {
      if (mounted) setState(() { _progress = p.percentage; _progressStage = p.stage; });
    });
    try {
      final result = await dart.processImage(
        image,
        ProcessingOptions(
          removeBackground: _removeBackground,
          maxColors: _maxColors,
          mode: ProcessingMode.local,
        ),
      );
      if (mounted) {
        setState(() { _isProcessing = false; _result = result.processedImage; _usedServer = false; });
        context.read<WorkflowBloc>().add(WorkflowImageCleaned(result.processedImage));
      }
    } on ImageProcessingException catch (e) {
      if (mounted) setState(() { _isProcessing = false; _errorMessage = e.message; });
    } catch (e) {
      if (mounted) setState(() { _isProcessing = false; _errorMessage = 'Erro ao processar: $e'; });
    } finally {
      await sub.cancel();
      dart.dispose();
    }
  }

  void _skipCleaning(ImageData image) {
    final processed = ProcessedImage(
      bytes: image.bytes,
      colorCount: _maxColors,
      processingDurationMs: 0,
      dominantColors: const [],
    );
    context.read<WorkflowBloc>()
      ..add(WorkflowImageCleaned(processed))
      ..add(const WorkflowAdvanceRequested());
    context.go(AppRoutes.parameters);
  }

  void _advance() {
    context.read<WorkflowBloc>().add(const WorkflowAdvanceRequested());
    context.go(AppRoutes.parameters);
  }

  void _goBack() {
    context.read<WorkflowBloc>().add(const WorkflowGoBackRequested());
    context.go(AppRoutes.imageCapture);
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WorkflowBloc, WorkflowBlocState>(
      builder: (context, state) {
        final originalImage = state.capturedImage;
        if (originalImage == null) {
          return const Scaffold(body: Center(child: Text('Nenhuma imagem carregada.')));
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Preparar Arte'),
            actions: const [ContextualHelpButton(step: WorkflowStep.imageCleaning)],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _StepHeader(),
                const SizedBox(height: 12),

                _ServerStatusBadge(
                  available: _serverAvailable,
                  serverUrl: ServerConfig.url,
                  onConfigure: () => _showServerDialog(context),
                ),
                const SizedBox(height: 16),

                // ── Image comparison ──────────────────────────────────────
                _ImageComparison(
                  original: originalImage.bytes,
                  result: _result?.bytes,
                ),
                const SizedBox(height: 16),

                // ── Dominant color palette (after processing) ─────────────
                if (_result != null && _result!.dominantColors.isNotEmpty) ...[
                  _PaletteRow(colors: _result!.dominantColors),
                  const SizedBox(height: 16),
                ],

                // ── Options ───────────────────────────────────────────────
                _OptionsPanel(
                  removeBackground: _removeBackground,
                  maxColors: _maxColors,
                  onRemoveBackgroundChanged: (v) => setState(() => _removeBackground = v),
                  onMaxColorsChanged: (v) => setState(() => _maxColors = v),
                ),
                const SizedBox(height: 16),

                // ── Progress ──────────────────────────────────────────────
                if (_isProcessing) ...[
                  LinearProgressIndicator(
                    value: _progress,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _progressStage,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Error ─────────────────────────────────────────────────
                if (_errorMessage != null) ...[
                  _ErrorBanner(message: _errorMessage!),
                  const SizedBox(height: 16),
                ],

                // ── Success banner ────────────────────────────────────────
                if (_result != null && !_isProcessing) ...[
                  _SuccessBanner(colorCount: _result!.colorCount, usedServer: _usedServer),
                  const SizedBox(height: 16),
                ],

                // ── Action buttons ────────────────────────────────────────
                if (!_isProcessing) ...[
                  FilledButton.icon(
                    onPressed: () => _cleanArt(originalImage),
                    icon: const Icon(Icons.auto_fix_high),
                    label: Text(_result != null ? 'Aplicar Novamente' : 'Aplicar Ajustes'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _skipCleaning(originalImage),
                    icon: const Icon(Icons.skip_next),
                    label: const Text('Usar imagem original (pular etapa)'),
                  ),
                ],
              ],
            ),
          ),
          bottomNavigationBar: StepNavigationButtons(
            onBack: _goBack,
            onNext: _result != null ? _advance : null,
            nextLabel: 'Configurar Parâmetros',
            nextEnabled: _result != null,
            isLoading: _isProcessing,
          ),
        );
      },
    );
  }

  void _showServerDialog(BuildContext context) {
    final controller = TextEditingController(text: ServerConfig.url);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Configurar Servidor'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('URL do servidor Python (api_server.py).\nPadrão: http://localhost:8000'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'URL do servidor',
                hintText: 'http://localhost:8000',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(
            onPressed: () async {
              await ServerConfig.reset();
              controller.text = ServerConfig.url;
            },
            child: const Text('Padrão'),
          ),
          FilledButton(
            onPressed: () async {
              await ServerConfig.save(controller.text);
              if (ctx.mounted) Navigator.pop(ctx);
              _checkServer();
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _StepHeader extends StatelessWidget {
  const _StepHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Passo 2 de 5',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.primary, fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text('Preparar a Arte', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          'Escolha se quer remover o fundo e quantas cores usar no bordado.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ImageComparison extends StatelessWidget {
  const _ImageComparison({required this.original, required this.result});

  final Uint8List original;
  final Uint8List? result;

  @override
  Widget build(BuildContext context) {
    if (result == null) {
      return _ImageCard(label: 'Imagem Original', bytes: original);
    }
    return Row(
      children: [
        Expanded(child: _ImageCard(label: 'Original', bytes: original)),
        const SizedBox(width: 10),
        Expanded(
          child: _ImageCard(label: 'Resultado', bytes: result!, highlight: true),
        ),
      ],
    );
  }
}

class _ImageCard extends StatelessWidget {
  const _ImageCard({required this.label, required this.bytes, this.highlight = false});

  final String label;
  final Uint8List bytes;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: highlight ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
            fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          height: 160,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: highlight ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
              width: highlight ? 2 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            // Checkered background shows transparency
            child: Stack(
              children: [
                _CheckeredBackground(),
                Positioned.fill(child: Image.memory(bytes, fit: BoxFit.contain)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Checkered pattern to visualize transparent areas in processed images.
class _CheckeredBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _CheckerPainter(), child: const SizedBox.expand());
  }
}

class _CheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const cellSize = 12.0;
    final light = Paint()..color = Colors.white;
    final dark = Paint()..color = const Color(0xFFDDDDDD);

    int row = 0;
    for (double y = 0; y < size.height; y += cellSize, row++) {
      int col = 0;
      for (double x = 0; x < size.width; x += cellSize, col++) {
        canvas.drawRect(
          Rect.fromLTWH(x, y, cellSize, cellSize),
          (row + col) % 2 == 0 ? light : dark,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerPainter _) => false;
}

/// Shows extracted dominant colors as swatches with their hex codes.
class _PaletteRow extends StatelessWidget {
  const _PaletteRow({required this.colors});

  final List<int> colors; // ARGB ints

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Cores extraídas',
          style: Theme.of(context)
              .textTheme
              .labelMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: colors.take(16).map((argb) {
            final hex =
                '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
            return Tooltip(
              message: hex,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Color(argb | 0xFF000000),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.black12),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _OptionsPanel extends StatelessWidget {
  const _OptionsPanel({
    required this.removeBackground,
    required this.maxColors,
    required this.onRemoveBackgroundChanged,
    required this.onMaxColorsChanged,
  });

  final bool removeBackground;
  final int maxColors;
  final ValueChanged<bool> onRemoveBackgroundChanged;
  final ValueChanged<int> onMaxColorsChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Opções de Ajuste',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            // ── Background removal ──────────────────────────────────────
            _BackgroundRemovalOption(
              value: removeBackground,
              onChanged: onRemoveBackgroundChanged,
            ),

            const Divider(height: 28),

            // ── Color count ─────────────────────────────────────────────
            _ColorCountOption(
              value: maxColors,
              onChanged: onMaxColorsChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _BackgroundRemovalOption extends StatelessWidget {
  const _BackgroundRemovalOption({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Remover fundo?',
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    value
                        ? 'O fundo será removido (transparente no resultado).'
                        : 'O fundo será mantido na imagem.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
        if (value)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'A remoção detecta a cor mais comum nas bordas da imagem. '
                      'Funciona melhor com fundos lisos (branco, cinza, cor única).',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ColorCountOption extends StatelessWidget {
  const _ColorCountOption({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  static const _presets = [
    (label: 'Simples', count: 4, hint: 'Menos detalhes, bordado rápido'),
    (label: 'Normal', count: 8, hint: 'Balanceado — recomendado'),
    (label: 'Detalhado', count: 16, hint: 'Mais cores, mais trocas de linha'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Número de cores',
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$value cores',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Quick presets
        Row(
          children: _presets.map((p) {
            final selected = value == p.count;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Tooltip(
                  message: p.hint,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: selected
                          ? theme.colorScheme.primaryContainer
                          : null,
                      side: BorderSide(
                        color: selected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outlineVariant,
                        width: selected ? 2 : 1,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onPressed: () => onChanged(p.count),
                    child: Text(
                      p.label,
                      style: TextStyle(
                        fontSize: 12,
                        color: selected
                            ? theme.colorScheme.onPrimaryContainer
                            : null,
                        fontWeight: selected ? FontWeight.bold : null,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),

        // Fine-grained slider
        Slider(
          value: value.toDouble(),
          min: 2,
          max: 16,
          divisions: 14,
          label: '$value',
          onChanged: (v) => onChanged(v.round()),
        ),
        Text(
          'Menos cores = troca de linha menos vezes. '
          'Mais cores = resultado mais fiel à imagem.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ServerStatusBadge extends StatelessWidget {
  const _ServerStatusBadge({
    required this.available,
    required this.serverUrl,
    required this.onConfigure,
  });

  final bool? available;
  final String serverUrl;
  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (icon, color, label) = switch (available) {
      null => (Icons.sync, theme.colorScheme.onSurfaceVariant, 'Verificando servidor...'),
      true => (Icons.cloud_done, Colors.green.shade700, 'Servidor conectado — IA ativa (rembg)'),
      false => (Icons.cloud_off, theme.colorScheme.onSurfaceVariant,
          'Servidor offline — processamento local'),
    };

    return InkWell(
      onTap: onConfigure,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label,
                  style: theme.textTheme.bodySmall?.copyWith(color: color)),
            ),
            Icon(Icons.settings, size: 14, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _SuccessBanner extends StatelessWidget {
  const _SuccessBanner({required this.colorCount, required this.usedServer});

  final int colorCount;
  final bool usedServer;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Ajuste aplicado! $colorCount cores. '
              '${usedServer ? "Processado com IA (rembg)." : "Processado localmente."}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onErrorContainer)),
          ),
        ],
      ),
    );
  }
}
