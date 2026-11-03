import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repos/leagues_repo.dart';
import '../badges/moment_ledger.dart';

/// Wraps a Leagues screen and turns each promotion the week-badge pass finds
/// into one "Promoted" moment: once per league and week, foreground only.
class PromotionMoments extends ConsumerStatefulWidget {
  const PromotionMoments({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<PromotionMoments> createState() => _PromotionMomentsState();
}

class _PromotionMomentsState extends ConsumerState<PromotionMoments> {
  ProviderSubscription<AsyncValue<PromotionEvent>>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = ref.listenManual(promotionEventsProvider, (_, next) {
      final e = next.value;
      if (e != null) celebratePromotion(e);
    });
  }

  @override
  void dispose() {
    _sub?.close();
    super.dispose();
  }

  Future<void> celebratePromotion(PromotionEvent e) async {
    if (!mounted) return;
    await ref
        .read(momentLedgerProvider)
        .celebrateOnce(
          context,
          id: e.id,
          title: 'Promoted',
          verdict: '${e.from.label} → ${e.to.label}',
        );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
