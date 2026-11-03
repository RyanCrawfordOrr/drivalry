import 'package:drift/drift.dart' show StringExpressionOperators;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database.dart';

/// `Settings` keys for spoken cues (docs/01 §4.2: optional, off by default).
abstract final class CueKeys {
  static const enabled = 'cues_enabled';
  static const limit = 'cues_limit';
  static const over = 'cues_over';
  static const smooth = 'cues_smooth';
  static const rate = 'cues_voice_rate';

  /// Every key, for the settings stream filter.
  static const prefix = 'cues_';
}

/// What the driver has opted into. Everything defaults to on except the
/// master switch, which defaults to off.
class CueSettings {
  const CueSettings({
    this.enabled = false,
    this.limit = true,
    this.over = true,
    this.smooth = true,
    this.rate = 0.9,
  });

  /// Master switch.
  final bool enabled;

  /// "Limit's 35" when the posted limit changes.
  final bool limit;

  /// "Over by 8" after eight seconds at least 5 mph over.
  final bool over;

  /// "Smooth" after five clean minutes.
  final bool smooth;

  /// Voice speed as a multiplier of normal (0.6–1.2).
  final double rate;

  static const minRate = 0.6;
  static const maxRate = 1.2;

  static CueSettings fromMap(Map<String, String> m) => CueSettings(
    enabled: m[CueKeys.enabled] == 'true',
    limit: m[CueKeys.limit] != 'false',
    over: m[CueKeys.over] != 'false',
    smooth: m[CueKeys.smooth] != 'false',
    rate: (double.tryParse(m[CueKeys.rate] ?? '') ?? 0.9).clamp(
      minRate,
      maxRate,
    ),
  );

  CueSettings copyWith({
    bool? enabled,
    bool? limit,
    bool? over,
    bool? smooth,
    double? rate,
  }) => CueSettings(
    enabled: enabled ?? this.enabled,
    limit: limit ?? this.limit,
    over: over ?? this.over,
    smooth: smooth ?? this.smooth,
    rate: rate ?? this.rate,
  );
}

/// Live view of the cue settings rows.
final cueSettingsProvider = StreamProvider<CueSettings>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(
    db.settings,
  )..where((s) => s.key.like('${CueKeys.prefix}%'))).watch().map(
    (rows) => CueSettings.fromMap({for (final r in rows) r.key: r.value}),
  );
});

/// Writes one cue setting.
Future<void> setCueSetting(AppDatabase db, String key, String value) =>
    db.setSetting(key, value);
