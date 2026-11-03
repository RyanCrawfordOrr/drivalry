import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drivalry_scoring/drivalry_scoring.dart' show SpeedUnits;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../data/convoy/recap_builder.dart';
import '../../../data/convoy/settle_up.dart';
import '../../../data/db/database.dart';
import '../../../data/repos/convoy_sync.dart';
import '../../../tracking/providers.dart';
import '../../../widgets/units.dart';
import '../../drive/share_card.dart' show renderWidgetToPng;
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
/// awards, and the numbers. Built on this phone from what it received.
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
    final theme = Theme.of(context);
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
            icon: const Icon(Icons.share_outlined),
          ),
        ],
      ),
      body: switch (data) {
        AsyncData(value: null) => const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'Nothing to recap yet: this convoy is not in your list.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        AsyncData(value: final d?) => _RecapBody(
          data: d,
          anim: _anim,
          units: units,
        ),
        AsyncError(:final error) => Center(child: Text('Recap failed: $error')),
        _ => const Center(child: CircularProgressIndicator()),
      },
      bottomNavigationBar: data.value == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  'Built from the positions this phone received and the '
                  'Drive Scores members chose to upload. Nothing was sent to '
                  'make it.',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not share: $e')));
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
    final theme = Theme.of(context);
    final r = data.recap;
    final total = r.members.fold(0.0, (a, m) => a + m.distanceM);
    final nameOf = {for (final m in r.members) m.userId: m.name};
    final order = [for (final m in r.members) m.userId];
    final d = r.duration;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(r.name, style: theme.textTheme.headlineSmall),
        Text(
          [
            '${r.members.length} ${r.members.length == 1 ? 'car' : 'cars'}',
            formatDistance(total, units),
            if (d != null) formatElapsed(d),
            '${r.stopsDone} ${r.stopsDone == 1 ? 'stop' : 'stops'}',
            if (r.totalCostCents > 0)
              formatCents(r.totalCostCents, currency: r.costCurrency),
          ].join(' · '),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
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
                      'No positions were received during this trip.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: IconButton.filledTonal(
                    key: const Key('replay'),
                    tooltip: 'Replay',
                    onPressed: data.tracks.isEmpty
                        ? null
                        : () => anim.forward(from: 0),
                    icon: const Icon(Icons.replay),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (data.tracks.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 12,
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
                            color: trackColors[i % trackColors.length],
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          nameOf[order[i]] ?? 'Driver',
                          style: theme.textTheme.labelSmall,
                        ),
                      ],
                    ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        Text('Awards', style: theme.textTheme.titleMedium),
        for (final a in r.awards)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              _awardIcon(a.id),
              color: a.honourable
                  ? theme.colorScheme.primary
                  : theme.colorScheme.error,
            ),
            title: Text(a.title),
            subtitle: Text('${nameOf[a.userId] ?? 'Driver'} · ${a.detail}'),
          ),
        const SizedBox(height: 8),
        Text('Cars', style: theme.textTheme.titleMedium),
        for (final m in r.members)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(m.name),
            subtitle: Text(
              [
                formatDistance(m.distanceM, units),
                if (m.averageScore != null)
                  'avg score ${m.averageScore!.round()}',
                if (m.stopsProposed > 0) '${m.stopsProposed} stops proposed',
              ].join(' · '),
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
