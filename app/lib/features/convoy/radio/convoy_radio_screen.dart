import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../widgets/signed_in_scope.dart';
import '../channel/convoy_channel.dart';
import '../widgets/member_names.dart';
import 'mesh.dart';
import 'peer_link.dart';
import 'radio_controller.dart';
import 'radio_stats.dart';

/// Push-to-talk radio for one convoy (docs/10 §4). Hold the big button to
/// talk; everyone else hears you through their current audio route.
class ConvoyRadioScreen extends ConsumerWidget {
  const ConvoyRadioScreen({super.key, required this.convoyId});

  final String convoyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Radio')),
      body: SignedInScope(
        message: 'Sign in to talk to your convoy.',
        icon: Icons.radio_outlined,
        child: RadioBody(convoyId: convoyId),
      ),
    );
  }
}

/// The radio screen body without the sign-in gate, so it can be tested with
/// provider overrides.
class RadioBody extends ConsumerWidget {
  const RadioBody({super.key, required this.convoyId});

  final String convoyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(radioControllerProvider(convoyId));
    final ctl = ref.read(radioControllerProvider(convoyId).notifier);
    final channel = ref.watch(convoyChannelProvider(convoyId));
    final theme = Theme.of(context);

    switch (state.phase) {
      case RadioPhase.off:
      case RadioPhase.error:
        return _Centered(
          icon: Icons.radio_outlined,
          title: 'Radio is off',
          body:
              state.error ??
              'Start the radio to talk car to car. Audio goes straight '
                  'between phones; nothing is recorded.',
          action: FilledButton.icon(
            key: const Key('radio-start'),
            onPressed: channel == null ? null : ctl.start,
            icon: const Icon(Icons.power_settings_new),
            label: const Text('Start radio'),
          ),
        );
      case RadioPhase.starting:
        return const Center(child: CircularProgressIndicator());
      case RadioPhase.noPermission:
        return _Centered(
          icon: Icons.mic_off_outlined,
          title: 'Microphone needed',
          body: state.permanentlyDenied
              ? 'The microphone is blocked for Drivalry. Allow it in the '
                    'system settings to use the radio.'
              : 'The radio needs the microphone to transmit when you hold '
                    'the button. Nothing is sent otherwise.',
          action: state.permanentlyDenied
              ? OutlinedButton.icon(
                  key: const Key('radio-open-settings'),
                  onPressed: openAppSettings,
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('Open settings'),
                )
              : FilledButton(
                  key: const Key('radio-retry'),
                  onPressed: ctl.start,
                  child: const Text('Try again'),
                ),
        );
      case RadioPhase.on:
        break;
    }

    final peers = state.peers.values.toList()
      ..sort((a, b) => a.peerId.compareTo(b.peerId));
    final relayed = ref.watch(relayedBytesProvider(convoyId)).value ?? 0;
    final names =
        ref.watch(convoyMemberNamesProvider(convoyId)).value ?? const {};

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _TalkingBanner(talking: state.talking, holding: state.holding),
        const SizedBox(height: 16),
        Center(
          child: _PttButton(
            holding: state.holding,
            onPress: ctl.press,
            onRelease: ctl.release,
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            state.holding ? 'Transmitting' : 'Hold to talk',
            style: theme.textTheme.labelLarge,
          ),
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          key: const Key('radio-mute-incoming'),
          title: const Text('Mute everyone'),
          subtitle: const Text('You can still transmit'),
          value: state.muteIncoming,
          onChanged: ctl.setMuteIncoming,
        ),
        const Divider(),
        Text('Cars', style: theme.textTheme.titleMedium),
        if (peers.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No one else is on the radio yet. Members join as they open '
              'this screen or start the radio.',
            ),
          ),
        for (final p in peers)
          _PeerTile(
            status: p,
            name: memberLabel(names, p.peerId),
            talking: state.talking.contains(p.peerId),
            onReconnect: () => ctl.reconnect(p.peerId),
          ),
        const SizedBox(height: 12),
        Text(
          state.relayAvailable
              ? 'Relay available for phones that cannot connect directly. '
                    'Relayed so far: ${_bytes(relayed)}.'
              : 'No relay configured: cars that cannot connect directly '
                    'will show as failed.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          key: const Key('radio-stop'),
          onPressed: ctl.stop,
          icon: const Icon(Icons.power_settings_new),
          label: const Text('Stop radio'),
        ),
      ],
    );
  }
}

class _TalkingBanner extends StatelessWidget {
  const _TalkingBanner({required this.talking, required this.holding});

  final Set<String> talking;
  final bool holding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String text;
    if (holding) {
      text = 'You are talking';
    } else if (talking.isEmpty) {
      text = 'Quiet';
    } else {
      text =
          '${talking.length == 1 ? 'Someone is' : '${talking.length} people are'} talking';
    }
    return Card(
      color: holding || talking.isNotEmpty
          ? theme.colorScheme.primaryContainer
          : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              holding || talking.isNotEmpty
                  ? Icons.graphic_eq
                  : Icons.volume_mute_outlined,
            ),
            const SizedBox(width: 12),
            Text(text, style: theme.textTheme.titleMedium),
          ],
        ),
      ),
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
    return Semantics(
      button: true,
      label: 'Push to talk',
      child: Listener(
        key: const Key('ptt-button'),
        onPointerDown: (_) => onPress(),
        onPointerUp: (_) => onRelease(),
        onPointerCancel: (_) => onRelease(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: holding ? scheme.error : scheme.primary,
            boxShadow: [
              BoxShadow(
                color: (holding ? scheme.error : scheme.primary).withValues(
                  alpha: 0.4,
                ),
                blurRadius: holding ? 32 : 12,
                spreadRadius: holding ? 8 : 2,
              ),
            ],
          ),
          child: Icon(
            holding ? Icons.mic : Icons.mic_none,
            size: 88,
            color: scheme.onPrimary,
          ),
        ),
      ),
    );
  }
}

class _PeerTile extends StatelessWidget {
  const _PeerTile({
    required this.status,
    required this.name,
    required this.talking,
    required this.onReconnect,
  });

  final PeerStatus status;
  final String name;
  final bool talking;
  final VoidCallback onReconnect;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status.state) {
      LinkState.connected when status.relayed => ('Relayed', Colors.orange),
      LinkState.connected => ('Direct', Colors.green),
      LinkState.connecting => ('Connecting', Colors.blueGrey),
      LinkState.disconnected => ('Reconnecting', Colors.orange),
      LinkState.failed => ('Failed', Colors.red),
      LinkState.closed => ('Closed', Colors.grey),
    };
    return ListTile(
      leading: Icon(
        talking ? Icons.graphic_eq : Icons.directions_car_outlined,
        color: color,
      ),
      title: Text(name),
      subtitle: Text(
        '$label · ${status.dataOpen ? 'data on' : 'data off'} · '
        '↑${_bytes(status.bytesSent)} ↓${_bytes(status.bytesReceived)}',
      ),
      trailing: status.state == LinkState.connected
          ? null
          : IconButton(
              tooltip: 'Reconnect',
              icon: const Icon(Icons.refresh),
              onPressed: onReconnect,
            ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(body, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            action,
          ],
        ),
      ),
    );
  }
}

String _bytes(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
}
