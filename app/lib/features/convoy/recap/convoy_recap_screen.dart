import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drivalry_scoring/drivalry_scoring.dart' show SpeedUnits;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/ui/ui.dart';
import '../../../data/convoy/recap_builder.dart';
import '../../../data/convoy/settle_up.dart';
import '../../../data/db/database.dart';
import '../../../data/repos/convoy_sync.dart';
import '../../../tracking/providers.dart';
import '../../../widgets/friendly_error.dart';
import '../../../widgets/units.dart';
import '../../drive/share_card.dart' show renderWidgetToPng;
import '../widgets/convoy_ui.dart';
import 'recap_card.dart';
import 'recap_playback.dart';

/// The recap plus the tracks it was drawn from.
class RecapData {
  const RecapData({required this.recap, required this.tracks});
  final ConvoyRecap recap;
  final Map<String, List<ConvoyTrack>> tracks;
}

/// Builds (or loads) the recap for a convoy. An ended convoy's recap is
/// stored in `ConvoyLocal` once built; `ref.invalidate` rebuilds it.
final convoyRecapProvider = FutureProvider.autoDispose
    .family<RecapData?, String>((ref, id) async {
      final repo = ref.watch(convoyRepoProvider);
      final db = ref.watch(databaseProvider);
      final convoy =
          ref.watch(convoyProvider(id)) ?? await repo.cachedConvoy(id);
      if (convoy == null) return null;
      final rows = await db.convoyTracksFor(id);
      final tracks = <String, List<ConvoyTrack>>{};
      for (final r in rows) {
        (tracks[r.userId] ??= []).add(r);
      }
      final local = await db.convoyLocalFor(id);
      final stored = ConvoyRecap.fromJson(local?.recapJson);
      if (stored != null && convoy.isEnded) {
        return RecapData(recap: stored, tracks: tracks);
      }
      final members = await repo.members(id);
      final stops = await repo.cachedStops(id) ?? await repo.fetchStops(id);
      final expenses =
          await repo.cachedExpenses(id) ?? await repo.fetchExpenses(id);
      final from = convoy.startedAt ?? convoy.createdAt;
      final to = convoy.endedAt ?? DateTime.now().toUtc();
      final summaries = await repo.tripSummaries(
        [for (final m in members) m.userId],
        from.subtract(const Duration(hours: 1)),
        to.add(const Duration(hours: 1)),
      );
      final now = DateTime.now().toUtc();
      final recap = buildRecap(
        convoy: convoy,
        members: members,
        tracks: rows,
        stops: stops,
        expenses: expenses,
        summaries: summaries,
        now: now,
      );
      final isFinal = recapIsFinal(
        ended: convoy.isEnded,
        endedAt: convoy.endedAt,
        hasSummaries: summaries.isNotEmpty,
        now: now,
      );
      if (isFinal) {
        await db.upsertConvoyLocal(
          ConvoyLocalCompanion(
            convoyId: Value(id),
            role: Value(local?.role ?? 'member'),
            joinedAt: Value(local?.joinedAt ?? now.millisecondsSinceEpoch),
            leftAt: Value(local?.leftAt),
            recapJson: Value(recap.toJson()),
            updatedAt: Value(now.millisecondsSinceEpoch),
          ),
        );
      }
      return RecapData(recap: recap, tracks: tracks);
    });

/// The end-of-trip recap: an animated replay of every car's line, the
/// awards as tiles, and the numbers. Built on this phone from what it
/// received.
class ConvoyRecapScreen extends ConsumerStatefulWidget {
  const ConvoyRecapScreen({super.key, required this.convoyId});

  final String convoyId;

  @override
  ConsumerState<ConvoyRecapScreen> createState() => _ConvoyRecapScreenState();
}

class _ConvoyRecapScreenState extends ConsumerState<ConvoyRecapScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  );
  bool _sharing = false;

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(convoyRecapProvider(widget.convoyId));
    final units = resolveUnits(
      ref.watch(unitsSettingProvider).value ?? UnitsSetting.auto,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recap'),
        actions: [
          IconButton(
            tooltip: 'Rebuild',
            onPressed: () =>
                ref.invalidate(convoyRecapProvider(widget.convoyId)),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            key: const Key('share-recap'),
            tooltip: 'Share',
            onPressed: data.value == null || _sharing
                ? null
                : () => _share(data.value!, units),
            icon: const Icon(Icons.ios_share),
          ),
        ],
      ),
      body: switch (data) {
        AsyncData(value: null) => const EmptyState(
          kicker: 'Recap',
          headline: 'Nothing to recap yet.',
          body: 'Open it from the Convoy tab first.',
        ),
        AsyncData(value: final d?) => _RecapBody(
          data: d,
          anim: _anim,
          units: units,
        ),
        AsyncError(:final error) => EmptyState(
          kicker: 'Recap',
          headline: 'No recap yet.',
          body: friendlyError(error, doing: 'build the recap'),
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(convoyRecapProvider(widget.convoyId)),
        ),
        _ => const Padding(
          padding: EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, 0),
          child: Column(
            children: [
              SkeletonTile(height: 72),
              SizedBox(height: Space.md),
              SkeletonTile(height: 220),
              SizedBox(height: Space.md),
              SkeletonTile(height: 88),
            ],
          ),
        ),
      },
    );
  }

  Future<void> _share(RecapData d, SpeedUnits units) async {
    setState(() => _sharing = true);
    try {
      final png = await renderWidgetToPng(
        RecapShareCard(recap: d.recap, tracks: d.tracks, units: units),
        view: View.of(context),
        theme: Theme.of(context),
        logicalSize: recapCardSize,
        pixelRatio: 2,
      );
      final dir = await getTemporaryDirectory();
      final file = File(
        p.join(dir.path, 'drivalry-convoy-${widget.convoyId}.png'),
      );
      await file.writeAsBytes(png, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          text: '${d.recap.name}: our convoy recap on Drivalry.',
          subject: 'Convoy recap',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e, doing: 'share the recap'))),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }
}

class _RecapBody extends StatelessWidget {
  const _RecapBody({
    required this.data,
    required this.anim,
    required this.units,
  });

  final RecapData data;
  final AnimationController anim;
  final SpeedUnits units;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = data.recap;
    final total = r.members.fold(0.0, (a, m) => a + m.distanceM);
    final nameOf = {for (final m in r.members) m.userId: m.name};
    final order = [for (final m in r.members) m.userId];
    final d = r.duration;
    return ListView(
      padding: const EdgeInsets.only(top: Space.lg, bottom: Space.xxxl),
      children: [
        Padding(
          padding: Space.screen,
          child: Reveal(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Kicker('Convoy recap'),
                const SizedBox(height: Space.sm),
                Text(r.name, style: context.headline),
                const SizedBox(height: Space.lg),
                ClipRRect(
                  borderRadius: Radii.cardRadius,
                  child: AspectRatio(
                    aspectRatio: 1.5,
                    child: Stack(
                      children: [
                        AnimatedBuilder(
                          animation: anim,
                          builder: (_, _) => RecapPlayback(
                            tracks: data.tracks,
                            progress: anim.isAnimating || anim.value > 0
                                ? anim.value
                                : 1,
                            order: order,
                          ),
                        ),
                        if (data.tracks.isEmpty)
                          Center(
                            child: Text(
                              'No car shared its position this trip.',
                              style: context.caption,
                            ),
                          ),
                        Positioned(
                          right: Space.sm,
                          bottom: Space.sm,
                          child: IconButton.filledTonal(
                            key: const Key('replay'),
                            tooltip: 'Replay',
                            constraints: const BoxConstraints.tightFor(
                              width: Sizes.touch,
                              height: Sizes.touch,
                            ),
                            onPressed: data.tracks.isEmpty
                                ? null
                                : () {
                                    Haptics.tap();
                                    anim.forward(from: 0);
                                  },
                            icon: const Icon(Icons.replay),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (data.tracks.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.sm),
                    child: Wrap(
                      spacing: Space.md,
                      runSpacing: Space.xs,
                      children: [
                        for (var i = 0; i < order.length; i++)
                          if (data.tracks.containsKey(order[i]))
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    // Line colours match the drawn tracks.
                                    color: trackColors[i % trackColors.length],
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: Space.xs),
                                Text(
                                  nameOf[order[i]] ?? 'Driver',
                                  style: context.caption,
                                ),
                              ],
                            ),
                      ],
                    ),
                  ),
                const SizedBox(height: Space.xl),
                StatGrid(
                  children: [
                    StatTile(
                      value: '${r.members.length}',
                      label: r.members.length == 1 ? 'Car' : 'Cars',
                    ),
                    StatTile(
                      value: formatDistance(total, units),
                      label: 'Together',
                    ),
                    if (d != null)
                      StatTile(value: formatElapsed(d), label: 'On the road'),
                    StatTile(
                      value: '${r.stopsDone}',
                      label: r.stopsDone == 1 ? 'Stop' : 'Stops',
                    ),
                    if (r.totalCostCents > 0)
                      StatTile(
                        value: formatCents(
                          r.totalCostCents,
                          currency: r.costCurrency,
                        ),
                        label: 'Spent',
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.section),
        if (r.awards.isNotEmpty)
          EditorialSection(
            kicker: 'Awards',
            child: Column(
              children: [
                for (final (i, a) in r.awards.indexed) ...[
                  if (i > 0) const SizedBox(height: Space.md),
                  Reveal(
                    delay: Reveal.stagger(i),
                    child: Tile(
                      child: Row(
                        children: [
                          Icon(
                            _awardIcon(a.id),
                            size: 28,
                            color: a.honourable ? scheme.primary : scheme.error,
                          ),
                          const SizedBox(width: Space.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(a.title, style: context.title),
                                const SizedBox(height: Space.xs),
                                Text(
                                  '${nameOf[a.userId] ?? 'Driver'} · ${a.detail}',
                                  style: context.caption,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        EditorialSection(
          kicker: 'Cars',
          child: Column(
            children: [
              for (final m in r.members)
                ConvoyRow(
                  leading: Avatar(name: m.name),
                  title: m.name,
                  caption: [
                    formatDistance(m.distanceM, units),
                    if (m.averageScore != null)
                      'score ${m.averageScore!.round()}',
                    if (m.stopsProposed > 0)
                      '${m.stopsProposed} ${m.stopsProposed == 1 ? 'stop' : 'stops'} proposed',
                  ].join(' · '),
                ),
            ],
          ),
        ),
        Padding(
          padding: Space.screen,
          child: Text(
            'Built on this phone from what the cars shared. Nothing was '
            'uploaded to make it.',
            style: context.caption,
          ),
        ),
      ],
    );
  }

  static IconData _awardIcon(String id) => switch (id) {
    'smoothest' => Icons.waves_outlined,
    'lead_foot' => Icons.speed,
    'most_stops' => Icons.local_gas_station_outlined,
    'dj' => Icons.headphones_outlined,
    'navigator' => Icons.explore_outlined,
    _ => Icons.emoji_events_outlined,
  };
}
