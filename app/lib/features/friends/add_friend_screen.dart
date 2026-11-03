import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/deep_links.dart';
import '../../app/ui/ui.dart';
import '../../data/repos/friends_repo.dart';
import '../../data/repos/friends_sync.dart';
import '../../data/supabase/supabase_providers.dart';
import '../../widgets/friendly_error.dart';
import '../../widgets/signed_in_scope.dart';
import 'widgets/person_row.dart';

/// Find someone by handle, show your own invite QR and link, or paste a
/// link someone sent you (docs/01 §4.5). Adding a friend shares your
/// location with them (ADR-018), and the screen says so.
class AddFriendScreen extends ConsumerStatefulWidget {
  const AddFriendScreen({super.key, this.initialUserId});

  /// From `/friends/add?user=<id>`: show that person straight away.
  final String? initialUserId;

  @override
  ConsumerState<AddFriendScreen> createState() => _AddFriendScreenState();
}

class _AddFriendScreenState extends ConsumerState<AddFriendScreen> {
  final _handle = TextEditingController();
  final _link = TextEditingController();
  FriendProfile? _result;
  bool _searching = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    final id = widget.initialUserId;
    if (id != null) Future.microtask(() => _loadUser(id));
  }

  @override
  void dispose() {
    _handle.dispose();
    _link.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _handle.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _searching = true;
      _message = null;
      _result = null;
    });
    try {
      final found = await ref.read(friendsRepoProvider).findByHandle(q);
      setState(() {
        _result = found;
        _message = found == null ? 'No one with that handle.' : null;
      });
    } catch (e) {
      setState(() => _message = friendlyError(e, doing: 'search'));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _loadUser(String id) async {
    setState(() {
      _searching = true;
      _message = null;
    });
    try {
      final found = await ref.read(friendsRepoProvider).profile(id);
      setState(() {
        _result = found;
        _message = found == null ? 'That link points at no one.' : null;
      });
    } catch (e) {
      setState(() => _message = friendlyError(e, doing: 'open that profile'));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _pasteLink() {
    final uri = Uri.tryParse(_link.text.trim());
    final route = uri == null ? null : deepLinkToRoute(uri);
    if (route == null) {
      setState(() => _message = 'That is not a Drivalry link.');
      return;
    }
    final match = RegExp(r'^/profile/([^/]+)$').firstMatch(route);
    if (match != null) {
      _loadUser(match.group(1)!);
    } else {
      context.push(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserIdProvider);
    final snapshot = ref.watch(friendsSnapshotProvider).value;
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Add friend')),
      body: SignedInScope(
        message: 'Sign in to add friends.',
        child: ListView(
          padding: const EdgeInsets.only(top: Space.lg, bottom: Space.xxxl),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.gutter,
                0,
                Space.gutter,
                Space.section,
              ),
              child: Text(
                'Friends see each other on the map, in the feed and in '
                'leagues. Adding someone shares your location until you hide.',
                style: context.bodyMuted,
              ),
            ),
            EditorialSection(
              kicker: 'Find by handle',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _handle,
                          decoration: const InputDecoration(
                            prefixText: '@',
                            hintText: 'handle',
                          ),
                          textInputAction: TextInputAction.search,
                          autocorrect: false,
                          onSubmitted: (_) => _search(),
                        ),
                      ),
                      const SizedBox(width: Space.sm),
                      FilledButton.tonal(
                        onPressed: _searching ? null : _search,
                        child: const Text('Find'),
                      ),
                    ],
                  ),
                  if (_searching) ...[
                    const SizedBox(height: Space.md),
                    const SkeletonTile(height: 56),
                  ],
                  if (_message != null) ...[
                    const SizedBox(height: Space.md),
                    Text(_message!, style: context.caption),
                  ],
                  if (result != null) ...[
                    const SizedBox(height: Space.md),
                    _ResultTile(
                      profile: result,
                      isMe: result.id == me,
                      isFriend: snapshot?.isFriend(result.id) ?? false,
                      requested: snapshot?.hasOutgoingTo(result.id) ?? false,
                      incoming: snapshot?.hasIncomingFrom(result.id) ?? false,
                      onAdd: () async {
                        await ref.read(friendsRepoProvider).sendRequest(result);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Request sent to ${result.name}'),
                            ),
                          );
                        }
                      },
                      onAccept: () async {
                        final s = snapshot;
                        if (s == null) return;
                        final req = s.incoming.firstWhere(
                          (r) => r.requesterId == result.id,
                        );
                        await ref.read(friendsRepoProvider).accept(req);
                      },
                    ),
                  ],
                ],
              ),
            ),
            if (me != null)
              EditorialSection(
                kicker: 'Share your link',
                child: _Invite(link: FriendsRepo.inviteLink(me)),
              ),
            EditorialSection(
              kicker: 'Paste a link',
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _link,
                      decoration: const InputDecoration(
                        hintText: 'drivalry://friend/…',
                      ),
                      autocorrect: false,
                      onSubmitted: (_) => _pasteLink(),
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  FilledButton.tonal(
                    onPressed: _pasteLink,
                    child: const Text('Open'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.profile,
    required this.isMe,
    required this.isFriend,
    required this.requested,
    required this.incoming,
    required this.onAdd,
    required this.onAccept,
  });

  final FriendProfile profile;
  final bool isMe;
  final bool isFriend;
  final bool requested;
  final bool incoming;
  final Future<void> Function() onAdd;
  final Future<void> Function() onAccept;

  @override
  Widget build(BuildContext context) {
    final Widget action;
    if (isMe) {
      action = const Pill('You', compact: true);
    } else if (isFriend) {
      action = const Pill(
        'Friends',
        tone: PillTone.positive,
        icon: Icons.check,
        compact: true,
      );
    } else if (requested) {
      action = const Pill('Invited', compact: true);
    } else if (incoming) {
      action = FilledButton(onPressed: onAccept, child: const Text('Accept'));
    } else {
      action = FilledButton(onPressed: onAdd, child: const Text('Add'));
    }
    return Tile(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.sm,
      ),
      child: PersonRow(
        name: profile.name,
        avatarPath: profile.avatarPath,
        caption: '@${profile.handle}',
        trailing: action,
      ),
    );
  }
}

class _Invite extends StatelessWidget {
  const _Invite({required this.link});
  final String link;

  @override
  Widget build(BuildContext context) {
    return Tile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              // QR codes need a white quiet zone whatever the theme.
              color: Colors.white,
              padding: const EdgeInsets.all(Space.sm),
              child: QrImageView(data: link, size: 180),
            ),
          ),
          const SizedBox(height: Space.md),
          Text(
            'Friends scan this or open the link to add you.',
            textAlign: TextAlign.center,
            style: context.caption,
          ),
          const SizedBox(height: Space.lg),
          SecondaryButton(
            label: 'Share link',
            icon: Icons.share_outlined,
            onPressed: () => SharePlus.instance.share(
              ShareParams(
                text: 'Add me on Drivalry: $link',
                subject: 'Drivalry invite',
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: link));
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Link copied')));
              }
            },
            child: const Text('Copy link'),
          ),
        ],
      ),
    );
  }
}
