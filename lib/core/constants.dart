/// Application-wide constants for the Embroidery MVP.
library;

/// App metadata
class AppConstants {
  AppConstants._();

  static const String appName = 'Embroidery MVP';
  static const String appVersion = '0.1.0';

  /// Alpha expiration: 90 days from build date
  static const int alphaExpirationDays = 90;
}

/// SharedPreferences keys
class PrefsKeys {
  PrefsKeys._();

  static const String onboardingCompleted = 'onboarding_completed';
  static const String lastOutputFormat = 'last_output_format';
  static const String lastHoopSize = 'last_hoop_size';
  static const String workflowState = 'workflow_state';
  static const String pendingFeedback = 'pending_feedback';

  // Session persistence keys
  static const String workflowHasSession = 'workflow_has_session';
  static const String workflowCurrentStep = 'workflow_step';
  static const String workflowCapturedMeta = 'workflow_captured_meta';
  static const String workflowCleanedMeta = 'workflow_cleaned_meta';
  static const String workflowParameters = 'workflow_parameters';
}

/// Supported image formats for import
class SupportedFormats {
  SupportedFormats._();

  static const List<String> imageExtensions = [
    'jpg',
    'jpeg',
    'png',
    'bmp',
    'webp',
  ];

  static const List<String> imageExtensionsDisplay = [
    'JPG',
    'JPEG',
    'PNG',
    'BMP',
    'WEBP',
  ];

  /// Maximum image file size in bytes (20 MB)
  static const int maxImageSizeBytes = 20 * 1024 * 1024;

  /// Maximum image file size in MB for display
  static const int maxImageSizeMB = 20;
}

/// Embroidery output formats organized by manufacturer
class OutputFormats {
  OutputFormats._();

  // Formatos confirmados pelo pyembroidery 1.5.1 (write support verificado).
  // HUS, VIP, SEW, CSD, EMB, OFM foram removidos: lançam IOError na escrita.
  static const List<EmbroideryFormat> all = [
    EmbroideryFormat(extension: 'DST', manufacturer: 'Tajima'),
    EmbroideryFormat(extension: 'PES', manufacturer: 'Brother / Babylock'),
    EmbroideryFormat(extension: 'JEF', manufacturer: 'Janome'),
    EmbroideryFormat(extension: 'EXP', manufacturer: 'Melco / Bernina'),
    EmbroideryFormat(extension: 'VP3', manufacturer: 'Husqvarna Viking / Pfaff'),
    EmbroideryFormat(extension: 'XXX', manufacturer: 'Singer'),
  ];
}

/// Represents an embroidery output format
class EmbroideryFormat {
  const EmbroideryFormat({
    required this.extension,
    required this.manufacturer,
  });

  final String extension;
  final String manufacturer;

  String get displayName => '.$extension — $manufacturer';
}

/// Hoop sizes organized by category
class HoopSizes {
  HoopSizes._();

  static const List<HoopSize> round = [
    HoopSize(id: 'round_100', label: '100 × 100 mm', widthMm: 100, heightMm: 100, isRound: true),
    HoopSize(id: 'round_130', label: '130 × 130 mm', widthMm: 130, heightMm: 130, isRound: true),
    HoopSize(id: 'round_150', label: '150 × 150 mm', widthMm: 150, heightMm: 150, isRound: true),
    HoopSize(id: 'round_200', label: '200 × 200 mm', widthMm: 200, heightMm: 200, isRound: true),
  ];

  static const List<HoopSize> rectangular = [
    HoopSize(id: 'rect_100x60', label: '100 × 60 mm', widthMm: 100, heightMm: 60),
    HoopSize(id: 'rect_130x110', label: '130 × 110 mm', widthMm: 130, heightMm: 110),
    HoopSize(id: 'rect_140x200', label: '140 × 200 mm (Brother/Janome)', widthMm: 140, heightMm: 200),
    HoopSize(id: 'rect_150x100', label: '150 × 100 mm', widthMm: 150, heightMm: 100),
    HoopSize(id: 'rect_180x130', label: '180 × 130 mm', widthMm: 180, heightMm: 130),
    HoopSize(id: 'rect_200x140', label: '200 × 140 mm', widthMm: 200, heightMm: 140),
    HoopSize(id: 'rect_260x160', label: '260 × 160 mm', widthMm: 260, heightMm: 160),
    HoopSize(id: 'rect_300x200', label: '300 × 200 mm', widthMm: 300, heightMm: 200),
    HoopSize(id: 'rect_360x200', label: '360 × 200 mm', widthMm: 360, heightMm: 200),
  ];

  static const List<HoopSize> special = [
    HoopSize(id: 'cap_60x70', label: 'Bastidor de Boné (60 × 70 mm)', widthMm: 60, heightMm: 70),
    HoopSize(id: 'sleeve_60x40', label: 'Bastidor de Manga (60 × 40 mm)', widthMm: 60, heightMm: 40),
    HoopSize(id: 'jumbo_360x260', label: 'Bastidor Jumbo (360 × 260 mm)', widthMm: 360, heightMm: 260),
  ];

  static List<HoopSize> get all => [...round, ...rectangular, ...special];
}

/// Represents a hoop size with embroidery area dimensions
class HoopSize {
  const HoopSize({
    required this.id,
    required this.label,
    required this.widthMm,
    required this.heightMm,
    this.isRound = false,
  });

  final String id;
  final String label;
  final double widthMm;
  final double heightMm;
  final bool isRound;
}

/// Fabric types with their stitch density ranges
class FabricTypes {
  FabricTypes._();

  static const FabricType knit = FabricType(
    id: 'knit',
    label: 'Malha',
    description: 'Tecido elástico — densidade reduzida para evitar distorção',
    minDensity: 3.5,
    maxDensity: 4.5,
  );

  static const FabricType cotton = FabricType(
    id: 'cotton',
    label: 'Algodão',
    description: 'Tecido padrão — densidade normal',
    minDensity: 4.5,
    maxDensity: 5.5,
  );

  static const FabricType towel = FabricType(
    id: 'towel',
    label: 'Toalha (felpudo)',
    description: 'Tecido felpudo — densidade elevada para cobrir a textura',
    minDensity: 5.5,
    maxDensity: 7.0,
  );

  static const List<FabricType> all = [knit, cotton, towel];
}

/// Represents a fabric type with stitch density configuration
class FabricType {
  const FabricType({
    required this.id,
    required this.label,
    required this.description,
    required this.minDensity,
    required this.maxDensity,
  });

  final String id;
  final String label;
  final String description;

  /// Minimum stitch density in stitches per mm²
  final double minDensity;

  /// Maximum stitch density in stitches per mm²
  final double maxDensity;

  /// Optimal density (midpoint of range)
  double get optimalDensity => (minDensity + maxDensity) / 2;
}

/// Processing configuration
class ProcessingConfig {
  ProcessingConfig._();

  /// Maximum number of colors after reduction
  static const int maxColors = 8;

  /// Minimum RAM in bytes required for local processing (2 GB)
  static const int minRamForLocalProcessing = 2 * 1024 * 1024 * 1024;

  /// MethodChannel name for Flutter-Python communication
  static const String methodChannelName = 'com.embroidery_mvp/python';

  /// HTTP API base URL for remote processing.
  /// For local testing: run `python api_server.py` and use http://localhost:8000
  /// For production: set to your deployed server URL
  static String apiBaseUrl = 'http://localhost:8000';

  /// HTTP request timeout in seconds
  static const int httpTimeoutSeconds = 60;
}

/// UI layout breakpoints
class LayoutBreakpoints {
  LayoutBreakpoints._();

  /// Minimum width for desktop layout (sidebar navigation)
  static const double desktopMinWidth = 1024;

  /// Minimum supported screen width
  static const double minScreenWidth = 360;

  /// Maximum supported screen width
  static const double maxScreenWidth = 1920;
}

/// Onboarding configuration
class OnboardingConfig {
  OnboardingConfig._();

  /// Maximum number of onboarding screens
  static const int maxScreens = 5;
}

/// Feedback form configuration
class FeedbackConfig {
  FeedbackConfig._();

  /// Maximum characters for feedback description
  static const int maxDescriptionLength = 500;

  /// Satisfaction rating range
  static const int minRating = 1;
  static const int maxRating = 5;
}

/// Export file naming
class ExportConfig {
  ExportConfig._();

  /// Default filename pattern: design_[date]_[time].[format]
  static String defaultFilename(String format) {
    final now = DateTime.now();
    final date = '${now.year}${_pad(now.month)}${_pad(now.day)}';
    final time = '${_pad(now.hour)}${_pad(now.minute)}${_pad(now.second)}';
    return 'design_${date}_$time.${format.toLowerCase()}';
  }

  static String _pad(int value) => value.toString().padLeft(2, '0');
}
