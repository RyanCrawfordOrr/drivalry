import 'package:drift/drift.dart' show Value;
import 'package:drivalry/app/bootstrap.dart';
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/models/trip_phase.dart';
import 'package:drivalry/features/drive/trip_detail_screen.dart';
import 'package:drivalry/tracking/providers.dart';
import 'package:drivalry/tracking/weather.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_tracking_port.dart';
import 'support/sqlite_support.dart';
import 'support/widget_support.dart';

/// Tests run without `--dart-define`, so the build has no Maps key: the
/// provider must settle to false without touching the plugin, and the trip
/// map must show its placeholder rather than build a `GoogleMap`.
void main() {
  final skipReason = skipWithoutSqlite();
  final skip = skipReason != null;

  test(
    'mapsReadyProvider is false without a key and skips the plugin',
    () async {
      final port = FakeTrackingPort();
      final container = ProviderContainer(
        overrides: [trackingPortProvider.overrideWithValue(port)],
      );
      addTearDown(container.dispose);
      addTearDown(port.dispose);
      expect(await container.read(mapsReadyProvider.future), isFalse);
      expect(port.calls, isNot(contains('setMapsApiKey')));
    },
  );

  testWidgets('the trip map shows a placeholder until the SDK has a key', (
    tester,
  ) async {
    final db = memoryDatabase();
    final port = FakeTrackingPort();
    await db.ensureTrip(
      TripsCompanion.insert(
        id: 'm',
        startedAt: 1000,
        phase: TripPhase.scored.wire,
        createdAt: 1000,
        endedAt: const Value(3000),
        passengerAnswered: const Value(true),
      ),
    );
    await db.insertFixBatch('m', 3000, [
      SamplesCompanion.insert(
        tripId: 'm',
        t: 1000,
        lat: 36.16,
        lon: -86.78,
        accuracy: 5,
        speed: const Value(10),
      ),
      SamplesCompanion.insert(
        tripId: 'm',
        t: 2000,
        lat: 36.161,
        lon: -86.78,
        accuracy: 5,
        speed: const Value(10),
      ),
      SamplesCompanion.insert(
        tripId: 'm',
        t: 3000,
        lat: 36.162,
        lon: -86.78,
        accuracy: 5,
        speed: const Value(10),
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          trackingPortProvider.overrideWithValue(port),
          weatherClientProvider.overrideWithValue(const NoWeather()),
        ],
        child: const MaterialApp(home: TripDetailScreen(tripId: 'm')),
      ),
    );
    await pumpFor(tester, const Duration(seconds: 1));

    expect(find.text('Map not available in this version.'), findsOneWidget);
    expect(find.textContaining('dart-define'), findsNothing);
    await unmountAndSettle(tester);
    await port.dispose();
    await db.close();
  }, skip: skip);
}
