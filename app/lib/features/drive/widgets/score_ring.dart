import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../app/ui/motion.dart';
import '../../../app/ui/tokens.dart';

/// The 0–100 Drive Score as a ring. `score == null` draws an empty ring with
/// a dash, for unscored trips.
///
/// With [animate] the arc sweeps from zero and the number counts up on first
/// appearance (docs/12 §5b), unless the system asks for reduced motion.
class ScoreRing extends StatelessWidget {
  const ScoreRing({
    super.key,
    required this.score,
    this.size = 96,
    this.stroke = 9,
    this.reckless = false,
    this.label,
    this.animate = false,
  });

  final int? score;
  final double size;
  final double stroke;
  final bool reckless;

  /// Small caption under the number (e.g. "+46 XP").
  final String? label;

  /// Sweep in from zero on first build.
  final bool animate;

  /// Length of the sweep.
  static const sweep = Duration(milliseconds: 600);

  @override
  Widget build(BuildContext context) {
    if (!animate || score == null || context.reduceMotion) {
      return _ring(context, 1);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: sweep,
      curve: Motion.enter,
      builder: (ctx, t, _) => _ring(ctx, t),
    );
  }

  Widget _ring(BuildContext context, double t) {
    final theme = Theme.of(context);
    final color = score == null
        ? theme.colorScheme.outlineVariant
        : DrivalryTheme.scoreColor(score!);
    final big = size >= 80;
    final shown = score == null ? null : (score! * t).round();
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: ScoreRingPainter(
          fraction: (score ?? 0) / 100 * t,
          color: color,
          track: theme.colorScheme.surfaceContainerHighest,
          stroke: stroke,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                shown?.toString() ?? '—',
                style:
                    (big
                            ? theme.textTheme.headlineMedium
                            : theme.textTheme.titleMedium)
                        ?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: color,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
              ),
              if (reckless && big)
                Text(
                  'RECKLESS',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                )
              else if (label != null && big)
                Text(label!, style: theme.textTheme.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}

/// Draws the track and the arc. Public so tests can read [fraction] while the
/// sweep is in flight.
class ScoreRingPainter extends CustomPainter {
  ScoreRingPainter({
    required this.fraction,
    required this.color,
    required this.track,
    required this.stroke,
  });

  final double fraction;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final inset = rect.deflate(stroke / 2);
    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(inset, 0, 2 * math.pi, false, trackPaint);
    if (fraction <= 0) return;
    final arcPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;
    canvas.drawArc(
      inset,
      -math.pi / 2,
      2 * math.pi * fraction.clamp(0, 1),
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(ScoreRingPainter old) =>
      old.fraction != fraction ||
      old.color != color ||
      old.track != track ||
      old.stroke != stroke;
}
