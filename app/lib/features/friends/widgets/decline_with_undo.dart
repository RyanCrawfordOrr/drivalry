import 'package:flutter/material.dart';

import '../../../data/repos/friends_repo.dart';

/// Declines an incoming request the forgiving way: the row disappears at
/// once, a snackbar offers Undo, and the decline is only sent when the
/// snackbar closes without it (audit item 15: undo, not silence).
///
/// [onHidden] is called with `true` to hide the row and `false` when the row
/// may come back (Undo) or has really gone (committed).
Future<void> declineWithUndo(
  BuildContext context, {
  required FriendRequest request,
  required FriendsRepo repo,
  required void Function(bool hidden) onHidden,
}) async {
  onHidden(true);
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  final snack = messenger.showSnackBar(
    SnackBar(
      content: Text('Declined ${request.other.name}.'),
      duration: const Duration(seconds: 5),
      // A snackbar with an action persists by default; this one must time
      // out, or the decline would never be sent.
      persist: false,
      action: SnackBarAction(label: 'Undo', onPressed: () {}),
    ),
  );
  final reason = await snack.closed;
  if (reason == SnackBarClosedReason.action) {
    onHidden(false);
    return;
  }
  await repo.remove(request.other.id);
  onHidden(false);
}
