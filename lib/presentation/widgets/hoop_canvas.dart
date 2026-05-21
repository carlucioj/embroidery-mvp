import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/models/embroidery_design.dart';
import '../../domain/models/embroidery_parameters.dart';

typedef DesignPositionChanged = void Function(Offset offsetMm);
typedef DesignSizeChanged = void Function(double widthMm, double heightMm);

/// Interactive canvas showing the hoop "ghost" with the embroidery design inside.
///
/// The hoop is drawn as a fixed frame (ellipse or rounded rectangle based on
/// [HoopSize.isRound]). The design area can be dragged and resized by the user
/// within the hoop bounds using corner handles.
class HoopCanvas extends StatefulWidget {
  const HoopCanvas({
    super.key,
    required this.parameters,
    this.design,
    this.selectedColorIndex,
    this.onPositionChanged,
    this.onSizeChanged,
  });

  final EmbroideryParameters parameters;
  final EmbroideryDesign? design;
  final int? selectedColorIndex;
  final DesignPositionChanged? onPositionChanged;
  final DesignSizeChanged? onSizeChanged;

  @override
  State<HoopCanvas> createState() => _HoopCanvasState();
}

class _HoopCanvasState extends State<HoopCanvas> {
  // Design position in mm from hoop top-left corner
  late Offset _designOffsetMm;

  // Current design dimensions in mm
  late double _designWidthMm;
  late double _designHeightMm;

  // Drag state
  bool _isDragging = false;
  Offset _gestureStart = Offset.zero;
  Offset _offsetAtGestureStart = Offset.zero;
  double _widthAtGestureStart = 0;
  double _heightAtGestureStart = 0;
  _ResizeHandle? _activeHandle;

  static const double _handleRadius = 7.0;
  static const double _padding = 28.0;
  static const double _minDesignMm = 10.0;

  @override
  void initState() {
    super.initState();
    _syncFromParameters();
  }

  @override
  void didUpdateWidget(HoopCanvas old) {
    super.didUpdateWidget(old);
    if (old.parameters.hoop != widget.parameters.hoop) {
      _syncFromParameters();
    }
  }

  void _syncFromParameters() {
    _designWidthMm = widget.parameters.designWidthMm;
    _designHeightMm = widget.parameters.designHeightMm;
    final hoop = widget.parameters.hoop;
    _designOffsetMm = Offset(
      ((hoop.widthMm - _designWidthMm) / 2).clamp(0, hoop.widthMm),
      ((hoop.heightMm - _designHeightMm) / 2).clamp(0, hoop.heightMm),
    );
  }

  // Returns (scale px/mm, hoop top-left in canvas pixels)
  (double, Offset) _layout(Size canvasSize) {
    final availW = canvasSize.width - _padding * 2;
    final availH = canvasSize.height - _padding * 2;
    final hoop = widget.parameters.hoop;
    final scale = math.min(availW / hoop.widthMm, availH / hoop.heightMm);
    final pxW = hoop.widthMm * scale;
    final pxH = hoop.heightMm * scale;
    final origin = Offset(
      (canvasSize.width - pxW) / 2,
      (canvasSize.height - pxH) / 2,
    );
    return (scale, origin);
  }

  void _clampOffset(double scale) {
    final hoop = widget.parameters.hoop;
    _designOffsetMm = Offset(
      _designOffsetMm.dx.clamp(0.0, math.max(0.0, hoop.widthMm - _designWidthMm)),
      _designOffsetMm.dy.clamp(0.0, math.max(0.0, hoop.heightMm - _designHeightMm)),
    );
  }

  // Returns which resize handle the pointer hit, or null if none.
  _ResizeHandle? _hitHandle(Offset pos, double scale, Offset origin) {
    final dxPx = _designOffsetMm.dx * scale;
    final dyPx = _designOffsetMm.dy * scale;
    final wPx = _designWidthMm * scale;
    final hPx = _designHeightMm * scale;
    final corners = {
      _ResizeHandle.topLeft: origin + Offset(dxPx, dyPx),
      _ResizeHandle.topRight: origin + Offset(dxPx + wPx, dyPx),
      _ResizeHandle.bottomLeft: origin + Offset(dxPx, dyPx + hPx),
      _ResizeHandle.bottomRight: origin + Offset(dxPx + wPx, dyPx + hPx),
    };
    for (final e in corners.entries) {
      if ((pos - e.value).distance <= _handleRadius + 6) return e.key;
    }
    return null;
  }

  bool _hitDesign(Offset pos, double scale, Offset origin) {
    final rect = Rect.fromLTWH(
      origin.dx + _designOffsetMm.dx * scale,
      origin.dy + _designOffsetMm.dy * scale,
      _designWidthMm * scale,
      _designHeightMm * scale,
    );
    return rect.contains(pos);
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final surface = Theme.of(context).colorScheme.surface;

    return LayoutBuilder(builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      final (scale, origin) = _layout(size);

      return GestureDetector(
        onPanStart: (d) {
          final pos = d.localPosition;
          final handle = _hitHandle(pos, scale, origin);
          if (handle != null) {
            _activeHandle = handle;
            _gestureStart = pos;
            _offsetAtGestureStart = _designOffsetMm;
            _widthAtGestureStart = _designWidthMm;
            _heightAtGestureStart = _designHeightMm;
          } else if (_hitDesign(pos, scale, origin)) {
            _isDragging = true;
            _gestureStart = pos;
            _offsetAtGestureStart = _designOffsetMm;
          }
        },
        onPanUpdate: (d) {
          final deltaMm = (d.localPosition - _gestureStart) / scale;
          final hoop = widget.parameters.hoop;

          if (_activeHandle != null) {
            setState(() {
              switch (_activeHandle!) {
                case _ResizeHandle.bottomRight:
                  _designWidthMm =
                      (_widthAtGestureStart + deltaMm.dx).clamp(_minDesignMm, hoop.widthMm);
                  _designHeightMm =
                      (_heightAtGestureStart + deltaMm.dy).clamp(_minDesignMm, hoop.heightMm);
                case _ResizeHandle.bottomLeft:
                  final newW =
                      (_widthAtGestureStart - deltaMm.dx).clamp(_minDesignMm, hoop.widthMm);
                  _designOffsetMm =
                      _offsetAtGestureStart.translate(_widthAtGestureStart - newW, 0);
                  _designWidthMm = newW;
                  _designHeightMm =
                      (_heightAtGestureStart + deltaMm.dy).clamp(_minDesignMm, hoop.heightMm);
                case _ResizeHandle.topRight:
                  final newH =
                      (_heightAtGestureStart - deltaMm.dy).clamp(_minDesignMm, hoop.heightMm);
                  _designOffsetMm =
                      _offsetAtGestureStart.translate(0, _heightAtGestureStart - newH);
                  _designWidthMm =
                      (_widthAtGestureStart + deltaMm.dx).clamp(_minDesignMm, hoop.widthMm);
                  _designHeightMm = newH;
                case _ResizeHandle.topLeft:
                  final newW =
                      (_widthAtGestureStart - deltaMm.dx).clamp(_minDesignMm, hoop.widthMm);
                  final newH =
                      (_heightAtGestureStart - deltaMm.dy).clamp(_minDesignMm, hoop.heightMm);
                  _designOffsetMm = _offsetAtGestureStart.translate(
                    _widthAtGestureStart - newW,
                    _heightAtGestureStart - newH,
                  );
                  _designWidthMm = newW;
                  _designHeightMm = newH;
              }
              _clampOffset(scale);
            });
          } else if (_isDragging) {
            setState(() {
              _designOffsetMm = _offsetAtGestureStart + deltaMm;
              _clampOffset(scale);
            });
          }
        },
        onPanEnd: (_) {
          if (_activeHandle != null) {
            widget.onSizeChanged?.call(_designWidthMm, _designHeightMm);
            _activeHandle = null;
          } else if (_isDragging) {
            widget.onPositionChanged?.call(_designOffsetMm);
            _isDragging = false;
          }
        },
        child: CustomPaint(
          painter: _HoopPainter(
            parameters: widget.parameters,
            design: widget.design,
            selectedColorIndex: widget.selectedColorIndex,
            designOffsetMm: _designOffsetMm,
            designWidthMm: _designWidthMm,
            designHeightMm: _designHeightMm,
            scale: scale,
            hoopOrigin: origin,
            handleRadius: _handleRadius,
            primaryColor: primary,
            surfaceColor: surface,
            isDragging: _isDragging || _activeHandle != null,
          ),
          child: const SizedBox.expand(),
        ),
      );
    });
  }
}

enum _ResizeHandle { topLeft, topRight, bottomLeft, bottomRight }

// ── Painter ─────────────────────────────────────────────────────────────────

class _HoopPainter extends CustomPainter {
  const _HoopPainter({
    required this.parameters,
    required this.design,
    required this.selectedColorIndex,
    required this.designOffsetMm,
    required this.designWidthMm,
    required this.designHeightMm,
    required this.scale,
    required this.hoopOrigin,
    required this.handleRadius,
    required this.primaryColor,
    required this.surfaceColor,
    required this.isDragging,
  });

  final EmbroideryParameters parameters;
  final EmbroideryDesign? design;
  final int? selectedColorIndex;
  final Offset designOffsetMm;
  final double designWidthMm;
  final double designHeightMm;
  final double scale;
  final Offset hoopOrigin;
  final double handleRadius;
  final Color primaryColor;
  final Color surfaceColor;
  final bool isDragging;

  @override
  void paint(Canvas canvas, Size size) {
    final hoop = parameters.hoop;
    final hoopRect = Rect.fromLTWH(
      hoopOrigin.dx,
      hoopOrigin.dy,
      hoop.widthMm * scale,
      hoop.heightMm * scale,
    );

    _paintBackground(canvas, size, hoopRect);
    _paintHoopFrame(canvas, hoopRect);
    _paintDesign(canvas, hoopRect);
    _paintDesignBorder(canvas);
    _paintHandles(canvas);
    _paintLabels(canvas, hoopRect);
  }

  void _paintBackground(Canvas canvas, Size size, Rect hoopRect) {
    // Dim everything outside the hoop
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.black.withValues(alpha: 0.18),
    );

    // Fabric-colored interior (cream/linen)
    final fabricPaint = Paint()..color = const Color(0xFFF2EDD7);
    if (parameters.hoop.isRound) {
      canvas.drawOval(hoopRect, fabricPaint);
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(hoopRect, const Radius.circular(6)),
        fabricPaint,
      );
    }

    // Subtle grid inside hoop
    final gridPaint = Paint()
      ..color = Colors.brown.withValues(alpha: 0.07)
      ..strokeWidth = 0.5;
    canvas.save();
    _clipHoop(canvas, hoopRect);
    const step = 18.0;
    for (var x = hoopRect.left; x <= hoopRect.right; x += step) {
      canvas.drawLine(Offset(x, hoopRect.top), Offset(x, hoopRect.bottom), gridPaint);
    }
    for (var y = hoopRect.top; y <= hoopRect.bottom; y += step) {
      canvas.drawLine(Offset(hoopRect.left, y), Offset(hoopRect.right, y), gridPaint);
    }
    canvas.restore();
  }

  void _paintHoopFrame(Canvas canvas, Rect hoopRect) {
    // Outer metal/wood ring
    final framePaint = Paint()
      ..color = const Color(0xFF8B6F2E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7;
    final innerShadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    if (parameters.hoop.isRound) {
      canvas.drawOval(hoopRect.inflate(3.5), framePaint);
      canvas.drawOval(hoopRect, innerShadow);
    } else {
      final rr = RRect.fromRectAndRadius(hoopRect, const Radius.circular(6));
      final rrOuter = RRect.fromRectAndRadius(hoopRect.inflate(3.5), const Radius.circular(8));
      canvas.drawRRect(rrOuter, framePaint);
      canvas.drawRRect(rr, innerShadow);
    }
  }

  void _paintDesign(Canvas canvas, Rect hoopRect) {
    final designRect = _designRect();

    canvas.save();
    _clipHoop(canvas, hoopRect);

    if (design != null && design!.stitchPaths.isNotEmpty) {
      _paintStitchPaths(canvas, designRect);
    } else {
      // Placeholder when no design generated yet
      final placeholderPaint = Paint()
        ..color = primaryColor.withValues(alpha: 0.08)
        ..style = PaintingStyle.fill;
      canvas.drawRect(designRect, placeholderPaint);
    }

    canvas.restore();
  }

  void _paintStitchPaths(Canvas canvas, Rect designRect) {
    if (design == null || design!.stitchPaths.isEmpty) return;

    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    for (final sp in design!.stitchPaths) {
      for (int i = 0; i < sp.points.length - 1; i += 2) {
        final x = sp.points[i], y = sp.points[i + 1];
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
      }
    }

    final rX = maxX - minX, rY = maxY - minY;
    if (rX == 0 || rY == 0) return;

    final sX = designRect.width / rX;
    final sY = designRect.height / rY;
    final s = math.min(sX, sY);
    final ox = designRect.left + (designRect.width - rX * s) / 2;
    final oy = designRect.top + (designRect.height - rY * s) / 2;

    for (final sp in design!.stitchPaths) {
      final ci = sp.colorIndex;
      final color = ci < design!.colors.length
          ? Color(design!.colors[ci].argb | 0xFF000000)
          : Colors.grey;

      final isSelected = selectedColorIndex == null || selectedColorIndex == ci;
      final paint = Paint()
        ..color = color.withValues(alpha: isSelected ? 1.0 : 0.18)
        ..strokeWidth = isSelected ? 1.3 : 0.8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      if (sp.points.length < 4) continue;

      final path = Path()
        ..moveTo(
          (sp.points[0] - minX) * s + ox,
          (sp.points[1] - minY) * s + oy,
        );
      for (int i = 2; i < sp.points.length - 1; i += 2) {
        path.lineTo(
          (sp.points[i] - minX) * s + ox,
          (sp.points[i + 1] - minY) * s + oy,
        );
      }
      canvas.drawPath(path, paint);
    }
  }

  void _paintDesignBorder(Canvas canvas) {
    final rect = _designRect();
    _drawDashedRect(
      canvas,
      rect,
      primaryColor.withValues(alpha: isDragging ? 1.0 : 0.65),
      strokeWidth: isDragging ? 2.0 : 1.5,
    );

    // Size label inside top-left
    _drawText(
      canvas,
      '${designWidthMm.toStringAsFixed(0)}×${designHeightMm.toStringAsFixed(0)} mm',
      rect.topLeft + const Offset(4, 4),
      color: primaryColor,
      fontSize: 9,
      bold: true,
      background: surfaceColor.withValues(alpha: 0.75),
    );
  }

  void _paintHandles(Canvas canvas) {
    final rect = _designRect();
    final corners = [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ];
    final fill = Paint()..color = surfaceColor;
    final border = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    for (final c in corners) {
      final r = Rect.fromCenter(center: c, width: handleRadius * 2, height: handleRadius * 2);
      canvas.drawRect(r, fill);
      canvas.drawRect(r, border);
    }
  }

  void _paintLabels(Canvas canvas, Rect hoopRect) {
    final hoop = parameters.hoop;

    // Width below hoop
    _drawText(
      canvas,
      '${hoop.widthMm.toStringAsFixed(0)} mm',
      Offset(hoopRect.center.dx - 18, hoopRect.bottom + 6),
      color: Colors.grey.shade600,
      fontSize: 9,
    );

    // Height to the right of hoop
    _drawText(
      canvas,
      '${hoop.heightMm.toStringAsFixed(0)} mm',
      Offset(hoopRect.right + 6, hoopRect.center.dy - 5),
      color: Colors.grey.shade600,
      fontSize: 9,
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Rect _designRect() => Rect.fromLTWH(
        hoopOrigin.dx + designOffsetMm.dx * scale,
        hoopOrigin.dy + designOffsetMm.dy * scale,
        designWidthMm * scale,
        designHeightMm * scale,
      );

  void _clipHoop(Canvas canvas, Rect hoopRect) {
    if (parameters.hoop.isRound) {
      canvas.clipRect(hoopRect);
    } else {
      canvas.clipRRect(RRect.fromRectAndRadius(hoopRect, const Radius.circular(6)));
    }
  }

  void _drawDashedRect(Canvas canvas, Rect rect, Color color,
      {double strokeWidth = 1.5}) {
    const dashLen = 5.0;
    const gapLen = 3.5;
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    void dashedLine(Offset a, Offset b) {
      final dir = b - a;
      final len = dir.distance;
      final unit = dir / len;
      var dist = 0.0;
      var draw = true;
      while (dist < len) {
        final seg = math.min(draw ? dashLen : gapLen, len - dist);
        if (draw) {
          canvas.drawLine(a + unit * dist, a + unit * (dist + seg), paint);
        }
        dist += seg;
        draw = !draw;
      }
    }

    dashedLine(rect.topLeft, rect.topRight);
    dashedLine(rect.topRight, rect.bottomRight);
    dashedLine(rect.bottomRight, rect.bottomLeft);
    dashedLine(rect.bottomLeft, rect.topLeft);
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset position, {
    required Color color,
    required double fontSize,
    bool bold = false,
    Color? background,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          backgroundColor: background,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, position);
  }

  @override
  bool shouldRepaint(_HoopPainter old) => true;
}
