import 'package:drivalry/data/models/trip_score_view.dart';
import 'package:drivalry/features/drive/event_text.dart';
import 'package:drivalry_scoring/drivalry_scoring.dart';
import 'package:flutter_test/flutter_test.dart';

TripEventView event(
  EventKind kind,
  Severity severity, {
  Map<String, dynamic> detail = const {},
  double durationS = 10,
}) => TripEventView(
  kind: kind,
  severity: severity,
  startT: 0,
  endT: (durationS * 1000).round(),
  durationS: durationS,
  startIdx: 0,
  endIdx: 10,
  lat: 36,
  lon: -86,
  detail: detail,
);

void main() {
  const mph40 = 40 * 0.44704;

  test('braking and cornering say hard or very hard, never m/s²', () {
    final hard = event(
      EventKind.harshBrake,
      Severity.moderate,
      detail: {'peak': 3.4, 'speedAtStart': mph40},
    );
    expect(describeEvent(hard, SpeedUnits.mph), 'Hard brake at 40 mph');
    final veryHard = event(
      EventKind.harshBrake,
      Severity.severe,
      detail: {'peak': 6.1, 'speedAtStart': mph40},
    );
    expect(
      describeEvent(veryHard, SpeedUnits.mph),
      'Very hard brake at 40 mph',
    );
    expect(describeEvent(hard, SpeedUnits.mph), isNot(contains('m/s')));
    expect(
      describeEvent(
        event(
          EventKind.harshAccel,
          Severity.minor,
          detail: {'speedAtStart': 0.0},
        ),
        SpeedUnits.kmh,
      ),
      'Hard acceleration from 0 km/h',
    );
  });

  test('titles use Hard consistently with the descriptions', () {
    expect(eventTitle(EventKind.harshBrake), 'Hard brake');
    expect(eventTitle(EventKind.harshAccel), 'Hard acceleration');
    for (final k in EventKind.values) {
      expect(eventTitle(k), isNot(contains('Harsh')));
    }
  });

  test('speeding names the road when known and stays quiet otherwise', () {
    final named = event(
      EventKind.speeding,
      Severity.moderate,
      durationS: 90,
      detail: {
        'limit': 25 * 0.44704,
        'maxSpeed': 41 * 0.44704,
        'roadName': 'Elm St',
      },
    );
    expect(
      describeEvent(named, SpeedUnits.mph),
      '41 in a 25 for 1 min 30 s on Elm St',
    );
    final unnamed = event(
      EventKind.speeding,
      Severity.moderate,
      durationS: 90,
      detail: {'limit': 25 * 0.44704, 'maxSpeed': 41 * 0.44704},
    );
    expect(describeEvent(unnamed, SpeedUnits.mph), '41 in a 25 for 1 min 30 s');
    expect(
      describeEvent(unnamed, SpeedUnits.mph),
      isNot(contains('that road')),
    );
  });

  test('phone use is plain', () {
    final phone = event(
      EventKind.phoneHandling,
      Severity.moderate,
      durationS: 23,
      detail: {'interactions': 2, 'maxSpeed': 38 * 0.44704},
    );
    expect(
      describeEvent(phone, SpeedUnits.mph),
      'Phone picked up 2 times, 23 seconds at up to 38 mph',
    );
    expect(eventTitle(EventKind.phoneHandling), 'Phone use');
  });
}
