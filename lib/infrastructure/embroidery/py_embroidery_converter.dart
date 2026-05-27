import 'dart:async';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../../core/server_config.dart';
import '../../domain/interfaces/embroidery_converter.dart';
import '../../domain/models/embroidery_design.dart';
import '../../domain/models/embroidery_parameters.dart';
import '../../domain/models/image_data.dart';
import '../http/processing_api_client.dart';
import '../python/python_bridge.dart';
import 'color_mapper.dart';

/// Embroidery converter that uses the Python/pyembroidery backend.
///
/// Tries the HTTP API server first (api_server.py), then falls back to the
/// MethodChannel bridge (requires a native Windows plugin).
class PyEmbroideryConverter implements EmbroideryConverter {
  PyEmbroideryConverter({
    PythonBridge? bridge,
    ColorMapper? colorMapper,
    ProcessingApiClient? apiClient,
  })  : _bridge = bridge ?? PythonBridge(),
        _colorMapper = colorMapper ?? ColorMapper(),
        _apiClient = apiClient ?? ProcessingApiClient();

  final PythonBridge _bridge;
  final ColorMapper _colorMapper;
  final ProcessingApiClient _apiClient;
  final _progressController = StreamController<ConversionProgress>.broadcast();
  bool _cancelled = false;
  static const _uuid = Uuid();

  @override
  Stream<ConversionProgress> get progressStream => _progressController.stream;

  @override
  List<String> validateParameters(EmbroideryParameters params) =>
      params.validate();

  @override
  Future<EmbroideryDesign> convertToEmbroidery(
    ProcessedImage image,
    EmbroideryParameters parameters,
  ) async {
    _cancelled = false;

    final errors = validateParameters(parameters);
    if (errors.isNotEmpty) {
      throw EmbroideryConversionException(errors.first);
    }

    _emitProgress(0.05, 'Preparando conversão...');
    if (_cancelled) throw const EmbroideryConversionException('Conversão cancelada.');

    // Attempt 1: HTTP server (api_server.py running locally)
    final serverOk = await ServerConfig.checkHealth();
    if (serverOk) {
      try {
        return await _convertViaHttpApi(image, parameters);
      } catch (e) {
        if (e is EmbroideryConversionException) rethrow;
        // If HTTP failed for non-auth/validation reason, try bridge next
      }
    }

    // Attempt 2: MethodChannel bridge (native Windows plugin)
    try {
      return await _convertViaBridge(image, parameters);
    } on PythonBridgeException {
      throw const EmbroideryConversionException(
        'O servidor Python não está disponível.\n'
        'Inicie o servidor com INICIAR_SERVIDOR.bat e tente novamente.',
      );
    }
  }

  Future<EmbroideryDesign> _convertViaHttpApi(
    ProcessedImage image,
    EmbroideryParameters parameters,
  ) async {
    _emitProgress(0.1, 'Convertendo via servidor...');

    final result = await _apiClient.convertToEmbroidery(
      imageBytes: image.bytes,
      format: parameters.outputFormat.extension,
      widthMm: parameters.designWidthMm,
      heightMm: parameters.designHeightMm,
      fabricId: parameters.fabric.id,
      stitchType: parameters.stitchType.id,
      onProgress: (p) => _emitProgress(0.1 + p * 0.6, 'Gerando pontos...'),
    );

    if (_cancelled) throw const EmbroideryConversionException('Conversão cancelada.');
    return _buildDesign(result, parameters);
  }

  Future<EmbroideryDesign> _convertViaBridge(
    ProcessedImage image,
    EmbroideryParameters parameters,
  ) async {
    _emitProgress(0.1, 'Convertendo via Python local...');

    final result = await _bridge.convertToEmbroidery(
      imageBytes: image.bytes,
      format: parameters.outputFormat.extension,
      widthMm: parameters.designWidthMm,
      heightMm: parameters.designHeightMm,
      fabricId: parameters.fabric.id,
      stitchType: parameters.stitchType.id,
    );

    if (_cancelled) throw const EmbroideryConversionException('Conversão cancelada.');
    return _buildDesign(result, parameters);
  }

  Future<EmbroideryDesign> _buildDesign(
    Map<String, dynamic> result,
    EmbroideryParameters parameters,
  ) async {
    _emitProgress(0.7, 'Mapeando cores das linhas...');

    final rawColors =
        (result['colors'] as List? ?? []).map((c) => c as int).toList();
    final mappedColors = await _colorMapper.mapColors(rawColors);

    _emitProgress(0.85, 'Finalizando design...');

    final fileBytes = result['fileBytes'] as Uint8List;
    final totalStitches = result['totalStitches'] as int? ?? 0;
    final colorChangeCount = result['colorChanges'] as int? ?? 0;
    final estimatedMinutes =
        (result['estimatedMinutes'] as num?)?.toDouble() ?? 0.0;

    final rawPaths = result['stitchPaths'] as List? ?? [];
    final stitchPaths = rawPaths.map((p) {
      final map = p as Map<dynamic, dynamic>;
      return StitchPath(
        colorIndex: map['colorIndex'] as int,
        stitchCount: map['stitchCount'] as int,
        points: (map['points'] as List)
            .map((v) => (v as num).toDouble())
            .toList(),
      );
    }).toList();

    // colorChangesList (list of events) vs colorChanges (int count)
    final rawChanges = result['colorChangesList'] as List? ?? [];
    final colorChanges = rawChanges.map((c) {
      final map = c as Map<dynamic, dynamic>;
      return ColorChange(
        stitchIndex: map['stitchIndex'] as int,
        fromColorIndex: map['fromColorIndex'] as int,
        toColorIndex: map['toColorIndex'] as int,
      );
    }).toList();

    final metrics = DesignMetrics(
      totalStitches: totalStitches,
      colorChangeCount: colorChangeCount,
      widthMm: parameters.designWidthMm,
      heightMm: parameters.designHeightMm,
      estimatedMinutes: estimatedMinutes,
    );

    // Parse validation (handles both Map<String, dynamic> from HTTP and
    // Map<dynamic, dynamic> from MethodChannel bridge)
    final rawValidation = result['validation'];
    DesignValidation? validation;
    if (rawValidation is Map) {
      final issues = (rawValidation['issues'] as List? ?? []).map((e) {
        final im = e as Map;
        return ValidationIssue(
          code: im['code'] as String,
          message: im['message'] as String,
          severity: switch (im['severity'] as String) {
            'error' => ValidationSeverity.error,
            'warning' => ValidationSeverity.warning,
            _ => ValidationSeverity.ok,
          },
        );
      }).toList();
      validation = DesignValidation(
        severity: switch (rawValidation['severity'] as String) {
          'error' => ValidationSeverity.error,
          'warning' => ValidationSeverity.warning,
          _ => ValidationSeverity.ok,
        },
        issues: issues,
      );
    }

    _emitProgress(1.0, 'Bordado gerado com sucesso!');

    return EmbroideryDesign(
      id: _uuid.v4(),
      created: DateTime.now(),
      stitchPaths: stitchPaths,
      colorChanges: colorChanges,
      colors: mappedColors,
      metrics: metrics,
      fileBytes: fileBytes,
      validation: validation,
    );
  }

  @override
  Future<PreviewData> generatePreview(EmbroideryDesign design) async {
    return PreviewData(
      previewBytes: design.fileBytes ?? Uint8List(0),
      widthPx: 400,
      heightPx: 400,
    );
  }

  @override
  DesignMetrics calculateMetrics(EmbroideryDesign design) => design.metrics;

  @override
  Future<void> cancel() async => _cancelled = true;

  void _emitProgress(double percentage, String stage) {
    if (!_progressController.isClosed) {
      _progressController.add(
          ConversionProgress(percentage: percentage, stage: stage));
    }
  }

  void dispose() => _progressController.close();
}
