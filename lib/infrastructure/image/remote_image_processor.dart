import 'dart:async';
import 'dart:io';

import '../../core/constants.dart';
import '../../domain/interfaces/image_processor.dart';
import '../../domain/models/image_data.dart';
import '../http/processing_api_client.dart';

/// Image processor that delegates to the remote HTTP API.
///
/// Used on Mobile when local processing is not available
/// (device RAM < 2 GB or Python not available).
class RemoteImageProcessor implements ImageProcessor {
  RemoteImageProcessor({ProcessingApiClient? apiClient})
      : _apiClient = apiClient ?? ProcessingApiClient();

  final ProcessingApiClient _apiClient;
  final _progressController = StreamController<ProcessingProgress>.broadcast();
  bool _cancelled = false;

  @override
  Stream<ProcessingProgress> get progressStream => _progressController.stream;

  @override
  ValidationResult validateImage(ImageData input) {
    if (!SupportedFormats.imageExtensions.contains(input.extension.toLowerCase())) {
      return ValidationResult.invalid(
        'Formato não suportado: .${input.extension}. '
        'Use ${SupportedFormats.imageExtensionsDisplay.join(", ")}.',
      );
    }

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
    // On mobile, check available RAM
    // This is a simplified check; real implementation would use
    // platform channels to query actual available RAM
    return const ProcessingCapabilities(
      canProcessLocally: false,
      availableRamBytes: 0,
      isDesktop: false,
    );
  }

  @override
  Future<ProcessingResult> processImage(
    ImageData input,
    ProcessingOptions options,
  ) async {
    _cancelled = false;

    final validation = validateImage(input);
    if (!validation.isValid) {
      throw ImageProcessingException(validation.errorMessage!);
    }

    _emitProgress(0.05, 'Conectando ao servidor...');

    if (_cancelled) throw const ImageProcessingException('Processamento cancelado.');

    try {
      _emitProgress(0.1, 'Enviando imagem para processamento na nuvem...');

      final processedBytes = await _apiClient.processImage(
        imageBytes: input.bytes,
        filename: input.filename,
        maxColors: options.maxColors,
        onProgress: (p) => _emitProgress(0.1 + p * 0.8, 'Processando na nuvem...'),
      );

      if (_cancelled) throw const ImageProcessingException('Processamento cancelado.');

      _emitProgress(0.95, 'Finalizando...');

      final processedImage = ProcessedImage(
        bytes: processedBytes,
        colorCount: options.maxColors,
        processingDurationMs: 0,
        dominantColors: const [],
      );

      _emitProgress(1.0, 'Concluído!');

      return ProcessingResult(
        processedImage: processedImage,
        wasRemote: true,
      );
    } on ApiException catch (e) {
      throw ImageProcessingException(
        'Falha na conexão com o servidor. Verifique sua internet e tente novamente.',
        cause: e,
      );
    } on SocketException catch (e) {
      throw ImageProcessingException(
        'Sem conexão com a internet. Verifique sua rede e tente novamente.',
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
    _apiClient.dispose();
  }
}
