import 'package:flutter/material.dart';

/// A sliver list for one tab of an editorial root. Inside a
/// [NestedScrollView] (the Friends root with its collapsing large app bar) it
/// injects the header overlap so content starts under the pinned bar; on its
/// own it is a plain [CustomScrollView]. Always scrollable, so pull to
/// refresh works on short lists too.
class TabScrollView extends StatelessWidget {
  const TabScrollView({super.key, required this.slivers, this.onScroll});

  final List<Widget> slivers;

  /// Called on every scroll update, for "load more near the end".
  final void Function(ScrollMetrics metrics)? onScroll;

  @override
  Widget build(BuildContext context) {
    final nested =
        context.findAncestorWidgetOfExactType<NestedScrollView>() != null;
    final view = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (nested)
          SliverOverlapInjector(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
          ),
        ...slivers,
      ],
    );
    if (onScroll == null) return view;
    return NotificationListener<ScrollUpdateNotification>(
      onNotification: (n) {
        onScroll!(n.metrics);
        return false;
      },
      child: view,
    );
  }
}
