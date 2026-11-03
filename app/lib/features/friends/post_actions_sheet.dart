import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/ui/ui.dart';
import '../../data/repos/feed_repo.dart';
import 'feed_post_card.dart';

/// Long-press on a post: react, comment, share or report, in a sheet
/// (docs/12 §5b, direct manipulation).
Future<void> showPostActions(
  BuildContext context, {
  required FeedPost post,
  required void Function(String kind) onReact,
  VoidCallback? onComment,
}) {
  return showDrivalrySheet<void>(
    context,
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Kicker('React'),
        const SizedBox(height: Space.sm),
        ReactionRow(
          post: post,
          onReact: (k) {
            Navigator.of(ctx).pop();
            onReact(k);
          },
        ),
        const SizedBox(height: Space.lg),
        _Action(
          icon: Icons.mode_comment_outlined,
          label: 'Comment',
          onTap: () {
            Navigator.of(ctx).pop();
            onComment?.call();
          },
        ),
        const SizedBox(height: Space.sm),
        _Action(
          icon: Icons.share_outlined,
          label: 'Share',
          onTap: () {
            Navigator.of(ctx).pop();
            SharePlus.instance.share(
              ShareParams(text: shareTextFor(post), subject: 'Drivalry'),
            );
          },
        ),
        const SizedBox(height: Space.sm),
        _Action(
          icon: Icons.flag_outlined,
          label: 'Report',
          onTap: () async {
            Navigator.of(ctx).pop();
            await _report(context);
          },
        ),
      ],
    ),
  );
}

/// One line about the post for the share sheet.
String shareTextFor(FeedPost post) {
  final who = post.author.name;
  final score = post.score;
  final roast = post.roastText;
  if (score != null) {
    final quote = (roast == null || roast.isEmpty) ? '' : ' "$roast"';
    return '$who scored $score on Drivalry.$quote';
  }
  final badge = post.body['badge_name'] ?? 'a badge';
  final place = post.body['label'] ?? 'home';
  return switch (post.kind) {
    'badge' => '$who earned $badge on Drivalry.',
    'checkin' => '$who checked in at $place.',
    _ => '$who on Drivalry.',
  };
}

Future<void> _report(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Report this post?'),
      content: const Text(
        'Use this when a post is abusive or not about the drive.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Report'),
        ),
      ],
    ),
  );
  if (ok == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Thanks. We will take a look.')),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tile(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.md,
      ),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: Space.lg),
          Text(
            label,
            style: context.body.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
