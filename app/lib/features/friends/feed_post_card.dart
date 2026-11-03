import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme.dart';
import '../../data/repos/feed_repo.dart';
import '../../widgets/relative_time.dart';
import 'widgets/user_avatar.dart';

/// One post: author, what happened, reactions, comment count
/// (docs/01 §4.2, §4.9). Roasts are shown exactly as the engine wrote them.
class FeedPostCard extends StatelessWidget {
  const FeedPostCard({
    super.key,
    required this.post,
    required this.onReact,
    this.onOpen,
    this.expanded = false,
  });

  final FeedPost post;
  final void Function(String kind) onReact;
  final VoidCallback? onOpen;

  /// Detail screen: no tap-to-open, comment count hidden.
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now().toUtc();
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        onTap: expanded ? null : onOpen,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  InkWell(
                    onTap: () =>
                        context.push(Routes.userProfile(post.author.id)),
                    child: UserAvatar(
                      name: post.author.name,
                      avatarPath: post.author.avatarPath,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          post.author.name,
                          style: theme.textTheme.titleSmall,
                        ),
                        Text(
                          '@${post.author.handle} · ${relativeTime(post.createdAt, now)}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  _KindChip(post: post),
                ],
              ),
              const SizedBox(height: 10),
              _Body(post: post),
              const SizedBox(height: 8),
              _ReactionBar(post: post, onReact: onReact),
              if (!expanded)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: onOpen,
                    icon: const Icon(Icons.mode_comment_outlined, size: 18),
                    label: Text(
                      post.commentCount == 0
                          ? 'Comment'
                          : '${post.commentCount} comment${post.commentCount == 1 ? '' : 's'}',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip({required this.post});
  final FeedPost post;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color) = switch (post.kind) {
      'shame' => ('WALL OF SHAME', theme.colorScheme.error),
      'badge' => ('BADGE', theme.colorScheme.tertiary),
      'league' => ('LEAGUE', theme.colorScheme.secondary),
      'convoy' => ('CONVOY', theme.colorScheme.secondary),
      _ when post.reckless => ('RECKLESS', theme.colorScheme.error),
      _ when (post.score ?? 0) >= 90 => ('WALL OF FAME', DrivalryTheme.teal),
      _ => ('TRIP', theme.colorScheme.outline),
    };
    return Text(
      label,
      style: theme.textTheme.labelSmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.post});
  final FeedPost post;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = post.body;
    switch (post.kind) {
      case 'badge':
        return Text(
          'Earned ${body['badge_name'] ?? body['badge_id'] ?? 'a badge'}',
          style: theme.textTheme.bodyLarge,
        );
      case 'league':
        final rank = body['rank'];
        return Text(
          rank == null
              ? 'League week finished'
              : 'Finished #$rank in ${body['league_name'] ?? 'the league'}',
          style: theme.textTheme.bodyLarge,
        );
      case 'convoy':
        return Text(
          body['title'] as String? ?? 'Convoy recap',
          style: theme.textTheme.bodyLarge,
        );
      default:
        final score = post.score;
        final roast = post.roastText;
        final comps = post.components;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (score != null)
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: DrivalryTheme.scoreColor(score),
                    width: 4,
                  ),
                ),
                child: Text(
                  '$score',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (score != null) const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (roast != null && roast.isNotEmpty)
                    Text(roast, style: theme.textTheme.bodyLarge)
                  else
                    Text(
                      post.reckless ? 'A reckless trip.' : 'A scored trip.',
                      style: theme.textTheme.bodyLarge,
                    ),
                  if (comps != null && comps.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: -6,
                      children: [
                        for (final e in comps.entries)
                          if (e.value is num && (e.value as num) > 0)
                            Chip(
                              visualDensity: VisualDensity.compact,
                              label: Text(
                                '${_componentLabel(e.key)} −${(e.value as num).toStringAsFixed(0)}',
                              ),
                            ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
    }
  }

  static String _componentLabel(String key) => switch (key) {
    'speed' => 'Speed',
    'smoothness' => 'Smoothness',
    'attention' => 'Attention',
    'efficiency' => 'Efficiency',
    _ => key,
  };
}

class _ReactionBar extends StatelessWidget {
  const _ReactionBar({required this.post, required this.onReact});
  final FeedPost post;
  final void Function(String kind) onReact;

  @override
  Widget build(BuildContext context) {
    final kinds = [
      for (final k in reactionKinds)
        if (k != 'snitch' || post.hasSpeeding) k,
    ];
    return Wrap(
      spacing: 6,
      runSpacing: -4,
      children: [
        for (final k in kinds)
          FilterChip(
            visualDensity: VisualDensity.compact,
            showCheckmark: false,
            selected: post.myReactions.contains(k),
            tooltip: reactionLabel(k),
            label: Text(
              post.reactions[k] == null
                  ? reactionEmoji(k)
                  : '${reactionEmoji(k)} ${post.reactions[k]}',
            ),
            onSelected: (_) => onReact(k),
          ),
      ],
    );
  }
}
