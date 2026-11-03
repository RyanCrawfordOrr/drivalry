import 'package:drivalry_scoring/drivalry_scoring.dart' show SpeedUnits;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/ui/ui.dart';
import '../../data/db/database.dart';
import '../../data/stats/stats_engine.dart';
import '../../data/stats/stats_providers.dart';
import '../../widgets/friendly_error.dart';
import '../../widgets/units.dart';
import '../leagues/widgets/live_numbers.dart';
import '../profile/profile_repo.dart' show myProfileProvider;
import 'fun_facts.dart';
import 'share_stats.dart';
import 'stats_cards.dart';
import 'stats_sections.dart';

/// Stats and fun facts (docs/01 §4.4) for one time window: window chips, a
/// headline tile with counting numbers, then editorial sections of tiles.
class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key, this.initialWindow = StatsWindow.allTime});

  final StatsWindow initialWindow;

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  late StatsWindow _window = widget.initialWindow;

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(driverStatsProvider(_window));
    final units = ref.watch(statsUnitsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stats'),
        actions: [
          IconButton(
            tooltip: 'Season Wrapped',
            icon: const Icon(Icons.auto_awesome_outlined),
            onPressed: () => context.push(Routes.wrapped),
          ),
        ],
      ),
      body: Column(
        // Stretched, so the chips sit on the gutter rather than centred
        // when they wrap to two rows at 360 px.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              Space.lg,
              Space.gutter,
              0,
            ),
            child: Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (final w in StatsWindow.values)
                  ChoiceChip(
                    label: Text(w.label),
                    selected: _window == w,
                    onSelected: (_) {
                      Haptics.select();
                      setState(() => _window = w);
                    },
                  ),
              ],
            ),
          ),
          Expanded(
            child: stats.when(
              loading: () => ListView(
                padding: EdgeInsets.fromLTRB(
                  Space.gutter,
                  Space.lg,
                  Space.gutter,
                  Space.xl + MediaQuery.paddingOf(context).bottom,
                ),
                children: const [
                  SkeletonTile(height: 200),
                  SizedBox(height: Space.section),
                  SkeletonTile(height: 96),
                  SizedBox(height: Space.md),
                  SkeletonTile(height: 96),
                ],
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.gutter,
                  Space.xxxl,
                  Space.gutter,
                  0,
                ),
                child: Text(
                  friendlyError(e, doing: 'work out your stats'),
                  style: context.bodyMuted,
                ),
              ),
              data: (s) => s.isEmpty
                  ? EmptyState(
                      kicker: _window.label,
                      headline: _window == StatsWindow.allTime
                          ? 'No scored trips yet.'
                          : 'Nothing in ${_window.label.toLowerCase()}.',
                      body: 'Finish a drive and the numbers appear.',
                    )
                  : _StatsBody(stats: s, units: units),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsBody extends ConsumerWidget {
  const _StatsBody({required this.stats, required this.units});

  final DriverStats stats;
  final SpeedUnits units;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = statsSections(stats, units);
    final headline = headlineFacts(stats, units);
    final visited = stats.geography.stateCodes.toSet();
    final line = stats.reality.timeSavedLine;
    final t = stats.totals;
    return ListView(
      // The closing note clears the navigation bar or home indicator.
      padding: EdgeInsets.only(
        top: Space.lg,
        bottom: Space.xl + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        Reveal(
          child: Padding(
            padding: Space.screen,
            child: Tile(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Kicker(stats.range.label),
                  const SizedBox(height: Space.lg),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: CountingHero(kicker: 'Trips', value: t.trips),
                      ),
                      Expanded(
                        child: CountingHero(
                          kicker: 'Average score',
                          value: t.averageScore?.round(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.md),
                  Text(
                    '${formatDistance(t.distanceM, units)} · '
                    '${formatHours(t.movingS)} behind the wheel',
                    style: context.caption,
                  ),
                  if (line != null) ...[
                    const SizedBox(height: Space.sm),
                    Text(line, style: context.bodyMuted),
                  ],
                  const SizedBox(height: Space.lg),
                  SecondaryButton(
                    label: 'Share headline',
                    icon: Icons.ios_share,
                    onPressed: () => _share(context, ref, headline),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: Space.section),
        for (var i = 0; i < sections.length; i++)
          Reveal(
            delay: Reveal.stagger(i + 1),
            child: EditorialSection(
              kicker: sections[i].title,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  StatGrid(
                    columns: 2,
                    children: [
                      for (final f in sections[i].facts)
                        FactTile(
                          value: f.value,
                          label: f.label,
                          hint: f.hint,
                          icon: f.icon,
                          onTap: _isFuelFact(f)
                              ? () => showFuelAssumptionsSheet(context, ref)
                              : null,
                        ),
                    ],
                  ),
                  if (sections[i].title == 'Geography') ...[
                    const SizedBox(height: Space.md),
                    StatesGrid(visited: visited),
                  ],
                ],
              ),
            ),
          ),
        Padding(
          padding: Space.screen,
          child: Text(
            'Fuel, cost and CO₂ are estimates. Tap the fuel tile to set your '
            'price. Nothing here leaves the phone unless you share it.',
            style: context.caption,
          ),
        ),
      ],
    );
  }

  static bool _isFuelFact(FunFact f) =>
      f.label == 'Fuel used' || f.label == 'Hard accelerations';

  Future<void> _share(
    BuildContext context,
    WidgetRef ref,
    List<FunFact> headline,
  ) async {
    final handle = ref.read(myProfileProvider).value?.handle;
    final slug = stats.range.label.replaceAll(RegExp('[^A-Za-z0-9]+'), '-');
    await shareCardWidget(
      context,
      ref,
      card: StatsHeadlineCard(stats: stats, facts: headline, handle: handle),
      fileName: 'drivalry-stats-$slug.png',
      text: 'My ${stats.range.label} on Drivalry: ${stats.totals.trips} trips.',
    );
  }
}

/// Price per litre and default economy are plain settings rows.
Future<void> showFuelAssumptionsSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  final db = ref.read(databaseProvider);
  final priceText =
      (ref.read(fuelPriceProvider).value ?? defaultFuelPricePerLitre)
          .toStringAsFixed(2);
  final economyText =
      (ref.read(fuelEconomyProvider).value ?? defaultLitresPer100km)
          .toStringAsFixed(1);
  final result = await showDrivalrySheet<(String, String)>(
    context,
    title: 'Fuel assumptions',
    builder: (_) => TextControllers(
      initial: [priceText, economyText],
      builder: (ctx, c) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: c[0],
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Fuel price per litre',
              ),
            ),
            const SizedBox(height: Space.md),
            TextField(
              controller: c[1],
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Typical economy, L/100 km',
                helperText: 'Used when a car has no fill-ups logged',
              ),
            ),
            const SizedBox(height: Space.xl),
            PrimaryButton(
              label: 'Save',
              onPressed: () => Navigator.pop(ctx, (c[0].text, c[1].text)),
            ),
          ],
        ),
      ),
    ),
  );
  if (result == null) return;
  final p = double.tryParse(result.$1.trim());
  final e = double.tryParse(result.$2.trim());
  if (p != null && p > 0) {
    await db.setSetting(fuelPriceSettingKey, p.toString());
  }
  if (e != null && e > 0) {
    await db.setSetting(fuelEconomySettingKey, e.toString());
  }
}
