import '../models/embroidery_design.dart';

/// Represents an export destination (file path)
class ExportDestination {
  const ExportDestination({
    required this.path,
    required this.isUsb,
  });

  /// Full file path including filename
  final String path;

  /// Whether this destination is a USB drive
  final bool isUsb;
}

/// Options for exporting an embroidery design
class ExportOptions {
  const ExportOptions({
    required this.format,
    required this.filename,
    required this.destination,
    this.createBackup = false,
  });

  /// Output format extension (e.g., 'DST', 'PES')
  final String format;

  /// Output filename (without path)
  final String filename;

  /// Export destination
  final ExportDestination destination;

  /// Whether to create a backup copy
  final bool createBackup;
}

/// Result of an export operation
class ExportResult {
  const ExportResult({
    required this.success,
    required this.filePath,
    this.errorMessage,
  });

  final bool success;

  /// Full path of the exported file
  final String filePath;

  /// Error message if export failed
  final String? errorMessage;
}

/// Record of a completed export
class ExportRecord {
  const ExportRecord({
    required this.id,
    required this.timestamp,
    required this.filePath,
    required this.format,
    required this.fileSizeBytes,
  });

  factory ExportRecord.fromJson(Map<String, dynamic> json) => ExportRecord(
        id: json['id'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        filePath: json['filePath'] as String,
        format: json['format'] as String,
        fileSizeBytes: json['fileSizeBytes'] as int,
      );

  final String id;
  final DateTime timestamp;
  final String filePath;
  final String format;
  final int fileSizeBytes;

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'filePath': filePath,
        'format': format,
        'fileSizeBytes': fileSizeBytes,
      };
}

/// Abstract interface for exporting embroidery designs.
///
/// Implementations handle platform-specific file saving:
/// - Desktop: file picker dialog with USB support
/// - Mobile: save to Downloads folder
abstract class ExportManager {
  /// Export a design with the given options.
  ///
  /// Returns an [ExportResult] indicating success or failure.
  Future<ExportResult> exportDesign(
    EmbroideryDesign design,
    ExportOptions options,
  );

  /// Open a destination picker dialog.
  ///
  /// Returns the selected destination, or null if cancelled.
  Future<ExportDestination?> selectDestination(String suggestedFilename);

  /// Validate that a destination has sufficient disk space.
  ///
  /// Returns null if valid, or an error message if not.
  Future<String?> validateDestination(
    ExportDestination destination,
    int requiredBytes,
  );

  /// Get the export history for this device.
  Future<List<ExportRecord>> getExportHistory();

  /// Clear the export history.
  Future<void> clearExportHistory();
}

/// Exception thrown when export fails.
class ExportException implements Exception {
  const ExportException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'ExportException: $message';
}
