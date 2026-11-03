import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/deep_links.dart';
import '../../data/repos/friends_repo.dart';
import '../../data/repos/friends_sync.dart';
import '../../data/supabase/supabase_providers.dart';
import '../../widgets/signed_in_scope.dart';
import 'widgets/user_avatar.dart';

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
      setState(() => _message = 'Search failed: $e');
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
      setState(() => _message = 'Could not load that profile: $e');
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
    final theme = Theme.of(context);
    final me = ref.watch(currentUserIdProvider);
    final snapshot = ref.watch(friendsSnapshotProvider).value;
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Add friend')),
      body: SignedInScope(
        message: 'Sign in to add friends.',
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Friends see each other on the map, in the feed and in leagues. '
              'Adding someone shares your location with them until you hide it.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Text('By handle', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _handle,
                    decoration: const InputDecoration(
                      prefixText: '@',
                      hintText: 'handle',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.search,
                    autocorrect: false,
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _searching ? null : _search,
                  child: const Text('Find'),
                ),
              ],
            ),
            if (_searching)
              const Padding(
                padding: EdgeInsets.all(12),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_message!, style: theme.textTheme.bodySmall),
              ),
            if (result != null)
              _ResultCard(
                profile: result,
                isMe: result.id == me,
                isFriend: snapshot?.isFriend(result.id) ?? false,
                requested: snapshot?.hasOutgoingTo(result.id) ?? false,
                incoming: snapshot?.hasIncomingFrom(result.id) ?? false,
                onAdd: () async {
                  await ref.read(friendsRepoProvider).sendRequest(result);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Request sent to ${result.name}')),
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
            const SizedBox(height: 24),
            Text('Your invite', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            if (me != null) _Invite(link: FriendsRepo.inviteLink(me)),
            const SizedBox(height: 24),
            Text('Paste a link', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _link,
                    decoration: const InputDecoration(
                      hintText: 'drivalry://friend/…',
                      border: OutlineInputBorder(),
                    ),
                    autocorrect: false,
                    onSubmitted: (_) => _pasteLink(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: _pasteLink,
                  child: const Text('Open'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
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
      action = const Text('That is you');
    } else if (isFriend) {
      action = const Text('Already friends');
    } else if (requested) {
      action = const Text('Request sent');
    } else if (incoming) {
      action = FilledButton(onPressed: onAccept, child: const Text('Accept'));
    } else {
      action = FilledButton.icon(
        onPressed: onAdd,
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('Add friend'),
      );
    }
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: ListTile(
        leading: UserAvatar(name: profile.name, avatarPath: profile.avatarPath),
        title: Text(profile.name),
        subtitle: Text('@${profile.handle}'),
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
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(8),
              child: QrImageView(data: link, size: 180),
            ),
            const SizedBox(height: 8),
            SelectableText(link, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: link));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Link copied')),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copy'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: () => SharePlus.instance.share(
                    ShareParams(
                      text: 'Add me on Drivalry: $link',
                      subject: 'Drivalry invite',
                    ),
                  ),
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Share'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
