import 'package:flutter/material.dart';

import '../../../app/ui/ui.dart';
import '../../friends/widgets/user_avatar.dart';

/// A short name-and-photo pair for [StackedAvatars].
typedef AvatarPerson = ({String name, String? avatarPath});

/// Up to [max] small avatars overlapping left to right, then a "+N" disc.
/// Each avatar gets a thin ring in [ringColor] (the tile it sits on) so they
/// read as separate heads.
class StackedAvatars extends StatelessWidget {
  const StackedAvatars({
    super.key,
    required this.people,
    this.max = 4,
    this.ringColor,
  });

  final List<AvatarPerson> people;
  final int max;
  final Color? ringColor;

  static const double _d = 32;
  static const double _ring = 2;
  static const double _step = Space.xl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ring = ringColor ?? Tile.colorFor(scheme, TileTone.resting);
    if (people.isEmpty) {
      return Container(
        width: _d + _ring * 2,
        height: _d + _ring * 2,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.groups_outlined,
          size: 20,
          color: scheme.onSurfaceVariant,
        ),
      );
    }
    final shown = people.take(max).toList();
    final extra = people.length - shown.length;
    final n = shown.length + (extra > 0 ? 1 : 0);
    final size = _d + _ring * 2;
    return SizedBox(
      width: size + (n - 1) * _step,
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * _step,
              child: _Ringed(
                color: ring,
                child: UserAvatar(
                  name: shown[i].name,
                  avatarPath: shown[i].avatarPath,
                  size: AvatarSize.sm,
                ),
              ),
            ),
          if (extra > 0)
            Positioned(
              left: shown.length * _step,
              child: _Ringed(
                color: ring,
                child: Container(
                  width: _d,
                  height: _d,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '+$extra',
                    style: context.label.copyWith(fontSize: 12),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Ringed extends StatelessWidget {
  const _Ringed({required this.color, required this.child});
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(StackedAvatars._ring),
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    child: child,
  );
}
