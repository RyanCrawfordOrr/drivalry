import 'package:drivalry/data/repos/presence_repo.dart';
import 'package:drivalry/features/drive/friends_map/friend_marker.dart';
import 'package:drivalry/widgets/relative_time.dart';
import 'package:flutter_test/flutter_test.dart';

PresenceRow row(
  String id,
  double lat,
  double lon, {
  bool driving = false,
  required DateTime updatedAt,
  String name = '',
}) => PresenceRow(
  userId: id,
  handle: id,
  displayName: name,
  lat: lat,
  lon: lon,
  driving: driving,
  updatedAt: updatedAt,
  battery: 0.42,
);

void main() {
  final now = DateTime.utc(2026, 11, 3, 12);

  test('relativeTime wording', () {
    expect(
      relativeTime(now.subtract(const Duration(seconds: 10)), now),
      'just now',
    );
    expect(
      relativeTime(now.subtract(const Duration(minutes: 4)), now),
      '4 min ago',
    );
    expect(
      relativeTime(now.subtract(const Duration(hours: 2)), now),
      '2 h ago',
    );
    expect(
      relativeTime(now.subtract(const Duration(days: 1)), now),
      'yesterday',
    );
    expect(
      relativeTime(now.subtract(const Duration(days: 5)), now),
      '5 days ago',
    );
    expect(
      relativeTime(now.subtract(const Duration(days: 60)), now),
      matches(r'^\d{4}-\d{2}-\d{2}$'),
    );
  });

  test('markersFrom drops me and sorts newest first', () {
    final rows = [
      row('old', 38, -77, updatedAt: now.subtract(const Duration(hours: 3))),
      row('me', 38, -77, updatedAt: now),
      row(
        'new',
        39,
        -76,
        driving: true,
        updatedAt: now.subtract(const Duration(minutes: 1)),
        name: 'Sam Lee',
      ),
    ];
    final markers = markersFrom(rows, excludeUserId: 'me');
    expect(markers.map((m) => m.id), ['new', 'old']);
    final sam = markers.first;
    expect(sam.title, 'Sam Lee');
    expect(sam.initials, 'SL');
    expect(sam.isDriving(now), isTrue);
    expect(sam.statusLine(now), 'Driving now');
    expect(markers.last.statusLine(now), 'Parked · 3 h ago');
    expect(markers.last.title, '@old');
  });

  test('a day-old driving flag is stale, not driving', () {
    final m = FriendMarker(
      row(
        'x',
        1,
        2,
        driving: true,
        updatedAt: now.subtract(const Duration(hours: 30)),
      ),
    );
    expect(m.isStale(now), isTrue);
    expect(m.isDriving(now), isFalse);
    expect(m.iconKey(now), '@X|false|true'.replaceFirst('@X', 'X'));
  });

  test('boundsOf covers every marker and is never degenerate', () {
    expect(boundsOf(const []), isNull);
    final one = boundsOf([FriendMarker(row('a', 38, -77, updatedAt: now))])!;
    expect(one.southwest.latitude, lessThan(38));
    expect(one.northeast.latitude, greaterThan(38));
    final two = boundsOf([
      FriendMarker(row('a', 38, -77, updatedAt: now)),
      FriendMarker(row('b', 40, -75, updatedAt: now)),
    ])!;
    expect(two.southwest.latitude, lessThanOrEqualTo(38));
    expect(two.northeast.longitude, greaterThanOrEqualTo(-75));
  });

  test(
    'PresenceRow parses the joined profile and falls back to the handle',
    () {
      final r = PresenceRow.fromJson({
        'user_id': 'u1',
        'lat': 38.9,
        'lon': -77.0,
        'speed': 12.5,
        'heading': null,
        'battery': 0.8,
        'driving': true,
        'updated_at': '2026-11-03T11:59:00Z',
        'profiles': {'handle': 'sam', 'display_name': '', 'avatar_path': null},
      });
      expect(r.name, '@sam');
      expect(r.speed, 12.5);
      expect(r.updatedAt.isUtc, isTrue);
      final back = PresenceRow.fromJson(r.toJson());
      expect(back.handle, 'sam');
      expect(back.driving, isTrue);
    },
  );
}
