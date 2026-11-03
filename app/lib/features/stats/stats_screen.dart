import 'package:drivalry_scoring/drivalry_scoring.dart' show SpeedUnits;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/db/database.dart';
import '../../data/stats/stats_engine.dart';
import '../../data/stats/stats_providers.dart';
import '../profile/profile_repo.dart' show myProfileProvider;
import 'fun_facts.dart';
import 'share_stats.dart';
import 'stats_cards.dart';
import 'stats_sections.dart';

/// Stats and fun facts (docs/01 §4.4) for one time window.
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
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Wrap(
              spacing: 8,
              children: [
                for (final w in StatsWindow.values)
                  ChoiceChip(
                    label: Text(w.label),
                    selected: _window == w,
                    onSelected: (_) => setState(() => _window = w),
                  ),
              ],
            ),
          ),
          Expanded(
            child: stats.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  Center(child: Text('Could not compute stats: $e')),
              data: (s) => s.isEmpty
                  ? _Empty(window: _window)
                  : _StatsBody(stats: s, units: units),
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.window});
  final StatsWindow window;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.query_stats, size: 48),
          const SizedBox(height: 12),
          Text(
            window == StatsWindow.allTime
                ? 'No scored trips yet'
                : 'No scored trips in ${window.label.toLowerCase()}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Everything here is computed on this phone from your own drives. '
            'Finish a trip as the driver and the numbers appear.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

class _StatsBody extends ConsumerWidget {
  const _StatsBody({required this.stats, required this.units});

  final DriverStats stats;
  final SpeedUnits units;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sections = statsSections(stats, units);
    final headline = headlineFacts(stats, units);
    final visited = stats.geography.stateCodes.toSet();
    final line = stats.reality.timeSavedLine;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(stats.range.label, style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  [
                    for (final f in headline)
                      '${f.value} ${f.label.toLowerCase()}',
                  ].join(' · '),
                  style: theme.textTheme.bodyMedium,
                ),
                if (line != null) ...[const SizedBox(height: 8), Text(line)],
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonalIcon(
                    onPressed: () => _share(context, ref, headline),
                    icon: const Icon(Icons.ios_share),
                    label: const Text('Share headline'),
                  ),
                ),
              ],
            ),
          ),
        ),
        for (final section in sections) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
            child: Text(section.title, style: theme.textTheme.titleMedium),
          ),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.5,
            children: [
              for (final f in section.facts)
                FactTile(
                  fact: f,
                  onTap: _isFuelFact(f)
                      ? () => _editFuelAssumptions(context, ref)
                      : null,
                ),
            ],
          ),
          if (section.title == 'Geography') ...[
            const SizedBox(height: 8),
            StatesGrid(visited: visited),
          ],
        ],
        const SizedBox(height: 24),
        Text(
          'Fuel, cost and CO₂ are estimates from distance and economy. Tap the '
          'fuel tile to set your price. Nothing here leaves the phone unless '
          'you share it.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  static bool _isFuelFact(FunFact f) =>
      f.label == 'Fuel estimate' || f.label == 'Hard accelerations';

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
Future<void> _editFuelAssumptions(BuildContext context, WidgetRef ref) async {
  final db = ref.read(databaseProvider);
  final price = TextEditingController(
    text: (ref.read(fuelPriceProvider).value ?? defaultFuelPricePerLitre)
        .toStringAsFixed(2),
  );
  final economy = TextEditingController(
    text: (ref.read(fuelEconomyProvider).value ?? defaultLitresPer100km)
        .toStringAsFixed(1),
  );
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Fuel assumptions'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Fuel price per litre',
            ),
          ),
          TextField(
            controller: economy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Default economy, L/100 km',
              helperText: 'Used for cars without fill-ups',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  final p = double.tryParse(price.text.trim());
  final e = double.tryParse(economy.text.trim());
  price.dispose();
  economy.dispose();
  if (ok != true) return;
  if (p != null && p > 0) {
    await db.setSetting(fuelPriceSettingKey, p.toString());
  }
  if (e != null && e > 0) {
    await db.setSetting(fuelEconomySettingKey, e.toString());
  }
}
