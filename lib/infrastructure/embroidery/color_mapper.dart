import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';

import '../../domain/models/embroidery_design.dart';

/// Maps image colors to the nearest thread colors using CIE Lab distance.
///
/// Loads color tables for Madeira, Isacord, and Brother from local assets
/// and finds the closest match for each color using Euclidean distance
/// in the CIE Lab color space.
class ColorMapper {
  ColorMapper();

  List<_ThreadEntry>? _madeiraColors;
  List<_ThreadEntry>? _isacordColors;
  List<_ThreadEntry>? _brotherColors;
  bool _loaded = false;
  // Prevents parallel loads: concurrent callers await the same Future.
  Completer<void>? _loadCompleter;

  /// Load color tables from assets. Must be called before [mapColors].
  /// Safe to call concurrently — subsequent calls await the first load.
  Future<void> loadColorTables() async {
    if (_loaded) return;
    if (_loadCompleter != null) return _loadCompleter!.future;

    _loadCompleter = Completer<void>();
    try {
      final madeiraJson = await rootBundle.loadString('assets/colors/madeira.json');
      final isacordJson = await rootBundle.loadString('assets/colors/isacord.json');
      final brotherJson = await rootBundle.loadString('assets/colors/brother.json');

      _madeiraColors = _parseColorTable(madeiraJson);
      _isacordColors = _parseColorTable(isacordJson);
      _brotherColors = _parseColorTable(brotherJson);
      _loaded = true;
      _loadCompleter!.complete();
    } catch (e, st) {
      final c = _loadCompleter!;
      _loadCompleter = null; // allow retry on next call
      c.completeError(e, st);
      rethrow;
    }
  }

  /// Map a list of ARGB colors to the nearest thread colors.
  ///
  /// Returns a list of [ThreadColor] with manufacturer codes and names.
  Future<List<ThreadColor>> mapColors(List<int> argbColors) async {
    await loadColorTables();

    return argbColors.map((argb) => _mapSingleColor(argb)).toList();
  }

  ThreadColor _mapSingleColor(int argb) {
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;

    final lab = _rgbToLab(r, g, b);

    final madeiraMatch = _findNearest(lab, _madeiraColors ?? []);
    final isacordMatch = _findNearest(lab, _isacordColors ?? []);
    final brotherMatch = _findNearest(lab, _brotherColors ?? []);

    return ThreadColor(
      argb: argb,
      madeiraCode: madeiraMatch?.code,
      madeiraName: madeiraMatch?.name,
      isacordCode: isacordMatch?.code,
      isacordName: isacordMatch?.name,
      brotherCode: brotherMatch?.code,
      brotherName: brotherMatch?.name,
    );
  }

  _ThreadEntry? _findNearest(List<double> lab, List<_ThreadEntry> entries) {
    if (entries.isEmpty) return null;

    _ThreadEntry? nearest;
    double minDistance = double.infinity;

    for (final entry in entries) {
      final distance = _labDistance(lab, entry.lab);
      if (distance < minDistance) {
        minDistance = distance;
        nearest = entry;
      }
    }

    return nearest;
  }

  /// Euclidean distance in CIE Lab color space.
  double _labDistance(List<double> lab1, List<double> lab2) {
    final dL = lab1[0] - lab2[0];
    final da = lab1[1] - lab2[1];
    final db = lab1[2] - lab2[2];
    return math.sqrt(dL * dL + da * da + db * db);
  }

  /// Convert RGB (0-255) to CIE Lab.
  List<double> _rgbToLab(int r, int g, int b) {
    // Step 1: Normalize to 0-1 and apply gamma correction
    double rLin = r / 255.0;
    double gLin = g / 255.0;
    double bLin = b / 255.0;

    rLin = rLin > 0.04045 ? math.pow((rLin + 0.055) / 1.055, 2.4).toDouble() : rLin / 12.92;
    gLin = gLin > 0.04045 ? math.pow((gLin + 0.055) / 1.055, 2.4).toDouble() : gLin / 12.92;
    bLin = bLin > 0.04045 ? math.pow((bLin + 0.055) / 1.055, 2.4).toDouble() : bLin / 12.92;

    // Step 2: RGB to XYZ (D65 illuminant)
    final x = (rLin * 0.4124564 + gLin * 0.3575761 + bLin * 0.1804375) / 0.95047;
    final y = (rLin * 0.2126729 + gLin * 0.7151522 + bLin * 0.0721750) / 1.00000;
    final z = (rLin * 0.0193339 + gLin * 0.1191920 + bLin * 0.9503041) / 1.08883;

    // Step 3: XYZ to Lab
    double fx = x > 0.008856 ? math.pow(x, 1.0 / 3.0).toDouble() : (7.787 * x) + (16.0 / 116.0);
    double fy = y > 0.008856 ? math.pow(y, 1.0 / 3.0).toDouble() : (7.787 * y) + (16.0 / 116.0);
    double fz = z > 0.008856 ? math.pow(z, 1.0 / 3.0).toDouble() : (7.787 * z) + (16.0 / 116.0);

    final l = (116.0 * fy) - 16.0;
    final a = 500.0 * (fx - fy);
    final bVal = 200.0 * (fy - fz);

    return [l, a, bVal];
  }

  List<_ThreadEntry> _parseColorTable(String jsonString) {
    final list = jsonDecode(jsonString) as List;
    return list.map((item) {
      final map = item as Map<String, dynamic>;
      final r = map['r'] as int;
      final g = map['g'] as int;
      final bVal = map['b'] as int;
      return _ThreadEntry(
        code: map['code'] as String,
        name: map['name'] as String,
        lab: _rgbToLab(r, g, bVal),
      );
    }).toList();
  }
}

class _ThreadEntry {
  const _ThreadEntry({
    required this.code,
    required this.name,
    required this.lab,
  });

  final String code;
  final String name;
  final List<double> lab;
}
