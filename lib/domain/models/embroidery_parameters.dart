import '../../core/constants.dart';

/// How the embroidery fill is rendered for each color region.
enum StitchType {
  fill,     // diagonal tatami fill (45°) + contour outline
  outline,  // running stitch along the boundary only
  satin;    // dense horizontal fill (boustrophedon at 0°), no outline

  String get id => name;

  String get label => switch (this) {
        StitchType.fill => 'Preenchimento',
        StitchType.outline => 'Contorno',
        StitchType.satin => 'Satim',
      };

  String get description => switch (this) {
        StitchType.fill =>
          'Preenche a área com linhas diagonais em zigue-zague (tatami). Ideal para grandes regiões.',
        StitchType.outline =>
          'Traça apenas o contorno da forma em ponto de corrida. Ideal para linhas e bordas.',
        StitchType.satin =>
          'Linhas paralelas densas cobrindo a forma. Ideal para letras e formas estreitas.',
      };
}

/// Parameters that define how an embroidery design will be generated.
class EmbroideryParameters {
  const EmbroideryParameters({
    required this.hoop,
    required this.fabric,
    required this.designWidthMm,
    required this.designHeightMm,
    required this.outputFormat,
    this.stitchType = StitchType.fill,
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

  /// How stitches are generated for each color region
  final StitchType stitchType;

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
    StitchType? stitchType,
    bool? maintainAspectRatio,
  }) {
    return EmbroideryParameters(
      hoop: hoop ?? this.hoop,
      fabric: fabric ?? this.fabric,
      designWidthMm: designWidthMm ?? this.designWidthMm,
      designHeightMm: designHeightMm ?? this.designHeightMm,
      outputFormat: outputFormat ?? this.outputFormat,
      stitchType: stitchType ?? this.stitchType,
      maintainAspectRatio: maintainAspectRatio ?? this.maintainAspectRatio,
    );
  }

  Map<String, dynamic> toJson() => {
        'hoopId': hoop.id,
        'fabricId': fabric.id,
        'designWidthMm': designWidthMm,
        'designHeightMm': designHeightMm,
        'outputFormat': outputFormat.extension,
        'stitchType': stitchType.id,
        'maintainAspectRatio': maintainAspectRatio,
      };

  factory EmbroideryParameters.fromJson(Map<String, dynamic> json) {
    final hoopId = json['hoopId'] as String;
    final fabricId = json['fabricId'] as String;
    final formatExt = json['outputFormat'] as String;
    final stitchTypeId = json['stitchType'] as String? ?? 'fill';

    return EmbroideryParameters(
      hoop: HoopSizes.all.firstWhere(
        (h) => h.id == hoopId,
        orElse: () => HoopSizes.rectangular.first,
      ),
      fabric: FabricTypes.all.firstWhere(
        (f) => f.id == fabricId,
        orElse: () => FabricTypes.cotton,
      ),
      designWidthMm: (json['designWidthMm'] as num).toDouble(),
      designHeightMm: (json['designHeightMm'] as num).toDouble(),
      outputFormat: OutputFormats.all.firstWhere(
        (f) => f.extension == formatExt,
        orElse: () => OutputFormats.all.first,
      ),
      stitchType: StitchType.values.firstWhere(
        (s) => s.id == stitchTypeId,
        orElse: () => StitchType.fill,
      ),
      maintainAspectRatio: json['maintainAspectRatio'] as bool? ?? true,
    );
  }

  @override
  String toString() =>
      'EmbroideryParameters(hoop: ${hoop.label}, fabric: ${fabric.label}, '
      'size: ${designWidthMm.toStringAsFixed(1)}x${designHeightMm.toStringAsFixed(1)} mm, '
      'format: .${outputFormat.extension}, stitch: ${stitchType.id})';
}
