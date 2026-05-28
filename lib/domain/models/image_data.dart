import 'dart:typed_data';

// ── Complexity analysis ───────────────────────────────────────────────────────

enum ComplexityLevel { simple, medium, complex }

/// Analysis result from the Python image processor after color quantization.
class ImageComplexity {
  const ImageComplexity({
    required this.level,
    required this.score,
    required this.uniqueColors,
    required this.edgeDensity,
    required this.regionCount,
    required this.avgRegionAreaPx,
  });

  final ComplexityLevel level;
  final int score;
  final int uniqueColors;
  final double edgeDensity;
  final int regionCount;
  final double avgRegionAreaPx;

  factory ImageComplexity.fromJson(Map<String, dynamic> json) {
    final levelStr = json['level'] as String? ?? 'simple';
    final level = switch (levelStr) {
      'medium' => ComplexityLevel.medium,
      'complex' => ComplexityLevel.complex,
      _ => ComplexityLevel.simple,
    };
    return ImageComplexity(
      level: level,
      score: (json['score'] as num?)?.toInt() ?? 0,
      uniqueColors: (json['unique_colors'] as num?)?.toInt() ?? 0,
      edgeDensity: (json['edge_density'] as num?)?.toDouble() ?? 0.0,
      regionCount: (json['region_count'] as num?)?.toInt() ?? 0,
      avgRegionAreaPx: (json['avg_region_area_px'] as num?)?.toDouble() ?? 0.0,
    );
  }

  String get levelLabel => switch (level) {
        ComplexityLevel.simple => 'Simples',
        ComplexityLevel.medium => 'Moderada',
        ComplexityLevel.complex => 'Complexa',
      };

  Map<String, dynamic> toJson() => {
        'level': level.name,
        'score': score,
        'unique_colors': uniqueColors,
        'edge_density': edgeDensity,
        'region_count': regionCount,
        'avg_region_area_px': avgRegionAreaPx,
      };

  String get recommendation => switch (level) {
        ComplexityLevel.simple => 'Boa para bordado direto.',
        ComplexityLevel.medium => 'Refinamento pode melhorar o resultado.',
        ComplexityLevel.complex => 'Refinamento recomendado ou use outra imagem.',
      };
}

// ── Image models ──────────────────────────────────────────────────────────────

/// Represents an image loaded into the application.
class ImageData {
  const ImageData({
    required this.bytes,
    required this.filename,
    required this.extension,
    required this.sizeBytes,
    this.widthPx,
    this.heightPx,
  });

  /// Raw image bytes
  final Uint8List bytes;

  /// Original filename (without path)
  final String filename;

  /// File extension in lowercase (e.g., 'jpg', 'png')
  final String extension;

  /// File size in bytes
  final int sizeBytes;

  /// Image width in pixels (null if not yet decoded)
  final int? widthPx;

  /// Image height in pixels (null if not yet decoded)
  final int? heightPx;

  /// File size in megabytes
  double get sizeMB => sizeBytes / (1024 * 1024);

  /// Whether the image has known dimensions
  bool get hasDimensions => widthPx != null && heightPx != null;

  /// Aspect ratio (width / height), or null if dimensions unknown
  double? get aspectRatio {
    if (!hasDimensions) return null;
    return widthPx! / heightPx!;
  }

  ImageData copyWith({
    Uint8List? bytes,
    String? filename,
    String? extension,
    int? sizeBytes,
    int? widthPx,
    int? heightPx,
  }) {
    return ImageData(
      bytes: bytes ?? this.bytes,
      filename: filename ?? this.filename,
      extension: extension ?? this.extension,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      widthPx: widthPx ?? this.widthPx,
      heightPx: heightPx ?? this.heightPx,
    );
  }

  /// Serializes metadata only (bytes are stored separately as a file).
  Map<String, dynamic> toJson() => {
        'filename': filename,
        'extension': extension,
        'sizeBytes': sizeBytes,
        if (widthPx != null) 'widthPx': widthPx,
        if (heightPx != null) 'heightPx': heightPx,
      };

  @override
  String toString() =>
      'ImageData(filename: $filename, size: ${sizeMB.toStringAsFixed(2)} MB, '
      'dimensions: ${widthPx}x$heightPx)';
}

/// Represents a processed image after background removal and color reduction.
class ProcessedImage {
  const ProcessedImage({
    required this.bytes,
    required this.colorCount,
    required this.processingDurationMs,
    this.dominantColors = const [],
    this.complexity,
  });

  /// Processed image bytes (PNG with transparency)
  final Uint8List bytes;

  /// Number of distinct colors after reduction (max 8)
  final int colorCount;

  /// Time taken to process in milliseconds
  final int processingDurationMs;

  /// List of dominant colors as ARGB integers
  final List<int> dominantColors;

  /// Complexity analysis from the Python backend (null if not available)
  final ImageComplexity? complexity;

  /// Serializes metadata only (bytes are stored separately as a file).
  Map<String, dynamic> toJson() => {
        'colorCount': colorCount,
        'processingDurationMs': processingDurationMs,
        'dominantColors': dominantColors,
        if (complexity != null) 'complexity': complexity!.toJson(),
      };

  @override
  String toString() =>
      'ProcessedImage(colors: $colorCount, duration: ${processingDurationMs}ms)';
}
