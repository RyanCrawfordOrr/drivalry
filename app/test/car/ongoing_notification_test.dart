import 'package:drivalry/car/car_snapshot.dart';
import 'package:drivalry/car/ongoing_notification.dart';
import 'package:drivalry/tracking/tracking_models.dart';
import 'package:drivalry_scoring/drivalry_scoring.dart' show SpeedUnits;
import 'package:flutter_test/flutter_test.dart';

CarSnapshot _snap(CarDrive d, {CarConvoy? convoy, SpeedUnits? units}) =>
    CarSnapshot(drive: d, convoy: convoy, units: units ?? SpeedUnits.mph);

void main() {
  test('nothing while idle: the service is not running', () {
    expect(ongoingNotificationFor(CarSnapshot.idle), isNull);
  });

  test('the headline case', () {
    final line = ongoingNotificationFor(
      _snap(
        const CarDrive(
          phase: TrackingPhase.active,
          tripId: 't1',
          speedMps: 13.86, // 31 mph
          limitMps: 15.65,
          posted: 35,
          overMps: 0,
        ),
      ),
    );
    expect(line!.text, 'Recording · Limit 35 · 31 mph · Clean so far');
    expect(line.title, 'Drivalry');
    expect(line.passengerAction, isTrue);
    expect(line.tripId, 't1');
    expect(line.subText, isNull);
  });

  test('over the limit', () {
    final line = ongoingNotificationFor(
      _snap(
        const CarDrive(
          phase: TrackingPhase.active,
          speedMps: 18.8,
          limitMps: 15.65,
          posted: 35,
          overMps: 3.15,
        ),
      ),
    );
    expect(line!.text, 'Recording · Limit 35 · 42 mph · 7 over');
  });

  test('no limit data: no "Limit" part and no claim of cleanliness', () {
    final line = ongoingNotificationFor(
      _snap(const CarDrive(phase: TrackingPhase.active, speedMps: 18.8)),
    );
    expect(line!.text, 'Recording · 42 mph · No limit data here');
  });

  test('speeds follow the posted unit, else the user setting', () {
    final posted = ongoingNotificationFor(
      _snap(
        const CarDrive(
          phase: TrackingPhase.active,
          speedMps: 13.9,
          limitMps: 13.9,
          posted: 50,
          limitUnit: 'km/h',
          overMps: 0,
        ),
        units: SpeedUnits.mph,
      ),
    );
    expect(posted!.text, 'Recording · Limit 50 · 50 km/h · Clean so far');

    final setting = ongoingNotificationFor(
      _snap(
        const CarDrive(phase: TrackingPhase.active, speedMps: 13.9),
        units: SpeedUnits.kmh,
      ),
    );
    expect(setting!.text, 'Recording · 50 km/h · No limit data here');
  });

  test('passenger replaces the limit line and drops the action', () {
    final line = ongoingNotificationFor(
      _snap(
        const CarDrive(
          phase: TrackingPhase.active,
          tripId: 't1',
          speedMps: 18.8,
          limitMps: 15.65,
          posted: 35,
          overMps: 3.15,
          passenger: true,
        ),
      ),
    );
    expect(line!.text, 'Recording · Passenger · not scored');
    expect(line.passengerAction, isFalse);
  });

  test('tentative has no action yet', () {
    final line = ongoingNotificationFor(
      _snap(const CarDrive(phase: TrackingPhase.tentative, tripId: 't3')),
    );
    expect(line!.text, 'Looks like a drive · confirming');
    expect(line.passengerAction, isFalse);
    expect(line.tripId, 't3');
  });

  test('an active convoy adds a second line', () {
    final line = ongoingNotificationFor(
      _snap(
        const CarDrive(phase: TrackingPhase.active, speedMps: 10),
        convoy: const CarConvoy(
          id: 'c1',
          name: 'Lake run',
          status: 'active',
          members: [
            CarMember(id: 'a', name: 'A', initials: 'A'),
            CarMember(id: 'b', name: 'B', initials: 'B'),
            CarMember(id: 'c', name: 'C', initials: 'C'),
          ],
        ),
      ),
    );
    expect(line!.subText, 'Convoy · Lake run · 3 cars');

    final planning = ongoingNotificationFor(
      _snap(
        const CarDrive(phase: TrackingPhase.active, speedMps: 10),
        convoy: const CarConvoy(id: 'c1', name: 'Later', status: 'planning'),
      ),
    );
    expect(planning!.subText, isNull);
  });

  test('wire form and equality', () {
    const a = OngoingNotificationLine(
      title: 'Drivalry',
      text: 'x',
      passengerAction: true,
      tripId: 't',
    );
    const b = OngoingNotificationLine(
      title: 'Drivalry',
      text: 'x',
      passengerAction: true,
      tripId: 't',
    );
    expect(a, b);
    expect(a.toWire(), {
      'title': 'Drivalry',
      'text': 'x',
      'subText': null,
      'passengerAction': true,
      'tripId': 't',
    });
  });
}
