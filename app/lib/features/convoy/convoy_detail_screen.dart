import 'dart:async';

import 'package:drivalry_scoring/drivalry_scoring.dart'
    show SpeedUnits, mpsToKmh, mpsToMph;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/ui/ui.dart';
import '../../config/env.dart';
import '../../data/convoy/eta.dart';
import '../../data/convoy/lost_sheep.dart';
import '../../data/google/routes_client.dart' show LatLon;
import '../../data/repos/convoy_repo.dart';
import '../../data/repos/convoy_sync.dart';
import '../../data/supabase/supabase_providers.dart';
import '../../tracking/providers.dart';
import '../../widgets/signed_in_scope.dart';
import '../../widgets/units.dart';
import 'live/convoy_live.dart';
import 'positions/peer_positions.dart';
import 'widgets/convoy_invite_sheet.dart';
import 'widgets/convoy_map.dart';
import 'widgets/convoy_ui.dart';
import 'widgets/destination_picker.dart';
import 'widgets/member_avatar.dart';
import 'widgets/talk_button.dart';

/// One convoy: the shared map is the stage, a status capsule floats over
/// it, and a sheet holds Talk, the leader's actions and the cars
/// (docs/12 §7 Convoy, audit items 9 and 14).
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
            ? (loading
                  ? const Padding(
                      padding: EdgeInsets.fromLTRB(
                        Space.gutter,
                        Space.gutter,
                        Space.gutter,
                        0,
                      ),
                      child: Column(
                        children: [
                          SkeletonTile(height: 240),
                          SizedBox(height: Space.md),
                          SkeletonTile(height: Sizes.drivingTouch),
                        ],
                      ),
                    )
                  : EmptyState(
                      kicker: 'Convoy',
                      headline: 'Convoy not found.',
                      body:
                          'Pull to refresh the Convoy tab, or ask for a new '
                          'invite.',
                      actionLabel: 'Back to convoys',
                      onAction: () => context.go(Routes.convoy),
                    ))
            : ConvoyDetailBody(convoy: convoy),
      ),
    );
  }
}

/// The map, capsule and sheet without the sign-in gate, for tests.
class ConvoyDetailBody extends ConsumerWidget {
  const ConvoyDetailBody({super.key, required this.convoy});
  final Convoy convoy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = convoy.id;
    // Keeps the channel, positions, ETAs and lost-sheep checks alive while
    // this screen is open (the active convoy stays live app-wide anyway).
    ref.watch(convoyLiveProvider(id));
    return Stack(
      children: [
        Positioned.fill(child: ConvoyMap(convoyId: id, showNotices: false)),
        Positioned(
          top: Space.md,
          left: Space.gutter,
          child: _StatusCapsule(convoy: convoy),
        ),
        _Sheet(convoy: convoy),
      ],
    );
  }
}

class _StatusCapsule extends ConsumerWidget {
  const _StatusCapsule({required this.convoy});
  final Convoy convoy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members =
        ref.watch(convoyMembersProvider(convoy.id)).value ?? const [];
    final present = members.where((m) => m.isPresent).length;
    return FloatingCapsule(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConvoyStatusBadge(status: convoy.status, compact: true),
          const SizedBox(width: Space.sm),
          Text(
            '$present of ${convoy.maxCars} cars',
            key: const Key('convoy-cars'),
            style: context.label,
          ),
        ],
      ),
    );
  }
}

class _Sheet extends ConsumerWidget {
  const _Sheet({required this.convoy});
  final Convoy convoy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
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
    final leaderName = members
        .where((m) => m.userId == leader)
        .firstOrNull
        ?.name;
    final dest = convoy.destination;

    return LayoutBuilder(
      builder: (context, constraints) {
        final bottomInset = MediaQuery.paddingOf(context).bottom;
        // Peek is measured, not guessed: the handle and the first row sit
        // whole above the gesture bar or home indicator on any phone
        // (docs/12 §2); half and full stay fractions of the stage.
        const half = 0.46;
        const full = 0.92;
        final peekPx =
            Space.md +
            SheetHandle.height +
            Space.lg +
            Sizes.drivingTouch +
            Space.lg +
            bottomInset;
        final height = constraints.maxHeight;
        final peek = height.isFinite && height > 0
            ? (peekPx / height).clamp(0.12, half - 0.04)
            : 0.22;
        return DraggableScrollableSheet(
          key: const Key('convoy-sheet'),
          initialChildSize: half,
          minChildSize: peek,
          maxChildSize: full,
          snap: true,
          snapSizes: [peek, half, full],
          builder: (ctx, controller) => Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: Radii.sheetRadius,
              boxShadow: [
                BoxShadow(
                  color: scheme.shadow.withValues(alpha: 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: _sheetBody(
              context,
              ref,
              controller,
              amLeader: amLeader,
              leaderName: leaderName,
              dest: dest,
              present: present,
              me: me,
              leader: leader,
              positions: positions,
              lead: lead,
              etas: etas,
              lost: lost,
              units: units,
              bottomInset: bottomInset,
            ),
          ),
        );
      },
    );
  }

  Widget _sheetBody(
    BuildContext context,
    WidgetRef ref,
    ScrollController controller, {
    required bool amLeader,
    required String? leaderName,
    required Destination? dest,
    required List<ConvoyMember> present,
    required String? me,
    required String? leader,
    required Map<String, PeerPosition> positions,
    required PeerPosition? lead,
    required Map<String, EtaInfo> etas,
    required Map<String, LostSheep> lost,
    required SpeedUnits units,
    required double bottomInset,
  }) {
    return ListView(
      controller: controller,
      padding: EdgeInsets.fromLTRB(
        Space.gutter,
        Space.md,
        Space.gutter,
        Space.xl + bottomInset,
      ),
      children: [
        const SheetHandle(),
        const SizedBox(height: Space.lg),
        ..._primaryAction(context, ref, amLeader, leaderName),
        if (amLeader && convoy.isActive) ...[
          const SizedBox(height: Space.md),
          Row(
            children: [
              Expanded(
                child: PairedAction(
                  label: 'Regroup here',
                  icon: Icons.group_work_outlined,
                  onPressed: () => _regroupHere(context, ref),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: PairedAction(
                  label: dest == null ? 'Set destination' : 'Move destination',
                  icon: Icons.flag_outlined,
                  onPressed: () => _pickDestination(context, ref),
                ),
              ),
            ],
          ),
        ],
        if (amLeader && convoy.status == ConvoyStatus.planning) ...[
          const SizedBox(height: Space.sm),
          SecondaryButton(
            label: dest == null ? 'Set destination' : 'Move destination',
            icon: Icons.flag_outlined,
            onPressed: () => _pickDestination(context, ref),
          ),
        ],
        const SizedBox(height: Space.xl),
        const Kicker('Cars'),
        if (!Env.hasGoogleMaps) ...[
          const SizedBox(height: Space.sm),
          Text(
            'No map in this version. Every car is listed here.',
            style: context.caption,
          ),
        ],
        const SizedBox(height: Space.xs),
        if (present.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.md),
            child: Text(
              'No cars yet. Share the invite.',
              style: context.bodyMuted,
            ),
          ),
        for (final m in present)
          _MemberRow(
            member: m,
            isMe: m.userId == me,
            isLeader: m.userId == leader,
            position: positions[m.userId],
            leaderPosition: lead,
            eta: etas[m.userId],
            lost: lost.containsKey(m.userId),
            units: units,
          ),
      ],
    );
  }

  List<Widget> _primaryAction(
    BuildContext context,
    WidgetRef ref,
    bool amLeader,
    String? leaderName,
  ) {
    final id = convoy.id;
    switch (convoy.status) {
      case ConvoyStatus.active:
        return [TalkButton(convoyId: id)];
      case ConvoyStatus.planning:
        if (amLeader) {
          return [
            PrimaryButton(
              key: const Key('start-convoy'),
              label: 'Start trip',
              icon: Icons.play_arrow_rounded,
              onPressed: () => ref
                  .read(convoyRepoProvider)
                  .setStatus(id, ConvoyStatus.active),
            ),
          ];
        }
        return [
          Text(
            leaderName == null
                ? 'Waiting for the leader to start.'
                : 'Waiting for $leaderName to start.',
            style: context.bodyMuted,
          ),
        ];
      case ConvoyStatus.ended:
        return [
          PrimaryButton(
            label: 'See the recap',
            icon: Icons.auto_awesome_outlined,
            onPressed: () => context.push(Routes.convoyRecap(id)),
          ),
        ];
    }
  }

  Future<void> _pickDestination(BuildContext context, WidgetRef ref) async {
    final d = await showDestinationPicker(context);
    if (d != null) {
      await ref.read(convoyRepoProvider).setDestination(convoy.id, d);
    }
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
      Haptics.success();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sent
                ? 'Regroup pin sent.'
                : 'Pin set here. It goes out when you are back online.',
          ),
        ),
      );
    }
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
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
    final style = context.label.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    // Speed and gap count to their values (docs/12 §5b, "numbers move").
    // Each entry is one unbreakable chunk; the line wraps between chunks
    // when a pill leaves it too little room on a narrow phone.
    final line = <Widget>[];
    final p = position;
    if (p == null) {
      line.add(Text(isLeader ? 'Leading' : 'No position yet', style: style));
    } else {
      final age = DateTime.now().millisecondsSinceEpoch - p.t;
      if (age > staleAfter.inMilliseconds) {
        line.add(
          Text('Last seen ${(age / 60000).round()} min ago', style: style),
        );
      } else if ((p.speed ?? 0) > 2) {
        final mph = units == SpeedUnits.mph;
        line.add(
          AnimatedNumber(
            value: mph ? mpsToMph(p.speed!) : mpsToKmh(p.speed!),
            style: style,
            suffix: ' ${unitLabel(units)}',
          ),
        );
      } else {
        line.add(Text('Stopped', style: style));
      }
      final lead = leaderPosition;
      if (isLeader) {
        line.add(Text(' · Leading', style: style));
      } else if (lead != null) {
        final d = LatLon(lead.lat, lead.lon).distanceTo(LatLon(p.lat, p.lon));
        final mi = units == SpeedUnits.mph;
        final value = mi ? d / 1609.344 : d / 1000;
        line.add(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(' · ', style: style),
              AnimatedNumber(
                value: value,
                decimals: value < 10 ? 1 : 0,
                style: style,
                suffix: mi ? ' mi back' : ' km back',
              ),
            ],
          ),
        );
      }
    }

    final e = eta;
    final pills = <Widget>[
      if (lost) const Pill('Fallen behind', tone: PillTone.warning),
      if (e != null && !lost)
        if (e.seconds < 3600)
          NumberPill(
            value: (e.seconds / 60).round(),
            prefix: e.estimated ? '~' : '',
            suffix: ' min',
            compact: true,
          )
        else
          Pill('${e.estimated ? '~' : ''}${e.label}', compact: true),
    ];

    return ConvoyRow(
      leading: MemberAvatar(
        name: member.name,
        avatarPath: member.avatarPath,
        isMe: isMe,
      ),
      title: isMe ? 'You' : member.name,
      subtitle: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: line,
      ),
      trailing: pills.isEmpty
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < pills.length; i++) ...[
                  if (i > 0) const SizedBox(height: Space.xs),
                  pills[i],
                ],
              ],
            ),
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
      tooltip: 'More',
      onSelected: (v) => _on(context, ref, v),
      itemBuilder: (_) => [
        if (amLeader)
          const PopupMenuItem(value: 'rename', child: Text('Rename')),
        if (amLeader && convoy.isActive)
          const PopupMenuItem(value: 'end', child: Text('End trip')),
        const PopupMenuItem(value: 'recap', child: Text('Recap')),
        const PopupMenuItem(value: 'leave', child: Text('Leave convoy')),
      ],
    );
  }

  Future<void> _on(BuildContext context, WidgetRef ref, String v) async {
    final repo = ref.read(convoyRepoProvider);
    switch (v) {
      case 'rename':
        final name = await showConvoySheet<String>(
          context,
          title: 'Rename convoy',
          builder: (_) => TextControllers(
            initial: [convoy.name],
            builder: (ctx, c) => Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(ctx).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: c.first,
                    autofocus: true,
                    maxLength: 40,
                    textCapitalization: TextCapitalization.sentences,
                    onSubmitted: (s) => Navigator.of(ctx).pop(s),
                  ),
                  const SizedBox(height: Space.lg),
                  PrimaryButton(
                    label: 'Save',
                    onPressed: () => Navigator.of(ctx).pop(c.first.text),
                  ),
                ],
              ),
            ),
          ),
        );
        if (name != null && name.trim().isNotEmpty) {
          await repo.rename(convoy.id, name);
        }
      case 'end':
        await _confirmEnd(context, ref);
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
    if (context.mounted) {
      Haptics.success();
      unawaited(context.push(Routes.convoyRecap(convoy.id)));
    }
  }
}
