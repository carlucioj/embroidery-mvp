import '../../core/constants.dart';

/// Parameters that define how an embroidery design will be generated.
class EmbroideryParameters {
  const EmbroideryParameters({
    required this.hoop,
    required this.fabric,
    required this.designWidthMm,
    required this.designHeightMm,
    required this.outputFormat,
    this.maintainAspectRatio = true,
  });

  /// Selected hoop size
  final HoopSize hoop;

  /// Selected fabric type
  final FabricType fabric;

  /// Design width in millimeters
  final double designWidthMm;

  /// Design height in millimeters
  final double designHeightMm;

  /// Output file format (e.g., 'DST', 'PES')
  final EmbroideryFormat outputFormat;

  /// Whether to maintain aspect ratio when resizing
  final bool maintainAspectRatio;

  /// Stitch density to use (optimal for selected fabric)
  double get stitchDensity => fabric.optimalDensity;

  /// Whether the design fits within the hoop area
  bool get fitsInHoop =>
      designWidthMm <= hoop.widthMm && designHeightMm <= hoop.heightMm;

  /// Validate all parameters and return a list of validation errors.
  /// Returns an empty list if all parameters are valid.
  List<String> validate() {
    final errors = <String>[];

    if (designWidthMm <= 0) {
      errors.add('A largura do design deve ser maior que zero.');
    }
    if (designHeightMm <= 0) {
      errors.add('A altura do design deve ser maior que zero.');
    }
    if (designWidthMm > hoop.widthMm) {
      errors.add(
        'A largura do design (${designWidthMm.toStringAsFixed(1)} mm) '
        'excede a área do bastidor (${hoop.widthMm} mm).',
      );
    }
    if (designHeightMm > hoop.heightMm) {
      errors.add(
        'A altura do design (${designHeightMm.toStringAsFixed(1)} mm) '
        'excede a área do bastidor (${hoop.heightMm} mm).',
      );
    }

    return errors;
  }

  /// Returns a copy with dimensions clamped to fit within the hoop.
  EmbroideryParameters clampToHoop() {
    return copyWith(
      designWidthMm: designWidthMm.clamp(1, hoop.widthMm),
      designHeightMm: designHeightMm.clamp(1, hoop.heightMm),
    );
  }

  /// Returns a copy with dimensions scaled to fill the hoop while
  /// maintaining the original aspect ratio.
  EmbroideryParameters fitToHoop() {
    if (designWidthMm <= 0 || designHeightMm <= 0) return this;

    final aspectRatio = designWidthMm / designHeightMm;
    final hoopAspectRatio = hoop.widthMm / hoop.heightMm;

    double newWidth;
    double newHeight;

    if (aspectRatio > hoopAspectRatio) {
      // Width-constrained
      newWidth = hoop.widthMm;
      newHeight = newWidth / aspectRatio;
    } else {
      // Height-constrained
      newHeight = hoop.heightMm;
      newWidth = newHeight * aspectRatio;
    }

    return copyWith(
      designWidthMm: newWidth,
      designHeightMm: newHeight,
    );
  }

  /// Returns a copy with the height recalculated to maintain aspect ratio
  /// based on the given original dimensions.
  EmbroideryParameters withProportionalHeight({
    required double originalWidth,
    required double originalHeight,
    required double newWidth,
  }) {
    if (originalWidth <= 0 || originalHeight <= 0) return this;
    final ratio = originalHeight / originalWidth;
    return copyWith(
      designWidthMm: newWidth,
      designHeightMm: newWidth * ratio,
    );
  }

  /// Returns a copy with the width recalculated to maintain aspect ratio
  /// based on the given original dimensions.
  EmbroideryParameters withProportionalWidth({
    required double originalWidth,
    required double originalHeight,
    required double newHeight,
  }) {
    if (originalWidth <= 0 || originalHeight <= 0) return this;
    final ratio = originalWidth / originalHeight;
    return copyWith(
      designWidthMm: newHeight * ratio,
      designHeightMm: newHeight,
    );
  }

  EmbroideryParameters copyWith({
    HoopSize? hoop,
    FabricType? fabric,
    double? designWidthMm,
    double? designHeightMm,
    EmbroideryFormat? outputFormat,
    bool? maintainAspectRatio,
  }) {
    return EmbroideryParameters(
      hoop: hoop ?? this.hoop,
      fabric: fabric ?? this.fabric,
      designWidthMm: designWidthMm ?? this.designWidthMm,
      designHeightMm: designHeightMm ?? this.designHeightMm,
      outputFormat: outputFormat ?? this.outputFormat,
      maintainAspectRatio: maintainAspectRatio ?? this.maintainAspectRatio,
    );
  }

  @override
  String toString() =>
      'EmbroideryParameters(hoop: ${hoop.label}, fabric: ${fabric.label}, '
      'size: ${designWidthMm.toStringAsFixed(1)}x${designHeightMm.toStringAsFixed(1)} mm, '
      'format: .${outputFormat.extension})';
}
