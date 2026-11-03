import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../data/db/database.dart' show ConvoyTrack;

/// Colours for up to six cars, in member order.
const List<Color> trackColors = [
  Color(0xFF1E88E5),
  Color(0xFFE53935),
  Color(0xFF43A047),
  Color(0xFFFB8C00),
  Color(0xFF8E24AA),
  Color(0xFF00ACC1),
];

/// Draws every car's received track on a plain canvas, revealed in time
/// order up to [progress] (0..1). Works without a Maps key and in tests.
class RecapPlayback extends StatelessWidget {
  const RecapPlayback({
    super.key,
    required this.tracks,
    required this.progress,
    this.order = const [],
  });

  /// userId → points sorted by time.
  final Map<String, List<ConvoyTrack>> tracks;
  final double progress;

  /// Member order, to keep colours stable; unknown ids follow.
  final List<String> order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomPaint(
      painter: _TrackPainter(
        tracks: tracks,
        progress: progress.clamp(0, 1),
        order: order,
        background: theme.colorScheme.surfaceContainerHighest,
        grid: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _TrackPainter extends CustomPainter {
  _TrackPainter({
    required this.tracks,
    required this.progress,
    required this.order,
    required this.background,
    required this.grid,
  });

  final Map<String, List<ConvoyTrack>> tracks;
  final double progress;
  final List<String> order;
  final Color background;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final x = size.width * i / 4;
      final y = size.height * i / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    final all = tracks.values.expand((l) => l).toList();
    if (all.isEmpty) return;
    var minLat = all.first.lat, maxLat = all.first.lat;
    var minLon = all.first.lon, maxLon = all.first.lon;
    var minT = all.first.t, maxT = all.first.t;
    for (final p in all) {
      minLat = math.min(minLat, p.lat);
      maxLat = math.max(maxLat, p.lat);
      minLon = math.min(minLon, p.lon);
      maxLon = math.max(maxLon, p.lon);
      minT = math.min(minT, p.t);
      maxT = math.max(maxT, p.t);
    }
    // Equal-ish scale: shrink longitude by cos(lat) so shapes look right.
    final cosLat = math.cos((minLat + maxLat) / 2 * math.pi / 180);
    final spanLat = math.max(maxLat - minLat, 1e-4);
    final spanLon = math.max((maxLon - minLon) * cosLat, 1e-4);
    const pad = 16.0;
    final scale = math.min(
      (size.width - 2 * pad) / spanLon,
      (size.height - 2 * pad) / spanLat,
    );
    final drawW = spanLon * scale;
    final drawH = spanLat * scale;
    final ox = (size.width - drawW) / 2;
    final oy = (size.height - drawH) / 2;
    Offset project(ConvoyTrack p) => Offset(
      ox + (p.lon - minLon) * cosLat * scale,
      oy + (maxLat - p.lat) * scale,
    );
    final cutoff = minT + ((maxT - minT) * progress).round();

    final ids = [
      ...order.where(tracks.containsKey),
      ...tracks.keys.where((k) => !order.contains(k)),
    ];
    for (var i = 0; i < ids.length; i++) {
      final pts = tracks[ids[i]]!;
      final color = trackColors[i % trackColors.length];
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final path = Path();
      Offset? last;
      var started = false;
      for (final p in pts) {
        if (p.t > cutoff) break;
        final o = project(p);
        if (!started) {
          path.moveTo(o.dx, o.dy);
          started = true;
        } else {
          path.lineTo(o.dx, o.dy);
        }
        last = o;
      }
      if (started) canvas.drawPath(path, paint);
      if (last != null) {
        canvas.drawCircle(last, 6, Paint()..color = color);
        canvas.drawCircle(
          last,
          6,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TrackPainter old) =>
      old.progress != progress || old.tracks != tracks;
}
