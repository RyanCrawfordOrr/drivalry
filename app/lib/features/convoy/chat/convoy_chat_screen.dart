import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/profile_repo.dart';
import '../audio/convoy_audio_session.dart';
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Convoy chat'),
        actions: [
          IconButton(
            tooltip: state.readAloud ? 'Read aloud: on' : 'Read aloud: off',
            icon: Icon(
              state.readAloud ? Icons.record_voice_over : Icons.voice_over_off,
            ),
            onPressed: () => c.setReadAloud(!state.readAloud),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: state.messages.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'Nothing yet. Voice notes play in every car; text is '
                        'read aloud to drivers.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(12),
                    itemCount: state.messages.length,
                    itemBuilder: (context, i) {
                      final m = state.messages[state.messages.length - 1 - i];
                      return _Bubble(message: m, onPlay: c.play);
                    },
                  ),
          ),
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                state.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (driving)
            const Padding(
              key: Key('driver-banner'),
              padding: EdgeInsets.all(12),
              child: Text(
                'Passengers type; drivers listen.',
                textAlign: TextAlign.center,
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
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: state.recording
                  ? Text(
                      'Recording… ${(state.recordingMs / 1000).toStringAsFixed(0)} s '
                      '(max 20)',
                      key: const Key('recording-label'),
                    )
                  : TextField(
                      key: const Key('chat-input'),
                      controller: controller,
                      decoration: const InputDecoration(
                        hintText: 'Message the convoy',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (v) {
                        chat.sendText(v);
                        controller.clear();
                      },
                    ),
            ),
            const SizedBox(width: 8),
            if (state.recording) ...[
              IconButton(
                tooltip: 'Cancel',
                icon: const Icon(Icons.delete_outline),
                onPressed: chat.cancelRecording,
              ),
              FilledButton.icon(
                key: const Key('send-voice'),
                onPressed: chat.stopRecordingAndSend,
                icon: const Icon(Icons.send),
                label: const Text('Send'),
              ),
            ] else ...[
              IconButton.filledTonal(
                key: const Key('record-voice'),
                tooltip: 'Record a voice note',
                icon: const Icon(Icons.mic),
                onPressed: chat.startRecording,
              ),
              IconButton.filled(
                key: const Key('send-text'),
                tooltip: 'Send',
                icon: const Icon(Icons.send),
                onPressed: () {
                  chat.sendText(controller.text);
                  controller.clear();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Bubble extends ConsumerWidget {
  const _Bubble({required this.message, required this.onPlay});

  final ChatMessage message;
  final Future<void> Function(VoiceNote) onPlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final name = message.mine
        ? 'You'
        : ref.watch(profileProvider(message.from)).value?.handle ??
              message.from.substring(0, message.from.length.clamp(0, 6));
    final bg = message.mine
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    return Align(
      alignment: message.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: theme.textTheme.labelSmall),
            if (message.isVoice)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.play_arrow),
                    onPressed: () => onPlay(message.voice!),
                  ),
                  Text(
                    'Voice note · ${(message.voice!.durationMs / 1000).toStringAsFixed(0)} s',
                  ),
                ],
              )
            else
              Text(message.text ?? ''),
          ],
        ),
      ),
    );
  }
}
