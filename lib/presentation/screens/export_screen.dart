import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/workflow/workflow_bloc.dart';
import '../../core/constants.dart';
import '../../domain/interfaces/export_manager.dart';
import '../../domain/models/embroidery_design.dart';
import '../../domain/models/workflow_state.dart';
import '../../infrastructure/export/desktop_export_manager.dart';
import '../../infrastructure/export/mobile_export_manager.dart';
import '../../infrastructure/export/usb_drive_detector.dart';
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

  // USB detection — Windows only
  final _usbDetector = UsbDriveDetector();
  List<UsbDrive> _usbDrives = [];
  Timer? _usbPollTimer;
  String? _usbCopyStatus; // drive letter of the last successful USB copy

  bool get _isDesktop =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS;

  ExportManager get _exportManager =>
      _isDesktop ? DesktopExportManager() : MobileExportManager();

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) {
      // Poll immediately, then every 3 seconds
      _pollUsb();
      _usbPollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _pollUsb());
    }
  }

  @override
  void dispose() {
    _usbPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _pollUsb() async {
    final drives = await _usbDetector.detectRemovableDrives();
    if (mounted) setState(() => _usbDrives = drives);
  }

  Future<void> _copyToUsb(UsbDrive drive, EmbroideryDesign design, String format) async {
    final bytes = design.fileBytes;
    if (bytes == null) return;

    setState(() => _errorMessage = null);

    try {
      final filename = ExportConfig.defaultFilename(format);
      final dest = '${drive.letter}\\$filename';
      await File(dest).writeAsBytes(bytes, flush: true);

      if (mounted) {
        setState(() => _usbCopyStatus = drive.letter);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Copiado para ${drive.displayName} → $filename'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Erro ao copiar para USB: $e');
      }
    }
  }

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
                if (design != null && params != null) ...[
                  _DesignSummaryCard(
                    stitchCount: design.metrics.totalStitches,
                    colorCount: design.colors.length,
                    widthMm: design.metrics.widthMm,
                    heightMm: design.metrics.heightMm,
                    estimatedMinutes: design.metrics.estimatedMinutes,
                    format: params.outputFormat.extension,
                    manufacturer: params.outputFormat.manufacturer,
                  ),
                  if (design.validation != null) ...[
                    const SizedBox(height: 12),
                    _ValidationCard(validation: design.validation!),
                  ],

                  // USB drives card — shown when removable drives are detected
                  if (_isDesktop && _usbDrives.isNotEmpty && design.fileBytes != null) ...[
                    const SizedBox(height: 12),
                    _UsbDrivesCard(
                      drives: _usbDrives,
                      format: params.outputFormat.extension,
                      lastCopiedLetter: _usbCopyStatus,
                      onCopy: (drive) => _copyToUsb(
                        drive,
                        design,
                        params.outputFormat.extension,
                      ),
                    ),
                  ],
                ],

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

                  // Export button — blocked if validation has errors
                  FilledButton.icon(
                    onPressed: _isExporting ||
                            design == null ||
                            design.validation?.isExportable == false
                        ? null
                        : () => _export(state),
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
    required this.estimatedMinutes,
    required this.format,
    required this.manufacturer,
  });

  final int stitchCount;
  final int colorCount;
  final double widthMm;
  final double heightMm;
  final double estimatedMinutes;
  final String format;
  final String manufacturer;

  String get _estimatedTime {
    if (estimatedMinutes < 1) return 'menos de 1 min';
    final h = estimatedMinutes ~/ 60;
    final m = (estimatedMinutes % 60).round();
    if (h == 0) return '$m min';
    return '${h}h ${m}min';
  }

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
            _Row(label: 'Tempo estimado', value: _estimatedTime),
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

class _ValidationCard extends StatelessWidget {
  const _ValidationCard({required this.validation});

  final DesignValidation validation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!validation.hasIssues) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green.shade300),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline, color: Colors.green.shade700, size: 20),
            const SizedBox(width: 8),
            Text(
              'Design validado — pronto para exportar.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.green.shade800,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    final isError = validation.severity == ValidationSeverity.error;
    final color = isError ? theme.colorScheme.error : Colors.orange.shade700;
    final bgColor = isError
        ? theme.colorScheme.errorContainer
        : Colors.orange.withValues(alpha: 0.1);
    final borderColor = isError ? theme.colorScheme.error : Colors.orange.shade300;
    final icon = isError ? Icons.error_outline : Icons.warning_amber_outlined;
    final title = isError ? 'Problemas bloqueando exportação' : 'Avisos do design';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...validation.issues.map(
            (issue) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    issue.severity == ValidationSeverity.error
                        ? Icons.cancel_outlined
                        : Icons.info_outline,
                    size: 16,
                    color: issue.severity == ValidationSeverity.error
                        ? theme.colorScheme.error
                        : Colors.orange.shade700,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      issue.message,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isError
                            ? theme.colorScheme.onErrorContainer
                            : Colors.orange.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isError)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Corrija os erros acima antes de exportar.',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
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

// ── USB Drives Card ───────────────────────────────────────────────────────────

class _UsbDrivesCard extends StatelessWidget {
  const _UsbDrivesCard({
    required this.drives,
    required this.format,
    required this.onCopy,
    this.lastCopiedLetter,
  });

  final List<UsbDrive> drives;
  final String format;
  final String? lastCopiedLetter;
  final void Function(UsbDrive) onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.usb, color: Colors.blue.shade700, size: 20),
              const SizedBox(width: 8),
              Text(
                'Máquina detectada',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: Colors.blue.shade800,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Copie o arquivo diretamente para o pendrive da máquina.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.blue.shade700,
            ),
          ),
          const SizedBox(height: 12),
          ...drives.map((drive) {
            final copied = drive.letter == lastCopiedLetter;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(
                    copied ? Icons.check_circle : Icons.drive_file_move_outline,
                    size: 18,
                    color: copied ? Colors.green.shade700 : Colors.blue.shade600,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      drive.displayName,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: copied ? null : () => onCopy(drive),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      minimumSize: Size.zero,
                    ),
                    icon: Icon(
                      copied ? Icons.check : Icons.copy,
                      size: 16,
                    ),
                    label: Text(
                      copied ? 'Copiado' : 'Copiar .$format',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ── Error Banner ──────────────────────────────────────────────────────────────

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
