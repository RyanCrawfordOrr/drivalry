import 'package:flutter/material.dart';

import '../../../app/ui/ui.dart';

/// The surface revealed behind a row swiped away (docs/12 §5b): the error
/// container with one trash icon at the trailing edge, rounded like the tile
/// it sits under.
class SwipeToDeleteBackground extends StatelessWidget {
  const SwipeToDeleteBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: Radii.cardRadius,
      ),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: Space.xl),
      child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
    );
  }
}
