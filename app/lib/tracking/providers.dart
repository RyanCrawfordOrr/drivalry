import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../data/crash/crash_monitor.dart';
import '../data/db/database.dart';
import '../widgets/units.dart';
import 'tracking_channel.dart';
import 'tracking_port.dart';
import 'trip_finalizer.dart';
import 'trip_recorder.dart';
import 'weather.dart';

/// The native plugin by default; tests and the simulator override this.
final trackingPortProvider = Provider<TrackingPort>((ref) => TrackingChannel());

/// One HTTP client for the app (weather, pack downloads).
final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final weatherClientProvider = Provider<WeatherClient>(
  (ref) => OpenMeteoClient(ref.watch(httpClientProvider)),
);

final tripFinalizerProvider = Provider<TripFinalizer>(
  (ref) => TripFinalizer(
    ref.watch(databaseProvider),
    weather: ref.watch(weatherClientProvider),
  ),
);

/// Writes events to the database and hands ended trips to the finalizer.
final tripRecorderProvider = Provider<TripRecorder>((ref) {
  final finalizer = ref.watch(tripFinalizerProvider);
  return TripRecorder(
    ref.watch(databaseProvider),
    onTripEnded: (tripId) => finalizer.finalize(tripId),
    onCrashCandidate: (e) =>
        ref.read(crashMonitorProvider.notifier).onCandidate(e),
  );
});

/// Trips for the Drive tab, newest first.
final recentTripsProvider = StreamProvider<List<TripWithScore>>(
  (ref) => ref.watch(databaseProvider).watchRecentTrips(),
);

/// Trips whose "Were you the passenger?" question is still open.
final unansweredTripsProvider = StreamProvider<List<Trip>>(
  (ref) => ref.watch(databaseProvider).watchUnansweredTrips(),
);

/// One trip with its score, live.
final tripProvider = StreamProvider.family<TripWithScore?, String>((ref, id) {
  final db = ref.watch(databaseProvider);
  return db.watchTrip(id).asyncMap((trip) async {
    if (trip == null) return null;
    return TripWithScore(trip, await db.scoreFor(id));
  });
});

final unitsSettingProvider = StreamProvider<UnitsSetting>(
  (ref) => ref
      .watch(databaseProvider)
      .watchSetting('units')
      .map(UnitsSetting.fromWire),
);
