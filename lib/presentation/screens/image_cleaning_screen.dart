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
/// Optional step. Tries the remote server first (rembg quality),
/// falls back to pure-Dart processing if server is unavailable.
///
/// Options:
///   - Remove background (on/off)
///   - Number of colors (2–16)
///   - Skip entirely
class ImageCleaningScreen extends StatefulWidget {
  const ImageCleaningScreen({super.key});

  @override
  State<ImageCleaningScreen> createState() => _ImageCleaningScreenState();
}

class _ImageCleaningScreenState extends State<ImageCleaningScreen> {
  // Options
  bool _removeBackground = true;
  int _maxColors = 8;

  // State
  bool _isProcessing = false;
  double _progress = 0;
  String _progressStage = '';
  String? _errorMessage;
  ProcessedImage? _result;
  bool _usedServer = false;

  // Server status
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

  Future<void> _cleanArt(ImageData image) async {
    debugPrint('[CleanArt] Starting. serverAvailable=$_serverAvailable');
    setState(() {
      _isProcessing = true;
      _progress = 0;
      _progressStage = 'Iniciando...';
      _errorMessage = null;
      _result = null;
      _usedServer = false;
    });

    // Try server first if available
    if (_serverAvailable == true) {
      debugPrint('[CleanArt] Trying server...');
      final success = await _tryServerProcessing(image);
      if (success) {
        debugPrint('[CleanArt] Server succeeded.');
        return;
      }
      debugPrint('[CleanArt] Server failed, falling back to Dart.');
      setState(() => _progressStage = 'Servidor indisponível. Usando processamento local...');
    } else {
      debugPrint('[CleanArt] Server not available ($_serverAvailable), using Dart directly.');
    }

    // Dart fallback
    await _dartProcessing(image);
  }

  Future<bool> _tryServerProcessing(ImageData image) async {
    final remote = RemoteImageProcessor();
    final sub = remote.progressStream.listen((p) {
      if (mounted) {
        setState(() {
          _progress = p.percentage * 0.9;
          _progressStage = '🌐 ${p.stage}';
        });
      }
    });

    try {
      setState(() => _progressStage = '🌐 Enviando para o servidor...');

      final result = await remote.processImage(
        image,
        ProcessingOptions(
          removeBackground: _removeBackground,
          maxColors: _maxColors,
          mode: ProcessingMode.remote,
        ),
      );

      if (mounted) {
        setState(() {
          _isProcessing = false;
          _result = result.processedImage;
          _usedServer = true;
        });
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
    debugPrint('[CleanArt] Starting Dart processing...');
    final dart = DartImageProcessor();
    final sub = dart.progressStream.listen((p) {
      debugPrint('[CleanArt] Dart progress: ${p.percentage} - ${p.stage}');
      if (mounted) {
        setState(() {
          _progress = p.percentage;
          _progressStage = '💻 ${p.stage}';
        });
      }
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

      debugPrint('[CleanArt] Dart processing succeeded. bytes=${result.processedImage.bytes.length}');

      if (mounted) {
        setState(() {
          _isProcessing = false;
          _result = result.processedImage;
          _usedServer = false;
        });
        context.read<WorkflowBloc>().add(WorkflowImageCleaned(result.processedImage));
      }
    } on ImageProcessingException catch (e) {
      debugPrint('[CleanArt] ImageProcessingException: ${e.message}');
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _errorMessage = e.message;
        });
      }
    } catch (e, stack) {
      debugPrint('[CleanArt] Unexpected error: $e\n$stack');
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _errorMessage = 'Erro ao processar imagem: $e';
        });
      }
    } finally {
      await sub.cancel();
      dart.dispose();
    }
  }

  /// Skip cleaning — use the original image as-is.
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

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WorkflowBloc, WorkflowBlocState>(
      builder: (context, state) {
        final originalImage = state.capturedImage;

        if (originalImage == null) {
          return const Scaffold(
            body: Center(child: Text('Nenhuma imagem carregada.')),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Preparar Arte'),
            actions: const [
              ContextualHelpButton(step: WorkflowStep.imageCleaning),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _StepHeader(
                  stepNumber: 2,
                  title: 'Preparar a Arte',
                  subtitle:
                      'Ajuste a imagem antes de gerar o bordado. '
                      'Esta etapa é opcional.',
                ),

                const SizedBox(height: 12),

                // Server status indicator
                _ServerStatusBadge(
                  available: _serverAvailable,
                  serverUrl: ServerConfig.url,
                  onConfigure: () => _showServerDialog(context),
                ),

                const SizedBox(height: 16),

                // Image preview
                if (_result != null) ...[
                  Row(
                    children: [
                      Expanded(
                        child: _ImageCard(
                          label: 'Original',
                          bytes: originalImage.bytes,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ImageCard(
                          label: 'Resultado',
                          bytes: _result!.bytes,
                          highlight: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SuccessBanner(
                    colorCount: _result!.colorCount,
                    usedServer: _usedServer,
                  ),
                ] else ...[
                  _ImageCard(
                    label: 'Imagem Original',
                    bytes: originalImage.bytes,
                  ),
                ],

                const SizedBox(height: 20),

                // Options
                _OptionsCard(
                  removeBackground: _removeBackground,
                  maxColors: _maxColors,
                  onRemoveBackgroundChanged: (v) =>
                      setState(() => _removeBackground = v),
                  onMaxColorsChanged: (v) => setState(() => _maxColors = v),
                ),

                const SizedBox(height: 16),

                // Progress
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

                // Error
                if (_errorMessage != null) ...[
                  _ErrorBanner(message: _errorMessage!),
                  const SizedBox(height: 16),
                ],

                // Buttons
                if (!_isProcessing) ...[
                  FilledButton.icon(
                    onPressed: () => _cleanArt(originalImage),
                    icon: const Icon(Icons.auto_fix_high),
                    label: Text(
                      _result != null ? 'Aplicar Novamente' : 'Aplicar Ajustes',
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _skipCleaning(originalImage),
                    icon: const Icon(Icons.skip_next),
                    label: const Text('Pular esta etapa'),
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
            const Text(
              'URL do servidor Python (api_server.py).\n'
              'Padrão: http://localhost:8000',
            ),
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
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
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
  const _StepHeader({
    required this.stepNumber,
    required this.title,
    required this.subtitle,
  });

  final int stepNumber;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Passo $stepNumber de 5',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(title, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
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
      true => (Icons.cloud_done, Colors.green, 'Servidor conectado — processamento com IA'),
      false => (Icons.cloud_off, theme.colorScheme.onSurfaceVariant,
          'Servidor offline — usando processamento local'),
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
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(color: color),
              ),
            ),
            Icon(Icons.settings, size: 14,
                color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _OptionsCard extends StatelessWidget {
  const _OptionsCard({
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
            Text(
              'Opções de Ajuste',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            // Remove background toggle
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Remover fundo',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w500),
                      ),
                      Text(
                        'Remove a cor de fundo da imagem',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: removeBackground,
                  onChanged: onRemoveBackgroundChanged,
                ),
              ],
            ),

            const Divider(height: 24),

            // Color count slider
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Número de cores',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$maxColors cores',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            Slider(
              value: maxColors.toDouble(),
              min: 2,
              max: 16,
              divisions: 14,
              label: '$maxColors',
              onChanged: (v) => onMaxColorsChanged(v.round()),
            ),
            Text(
              'Menos cores = bordado mais simples. '
              'Mais cores = mais detalhes.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuccessBanner extends StatelessWidget {
  const _SuccessBanner({
    required this.colorCount,
    required this.usedServer,
  });

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
          Icon(Icons.check_circle,
              color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Ajuste aplicado! $colorCount cores. '
              '${usedServer ? "Processado pelo servidor (IA)." : "Processado localmente."}',
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
          Icon(Icons.error_outline,
              color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageCard extends StatelessWidget {
  const _ImageCard({
    required this.label,
    required this.bytes,
    this.highlight = false,
  });

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
            color: highlight
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
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
              color: highlight
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              width: highlight ? 2 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(bytes, fit: BoxFit.contain),
          ),
        ),
      ],
    );
  }
}
