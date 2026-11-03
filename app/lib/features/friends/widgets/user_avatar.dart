import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repos/friends_repo.dart' show initialsOf;
import '../../../data/supabase/supabase_providers.dart';

/// Avatar from the public `avatars` bucket, or initials when there is none.
class UserAvatar extends ConsumerWidget {
  const UserAvatar({
    super.key,
    required this.name,
    this.avatarPath,
    this.radius = 20,
    this.highlighted = false,
  });

  final String name;
  final String? avatarPath;
  final double radius;

  /// Driving right now: primary colour instead of secondary.
  final bool highlighted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final path = avatarPath;
    final client = ref.watch(supabaseProvider);
    final url = (path != null && path.isNotEmpty && client != null)
        ? client.storage.from('avatars').getPublicUrl(path)
        : null;
    return CircleAvatar(
      radius: radius,
      backgroundColor: highlighted
          ? theme.colorScheme.primary
          : theme.colorScheme.secondaryContainer,
      foregroundColor: highlighted
          ? theme.colorScheme.onPrimary
          : theme.colorScheme.onSecondaryContainer,
      backgroundImage: url == null ? null : CachedNetworkImageProvider(url),
      child: url == null
          ? Text(
              initialsOf(name),
              style: TextStyle(
                fontSize: radius * 0.8,
                fontWeight: FontWeight.w600,
              ),
            )
          : null,
    );
  }
}
