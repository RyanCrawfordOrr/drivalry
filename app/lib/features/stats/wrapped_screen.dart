import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/stats/stats_engine.dart';
import '../../data/stats/stats_providers.dart';
import '../profile/profile_repo.dart' show myProfileProvider;
import 'share_stats.dart';
import 'wrapped_cards.dart';

/// Season Wrapped: ten swipeable cards for the season, each shareable as an
/// image. Built on the phone from the local trips; nothing is uploaded.
class WrappedScreen extends ConsumerStatefulWidget {
  const WrappedScreen({super.key});

  @override
  ConsumerState<WrappedScreen> createState() => _WrappedScreenState();
}

class _WrappedScreenState extends ConsumerState<WrappedScreen> {
  final _controller = PageController(viewportFraction: 0.92);
  var _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(wrappedStatsProvider);
    final units = ref.watch(statsUnitsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Season Wrapped')),
      body: stats.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not build the Wrapped: $e')),
        data: (s) {
          if (s.isEmpty) return _Empty(range: s.range);
          final cards = wrappedCards(s, units);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  s.range.label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: cards.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.all(8),
                    child: WrappedCard(
                      data: cards[i],
                      rangeLabel: s.range.label,
                    ),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < cards.length; i++)
                    Container(
                      width: i == _page ? 10 : 6,
                      height: 6,
                      margin: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: i == _page
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: FilledButton.icon(
                  onPressed: () => _share(s, cards[_page]),
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Share this card'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _share(DriverStats s, WrappedCardData card) async {
    final handle = ref.read(myProfileProvider).value?.handle;
    await shareCardWidget(
      context,
      ref,
      card: WrappedCard(
        data: card,
        rangeLabel: s.range.label,
        forShare: true,
        handle: handle,
      ),
      fileName: 'drivalry-wrapped-${card.id}.png',
      text: '${card.kicker}: ${card.value}. My ${s.range.label} on Drivalry.',
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.range});
  final StatsRange range;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_awesome_outlined, size: 48),
          const SizedBox(height: 12),
          Text(
            'Nothing to wrap yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'No scored driver trips in ${range.label}. Drive, and this fills in.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
