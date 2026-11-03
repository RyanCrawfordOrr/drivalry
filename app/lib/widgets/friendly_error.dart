import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Turns any thrown object into one short sentence a person can act on, and
/// logs the detail for Diagnostics. Screens never interpolate `$e` into
/// visible text (docs/12-ux-direction.md §6).
String friendlyError(Object error, {String? doing}) {
  debugPrint('${doing ?? 'operation'} failed: $error');
  final text = error.toString();
  final lower = text.toLowerCase();
  if (error is SocketException ||
      error is HandshakeException ||
      lower.contains('socketexception') ||
      lower.contains('failed host lookup') ||
      lower.contains('network is unreachable') ||
      lower.contains('connection refused') ||
      lower.contains('connection reset')) {
    return 'No connection right now. Try again when you are back online.';
  }
  if (error is TimeoutException || lower.contains('timed out')) {
    return 'That took too long. Try again.';
  }
  if (lower.contains('offline build') || lower.contains('not configured')) {
    return 'Not available in this version yet.';
  }
  if (lower.contains('jwt') ||
      lower.contains('not authenticated') ||
      lower.contains('refresh_token') ||
      lower.contains('invalid token')) {
    return 'Your sign-in expired. Sign in again.';
  }
  if (lower.contains('permission') || lower.contains('row-level security')) {
    return 'You do not have access to that.';
  }
  if (lower.contains('rate limit') || lower.contains('429')) {
    return 'Slow down a little. Try again in a minute.';
  }
  if (doing != null) return 'Could not $doing. Try again.';
  return 'Something went wrong. Try again.';
}
