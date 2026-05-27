import 'package:flutter/services.dart';

import '../../core/constants.dart';

/// Bridge for communicating with the Python backend via MethodChannel.
///
/// Used on Desktop (Windows) where Python runs as a local subprocess.
/// All heavy processing (image cleaning, embroidery conversion) is
/// delegated to Python via this channel.
class PythonBridge {
  PythonBridge()
      : _channel = const MethodChannel(ProcessingConfig.methodChannelName);

  final MethodChannel _channel;

  /// Process an image: remove background and reduce colors.
  ///
  /// [imageBytes] - Raw image bytes (JPG, PNG, BMP, or WEBP)
  /// [maxColors] - Maximum number of colors after reduction (default: 8)
  ///
  /// Returns processed image bytes as PNG with transparency.
  /// Throws [PythonBridgeException] on failure.
  Future<Uint8List> processImage({
    required Uint8List imageBytes,
    int maxColors = ProcessingConfig.maxColors,
  }) async {
    try {
      final result = await _channel.invokeMethod<Uint8List>(
        'processImage',
        {
          'imageBytes': imageBytes,
          'maxColors': maxColors,
        },
      );

      if (result == null) {
        throw const PythonBridgeException('processImage returned null');
      }

      return result;
    } on PlatformException catch (e) {
      throw PythonBridgeException(
        'Falha ao processar imagem: ${e.message}',
        cause: e,
      );
    }
  }

  /// Convert a processed image to an embroidery file.
  ///
  /// [imageBytes] - Processed image bytes (PNG with transparency)
  /// [format] - Output format extension (e.g., 'DST', 'PES')
  /// [widthMm] - Design width in millimeters
  /// [heightMm] - Design height in millimeters
  /// [fabricId] - Fabric type ID ('knit', 'cotton', or 'towel')
  /// [stitchType] - Stitch algorithm: 'fill', 'outline', or 'satin'
  ///
  /// Returns a map with:
  /// - 'fileBytes': Uint8List — the embroidery file bytes
  /// - 'totalStitches': int
  /// - 'colorChanges': int
  /// - 'estimatedMinutes': double
  Future<Map<String, dynamic>> convertToEmbroidery({
    required Uint8List imageBytes,
    required String format,
    required double widthMm,
    required double heightMm,
    required String fabricId,
    String stitchType = 'fill',
  }) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'convertToEmbroidery',
        {
          'imageBytes': imageBytes,
          'format': format,
          'widthMm': widthMm,
          'heightMm': heightMm,
          'fabricId': fabricId,
          'stitchType': stitchType,
        },
      );

      if (result == null) {
        throw const PythonBridgeException('convertToEmbroidery returned null');
      }

      return Map<String, dynamic>.from(result);
    } on PlatformException catch (e) {
      throw PythonBridgeException(
        'Falha ao converter para bordado: ${e.message}',
        cause: e,
      );
    }
  }

  /// Check if the Python backend is available and responsive.
  Future<bool> validateCapabilities() async {
    try {
      final result = await _channel.invokeMethod<bool>('validateCapabilities');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }
}

/// Exception thrown when Python bridge communication fails.
class PythonBridgeException implements Exception {
  const PythonBridgeException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'PythonBridgeException: $message';
}
