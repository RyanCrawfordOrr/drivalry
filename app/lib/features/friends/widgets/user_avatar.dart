import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/ui/ui.dart';
import '../../../data/supabase/supabase_providers.dart';

/// The shared [Avatar] for a person with a profile: resolves [avatarPath] in
/// the public `avatars` bucket to an image, or shows initials. Every social
/// screen draws people through this, so there is one avatar in the app
/// (docs/12 §4).
class UserAvatar extends ConsumerWidget {
  const UserAvatar({
    super.key,
    required this.name,
    this.avatarPath,
    this.size,
    this.radius,
    this.highlighted = false,
    this.isMe = false,
  });

  final String name;
  final String? avatarPath;

  /// One of the three house sizes. Wins over [radius].
  final AvatarSize? size;

  /// Older call sites size by radius; mapped onto the nearest house size.
  final double? radius;

  /// Driving right now (or leading a convoy): tinted with the primary colour.
  final bool highlighted;

  /// Draws the primary ring that marks the signed-in person.
  final bool isMe;

  AvatarSize get _size {
    if (size != null) return size!;
    final r = radius ?? 20;
    if (r <= 16) return AvatarSize.sm;
    if (r <= 22) return AvatarSize.md;
    return AvatarSize.lg;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = avatarPath;
    final client = ref.watch(supabaseProvider);
    final url = (path != null && path.isNotEmpty && client != null)
        ? client.storage.from('avatars').getPublicUrl(path)
        : null;
    return Avatar(
      name: name,
      size: _size,
      image: url == null ? null : CachedNetworkImageProvider(url),
      isMe: isMe,
      color: highlighted ? Theme.of(context).colorScheme.primary : null,
    );
  }
}
