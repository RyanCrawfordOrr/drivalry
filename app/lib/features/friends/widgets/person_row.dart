import 'package:flutter/material.dart';

import '../../../app/ui/ui.dart';
import 'user_avatar.dart';

/// Avatar, name, one caption line and optional trailing widgets: the one row
/// for a person in the friends list, requests, circle members and pickers.
/// 56 tall, so it clears the 48 touch target on its own. With [heroTag] the
/// avatar flies to the profile screen (docs/12 §5b, tag `avatar-<userId>`).
class PersonRow extends StatelessWidget {
  const PersonRow({
    super.key,
    required this.name,
    this.avatarPath,
    this.caption,
    this.badge,
    this.trailing,
    this.onTap,
    this.highlighted = false,
    this.isMe = false,
    this.avatarSize = AvatarSize.md,
    this.heroTag,
  });

  final String name;
  final String? avatarPath;
  final String? caption;

  /// A status capsule shown before [trailing].
  final Widget? badge;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool highlighted;
  final bool isMe;
  final AvatarSize avatarSize;
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    Widget avatar = UserAvatar(
      name: name,
      avatarPath: avatarPath,
      size: avatarSize,
      highlighted: highlighted,
      isMe: isMe,
    );
    if (heroTag != null) avatar = Hero(tag: heroTag!, child: avatar);
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: Row(
        children: [
          avatar,
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: context.body.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (caption != null)
                  Text(
                    caption!,
                    style: context.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (badge != null) ...[const SizedBox(width: Space.sm), badge!],
          if (trailing != null) ...[const SizedBox(width: Space.sm), trailing!],
        ],
      ),
    );
    if (onTap == null) return row;
    return PressScale(
      child: InkWell(
        borderRadius: Radii.tileRadius,
        onTap: () {
          Haptics.tap();
          onTap!();
        },
        child: row,
      ),
    );
  }
}
