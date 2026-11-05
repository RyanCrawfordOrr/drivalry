import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/ui/ui.dart';
import '../../data/repos/feed_repo.dart';
import '../../data/repos/moderation_repo.dart';
import '../../data/supabase/supabase_providers.dart';
import 'feed_post_card.dart';
import 'moderation_actions.dart';
import 'widgets/page_insets.dart';

/// Long-press on a post: react, comment, share, and on someone else's post
/// report it or block them (docs/12 §5b, direct manipulation; docs/05 §1).
Future<void> showPostActions(
  BuildContext context,
  WidgetRef ref, {
  required FeedPost post,
  required void Function(String kind) onReact,
  VoidCallback? onComment,
}) {
  final own = post.author.id == ref.read(currentUserIdProvider);
  return showDrivalrySheet<void>(
    context,
    builder: (ctx) => Padding(
      padding: sheetBottomInset(ctx),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Kicker('React'),
          const SizedBox(height: Space.sm),
          ReactionRow(
            post: post,
            raised: true,
            onReact: (k) {
              Navigator.of(ctx).pop();
              onReact(k);
            },
          ),
          const SizedBox(height: Space.lg),
          ModerationActionTile(
            icon: Icons.mode_comment_outlined,
            label: 'Comment',
            onTap: () {
              Navigator.of(ctx).pop();
              onComment?.call();
            },
          ),
          const SizedBox(height: Space.sm),
          ModerationActionTile(
            icon: Icons.share_outlined,
            label: 'Share',
            onTap: () {
              Navigator.of(ctx).pop();
              SharePlus.instance.share(
                ShareParams(text: shareTextFor(post), subject: 'Drivalry'),
              );
            },
          ),
          if (!own) ...[
            const SizedBox(height: Space.sm),
            ModerationActionTile(
              icon: Icons.flag_outlined,
              label: 'Report',
              onTap: () async {
                Navigator.of(ctx).pop();
                await reportPostFlow(context, ref, post);
              },
            ),
            const SizedBox(height: Space.sm),
            ModerationActionTile(
              icon: Icons.block_outlined,
              label: 'Block ${post.author.name}',
              danger: true,
              onTap: () async {
                Navigator.of(ctx).pop();
                await blockUserFlow(
                  context,
                  ref,
                  BlockedUser(
                    id: post.author.id,
                    handle: post.author.handle,
                    displayName: post.author.displayName,
                    avatarPath: post.author.avatarPath,
                  ),
                );
              },
            ),
          ],
        ],
      ),
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
