import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/crash/crash_monitor.dart';
import '../../data/db/database.dart';
import '../../data/diagnostics/battery_stats.dart';
import '../../data/diagnostics/detection_counters.dart';
import '../convoy/radio/radio_stats.dart';
import '../../tracking/providers.dart';
import '../../tracking/tracking_controller.dart';
import '../../tracking/tracking_models.dart';
import '../../widgets/friendly_error.dart';

/// Settings › Diagnostics (docs/06 M1.5): what the plugin has seen, what is
/// in the database, which packs are installed. Nothing here leaves the phone
/// unless the user copies it.
class DiagnosticsScreen extends ConsumerStatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  ConsumerState<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends ConsumerState<DiagnosticsScreen> {
  late Future<_Report> _report = _load();

  Future<_Report> _load() async {
    final port = ref.read(trackingPortProvider);
    final db = ref.read(databaseProvider);
    final now = DateTime.now().millisecondsSinceEpoch;
    final diagnostics = await port.getDiagnostics();
    return _Report(
      state: await port.getState(),
      diagnostics: diagnostics,
      battery: await BatteryStats.load(db, now),
      detection: await DetectionCounters.load(db, diagnostics, now),
      counts: await db.tableCounts(),
      packs: await db.installedPacks(),
      crashLastCandidateAt: int.tryParse(
        await db.getSetting(CrashKeys.lastCandidateAt) ?? '',
      ),
      crashFalsePositives: await db.settingInt(CrashKeys.falsePositives),
      crashUnresolved: await db.getSetting(CrashKeys.unresolved) != null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(trackingControllerProvider);
    final relayed = ref.watch(totalRelayedBytesProvider).value ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _report = _load()),
          ),
        ],
      ),
      body: FutureBuilder<_Report>(
        future: _report,
        builder: (context, snap) {
          if (!snap.hasData) {
            if (snap.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    friendlyError(snap.error!, doing: 'read the numbers'),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return const Center(child: CircularProgressIndicator());
          }
          final r = snap.data!;
          final rows = <(String, String)>[
            ('Tracking available', '${r.state.pluginAvailable}'),
            ('Phase', r.state.phase.name),
            ('Enabled', '${r.state.enabled}'),
            (
              'Paused until',
              _ms(r.state.pausedUntil == 0 ? null : r.state.pausedUntil),
            ),
            (
              'Location',
              '${r.state.permissions.location.name}'
                  '${r.state.permissions.preciseLocation ? ', precise' : ', approximate'}',
            ),
            ('Motion', r.state.permissions.motion.name),
            ('Notifications', r.state.permissions.notifications.name),
            ('Bluetooth', r.state.permissions.bluetooth.name),
            ('Events waiting', '${r.state.spooledEvents}'),
            ('Service running', '${r.diagnostics.serviceRunning}'),
            (
              'Battery',
              r.diagnostics.batteryLevel == null
                  ? '–'
                  : '${(r.diagnostics.batteryLevel! * 100).round()}%',
            ),
            (
              'Last trigger',
              '${r.diagnostics.lastTriggerKind ?? '–'} ${_ms(r.diagnostics.lastTriggerAt)}',
            ),
            ('Tentative starts', '${r.diagnostics.tentativeStarts}'),
            ('Confirmed trips', '${r.diagnostics.confirmedTrips}'),
            ('Discarded tentatives', '${r.diagnostics.discardedTentatives}'),
            (
              'Last trip ended',
              '${r.diagnostics.lastTripEndReason ?? '–'} ${_ms(r.diagnostics.lastTripEndedAt)}',
            ),
            for (final (k, v) in batteryRows(r.battery)) (k, v),
            for (final (k, v) in detectionRows(r.detection)) (k, v),
            ('Radio: relayed data', _bytes(relayed)),
            ('Crash: last check', _ms(r.crashLastCandidateAt)),
            ('Crash: false alarms dismissed', '${r.crashFalsePositives}'),
            ('Crash: alert still open', '${r.crashUnresolved}'),
            ('App started', '${ui.booted}'),
            ('Live trip', ui.live == null ? '–' : '${ui.live!.fixCount} fixes'),
            if (ui.error != null) ('Error', ui.error!),
            for (final e in ui.recentErrors.reversed)
              ('Plugin ${e.code}', '${e.message} ${_ms(e.t)}'),
            for (final e in r.counts.entries)
              ('Stored ${e.key}', '${e.value}'),
            for (final p in r.packs)
              ('Pack ${p.region}', '${p.name}, OSM ${p.osmTimestamp}'),
          ];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final (k, v) in rows)
                ListTile(
                  dense: true,
                  title: Text(k),
                  trailing: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 200),
                    child: Text(
                      v,
                      textAlign: TextAlign.end,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () async {
                  final text = const JsonEncoder.withIndent('  ').convert({
                    'state': r.state.permissions.toMap()
                      ..addAll({
                        'phase': r.state.phase.name,
                        'enabled': r.state.enabled,
                      }),
                    'diagnostics': r.diagnostics.toMap(),
                    'counts': r.counts,
                    'packs': [
                      for (final p in r.packs) '${p.region} ${p.osmTimestamp}',
                    ],
                    'dart': {'booted': ui.booted, 'error': ui.error},
                    'battery': {
                      for (final (k, v) in batteryRows(r.battery)) k: v,
                    },
                    'detection': {
                      for (final (k, v) in detectionRows(r.detection)) k: v,
                    },
                    'radioRelayedBytes': relayed,
                    'crash': {
                      'lastCandidateAt': r.crashLastCandidateAt,
                      'falsePositives': r.crashFalsePositives,
                      'unresolved': r.crashUnresolved,
                    },
                    'pluginErrors': [
                      for (final e in ui.recentErrors)
                        '${e.t} ${e.code}: ${e.message}',
                    ],
                  });
                  await Clipboard.setData(ClipboardData(text: text));
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('Copied')));
                  }
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copy for a bug report'),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _ms(int? ms) => ms == null
      ? ''
      : DateFormat.yMd().add_jm().format(
          DateTime.fromMillisecondsSinceEpoch(ms),
        );

  static String _bytes(int b) => b < 1024
      ? '$b B'
      : b < 1024 * 1024
      ? '${(b / 1024).toStringAsFixed(1)} KB'
      : '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Battery rows for the list and the copied report: honest about how much
/// evidence sits behind each rate (docs/06 M1.5).
List<(String, String)> batteryRows(BatteryStats b) => [
  (
    'Battery: per hour driving (14 d)',
    b.drivingPctPerHour == null
        ? 'not enough data yet (${b.drivingPairs} trips, '
              '${b.drivingHours.toStringAsFixed(1)} h)'
        : '${b.drivingPctPerHour!.toStringAsFixed(1)}%/h over '
              '${b.drivingPairs} trips',
  ),
  (
    'Battery: per day parked (14 d)',
    b.parkedPctPerDay == null
        ? 'not enough data yet (${b.parkedDays.toStringAsFixed(1)} days)'
        : '${b.parkedPctPerDay!.toStringAsFixed(1)}%/day over '
              '${b.parkedDays.toStringAsFixed(1)} days',
  ),
];

/// Detection rows. A missed start leaves nothing on the phone, so it is
/// reported as not countable with the nearest proxy beside it.
List<(String, String)> detectionRows(DetectionCounters d) => [
  ('Trips recorded (14 d)', '${d.trips}'),
  ('Missed starts', 'n/a: a missed start leaves nothing to count'),
  (
    'Trips started by hand (14 d)',
    '${d.manualStarts} (closest stand-in for missed)',
  ),
  (
    'False starts',
    '${d.discardedTentativesSinceInstall} dropped before they became trips; '
        '${d.deletedTrips} deleted by you (14 d)',
  ),
  (
    'Late starts (14 d)',
    d.lateStartsCountable == 0
        ? 'n/a: no trips with a stored trigger time yet'
        : '${d.lateStarts} of ${d.lateStartsCountable} confirmed over '
              '2 min after the trigger',
  ),
  (
    'Late ends (14 d)',
    d.lateEndsCountable == 0
        ? 'n/a: no stationary-ended trips with samples'
        : '${d.lateEnds} of ${d.lateEndsCountable} ended over a minute '
              'after the 3-min rule',
  ),
];

class _Report {
  const _Report({
    required this.state,
    required this.diagnostics,
    required this.battery,
    required this.detection,
    required this.counts,
    required this.packs,
    required this.crashLastCandidateAt,
    required this.crashFalsePositives,
    required this.crashUnresolved,
  });
  final TrackingState state;
  final TrackingDiagnostics diagnostics;
  final BatteryStats battery;
  final DetectionCounters detection;
  final Map<String, int> counts;
  final List<Pack> packs;
  final int? crashLastCandidateAt;
  final int crashFalsePositives;
  final bool crashUnresolved;
}
