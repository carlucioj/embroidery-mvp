import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/constants.dart';
import '../../domain/interfaces/image_processor.dart';
import '../../domain/models/image_data.dart';
import 'dart_image_processor.dart';
import 'remote_image_processor.dart';

/// Image processor that automatically selects local or remote processing.
///
/// On Desktop: uses pure-Dart processing (no Python required).
/// On Mobile: checks device RAM and falls back to remote if insufficient.
class AdaptiveImageProcessor implements ImageProcessor {
  AdaptiveImageProcessor({
    DartImageProcessor? localProcessor,
    RemoteImageProcessor? remoteProcessor,
  })  : _local = localProcessor ?? DartImageProcessor(),
        _remote = remoteProcessor ?? RemoteImageProcessor();

  final DartImageProcessor _local;
  final RemoteImageProcessor _remote;

  ImageProcessor? _activeProcessor;
  final _progressController = StreamController<ProcessingProgress>.broadcast();

  @override
  Stream<ProcessingProgress> get progressStream => _progressController.stream;

  @override
  ValidationResult validateImage(ImageData input) {
    // Validation is the same regardless of processor
    return _local.validateImage(input);
  }

  @override
  Future<ProcessingCapabilities> getCapabilities() async {
    if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return _local.getCapabilities();
    }
    return _remote.getCapabilities();
  }

  @override
  Future<ProcessingResult> processImage(
    ImageData input,
    ProcessingOptions options,
  ) async {
    final processor = await _selectProcessor(options);
    _activeProcessor = processor;

    // Forward progress events from the selected processor
    final subscription = processor.progressStream.listen(
      (progress) {
        if (!_progressController.isClosed) {
          _progressController.add(progress);
        }
      },
    );

    try {
      return await processor.processImage(input, options);
    } finally {
      await subscription.cancel();
      _activeProcessor = null;
    }
  }

  @override
  Future<void> cancel() async {
    await _activeProcessor?.cancel();
  }

  /// Select the appropriate processor based on platform and capabilities.
  Future<ImageProcessor> _selectProcessor(ProcessingOptions options) async {
    // Explicit mode override
    if (options.mode == ProcessingMode.local) return _local;
    if (options.mode == ProcessingMode.remote) return _remote;

    // Auto mode: use local on Desktop, check capabilities on Mobile
    final isDesktop = defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS;

    if (isDesktop) return _local;

    // On Mobile: check if local processing is feasible
    final capabilities = await _local.getCapabilities();
    if (capabilities.canProcessLocally &&
        capabilities.availableRamBytes >= ProcessingConfig.minRamForLocalProcessing) {
      return _local;
    }

    return _remote;
  }

  void dispose() {
    _progressController.close();
    _local.dispose();
    _remote.dispose();
  }
}
