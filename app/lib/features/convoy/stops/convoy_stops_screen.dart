import 'dart:async';

import 'package:drivalry_scoring/drivalry_scoring.dart' show SpeedUnits;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/ui/ui.dart';
import '../../../data/convoy/stop_suggestions.dart';
import '../../../data/google/places_client.dart';
import '../../../data/google/routes_client.dart' show LatLon;
import '../../../data/repos/convoy_repo.dart';
import '../../../data/repos/convoy_sync.dart';
import '../../../data/supabase/supabase_providers.dart';
import '../../../tracking/providers.dart';
import '../../../widgets/units.dart';
import '../live/convoy_live.dart';
import '../widgets/convoy_map.dart' show stopIcon;
import '../widgets/convoy_ui.dart';

/// Stops: propose from Places suggestions along the route (or from where
/// you are), vote, and let the leader accept, reject or mark done. A
/// driving screen: 64-tall category tiles, 56 vote buttons, inline leader
/// actions (docs/12 §7, audit item 14).
class ConvoyStopsScreen extends ConsumerStatefulWidget {
  const ConvoyStopsScreen({super.key, required this.convoyId});

  final String convoyId;

  @override
  ConsumerState<ConvoyStopsScreen> createState() => _ConvoyStopsScreenState();
}

class _ConvoyStopsScreenState extends ConsumerState<ConvoyStopsScreen> {
  StopCategory? _loading;

  /// Stops I swiped away, hidden at once so the Dismissible leaves the tree
  /// before the cache catches up; Undo puts them back.
  final Set<String> _withdrawn = {};

  @override
  Widget build(BuildContext context) {
    final id = widget.convoyId;
    final me = ref.watch(currentUserIdProvider);
    final amLeader = ref.watch(amConvoyLeaderProvider(id));
    final stops = ref.watch(convoyStopsProvider(id));
    final list = [
      for (final s in stops.value ?? const <ConvoyStop>[])
        if (!_withdrawn.contains(s.id)) s,
    ];
    final members = ref.watch(convoyMembersProvider(id)).value ?? const [];
    final nameOf = {for (final m in members) m.userId: m.name};
    final units = resolveUnits(
      ref.watch(unitsSettingProvider).value ?? UnitsSetting.auto,
    );

    final accepted = [
      for (final s in list)
        if (s.status == StopStatus.accepted) s,
    ];
    final proposed = [
      for (final s in list)
        if (s.status == StopStatus.proposed) s,
    ]..sort((a, b) => b.score.compareTo(a.score));
    final earlier = [
      for (final s in list)
        if (s.status == StopStatus.done || s.status == StopStatus.rejected) s,
    ];

    Widget tile(ConvoyStop s, {bool open = true}) {
      final t = _StopTile(
        stop: s,
        me: me,
        amLeader: amLeader,
        proposer: nameOf[s.proposedBy],
        onVote: open
            ? (v) => ref.read(convoyRepoProvider).vote(id, s.id, v)
            : null,
        onStatus: open
            ? (st) => ref.read(convoyRepoProvider).setStopStatus(id, s.id, st)
            : null,
      );
      final mine =
          me != null && s.proposedBy == me && s.status == StopStatus.proposed;
      if (!mine) return t;
      // Swipe my own proposal away, with an Undo.
      final scheme = Theme.of(context).colorScheme;
      return Dismissible(
        key: ValueKey('withdraw:${s.id}'),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: Space.xl),
          decoration: BoxDecoration(
            color: scheme.errorContainer,
            borderRadius: Radii.cardRadius,
          ),
          child: Icon(Icons.undo, color: scheme.onErrorContainer),
        ),
        onDismissed: (_) => _withdraw(s),
        child: t,
      );
    }

    Widget section(String kicker, List<ConvoyStop> items, {bool open = true}) =>
        EditorialSection(
          kicker: kicker,
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(height: Space.md),
                Reveal(
                  delay: Reveal.stagger(i),
                  child: tile(items[i], open: open),
                ),
              ],
            ],
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Stops')),
      body: ListView(
        padding: EdgeInsets.only(
          top: Space.lg,
          bottom: pageBottomInset(context),
        ),
        children: [
          EditorialSection(
            kicker: 'Propose a stop',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CategoryGrid(
                  loading: _loading,
                  onPick: _loading != null ? null : (c) => _suggest(c, units),
                ),
                const SizedBox(height: Space.sm),
                Text(
                  'Along the route, or right where you are.',
                  style: context.caption,
                ),
              ],
            ),
          ),
          if (stops.isLoading && list.isEmpty)
            const Padding(
              padding: Space.screen,
              child: Column(
                children: [
                  SkeletonTile(height: 120),
                  SizedBox(height: Space.md),
                  SkeletonTile(height: 120),
                ],
              ),
            ),
          if (!stops.isLoading && list.isEmpty)
            // Follows the propose section, which already ends with the
            // section gap, so no top band of its own.
            const ConvoyNotice(
              headline: 'No stops yet.',
              body: 'Propose gas, food or a photo stop and the convoy votes.',
              padding: EdgeInsets.fromLTRB(
                Space.gutter,
                0,
                Space.gutter,
                Space.xxl,
              ),
            ),
          if (accepted.isNotEmpty) section('Next up', accepted),
          if (proposed.isNotEmpty) section('Proposed', proposed),
          if (earlier.isNotEmpty) section('Earlier', earlier, open: false),
        ],
      ),
    );
  }

  void _withdraw(ConvoyStop s) {
    final repo = ref.read(convoyRepoProvider);
    final id = widget.convoyId;
    setState(() => _withdrawn.add(s.id));
    Haptics.warning();
    unawaited(repo.setStopStatus(id, s.id, StopStatus.rejected));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('${s.name} withdrawn.'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              if (mounted) setState(() => _withdrawn.remove(s.id));
              unawaited(repo.setStopStatus(id, s.id, StopStatus.proposed));
            },
          ),
        ),
      );
  }

  /// The route still ahead of me: my routed polyline when there is one,
  /// else a straight line from me to the next target.
  Future<List<LatLon>> _remainingRoute() async {
    final live = ref.read(convoyLiveProvider(widget.convoyId));
    final poly = live?.eta.last?.polyline ?? const <LatLon>[];
    if (poly.length >= 2) return poly;
    final me = await _myPosition();
    final target =
        live?.nextTarget()?.point ??
        switch (ref.read(convoyProvider(widget.convoyId))?.destination) {
          final d? => LatLon(d.lat, d.lon),
          null => null,
        };
    return [?me, ?target];
  }

  Future<LatLon?> _myPosition() async {
    final me = ref.read(currentUserIdProvider);
    final live = ref.read(convoyLiveProvider(widget.convoyId));
    final mine = me == null ? null : live?.link.hub.latest[me];
    if (mine != null) return LatLon(mine.lat, mine.lon);
    try {
      final loc = await ref.read(trackingPortProvider).getLastKnownLocation();
      return loc == null ? null : LatLon(loc.lat, loc.lon);
    } catch (_) {
      return null;
    }
  }

  Future<void> _suggest(StopCategory category, SpeedUnits units) async {
    setState(() => _loading = category);
    try {
      final route = await _remainingRoute();
      if (route.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Needs a destination or a position first.'),
            ),
          );
        }
        return;
      }
      final found = await suggestStops(
        places: ref.read(placesClientProvider),
        category: category,
        remainingRoute: route,
      );
      if (!mounted) return;
      await _showSuggestions(category, found, units);
    } finally {
      if (mounted) setState(() => _loading = null);
    }
  }

  Future<void> _showSuggestions(
    StopCategory category,
    List<StopSuggestion>? found,
    SpeedUnits units,
  ) {
    final repo = ref.read(convoyRepoProvider);
    final id = widget.convoyId;
    final shown = found == null ? const <StopSuggestion>[] : found.take(8);
    return showConvoySheet<void>(
      context,
      title: '${category.label} along the way',
      scrollable: shown.length > 4,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (found == null)
            Text(
              'Suggestions are resting until tomorrow. Propose a stop by '
              'hand.',
              style: ctx.bodyMuted,
            ),
          if (found != null && found.isEmpty)
            Text('Nothing of that kind near the route.', style: ctx.bodyMuted),
          for (final s in shown)
            ConvoyRow(
              leading: Icon(stopIcon(category), size: 28),
              title: s.place.name,
              caption: [
                '${formatDistance(s.detourM, units)} off route',
                if (s.place.rating != null)
                  '★ ${s.place.rating!.toStringAsFixed(1)}',
                if (s.place.openNow == true) 'Open now',
                if (s.place.openNow == false) 'Closed',
              ].join(' · '),
              trailing: Text(
                'Propose',
                style: ctx.label.copyWith(
                  color: Theme.of(ctx).colorScheme.primary,
                ),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                unawaited(
                  repo.proposeStop(
                    id,
                    category: category,
                    name: s.place.name,
                    lat: s.place.location.lat,
                    lon: s.place.location.lon,
                    placeId: s.place.placeId,
                  ),
                );
              },
            ),
          const SizedBox(height: Space.sm),
          ConvoyRow(
            leading: const Icon(Icons.my_location, size: 28),
            title: '${category.label} stop where I am',
            caption: 'Pins your position',
            onTap: () async {
              Navigator.of(ctx).pop();
              final here = await _myPosition();
              if (here == null) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('No position yet. Try again in a moment.'),
                    ),
                  );
                }
                return;
              }
              await repo.proposeStop(
                id,
                category: category,
                name: '${category.label} stop',
                lat: here.lat,
                lon: here.lon,
              );
            },
          ),
        ],
      ),
    );
  }
}

/// The six categories as 64-tall tiles in three columns.
class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({required this.loading, required this.onPick});
  final StopCategory? loading;
  final void Function(StopCategory)? onPick;

  @override
  Widget build(BuildContext context) {
    const columns = 3;
    final cats = StopCategory.values;
    final rows = <Widget>[];
    for (var i = 0; i < cats.length; i += columns) {
      final slice = cats.sublist(i, (i + columns).clamp(0, cats.length));
      rows.add(
        Row(
          children: [
            for (var j = 0; j < columns; j++) ...[
              if (j > 0) const SizedBox(width: Space.md),
              Expanded(
                child: j < slice.length
                    ? _CategoryTile(
                        category: slice[j],
                        busy: loading == slice[j],
                        onTap: onPick == null ? null : () => onPick!(slice[j]),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      );
      if (i + columns < cats.length) rows.add(const SizedBox(height: Space.md));
    }
    return Column(children: rows);
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.busy,
    required this.onTap,
  });

  final StopCategory category;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: Sizes.drivingTouch,
      child: Tile(
        key: Key('stop-category-${category.wire}'),
        onTap: onTap,
        padding: const EdgeInsets.symmetric(
          horizontal: Space.xs,
          vertical: Space.xs,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy)
              SizedBox.square(
                dimension: 28,
                child: Padding(
                  padding: const EdgeInsets.all(Space.xs),
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: scheme.primary,
                  ),
                ),
              )
            else
              Icon(stopIcon(category), size: 28, color: scheme.primary),
            const SizedBox(height: Space.xs),
            Text(
              category.label,
              style: context.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _StopTile extends StatelessWidget {
  const _StopTile({
    required this.stop,
    required this.me,
    required this.amLeader,
    required this.proposer,
    required this.onVote,
    required this.onStatus,
  });

  final ConvoyStop stop;
  final String? me;
  final bool amLeader;
  final String? proposer;
  final void Function(int vote)? onVote;
  final void Function(StopStatus status)? onStatus;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = stop;
    final mine = me == null ? null : s.votes[me];
    final statusLabel = switch (s.status) {
      StopStatus.proposed => null,
      StopStatus.accepted => 'Accepted',
      StopStatus.rejected => 'Rejected',
      StopStatus.done => 'Done',
    };
    final caption = [
      s.category.label,
      if (me != null && s.proposedBy == me)
        'by you'
      else if (proposer case final who?)
        'by $who',
      ?statusLabel,
    ].join(' · ');
    final leaderActions = amLeader && onStatus != null;

    return Tile(
      key: Key('stop-${s.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(stopIcon(s.category), size: 28, color: scheme.primary),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.name,
                      style: context.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: Space.xs),
                    Text(caption, style: context.caption),
                  ],
                ),
              ),
            ],
          ),
          if (onVote != null) ...[
            const SizedBox(height: Space.lg),
            Row(
              children: [
                Expanded(
                  child: _VoteButton(
                    key: Key('vote-up-${s.id}'),
                    selected: mine == 1,
                    icon: mine == 1 ? Icons.thumb_up : Icons.thumb_up_outlined,
                    count: s.upVotes,
                    semantics: 'Yes',
                    onPressed: () => onVote!(mine == 1 ? 0 : 1),
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: _VoteButton(
                    key: Key('vote-down-${s.id}'),
                    selected: mine == -1,
                    icon: mine == -1
                        ? Icons.thumb_down
                        : Icons.thumb_down_outlined,
                    count: s.downVotes,
                    semantics: 'No',
                    onPressed: () => onVote!(mine == -1 ? 0 : -1),
                  ),
                ),
              ],
            ),
          ] else if (s.status != StopStatus.proposed) ...[
            const SizedBox(height: Space.md),
            Text(
              '${s.upVotes} yes · ${s.downVotes} no',
              style: context.label.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          if (leaderActions && s.status == StopStatus.proposed) ...[
            const SizedBox(height: Space.md),
            Row(
              children: [
                Expanded(
                  child: PairedAction(
                    key: Key('accept-${s.id}'),
                    label: 'Accept',
                    height: Sizes.touch,
                    onPressed: () => onStatus!(StopStatus.accepted),
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: PairedAction(
                    key: Key('reject-${s.id}'),
                    label: 'Reject',
                    height: Sizes.touch,
                    onPressed: () => onStatus!(StopStatus.rejected),
                  ),
                ),
              ],
            ),
          ],
          if (leaderActions && s.status == StopStatus.accepted) ...[
            const SizedBox(height: Space.md),
            Row(
              children: [
                Expanded(
                  child: PairedAction(
                    key: Key('done-${s.id}'),
                    label: 'Done',
                    height: Sizes.touch,
                    onPressed: () => onStatus!(StopStatus.done),
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: PairedAction(
                    key: Key('reopen-${s.id}'),
                    label: 'Reopen vote',
                    height: Sizes.touch,
                    onPressed: () => onStatus!(StopStatus.proposed),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A 56-tall vote button: thumb plus the count in `label`.
class _VoteButton extends StatelessWidget {
  const _VoteButton({
    super.key,
    required this.selected,
    required this.icon,
    required this.count,
    required this.semantics,
    required this.onPressed,
  });

  final bool selected;
  final IconData icon;
  final int count;
  final String semantics;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? scheme.onPrimary : scheme.onSecondaryContainer;
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 22, color: fg),
        const SizedBox(width: Space.sm),
        AnimatedNumber(
          value: count,
          style: context.label.copyWith(color: fg),
        ),
      ],
    );
    void press() {
      Haptics.select();
      onPressed();
    }

    return Semantics(
      label: '$semantics, $count ${count == 1 ? 'vote' : 'votes'}',
      child: SizedBox(
        height: Sizes.button,
        child: selected
            ? FilledButton(onPressed: press, child: child)
            : FilledButton.tonal(onPressed: press, child: child),
      ),
    );
  }
}
