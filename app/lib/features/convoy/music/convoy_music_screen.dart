import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/ui/ui.dart';
import '../../../config/env.dart';
import '../../../data/spotify/spotify_client.dart';
import '../widgets/convoy_ui.dart';
import '../widgets/member_names.dart';
import 'dj_controller.dart';

/// Music for one convoy: Spotify Jam / Apple Music deep links, and Convoy DJ
/// (docs/01 §4.6, docs/10 §6). Reached from inside a convoy, which already
/// requires sign-in, so there is no scope gate here.
class ConvoyMusicScreen extends ConsumerWidget {
  const ConvoyMusicScreen({
    super.key,
    required this.convoyId,
    @visibleForTesting this.djAvailable,
  });

  final String convoyId;

  /// Whether Convoy DJ is offered; the build's Spotify id decides. Tests set
  /// it to render the DJ states without a Spotify app id.
  final bool? djAvailable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Music')),
      body: ListView(
        padding: EdgeInsets.only(
          top: Space.lg,
          bottom: pageBottomInset(context),
        ),
        children: [
          const EditorialSection(kicker: 'Together', child: _JamTile()),
          EditorialSection(
            kicker: 'Convoy DJ',
            child: _DjSection(
              convoyId: convoyId,
              available: djAvailable ?? Env.hasSpotify,
            ),
          ),
        ],
      ),
    );
  }
}

class _JamTile extends StatelessWidget {
  const _JamTile();

  @override
  Widget build(BuildContext context) {
    final ios = !kIsWeb && Platform.isIOS;
    return Reveal(
      child: Tile(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Everyone on one playlist', style: context.title),
            const SizedBox(height: Space.sm),
            Text(
              'Start a Jam in Spotify and share the invite in chat.',
              style: context.bodyMuted,
            ),
            const SizedBox(height: Space.lg),
            SecondaryButton(
              key: const Key('open-spotify'),
              label: 'Open Spotify',
              icon: Icons.play_circle_outline,
              onPressed: () => _open(
                Uri.parse('spotify:'),
                fallback: Uri.parse('https://open.spotify.com/'),
              ),
            ),
            if (ios) ...[
              const SizedBox(height: Space.sm),
              SecondaryButton(
                label: 'Open Apple Music',
                icon: Icons.group_outlined,
                onPressed: () => _open(
                  Uri.parse('music://'),
                  fallback: Uri.parse('https://music.apple.com/'),
                ),
              ),
            ],
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
  const _DjSection({required this.convoyId, required this.available});
  final String convoyId;
  final bool available;

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
    final scheme = Theme.of(context).colorScheme;
    if (!widget.available) {
      return Reveal(
        child: Tile(
          child: Row(
            children: [
              Icon(Icons.radio_outlined, size: 28, color: scheme.primary),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Convoy DJ', style: context.title),
                    const SizedBox(height: Space.xs),
                    Text(
                      "Convoy DJ isn't available in this version yet.",
                      style: context.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    final s = ref.watch(djControllerProvider(widget.convoyId));
    final c = ref.read(djControllerProvider(widget.convoyId).notifier);
    final names =
        ref.watch(convoyMemberNamesProvider(widget.convoyId)).value ??
        const <String, String>{};
    final djPill = s.dj == null
        ? const Pill('No DJ yet')
        : s.isDj
        ? const Pill('You are the DJ', tone: PillTone.live)
        : Pill('DJ: ${memberLabel(names, s.dj!)}', tone: PillTone.primary);

    return Reveal(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Tile(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'One phone picks, every car plays in step',
                        style: context.title,
                      ),
                    ),
                    const SizedBox(width: Space.md),
                    djPill,
                  ],
                ),
                const SizedBox(height: Space.sm),
                Text(
                  'Needs Spotify Premium and an invite from Ryan.',
                  style: context.caption,
                ),
                if (s.error != null) ...[
                  const SizedBox(height: Space.sm),
                  Text(
                    s.error!,
                    key: const Key('dj-error'),
                    style: context.caption.copyWith(color: scheme.error),
                  ),
                ],
                if (s.peers.isEmpty) ...[
                  const SizedBox(height: Space.sm),
                  Text(
                    'Waiting for another car on the radio.',
                    style: context.caption,
                  ),
                ],
                const SizedBox(height: Space.lg),
                if (!s.spotifyConnected)
                  PrimaryButton(
                    key: const Key('connect-spotify'),
                    label: 'Connect Spotify',
                    icon: Icons.link,
                    onPressed: c.connectSpotify,
                  )
                else if (s.isDj)
                  Row(
                    children: [
                      Expanded(
                        child: PairedAction(
                          label: 'Step down',
                          onPressed: c.release,
                        ),
                      ),
                      const SizedBox(width: Space.md),
                      Expanded(
                        child: PairedAction(
                          label: 'Disconnect',
                          onPressed: c.disconnectSpotify,
                        ),
                      ),
                    ],
                  )
                else ...[
                  PrimaryButton(
                    key: const Key('claim-dj'),
                    label: 'Be the DJ',
                    icon: Icons.headphones_outlined,
                    onPressed: c.claim,
                  ),
                  const SizedBox(height: Space.sm),
                  TextButton(
                    onPressed: c.disconnectSpotify,
                    child: const Text('Disconnect Spotify'),
                  ),
                ],
              ],
            ),
          ),
          if (s.current != null) ...[
            const SizedBox(height: Space.md),
            Tile(
              tone: TileTone.primary,
              child: Row(
                children: [
                  PulsingDot(color: scheme.primary, size: 8),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.current!.name,
                          style: context.title.copyWith(
                            color: scheme.onPrimaryContainer,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          s.current!.artists,
                          style: context.caption.copyWith(
                            color: scheme.onPrimaryContainer,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Haptics.select();
                      c.voteSkip();
                    },
                    child: Text(
                      s.skipVotes == 0
                          ? 'Vote to skip'
                          : 'Skip (${s.skipVotes})',
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (s.isDj) ...[
            const SizedBox(height: Space.xl),
            TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Search tracks',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(Space.md),
                        child: SizedBox.square(
                          dimension: 16,
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
              ConvoyRow(
                title: t.name,
                caption: t.artists,
                titleStyle: context.body,
                trailing: IconButton(
                  tooltip: 'Add to the queue',
                  icon: const Icon(Icons.playlist_add),
                  onPressed: () {
                    Haptics.tap();
                    c.addToQueue(t);
                  },
                ),
              ),
            if (s.queue.isNotEmpty) ...[
              const SizedBox(height: Space.xl),
              const Kicker('Up next'),
              const SizedBox(height: Space.xs),
              for (final t in s.queue)
                ConvoyRow(
                  leading: const Icon(Icons.queue_music),
                  title: t.name,
                  caption: t.artists,
                  titleStyle: context.body,
                  trailing: IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.close),
                    onPressed: () => c.removeFromQueue(t.uri),
                  ),
                ),
            ],
            const SizedBox(height: Space.lg),
            PrimaryButton(
              label: s.current == null ? 'Start the queue' : 'Next track',
              icon: Icons.skip_next,
              onPressed: s.queue.isEmpty ? null : () => c.playNext(),
            ),
          ],
        ],
      ),
    );
  }
}
