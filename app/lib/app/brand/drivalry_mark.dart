import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme.dart';

/// The Drivalry mark: a road ribbon climbing from bottom-left to top-right
/// with a dashed centre line and a teal destination dot inside the top end.
///
/// One painter renders every size the stores and the OS need (adaptive icon
/// layers, legacy launcher icons, the App Store icon, splash images and the
/// store graphics), so there is a single source of truth for the brand. The
/// geometry is in unit coordinates; [contentScale] says how much of the
/// canvas the artwork may use (adaptive foregrounds keep to the 66 dp safe
/// zone of a 108 dp layer, full-bleed icons use more).
abstract final class DrivalryBrand {
  static const ink = Color(0xFF111726);
  static const inkLight = Color(0xFF1C2537);
  static const orange = DrivalryTheme.seed;
  static const orangeLight = Color(0xFFFF9552);
  static const teal = DrivalryTheme.teal;
  static const paper = Color(0xFFFFF7F0);

  static const backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [inkLight, ink],
  );
}

enum MarkStyle {
  /// Orange ribbon, teal dot. Dashes and the dot's ring are cut through to
  /// whatever is underneath (transparent on a foreground layer).
  colour,

  /// Single white shape for Android's themed icons and the status bar. The
  /// dot becomes a hole.
  monochrome,
}

class DrivalryMarkPainter extends CustomPainter {
  const DrivalryMarkPainter({
    this.style = MarkStyle.colour,
    this.contentScale = 0.86,
    this.background,
    this.backgroundRadiusFraction = 0,
  });

  final MarkStyle style;

  /// Fraction of the canvas the unit square of the artwork occupies.
  final double contentScale;

  /// Paint a background behind the mark: null for a transparent layer.
  final Gradient? background;

  /// Corner radius of the background as a fraction of the canvas size
  /// (0 = square, 0.5 = circle).
  final double backgroundRadiusFraction;

  // Unit-square geometry: a route from a start node to a destination node.
  static const _start = Offset(0.24, 0.78);
  static const _c1 = Offset(0.24, 0.42);
  static const _c2 = Offset(0.76, 0.58);
  static const _end = Offset(0.76, 0.24);
  static const _ribbonWidth = 0.165;
  static const _startNodeRadius = 0.115;
  static const _endNodeRadius = 0.15;
  static const _dashWidth = 0.032;
  static const _dashOn = 0.07;
  static const _dashOff = 0.06;
  static const _dotRadius = 0.058;
  static const _ringWidth = 0.03;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final rect = Offset.zero & size;
    if (background != null) {
      final r = backgroundRadiusFraction * s;
      final paint = Paint()..shader = background!.createShader(rect);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(r)),
        paint,
      );
    }

    final unit = s * contentScale;
    final origin = Offset((size.width - unit) / 2, (size.height - unit) / 2);
    Offset u(Offset p) => origin + Offset(p.dx * unit, p.dy * unit);

    final road = Path()
      ..moveTo(u(_start).dx, u(_start).dy)
      ..cubicTo(
        u(_c1).dx,
        u(_c1).dy,
        u(_c2).dx,
        u(_c2).dy,
        u(_end).dx,
        u(_end).dy,
      );

    final mono = style == MarkStyle.monochrome;
    final ribbonPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _ribbonWidth * unit
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (mono) {
      ribbonPaint.color = Colors.white;
    } else {
      ribbonPaint.shader = ui.Gradient.linear(u(_start), u(_end), const [
        DrivalryBrand.orange,
        DrivalryBrand.orangeLight,
      ]);
    }

    // Everything cut out of the ribbon uses BlendMode.clear inside one layer
    // so the background (or transparency) shows through.
    canvas.saveLayer(rect, Paint());
    canvas.drawPath(road, ribbonPaint);
    final nodePaint = Paint()..shader = ribbonPaint.shader;
    if (mono) nodePaint.color = Colors.white;
    canvas.drawCircle(u(_start), _startNodeRadius * unit, nodePaint);
    canvas.drawCircle(u(_end), _endNodeRadius * unit, nodePaint);

    final clear = Paint()
      ..blendMode = BlendMode.clear
      ..style = PaintingStyle.stroke
      ..strokeWidth = _dashWidth * unit
      ..strokeCap = StrokeCap.round;
    final dashes = _dashed(
      road,
      on: _dashOn * unit,
      off: _dashOff * unit,
      // Start after the start node, stop before the destination node.
      skipStart: (_startNodeRadius + 0.05) * unit,
      skipEnd: (_endNodeRadius + 0.04) * unit,
    );
    canvas.drawPath(dashes, clear);

    // Destination: a ring cut out of the ribbon end, then the teal dot.
    final ringPaint = Paint()
      ..blendMode = BlendMode.clear
      ..style = PaintingStyle.stroke
      ..strokeWidth = _ringWidth * unit;
    canvas.drawCircle(u(_end), (_dotRadius + _ringWidth / 2) * unit, ringPaint);
    if (mono) {
      canvas.drawCircle(
        u(_end),
        _dotRadius * unit,
        Paint()..blendMode = BlendMode.clear,
      );
    }
    canvas.restore();

    if (!mono) {
      canvas.drawCircle(
        u(_end),
        _dotRadius * unit,
        Paint()..color = DrivalryBrand.teal,
      );
    }
  }

  static Path _dashed(
    Path source, {
    required double on,
    required double off,
    required double skipStart,
    required double skipEnd,
  }) {
    final out = Path();
    for (final metric in source.computeMetrics()) {
      var d = skipStart;
      final limit = metric.length - skipEnd;
      while (d + on <= limit) {
        out.addPath(metric.extractPath(d, d + on), Offset.zero);
        d += on + off;
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(DrivalryMarkPainter old) =>
      old.style != style ||
      old.contentScale != contentScale ||
      old.background != background ||
      old.backgroundRadiusFraction != backgroundRadiusFraction;
}

/// The mark as a widget. [size] is the side of the square.
class DrivalryMark extends StatelessWidget {
  const DrivalryMark({
    super.key,
    required this.size,
    this.style = MarkStyle.colour,
    this.contentScale = 0.86,
    this.background,
    this.backgroundRadiusFraction = 0,
  });

  /// The mark on its dark rounded tile, as it appears in the launcher.
  const DrivalryMark.tile({super.key, required this.size})
    : style = MarkStyle.colour,
      contentScale = 0.86,
      background = DrivalryBrand.backgroundGradient,
      backgroundRadiusFraction = 0.22;

  final double size;
  final MarkStyle style;
  final double contentScale;
  final Gradient? background;
  final double backgroundRadiusFraction;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: DrivalryMarkPainter(
          style: style,
          contentScale: contentScale,
          background: background,
          backgroundRadiusFraction: backgroundRadiusFraction,
        ),
      ),
    );
  }
}
