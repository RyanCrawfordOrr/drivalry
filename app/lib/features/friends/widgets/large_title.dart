import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../../app/ui/ui.dart';

/// The title of a `SliverAppBar.large` on an editorial root: `headline`
/// while the bar is expanded, the toolbar's title style once it has
/// collapsed, interpolated as the person scrolls.
///
/// The theme sets `AppBarTheme.titleTextStyle`, which the large app bar
/// would otherwise reuse for the expanded title too; reading the bar's
/// extent here gives the big-title-that-collapses feel (docs/12 §5b).
class LargeTitle extends StatelessWidget {
  const LargeTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final settings = context
        .dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
    final collapsed =
        Theme.of(context).appBarTheme.titleTextStyle ?? context.title;
    if (settings == null) return Text(text, style: collapsed);
    final range = settings.maxExtent - settings.minExtent;
    final t = range <= 0
        ? 0.0
        : ((settings.currentExtent - settings.minExtent) / range).clamp(
            0.0,
            1.0,
          );
    // Interpolated by hand: the two styles differ in `inherit`, which
    // TextStyle.lerp refuses.
    final big = context.headline;
    return Text(
      text,
      style: collapsed.copyWith(
        fontSize: lerpDouble(collapsed.fontSize ?? 22, big.fontSize ?? 28, t),
        letterSpacing: lerpDouble(
          collapsed.letterSpacing ?? 0,
          big.letterSpacing ?? 0,
          t,
        ),
        fontWeight: FontWeight.w700,
        fontFamily: t > 0.5 ? big.fontFamily : collapsed.fontFamily,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
