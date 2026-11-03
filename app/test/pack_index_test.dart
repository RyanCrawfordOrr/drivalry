import 'package:drivalry_packs/drivalry_packs.dart';
import 'package:flutter_test/flutter_test.dart';

const indexJson = {
  'schemaVersion': 1,
  'builtAt': '2026-11-02T03:14:15Z',
  'packs': [
    {
      'region': 'us-tn',
      'name': 'Tennessee',
      'url': 'https://example.test/us-tn.pack',
      'bytes': 10,
      'sha256': 'aa',
      'osmTimestamp': '2026-10-31T00:00:00Z',
      'wayCount': 5,
      'bbox': [34.98, -90.31, 36.68, -81.65],
    },
    {
      'region': 'us-ky',
      'name': 'Kentucky',
      'url': 'https://example.test/us-ky.pack',
      'bytes': 10,
      'sha256': 'bb',
      'osmTimestamp': '2026-10-31T00:00:00Z',
      'wayCount': 5,
      'bbox': [36.49, -89.57, 39.15, -81.96],
    },
  ],
};

void main() {
  test('regionsFor returns every region whose box holds the point', () {
    final index = PackIndex.fromJson(indexJson);
    expect(index.regionsFor(36.16, -86.78).map((p) => p.region), ['us-tn']);
    // The TN/KY boxes overlap along the border.
    expect(index.regionsFor(36.6, -86.5).map((p) => p.region), [
      'us-tn',
      'us-ky',
    ]);
    expect(index.regionsFor(40.7, -74.0), isEmpty);
    expect(index.byRegion('us-ky')?.name, 'Kentucky');
    expect(index.toJson()['packs'], hasLength(2));
  });
}
