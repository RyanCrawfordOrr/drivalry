import 'package:flutter/material.dart';

import '../theme.dart';

/// Shared palette for the Good Company identity.
///
/// The same mark is rendered at every launcher, splash and store size by the
/// artwork tests. Semantic score and safety colours remain separate.
abstract final class DrivalryBrand {
  static const ink = DrivalryTheme.ink;
  static const inkLight = DrivalryTheme.ink;
  static const coral = DrivalryTheme.seed;
  static const paper = DrivalryTheme.paper;

  // Kept for existing feature art that uses the previous accent names.
  static const orange = coral;
  static const orangeLight = coral;
  static const teal = DrivalryTheme.teal;

  /// A flat field rather than a gradient; kept as a Gradient for callers that
  /// paint Android launcher backgrounds and rounded brand tiles.
  static const backgroundGradient = LinearGradient(colors: [ink, ink]);
}

enum MarkStyle {
  /// Cream lowercase-d mark with a coral dot.
  colour,

  /// White silhouette with a separate white dot for Android themed icons.
  monochrome,
}

/// A scalable interpretation of the approved lowercase-d identity.
///
/// The geometry is relative to a square so the logo remains consistent on
/// Android, iOS and in store artwork. [contentScale] is used to keep launcher
/// foregrounds inside Android's adaptive-icon safe area.
class DrivalryMarkPainter extends CustomPainter {
  const DrivalryMarkPainter({
    this.style = MarkStyle.colour,
    this.contentScale = 1,
    this.background,
    this.backgroundRadiusFraction = 0,
  });

  final MarkStyle style;
  final double contentScale;
  final Gradient? background;
  final double backgroundRadiusFraction;

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
    Offset u(double x, double y) => origin + Offset(x * unit, y * unit);
    Rect box(double left, double top, double right, double bottom) =>
        Rect.fromPoints(u(left, top), u(right, bottom));

    const cx = 0.50;
    const cy = 0.596;
    final monochrome = style == MarkStyle.monochrome;
    final markPaint = Paint()
      ..color = monochrome ? Colors.white : DrivalryBrand.paper;

    // Clear the counter and opening in an isolated layer, so a transparent
    // adaptive foreground and an opaque app icon use identical geometry.
    canvas.saveLayer(rect, Paint());
    canvas.drawCircle(u(cx, cy), 0.233 * unit, markPaint);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        box(0.596, 0.199, 0.733, 0.596),
        topLeft: Radius.circular(0.052 * unit),
        topRight: Radius.circular(0.052 * unit),
      ),
      markPaint,
    );
    final clear = Paint()..blendMode = BlendMode.clear;
    canvas.drawCircle(u(cx, cy), 0.118 * unit, clear);
    final opening = Path()
      ..moveTo(u(0.60, 0.566).dx, u(0.60, 0.566).dy)
      ..cubicTo(
        u(0.617, 0.570).dx,
        u(0.617, 0.570).dy,
        u(0.618, 0.579).dx,
        u(0.618, 0.579).dy,
        u(0.638, 0.579).dx,
        u(0.638, 0.579).dy,
      )
      ..lineTo(u(0.76, 0.579).dx, u(0.76, 0.579).dy)
      ..lineTo(u(0.76, 0.615).dx, u(0.76, 0.615).dy)
      ..lineTo(u(0.638, 0.615).dx, u(0.638, 0.615).dy)
      ..cubicTo(
        u(0.618, 0.615).dx,
        u(0.618, 0.615).dy,
        u(0.617, 0.625).dx,
        u(0.617, 0.625).dy,
        u(0.60, 0.628).dx,
        u(0.60, 0.628).dy,
      )
      ..lineTo(u(0.50, 0.628).dx, u(0.50, 0.628).dy)
      ..lineTo(u(0.50, 0.566).dx, u(0.50, 0.566).dy)
      ..close();
    canvas.drawPath(opening, clear);
    canvas.restore();

    canvas.drawCircle(
      u(cx, cy),
      0.072 * unit,
      Paint()..color = monochrome ? Colors.white : DrivalryBrand.coral,
    );
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
    this.contentScale = 1,
    this.background,
    this.backgroundRadiusFraction = 0,
  });

  /// The mark on its dark rounded tile, as it appears in the launcher.
  const DrivalryMark.tile({super.key, required this.size})
    : style = MarkStyle.colour,
      contentScale = 1,
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
