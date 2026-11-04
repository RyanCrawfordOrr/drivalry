import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../app/ui/ui.dart';
import '../../../data/repos/convoy_models.dart';
import '../../../data/repos/convoy_sync.dart';
import '../../../widgets/signed_in_scope.dart';
import '../channel/convoy_channel.dart';
import '../widgets/convoy_ui.dart';
import '../widgets/member_avatar.dart';
import 'mesh.dart';
import 'peer_link.dart';
import 'radio_controller.dart';

/// Push-to-talk radio for one convoy (docs/10 §4). Hold the big button to
/// talk; everyone else hears you through their current audio route. A
/// driving screen: 64 targets, a `display` state word, nothing below
/// `label` (docs/12 §7).
class ConvoyRadioScreen extends ConsumerWidget {
  const ConvoyRadioScreen({
    super.key,
    required this.convoyId,
    this.autoStart = false,
  });

  final String convoyId;

  /// Start the radio as the screen opens (the Talk button's way in).
  final bool autoStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Radio')),
      body: SignedInScope(
        message: 'Sign in to talk to your convoy.',
        icon: Icons.radio_outlined,
        child: RadioBody(convoyId: convoyId, autoStart: autoStart),
      ),
    );
  }
}

/// The radio screen body without the sign-in gate, so it can be tested with
/// provider overrides.
class RadioBody extends ConsumerStatefulWidget {
  const RadioBody({super.key, required this.convoyId, this.autoStart = false});

  final String convoyId;
  final bool autoStart;

  @override
  ConsumerState<RadioBody> createState() => _RadioBodyState();
}

class _RadioBodyState extends ConsumerState<RadioBody> {
  @override
  void initState() {
    super.initState();
    if (!widget.autoStart) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final id = widget.convoyId;
      final off = ref.read(radioControllerProvider(id)).phase == RadioPhase.off;
      final channel = ref.read(convoyChannelProvider(id));
      if (off && channel != null) {
        unawaited(ref.read(radioControllerProvider(id).notifier).start());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.convoyId;
    final state = ref.watch(radioControllerProvider(id));
    final ctl = ref.read(radioControllerProvider(id).notifier);
    final channel = ref.watch(convoyChannelProvider(id));

    switch (state.phase) {
      case RadioPhase.off:
      case RadioPhase.error:
        return ConvoyNotice(
          kicker: 'Radio',
          headline: 'Radio is off.',
          body: state.error ?? 'Hold to talk, car to car. Nothing is recorded.',
          action: PrimaryButton(
            key: const Key('radio-start'),
            label: 'Start radio',
            icon: Icons.mic,
            onPressed: channel == null ? null : ctl.start,
          ),
        );
      case RadioPhase.starting:
        return const ConvoyNotice(
          kicker: 'Radio',
          headline: 'Starting…',
          body: 'Finding the other cars.',
          action: Column(
            children: [
              SkeletonTile(height: Sizes.drivingTouch),
              SizedBox(height: Space.md),
              SkeletonTile(height: Sizes.drivingTouch),
            ],
          ),
        );
      case RadioPhase.noPermission:
        return ConvoyNotice(
          kicker: 'Radio',
          headline: 'Allow the microphone.',
          body: state.permanentlyDenied
              ? 'Drivalry cannot use the mic. Turn it on in Settings.'
              : 'Talking needs the mic. It only sends while you hold the '
                    'button.',
          action: state.permanentlyDenied
              ? PrimaryButton(
                  key: const Key('radio-open-settings'),
                  label: 'Open settings',
                  icon: Icons.settings_outlined,
                  onPressed: openAppSettings,
                )
              : PrimaryButton(
                  key: const Key('radio-retry'),
                  label: 'Try again',
                  onPressed: ctl.start,
                ),
        );
      case RadioPhase.on:
        break;
    }

    final peers = state.peers.values.toList()
      ..sort((a, b) => a.peerId.compareTo(b.peerId));
    final members = ref.watch(convoyMembersProvider(id)).value ?? const [];
    final byId = {for (final m in members) m.userId: m};
    String nameOf(String peerId) => byId[peerId]?.name ?? 'Someone';
    final connected = peers.where((p) => p.state == LinkState.connected).length;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        Space.gutter,
        Space.lg,
        Space.gutter,
        pageBottomInset(context),
      ),
      children: [
        _StateWord(
          kicker: ref.watch(convoyProvider(id))?.name ?? 'Radio',
          holding: state.holding,
          talking: state.talking,
          connected: connected,
          nameOf: nameOf,
        ),
        const SizedBox(height: Space.xxl),
        Center(
          child: _PttButton(
            holding: state.holding,
            onPress: ctl.press,
            onRelease: ctl.release,
          ),
        ),
        const SizedBox(height: Space.md),
        Center(
          child: Text(
            state.holding ? 'Transmitting' : 'Hold to talk',
            style: context.title,
          ),
        ),
        const SizedBox(height: Space.xxl),
        _MuteTile(value: state.muteIncoming, onChanged: ctl.setMuteIncoming),
        const SizedBox(height: Space.section),
        EditorialSection(
          kicker: 'Cars',
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              if (peers.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.sm),
                  child: Text(
                    'No one else is on the radio yet.',
                    style: context.bodyMuted,
                  ),
                ),
              for (final p in peers)
                _PeerRow(
                  status: p,
                  member: byId[p.peerId],
                  name: nameOf(p.peerId),
                  talking: state.talking.contains(p.peerId),
                  onReconnect: () => ctl.reconnect(p.peerId),
                ),
            ],
          ),
        ),
        if (state.relayAvailable) ...[
          Text('Works across networks.', style: context.caption),
          const SizedBox(height: Space.lg),
        ],
        SecondaryButton(
          key: const Key('radio-stop'),
          label: 'Stop radio',
          icon: Icons.power_settings_new,
          onPressed: ctl.stop,
        ),
      ],
    );
  }
}

/// One `display` word for the radio's state and one line under it.
class _StateWord extends StatelessWidget {
  const _StateWord({
    required this.kicker,
    required this.holding,
    required this.talking,
    required this.connected,
    required this.nameOf,
  });

  final String kicker;
  final bool holding;
  final Set<String> talking;
  final int connected;
  final String Function(String) nameOf;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final String word;
    final String detail;
    Color? color;
    if (holding) {
      word = 'On air';
      detail = 'Everyone hears you.';
      color = scheme.error;
    } else if (talking.isNotEmpty) {
      word = 'Live';
      detail = talking.length == 1
          ? '${nameOf(talking.single)} is talking.'
          : '${talking.length} people are talking.';
      color = scheme.primary;
    } else {
      word = 'Quiet';
      detail = switch (connected) {
        0 => 'Waiting for the other cars.',
        1 => '1 car connected.',
        _ => '$connected cars connected.',
      };
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Kicker(kicker),
        const SizedBox(height: Space.sm),
        Row(
          children: [
            Text(word, style: context.display.copyWith(color: color)),
            if (color != null) ...[
              const SizedBox(width: Space.md),
              PulsingDot(color: color, size: 12),
            ],
          ],
        ),
        const SizedBox(height: Space.sm),
        StateSwitcher(
          child: Text(detail, key: ValueKey(detail), style: context.title),
        ),
      ],
    );
  }
}

/// The hold-to-talk button: pointer down transmits, up or cancel stops.
class _PttButton extends StatelessWidget {
  const _PttButton({
    required this.holding,
    required this.onPress,
    required this.onRelease,
  });

  final bool holding;
  final Future<void> Function() onPress;
  final Future<void> Function() onRelease;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = holding ? scheme.error : scheme.primary;
    return Semantics(
      button: true,
      label: 'Push to talk',
      child: Listener(
        key: const Key('ptt-button'),
        onPointerDown: (_) {
          Haptics.select();
          onPress();
        },
        onPointerUp: (_) {
          Haptics.select();
          onRelease();
        },
        onPointerCancel: (_) => onRelease(),
        child: AnimatedScale(
          scale: holding && !context.reduceMotion ? 1.06 : 1,
          duration: Motion.quick,
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: Motion.quick,
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: holding ? 32 : 12,
                  spreadRadius: holding ? 8 : 2,
                ),
              ],
            ),
            child: Icon(
              holding ? Icons.mic : Icons.mic_none,
              size: 88,
              color: holding ? scheme.onError : scheme.onPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// "Mute everyone" as a 64-tall tile with a switch; the whole row toggles.
class _MuteTile extends StatelessWidget {
  const _MuteTile({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Tile(
      onTap: () => onChanged(!value),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.gutter,
        vertical: Space.sm,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: Sizes.drivingTouch - 2 * Space.sm,
        ),
        child: Row(
          children: [
            Icon(
              value ? Icons.volume_off_outlined : Icons.volume_up_outlined,
              size: 28,
            ),
            const SizedBox(width: Space.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Mute everyone', style: context.title),
                  Text('Your mic still works', style: context.caption),
                ],
              ),
            ),
            Switch(
              key: const Key('radio-mute-incoming'),
              value: value,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _PeerRow extends StatelessWidget {
  const _PeerRow({
    required this.status,
    required this.member,
    required this.name,
    required this.talking,
    required this.onReconnect,
  });

  final PeerStatus status;
  final ConvoyMember? member;
  final String name;
  final bool talking;
  final VoidCallback onReconnect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pill = switch (status.state) {
      LinkState.connected => const Pill('Connected', tone: PillTone.positive),
      LinkState.connecting => const Pill('Connecting…'),
      LinkState.disconnected ||
      LinkState.failed ||
      LinkState.closed => const Pill('Reconnecting', tone: PillTone.warning),
    };
    final stuck =
        status.state == LinkState.failed || status.state == LinkState.closed;
    return ConvoyRow(
      leading: MemberAvatar(name: name, avatarPath: member?.avatarPath),
      title: name,
      subtitle: talking
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PulsingDot(color: scheme.primary, size: 8),
                const SizedBox(width: Space.xs),
                Text(
                  'Talking',
                  style: context.label.copyWith(color: scheme.primary),
                ),
              ],
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (stuck) ...[
            TextButton(onPressed: onReconnect, child: const Text('Retry')),
            const SizedBox(width: Space.xs),
          ],
          // Connecting… cross-fades into Connected.
          StateSwitcher(
            child: KeyedSubtree(key: ValueKey(status.state), child: pill),
          ),
        ],
      ),
    );
  }
}
