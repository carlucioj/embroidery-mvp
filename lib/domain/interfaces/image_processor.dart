import '../models/image_data.dart';

/// Processing mode selection
enum ProcessingMode {
  /// Always use local Python processing
  local,

  /// Always use remote API processing
  remote,

  /// Automatically select based on device capabilities
  auto,
}

/// Image quality setting for processing
enum ImageQuality {
  /// Faster processing, lower quality
  draft,

  /// Balanced quality and speed
  standard,

  /// Best quality, slower processing
  high,
}

/// Options for image processing
class ProcessingOptions {
  const ProcessingOptions({
    this.removeBackground = true,
    this.maxColors = 8,
    this.quality = ImageQuality.standard,
    this.mode = ProcessingMode.auto,
  });

  /// Whether to remove the image background
  final bool removeBackground;

  /// Maximum number of colors after reduction
  final int maxColors;

  /// Processing quality level
  final ImageQuality quality;

  /// Processing mode (local, remote, or auto)
  final ProcessingMode mode;

  static const ProcessingOptions defaults = ProcessingOptions();
}

/// Progress update during image processing
class ProcessingProgress {
  const ProcessingProgress({
    required this.percentage,
    required this.stage,
    this.estimatedSecondsRemaining,
  });

  /// Progress percentage (0.0 to 1.0)
  final double percentage;

  /// Current processing stage description
  final String stage;

  /// Estimated seconds remaining (null if unknown)
  final int? estimatedSecondsRemaining;
}

/// Result of image processing
class ProcessingResult {
  const ProcessingResult({
    required this.processedImage,
    required this.wasRemote,
  });

  /// The processed image
  final ProcessedImage processedImage;

  /// Whether processing was done remotely
  final bool wasRemote;
}

/// Validation result for image input
class ValidationResult {
  const ValidationResult({
    required this.isValid,
    this.errorMessage,
  });

  const ValidationResult.valid() : isValid = true, errorMessage = null;

  const ValidationResult.invalid(String message)
      : isValid = false,
        errorMessage = message;

  final bool isValid;
  final String? errorMessage;
}

/// Device processing capabilities
class ProcessingCapabilities {
  const ProcessingCapabilities({
    required this.canProcessLocally,
    required this.availableRamBytes,
    required this.isDesktop,
  });

  /// Whether the device can process images locally
  final bool canProcessLocally;

  /// Available RAM in bytes
  final int availableRamBytes;

  /// Whether running on desktop
  final bool isDesktop;
}

/// Abstract interface for image processing.
///
/// Implementations handle background removal and color reduction,
/// either locally via Python or remotely via HTTP API.
abstract class ImageProcessor {
  /// Process an image with the given options.
  ///
  /// Returns a [ProcessingResult] with the processed image.
  /// Throws [ImageProcessingException] on failure.
  Future<ProcessingResult> processImage(
    ImageData input,
    ProcessingOptions options,
  );

  /// Stream of progress updates during processing.
  Stream<ProcessingProgress> get progressStream;

  /// Validate an image before processing.
  ///
  /// Checks format, size, and other constraints.
  ValidationResult validateImage(ImageData input);

  /// Get the processing capabilities of the current device.
  Future<ProcessingCapabilities> getCapabilities();

  /// Cancel any ongoing processing.
  Future<void> cancel();
}

/// Exception thrown when image processing fails.
class ImageProcessingException implements Exception {
  const ImageProcessingException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'ImageProcessingException: $message';
}
