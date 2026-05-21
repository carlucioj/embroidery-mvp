import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../core/constants.dart';
import '../../domain/interfaces/image_processor.dart';
import '../../domain/models/image_data.dart';

/// Pure-Dart image processor — no Python, no server required.
///
/// Runs entirely on the device using Flutter's dart:ui APIs.
/// Supports:
///   - Background removal via flood-fill from corners
///   - Color reduction via K-means clustering
class DartImageProcessor implements ImageProcessor {
  DartImageProcessor();

  final _progressController = StreamController<ProcessingProgress>.broadcast();
  bool _cancelled = false;

  @override
  Stream<ProcessingProgress> get progressStream => _progressController.stream;

  @override
  ValidationResult validateImage(ImageData input) {
    if (!SupportedFormats.imageExtensions
        .contains(input.extension.toLowerCase())) {
      return ValidationResult.invalid(
        'Formato não suportado: .${input.extension}. '
        'Use ${SupportedFormats.imageExtensionsDisplay.join(", ")}.',
      );
    }
    if (input.sizeBytes > SupportedFormats.maxImageSizeBytes) {
      return ValidationResult.invalid(
        'Arquivo muito grande: ${input.sizeMB.toStringAsFixed(1)} MB. '
        'O limite é ${SupportedFormats.maxImageSizeMB} MB.',
      );
    }
    return const ValidationResult.valid();
  }

  @override
  Future<ProcessingCapabilities> getCapabilities() async {
    return const ProcessingCapabilities(
      canProcessLocally: true,
      availableRamBytes: 4 * 1024 * 1024 * 1024,
      isDesktop: true,
    );
  }

  @override
  Future<ProcessingResult> processImage(
    ImageData input,
    ProcessingOptions options,
  ) async {
    _cancelled = false;

    final validation = validateImage(input);
    if (!validation.isValid) {
      throw ImageProcessingException(validation.errorMessage!);
    }

    _emitProgress(0.05, 'Decodificando imagem...');

    // Decode image to raw RGBA pixels using dart:ui
    final codec = await ui.instantiateImageCodec(input.bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final width = image.width;
    final height = image.height;

    _emitProgress(0.15, 'Lendo pixels...');

    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) {
      throw const ImageProcessingException('Não foi possível ler os pixels da imagem.');
    }

    if (_cancelled) throw const ImageProcessingException('Cancelado.');

    // Get initial pixels
    var pixels = Uint8List.fromList(byteData.buffer.asUint8List());

    // ── Step 1: Background removal (optional) ──────────────────────────
    if (options.removeBackground) {
      _emitProgress(0.25, 'Removendo fundo...');
      // FIX: assign the result back to pixels (isolate returns a new Uint8List)
      pixels = await compute(
        _removeBackgroundIsolate,
        _RemoveBgParams(pixels, width, height),
      );
    }

    if (_cancelled) throw const ImageProcessingException('Cancelado.');

    // ── Step 2: Color reduction ─────────────────────────────────────────
    _emitProgress(0.55, 'Simplificando cores...');
    // FIX: assign the result back to pixels
    pixels = await compute(
      _reduceColorsIsolate,
      _ReduceColorsParams(pixels, width, height, options.maxColors),
    );

    if (_cancelled) throw const ImageProcessingException('Cancelado.');

    _emitProgress(0.85, 'Gerando imagem final...');

    // Re-encode to PNG
    final resultBytes = await _pixelsToPng(pixels, width, height);

    _emitProgress(1.0, 'Concluído!');

    return ProcessingResult(
      processedImage: ProcessedImage(
        bytes: resultBytes,
        colorCount: options.maxColors,
        processingDurationMs: 0,
        dominantColors: const [],
      ),
      wasRemote: false,
    );
  }

  @override
  Future<void> cancel() async => _cancelled = true;

  void _emitProgress(double p, String stage) {
    if (!_progressController.isClosed) {
      _progressController.add(ProcessingProgress(percentage: p, stage: stage));
    }
  }

  void dispose() => _progressController.close();

  /// Convert raw RGBA pixels back to PNG bytes.
  Future<Uint8List> _pixelsToPng(Uint8List pixels, int width, int height) async {
    final completer = Completer<Uint8List>();
    ui.decodeImageFromPixels(
      pixels,
      width,
      height,
      ui.PixelFormat.rgba8888,
      (img) async {
        final data = await img.toByteData(format: ui.ImageByteFormat.png);
        completer.complete(
          data != null
              ? Uint8List.fromList(data.buffer.asUint8List())
              : pixels,
        );
      },
    );
    return completer.future;
  }
}

// ── Isolate helpers ──────────────────────────────────────────────────────────

class _RemoveBgParams {
  const _RemoveBgParams(this.pixels, this.width, this.height);
  final Uint8List pixels;
  final int width;
  final int height;
}

/// Background removal via flood-fill from all four corners.
Uint8List _removeBackgroundIsolate(_RemoveBgParams p) {
  final pixels = Uint8List.fromList(p.pixels);
  final w = p.width;
  final h = p.height;
  const tolerance = 40;

  final bgColor = _getPixel(pixels, 0, 0, w);

  final visited = List<bool>.filled(w * h, false);
  final queue = <int>[];

  void enqueue(int x, int y) {
    if (x < 0 || x >= w || y < 0 || y >= h) return;
    final idx = y * w + x;
    if (visited[idx]) return;
    final c = _getPixel(pixels, x, y, w);
    if (_colorDistance(c, bgColor) <= tolerance) {
      visited[idx] = true;
      queue.add(x | (y << 16));
    }
  }

  for (int x = 0; x < w; x++) {
    enqueue(x, 0);
    enqueue(x, h - 1);
  }
  for (int y = 0; y < h; y++) {
    enqueue(0, y);
    enqueue(w - 1, y);
  }

  while (queue.isNotEmpty) {
    final coord = queue.removeLast();
    final x = coord & 0xFFFF;
    final y = coord >> 16;
    final base = (y * w + x) * 4;
    pixels[base + 3] = 0;
    enqueue(x + 1, y);
    enqueue(x - 1, y);
    enqueue(x, y + 1);
    enqueue(x, y - 1);
  }

  return pixels;
}

class _ReduceColorsParams {
  const _ReduceColorsParams(this.pixels, this.width, this.height, this.maxColors);
  final Uint8List pixels;
  final int width;
  final int height;
  final int maxColors;
}

/// K-means color quantization in pure Dart.
Uint8List _reduceColorsIsolate(_ReduceColorsParams p) {
  final pixels = Uint8List.fromList(p.pixels);
  final total = p.width * p.height;
  final k = math.min(p.maxColors, 32);

  final visibleColors = <List<int>>[];
  for (int i = 0; i < total; i++) {
    final base = i * 4;
    if (pixels[base + 3] > 10) {
      visibleColors.add([pixels[base], pixels[base + 1], pixels[base + 2]]);
    }
  }

  if (visibleColors.isEmpty) return pixels;

  final step = math.max(1, visibleColors.length ~/ k);
  final centroids = List.generate(
    math.min(k, visibleColors.length),
    (i) => List<double>.from(visibleColors[(i * step) % visibleColors.length]),
  );

  for (int iter = 0; iter < 10; iter++) {
    final sums = List.generate(centroids.length, (_) => [0.0, 0.0, 0.0]);
    final counts = List<int>.filled(centroids.length, 0);

    for (final color in visibleColors) {
      int nearest = 0;
      double minDist = double.infinity;
      for (int c = 0; c < centroids.length; c++) {
        final d = _colorDistList(color, centroids[c]);
        if (d < minDist) {
          minDist = d;
          nearest = c;
        }
      }
      sums[nearest][0] += color[0];
      sums[nearest][1] += color[1];
      sums[nearest][2] += color[2];
      counts[nearest]++;
    }

    bool changed = false;
    for (int c = 0; c < centroids.length; c++) {
      if (counts[c] == 0) continue;
      final newR = sums[c][0] / counts[c];
      final newG = sums[c][1] / counts[c];
      final newB = sums[c][2] / counts[c];
      if ((newR - centroids[c][0]).abs() > 1 ||
          (newG - centroids[c][1]).abs() > 1 ||
          (newB - centroids[c][2]).abs() > 1) {
        changed = true;
      }
      centroids[c] = [newR, newG, newB];
    }
    if (!changed) break;
  }

  for (int i = 0; i < total; i++) {
    final base = i * 4;
    if (pixels[base + 3] <= 10) continue;
    final color = [pixels[base], pixels[base + 1], pixels[base + 2]];
    int nearest = 0;
    double minDist = double.infinity;
    for (int c = 0; c < centroids.length; c++) {
      final d = _colorDistList(color, centroids[c]);
      if (d < minDist) {
        minDist = d;
        nearest = c;
      }
    }
    pixels[base] = centroids[nearest][0].round().clamp(0, 255);
    pixels[base + 1] = centroids[nearest][1].round().clamp(0, 255);
    pixels[base + 2] = centroids[nearest][2].round().clamp(0, 255);
  }

  return pixels;
}

List<int> _getPixel(Uint8List pixels, int x, int y, int width) {
  final base = (y * width + x) * 4;
  return [pixels[base], pixels[base + 1], pixels[base + 2]];
}

double _colorDistance(List<int> a, List<int> b) {
  final dr = (a[0] - b[0]).toDouble();
  final dg = (a[1] - b[1]).toDouble();
  final db = (a[2] - b[2]).toDouble();
  return math.sqrt(dr * dr + dg * dg + db * db);
}

double _colorDistList(List<int> a, List<double> b) {
  final dr = a[0] - b[0];
  final dg = a[1] - b[1];
  final db = a[2] - b[2];
  return dr * dr + dg * dg + db * db;
}
