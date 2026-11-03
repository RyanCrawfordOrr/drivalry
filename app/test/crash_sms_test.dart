import 'package:drivalry/data/crash/crash_sms.dart';
import 'package:drivalry/tracking/tracking_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('message names the person and carries only a maps link', () {
    final m = crashMessage(name: 'Ryan', lat: 38.8977, lon: -77.0365);
    expect(m, startsWith("Drivalry: Ryan's phone detected a possible crash"));
    expect(m, contains('https://maps.google.com/?q=38.89770,-77.03650'));
    expect(m, endsWith('They have not responded.'));
  });

  test('phone numbers are reduced to digits and a leading plus', () {
    expect(normalisePhone('+1 (555) 123-4567'), '+15551234567');
    expect(normalisePhone('555.123.4567'), '5551234567');
    expect(normalisePhone('call me'), '');
  });

  test('android uses ; between numbers and ?body=', () {
    final u = crashSmsUri(
      numbers: ['+1 555 111 2222', '555-333-4444', 'junk'],
      body: 'hi there & co',
      ios: false,
    );
    expect(
      u.toString(),
      'sms:+15551112222;5553334444?body=hi%20there%20%26%20co',
    );
  });

  test('ios uses , between numbers and &body=', () {
    final u = crashSmsUri(
      numbers: ['+15551112222', '5553334444'],
      body: 'hi',
      ios: true,
    );
    expect(u.toString(), 'sms:+15551112222,5553334444&body=hi');
  });

  test('crashCandidate event round-trips through the wire map', () {
    final e = TrackingEvent.fromMap({
      'type': 'crashCandidate',
      'tripId': 't1',
      't': 5000,
      'peakMps2': 48.5,
      'speedBeforeMps': 14,
      'lat': 1.5,
      'lon': 2.5,
      'accuracy': 7,
    });
    expect(e, isA<CrashCandidateEvent>());
    final c = e as CrashCandidateEvent;
    expect(c.peakMps2, 48.5);
    expect(c.speedBeforeMps, 14.0);
    expect(c.toMap()['type'], 'crashCandidate');
    expect(TrackingEvent.fromMap(c.toMap())!.toMap(), c.toMap());
    // Missing position: not an event.
    expect(
      TrackingEvent.fromMap({'type': 'crashCandidate', 'tripId': 't', 't': 1}),
      isNull,
    );
  });
}
