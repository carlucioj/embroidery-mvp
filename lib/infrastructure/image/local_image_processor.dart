import 'dart:async';

import '../../core/constants.dart';
import '../../domain/interfaces/image_processor.dart';
import '../../domain/models/image_data.dart';
import '../python/python_bridge.dart';

/// Image processor that uses the local Python backend via MethodChannel.
///
/// Used on Desktop (Windows) where Python runs as a local subprocess.
class LocalImageProcessor implements ImageProcessor {
  LocalImageProcessor({PythonBridge? bridge})
      : _bridge = bridge ?? PythonBridge();

  final PythonBridge _bridge;
  final _progressController = StreamController<ProcessingProgress>.broadcast();
  bool _cancelled = false;

  @override
  Stream<ProcessingProgress> get progressStream => _progressController.stream;

  @override
  ValidationResult validateImage(ImageData input) {
    // Validate file extension
    if (!SupportedFormats.imageExtensions.contains(input.extension.toLowerCase())) {
      return ValidationResult.invalid(
        'Formato não suportado: .${input.extension}. '
        'Use ${SupportedFormats.imageExtensionsDisplay.join(", ")}.',
      );
    }

    // Validate file size
    if (input.sizeBytes > SupportedFormats.maxImageSizeBytes) {
      return ValidationResult.invalid(
        'Arquivo muito grande: ${input.sizeMB.toStringAsFixed(1)} MB. '
        'O limite é ${SupportedFormats.maxImageSizeMB} MB.',
      );
    }

    return const ValidationResult.valid();
  }

  @override
  Future<ProcessingCapabilities> getCapabilities() async {
    final isAvailable = await _bridge.validateCapabilities();
    return ProcessingCapabilities(
      canProcessLocally: isAvailable,
      availableRamBytes: ProcessingConfig.minRamForLocalProcessing * 2,
      isDesktop: true,
    );
  }

  @override
  Future<ProcessingResult> processImage(
    ImageData input,
    ProcessingOptions options,
  ) async {
    _cancelled = false;

    // Validate input first
    final validation = validateImage(input);
    if (!validation.isValid) {
      throw ImageProcessingException(validation.errorMessage!);
    }

    _emitProgress(0.05, 'Preparando imagem...');

    if (_cancelled) throw const ImageProcessingException('Processamento cancelado.');

    try {
      _emitProgress(0.1, 'Removendo fundo...');

      final processedBytes = await _bridge.processImage(
        imageBytes: input.bytes,
        maxColors: options.maxColors,
      );

      if (_cancelled) throw const ImageProcessingException('Processamento cancelado.');

      _emitProgress(0.9, 'Finalizando...');

      final processedImage = ProcessedImage(
        bytes: processedBytes,
        colorCount: options.maxColors,
        processingDurationMs: 0, // actual duration tracked by caller
        dominantColors: const [],
      );

      _emitProgress(1.0, 'Concluído!');

      return ProcessingResult(
        processedImage: processedImage,
        wasRemote: false,
      );
    } on PythonBridgeException catch (e) {
      throw ImageProcessingException(
        'Falha ao processar imagem. Tente novamente.',
        cause: e,
      );
    }
  }

  @override
  Future<void> cancel() async {
    _cancelled = true;
  }

  void _emitProgress(double percentage, String stage) {
    if (!_progressController.isClosed) {
      _progressController.add(ProcessingProgress(
        percentage: percentage,
        stage: stage,
      ));
    }
  }

  void dispose() {
    _progressController.close();
  }
}
