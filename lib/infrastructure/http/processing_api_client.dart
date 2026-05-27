import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

import '../../core/constants.dart';
import '../../domain/models/image_data.dart';

/// HTTP client for the remote processing API.
///
/// Used on Mobile when local processing is not available.
/// Handles image upload, processing, and embroidery conversion
/// via REST endpoints.
class ProcessingApiClient {
  ProcessingApiClient({
    http.Client? httpClient,
    String? baseUrl,
  })  : _client = httpClient ?? http.Client(),
        _baseUrl = baseUrl ?? ProcessingConfig.apiBaseUrl;

  final http.Client _client;
  final String _baseUrl;

  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 2);

  /// Upload and process an image remotely.
  ///
  /// Returns [ProcessingApiResult] with image bytes, dominant colors, and complexity.
  Future<ProcessingApiResult> processImage({
    required Uint8List imageBytes,
    required String filename,
    int maxColors = ProcessingConfig.maxColors,
    bool removeBackground = true,
    String mode = 'basic',
    void Function(double progress)? onProgress,
  }) async {
    return _withRetry(() async {
      final uri = Uri.parse('$_baseUrl/process-image');
      final request = http.MultipartRequest('POST', uri)
        ..fields['maxColors'] = maxColors.toString()
        ..fields['removeBackground'] = removeBackground.toString()
        ..fields['mode'] = mode
        ..files.add(
          http.MultipartFile.fromBytes('image', imageBytes, filename: filename),
        );

      onProgress?.call(0.1);

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: ProcessingConfig.httpTimeoutSeconds),
      );

      onProgress?.call(0.9);

      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode != 200) {
        throw ApiException(
          'Falha no processamento remoto: ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }

      onProgress?.call(1.0);

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final imageBase64 = json['imageBase64'] as String;
      final rawColors = (json['dominantColors'] as List? ?? [])
          .map((c) => (c as num).toInt())
          .toList();
      final complexityJson = json['complexity'] as Map<String, dynamic>?;

      return ProcessingApiResult(
        imageBytes: base64Decode(imageBase64),
        dominantColors: rawColors,
        complexity: complexityJson != null
            ? ImageComplexity.fromJson(complexityJson)
            : null,
      );
    });
  }

  /// Convert a processed image to an embroidery file remotely.
  ///
  /// Returns a map with 'fileBytes', 'totalStitches', 'colorChanges',
  /// 'estimatedMinutes'.
  Future<Map<String, dynamic>> convertToEmbroidery({
    required Uint8List imageBytes,
    required String format,
    required double widthMm,
    required double heightMm,
    required String fabricId,
    String stitchType = 'fill',
    void Function(double progress)? onProgress,
  }) async {
    return _withRetry(() async {
      final uri = Uri.parse('$_baseUrl/convert-embroidery');
      final request = http.MultipartRequest('POST', uri)
        ..fields['format'] = format
        ..fields['widthMm'] = widthMm.toString()
        ..fields['heightMm'] = heightMm.toString()
        ..fields['fabricId'] = fabricId
        ..fields['stitchType'] = stitchType
        ..files.add(
          http.MultipartFile.fromBytes(
            'image',
            imageBytes,
            filename: 'processed.png',
          ),
        );

      onProgress?.call(0.1);

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: ProcessingConfig.httpTimeoutSeconds),
      );

      onProgress?.call(0.8);

      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode != 200) {
        throw ApiException(
          'Falha na conversão remota: ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }

      onProgress?.call(1.0);

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      // fileBytes comes as base64 in JSON response
      final fileBase64 = json['fileBytes'] as String;
      return {
        ...json,
        'fileBytes': base64Decode(fileBase64),
      };
    });
  }

  /// Execute [operation] with automatic retry on network failures.
  Future<T> _withRetry<T>(Future<T> Function() operation) async {
    var attempts = 0;
    while (true) {
      try {
        attempts++;
        return await operation();
      } on ApiException {
        rethrow; // Don't retry API errors (4xx, 5xx)
      } catch (e) {
        if (attempts >= _maxRetries) {
          throw ApiException(
            'Falha na conexão após $attempts tentativas. '
            'Verifique sua conexão com a internet.',
            cause: e,
          );
        }
        await Future<void>.delayed(_retryDelay * attempts);
      }
    }
  }

  /// Close the HTTP client and release resources.
  void dispose() => _client.close();
}

/// Result of a remote processImage call.
class ProcessingApiResult {
  const ProcessingApiResult({
    required this.imageBytes,
    required this.dominantColors,
    this.complexity,
  });

  final Uint8List imageBytes;
  final List<int> dominantColors;
  final ImageComplexity? complexity;
}

/// Exception thrown when the API returns an error response.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.cause});

  final String message;
  final int? statusCode;
  final Object? cause;

  @override
  String toString() => 'ApiException($statusCode): $message';
}
