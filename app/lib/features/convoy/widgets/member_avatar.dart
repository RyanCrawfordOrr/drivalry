import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/ui/ui.dart';
import '../../../data/repos/convoy_models.dart';
import '../../../data/supabase/supabase_providers.dart';

/// The house [Avatar] for a convoy member: their photo from the public
/// `avatars` bucket when there is one, initials otherwise.
class MemberAvatar extends ConsumerWidget {
  const MemberAvatar({
    super.key,
    required this.name,
    this.avatarPath,
    this.size = AvatarSize.md,
    this.isMe = false,
  });

  final String name;
  final String? avatarPath;
  final AvatarSize size;
  final bool isMe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = avatarPath;
    final client = ref.watch(supabaseProvider);
    final url = (path != null && path.isNotEmpty && client != null)
        ? client.storage.from('avatars').getPublicUrl(path)
        : null;
    return Avatar(
      name: name,
      size: size,
      isMe: isMe,
      image: url == null ? null : CachedNetworkImageProvider(url),
    );
  }
}

/// Up to [max] small avatars overlapping in a row, then "+n".
class StackedAvatars extends StatelessWidget {
  const StackedAvatars({
    super.key,
    required this.members,
    this.me,
    this.max = 5,
  });

  final List<ConvoyMember> members;
  final String? me;
  final int max;

  static const double _size = 32;
  static const double _step = 24;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = members.take(max).toList();
    final extra = members.length - shown.length;
    final count = shown.length + (extra > 0 ? 1 : 0);
    if (count == 0) return const SizedBox(height: _size);
    return SizedBox(
      height: _size,
      width: _size + (count - 1) * _step,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * _step,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.surface, width: 2),
                ),
                child: MemberAvatar(
                  name: shown[i].name,
                  avatarPath: shown[i].avatarPath,
                  size: AvatarSize.sm,
                  isMe: shown[i].userId == me,
                ),
              ),
            ),
          if (extra > 0)
            Positioned(
              left: shown.length * _step,
              child: Container(
                width: _size,
                height: _size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.surfaceContainerHighest,
                  border: Border.all(color: scheme.surface, width: 2),
                ),
                child: Text('+$extra', style: context.label),
              ),
            ),
        ],
      ),
    );
  }
}
