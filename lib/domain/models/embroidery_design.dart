import 'dart:convert';
import 'dart:typed_data';

/// Represents a single stitch path (one color segment)
class StitchPath {
  const StitchPath({
    required this.colorIndex,
    required this.stitchCount,
    required this.points,
  });

  factory StitchPath.fromJson(Map<String, dynamic> json) => StitchPath(
        colorIndex: json['colorIndex'] as int,
        stitchCount: json['stitchCount'] as int,
        points: (json['points'] as List).cast<double>(),
      );

  /// Index into the design's color list
  final int colorIndex;

  /// Number of stitches in this path
  final int stitchCount;

  /// Stitch coordinates as flat list [x0, y0, x1, y1, ...]
  final List<double> points;

  Map<String, dynamic> toJson() => {
        'colorIndex': colorIndex,
        'stitchCount': stitchCount,
        'points': points,
      };
}

/// Represents a color change event in the stitch sequence
class ColorChange {
  const ColorChange({
    required this.stitchIndex,
    required this.fromColorIndex,
    required this.toColorIndex,
  });

  factory ColorChange.fromJson(Map<String, dynamic> json) => ColorChange(
        stitchIndex: json['stitchIndex'] as int,
        fromColorIndex: json['fromColorIndex'] as int,
        toColorIndex: json['toColorIndex'] as int,
      );

  /// Stitch index where the color change occurs
  final int stitchIndex;

  /// Index of the color being changed from
  final int fromColorIndex;

  /// Index of the color being changed to
  final int toColorIndex;

  Map<String, dynamic> toJson() => {
        'stitchIndex': stitchIndex,
        'fromColorIndex': fromColorIndex,
        'toColorIndex': toColorIndex,
      };
}

/// Represents a thread color with manufacturer references
class ThreadColor {
  const ThreadColor({
    required this.argb,
    this.madeiraCode,
    this.madeiraName,
    this.isacordCode,
    this.isacordName,
    this.brotherCode,
    this.brotherName,
  });

  factory ThreadColor.fromJson(Map<String, dynamic> json) => ThreadColor(
        argb: json['argb'] as int,
        madeiraCode: json['madeiraCode'] as String?,
        madeiraName: json['madeiraName'] as String?,
        isacordCode: json['isacordCode'] as String?,
        isacordName: json['isacordName'] as String?,
        brotherCode: json['brotherCode'] as String?,
        brotherName: json['brotherName'] as String?,
      );

  /// Color as ARGB integer
  final int argb;

  /// Madeira thread code (e.g., '1234')
  final String? madeiraCode;

  /// Madeira thread name
  final String? madeiraName;

  /// Isacord thread code
  final String? isacordCode;

  /// Isacord thread name
  final String? isacordName;

  /// Brother thread code
  final String? brotherCode;

  /// Brother thread name
  final String? brotherName;

  /// Primary display name (uses first available manufacturer name)
  String get displayName =>
      madeiraName ?? isacordName ?? brotherName ?? 'Cor desconhecida';

  /// Primary display code (uses first available manufacturer code)
  String get displayCode =>
      (madeiraCode != null ? 'Madeira $madeiraCode' : null) ??
      (isacordCode != null ? 'Isacord $isacordCode' : null) ??
      (brotherCode != null ? 'Brother $brotherCode' : null) ??
      'N/A';

  Map<String, dynamic> toJson() => {
        'argb': argb,
        if (madeiraCode != null) 'madeiraCode': madeiraCode,
        if (madeiraName != null) 'madeiraName': madeiraName,
        if (isacordCode != null) 'isacordCode': isacordCode,
        if (isacordName != null) 'isacordName': isacordName,
        if (brotherCode != null) 'brotherCode': brotherCode,
        if (brotherName != null) 'brotherName': brotherName,
      };
}

/// Design metrics calculated after generation
class DesignMetrics {
  const DesignMetrics({
    required this.totalStitches,
    required this.colorChangeCount,
    required this.widthMm,
    required this.heightMm,
    required this.estimatedMinutes,
  });

  factory DesignMetrics.fromJson(Map<String, dynamic> json) => DesignMetrics(
        totalStitches: json['totalStitches'] as int,
        colorChangeCount: json['colorChangeCount'] as int,
        widthMm: (json['widthMm'] as num).toDouble(),
        heightMm: (json['heightMm'] as num).toDouble(),
        estimatedMinutes: (json['estimatedMinutes'] as num).toDouble(),
      );

  /// Total number of stitches
  final int totalStitches;

  /// Number of color changes
  final int colorChangeCount;

  /// Final design width in millimeters
  final double widthMm;

  /// Final design height in millimeters
  final double heightMm;

  /// Estimated embroidery time in minutes
  final double estimatedMinutes;

  Map<String, dynamic> toJson() => {
        'totalStitches': totalStitches,
        'colorChangeCount': colorChangeCount,
        'widthMm': widthMm,
        'heightMm': heightMm,
        'estimatedMinutes': estimatedMinutes,
      };
}

/// Preview data for rendering stitch paths on screen
class PreviewData {
  const PreviewData({
    required this.previewBytes,
    required this.widthPx,
    required this.heightPx,
  });

  /// PNG preview image bytes
  final Uint8List previewBytes;

  /// Preview width in pixels
  final int widthPx;

  /// Preview height in pixels
  final int heightPx;
}

/// A complete embroidery design ready for export.
class EmbroideryDesign {
  const EmbroideryDesign({
    required this.id,
    required this.created,
    required this.stitchPaths,
    required this.colorChanges,
    required this.colors,
    required this.metrics,
    this.previewData,
    this.fileBytes,
  });

  factory EmbroideryDesign.fromJson(Map<String, dynamic> json) =>
      EmbroideryDesign(
        id: json['id'] as String,
        created: DateTime.parse(json['created'] as String),
        stitchPaths: (json['stitchPaths'] as List)
            .map((e) => StitchPath.fromJson(e as Map<String, dynamic>))
            .toList(),
        colorChanges: (json['colorChanges'] as List)
            .map((e) => ColorChange.fromJson(e as Map<String, dynamic>))
            .toList(),
        colors: (json['colors'] as List)
            .map((e) => ThreadColor.fromJson(e as Map<String, dynamic>))
            .toList(),
        metrics: DesignMetrics.fromJson(json['metrics'] as Map<String, dynamic>),
      );

  factory EmbroideryDesign.fromJsonString(String jsonString) =>
      EmbroideryDesign.fromJson(
        jsonDecode(jsonString) as Map<String, dynamic>,
      );

  /// Unique identifier
  final String id;

  /// Creation timestamp
  final DateTime created;

  /// Stitch paths, one per color segment
  final List<StitchPath> stitchPaths;

  /// Color change events
  final List<ColorChange> colorChanges;

  /// Thread colors used in the design
  final List<ThreadColor> colors;

  /// Design metrics
  final DesignMetrics metrics;

  /// Preview image data (null until generated)
  final PreviewData? previewData;

  /// Raw embroidery file bytes (null until exported)
  final Uint8List? fileBytes;

  Map<String, dynamic> toJson() => {
        'id': id,
        'created': created.toIso8601String(),
        'stitchPaths': stitchPaths.map((p) => p.toJson()).toList(),
        'colorChanges': colorChanges.map((c) => c.toJson()).toList(),
        'colors': colors.map((c) => c.toJson()).toList(),
        'metrics': metrics.toJson(),
      };

  /// Serialize to JSON string
  String toJsonString() => jsonEncode(toJson());

  @override
  String toString() =>
      'EmbroideryDesign(id: $id, stitches: ${metrics.totalStitches}, '
      'colors: ${colors.length})';
}
