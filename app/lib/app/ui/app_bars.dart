import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'tokens.dart';
import 'typography.dart';

/// The app bar of an editorial root (Friends, Leagues, Garage, Profile,
/// Settings): a headline-size title that sits directly under the toolbar
/// row and shrinks into it as the page scrolls (docs/12 §2, §5b).
///
/// Material's `SliverAppBar.large` reserves 152 px and parks the title at
/// the bottom of that band, which reads as a hole at the top of the page.
/// This bar is one toolbar row (where the actions live) plus one title
/// line, 104 px in all, the same geometry as an iOS large title.
class LargeTitleBar extends StatelessWidget {
  const LargeTitleBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.bottom,
    this.automaticallyImplyLeading = true,
  });

  final String title;
  final List<Widget>? actions;
  final Widget? leading;
  final PreferredSizeWidget? bottom;
  final bool automaticallyImplyLeading;

  /// Height of the title line under the toolbar while expanded.
  static const double titleBlock = 48;

  @override
  Widget build(BuildContext context) {
    final bottomHeight = bottom?.preferredSize.height ?? 0;
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    final hasLeading =
        leading != null ||
        (automaticallyImplyLeading &&
            (canPop || (Scaffold.maybeOf(context)?.hasDrawer ?? false)));
    return SliverAppBar(
      pinned: true,
      leading: leading,
      automaticallyImplyLeading: automaticallyImplyLeading,
      actions: actions,
      bottom: bottom,
      toolbarHeight: kToolbarHeight,
      expandedHeight: kToolbarHeight + titleBlock + bottomHeight,
      flexibleSpace: FlexibleSpaceBar(
        expandedTitleScale: 1,
        centerTitle: false,
        // The flexible space spans the bottom widget too, so the title
        // must clear it: a tab bar would otherwise sit on the title.
        titlePadding: EdgeInsetsDirectional.only(
          start: Space.gutter,
          bottom: Space.lg + bottomHeight,
        ),
        // Once collapsed the title must clear the back button.
        title: LargeTitle(title, collapsedStart: hasLeading ? 56 : 0),
      ),
    );
  }
}

/// The title inside [LargeTitleBar]: `headline` while the bar is expanded,
/// the toolbar's title style once it has collapsed, interpolated as the
/// person scrolls. Usable on its own inside any `FlexibleSpaceBar`.
class LargeTitle extends StatelessWidget {
  const LargeTitle(this.text, {super.key, this.collapsedStart = 0});

  final String text;

  /// Extra start inset applied as the bar collapses, so the title does not
  /// run under a leading widget.
  final double collapsedStart;

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
    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: lerpDouble(collapsedStart, 0, t)!,
      ),
      child: Text(
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
      ),
    );
  }
}
