import 'package:drivalry/tracking/tracking_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parkedFix parses with integral JSON numbers and round-trips', () {
    final e = TrackingEvent.fromMap({
      'type': 'parkedFix',
      'tripId': null,
      't': 1700000000000,
      'lat': 38,
      'lon': -77,
      'accuracy': 65,
      'speed': 0,
    });
    expect(e, isA<ParkedFixEvent>());
    final p = e as ParkedFixEvent;
    expect(p.tripId, isNull);
    expect(p.lat, 38.0);
    expect(p.accuracy, 65.0);
    expect(p.speed, 0.0);
    expect(p.heading, isNull);
    expect(p.toMap()['type'], 'parkedFix');
    expect(p.toMap().containsKey('heading'), isFalse);
  });

  test('parkedFix without coordinates is dropped', () {
    expect(
      TrackingEvent.fromMap({'type': 'parkedFix', 't': 1, 'lat': 38}),
      isNull,
    );
  });

  test('LastKnownLocation.fromMap', () {
    final l = LastKnownLocation.fromMap({
      't': 5,
      'lat': 1.5,
      'lon': 2.5,
      'accuracy': 10,
      'heading': 90,
    });
    expect(l.t, 5);
    expect(l.heading, 90.0);
    expect(l.speed, isNull);
    expect(l.toMap()['lon'], 2.5);
  });
}
