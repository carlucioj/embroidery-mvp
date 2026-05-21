import 'dart:async';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../../domain/interfaces/embroidery_converter.dart';
import '../../domain/models/embroidery_design.dart';
import '../../domain/models/embroidery_parameters.dart';
import '../../domain/models/image_data.dart';
import '../python/python_bridge.dart';
import 'color_mapper.dart';

/// Embroidery converter that uses the Python/pyembroidery backend.
///
/// Communicates with Python via MethodChannel on Desktop,
/// or via HTTP API on Mobile (through the bridge abstraction).
class PyEmbroideryConverter implements EmbroideryConverter {
  PyEmbroideryConverter({
    PythonBridge? bridge,
    ColorMapper? colorMapper,
  })  : _bridge = bridge ?? PythonBridge(),
        _colorMapper = colorMapper ?? ColorMapper();

  final PythonBridge _bridge;
  final ColorMapper _colorMapper;
  final _progressController = StreamController<ConversionProgress>.broadcast();
  bool _cancelled = false;
  static const _uuid = Uuid();

  @override
  Stream<ConversionProgress> get progressStream => _progressController.stream;

  @override
  List<String> validateParameters(EmbroideryParameters params) {
    return params.validate();
  }

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

    try {
      _emitProgress(0.1, 'Convertendo para bordado...');

      final result = await _bridge.convertToEmbroidery(
        imageBytes: image.bytes,
        format: parameters.outputFormat.extension,
        widthMm: parameters.designWidthMm,
        heightMm: parameters.designHeightMm,
        fabricId: parameters.fabric.id,
      );

      if (_cancelled) throw const EmbroideryConversionException('Conversão cancelada.');

      _emitProgress(0.7, 'Mapeando cores...');

      // Map colors from the result
      final rawColors = (result['colors'] as List? ?? [])
          .map((c) => c as int)
          .toList();

      final mappedColors = await _colorMapper.mapColors(rawColors);

      _emitProgress(0.85, 'Gerando pré-visualização...');

      final fileBytes = result['fileBytes'] as Uint8List;
      final totalStitches = result['totalStitches'] as int? ?? 0;
      final colorChanges = result['colorChanges'] as int? ?? 0;
      final estimatedMinutes = (result['estimatedMinutes'] as num?)?.toDouble() ?? 0.0;

      // Build stitch paths from result
      final rawPaths = (result['stitchPaths'] as List? ?? []);
      final stitchPaths = rawPaths.map((p) {
        final map = p as Map<dynamic, dynamic>;
        return StitchPath(
          colorIndex: map['colorIndex'] as int,
          stitchCount: map['stitchCount'] as int,
          points: (map['points'] as List).map((v) => (v as num).toDouble()).toList(),
        );
      }).toList();

      // Build color changes from result
      final rawChanges = (result['colorChanges'] as List? ?? []);
      final colorChangeList = rawChanges.map((c) {
        final map = c as Map<dynamic, dynamic>;
        return ColorChange(
          stitchIndex: map['stitchIndex'] as int,
          fromColorIndex: map['fromColorIndex'] as int,
          toColorIndex: map['toColorIndex'] as int,
        );
      }).toList();

      final metrics = DesignMetrics(
        totalStitches: totalStitches,
        colorChangeCount: colorChanges,
        widthMm: parameters.designWidthMm,
        heightMm: parameters.designHeightMm,
        estimatedMinutes: estimatedMinutes,
      );

      _emitProgress(1.0, 'Bordado gerado com sucesso!');

      return EmbroideryDesign(
        id: _uuid.v4(),
        created: DateTime.now(),
        stitchPaths: stitchPaths,
        colorChanges: colorChangeList,
        colors: mappedColors,
        metrics: metrics,
        fileBytes: fileBytes,
      );
    } on PythonBridgeException catch (e) {
      throw EmbroideryConversionException(
        'Falha ao gerar bordado. Verifique os parâmetros e tente novamente.',
        cause: e,
      );
    }
  }

  @override
  Future<PreviewData> generatePreview(EmbroideryDesign design) async {
    // Generate a simple preview from the stitch paths
    // In a real implementation this would render the paths to a canvas
    return PreviewData(
      previewBytes: design.fileBytes ?? Uint8List(0),
      widthPx: 400,
      heightPx: 400,
    );
  }

  @override
  DesignMetrics calculateMetrics(EmbroideryDesign design) {
    return design.metrics;
  }

  @override
  Future<void> cancel() async {
    _cancelled = true;
  }

  void _emitProgress(double percentage, String stage) {
    if (!_progressController.isClosed) {
      _progressController.add(ConversionProgress(
        percentage: percentage,
        stage: stage,
      ));
    }
  }

  void dispose() {
    _progressController.close();
  }
}
