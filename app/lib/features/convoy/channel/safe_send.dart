import 'package:flutter/foundation.dart';

/// Runs a network send so a dropped socket never becomes an unhandled
/// asynchronous error. Failures are logged and swallowed; the transports
/// retry on their own cadence (docs/10 §3: broadcast is best-effort).
/// Returns true when the send completed.
Future<bool> safeSend(String what, Future<void> Function() send) async {
  try {
    await send();
    return true;
  } catch (e) {
    debugPrint('$what failed: $e');
    return false;
  }
}
