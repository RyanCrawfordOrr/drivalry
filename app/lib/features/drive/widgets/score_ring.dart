import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme.dart';

/// The 0–100 Drive Score as a ring. `score == null` draws an empty ring with
/// a dash, for unscored trips.
class ScoreRing extends StatelessWidget {
  const ScoreRing({
    super.key,
    required this.score,
    this.size = 96,
    this.stroke = 9,
    this.reckless = false,
    this.label,
  });

  final int? score;
  final double size;
  final double stroke;
  final bool reckless;

  /// Small caption under the number (e.g. "+46 XP").
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = score == null
        ? theme.colorScheme.outlineVariant
        : DrivalryTheme.scoreColor(score!);
    final big = size >= 80;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
          fraction: (score ?? 0) / 100,
          color: color,
          track: theme.colorScheme.surfaceContainerHighest,
          stroke: stroke,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                score?.toString() ?? '—',
                style:
                    (big
                            ? theme.textTheme.headlineMedium
                            : theme.textTheme.titleMedium)
                        ?.copyWith(fontWeight: FontWeight.w700, color: color),
              ),
              if (reckless)
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

class _RingPainter extends CustomPainter {
  _RingPainter({
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
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction ||
      old.color != color ||
      old.track != track ||
      old.stroke != stroke;
}
