import 'dart:convert';

import 'package:drivalry_packs/drivalry_packs.dart';
import 'package:test/test.dart';

void main() {
  const json = '''
{
  "schemaVersion": 1,
  "builtAt": "2026-11-02T03:14:15Z",
  "packs": [
    {
      "region": "us-dc",
      "name": "District of Columbia",
      "url": "https://github.com/RyanCrawfordOrr/drivalry/releases/download/packs-2026.11/us-dc.pack",
      "bytes": 1234567,
      "sha256": "abc",
      "osmTimestamp": "2026-10-31T21:20:04Z",
      "wayCount": 23456,
      "bbox": [38.79, -77.12, 38.996, -76.909]
    },
    {
      "region": "us-md",
      "name": "Maryland",
      "url": "https://example.invalid/us-md.pack",
      "bytes": 9,
      "sha256": "def",
      "osmTimestamp": "2026-10-31T21:20:04Z",
      "wayCount": 2,
      "bbox": [37.88, -79.49, 39.73, -74.98]
    }
  ]
}
''';

  test('round trips', () {
    final index = PackIndex.fromJson(jsonDecode(json) as Map<String, dynamic>);
    expect(index.schemaVersion, 1);
    expect(index.builtAt, '2026-11-02T03:14:15Z');
    expect(index.packs, hasLength(2));
    final dc = index.byRegion('us-dc')!;
    expect(dc.name, 'District of Columbia');
    expect(dc.bytes, 1234567);
    expect(dc.wayCount, 23456);
    expect(dc.bbox, [38.79, -77.12, 38.996, -76.909]);
    expect(index.byRegion('us-zz'), isNull);

    final again = PackIndex.fromJson(
      jsonDecode(jsonEncode(index.toJson())) as Map<String, dynamic>,
    );
    expect(jsonEncode(again.toJson()), jsonEncode(index.toJson()));
  });

  test('regionsFor uses bounding boxes', () {
    final index = PackIndex.fromJson(jsonDecode(json) as Map<String, dynamic>);
    expect(index.regionsFor(38.8977, -77.0365).map((p) => p.region), [
      'us-dc',
      'us-md',
    ]);
    expect(index.regionsFor(39.3, -76.6).map((p) => p.region), ['us-md']);
    expect(index.regionsFor(34.05, -118.24), isEmpty);
  });

  test('rejects a malformed bbox', () {
    expect(
      () => PackIndexEntry.fromJson({
        'region': 'x',
        'name': 'x',
        'url': 'x',
        'bytes': 1,
        'sha256': 'x',
        'osmTimestamp': 'x',
        'wayCount': 1,
        'bbox': [1, 2, 3],
      }),
      throwsFormatException,
    );
  });
}
