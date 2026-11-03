import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/crash/crash_monitor.dart';
import '../../data/db/database.dart';
import '../../tracking/providers.dart';
import '../../tracking/tracking_controller.dart';
import '../../tracking/tracking_models.dart';

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
    return _Report(
      state: await port.getState(),
      diagnostics: await port.getDiagnostics(),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _report = _load()),
          ),
        ],
      ),
      body: FutureBuilder<_Report>(
        future: _report,
        builder: (context, snap) {
          if (!snap.hasData) {
            if (snap.hasError) return Center(child: Text('${snap.error}'));
            return const Center(child: CircularProgressIndicator());
          }
          final r = snap.data!;
          final rows = <(String, String)>[
            ('Plugin available', '${r.state.pluginAvailable}'),
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
            ('Spooled events', '${r.state.spooledEvents}'),
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
            ('Crash: last candidate', _ms(r.crashLastCandidateAt)),
            ('Crash: false alarms dismissed', '${r.crashFalsePositives}'),
            ('Crash: unresolved alert', '${r.crashUnresolved}'),
            ('Booted (Dart)', '${ui.booted}'),
            ('Live trip', ui.live == null ? '–' : '${ui.live!.fixCount} fixes'),
            if (ui.error != null) ('Error', ui.error!),
            for (final e in ui.recentErrors.reversed)
              ('Plugin ${e.code}', '${e.message} ${_ms(e.t)}'),
            for (final e in r.counts.entries) ('DB ${e.key}', '${e.value}'),
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
                label: const Text('Copy debug info'),
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
}

class _Report {
  const _Report({
    required this.state,
    required this.diagnostics,
    required this.counts,
    required this.packs,
    required this.crashLastCandidateAt,
    required this.crashFalsePositives,
    required this.crashUnresolved,
  });
  final TrackingState state;
  final TrackingDiagnostics diagnostics;
  final Map<String, int> counts;
  final List<Pack> packs;
  final int? crashLastCandidateAt;
  final int crashFalsePositives;
  final bool crashUnresolved;
}
