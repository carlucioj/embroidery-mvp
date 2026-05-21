import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../application/workflow/workflow_bloc.dart';
import '../../core/app_router.dart';
import '../../domain/interfaces/embroidery_converter.dart';
import '../../domain/models/embroidery_design.dart';
import '../../domain/models/workflow_state.dart';
import '../../infrastructure/embroidery/py_embroidery_converter.dart';
import '../widgets/contextual_help_button.dart';

/// Step 4: Embroidery generation and preview screen.
///
/// Shows a "Gerar Bordado" button that triggers conversion.
/// After generation, renders a preview of stitch paths with metrics.
/// Tapping a color highlights its path and shows thread codes.
class GenerationScreen extends StatefulWidget {
  const GenerationScreen({super.key});

  @override
  State<GenerationScreen> createState() => _GenerationScreenState();
}

class _GenerationScreenState extends State<GenerationScreen> {
  final _converter = PyEmbroideryConverter();

  bool _isGenerating = false;
  double _progress = 0;
  String _progressStage = '';
  String? _errorMessage;
  EmbroideryDesign? _design;
  int? _selectedColorIndex;

  @override
  void dispose() {
    _converter.dispose();
    super.dispose();
  }

  Future<void> _generate(WorkflowBlocState state) async {
    final image = state.cleanedImage;
    final params = state.parameters;

    if (image == null || params == null) return;

    setState(() {
      _isGenerating = true;
      _progress = 0;
      _progressStage = 'Iniciando conversão...';
      _errorMessage = null;
      _design = null;
      _selectedColorIndex = null;
    });

    final sub = _converter.progressStream.listen((p) {
      if (mounted) {
        setState(() {
          _progress = p.percentage;
          _progressStage = p.stage;
        });
      }
    });

    try {
      final design = await _converter.convertToEmbroidery(image, params);

      if (mounted) {
        setState(() {
          _isGenerating = false;
          _design = design;
        });
        context.read<WorkflowBloc>().add(WorkflowDesignGenerated(design));
      }
    } on EmbroideryConversionException catch (e) {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _errorMessage = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _errorMessage = 'Erro ao gerar bordado. Tente novamente.';
        });
      }
    } finally {
      await sub.cancel();
    }
  }

  void _advance() {
    context.read<WorkflowBloc>().add(const WorkflowAdvanceRequested());
    context.go(AppRoutes.export);
  }

  void _goBack() {
    context.read<WorkflowBloc>().add(const WorkflowGoBackRequested());
    context.go(AppRoutes.parameters);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WorkflowBloc, WorkflowBlocState>(
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Gerar Bordado'),
            actions: const [
              ContextualHelpButton(step: WorkflowStep.generation),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _StepHeader(
                  stepNumber: 4,
                  title: 'Gerar Bordado',
                  subtitle: 'Visualize os caminhos de pontos antes de exportar.',
                ),
                const SizedBox(height: 24),

                // Preview area
                _PreviewArea(
                  design: _design,
                  isGenerating: _isGenerating,
                  selectedColorIndex: _selectedColorIndex,
                  onColorTap: (i) => setState(() => _selectedColorIndex = i),
                ),

                const SizedBox(height: 16),

                // Progress
                if (_isGenerating) ...[
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

                // Metrics
                if (_design != null) ...[
                  _MetricsCard(design: _design!),
                  const SizedBox(height: 16),
                  _ColorList(
                    design: _design!,
                    selectedIndex: _selectedColorIndex,
                    onTap: (i) => setState(() => _selectedColorIndex = i),
                  ),
                  const SizedBox(height: 16),
                ],

                // Generate button
                if (!_isGenerating)
                  FilledButton.icon(
                    onPressed: () => _generate(state),
                    icon: const Icon(Icons.auto_awesome),
                    label: Text(
                      _design != null ? 'Gerar Novamente' : 'Gerar Bordado',
                    ),
                  ),
              ],
            ),
          ),
          bottomNavigationBar: StepNavigationButtons(
            onBack: _goBack,
            onNext: _design != null ? _advance : null,
            nextLabel: 'Exportar',
            nextEnabled: _design != null,
            isLoading: _isGenerating,
          ),
        );
      },
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

class _PreviewArea extends StatelessWidget {
  const _PreviewArea({
    required this.design,
    required this.isGenerating,
    required this.selectedColorIndex,
    required this.onColorTap,
  });

  final EmbroideryDesign? design;
  final bool isGenerating;
  final int? selectedColorIndex;
  final ValueChanged<int> onColorTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 280,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: isGenerating
            ? const Center(child: CircularProgressIndicator())
            : design == null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.preview_outlined,
                        size: 64,
                        color: theme.colorScheme.outlineVariant,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Clique em "Gerar Bordado" para ver a prévia',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  )
                : _StitchPreviewCanvas(
                    design: design!,
                    selectedColorIndex: selectedColorIndex,
                    onColorTap: onColorTap,
                  ),
      ),
    );
  }
}

/// Simple canvas that renders stitch paths as colored lines.
class _StitchPreviewCanvas extends StatelessWidget {
  const _StitchPreviewCanvas({
    required this.design,
    required this.selectedColorIndex,
    required this.onColorTap,
  });

  final EmbroideryDesign design;
  final int? selectedColorIndex;
  final ValueChanged<int> onColorTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapUp: (details) {
        // Cycle through colors on tap
        if (design.colors.isEmpty) return;
        final next = ((selectedColorIndex ?? -1) + 1) % design.colors.length;
        onColorTap(next);
      },
      child: CustomPaint(
        painter: _StitchPainter(
          design: design,
          selectedColorIndex: selectedColorIndex,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _StitchPainter extends CustomPainter {
  const _StitchPainter({required this.design, this.selectedColorIndex});

  final EmbroideryDesign design;
  final int? selectedColorIndex;

  @override
  void paint(Canvas canvas, Size size) {
    if (design.stitchPaths.isEmpty) {
      // Draw placeholder grid
      final paint = Paint()
        ..color = Colors.grey.withValues(alpha: 0.3)
        ..strokeWidth = 1;
      for (double x = 0; x < size.width; x += 20) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      }
      for (double y = 0; y < size.height; y += 20) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
      return;
    }

    // Find bounding box of all points
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    for (final path in design.stitchPaths) {
      for (int i = 0; i < path.points.length - 1; i += 2) {
        final x = path.points[i];
        final y = path.points[i + 1];
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
      }
    }

    final rangeX = maxX - minX;
    final rangeY = maxY - minY;
    if (rangeX == 0 || rangeY == 0) return;

    final scaleX = (size.width - 32) / rangeX;
    final scaleY = (size.height - 32) / rangeY;
    final scale = scaleX < scaleY ? scaleX : scaleY;
    final offsetX = (size.width - rangeX * scale) / 2;
    final offsetY = (size.height - rangeY * scale) / 2;

    for (final stitchPath in design.stitchPaths) {
      final colorIndex = stitchPath.colorIndex;
      final isSelected = selectedColorIndex == colorIndex;
      final color = colorIndex < design.colors.length
          ? Color(design.colors[colorIndex].argb | 0xFF000000)
          : Colors.grey;

      final paint = Paint()
        ..color = isSelected ? color : color.withValues(alpha: 0.5)
        ..strokeWidth = isSelected ? 2.0 : 1.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final points = stitchPath.points;
      if (points.length < 4) continue;

      final path = Path();
      path.moveTo(
        (points[0] - minX) * scale + offsetX,
        (points[1] - minY) * scale + offsetY,
      );

      for (int i = 2; i < points.length - 1; i += 2) {
        path.lineTo(
          (points[i] - minX) * scale + offsetX,
          (points[i + 1] - minY) * scale + offsetY,
        );
      }

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_StitchPainter old) =>
      old.design != design || old.selectedColorIndex != selectedColorIndex;
}

class _MetricsCard extends StatelessWidget {
  const _MetricsCard({required this.design});

  final EmbroideryDesign design;

  @override
  Widget build(BuildContext context) {
    final m = design.metrics;
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Métricas do Design',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                _MetricItem(
                    label: 'Pontos', value: m.totalStitches.toString()),
                _MetricItem(
                    label: 'Trocas de cor',
                    value: m.colorChangeCount.toString()),
                _MetricItem(
                    label: 'Tamanho',
                    value:
                        '${m.widthMm.toStringAsFixed(0)}×${m.heightMm.toStringAsFixed(0)} mm'),
                _MetricItem(
                    label: 'Tempo est.',
                    value: '${m.estimatedMinutes.toStringAsFixed(0)} min'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricItem extends StatelessWidget {
  const _MetricItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ColorList extends StatelessWidget {
  const _ColorList({
    required this.design,
    required this.selectedIndex,
    required this.onTap,
  });

  final EmbroideryDesign design;
  final int? selectedIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    if (design.colors.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Cores das Linhas',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...design.colors.asMap().entries.map((entry) {
          final i = entry.key;
          final color = entry.value;
          final isSelected = selectedIndex == i;
          final argb = color.argb | 0xFF000000;

          return Card(
            margin: const EdgeInsets.only(bottom: 6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
                width: 2,
              ),
            ),
            child: ListTile(
              dense: true,
              leading: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Color(argb),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black12),
                ),
              ),
              title: Text(color.displayName),
              subtitle: Text(color.displayCode),
              trailing: isSelected
                  ? Text(
                      'Madeira: ${color.madeiraCode ?? "—"}\n'
                      'Isacord: ${color.isacordCode ?? "—"}\n'
                      'Brother: ${color.brotherCode ?? "—"}',
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  : null,
              onTap: () => onTap(i),
            ),
          );
        }),
      ],
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
