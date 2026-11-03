import 'dart:async';

import 'package:drivalry_scoring/drivalry_scoring.dart' show SpeedUnits;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/convoy/eta.dart';
import '../../data/google/routes_client.dart' show LatLon;
import '../../data/repos/convoy_repo.dart';
import '../../data/repos/convoy_sync.dart';
import '../../data/supabase/supabase_providers.dart';
import '../../tracking/providers.dart';
import '../../widgets/signed_in_scope.dart';
import '../../widgets/units.dart';
import '../friends/widgets/user_avatar.dart';
import 'live/convoy_live.dart';
import 'positions/peer_positions.dart';
import 'widgets/convoy_invite_sheet.dart';
import 'widgets/convoy_map.dart';
import 'widgets/destination_picker.dart';

/// One convoy: the shared map on top, the cars with their ETAs below, and
/// the doors to radio, stops, chat, music, games, expenses, album and recap.
class ConvoyDetailScreen extends ConsumerWidget {
  const ConvoyDetailScreen({super.key, required this.convoyId});

  final String convoyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final convoy = ref.watch(convoyProvider(convoyId));
    final loading = ref.watch(myConvoysProvider).isLoading;
    return Scaffold(
      appBar: AppBar(
        title: Text(convoy?.name ?? 'Convoy'),
        actions: [
          if (convoy != null)
            IconButton(
              tooltip: 'Invite',
              onPressed: () => showConvoyInviteSheet(context, convoy),
              icon: const Icon(Icons.person_add_alt_1_outlined),
            ),
          if (convoy != null) _Menu(convoy: convoy),
        ],
      ),
      body: SignedInScope(
        message: 'Sign in to see the convoy.',
        icon: Icons.route_outlined,
        child: convoy == null
            ? Center(
                child: loading
                    ? const CircularProgressIndicator()
                    : const Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'This convoy is not in your list. Pull to refresh '
                          'the Convoy tab, or ask for a new invite.',
                          textAlign: TextAlign.center,
                        ),
                      ),
              )
            : _Body(convoy: convoy),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.convoy});
  final Convoy convoy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = convoy.id;
    // Keeps the channel, positions, ETAs and lost-sheep checks alive while
    // this screen is open (the active convoy stays live app-wide anyway).
    ref.watch(convoyLiveProvider(id));
    return Column(
      children: [
        Expanded(flex: 5, child: ConvoyMap(convoyId: id)),
        Expanded(flex: 4, child: _Panel(convoy: convoy)),
      ],
    );
  }
}

class _Panel extends ConsumerWidget {
  const _Panel({required this.convoy});
  final Convoy convoy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final id = convoy.id;
    final me = ref.watch(currentUserIdProvider);
    final amLeader = ref.watch(amConvoyLeaderProvider(id));
    final leader = ref.watch(convoyLeaderProvider(id));
    final members = ref.watch(convoyMembersProvider(id)).value ?? const [];
    final positions = ref.watch(peerPositionsProvider(id)).value ?? const {};
    final etas = ref.watch(convoyEtasProvider(id)).value ?? const {};
    final lost = ref.watch(lostSheepProvider(id)).value ?? const {};
    final units = resolveUnits(
      ref.watch(unitsSettingProvider).value ?? UnitsSetting.auto,
    );
    final present = [
      for (final m in members)
        if (m.isPresent) m,
    ];
    final lead = leader == null ? null : positions[leader];
    final dest = convoy.destination;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        Row(
          children: [
            _StatusChip(status: convoy.status),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                dest == null
                    ? '${present.length} of ${convoy.maxCars} cars · no '
                          'destination yet'
                    : '${present.length} of ${convoy.maxCars} cars · to '
                          '${dest.name}',
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (amLeader && convoy.status == ConvoyStatus.planning)
              FilledButton.tonal(
                key: const Key('start-convoy'),
                onPressed: () => ref
                    .read(convoyRepoProvider)
                    .setStatus(id, ConvoyStatus.active),
                child: const Text('Start trip'),
              ),
            if (amLeader && convoy.isActive)
              OutlinedButton(
                onPressed: () => _confirmEnd(context, ref),
                child: const Text('End trip'),
              ),
          ],
        ),
        if (amLeader && convoy.isActive)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _regroupHere(context, ref),
                    icon: const Icon(Icons.group_work_outlined),
                    label: const Text('Regroup here'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final d = await showDestinationPicker(context);
                      if (d != null) {
                        await ref
                            .read(convoyRepoProvider)
                            .setDestination(id, d);
                      }
                    },
                    icon: const Icon(Icons.flag_outlined),
                    label: Text(dest == null ? 'Set destination' : 'Change'),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        for (final m in present)
          _MemberTile(
            member: m,
            isMe: m.userId == me,
            isLeader: m.userId == leader,
            position: positions[m.userId],
            leaderPosition: lead,
            eta: etas[m.userId],
            lost: lost.containsKey(m.userId),
            units: units,
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Action(Icons.radio_outlined, 'Radio', Routes.convoyRadio(id)),
            _Action(
              Icons.local_gas_station_outlined,
              'Stops',
              Routes.convoyStops(id),
            ),
            _Action(Icons.chat_bubble_outline, 'Chat', Routes.convoyChat(id)),
            _Action(Icons.music_note_outlined, 'Music', Routes.convoyMusic(id)),
            _Action(
              Icons.sports_esports_outlined,
              'Games',
              Routes.convoyGames(id),
            ),
            _Action(
              Icons.receipt_long_outlined,
              'Expenses',
              Routes.convoyExpenses(id),
            ),
            _Action(
              Icons.photo_library_outlined,
              'Album',
              Routes.convoyAlbum(id),
            ),
            _Action(
              Icons.auto_awesome_outlined,
              'Recap',
              Routes.convoyRecap(id),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _confirmEnd(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End the trip?'),
        content: const Text(
          'Positions stop flowing and everyone gets the recap. Stops, '
          'expenses and photos stay.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep going'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('End trip'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await ref.read(convoyRepoProvider).setStatus(convoy.id, ConvoyStatus.ended);
    if (context.mounted) context.push(Routes.convoyRecap(convoy.id));
  }

  Future<void> _regroupHere(BuildContext context, WidgetRef ref) async {
    final live = ref.read(convoyLiveProvider(convoy.id));
    if (live == null) return;
    final me = ref.read(currentUserIdProvider);
    final mine = me == null ? null : live.link.hub.latest[me];
    double? lat = mine?.lat, lon = mine?.lon;
    if (lat == null || lon == null) {
      try {
        final loc = await ref.read(trackingPortProvider).getLastKnownLocation();
        lat = loc?.lat;
        lon = loc?.lon;
      } catch (_) {}
    }
    if (lat == null || lon == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No position yet. Long-press the map instead.'),
          ),
        );
      }
      return;
    }
    final sent = await live.setRegroup(lat, lon);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sent
                ? 'Regroup pin sent.'
                : 'Pin set here; it could not be sent. Check your connection.',
          ),
        ),
      );
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final ConvoyStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color) = switch (status) {
      ConvoyStatus.active => ('On the road', theme.colorScheme.primary),
      ConvoyStatus.planning => ('Planning', theme.colorScheme.secondary),
      ConvoyStatus.ended => ('Ended', theme.colorScheme.outline),
    };
    return Chip(
      label: Text(label),
      labelStyle: theme.textTheme.labelSmall?.copyWith(color: color),
      side: BorderSide(color: color),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.isMe,
    required this.isLeader,
    required this.position,
    required this.leaderPosition,
    required this.eta,
    required this.lost,
    required this.units,
  });

  final ConvoyMember member;
  final bool isMe;
  final bool isLeader;
  final PeerPosition? position;
  final PeerPosition? leaderPosition;
  final EtaInfo? eta;
  final bool lost;
  final SpeedUnits units;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parts = <String>[];
    final p = position;
    if (p == null) {
      parts.add('No position yet');
    } else {
      final age = DateTime.now().millisecondsSinceEpoch - p.t;
      if (age > staleAfter.inMilliseconds) {
        parts.add('Last seen ${(age / 60000).round()} min ago');
      } else if ((p.speed ?? 0) > 2) {
        parts.add(formatSpeed(p.speed!, units));
      } else {
        parts.add('Stopped');
      }
      final lead = leaderPosition;
      if (lead != null && !isLeader) {
        final d = LatLon(lead.lat, lead.lon).distanceTo(LatLon(p.lat, p.lon));
        parts.add('${formatDistance(d, units)} from the leader');
      }
    }
    if (eta != null) parts.add('ETA ${eta!.estimated ? '~' : ''}${eta!.label}');
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: UserAvatar(
        name: member.name,
        avatarPath: member.avatarPath,
        radius: 18,
        highlighted: isLeader,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              isMe ? 'You' : member.name,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isLeader) ...[
            const SizedBox(width: 6),
            Icon(Icons.star, size: 14, color: theme.colorScheme.primary),
          ],
        ],
      ),
      subtitle: Text(parts.join(' · ')),
      trailing: lost
          ? Tooltip(
              message: 'Lost sheep',
              child: Icon(
                Icons.warning_amber_rounded,
                color: theme.colorScheme.error,
              ),
            )
          : null,
    );
  }
}

class _Action extends StatelessWidget {
  const _Action(this.icon, this.label, this.route);
  final IconData icon;
  final String label;
  final String route;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onPressed: () => context.push(route),
    );
  }
}

class _Menu extends ConsumerWidget {
  const _Menu({required this.convoy});
  final Convoy convoy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final amLeader = ref.watch(amConvoyLeaderProvider(convoy.id));
    return PopupMenuButton<String>(
      onSelected: (v) => _on(context, ref, v),
      itemBuilder: (_) => [
        if (amLeader)
          const PopupMenuItem(value: 'rename', child: Text('Rename')),
        const PopupMenuItem(value: 'recap', child: Text('Recap')),
        const PopupMenuItem(value: 'leave', child: Text('Leave convoy')),
      ],
    );
  }

  Future<void> _on(BuildContext context, WidgetRef ref, String v) async {
    final repo = ref.read(convoyRepoProvider);
    switch (v) {
      case 'rename':
        final controller = TextEditingController(text: convoy.name);
        final name = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Rename convoy'),
            content: TextField(
              controller: controller,
              autofocus: true,
              maxLength: 40,
              onSubmitted: (s) => Navigator.of(ctx).pop(s),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(controller.text),
                child: const Text('Save'),
              ),
            ],
          ),
        );
        controller.dispose();
        if (name != null) await repo.rename(convoy.id, name);
      case 'recap':
        if (context.mounted) context.push(Routes.convoyRecap(convoy.id));
      case 'leave':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Leave this convoy?'),
            content: const Text(
              'You drop off the shared map and the radio. Rejoin with the '
              'invite code any time.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Stay'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Leave'),
              ),
            ],
          ),
        );
        if (ok == true) {
          await repo.leave(convoy.id);
          if (context.mounted) context.go(Routes.convoy);
        }
    }
  }
}
