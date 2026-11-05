import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/ui/ui.dart';
import '../../data/repos/feed_repo.dart';
import '../../data/repos/friends_sync.dart';
import '../../data/repos/moderation_repo.dart';
import '../../widgets/friendly_error.dart';

/// The report and block flows, shared by the feed, the post screen, the
/// friends list, the requests screen and profiles (docs/05 §1). Each one
/// confirms, writes through [ModerationRepo] and says what happened.

/// Confirms, blocks [user] and drops them from the friends cache. Returns
/// true when the block went through.
Future<bool> blockUserFlow(
  BuildContext context,
  WidgetRef ref,
  BlockedUser user,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Block ${user.name}?'),
      content: const Text(
        'They will not see your drives, your posts or your location, and you '
        'will not see theirs. Any friendship or request ends. You can unblock '
        'them in Settings.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
            foregroundColor: Theme.of(ctx).colorScheme.onError,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Block'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  try {
    await ref.read(moderationRepoProvider).block(user);
    await ref.read(friendsRepoProvider).forgetLocal(user.id);
    Haptics.success();
    if (context.mounted) _toast(context, 'Blocked ${user.name}.');
    return true;
  } catch (e) {
    if (context.mounted) {
      _toast(context, friendlyError(e, doing: 'block ${user.name}'));
    }
    return false;
  }
}

Future<void> unblockUserFlow(
  BuildContext context,
  WidgetRef ref,
  BlockedUser user,
) async {
  try {
    await ref.read(moderationRepoProvider).unblock(user.id);
    if (context.mounted) _toast(context, 'Unblocked ${user.name}.');
  } catch (e) {
    if (context.mounted) {
      _toast(context, friendlyError(e, doing: 'unblock ${user.name}'));
    }
  }
}

/// Asks why, then files the report and hides the post for the reporter.
/// Returns true when a report was sent.
Future<bool> reportPostFlow(
  BuildContext context,
  WidgetRef ref,
  FeedPost post,
) async {
  final reason = await pickReportReason(context, what: 'post');
  if (reason == null || !context.mounted) return false;
  try {
    await ref
        .read(moderationRepoProvider)
        .reportPost(
          postId: post.id,
          authorId: post.author.id,
          reason: reason,
          snapshot: {
            'kind': post.kind,
            'score': post.score,
            'roast': post.roastText,
            'author_handle': post.author.handle,
          },
        );
    if (context.mounted) _toast(context, _reportedToast('post'));
    return true;
  } catch (e) {
    if (context.mounted) {
      _toast(context, friendlyError(e, doing: 'send the report'));
    }
    return false;
  }
}

/// Asks why, then files the report and hides the comment for the reporter.
Future<bool> reportCommentFlow(
  BuildContext context,
  WidgetRef ref,
  FeedComment comment,
) async {
  final reason = await pickReportReason(context, what: 'comment');
  if (reason == null || !context.mounted) return false;
  try {
    await ref
        .read(moderationRepoProvider)
        .reportComment(
          commentId: comment.id,
          postId: comment.postId,
          authorId: comment.author.id,
          reason: reason,
          snapshot: {
            'body': comment.body,
            'author_handle': comment.author.handle,
          },
        );
    if (context.mounted) _toast(context, _reportedToast('comment'));
    return true;
  } catch (e) {
    if (context.mounted) {
      _toast(context, friendlyError(e, doing: 'send the report'));
    }
    return false;
  }
}

String _reportedToast(String what) =>
    'Reported. The $what is hidden for you and will be reviewed within '
    '24 hours.';

/// "Report this post": one row per [ReportReason]. Null when dismissed.
Future<ReportReason?> pickReportReason(
  BuildContext context, {
  required String what,
}) {
  return showDrivalrySheet<ReportReason>(
    context,
    title: 'Report this $what',
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'A person reads every report within 24 hours. The $what is hidden '
          'for you as soon as you send it.',
          style: ctx.bodyMuted,
        ),
        const SizedBox(height: Space.lg),
        for (final r in ReportReason.values) ...[
          ModerationActionTile(
            icon: switch (r) {
              ReportReason.abusive => Icons.sentiment_very_dissatisfied,
              ReportReason.notDriving => Icons.directions_car_outlined,
              ReportReason.spam => Icons.report_gmailerrorred_outlined,
              ReportReason.other => Icons.more_horiz,
            },
            label: r.label,
            onTap: () => Navigator.of(ctx).pop(r),
          ),
          if (r != ReportReason.values.last) const SizedBox(height: Space.sm),
        ],
      ],
    ),
  );
}

/// One row in an actions sheet: icon, label, tap.
class ModerationActionTile extends StatelessWidget {
  const ModerationActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = danger ? scheme.error : null;
    return Tile(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.md,
      ),
      child: Row(
        children: [
          Icon(icon, color: color ?? scheme.onSurfaceVariant),
          const SizedBox(width: Space.lg),
          Expanded(
            child: Text(
              label,
              style: context.body.copyWith(
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
