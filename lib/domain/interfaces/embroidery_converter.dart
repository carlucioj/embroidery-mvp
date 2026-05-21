import '../models/embroidery_design.dart';
import '../models/embroidery_parameters.dart';
import '../models/image_data.dart';

/// Progress update during embroidery conversion
class ConversionProgress {
  const ConversionProgress({
    required this.percentage,
    required this.stage,
    this.estimatedSecondsRemaining,
  });

  /// Progress percentage (0.0 to 1.0)
  final double percentage;

  /// Current conversion stage description
  final String stage;

  /// Estimated seconds remaining (null if unknown)
  final int? estimatedSecondsRemaining;
}

/// Abstract interface for converting processed images to embroidery designs.
///
/// Implementations use pyembroidery (via Python bridge) to generate
/// stitch paths from processed images.
abstract class EmbroideryConverter {
  /// Convert a processed image to an embroidery design.
  ///
  /// Returns an [EmbroideryDesign] with stitch paths and metrics.
  /// Throws [EmbroideryConversionException] on failure.
  Future<EmbroideryDesign> convertToEmbroidery(
    ProcessedImage image,
    EmbroideryParameters parameters,
  );

  /// Generate a preview image for an embroidery design.
  Future<PreviewData> generatePreview(EmbroideryDesign design);

  /// Calculate metrics for a design without full conversion.
  DesignMetrics calculateMetrics(EmbroideryDesign design);

  /// Validate embroidery parameters before conversion.
  ///
  /// Returns a list of validation error messages.
  /// Returns empty list if all parameters are valid.
  List<String> validateParameters(EmbroideryParameters params);

  /// Stream of progress updates during conversion.
  Stream<ConversionProgress> get progressStream;

  /// Cancel any ongoing conversion.
  Future<void> cancel();
}

/// Exception thrown when embroidery conversion fails.
class EmbroideryConversionException implements Exception {
  const EmbroideryConversionException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'EmbroideryConversionException: $message';
}
