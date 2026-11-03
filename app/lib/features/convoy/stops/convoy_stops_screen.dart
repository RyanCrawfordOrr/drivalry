import 'dart:async';

import 'package:drivalry_scoring/drivalry_scoring.dart' show SpeedUnits;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// Stops: propose from Places suggestions along the route (or from where
/// you are), vote, and let the leader accept, reject or mark done.
class ConvoyStopsScreen extends ConsumerStatefulWidget {
  const ConvoyStopsScreen({super.key, required this.convoyId});

  final String convoyId;

  @override
  ConsumerState<ConvoyStopsScreen> createState() => _ConvoyStopsScreenState();
}

class _ConvoyStopsScreenState extends ConsumerState<ConvoyStopsScreen> {
  StopCategory? _loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final id = widget.convoyId;
    final me = ref.watch(currentUserIdProvider);
    final amLeader = ref.watch(amConvoyLeaderProvider(id));
    final stops = ref.watch(convoyStopsProvider(id));
    final list = stops.value ?? const <ConvoyStop>[];
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

    return Scaffold(
      appBar: AppBar(title: const Text('Stops')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Suggest a stop', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Places along the remaining route, a few lookups a day. Or '
            'propose wherever you are.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in StopCategory.values)
                ActionChip(
                  avatar: _loading == c
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(stopIcon(c), size: 18),
                  label: Text(c.label),
                  onPressed: _loading != null ? null : () => _suggest(c, units),
                ),
            ],
          ),
          const SizedBox(height: 20),
          if (stops.isLoading && list.isEmpty)
            const LinearProgressIndicator(minHeight: 2),
          if (!stops.isLoading && list.isEmpty)
            Text('No stops proposed yet.', style: theme.textTheme.bodyMedium),
          if (accepted.isNotEmpty) ...[
            Text('Next up', style: theme.textTheme.titleSmall),
            for (final s in accepted)
              _StopTile(
                stop: s,
                me: me,
                amLeader: amLeader,
                proposer: nameOf[s.proposedBy],
                onVote: (v) => ref.read(convoyRepoProvider).vote(id, s.id, v),
                onStatus: (st) =>
                    ref.read(convoyRepoProvider).setStopStatus(id, s.id, st),
              ),
            const SizedBox(height: 12),
          ],
          if (proposed.isNotEmpty) ...[
            Text('Proposed', style: theme.textTheme.titleSmall),
            for (final s in proposed)
              _StopTile(
                stop: s,
                me: me,
                amLeader: amLeader,
                proposer: nameOf[s.proposedBy],
                onVote: (v) => ref.read(convoyRepoProvider).vote(id, s.id, v),
                onStatus: (st) =>
                    ref.read(convoyRepoProvider).setStopStatus(id, s.id, st),
              ),
            const SizedBox(height: 12),
          ],
          if (earlier.isNotEmpty) ...[
            Text('Earlier', style: theme.textTheme.titleSmall),
            for (final s in earlier)
              _StopTile(
                stop: s,
                me: me,
                amLeader: amLeader,
                proposer: nameOf[s.proposedBy],
                onVote: null,
                onStatus: null,
              ),
          ],
        ],
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
              content: Text('Set a destination (or get a fix) first.'),
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
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  '${category.label} along the way',
                  style: theme.textTheme.titleLarge,
                ),
              ),
              if (found == null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'Place suggestions are not available right now (offline, '
                    "or today's free lookups are used up).",
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              if (found != null && found.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text('Nothing of that kind near the route.'),
                ),
              if (found != null && found.isNotEmpty)
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: found.length > 12 ? 12 : found.length,
                    itemBuilder: (_, i) {
                      final s = found[i];
                      final p = s.place;
                      final bits = <String>[
                        '${formatDistance(s.detourM, units)} off route',
                        if (p.rating != null)
                          '★ ${p.rating!.toStringAsFixed(1)}',
                        if (p.openNow == true) 'Open now',
                        if (p.openNow == false) 'Closed',
                      ];
                      return ListTile(
                        leading: Icon(stopIcon(category)),
                        title: Text(p.name),
                        subtitle: Text(bits.join(' · ')),
                        trailing: const Text('Propose'),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          unawaited(
                            repo.proposeStop(
                              id,
                              category: category,
                              name: p.name,
                              lat: p.location.lat,
                              lon: p.location.lon,
                              placeId: p.placeId,
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ListTile(
                leading: const Icon(Icons.my_location),
                title: Text('${category.label} stop where I am'),
                subtitle: const Text('Pin my current position'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final here = await _myPosition();
                  if (here == null) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('No position fix yet.')),
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
              const SizedBox(height: 8),
            ],
          ),
        );
      },
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
    final theme = Theme.of(context);
    final s = stop;
    final mine = me == null ? null : s.votes[me];
    final statusLabel = switch (s.status) {
      StopStatus.proposed => null,
      StopStatus.accepted => 'Accepted',
      StopStatus.rejected => 'Rejected',
      StopStatus.done => 'Done',
    };
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(stopIcon(s.category)),
        title: Text(s.name),
        subtitle: Text(
          [
            s.category.label,
            if (proposer case final who?)
              'by ${s.proposedBy == me ? 'you' : who}',
            ?statusLabel,
          ].join(' · '),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Yes',
              visualDensity: VisualDensity.compact,
              onPressed: onVote == null
                  ? null
                  : () => onVote!(mine == 1 ? 0 : 1),
              icon: Icon(
                mine == 1 ? Icons.thumb_up : Icons.thumb_up_outlined,
                size: 20,
                color: mine == 1 ? theme.colorScheme.primary : null,
              ),
            ),
            Text('${s.upVotes}', style: theme.textTheme.labelMedium),
            IconButton(
              tooltip: 'No',
              visualDensity: VisualDensity.compact,
              onPressed: onVote == null
                  ? null
                  : () => onVote!(mine == -1 ? 0 : -1),
              icon: Icon(
                mine == -1 ? Icons.thumb_down : Icons.thumb_down_outlined,
                size: 20,
                color: mine == -1 ? theme.colorScheme.error : null,
              ),
            ),
            Text('${s.downVotes}', style: theme.textTheme.labelMedium),
            if (amLeader && onStatus != null)
              PopupMenuButton<StopStatus>(
                tooltip: 'Leader',
                onSelected: onStatus,
                itemBuilder: (_) => [
                  if (s.status == StopStatus.proposed)
                    const PopupMenuItem(
                      value: StopStatus.accepted,
                      child: Text('Accept'),
                    ),
                  if (s.status == StopStatus.proposed)
                    const PopupMenuItem(
                      value: StopStatus.rejected,
                      child: Text('Reject'),
                    ),
                  if (s.status == StopStatus.accepted)
                    const PopupMenuItem(
                      value: StopStatus.done,
                      child: Text('Mark done'),
                    ),
                  if (s.status == StopStatus.accepted)
                    const PopupMenuItem(
                      value: StopStatus.proposed,
                      child: Text('Back to proposed'),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
