import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/ui/ui.dart';
import '../../data/stats/stats_engine.dart';
import '../../data/stats/stats_providers.dart';
import '../../widgets/friendly_error.dart';
import '../profile/profile_repo.dart' show myProfileProvider;
import 'share_stats.dart';
import 'wrapped_cards.dart';

/// Season Wrapped: an intro page, then ten swipeable cards for the season,
/// each shareable as an image. Built on the phone from the local trips;
/// nothing is uploaded.
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
    final scheme = Theme.of(context).colorScheme;
    final stats = ref.watch(wrappedStatsProvider);
    final units = ref.watch(statsUnitsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Season Wrapped')),
      body: stats.when(
        loading: () => const Padding(
          padding: EdgeInsets.fromLTRB(
            Space.gutter,
            Space.sm,
            Space.gutter,
            Space.xxxl,
          ),
          child: SkeletonTile(height: 520),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.gutter,
            Space.xxxl,
            Space.gutter,
            0,
          ),
          child: Text(
            friendlyError(e, doing: 'build your Wrapped'),
            style: context.bodyMuted,
          ),
        ),
        data: (s) {
          if (s.isEmpty) {
            return EmptyState(
              kicker: s.range.label,
              headline: 'Nothing to wrap yet.',
              body: 'Drive this season and this fills in.',
            );
          }
          final cards = wrappedCards(s, units);
          final pages = cards.length + 1;
          return Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: pages,
                  onPageChanged: (i) {
                    Haptics.select();
                    setState(() => _page = i);
                  },
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.all(Space.sm),
                    child: i == 0
                        ? WrappedIntroCard(rangeLabel: s.range.label)
                        : WrappedCard(
                            data: cards[i - 1],
                            rangeLabel: s.range.label,
                          ),
                  ),
                ),
              ),
              const SizedBox(height: Space.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < pages; i++)
                    AnimatedContainer(
                      duration: Motion.quick,
                      width: i == _page ? 16 : 6,
                      height: 6,
                      margin: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: i == _page
                            ? scheme.primary
                            : scheme.outlineVariant,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.gutter,
                  Space.sm,
                  Space.gutter,
                  Space.gutter,
                ),
                child: SecondaryButton(
                  label: 'Share this card',
                  icon: Icons.ios_share,
                  onPressed: _page == 0
                      ? null
                      : () => _share(s, cards[_page - 1]),
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
