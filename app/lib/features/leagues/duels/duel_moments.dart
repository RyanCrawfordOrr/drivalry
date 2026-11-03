import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repos/duels_repo.dart';
import '../../../data/supabase/supabase_providers.dart';
import '../../badges/moment_ledger.dart';
import 'duel_card.dart';

/// How long after a duel ends a win still earns the moment.
const Duration duelMomentWindow = Duration(days: 14);

/// Duels [me] won in the last [within], newest first.
List<Duel> wonRecently(
  List<Duel> duels,
  String me,
  DateTime now, {
  Duration within = duelMomentWindow,
}) => [
  for (final d in duels)
    if (d.isFinished &&
        d.winnerId == me &&
        recentlyAt(d.finishedAt, now, within))
      d,
];

/// Wraps a screen and shows "Duel won" once per duel the signed-in user won,
/// whenever the duel list reports one while the app is in the foreground.
class DuelMoments extends ConsumerStatefulWidget {
  const DuelMoments({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<DuelMoments> createState() => _DuelMomentsState();
}

class _DuelMomentsState extends ConsumerState<DuelMoments>
    with WidgetsBindingObserver {
  ProviderSubscription<AsyncValue<List<Duel>>>? _sub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sub = ref.listenManual(
      myDuelsProvider,
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
      _check(ref.read(myDuelsProvider).value);
    }
  }

  Future<void> _check(List<Duel>? duels) async {
    if (duels == null || !mounted) return;
    final me = ref.read(currentUserIdProvider);
    if (me == null) return;
    final ledger = ref.read(momentLedgerProvider);
    for (final d in wonRecently(duels, me, DateTime.now())) {
      if (!mounted) return;
      await ledger.celebrateOnce(
        context,
        id: 'duel:${d.id}',
        title: 'Duel won',
        verdict: duelWinLine(d, me),
        badges: [if (d.loserBadgeId != null) duelBadgeName(d.loserBadgeId!)],
      );
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
