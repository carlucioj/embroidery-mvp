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
import '../widgets/hoop_canvas.dart';

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

                // Hoop canvas — shows the bastidor ghost and stitch preview
                if (state.parameters != null)
                  SizedBox(
                    height: 300,
                    child: Stack(
                      children: [
                        HoopCanvas(
                          parameters: state.parameters!,
                          design: _design,
                          selectedColorIndex: _selectedColorIndex,
                          onSizeChanged: (w, h) {
                            // Update parameters in BLoC when user resizes design
                            final updated = state.parameters!.copyWith(
                              designWidthMm: w,
                              designHeightMm: h,
                            );
                            context
                                .read<WorkflowBloc>()
                                .add(WorkflowParametersSet(updated));
                          },
                        ),
                        if (_isGenerating)
                          const Positioned.fill(
                            child: ColoredBox(
                              color: Color(0x66000000),
                              child: Center(child: CircularProgressIndicator()),
                            ),
                          ),
                      ],
                    ),
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
