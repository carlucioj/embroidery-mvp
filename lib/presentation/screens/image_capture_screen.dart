import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../application/workflow/workflow_bloc.dart';
import '../../core/app_router.dart';
import '../../core/constants.dart';
import '../../domain/models/image_data.dart';
import '../../domain/models/workflow_state.dart';
import '../widgets/contextual_help_button.dart';

/// Step 1: Image capture or import screen.
///
/// On Mobile: shows a "Tirar Foto" button using the device camera.
/// On Desktop: shows an "Importar Imagem" button using the file picker.
/// Both paths validate format and file size before loading.
class ImageCaptureScreen extends StatefulWidget {
  const ImageCaptureScreen({super.key});

  @override
  State<ImageCaptureScreen> createState() => _ImageCaptureScreenState();
}

class _ImageCaptureScreenState extends State<ImageCaptureScreen> {
  bool _isLoading = false;
  String? _errorMessage;
  ImageData? _loadedImage;

  bool get _isMobile =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _pickFromCamera() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.camera);
      if (picked == null) {
        setState(() => _isLoading = false);
        return;
      }

      final bytes = await picked.readAsBytes();
      final ext = picked.name.split('.').last.toLowerCase();
      await _loadImage(bytes, picked.name, ext);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Não foi possível acessar a câmera. Tente novamente.';
      });
    }
  }

  Future<void> _pickFromFile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: SupportedFormats.imageExtensions,
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }

      final file = result.files.first;
      if (file.bytes == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Não foi possível ler o arquivo. Tente novamente.';
        });
        return;
      }

      final ext = (file.extension ?? '').toLowerCase();
      await _loadImage(file.bytes!, file.name, ext);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Erro ao abrir arquivo. Tente novamente.';
      });
    }
  }

  Future<void> _loadImage(Uint8List bytes, String filename, String ext) async {
    // Validate extension
    if (!SupportedFormats.imageExtensions.contains(ext)) {
      setState(() {
        _isLoading = false;
        _errorMessage =
            'Formato não suportado: .$ext\n'
            'Use: ${SupportedFormats.imageExtensionsDisplay.join(", ")}';
      });
      return;
    }

    // Validate size
    if (bytes.length > SupportedFormats.maxImageSizeBytes) {
      final sizeMB = (bytes.length / (1024 * 1024)).toStringAsFixed(1);
      setState(() {
        _isLoading = false;
        _errorMessage =
            'Arquivo muito grande: $sizeMB MB.\n'
            'O limite é ${SupportedFormats.maxImageSizeMB} MB.';
      });
      return;
    }

    final image = ImageData(
      bytes: bytes,
      filename: filename,
      extension: ext,
      sizeBytes: bytes.length,
    );

    setState(() {
      _isLoading = false;
      _loadedImage = image;
      _errorMessage = null;
    });

    // Notify the BLoC
    if (mounted) {
      context.read<WorkflowBloc>().add(WorkflowImageCaptured(image));
    }
  }

  void _advance() {
    context.read<WorkflowBloc>().add(const WorkflowAdvanceRequested());
    context.go(AppRoutes.imageCleaning);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocListener<WorkflowBloc, WorkflowBlocState>(
      listener: (context, state) {
        if (state.hasErrors) {
          setState(() => _errorMessage = state.validationErrors.first);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Importar Imagem'),
          actions: const [
            ContextualHelpButton(step: WorkflowStep.imageCapture),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Step indicator
              _StepHeader(
                stepNumber: 1,
                title: 'Selecione sua arte',
                subtitle: _isMobile
                    ? 'Tire uma foto ou importe uma imagem'
                    : 'Importe uma imagem do seu computador',
              ),

              const SizedBox(height: 32),

              // Image preview or placeholder
              _ImagePreview(
                image: _loadedImage,
                isLoading: _isLoading,
              ),

              const SizedBox(height: 24),

              // Error message
              if (_errorMessage != null)
                Container(
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
                          _errorMessage!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              if (_errorMessage != null) const SizedBox(height: 16),

              // Action buttons
              if (_isMobile) ...[
                FilledButton.icon(
                  onPressed: _isLoading ? null : _pickFromCamera,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Tirar Foto'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _pickFromFile,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Escolher da Galeria'),
                ),
              ] else ...[
                FilledButton.icon(
                  onPressed: _isLoading ? null : _pickFromFile,
                  icon: const Icon(Icons.add_photo_alternate),
                  label: const Text('Importar Imagem'),
                ),
              ],

              const SizedBox(height: 8),
              Text(
                'Formatos aceitos: ${SupportedFormats.imageExtensionsDisplay.join(", ")} '
                '(máx. ${SupportedFormats.maxImageSizeMB} MB)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        bottomNavigationBar: StepNavigationButtons(
          onNext: _loadedImage != null ? _advance : null,
          nextLabel: 'Limpar Arte',
          nextEnabled: _loadedImage != null,
        ),
      ),
    );
  }
}

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

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({
    required this.image,
    required this.isLoading,
  });

  final ImageData? image;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 240,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : image != null
                ? Image.memory(
                    image!.bytes,
                    fit: BoxFit.contain,
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.image_outlined,
                        size: 64,
                        color: theme.colorScheme.outlineVariant,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Nenhuma imagem selecionada',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
