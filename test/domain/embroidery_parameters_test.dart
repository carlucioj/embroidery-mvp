import 'package:embroidery_mvp/core/constants.dart';
import 'package:embroidery_mvp/domain/models/embroidery_parameters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Standard test hoop and fabric
  const testHoop = HoopSize(
    id: 'rect_200x140',
    label: '200 × 140 mm',
    widthMm: 200,
    heightMm: 140,
  );
  const testFabric = FabricTypes.cotton;
  const testFormat = EmbroideryFormat(extension: 'DST', manufacturer: 'Tajima');

  EmbroideryParameters makeParams({
    double width = 100,
    double height = 80,
    HoopSize? hoop,
  }) {
    return EmbroideryParameters(
      hoop: hoop ?? testHoop,
      fabric: testFabric,
      designWidthMm: width,
      designHeightMm: height,
      outputFormat: testFormat,
    );
  }

  group('EmbroideryParameters.validate()', () {
    test('returns empty list for valid parameters', () {
      final params = makeParams();
      expect(params.validate(), isEmpty);
    });

    test('returns error when width exceeds hoop', () {
      final params = makeParams(width: 250); // hoop is 200mm wide
      final errors = params.validate();
      expect(errors, isNotEmpty);
      expect(errors.first, contains('largura'));
    });

    test('returns error when height exceeds hoop', () {
      final params = makeParams(height: 200); // hoop is 140mm tall
      final errors = params.validate();
      expect(errors, isNotEmpty);
      expect(errors.first, contains('altura'));
    });

    test('returns error for zero width', () {
      final params = makeParams(width: 0);
      expect(params.validate(), isNotEmpty);
    });

    test('returns error for negative height', () {
      final params = makeParams(height: -10);
      expect(params.validate(), isNotEmpty);
    });
  });

  group('EmbroideryParameters.fitsInHoop', () {
    test('returns true when design fits', () {
      expect(makeParams(width: 100, height: 80).fitsInHoop, isTrue);
    });

    test('returns false when width exceeds hoop', () {
      expect(makeParams(width: 201, height: 80).fitsInHoop, isFalse);
    });

    test('returns false when height exceeds hoop', () {
      expect(makeParams(width: 100, height: 141).fitsInHoop, isFalse);
    });

    test('returns true at exact hoop dimensions', () {
      expect(makeParams(width: 200, height: 140).fitsInHoop, isTrue);
    });
  });

  group('EmbroideryParameters.fitToHoop()', () {
    test('scales wide design to fit hoop width', () {
      // 4:1 aspect ratio, hoop is 200x140
      final params = makeParams(width: 400, height: 100);
      final fitted = params.fitToHoop();
      expect(fitted.designWidthMm, closeTo(200, 0.01));
      expect(fitted.designHeightMm, closeTo(50, 0.01));
    });

    test('scales tall design to fit hoop height', () {
      // 1:4 aspect ratio, hoop is 200x140
      final params = makeParams(width: 100, height: 400);
      final fitted = params.fitToHoop();
      expect(fitted.designHeightMm, closeTo(140, 0.01));
      expect(fitted.designWidthMm, closeTo(35, 0.01));
    });

    test('maintains aspect ratio after fitting', () {
      final params = makeParams(width: 300, height: 200);
      const originalRatio = 300.0 / 200.0;
      final fitted = params.fitToHoop();
      final fittedRatio = fitted.designWidthMm / fitted.designHeightMm;
      expect(fittedRatio, closeTo(originalRatio, 0.001));
    });
  });

  group('EmbroideryParameters.withProportionalHeight()', () {
    test('recalculates height proportionally', () {
      final params = makeParams(width: 100, height: 80);
      final updated = params.withProportionalHeight(
        originalWidth: 100,
        originalHeight: 80,
        newWidth: 150,
      );
      // ratio is 80/100 = 0.8, so new height = 150 * 0.8 = 120
      expect(updated.designWidthMm, closeTo(150, 0.01));
      expect(updated.designHeightMm, closeTo(120, 0.01));
    });
  });

  group('EmbroideryParameters.withProportionalWidth()', () {
    test('recalculates width proportionally', () {
      final params = makeParams(width: 100, height: 80);
      final updated = params.withProportionalWidth(
        originalWidth: 100,
        originalHeight: 80,
        newHeight: 40,
      );
      // ratio is 100/80 = 1.25, so new width = 40 * 1.25 = 50
      expect(updated.designWidthMm, closeTo(50, 0.01));
      expect(updated.designHeightMm, closeTo(40, 0.01));
    });
  });

  group('FabricType density ranges', () {
    test('knit has density between 3.5 and 4.5', () {
      expect(FabricTypes.knit.minDensity, 3.5);
      expect(FabricTypes.knit.maxDensity, 4.5);
    });

    test('cotton has density between 4.5 and 5.5', () {
      expect(FabricTypes.cotton.minDensity, 4.5);
      expect(FabricTypes.cotton.maxDensity, 5.5);
    });

    test('towel has density between 5.5 and 7.0', () {
      expect(FabricTypes.towel.minDensity, 5.5);
      expect(FabricTypes.towel.maxDensity, 7.0);
    });

    test('optimal density is midpoint of range', () {
      expect(FabricTypes.knit.optimalDensity, closeTo(4.0, 0.01));
      expect(FabricTypes.cotton.optimalDensity, closeTo(5.0, 0.01));
      expect(FabricTypes.towel.optimalDensity, closeTo(6.25, 0.01));
    });
  });
}
