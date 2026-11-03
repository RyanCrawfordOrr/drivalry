import 'package:drivalry/car/carplay_stub.dart';
import 'package:drivalry/car/live_activity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const driving = LiveActivityContent(
    limitPosted: 45,
    limitUnit: 'mph',
    speedPosted: 50,
    cleanSoFar: true,
    overBy: 5,
    roadName: 'Main St',
    tripMinutes: 10,
    updatedAt: 0,
  );
  const convoying = LiveActivityContent(
    limitPosted: 65,
    limitUnit: 'mph',
    speedPosted: 63,
    cleanSoFar: false,
    tripMinutes: 42,
    convoyName: 'Road trip',
    gapMinutes: 3,
    etaMinutes: 20,
    talking: 'Sam',
    updatedAt: 0,
  );

  test('parked plan has four tabs and no buttons', () {
    final p = CarPlayPlan.from(null);
    expect(p.tabs.map((t) => t.title), ['Drive', 'Convoy', 'Talk', 'Stops']);
    expect(p.tabs.map((t) => t.kind), [
      CarPlayTemplateKind.information,
      CarPlayTemplateKind.list,
      CarPlayTemplateKind.grid,
      CarPlayTemplateKind.pointOfInterest,
    ]);
    expect(p.drive.items.single.title, 'Parked');
    expect(p.drive.actions, isEmpty);
    expect(p.convoy.items.single.title, 'No active convoy');
    expect(p.convoy.actions, isEmpty);
    expect(p.talk.items.single.title, 'Join a convoy to talk');
    expect(p.talk.items.single.action, isNull);
    expect(p.stops.items.single.title, 'No active convoy');
    expect(p.stopPins, isEmpty);
  });

  test('a drive shows clean-so-far, the limit and the passenger button', () {
    final p = CarPlayPlan.from(driving);
    expect(p.drive.items.map((i) => i.title), ['Clean so far', 'Limit 45 mph']);
    expect(p.drive.items[0].detail, '10 min');
    expect(p.drive.items[1].detail, '50, 5 over');
    expect(p.drive.actions.single.action, CarPlayAction.markPassenger);
    expect(p.convoy.items.single.title, 'No active convoy');
    expect(p.stops.items.single.title, 'No active convoy');
  });

  test('under the limit the detail is the plain speed', () {
    const c = LiveActivityContent(
      limitPosted: 30,
      limitUnit: 'km/h',
      speedPosted: 28,
      cleanSoFar: true,
      tripMinutes: 1,
      updatedAt: 0,
    );
    final p = CarPlayPlan.from(c);
    expect(p.drive.items[1].title, 'Limit 30 km/h');
    expect(p.drive.items[1].detail, '28 km/h');
  });

  test('convoy tab lists members with gap and eta, talk and stops fill', () {
    final p = CarPlayPlan.from(
      convoying,
      members: const [
        CarPlayMember(name: 'Ryan', gapMinutes: 0, etaMinutes: 18),
        CarPlayMember(name: 'Sam', gapMinutes: 3, etaMinutes: 21),
        CarPlayMember(name: 'Jo', lost: true),
      ],
      stops: const [
        CarPlayStop(
          id: 's1',
          name: 'Buc-ee\'s',
          lat: 30.1,
          lon: -97.6,
          votes: 2,
        ),
        CarPlayStop(
          id: 's2',
          name: 'Overlook',
          lat: 30.2,
          lon: -97.7,
          votes: 3,
          agreed: true,
        ),
      ],
    );
    expect(p.drive.items[0].title, 'Recording');
    expect(p.convoy.items.map((i) => i.title), ['Ryan', 'Sam', 'Jo · lost']);
    expect(p.convoy.items[0].detail, 'leading · ETA 18 min');
    expect(p.convoy.items[1].detail, '3 min behind · ETA 21 min');
    expect(p.convoy.items[2].detail, isNull);
    expect(p.convoy.actions.map((a) => a.action), [
      CarPlayAction.regroupHere,
      CarPlayAction.proposeStop,
    ]);
    expect(p.talk.items.single.title, 'Hold to talk');
    expect(p.talk.items.single.detail, 'Sam talking');
    expect(p.talk.items.single.action, CarPlayAction.pushToTalk);
    expect(p.stops.items.map((i) => i.detail), ['2 votes', 'Agreed']);
    expect(p.stops.items.map((i) => i.stopId), ['s1', 's2']);
    expect(p.stopPins.length, 2);
  });

  test('talk tab remembers the last speaker when nobody is talking', () {
    const quiet = LiveActivityContent(
      limitUnit: 'mph',
      cleanSoFar: true,
      tripMinutes: 5,
      convoyName: 'Road trip',
      updatedAt: 0,
    );
    final p = CarPlayPlan.from(
      quiet,
      lastTalker: 'Sam',
      lastTalkAgoSeconds: 10,
    );
    expect(p.talk.items.single.detail, 'Last: Sam, 10 s ago');
    expect(p.convoy.items.single.title, 'Waiting for positions');
    expect(p.stops.items.single.title, 'No stops yet');
    final later = CarPlayPlan.from(
      quiet,
      lastTalker: 'Sam',
      lastTalkAgoSeconds: 150,
    );
    expect(later.talk.items.single.detail, 'Last: Sam, 2 min ago');
  });

  test('every string fits a car row and carries no roast', () {
    const longRoad = LiveActivityContent(
      limitUnit: 'mph',
      cleanSoFar: true,
      tripMinutes: 3,
      roadName:
          'Martin Luther King Junior Memorial Parkway Northbound Frontage Road',
      updatedAt: 0,
    );
    final p = CarPlayPlan.from(longRoad);
    final strings = [
      for (final t in p.tabs) ...[
        t.title,
        for (final i in t.items) ...[i.title, ?i.detail],
        for (final a in t.actions) a.title,
      ],
    ];
    for (final s in strings) {
      expect(s.length, lessThanOrEqualTo(carPlayMaxChars), reason: s);
      expect(s.toLowerCase(), isNot(contains('roast')));
    }
    expect(p.drive.items[1].title, endsWith('…'));
    expect(clipForCar('short'), 'short');
  });

  test('toMap is plain data the Swift side can decode', () {
    final m = CarPlayPlan.from(driving).toMap();
    final tabs = m['tabs'] as List;
    expect(tabs.length, 4);
    final drive = tabs.first as Map<String, Object?>;
    expect(drive['kind'], 'information');
    final rows = drive['items'] as List;
    expect((rows.first as Map)['title'], 'Clean so far');
    final actions = drive['actions'] as List;
    expect((actions.first as Map)['action'], 'markPassenger');
    expect((rows.first as Map).containsKey('action'), isFalse);
    expect(m['pins'], isEmpty);
  });
}
