import 'dart:convert';

/// Quiet hours (docs/01 §4.10): everything but crash alerts waits. Stored in
/// `Settings` under [settingsKey] as JSON. Times are minutes after local
/// midnight; a range that ends before it starts spans midnight.
class QuietHours {
  const QuietHours({
    this.enabled = false,
    this.startMinutes = 22 * 60,
    this.endMinutes = 7 * 60,
  });

  factory QuietHours.fromJson(String? json) {
    if (json == null || json.isEmpty) return const QuietHours();
    try {
      final m = jsonDecode(json) as Map<String, dynamic>;
      return QuietHours(
        enabled: m['enabled'] as bool? ?? false,
        startMinutes: (m['start'] as num?)?.toInt() ?? 22 * 60,
        endMinutes: (m['end'] as num?)?.toInt() ?? 7 * 60,
      );
    } catch (_) {
      return const QuietHours();
    }
  }

  static const String settingsKey = 'quiet_hours';

  final bool enabled;
  final int startMinutes;
  final int endMinutes;

  String toJson() => jsonEncode({
    'enabled': enabled,
    'start': startMinutes,
    'end': endMinutes,
  });

  QuietHours copyWith({bool? enabled, int? startMinutes, int? endMinutes}) =>
      QuietHours(
        enabled: enabled ?? this.enabled,
        startMinutes: startMinutes ?? this.startMinutes,
        endMinutes: endMinutes ?? this.endMinutes,
      );

  /// True when [local] falls inside the quiet window.
  bool isQuiet(DateTime local) {
    if (!enabled || startMinutes == endMinutes) return false;
    final m = local.hour * 60 + local.minute;
    if (startMinutes < endMinutes) {
      return m >= startMinutes && m < endMinutes;
    }
    // Spans midnight, e.g. 22:00 → 07:00.
    return m >= startMinutes || m < endMinutes;
  }

  static String formatMinutes(int minutes) {
    final h = (minutes ~/ 60) % 24;
    final m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }
}
