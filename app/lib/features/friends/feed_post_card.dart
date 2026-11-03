import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme.dart';
import '../../app/ui/ui.dart';
import '../../data/repos/feed_repo.dart';
import '../../widgets/relative_time.dart';
import '../drive/widgets/score_ring.dart';
import 'widgets/user_avatar.dart';

/// One post: who, what happened, reactions, comment count (docs/01 §4.2,
/// §4.9; docs/12 §7 "Friends"). Roasts are shown exactly as the engine wrote
/// them. A borderless tile that springs on press; the list puts 24 between
/// cards. Long-press opens the actions sheet.
class FeedPostCard extends StatelessWidget {
  const FeedPostCard({
    super.key,
    required this.post,
    required this.onReact,
    this.onOpen,
    this.onLongPress,
    this.expanded = false,
    this.heroAvatar = true,
  });

  final FeedPost post;
  final void Function(String kind) onReact;
  final VoidCallback? onOpen;
  final VoidCallback? onLongPress;

  /// Detail screen: no tap-to-open, comment count hidden.
  final bool expanded;

  /// Tag the avatar `avatar-<userId>` so it flies to the profile. A list
  /// passes false for every post but an author's first, since Hero tags must
  /// be unique on a screen.
  final bool heroAvatar;

  /// The wall a post sits on, when it sits on one: label and colour.
  static (String, Color)? wallOf(BuildContext context, FeedPost post) {
    if (post.kind == 'shame' || post.reckless) {
      return ('Wall of shame', Theme.of(context).colorScheme.error);
    }
    if (post.kind == 'trip' && (post.score ?? 0) >= 90) {
      return ('Wall of fame', DrivalryTheme.teal);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc();
    final wall = wallOf(context, post);
    Widget avatar = UserAvatar(
      name: post.author.name,
      avatarPath: post.author.avatarPath,
    );
    if (heroAvatar) {
      avatar = Hero(tag: 'avatar-${post.author.id}', child: avatar);
    }
    return Tile(
      onTap: expanded ? null : onOpen,
      onLongPress: expanded ? null : onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                customBorder: const CircleBorder(),
                onTap: () => context.push(Routes.userProfile(post.author.id)),
                child: avatar,
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.author.name,
                      style: context.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '@${post.author.handle} · '
                      '${relativeTime(post.createdAt, now)}',
                      style: context.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (wall != null) ...[
                const SizedBox(width: Space.sm),
                Kicker(wall.$1, color: wall.$2),
              ],
            ],
          ),
          const SizedBox(height: Space.lg),
          _Body(post: post),
          const SizedBox(height: Space.sm),
          ReactionRow(post: post, onReact: onReact),
          if (!expanded) _CommentCount(count: post.commentCount),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.post});
  final FeedPost post;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final body = post.body;
    switch (post.kind) {
      case 'badge':
        return _IconLine(
          icon: Icons.military_tech_outlined,
          color: scheme.tertiary,
          text: 'Earned ${body['badge_name'] ?? body['badge_id'] ?? 'a badge'}',
        );
      case 'league':
        final rank = body['rank'];
        return Text(
          rank == null
              ? 'League week finished'
              : 'Finished #$rank in ${body['league_name'] ?? 'the league'}',
          style: context.body,
        );
      case 'convoy':
        return Text(
          body['title'] as String? ?? 'Convoy recap',
          style: context.body,
        );
      case 'checkin':
        return _IconLine(
          icon: Icons.home_outlined,
          color: scheme.tertiary,
          text: 'Checked in at ${body['label'] ?? 'home'}',
        );
      default:
        final score = post.score;
        final roast = post.roastText;
        final comps = post.components;
        final verdict = (roast != null && roast.isNotEmpty)
            ? roast
            : (post.reckless ? 'A reckless trip.' : 'A scored trip.');
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (score != null) ...[
              ScoreRing(score: score, size: 56, stroke: 6),
              const SizedBox(width: Space.lg),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(verdict, style: context.body),
                  if (comps != null && comps.isNotEmpty) ...[
                    const SizedBox(height: Space.sm),
                    Wrap(
                      spacing: Space.sm,
                      runSpacing: Space.sm,
                      children: [
                        for (final e in comps.entries)
                          if (e.value is num && (e.value as num) > 0)
                            _ComponentPill(
                              component: e.key,
                              points: (e.value as num).round(),
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
}

class _IconLine extends StatelessWidget {
  const _IconLine({
    required this.icon,
    required this.color,
    required this.text,
  });
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: Space.sm),
        Expanded(child: Text(text, style: context.body)),
      ],
    );
  }
}

/// Points lost on one score component, as a compact pill with the
/// component's icon; the name sits in the tooltip.
class _ComponentPill extends StatelessWidget {
  const _ComponentPill({required this.component, required this.points});
  final String component;
  final int points;

  static (String, IconData) _describe(String key) => switch (key) {
    'speed' => ('Speed', Icons.speed_outlined),
    'smoothness' => ('Smoothness', Icons.waves_outlined),
    'attention' => ('Attention', Icons.phone_android_outlined),
    'efficiency' => ('Efficiency', Icons.eco_outlined),
    _ => (key, Icons.remove_circle_outline),
  };

  @override
  Widget build(BuildContext context) {
    final (name, icon) = _describe(component);
    return Tooltip(
      message: name,
      child: Pill('−$points', icon: icon, compact: true),
    );
  }
}

/// One row of reaction capsules that scrolls sideways. The ones you gave
/// are tinted primary; each springs on press and its count counts.
class ReactionRow extends StatelessWidget {
  const ReactionRow({super.key, required this.post, required this.onReact});
  final FeedPost post;
  final void Function(String kind) onReact;

  @override
  Widget build(BuildContext context) {
    final kinds = [
      for (final k in reactionKinds)
        if (k != 'snitch' || post.hasSpeeding) k,
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final k in kinds)
            Padding(
              padding: const EdgeInsets.only(right: Space.sm),
              child: _ReactionPill(
                kind: k,
                count: post.reactions[k],
                selected: post.myReactions.contains(k),
                onTap: () => onReact(k),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReactionPill extends StatelessWidget {
  const _ReactionPill({
    required this.kind,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String kind;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = selected
        ? (scheme.primaryContainer, scheme.onPrimaryContainer)
        : (scheme.surfaceContainerHigh, scheme.onSurface);
    final style = context.label.copyWith(color: fg);
    return Tooltip(
      message: reactionLabel(kind),
      child: PressScale(
        haptic: false,
        scale: 0.9,
        onTap: () {
          Haptics.select();
          onTap();
        },
        // Vertical padding lifts the capsule to a 48 px target.
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.md),
          child: AnimatedContainer(
            duration: Motion.quick,
            padding: const EdgeInsets.symmetric(
              horizontal: Space.md,
              vertical: Space.xs,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(reactionEmoji(kind), style: style),
                if (count != null) ...[
                  const SizedBox(width: Space.xs),
                  AnimatedNumber(value: count!, style: style),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CommentCount extends StatelessWidget {
  const _CommentCount({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.mode_comment_outlined,
          size: 18,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: Space.sm),
        Text(
          count == 0
              ? 'No comments yet'
              : '$count comment${count == 1 ? '' : 's'}',
          style: context.caption,
        ),
      ],
    );
  }
}
