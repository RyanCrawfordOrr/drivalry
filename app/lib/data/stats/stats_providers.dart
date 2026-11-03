import 'package:drivalry_scoring/drivalry_scoring.dart' show SpeedUnits;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../tracking/providers.dart' show unitsSettingProvider;
import '../../widgets/units.dart';
import '../badges/badge_engine.dart';
import '../convoy/recap_builder.dart' show ConvoyRecap;
import '../db/database.dart';
import '../garage/fuel_math.dart';
import '../repos/convoy_models.dart' show ConvoyMember;
import '../repos/convoy_sync.dart' show convoyRepoProvider;
import '../supabase/supabase_providers.dart' show currentUserIdProvider;
import 'stats_engine.dart';

/// Settings keys. Both are plain decimal strings in the `settings` table.
const String fuelPriceSettingKey = 'stats_fuel_price_per_litre';
const String fuelEconomySettingKey = 'stats_default_l_per_100km';

/// Trips the engine should look back over. Scored trips stay small (a few
/// a day), so five thousand covers years.
const int statsTripLimit = 5000;

/// Wall clock for the windows; tests pin it.
final statsClockProvider = Provider<DateTime Function()>((_) => DateTime.now);

final scoredTripsForStatsProvider = StreamProvider<List<ScoredTrip>>((ref) {
  final parser = ScoredTripParser();
  return ref
      .watch(databaseProvider)
      .watchScoredTripsWithScores(limit: statsTripLimit)
      .map(parser.parse);
});

final fuelPriceProvider = StreamProvider<double>(
  (ref) => ref
      .watch(databaseProvider)
      .watchSetting(fuelPriceSettingKey)
      .map((v) => _positive(v) ?? defaultFuelPricePerLitre),
);

final fuelEconomyProvider = StreamProvider<double>(
  (ref) => ref
      .watch(databaseProvider)
      .watchSetting(fuelEconomySettingKey)
      .map((v) => _positive(v) ?? defaultLitresPer100km),
);

double? _positive(String? wire) {
  final v = double.tryParse(wire ?? '');
  return v != null && v.isFinite && v > 0 ? v : null;
}

/// Fills the per-trip aggregates for trips finalised before schema 5, in
/// batches, once per app run. Each write re-emits the trip stream, so the
/// stats input rebuilds with the filled rows; the loop ends when every ended
/// trip has `statsAt`.
final tripStatsBackfillProvider = FutureProvider<int>((ref) async {
  final db = ref.watch(databaseProvider);
  var done = 0;
  while (true) {
    final ids = await db.tripsNeedingStats();
    if (ids.isEmpty) return done;
    for (final id in ids) {
      await db.computeTripStats(id, DateTime.now().millisecondsSinceEpoch);
      done++;
    }
  }
});

/// Everything the engine needs, re-gathered when the trips or the fuel
/// settings change. Convoy member lists come from the local cache only.
final statsInputProvider = FutureProvider<StatsInput>((ref) async {
  final db = ref.watch(databaseProvider);
  final trips = await ref.watch(scoredTripsForStatsProvider.future);
  final price = await ref.watch(fuelPriceProvider.future);
  final economy = await ref.watch(fuelEconomyProvider.future);
  final me = ref.watch(currentUserIdProvider);
  final repo = ref.watch(convoyRepoProvider);

  // Per-trip aggregates live on the trip row (schema 5). Rows from before
  // that are filled a few at a time by the backfill; nothing here scans the
  // samples table.
  await ref.watch(tripStatsBackfillProvider.future);
  final extents = <String, TripExtent>{};
  final endpoints = <String, TripEndpoints>{};
  final roads = <String, Set<String>>{};
  for (final t in trips) {
    final e = TripExtent.of(t.trip);
    if (e != null) extents[t.trip.id] = e;
    final p = TripEndpoints.of(t.trip);
    if (p != null) endpoints[t.trip.id] = p;
    final r = tripRoadNames(t.trip);
    if (r.isNotEmpty) roads[t.trip.id] = r;
  }
  final places = await db.select(db.places).get();
  final vehicles = await db.activeVehicles();
  final convoys = await db.allConvoyLocal();

  final fuel = <String, FuelStats>{};
  for (final v in vehicles) {
    fuel[v.id] = computeFuelStats(await db.fuelEntriesFor(v.id));
  }
  final members = <String, List<ConvoyMember>>{};
  final dj = <String, int>{};
  for (final c in convoys) {
    final list = await repo.cachedMembers(c.convoyId);
    if (list != null) members[c.convoyId] = list;
    final recap = ConvoyRecap.fromJson(c.recapJson);
    if (recap != null && me != null) {
      for (final m in recap.members) {
        if (m.userId == me) dj[c.convoyId] = m.djTracks;
      }
    }
  }
  return StatsInput(
    trips: trips,
    extents: extents,
    endpoints: endpoints,
    roadsByTrip: roads,
    places: places,
    vehicles: vehicles,
    fuelStats: fuel,
    convoys: convoys,
    convoyMembers: members,
    djTracksByConvoy: dj,
    myUserId: me,
    fuelPricePerLitre: price,
    defaultLPer100km: economy,
  );
});

final driverStatsProvider = FutureProvider.family<DriverStats, StatsWindow>((
  ref,
  window,
) async {
  final input = await ref.watch(statsInputProvider.future);
  final now = ref.watch(statsClockProvider)();
  return computeDriverStats(input, StatsRange.forWindow(window, now));
});

/// The season the Wrapped shows: the current quarter, or the previous one
/// while the current quarter has fewer than three trips and the previous
/// one has some (the first days of a season would otherwise look empty).
final wrappedStatsProvider = FutureProvider<DriverStats>((ref) async {
  final input = await ref.watch(statsInputProvider.future);
  final now = ref.watch(statsClockProvider)();
  final current = computeDriverStats(input, StatsRange.season(now));
  if (current.totals.trips >= 3) return current;
  final previous = computeDriverStats(input, StatsRange.previousSeason(now));
  return previous.isEmpty ? current : previous;
});

/// Display units for the stats: the units setting, else the region most of
/// the trips were matched in, else the device locale.
final statsUnitsProvider = Provider<SpeedUnits>((ref) {
  final setting = ref.watch(unitsSettingProvider).value ?? UnitsSetting.auto;
  final trips = ref.watch(scoredTripsForStatsProvider).value ?? const [];
  final counts = <String, int>{};
  for (final t in trips) {
    final r = t.trip.packRegion;
    if (r != null) counts[r] = (counts[r] ?? 0) + 1;
  }
  String? top;
  var n = 0;
  for (final e in counts.entries) {
    if (e.value > n) {
      top = e.key;
      n = e.value;
    }
  }
  return resolveUnits(setting, packRegion: top);
});
