import 'dart:typed_data';

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
  });

  /// Processed image bytes (PNG with transparency)
  final Uint8List bytes;

  /// Number of distinct colors after reduction (max 8)
  final int colorCount;

  /// Time taken to process in milliseconds
  final int processingDurationMs;

  /// List of dominant colors as ARGB integers
  final List<int> dominantColors;

  @override
  String toString() =>
      'ProcessedImage(colors: $colorCount, duration: ${processingDurationMs}ms)';
}
