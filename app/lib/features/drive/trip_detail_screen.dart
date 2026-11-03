import 'package:drift/drift.dart' show Value;
import 'package:drivalry_scoring/drivalry_scoring.dart'
    show
        Attention,
        Efficiency,
        EventKind,
        RoadSegment,
        Smoothness,
        SpeedUnits,
        Speeding,
        formatDuration,
        kmh,
        mph;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

import '../../app/bootstrap.dart';
import '../../app/theme.dart';
import '../../app/ui/ui.dart';
import '../../data/db/database.dart';
import '../../data/models/trip_phase.dart';
import '../../data/models/trip_score_view.dart';
import '../../tracking/providers.dart';
import '../../tracking/tracking_controller.dart';
import '../../widgets/units.dart';
import 'event_text.dart';
import 'share_card.dart';
import 'widgets/score_ring.dart';
import 'widgets/sheet_action.dart';
import 'widgets/trip_card.dart';

final _samplesProvider = FutureProvider.family<List<Sample>, String>(
  (ref, id) => ref.watch(databaseProvider).samplesFor(id),
);
final _segmentsProvider = FutureProvider.family<List<RoadSegment>, String>(
  (ref, id) => ref.watch(databaseProvider).segmentsFor(id),
);

/// Replaces the Google map at the top of the trip screen when set. Tests and
/// the layout audit use it: platform views do not exist there, so they draw
/// a stand-in and keep everything under it real.
final tripMapSurfaceProvider = Provider<WidgetBuilder?>((_) => null);

/// One trip, editorial (docs/12 §7 "Trip"): the route map at 40 % under a
/// pinned app bar, fading into the content, the ring with XP under it and
/// the verdict beside it, four thin bars, a grid of six stats, "What
/// happened" as a timeline, and one-line footnotes about limit coverage and
/// the route. Without a saved route the page starts under the app bar.
/// Share is the only app-bar action besides the overflow.
class TripDetailScreen extends ConsumerWidget {
  const TripDetailScreen({super.key, required this.tripId});

  final String tripId;

  /// Height of the route map at the top of the screen.
  static double mapHeight(BuildContext context) =>
      MediaQuery.sizeOf(context).height * 0.4;

  /// How much of the map the content fades over.
  static const fade = 72.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripAsync = ref.watch(tripProvider(tripId));
    final trip = tripAsync.value;
    if (trip == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Trip')),
        body: tripAsync.isLoading
            ? const Padding(
                padding: Space.screen,
                child: Column(
                  children: [
                    SizedBox(height: Space.xl),
                    SkeletonTile(height: 160),
                    SizedBox(height: Space.md),
                    SkeletonTile(),
                  ],
                ),
              )
            : const EmptyState(
                headline: 'This trip is gone.',
                body:
                    'It was deleted from this phone, so there is nothing '
                    'to show.',
              ),
      );
    }
    final t = trip.trip;
    final score = trip.score == null
        ? null
        : TripScoreView.fromJsonString(trip.score!.scoreJson);
    final scored = score != null && score.scored;
    final unitsSetting =
        ref.watch(unitsSettingProvider).value ?? UnitsSetting.auto;
    final units = resolveUnits(unitsSetting, packRegion: t.packRegion);
    final samplesAsync = ref.watch(_samplesProvider(tripId));
    final samples = samplesAsync.value ?? const <Sample>[];
    final segments =
        ref.watch(_segmentsProvider(tripId)).value ?? const <RoadSegment>[];
    final controller = ref.read(trackingControllerProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final topPad = media.padding.top;

    // The route map takes the top 40 % only while there is, or may still
    // be, something to draw. Without a route the page starts straight under
    // the app bar (docs/12 §2: no empty band at the top) and the fact goes
    // in the footnotes.
    final hasRoute = samples.length >= 2;
    final mapsReady = ref.watch(mapsReadyProvider);
    final canDraw =
        ref.watch(tripMapSurfaceProvider) != null ||
        mapsReady.isLoading ||
        mapsReady.value == true;
    final showMap = samplesAsync.isLoading || (hasRoute && canDraw);
    final String? routeNote;
    if (showMap) {
      routeNote = null;
    } else if (!hasRoute) {
      routeNote = 'Route not saved for this trip.';
    } else {
      routeNote = 'Map not available in this version.';
    }
    final notes = <String>[?_coverageNote(t), ?routeNote];
    // Six stats in two columns on phones: "1 min 14 s" and "Over the limit"
    // ellipsize in three columns under 600 wide.
    final columns = media.size.width >= 600 ? 3 : 2;

    final sections = <Widget>[
      _Hero(trip: t, score: score, units: units),
      if (scored) ...[
        const SizedBox(height: Space.section),
        EditorialSection(
          kicker: 'Breakdown',
          padding: EdgeInsets.zero,
          gap: 0,
          child: Column(
            children: [
              _BarRow('Speed', score.penalties.speed, Speeding.cap),
              _BarRow('Smoothness', score.penalties.smoothness, Smoothness.cap),
              _BarRow('Attention', score.penalties.attention, Attention.cap),
              _BarRow('Efficiency', score.penalties.efficiency, Efficiency.cap),
            ],
          ),
        ),
      ],
      const SizedBox(height: Space.section),
      EditorialSection(
        kicker: 'Stats',
        padding: EdgeInsets.zero,
        gap: 0,
        child: StatGrid(
          columns: columns,
          children: [
            for (final (label, value) in _stats(t, score, units))
              StatTile(value: value, label: label),
          ],
        ),
      ),
      if (score != null &&
          (score.events.isNotEmpty || score.observations.isNotEmpty)) ...[
        const SizedBox(height: Space.section),
        EditorialSection(
          kicker: 'What happened',
          padding: EdgeInsets.zero,
          gap: 0,
          child: Column(
            children: [
              for (final (i, e) in score.events.indexed)
                _EventRow(
                  key: ValueKey('event-$i'),
                  event: e,
                  units: units,
                  counted: true,
                  onFlag: e.kind == EventKind.speeding
                      ? () => _flagLimit(context, ref, t, e, segments, units)
                      : null,
                ),
              for (final (i, e) in score.observations.indexed)
                _EventRow(
                  key: ValueKey('obs-$i'),
                  event: e,
                  units: units,
                  counted: false,
                  onFlag: () => _flagLimit(context, ref, t, e, segments, units),
                ),
            ],
          ),
        ),
      ],
      if (notes.isNotEmpty) ...[
        const SizedBox(height: Space.xl),
        for (final (i, n) in notes.indexed) ...[
          if (i > 0) const SizedBox(height: Space.xs),
          Text(n, style: context.caption),
        ],
      ],
    ];

    final actions = <Widget>[
      if (scored)
        IconButton(
          tooltip: 'Share',
          icon: const Icon(Icons.ios_share),
          onPressed: () => shareTripFromApp(context, ref, t, score, units),
        ),
      PopupMenuButton<String>(
        tooltip: 'More',
        onSelected: (v) async {
          switch (v) {
            case 'passenger':
              await controller.answerPassenger(tripId, t.isPassenger != true);
            case 'rescore':
              await controller.rescore(tripId);
            case 'delete':
              if (await confirmDeleteTrip(context)) {
                await controller.deleteTrip(tripId);
                if (context.mounted) context.pop();
              }
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'passenger',
            child: Text(
              t.isPassenger == true ? 'I was the driver' : 'Mark as passenger',
            ),
          ),
          const PopupMenuItem(value: 'rescore', child: Text('Score again')),
          const PopupMenuItem(value: 'delete', child: Text('Delete trip')),
        ],
      ),
    ];

    // A pinned bar: over the map while the page is at the top, solid once
    // the content scrolls under it, so nothing ever shows through the title.
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            title: Text(tripDateLabel(t)),
            actions: actions,
            // The bar's own extent is measured under the status bar.
            expandedHeight: showMap ? mapHeight(context) - topPad : null,
            flexibleSpace: !showMap
                ? null
                : FlexibleSpaceBar(
                    // Pinned: the platform view is clipped, never resized,
                    // as the content slides over it.
                    collapseMode: CollapseMode.pin,
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        _TripMap(
                          samples: samples,
                          segments: segments,
                          score: score,
                          units: units,
                          loading: samplesAsync.isLoading,
                        ),
                        // The lower edge fades into the page.
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: fade,
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    scheme.surface.withValues(alpha: 0),
                                    scheme.surface,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Legible title over any map tile.
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: topPad + kToolbarHeight + Space.xl,
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    scheme.surface.withValues(alpha: 0.85),
                                    scheme.surface.withValues(alpha: 0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              Space.gutter,
              Space.lg,
              Space.gutter,
              Space.xl + media.padding.bottom,
            ),
            sliver: SliverList.list(
              children: [
                for (final (i, s) in sections.indexed)
                  Reveal(delay: Reveal.stagger(i), child: s),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static List<(String, String)> _stats(
    Trip trip,
    TripScoreView? score,
    SpeedUnits units,
  ) {
    final s = score?.summary;
    final items = <(String, String)>[
      ('Distance', formatDistance(trip.distanceM, units)),
      ('Driving', formatElapsed(Duration(seconds: trip.movingS.round()))),
      if (s != null) ('Average', formatSpeed(s.avgMovingSpeed, units)),
      if (s != null) ('Top speed', formatSpeed(s.maxSpeed, units)),
      if (s != null && s.secondsOverLimit > 0)
        ('Over the limit', formatDuration(s.secondsOverLimit)),
      if (s != null && s.secondsOverLimit > 0)
        ('Time saved', formatDuration(s.timeSavedBySpeedingS)),
      if (trip.nightFraction != null && trip.nightFraction! > 0)
        ('At night', '${(trip.nightFraction! * 100).round()}%'),
      if (trip.weather != null) ('Weather', trip.weather!),
      if (trip.vehicleLabel != null) ('Car', trip.vehicleLabel!),
      if (trip.phase == TripPhase.unscored.wire && trip.isPassenger == true)
        ('Role', 'Passenger'),
    ];
    return items.length > 6 ? items.sublist(0, 6) : items;
  }

  /// "82% of this drive had known limits." or why speeding went unscored.
  static String? _coverageNote(Trip t) {
    final c = t.limitCoverage;
    if (c == null) return null;
    if (c > 0) return '${(c * 100).round()}% of this drive had known limits.';
    if (t.packRegion == null) {
      return 'No speed-limit pack covers this area yet, so speeding was not '
          'scored.';
    }
    return 'No road with a known limit on this drive.';
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
        const SnackBar(content: Text('This event has no road to flag.')),
      );
      return;
    }
    final roadLabel = segName ?? 'this road';
    final initial = event.limitMps == null || event.limitMps!.isNaN
        ? ''
        : formatSpeed(event.limitMps!, units, withUnit: false);
    final posted = await showDrivalrySheet<int>(
      context,
      title: 'Limit is wrong here',
      // The field owns its controller for as long as the sheet is on screen,
      // exit animation included; the value comes back through the pop.
      builder: (_) => TextControllers(
        initial: [initial],
        builder: (ctx, c) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('On $roadLabel. What does the sign say?', style: ctx.body),
              const SizedBox(height: Space.sm),
              Text(
                'Your fix applies to you now, and to everyone once a second '
                'driver agrees.',
                style: ctx.caption,
              ),
              const SizedBox(height: Space.lg),
              TextField(
                controller: c.first,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Posted limit (${unitLabel(units)})',
                ),
              ),
              const SizedBox(height: Space.lg),
              PrimaryButton(
                label: 'Send',
                onPressed: () =>
                    Navigator.pop(ctx, int.tryParse(c.first.text.trim())),
              ),
            ],
          ),
        ),
      ),
    );
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
      Haptics.success();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Thanks. This road stays quiet for you until the fix lands.',
          ),
        ),
      );
    }
  }
}

/// Ring 120 with XP under it, verdict beside it as `headline` 24.
class _Hero extends StatelessWidget {
  const _Hero({required this.trip, required this.score, required this.units});

  final Trip trip;
  final TripScoreView? score;
  final SpeedUnits units;

  @override
  Widget build(BuildContext context) {
    final s = score;
    final scored = s != null && s.scored;
    final verdict = scored && s.roastText != null
        ? s.roastText!
        : unscoredLabel(trip, s);
    final lines = (s?.lines ?? const <FeedbackLineView>[]).take(2).toList();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Hero(
              tag: tripRingTag(trip.id),
              child: ScoreRing(
                score: scored ? s.score : null,
                size: 120,
                stroke: 11,
                reckless: s?.reckless ?? false,
                animate: true,
              ),
            ),
            if (scored) ...[
              const SizedBox(height: Space.sm),
              AnimatedNumber(
                value: s.xp,
                prefix: '+',
                suffix: ' XP',
                style: context.label,
              ),
            ],
          ],
        ),
        const SizedBox(width: Space.xl),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                verdict,
                style: context.headline.copyWith(
                  fontSize: 24,
                  fontStyle: scored && s.headlineIsRoast
                      ? FontStyle.italic
                      : null,
                ),
              ),
              for (final line in lines) ...[
                const SizedBox(height: Space.sm),
                Text(line.text, style: context.bodyMuted),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One thin bar of the breakdown: label, bar, points lost.
class _BarRow extends StatelessWidget {
  const _BarRow(this.label, this.lost, this.cap);
  final String label;
  final double lost;
  final double cap;

  @override
  Widget build(BuildContext context) {
    final kept = (cap - lost).clamp(0.0, cap);
    final fraction = cap <= 0 ? 0.0 : kept / cap;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: Row(
        children: [
          SizedBox(width: 96, child: Text(label, style: context.caption)),
          Expanded(
            child: ThinBar(
              fraction: fraction,
              color: DrivalryTheme.scoreColor((100 * fraction).round()),
            ),
          ),
          const SizedBox(width: Space.md),
          SizedBox(
            width: 56,
            child: Text(
              lost < 0.05
                  ? 'Clean'
                  : '−${lost.toStringAsFixed(lost < 10 ? 1 : 0)}',
              textAlign: TextAlign.end,
              style: context.label,
            ),
          ),
        ],
      ),
    );
  }
}

/// Timeline row: icon, plain one-line description, kind and time; the flag
/// stays for speeding.
class _EventRow extends StatelessWidget {
  const _EventRow({
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
    final scheme = Theme.of(context).colorScheme;
    final color = counted
        ? severityColor(event.severity, scheme)
        : scheme.outline;
    final at = DateFormat.jm().format(
      DateTime.fromMillisecondsSinceEpoch(event.startT),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.18),
            ),
            alignment: Alignment.center,
            child: Icon(eventIcon(event.kind), size: 20, color: color),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(describeEvent(event, units), style: context.body),
                  const SizedBox(height: Space.xs),
                  Text(
                    counted
                        ? '${eventTitle(event.kind)} · $at'
                        : 'Not scored, the limit here is unsure · $at',
                    style: context.caption,
                  ),
                ],
              ),
            ),
          ),
          if (onFlag != null)
            IconButton(
              icon: const Icon(Icons.flag_outlined),
              tooltip: 'Limit is wrong here',
              onPressed: onFlag,
            ),
        ],
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
    this.loading = false,
  });

  final List<Sample> samples;
  final List<RoadSegment> segments;
  final TripScoreView? score;
  final SpeedUnits units;

  /// The samples are still on their way from the database.
  final bool loading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    // Never build a GoogleMap before the SDK has its key (bootstrap.dart):
    // on iOS that aborts the process. While the key is on its way the
    // placeholder shows, which is also what a build without a key shows.
    final surface = ref.watch(tripMapSurfaceProvider);
    if (surface != null && samples.length >= 2) return surface(context);
    final mapsReady = ref.watch(mapsReadyProvider);
    final ready = mapsReady.value == true;
    if (!ready || samples.length < 2) {
      final String message;
      if (loading || mapsReady.isLoading) {
        message = 'Loading the map…';
      } else if (samples.length < 2) {
        message = 'Route not saved for this trip.';
      } else {
        message = 'Map not available in this version.';
      }
      return Container(
        color: scheme.surfaceContainerLow,
        // The lower part fades under the content; keep the words above it.
        alignment: const Alignment(0, -0.2),
        padding: const EdgeInsets.all(Space.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Kicker('Route'),
            const SizedBox(height: Space.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.bodyMuted,
            ),
          ],
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
          color: scheme.outline,
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
          c.animateCamera(CameraUpdate.newLatLngBounds(bounds, 24)),
    );
  }
}
