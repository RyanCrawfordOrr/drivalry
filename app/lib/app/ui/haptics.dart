import 'package:flutter/services.dart';

/// Haptic vocabulary (docs/12 §5). Light on taps that change state, medium
/// when a trip scores, heavy when a badge or promotion lands, warning when the
/// crash countdown starts. Fire-and-forget; the platform may ignore them.
abstract final class Haptics {
  /// Tests and the store-art renderer switch this off.
  static bool enabled = true;

  static void tap() => _run(HapticFeedback.lightImpact);
  static void select() => _run(HapticFeedback.selectionClick);
  static void success() => _run(HapticFeedback.mediumImpact);
  static void celebrate() => _run(HapticFeedback.heavyImpact);
  static void warning() => _run(HapticFeedback.vibrate);

  static void _run(Future<void> Function() f) {
    if (!enabled) return;
    f().catchError((Object _) {});
  }
}
