import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/env.dart';
import '../../../data/spotify/spotify_client.dart';
import 'dj_controller.dart';

/// Music for one convoy: Spotify Jam / Apple Music SharePlay deep links, and
/// Convoy DJ (docs/01 §4.6, docs/10 §6). Reached from inside a convoy, which
/// already requires sign-in, so there is no scope gate here.
class ConvoyMusicScreen extends ConsumerWidget {
  const ConvoyMusicScreen({super.key, required this.convoyId});

  final String convoyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Music')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _JamCard(),
          const SizedBox(height: 16),
          _DjSection(convoyId: convoyId),
        ],
      ),
    );
  }
}

class _JamCard extends StatelessWidget {
  const _JamCard();

  @override
  Widget build(BuildContext context) {
    final ios = !kIsWeb && Platform.isIOS;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Everyone on one playlist',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Spotify Jam lets the whole convoy add to one queue. Start a Jam '
              'in Spotify and share the invite in chat.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.tonalIcon(
                  key: const Key('open-spotify'),
                  onPressed: () => _open(
                    Uri.parse('spotify:'),
                    fallback: Uri.parse('https://open.spotify.com/'),
                  ),
                  icon: const Icon(Icons.play_circle_outline),
                  label: const Text('Open Spotify'),
                ),
                if (ios)
                  OutlinedButton.icon(
                    onPressed: () => _open(
                      Uri.parse('music://'),
                      fallback: Uri.parse('https://music.apple.com/'),
                    ),
                    icon: const Icon(Icons.group_outlined),
                    label: const Text('Apple Music SharePlay'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(Uri app, {required Uri fallback}) async {
    try {
      if (await canLaunchUrl(app)) {
        await launchUrl(app, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (_) {}
    await launchUrl(fallback, mode: LaunchMode.externalApplication);
  }
}

class _DjSection extends ConsumerStatefulWidget {
  const _DjSection({required this.convoyId});
  final String convoyId;

  @override
  ConsumerState<_DjSection> createState() => _DjSectionState();
}

class _DjSectionState extends ConsumerState<_DjSection> {
  final _search = TextEditingController();
  List<SpotifyTrack> _results = const [];
  bool _searching = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!Env.hasSpotify) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.radio_outlined),
          title: const Text('Convoy DJ'),
          subtitle: const Text(
            'Not available in this build: no Spotify client id is configured '
            '(docs/09-auth-setup.md §8).',
          ),
        ),
      );
    }
    final s = ref.watch(djControllerProvider(widget.convoyId));
    final c = ref.read(djControllerProvider(widget.convoyId).notifier);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Convoy DJ', style: theme.textTheme.titleMedium),
                ),
                if (s.spotifyConnected)
                  TextButton(
                    onPressed: c.disconnectSpotify,
                    child: const Text('Disconnect'),
                  )
                else
                  FilledButton.icon(
                    key: const Key('connect-spotify'),
                    onPressed: c.connectSpotify,
                    icon: const Icon(Icons.link),
                    label: const Text('Connect Spotify'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'One phone is the DJ; every car plays the same track in lockstep. '
              'Needs Spotify Premium and a spot on the Drivalry allowlist.',
              style: theme.textTheme.bodySmall,
            ),
            if (s.error != null) ...[
              const SizedBox(height: 8),
              Text(
                s.error!,
                key: const Key('dj-error'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            if (s.peers.isEmpty)
              Text(
                'No other cars connected yet. DJ starts once the radio mesh is up.',
                style: theme.textTheme.bodySmall,
              ),
            Row(
              children: [
                Chip(
                  label: Text(
                    s.dj == null
                        ? 'No DJ yet'
                        : s.isDj
                        ? 'You are the DJ'
                        : 'DJ: ${_short(s.dj!)}',
                  ),
                ),
                const Spacer(),
                if (s.isDj)
                  TextButton(
                    onPressed: c.release,
                    child: const Text('Step down'),
                  )
                else
                  FilledButton.tonal(
                    key: const Key('claim-dj'),
                    onPressed: s.spotifyConnected ? c.claim : null,
                    child: const Text('Be the DJ'),
                  ),
              ],
            ),
            if (s.current != null) ...[
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.graphic_eq),
                title: Text(s.current!.name),
                subtitle: Text(s.current!.artists),
                trailing: TextButton(
                  onPressed: c.voteSkip,
                  child: Text(
                    s.skipVotes == 0 ? 'Vote to skip' : 'Skip (${s.skipVotes})',
                  ),
                ),
              ),
            ],
            if (s.isDj) ...[
              const Divider(),
              TextField(
                controller: _search,
                decoration: InputDecoration(
                  hintText: 'Search tracks',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (q) async {
                  setState(() => _searching = true);
                  final r = await c.search(q);
                  if (mounted) {
                    setState(() {
                      _results = r;
                      _searching = false;
                    });
                  }
                },
              ),
              for (final t in _results)
                ListTile(
                  dense: true,
                  title: Text(t.name),
                  subtitle: Text(t.artists),
                  trailing: IconButton(
                    icon: const Icon(Icons.playlist_add),
                    onPressed: () => c.addToQueue(t),
                  ),
                ),
              if (s.queue.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Up next', style: theme.textTheme.labelLarge),
                for (final t in s.queue)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.queue_music),
                    title: Text(t.name),
                    subtitle: Text(t.artists),
                    trailing: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => c.removeFromQueue(t.uri),
                    ),
                  ),
              ],
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: s.queue.isEmpty ? null : () => c.playNext(),
                icon: const Icon(Icons.skip_next),
                label: Text(
                  s.current == null ? 'Start the queue' : 'Next track',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _short(String id) => id.length > 8 ? id.substring(0, 8) : id;
}
