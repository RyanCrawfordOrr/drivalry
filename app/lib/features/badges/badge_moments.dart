import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/badges/badges_providers.dart';
import 'moment_ledger.dart';

/// How long after an award a badge still earns the moment.
const Duration badgeMomentWindow = Duration(days: 7);

/// Earned badges new enough for a moment. Shame badges stay quiet.
List<MyBadge> badgesToCelebrate(
  List<MyBadge> list,
  DateTime now, {
  Duration within = badgeMomentWindow,
}) => [
  for (final b in list)
    if (b.earned && !b.def.isShame && recentlyAt(b.awardedAt, now, within)) b,
];

/// Wraps a screen and shows "Badge earned" once per badge id, whenever the
/// local awards gain one while the app is in the foreground. Several that
/// land together share one moment.
class BadgeMoments extends ConsumerStatefulWidget {
  const BadgeMoments({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<BadgeMoments> createState() => _BadgeMomentsState();
}

class _BadgeMomentsState extends ConsumerState<BadgeMoments>
    with WidgetsBindingObserver {
  ProviderSubscription<AsyncValue<List<MyBadge>>>? _sub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sub = ref.listenManual(
      myBadgesProvider,
      (_, next) => _check(next.value),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _check(ref.read(myBadgesProvider).value);
    }
  }

  Future<void> _check(List<MyBadge>? list) async {
    if (list == null || !mounted || !appInForeground()) return;
    final ledger = ref.read(momentLedgerProvider);
    final fresh = <MyBadge>[];
    for (final b in badgesToCelebrate(list, DateTime.now())) {
      if (await ledger.claim('badge:${b.def.id}')) fresh.add(b);
    }
    if (fresh.isEmpty || !mounted) return;
    await ledger.show(
      context,
      title: 'Badge earned',
      verdict: fresh.length == 1
          ? fresh.single.def.description
          : '${fresh.length} new badges',
      badges: [for (final b in fresh) b.def.name],
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
