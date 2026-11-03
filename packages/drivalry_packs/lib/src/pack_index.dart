/// `index.json` from a packs release (`docs/07-pack-format.md` §6).
library;

/// One downloadable pack.
class PackIndexEntry {
  const PackIndexEntry({
    required this.region,
    required this.name,
    required this.url,
    required this.bytes,
    required this.sha256,
    required this.osmTimestamp,
    required this.wayCount,
    required this.minLat,
    required this.minLon,
    required this.maxLat,
    required this.maxLon,
  });

  factory PackIndexEntry.fromJson(Map<String, dynamic> json) {
    final bbox = (json['bbox'] as List).cast<num>();
    if (bbox.length != 4) {
      throw FormatException('bbox must have 4 numbers, got ${bbox.length}');
    }
    return PackIndexEntry(
      region: json['region'] as String,
      name: json['name'] as String,
      url: json['url'] as String,
      bytes: (json['bytes'] as num).toInt(),
      sha256: json['sha256'] as String,
      osmTimestamp: json['osmTimestamp'] as String,
      wayCount: (json['wayCount'] as num).toInt(),
      minLat: bbox[0].toDouble(),
      minLon: bbox[1].toDouble(),
      maxLat: bbox[2].toDouble(),
      maxLon: bbox[3].toDouble(),
    );
  }

  /// Region code, e.g. `us-dc`.
  final String region;

  /// Human name, e.g. `District of Columbia`.
  final String name;
  final String url;
  final int bytes;

  /// Lower-case hex SHA-256 of the file.
  final String sha256;

  /// ISO-8601 OSM replication timestamp the pack was built from.
  final String osmTimestamp;
  final int wayCount;
  final double minLat;
  final double minLon;
  final double maxLat;
  final double maxLon;

  /// `[minLat, minLon, maxLat, maxLon]`.
  List<double> get bbox => [minLat, minLon, maxLat, maxLon];

  /// True when the point lies inside the region's bounding box.
  bool contains(double lat, double lon) =>
      lat >= minLat && lat <= maxLat && lon >= minLon && lon <= maxLon;

  Map<String, Object?> toJson() => {
    'region': region,
    'name': name,
    'url': url,
    'bytes': bytes,
    'sha256': sha256,
    'osmTimestamp': osmTimestamp,
    'wayCount': wayCount,
    'bbox': bbox,
  };
}

/// The whole index.
class PackIndex {
  const PackIndex({
    required this.schemaVersion,
    required this.builtAt,
    required this.packs,
  });

  factory PackIndex.fromJson(Map<String, dynamic> json) => PackIndex(
    schemaVersion: (json['schemaVersion'] as num).toInt(),
    builtAt: json['builtAt'] as String,
    packs: [
      for (final p in json['packs'] as List)
        PackIndexEntry.fromJson(p as Map<String, dynamic>),
    ],
  );

  final int schemaVersion;
  final String builtAt;
  final List<PackIndexEntry> packs;

  /// Entry for a region code, or null.
  PackIndexEntry? byRegion(String region) {
    for (final p in packs) {
      if (p.region == region) return p;
    }
    return null;
  }

  /// Every pack whose bounding box contains the point. Bounding boxes of
  /// neighbouring states overlap, so this can return more than one; callers
  /// usually install all of them or pick the one with the smallest box.
  List<PackIndexEntry> regionsFor(double lat, double lon) => [
    for (final p in packs)
      if (p.contains(lat, lon)) p,
  ];

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'builtAt': builtAt,
    'packs': [for (final p in packs) p.toJson()],
  };
}
