import 'package:drift/drift.dart' show Value;
import 'package:drivalry_scoring/drivalry_scoring.dart'
    show EventKind, RoadSegment, SpeedUnits, formatDuration, kmh, mph;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

import '../../app/bootstrap.dart';
import '../../app/theme.dart';
import '../../data/db/database.dart';
import '../../data/models/trip_phase.dart';
import '../../data/models/trip_score_view.dart';
import '../../tracking/providers.dart';
import '../../tracking/tracking_controller.dart';
import '../../widgets/units.dart';
import 'event_text.dart';
import 'widgets/score_ring.dart';
import 'widgets/trip_card.dart';

final _samplesProvider = FutureProvider.family<List<Sample>, String>(
  (ref, id) => ref.watch(databaseProvider).samplesFor(id),
);
final _segmentsProvider = FutureProvider.family<List<RoadSegment>, String>(
  (ref, id) => ref.watch(databaseProvider).segmentsFor(id),
);

/// One trip: map, score, components, events, stats, corrections.
class TripDetailScreen extends ConsumerWidget {
  const TripDetailScreen({super.key, required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripAsync = ref.watch(tripProvider(tripId));
    final trip = tripAsync.value;
    if (trip == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Trip')),
        body: Center(
          child: tripAsync.isLoading
              ? const CircularProgressIndicator()
              : const Text('This trip is gone.'),
        ),
      );
    }
    final t = trip.trip;
    final score = trip.score == null
        ? null
        : TripScoreView.fromJsonString(trip.score!.scoreJson);
    final unitsSetting =
        ref.watch(unitsSettingProvider).value ?? UnitsSetting.auto;
    final units = resolveUnits(unitsSetting, packRegion: t.packRegion);
    final samples =
        ref.watch(_samplesProvider(tripId)).value ?? const <Sample>[];
    final segments =
        ref.watch(_segmentsProvider(tripId)).value ?? const <RoadSegment>[];
    final controller = ref.read(trackingControllerProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(tripDateLabel(t)),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'passenger':
                  await controller.answerPassenger(
                    tripId,
                    t.isPassenger != true,
                  );
                case 'rescore':
                  await controller.rescore(tripId);
                case 'delete':
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Delete this trip?'),
                      content: const Text(
                        'It disappears from your history. Nothing was uploaded.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Keep'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await controller.deleteTrip(tripId);
                    if (context.mounted) context.pop();
                  }
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'passenger',
                child: Text(
                  t.isPassenger == true
                      ? 'I was the driver'
                      : 'Mark as passenger',
                ),
              ),
              const PopupMenuItem(value: 'rescore', child: Text('Re-score')),
              const PopupMenuItem(value: 'delete', child: Text('Delete trip')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          SizedBox(
            height: 260,
            child: _TripMap(
              samples: samples,
              segments: segments,
              score: score,
              units: units,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ScoreRing(
                  score: score != null && score.scored ? score.score : null,
                  size: 112,
                  stroke: 10,
                  reckless: score?.reckless ?? false,
                  label: score != null && score.scored
                      ? '+${score.xp} XP'
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (score != null &&
                          score.scored &&
                          score.roastText != null)
                        Text(
                          score.roastText!,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontStyle: score.headlineIsRoast
                                ? FontStyle.italic
                                : null,
                          ),
                        )
                      else
                        Text(
                          unscoredLabel(t, score),
                          style: theme.textTheme.titleMedium,
                        ),
                      const SizedBox(height: 8),
                      for (final line
                          in score?.lines ?? const <FeedbackLineView>[])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '• ${line.text}',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (score != null && score.scored) ...[
            _SectionTitle('Score breakdown'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  _ComponentBar('Speed discipline', score.penalties.speed, 40),
                  _ComponentBar('Smoothness', score.penalties.smoothness, 30),
                  _ComponentBar('Attention', score.penalties.attention, 30),
                  _ComponentBar('Efficiency', score.penalties.efficiency, 15),
                ],
              ),
            ),
          ],
          _SectionTitle('Stats'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _StatsGrid(trip: t, score: score, units: units),
          ),
          if (score != null &&
              (score.events.isNotEmpty || score.observations.isNotEmpty)) ...[
            _SectionTitle('What happened'),
            for (final (i, e) in score.events.indexed)
              _EventTile(
                event: e,
                units: units,
                counted: true,
                onFlag: e.kind == EventKind.speeding
                    ? () => _flagLimit(context, ref, t, e, segments, units)
                    : null,
                key: ValueKey('event-$i'),
              ),
            for (final (i, e) in score.observations.indexed)
              _EventTile(
                event: e,
                units: units,
                counted: false,
                onFlag: () => _flagLimit(context, ref, t, e, segments, units),
                key: ValueKey('obs-$i'),
              ),
          ],
          if (t.limitCoverage != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(
                t.limitCoverage! > 0
                    ? '${(t.limitCoverage! * 100).round()}% of this drive was on roads with a '
                          'known speed limit (pack ${t.packRegion}, OSM ${_short(t.packVersion)}).'
                    : t.packRegion == null
                    ? 'No speed-limit pack covers this area yet, so speeding was not scored.'
                    : 'No road with a known limit was matched on this drive.',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  static String _short(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    return d == null ? (iso ?? '') : DateFormat.yMMM().format(d);
  }

  Future<void> _flagLimit(
    BuildContext context,
    WidgetRef ref,
    Trip trip,
    TripEventView event,
    List<RoadSegment> segments,
    SpeedUnits units,
  ) async {
    RoadSegment? seg;
    for (final s in segments) {
      if (event.startIdx >= s.fromIdx && event.startIdx <= s.toIdx) {
        seg = s;
        break;
      }
    }
    final wayId = seg?.wayId;
    final segName = seg?.name;
    if (wayId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No road from the pack is attached to this event.'),
        ),
      );
      return;
    }
    final controller = TextEditingController(
      text: event.limitMps == null || event.limitMps!.isNaN
          ? ''
          : formatSpeed(event.limitMps!, units, withUnit: false),
    );
    final posted = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Limit is wrong here',
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'On ${segName ?? 'this road'}. What does the sign say? Your flag '
              'silences this road for you now; two agreeing flags fix it for everyone.',
              style: Theme.of(ctx).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Posted limit (${unitLabel(units)})',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(ctx, int.tryParse(controller.text.trim())),
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (posted == null || posted <= 0) return;
    final mps = units == SpeedUnits.mph ? posted * mph : posted * kmh;
    final db = ref.read(databaseProvider);
    await db.addLimitFlag(
      LimitFlagsCompanion.insert(
        wayId: wayId,
        region: Value(trip.packRegion),
        tripId: Value(trip.id),
        suggestedMps: mps,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    await ref.read(tripFinalizerProvider).finalize(trip.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Thanks. This road is silent for you until the fix is confirmed.',
          ),
        ),
      );
    }
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

class _ComponentBar extends StatelessWidget {
  const _ComponentBar(this.label, this.lost, this.cap);
  final String label;
  final double lost;
  final double cap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kept = (cap - lost).clamp(0, cap);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: kept / cap,
                minHeight: 10,
                color: DrivalryTheme.scoreColor((100 * kept / cap).round()),
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 56,
            child: Text(
              lost < 0.05 ? 'clean' : '−${lost.toStringAsFixed(1)}',
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({
    required this.trip,
    required this.score,
    required this.units,
  });
  final Trip trip;
  final TripScoreView? score;
  final SpeedUnits units;

  @override
  Widget build(BuildContext context) {
    final s = score?.summary;
    final items = <(String, String)>[
      ('Distance', formatDistance(trip.distanceM, units)),
      ('Moving time', formatElapsed(Duration(seconds: trip.movingS.round()))),
      if (s != null) ('Average', formatSpeed(s.avgMovingSpeed, units)),
      if (s != null) ('Top speed', formatSpeed(s.maxSpeed, units)),
      if (s != null && s.secondsOverLimit > 0)
        ('Over the limit', formatDuration(s.secondsOverLimit)),
      if (s != null && s.secondsOverLimit > 0)
        ('Time saved', formatDuration(s.timeSavedBySpeedingS)),
      if (trip.nightFraction != null)
        ('Night', '${(trip.nightFraction! * 100).round()}%'),
      if (trip.weather != null) ('Weather', trip.weather!),
      if (trip.vehicleLabel != null) ('Vehicle', trip.vehicleLabel!),
      if (trip.phase == TripPhase.unscored.wire && trip.isPassenger == true)
        ('Role', 'Passenger'),
    ];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.9,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: [
        for (final (k, v) in items)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  v,
                  style: Theme.of(context).textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(k, style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ),
      ],
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({
    super.key,
    required this.event,
    required this.units,
    required this.counted,
    this.onFlag,
  });

  final TripEventView event;
  final SpeedUnits units;

  /// False for observations: shown, never scored (docs/02 §3).
  final bool counted;
  final VoidCallback? onFlag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = counted
        ? severityColor(event.severity, theme.colorScheme)
        : theme.colorScheme.outline;
    final at = DateFormat.jm().format(
      DateTime.fromMillisecondsSinceEpoch(event.startT),
    );
    return ListTile(
      leading: Icon(eventIcon(event.kind), color: color),
      title: Text(describeEvent(event, units)),
      subtitle: Text(
        counted
            ? '${eventTitle(event.kind)} · ${severityLabel(event.severity)} · $at'
            : 'Observation only: limit not confident · $at',
      ),
      trailing: onFlag == null
          ? null
          : IconButton(
              icon: const Icon(Icons.flag_outlined),
              tooltip: 'Limit is wrong here',
              onPressed: onFlag,
            ),
    );
  }
}

class _TripMap extends ConsumerWidget {
  const _TripMap({
    required this.samples,
    required this.segments,
    required this.score,
    required this.units,
  });

  final List<Sample> samples;
  final List<RoadSegment> segments;
  final TripScoreView? score;
  final SpeedUnits units;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Never build a GoogleMap before the SDK has its key (bootstrap.dart):
    // on iOS that aborts the process. While the key is on its way the
    // placeholder shows, which is also what a build without a key shows.
    final mapsReady = ref.watch(mapsReadyProvider);
    final ready = mapsReady.value == true;
    if (!ready || samples.length < 2) {
      final String message;
      if (samples.length < 2) {
        message = 'No route recorded.';
      } else if (mapsReady.isLoading) {
        message = 'Loading map…';
      } else {
        message =
            'Map unavailable: build with --dart-define-from-file=../.env to show the route.';
      }
      return Container(
        color: theme.colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(16),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
      );
    }
    final polylines = <Polyline>{};
    final known = <LatLng>[];
    final unknown = <LatLng>[];
    var segIdx = 0;
    for (var i = 0; i < samples.length; i++) {
      while (segIdx < segments.length - 1 && i > segments[segIdx].toIdx) {
        segIdx++;
      }
      final seg = segments.isEmpty ? null : segments[segIdx];
      final isKnown =
          seg != null && seg.speedLimit != null && seg.confidence >= 0.7;
      final p = LatLng(samples[i].lat, samples[i].lon);
      (isKnown ? known : unknown).add(p);
      // Keep the lines continuous at boundaries.
      if (isKnown && unknown.isNotEmpty) unknown.add(p);
      if (!isKnown && known.isNotEmpty) known.add(p);
    }
    if (known.length > 1) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('known'),
          points: known,
          color: DrivalryTheme.teal,
          width: 5,
        ),
      );
    }
    if (unknown.length > 1) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('unknown'),
          points: unknown,
          color: theme.colorScheme.outline,
          width: 4,
        ),
      );
    }
    final markers = <Marker>{
      for (final (i, e) in (score?.events ?? const <TripEventView>[]).indexed)
        Marker(
          markerId: MarkerId('e$i'),
          position: LatLng(e.lat, e.lon),
          infoWindow: InfoWindow(
            title: eventTitle(e.kind),
            snippet: describeEvent(e, units),
          ),
        ),
    };
    var minLat = samples.first.lat, maxLat = samples.first.lat;
    var minLon = samples.first.lon, maxLon = samples.first.lon;
    for (final s in samples) {
      if (s.lat < minLat) minLat = s.lat;
      if (s.lat > maxLat) maxLat = s.lat;
      if (s.lon < minLon) minLon = s.lon;
      if (s.lon > maxLon) maxLon = s.lon;
    }
    final bounds = LatLngBounds(
      southwest: LatLng(minLat - 0.002, minLon - 0.002),
      northeast: LatLng(maxLat + 0.002, maxLon + 0.002),
    );
    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: LatLng((minLat + maxLat) / 2, (minLon + maxLon) / 2),
        zoom: 12,
      ),
      polylines: polylines,
      markers: markers,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      liteModeEnabled: false,
      onMapCreated: (c) =>
          c.moveCamera(CameraUpdate.newLatLngBounds(bounds, 24)),
    );
  }
}
