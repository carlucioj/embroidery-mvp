import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/workflow/workflow_bloc.dart';
import '../../core/constants.dart';
import '../../domain/interfaces/export_manager.dart';
import '../../domain/models/workflow_state.dart';
import '../../infrastructure/export/desktop_export_manager.dart';
import '../../infrastructure/export/mobile_export_manager.dart';
import '../widgets/contextual_help_button.dart';

/// Step 5: Export screen.
///
/// Lets the user save the generated embroidery file to a destination.
/// Desktop: opens a file picker (including USB drives).
/// Mobile: saves to the Downloads folder.
/// After export, shows a confirmation with the full file path
/// and offers a "Novo Design" button to restart.
class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  bool _isExporting = false;
  String? _exportedPath;
  String? _errorMessage;

  bool get _isDesktop =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS;

  ExportManager get _exportManager =>
      _isDesktop ? DesktopExportManager() : MobileExportManager();

  Future<void> _export(WorkflowBlocState state) async {
    final design = state.generatedDesign;
    final params = state.parameters;

    if (design == null || params == null) return;

    setState(() {
      _isExporting = true;
      _errorMessage = null;
      _exportedPath = null;
    });

    try {
      final format = params.outputFormat.extension;
      final filename = ExportConfig.defaultFilename(format);

      // Select destination
      final destination = await _exportManager.selectDestination(filename);
      if (destination == null) {
        // User cancelled
        setState(() => _isExporting = false);
        return;
      }

      // Validate destination
      final validationError = await _exportManager.validateDestination(
        destination,
        design.fileBytes?.length ?? 0,
      );
      if (validationError != null) {
        setState(() {
          _isExporting = false;
          _errorMessage = validationError;
        });
        return;
      }

      // Export
      final result = await _exportManager.exportDesign(
        design,
        ExportOptions(
          format: format,
          filename: filename,
          destination: destination,
        ),
      );

      if (result.success) {
        setState(() {
          _isExporting = false;
          _exportedPath = result.filePath;
        });
        if (mounted) {
          context
              .read<WorkflowBloc>()
              .add(WorkflowExportCompleted(result.filePath));
        }
      } else {
        setState(() {
          _isExporting = false;
          _errorMessage = result.errorMessage ??
              'Erro ao exportar. Tente novamente.';
        });
      }
    } catch (e) {
      setState(() {
        _isExporting = false;
        _errorMessage = 'Erro inesperado ao exportar. Tente novamente.';
      });
    }
  }

  void _newDesign() {
    context.read<WorkflowBloc>().add(const WorkflowReset());
  }

  void _goBack() {
    context.read<WorkflowBloc>().add(const WorkflowGoBackRequested());
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WorkflowBloc, WorkflowBlocState>(
      builder: (context, state) {
        final design = state.generatedDesign;
        final params = state.parameters;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Exportar'),
            actions: const [
              ContextualHelpButton(step: WorkflowStep.export),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StepHeader(
                  stepNumber: 5,
                  title: 'Exportar Arquivo',
                  subtitle: _isDesktop
                      ? 'Salve o arquivo no seu pendrive ou computador.'
                      : 'Salve o arquivo no seu dispositivo.',
                ),

                const SizedBox(height: 24),

                // Design summary card
                if (design != null && params != null)
                  _DesignSummaryCard(
                    stitchCount: design.metrics.totalStitches,
                    colorCount: design.colors.length,
                    widthMm: design.metrics.widthMm,
                    heightMm: design.metrics.heightMm,
                    format: params.outputFormat.extension,
                    manufacturer: params.outputFormat.manufacturer,
                  ),

                const SizedBox(height: 24),

                // Success state
                if (_exportedPath != null) ...[
                  _SuccessBanner(filePath: _exportedPath!),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _newDesign,
                    icon: const Icon(Icons.add_photo_alternate),
                    label: const Text('Novo Design'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _export(state),
                    icon: const Icon(Icons.save_alt),
                    label: const Text('Exportar Novamente'),
                  ),
                ] else ...[
                  // Error
                  if (_errorMessage != null) ...[
                    _ErrorBanner(message: _errorMessage!),
                    const SizedBox(height: 16),
                  ],

                  // Export button
                  FilledButton.icon(
                    onPressed:
                        _isExporting || design == null ? null : () => _export(state),
                    icon: _isExporting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_alt),
                    label: Text(_isExporting ? 'Exportando...' : 'Exportar'),
                  ),
                ],
              ],
            ),
          ),
          bottomNavigationBar: _exportedPath == null
              ? StepNavigationButtons(
                  onBack: _goBack,
                  onNext: null,
                  nextLabel: 'Exportar',
                  nextEnabled: false,
                )
              : null,
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

class _DesignSummaryCard extends StatelessWidget {
  const _DesignSummaryCard({
    required this.stitchCount,
    required this.colorCount,
    required this.widthMm,
    required this.heightMm,
    required this.format,
    required this.manufacturer,
  });

  final int stitchCount;
  final int colorCount;
  final double widthMm;
  final double heightMm;
  final String format;
  final String manufacturer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Resumo do Design',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _Row(label: 'Pontos', value: stitchCount.toString()),
            _Row(label: 'Cores', value: colorCount.toString()),
            _Row(
              label: 'Tamanho',
              value:
                  '${widthMm.toStringAsFixed(0)} × ${heightMm.toStringAsFixed(0)} mm',
            ),
            _Row(
              label: 'Formato',
              value: '.$format — $manufacturer',
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              )),
          Text(value,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _SuccessBanner extends StatelessWidget {
  const _SuccessBanner({required this.filePath});

  final String filePath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Arquivo exportado com sucesso!',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            filePath,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              fontFamily: 'monospace',
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
