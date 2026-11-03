import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Renders round initials pins for the friends map and caches them by key.
class MarkerIconCache {
  final Map<String, Future<BitmapDescriptor>> _cache = {};

  Future<BitmapDescriptor> get({
    required String key,
    required String initials,
    required Color fill,
    required Color ring,
    required double devicePixelRatio,
    bool stale = false,
  }) => _cache.putIfAbsent(
    key,
    () => renderInitialsPin(
      initials: initials,
      fill: fill,
      ring: ring,
      devicePixelRatio: devicePixelRatio,
      stale: stale,
    ),
  );
}

/// A 44 dp circle with two letters, a white border, and a coloured ring for
/// drivers. Drawn once per distinct look.
Future<BitmapDescriptor> renderInitialsPin({
  required String initials,
  required Color fill,
  required Color ring,
  required double devicePixelRatio,
  bool stale = false,
  double sizeDp = 44,
}) async {
  final size = sizeDp * devicePixelRatio;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final center = Offset(size / 2, size / 2);
  final radius = size / 2 - 2 * devicePixelRatio;

  canvas.drawCircle(
    center,
    radius,
    Paint()..color = Colors.black.withValues(alpha: 0.25),
  );
  canvas.drawCircle(
    center,
    radius - 1 * devicePixelRatio,
    Paint()..color = ring,
  );
  canvas.drawCircle(
    center,
    radius - 4 * devicePixelRatio,
    Paint()..color = Colors.white,
  );
  canvas.drawCircle(
    center,
    radius - 6 * devicePixelRatio,
    Paint()..color = stale ? fill.withValues(alpha: 0.45) : fill,
  );

  final painter = TextPainter(
    text: TextSpan(
      text: initials,
      style: TextStyle(
        color: Colors.white,
        fontSize: 16 * devicePixelRatio,
        fontWeight: FontWeight.w700,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));

  final image = await recorder.endRecording().toImage(size.ceil(), size.ceil());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return BitmapDescriptor.bytes(
    bytes!.buffer.asUint8List(),
    imagePixelRatio: devicePixelRatio,
  );
}
