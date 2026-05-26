import 'dart:convert';
import 'dart:typed_data';

import 'package:embroidery_mvp/core/constants.dart';
import 'package:embroidery_mvp/domain/models/embroidery_design.dart';
import 'package:embroidery_mvp/domain/models/embroidery_parameters.dart';
import 'package:embroidery_mvp/domain/models/image_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ── ImageComplexity ────────────────────────────────────────────────────────

  group('ImageComplexity', () {
    test('round-trips all fields correctly', () {
      const original = ImageComplexity(
        level: ComplexityLevel.medium,
        score: 42,
        uniqueColors: 7,
        edgeDensity: 0.35,
        regionCount: 12,
        avgRegionAreaPx: 320.5,
      );

      final restored = ImageComplexity.fromJson(original.toJson());

      expect(restored.level, original.level);
      expect(restored.score, original.score);
      expect(restored.uniqueColors, original.uniqueColors);
      expect(restored.edgeDensity, closeTo(original.edgeDensity, 0.0001));
      expect(restored.regionCount, original.regionCount);
      expect(restored.avgRegionAreaPx, closeTo(original.avgRegionAreaPx, 0.0001));
    });

    test('round-trips all three complexity levels', () {
      for (final level in ComplexityLevel.values) {
        final c = ImageComplexity(
          level: level,
          score: 0,
          uniqueColors: 1,
          edgeDensity: 0,
          regionCount: 0,
          avgRegionAreaPx: 0,
        );
        expect(ImageComplexity.fromJson(c.toJson()).level, level);
      }
    });

    test('fromJson is tolerant of int values for double fields', () {
      // JSON decode can produce int for fields like 0.0 encoded as 0
      final json = {
        'level': 'simple',
        'score': 10,
        'unique_colors': 3,
        'edge_density': 0,     // int, not double
        'region_count': 5,
        'avg_region_area_px': 100, // int, not double
      };
      final c = ImageComplexity.fromJson(json);
      expect(c.edgeDensity, isA<double>());
      expect(c.avgRegionAreaPx, isA<double>());
    });
  });

  // ── ImageData ──────────────────────────────────────────────────────────────

  group('ImageData.toJson', () {
    test('includes all optional fields when present', () {
      final img = ImageData(
        bytes: Uint8List.fromList([1, 2, 3]),
        filename: 'flor.jpg',
        extension: 'jpg',
        sizeBytes: 1024,
        widthPx: 800,
        heightPx: 600,
      );

      final json = img.toJson();

      expect(json['filename'], 'flor.jpg');
      expect(json['extension'], 'jpg');
      expect(json['sizeBytes'], 1024);
      expect(json['widthPx'], 800);
      expect(json['heightPx'], 600);
    });

    test('omits dimension fields when null', () {
      final img = ImageData(
        bytes: Uint8List.fromList([1]),
        filename: 'test.png',
        extension: 'png',
        sizeBytes: 512,
      );

      final json = img.toJson();

      expect(json.containsKey('widthPx'), isFalse);
      expect(json.containsKey('heightPx'), isFalse);
    });

    test('round-trips through jsonEncode/jsonDecode without loss', () {
      final img = ImageData(
        bytes: Uint8List.fromList([0xFF, 0xD8]),
        filename: 'foto.jpeg',
        extension: 'jpeg',
        sizeBytes: 204800,
        widthPx: 1920,
        heightPx: 1080,
      );

      final decoded = jsonDecode(jsonEncode(img.toJson())) as Map<String, dynamic>;

      expect(decoded['filename'], img.filename);
      expect(decoded['sizeBytes'], img.sizeBytes);
      expect(decoded['widthPx'], img.widthPx);
      expect(decoded['heightPx'], img.heightPx);
    });
  });

  // ── ProcessedImage ─────────────────────────────────────────────────────────

  group('ProcessedImage.toJson', () {
    test('includes complexity when present', () {
      const complexity = ImageComplexity(
        level: ComplexityLevel.complex,
        score: 80,
        uniqueColors: 6,
        edgeDensity: 0.75,
        regionCount: 30,
        avgRegionAreaPx: 90.0,
      );
      final img = ProcessedImage(
        bytes: Uint8List.fromList([0x89, 0x50]),
        colorCount: 6,
        processingDurationMs: 1250,
        dominantColors: [0xFFFF0000, 0xFF00FF00],
        complexity: complexity,
      );

      final json = img.toJson();

      expect(json['colorCount'], 6);
      expect(json['processingDurationMs'], 1250);
      expect(json['dominantColors'], [0xFFFF0000, 0xFF00FF00]);
      expect(json.containsKey('complexity'), isTrue);
      expect(json['complexity']['level'], 'complex');
    });

    test('omits complexity when null', () {
      final img = ProcessedImage(
        bytes: Uint8List.fromList([1]),
        colorCount: 3,
        processingDurationMs: 500,
      );

      expect(img.toJson().containsKey('complexity'), isFalse);
    });
  });

  // ── EmbroideryParameters ───────────────────────────────────────────────────

  group('EmbroideryParameters toJson/fromJson', () {
    EmbroideryParameters makeParams({
      String hoopId = 'rect_200x140',
      String fabricId = 'cotton',
      double width = 100,
      double height = 80,
      String format = 'PES',
      StitchType stitchType = StitchType.fill,
      bool maintainAspect = true,
    }) {
      return EmbroideryParameters(
        hoop: HoopSizes.all.firstWhere((h) => h.id == hoopId),
        fabric: FabricTypes.all.firstWhere((f) => f.id == fabricId),
        designWidthMm: width,
        designHeightMm: height,
        outputFormat: OutputFormats.all.firstWhere((f) => f.extension == format),
        stitchType: stitchType,
        maintainAspectRatio: maintainAspect,
      );
    }

    test('round-trips all fields', () {
      final params = makeParams(
        hoopId: 'rect_200x140',
        fabricId: 'cotton',
        width: 120.5,
        height: 95.0,
        format: 'PES',
        stitchType: StitchType.satin,
        maintainAspect: false,
      );

      final restored = EmbroideryParameters.fromJson(params.toJson());

      expect(restored.hoop.id, params.hoop.id);
      expect(restored.fabric.id, params.fabric.id);
      expect(restored.designWidthMm, closeTo(params.designWidthMm, 0.001));
      expect(restored.designHeightMm, closeTo(params.designHeightMm, 0.001));
      expect(restored.outputFormat.extension, params.outputFormat.extension);
      expect(restored.stitchType, params.stitchType);
      expect(restored.maintainAspectRatio, params.maintainAspectRatio);
    });

    test('round-trips all three stitch types', () {
      for (final type in StitchType.values) {
        final p = makeParams(stitchType: type);
        expect(EmbroideryParameters.fromJson(p.toJson()).stitchType, type);
      }
    });

    test('fromJson falls back gracefully on unknown hoopId', () {
      final json = {
        'hoopId': 'nonexistent_hoop',
        'fabricId': 'cotton',
        'designWidthMm': 50.0,
        'designHeightMm': 50.0,
        'outputFormat': 'PES',
        'stitchType': 'fill',
        'maintainAspectRatio': true,
      };

      // Should not throw — falls back to first available hoop
      expect(() => EmbroideryParameters.fromJson(json), returnsNormally);
    });

    test('survives jsonEncode/jsonDecode cycle (int vs double edge case)', () {
      // After jsonDecode, numeric fields may be int if they have no decimal part
      final params = makeParams(width: 100, height: 80); // whole numbers
      final decoded = jsonDecode(jsonEncode(params.toJson())) as Map<String, dynamic>;
      final restored = EmbroideryParameters.fromJson(decoded);

      expect(restored.designWidthMm, isA<double>());
      expect(restored.designHeightMm, isA<double>());
      expect(restored.designWidthMm, 100.0);
      expect(restored.designHeightMm, 80.0);
    });
  });

  // ── StitchPath ─────────────────────────────────────────────────────────────

  group('StitchPath toJson/fromJson', () {
    test('round-trips correctly', () {
      const path = StitchPath(
        colorIndex: 2,
        stitchCount: 150,
        points: [0.0, 10.0, 5.5, 15.5],
      );

      final restored = StitchPath.fromJson(path.toJson());

      expect(restored.colorIndex, 2);
      expect(restored.stitchCount, 150);
      expect(restored.points, [0.0, 10.0, 5.5, 15.5]);
    });

    test('handles int values in points list after JSON decode', () {
      // JSON round-trip may produce ints for whole-number coordinates
      final json = {
        'colorIndex': 0,
        'stitchCount': 3,
        'points': [0, 10, 20, 30], // ints, not doubles
      };

      final path = StitchPath.fromJson(json);

      expect(path.points.every((v) => v is double), isTrue);
      expect(path.points, [0.0, 10.0, 20.0, 30.0]);
    });
  });

  // ── DesignValidation ───────────────────────────────────────────────────────

  group('DesignValidation toJson/fromJson', () {
    test('round-trips with no issues (ok severity)', () {
      const v = DesignValidation(severity: ValidationSeverity.ok, issues: []);
      final restored = DesignValidation.fromJson(v.toJson());
      expect(restored.severity, ValidationSeverity.ok);
      expect(restored.issues, isEmpty);
    });

    test('round-trips with warning issue', () {
      const v = DesignValidation(
        severity: ValidationSeverity.warning,
        issues: [
          ValidationIssue(
            code: 'COLORS_EXCEED_CONSUMER_LIMIT',
            message: 'Mais de 16 cores detectadas.',
            severity: ValidationSeverity.warning,
          ),
        ],
      );

      final restored = DesignValidation.fromJson(v.toJson());

      expect(restored.severity, ValidationSeverity.warning);
      expect(restored.issues.length, 1);
      expect(restored.issues.first.code, 'COLORS_EXCEED_CONSUMER_LIMIT');
      expect(restored.issues.first.severity, ValidationSeverity.warning);
      expect(restored.isExportable, isTrue);
    });

    test('round-trips with error issue and blocks export', () {
      const v = DesignValidation(
        severity: ValidationSeverity.error,
        issues: [
          ValidationIssue(
            code: 'NO_STITCHES',
            message: 'Nenhum ponto gerado.',
            severity: ValidationSeverity.error,
          ),
        ],
      );

      final restored = DesignValidation.fromJson(v.toJson());

      expect(restored.severity, ValidationSeverity.error);
      expect(restored.isExportable, isFalse);
      expect(restored.hasIssues, isTrue);
    });

    test('round-trips multiple issues of mixed severity', () {
      const v = DesignValidation(
        severity: ValidationSeverity.error,
        issues: [
          ValidationIssue(
            code: 'TOO_MANY_COLORS',
            message: 'Mais de 64 cores.',
            severity: ValidationSeverity.error,
          ),
          ValidationIssue(
            code: 'STITCH_COUNT_HIGH',
            message: 'Mais de 500.000 pontos.',
            severity: ValidationSeverity.warning,
          ),
        ],
      );

      final restored = DesignValidation.fromJson(v.toJson());

      expect(restored.issues.length, 2);
      expect(restored.issues[0].code, 'TOO_MANY_COLORS');
      expect(restored.issues[1].severity, ValidationSeverity.warning);
    });
  });

  // ── EmbroideryDesign full round-trip ───────────────────────────────────────

  group('EmbroideryDesign toJsonString/fromJsonString', () {
    EmbroideryDesign makeDesign({DesignValidation? validation}) {
      return EmbroideryDesign(
        id: 'test-id-001',
        created: DateTime.utc(2025, 5, 20, 10, 30),
        stitchPaths: const [
          StitchPath(colorIndex: 0, stitchCount: 200, points: [0.0, 0.0, 1.5, 2.5]),
          StitchPath(colorIndex: 1, stitchCount: 100, points: [10.0, 10.0]),
        ],
        colorChanges: const [
          ColorChange(stitchIndex: 200, fromColorIndex: 0, toColorIndex: 1),
        ],
        colors: const [
          ThreadColor(argb: 0xFFFF0000, madeiraCode: '0510', madeiraName: 'Rubi'),
          ThreadColor(argb: 0xFF0000FF, brotherCode: '035', brotherName: 'Azul Royal'),
        ],
        metrics: const DesignMetrics(
          totalStitches: 300,
          colorChangeCount: 1,
          widthMm: 80.0,
          heightMm: 60.0,
          estimatedMinutes: 4.5,
        ),
        validation: validation,
      );
    }

    test('round-trips all core fields without validation', () {
      final design = makeDesign();
      final restored = EmbroideryDesign.fromJsonString(design.toJsonString());

      expect(restored.id, design.id);
      expect(restored.created, design.created);
      expect(restored.stitchPaths.length, 2);
      expect(restored.colorChanges.length, 1);
      expect(restored.colors.length, 2);
      expect(restored.metrics.totalStitches, 300);
      expect(restored.metrics.estimatedMinutes, closeTo(4.5, 0.001));
      expect(restored.validation, isNull);
      // fileBytes is never serialized — should be null after restore
      expect(restored.fileBytes, isNull);
    });

    test('round-trips with validation included', () {
      const validation = DesignValidation(
        severity: ValidationSeverity.warning,
        issues: [
          ValidationIssue(
            code: 'COLORS_EXCEED_CONSUMER_LIMIT',
            message: 'Mais de 16 cores.',
            severity: ValidationSeverity.warning,
          ),
        ],
      );
      final design = makeDesign(validation: validation);
      final restored = EmbroideryDesign.fromJsonString(design.toJsonString());

      expect(restored.validation, isNotNull);
      expect(restored.validation!.severity, ValidationSeverity.warning);
      expect(restored.validation!.issues.first.code, 'COLORS_EXCEED_CONSUMER_LIMIT');
    });

    test('round-trips thread colors with partial manufacturer data', () {
      final design = makeDesign();
      final restored = EmbroideryDesign.fromJsonString(design.toJsonString());

      final red = restored.colors[0];
      expect(red.madeiraCode, '0510');
      expect(red.madeiraName, 'Rubi');
      expect(red.brotherCode, isNull);

      final blue = restored.colors[1];
      expect(blue.brotherCode, '035');
      expect(blue.madeiraCode, isNull);
    });

    test('stitch coordinates survive int-from-JSON edge case', () {
      // Inject whole-number coords that JSON will decode as int, not double
      final design = EmbroideryDesign(
        id: 'int-test',
        created: DateTime.utc(2025, 1, 1),
        stitchPaths: const [
          StitchPath(colorIndex: 0, stitchCount: 2, points: [0.0, 10.0]),
        ],
        colorChanges: const [],
        colors: const [ThreadColor(argb: 0xFFFFFFFF)],
        metrics: const DesignMetrics(
          totalStitches: 2,
          colorChangeCount: 0,
          widthMm: 10.0,
          heightMm: 10.0,
          estimatedMinutes: 1.0,
        ),
      );

      final restored = EmbroideryDesign.fromJsonString(design.toJsonString());
      final points = restored.stitchPaths.first.points;

      expect(points.every((v) => v is double), isTrue);
    });
  });
}
