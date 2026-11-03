import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/ui/ui.dart';
import '../../profile/profile_repo.dart';
import '../audio/convoy_audio_session.dart';
import '../widgets/member_names.dart';
import 'chat_controller.dart';
import 'voice_notes.dart';

/// Voice-note-first chat for one convoy (docs/01 §4.6). Drivers listen;
/// passengers type and record.
class ConvoyChatScreen extends ConsumerStatefulWidget {
  const ConvoyChatScreen({super.key, required this.convoyId});

  final String convoyId;

  @override
  ConsumerState<ConvoyChatScreen> createState() => _ConvoyChatScreenState();
}

class _ConvoyChatScreenState extends ConsumerState<ConvoyChatScreen> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatControllerProvider(widget.convoyId));
    final c = ref.read(chatControllerProvider(widget.convoyId).notifier);
    final driving = ref.watch(isDrivingNowProvider);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat'),
        actions: [
          IconButton(
            tooltip: state.readAloud
                ? 'Mute read-aloud'
                : 'Read messages aloud',
            icon: Icon(
              state.readAloud ? Icons.record_voice_over : Icons.voice_over_off,
            ),
            onPressed: () {
              Haptics.select();
              c.setReadAloud(!state.readAloud);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: state.messages.isEmpty
                ? const Center(
                    child: EmptyState(
                      kicker: 'Chat',
                      headline: 'No messages yet.',
                      body:
                          'Voice notes play in every car. Drivers hear text '
                          'read aloud.',
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(
                      Space.gutter,
                      Space.sm,
                      Space.gutter,
                      Space.sm,
                    ),
                    itemCount: state.messages.length,
                    itemBuilder: (context, i) {
                      final m = state.messages[state.messages.length - 1 - i];
                      return _Bubble(
                        convoyId: widget.convoyId,
                        message: m,
                        onPlay: c.play,
                      );
                    },
                  ),
          ),
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.gutter,
                0,
                Space.gutter,
                Space.sm,
              ),
              child: Text(
                state.error!,
                style: context.caption.copyWith(color: scheme.error),
              ),
            ),
          if (driving)
            Padding(
              key: const Key('driver-banner'),
              padding: const EdgeInsets.all(Space.lg),
              child: Text(
                'Passengers type; drivers listen.',
                textAlign: TextAlign.center,
                style: context.bodyMuted,
              ),
            )
          else
            _Composer(controller: _text, state: state, chat: c),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.state,
    required this.chat,
  });

  final TextEditingController controller;
  final ChatState state;
  final ChatController chat;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const target = BoxConstraints.tightFor(
      width: Sizes.touch,
      height: Sizes.touch,
    );
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          Space.xs,
          Space.gutter,
          Space.sm,
        ),
        child: StateSwitcher(
          child: state.recording
              ? Row(
                  key: const ValueKey('recording'),
                  children: [
                    Expanded(
                      child: Row(
                        key: const Key('recording-label'),
                        children: [
                          PulsingDot(color: scheme.error, size: 8),
                          const SizedBox(width: Space.xs),
                          Text('Recording · ', style: context.title),
                          AnimatedNumber(
                            value: state.recordingMs / 1000,
                            style: context.title,
                            suffix: ' s',
                            duration: Motion.reveal,
                          ),
                          const SizedBox(width: Space.sm),
                          Text('Max 20 seconds', style: context.caption),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cancel',
                      constraints: target,
                      icon: const Icon(Icons.delete_outline),
                      onPressed: chat.cancelRecording,
                    ),
                    const SizedBox(width: Space.xs),
                    SizedBox(
                      height: Sizes.touch,
                      child: FilledButton.icon(
                        key: const Key('send-voice'),
                        onPressed: () {
                          Haptics.success();
                          chat.stopRecordingAndSend();
                        },
                        icon: const Icon(Icons.send),
                        label: const Text('Send'),
                      ),
                    ),
                  ],
                )
              : Row(
                  key: const ValueKey('idle'),
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('chat-input'),
                        controller: controller,
                        decoration: const InputDecoration(
                          hintText: 'Message the convoy',
                        ),
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (v) {
                          chat.sendText(v);
                          controller.clear();
                        },
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    IconButton.filledTonal(
                      key: const Key('record-voice'),
                      tooltip: 'Record a voice note',
                      constraints: target,
                      icon: const Icon(Icons.mic),
                      onPressed: () {
                        Haptics.select();
                        chat.startRecording();
                      },
                    ),
                    const SizedBox(width: Space.xs),
                    IconButton.filled(
                      key: const Key('send-text'),
                      tooltip: 'Send',
                      constraints: target,
                      icon: const Icon(Icons.send),
                      onPressed: () {
                        chat.sendText(controller.text);
                        controller.clear();
                      },
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _Bubble extends ConsumerWidget {
  const _Bubble({
    required this.convoyId,
    required this.message,
    required this.onPlay,
  });

  final String convoyId;
  final ChatMessage message;
  final Future<void> Function(VoiceNote) onPlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final names =
        ref.watch(convoyMemberNamesProvider(convoyId)).value ?? const {};
    // Member name first, then a cached profile handle, never a UUID prefix.
    final name = message.mine
        ? 'You'
        : names[message.from] ??
              ref.watch(profileProvider(message.from)).value?.handle ??
              'Someone';
    final bg = message.mine
        ? scheme.primaryContainer
        : scheme.surfaceContainerHigh;
    final fg = message.mine ? scheme.onPrimaryContainer : scheme.onSurface;
    return Align(
      alignment: message.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Reveal(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: Space.xs),
          padding: const EdgeInsets.symmetric(
            horizontal: Space.md,
            vertical: Space.sm,
          ),
          constraints: const BoxConstraints(maxWidth: 320),
          decoration: BoxDecoration(color: bg, borderRadius: Radii.tileRadius),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: context.caption.copyWith(
                  color: fg.withValues(alpha: 0.8),
                ),
              ),
              if (message.isVoice)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton.filledTonal(
                      tooltip: 'Play',
                      constraints: const BoxConstraints.tightFor(
                        width: Sizes.touch,
                        height: Sizes.touch,
                      ),
                      icon: const Icon(Icons.play_arrow),
                      onPressed: () {
                        Haptics.tap();
                        onPlay(message.voice!);
                      },
                    ),
                    const SizedBox(width: Space.sm),
                    Text(
                      'Voice note · '
                      '${(message.voice!.durationMs / 1000).toStringAsFixed(0)} s',
                      style: context.label.copyWith(color: fg),
                    ),
                  ],
                )
              else
                Text(
                  message.text ?? '',
                  style: context.body.copyWith(color: fg),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
