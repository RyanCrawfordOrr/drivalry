import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:drivalry_packs/drivalry_packs.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sql;

import '../data/db/database.dart';
import '../data/db/pack_bounds.dart';

/// Thrown when a download or import cannot be used.
class PackInstallException implements Exception {
  const PackInstallException(this.message);
  final String message;

  @override
  String toString() => 'PackInstallException: $message';
}

/// Decides whether a large download may happen now. Wi-Fi only by default
/// (docs/03 §4.3).
abstract class DownloadPolicy {
  Future<bool> allowsLargeDownload();
}

class WifiOnlyPolicy implements DownloadPolicy {
  WifiOnlyPolicy([Connectivity? connectivity])
    : _connectivity = connectivity ?? Connectivity();
  final Connectivity _connectivity;

  @override
  Future<bool> allowsLargeDownload() async {
    final results = await _connectivity.checkConnectivity();
    return results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet);
  }
}

class AlwaysAllowPolicy implements DownloadPolicy {
  const AlwaysAllowPolicy();

  @override
  Future<bool> allowsLargeDownload() async => true;
}

/// Installs, verifies and removes speed-limit packs (docs/03 §4.3,
/// docs/07 §6). The `Packs` table is the record of what is installed; files
/// live in `<packsDir>/<region>.pack`.
class PackManager {
  PackManager(
    this._db,
    this._http, {
    required this.indexUrl,
    required this.packsDir,
    DownloadPolicy? policy,
    int Function()? now,
  }) : _policy = policy ?? WifiOnlyPolicy(),
       _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final AppDatabase _db;
  final http.Client _http;
  final String indexUrl;

  /// Where `.pack` files live.
  final Future<Directory> Function() packsDir;
  final DownloadPolicy _policy;
  final int Function() _now;

  static const _indexKey = 'packIndexJson';
  static const _indexAtKey = 'packIndexFetchedAt';

  /// How often the catalogue is re-fetched on its own.
  static const indexMaxAge = Duration(days: 30);

  /// Schema versions this app can read.
  static const supportedSchema = 1;

  PackIndex? _index;

  /// The catalogue, from cache unless stale or [force].
  Future<PackIndex?> refreshIndex({bool force = false}) async {
    if (!force) {
      final cached = await _cachedIndex();
      if (cached != null) return _index = cached;
    }
    try {
      final res = await _http
          .get(Uri.parse(indexUrl))
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        return _index ??= await _cachedIndex(ignoreAge: true);
      }
      final index = PackIndex.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>,
      );
      await _db.setSetting(_indexKey, res.body);
      await _db.setSetting(_indexAtKey, '${_now()}');
      return _index = index;
    } catch (_) {
      return _index ??= await _cachedIndex(ignoreAge: true);
    }
  }

  Future<PackIndex?> _cachedIndex({bool ignoreAge = false}) async {
    final json = await _db.getSetting(_indexKey);
    if (json == null) return null;
    if (!ignoreAge) {
      final at = int.tryParse(await _db.getSetting(_indexAtKey) ?? '') ?? 0;
      if (_now() - at > indexMaxAge.inMilliseconds) return null;
    }
    try {
      return PackIndex.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Makes sure a pack covering the point is installed. Returns it, or null
  /// when none exists in the catalogue or the policy says not now.
  Future<Pack?> ensureRegionFor(
    double lat,
    double lon, {
    bool force = false,
    void Function(double fraction)? onProgress,
  }) async {
    final installed = smallestPackContaining(
      await _db.installedPacks(),
      lat,
      lon,
    );
    if (installed != null) return installed;
    final index = await refreshIndex(force: force);
    if (index == null) return null;
    final candidates = index.regionsFor(lat, lon);
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => _area(a).compareTo(_area(b)));
    if (!force && !await _policy.allowsLargeDownload()) return null;
    return install(candidates.first, onProgress: onProgress);
  }

  static double _area(PackIndexEntry e) =>
      (e.maxLat - e.minLat) * (e.maxLon - e.minLon);

  /// Downloads [entry] to a temp file, checks its hash, swaps it into place
  /// and records it. The previous file for the region is removed after the
  /// new row is written.
  Future<Pack> install(
    PackIndexEntry entry, {
    void Function(double fraction)? onProgress,
  }) async {
    final dir = await packsDir();
    await dir.create(recursive: true);
    final tmp = File(p.join(dir.path, '${entry.region}.download'));
    final digest = await _download(
      Uri.parse(entry.url),
      tmp,
      entry.bytes,
      onProgress,
    );
    if (digest != entry.sha256.toLowerCase()) {
      await tmp.delete();
      throw PackInstallException('${entry.region}: checksum mismatch');
    }
    return _adopt(
      tmp,
      region: entry.region,
      name: entry.name,
      osmTimestamp: entry.osmTimestamp,
      sha256: digest,
      wayCount: entry.wayCount,
      bbox: entry.bbox,
    );
  }

  /// Installs a `.pack` the user put on the phone (or a test wrote). The
  /// region and bounds are read from the file itself.
  Future<Pack> importLocalFile(String path) async {
    final src = File(path);
    if (!await src.exists()) throw PackInstallException('no file at $path');
    final dir = await packsDir();
    await dir.create(recursive: true);
    final tmp = File(p.join(dir.path, importTempName));
    try {
      await src.copy(tmp.path);
      final digest = await _sha256Of(tmp);
      return await _adoptFromMeta(tmp, digest);
    } catch (_) {
      await _deleteIfExists(tmp);
      rethrow;
    }
  }

  /// One fixed temp name for imports, so a failed attempt never leaves a
  /// uniquely named orphan behind and a retry overwrites the last one.
  static const importTempName = 'import.download';

  /// Removes temp files from interrupted installs and imports. Called at
  /// start-up; anything older than an hour is nobody's in-flight download.
  Future<int> sweepTempFiles({
    Duration olderThan = const Duration(hours: 1),
  }) async {
    final dir = await packsDir();
    if (!await dir.exists()) return 0;
    final cutoff = DateTime.now().subtract(olderThan);
    var removed = 0;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      final isTemp =
          name.endsWith('.download') ||
          name.endsWith('.pack.new') ||
          name.endsWith('.pack.old');
      if (!isTemp) continue;
      try {
        if ((await entity.lastModified()).isBefore(cutoff)) {
          await entity.delete();
          removed++;
        }
      } catch (_) {
        // Another install may hold it; try again next start.
      }
    }
    return removed;
  }

  /// Downloads any `.pack` URL (no catalogue entry, so no expected hash;
  /// the file's own meta is trusted after the schema check).
  Future<Pack> importFromUrl(
    String url, {
    void Function(double)? onProgress,
  }) async {
    final dir = await packsDir();
    await dir.create(recursive: true);
    final tmp = File(p.join(dir.path, importTempName));
    final digest = await _download(Uri.parse(url), tmp, null, onProgress);
    return _adoptFromMeta(tmp, digest);
  }

  Future<Pack> _adoptFromMeta(File tmp, String digest) async {
    final Map<String, String> meta;
    final List<double> bbox;
    final int wayCount;
    try {
      final pack = SqlitePack.open(tmp.path);
      try {
        meta = pack.meta;
      } finally {
        pack.close();
      }
      bbox = _bboxOf(tmp.path);
      wayCount = int.tryParse(meta['way_count'] ?? '') ?? 0;
    } on UnsupportedPackException catch (e) {
      await tmp.delete();
      throw PackInstallException(e.message);
    } catch (e) {
      await tmp.delete();
      throw PackInstallException('not a pack file: $e');
    }
    final region = meta['region'];
    if (region == null || region.isEmpty) {
      await tmp.delete();
      throw PackInstallException('pack has no region in meta');
    }
    return _adopt(
      tmp,
      region: region,
      name: meta['region_name'] ?? region,
      osmTimestamp: meta['osm_replication_timestamp'] ?? '',
      sha256: digest,
      wayCount: wayCount,
      bbox: bbox,
    );
  }

  Future<Pack> _adopt(
    File tmp, {
    required String region,
    required String name,
    required String osmTimestamp,
    required String sha256,
    required int wayCount,
    required List<double> bbox,
  }) async {
    final dir = await packsDir();
    final previous = await _db.packByRegion(region);
    final target = File(p.join(dir.path, '$region.pack'));
    final staged = File(p.join(dir.path, '$region.pack.new'));
    if (await staged.exists()) await staged.delete();
    await tmp.rename(staged.path);
    // Validate the staged file opens before touching the live one.
    SqlitePack.open(staged.path).close();
    if (await target.exists()) {
      final old = File(p.join(dir.path, '$region.pack.old'));
      if (await old.exists()) await old.delete();
      await target.rename(old.path);
    }
    await staged.rename(target.path);
    final row = PacksCompanion.insert(
      region: region,
      name: name,
      osmTimestamp: osmTimestamp,
      path: target.path,
      sha256: sha256,
      bytes: await target.length(),
      wayCount: wayCount,
      bboxMinLat: bbox[0],
      bboxMinLon: bbox[1],
      bboxMaxLat: bbox[2],
      bboxMaxLon: bbox[3],
      installedAt: _now(),
    );
    await _db.upsertPack(row);
    final old = File(p.join(dir.path, '$region.pack.old'));
    if (await old.exists()) await old.delete();
    if (previous != null && previous.path != target.path) {
      final f = File(previous.path);
      if (await f.exists()) await f.delete();
    }
    return (await _db.packByRegion(region))!;
  }

  Future<void> removeRegion(String region) async {
    final pack = await _db.packByRegion(region);
    await _db.removePack(region);
    if (pack != null) {
      final f = File(pack.path);
      if (await f.exists()) await f.delete();
    }
  }

  /// Re-downloads installed regions whose catalogue entry is newer.
  /// Returns the regions updated. Respects the download policy.
  Future<List<String>> updateInstalled({bool force = false}) async {
    final index = await refreshIndex(force: force);
    if (index == null) return const [];
    final updated = <String>[];
    for (final installed in await _db.installedPacks()) {
      final entry = index.byRegion(installed.region);
      if (entry == null || entry.sha256.toLowerCase() == installed.sha256) {
        continue;
      }
      if (!force && !await _policy.allowsLargeDownload()) break;
      await install(entry);
      updated.add(installed.region);
    }
    return updated;
  }

  // ------------------------------------------------------------- helpers --

  /// Streams [uri] into [target] and returns its SHA-256. On any failure the
  /// partial file is removed before the error propagates, so the packs
  /// directory never accumulates half-downloads.
  Future<String> _download(
    Uri uri,
    File target,
    int? expectedBytes,
    void Function(double)? onProgress,
  ) async {
    try {
      final res = await _http.send(http.Request('GET', uri));
      if (res.statusCode != 200) {
        // Release the connection; the body is not wanted.
        await res.stream.drain<void>().catchError((_) {});
        throw PackInstallException(
          'download failed: HTTP ${res.statusCode} for $uri',
        );
      }
      final total = expectedBytes ?? res.contentLength;
      final sink = target.openWrite();
      final digestSink = _DigestSink();
      final hasher = sha256.startChunkedConversion(digestSink);
      var received = 0;
      try {
        await for (final chunk in res.stream) {
          sink.add(chunk);
          hasher.add(chunk);
          received += chunk.length;
          if (onProgress != null && total != null && total > 0) {
            onProgress((received / total).clamp(0, 1));
          }
        }
      } finally {
        await sink.close();
      }
      hasher.close();
      return digestSink.hex;
    } catch (_) {
      await _deleteIfExists(target);
      rethrow;
    }
  }

  static Future<void> _deleteIfExists(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {
      // Best effort; the start-up sweep catches stragglers.
    }
  }

  static Future<String> _sha256Of(File f) async {
    final digestSink = _DigestSink();
    final hasher = sha256.startChunkedConversion(digestSink);
    await for (final chunk in f.openRead()) {
      hasher.add(chunk);
    }
    hasher.close();
    return digestSink.hex;
  }

  /// Bounding box of every tile in the pack: `[minLat, minLon, maxLat, maxLon]`.
  static List<double> _bboxOf(String path) {
    final db = sql.sqlite3.open(path, mode: sql.OpenMode.readOnly);
    try {
      var minLat = 90.0, minLon = 180.0, maxLat = -90.0, maxLon = -180.0;
      var any = false;
      for (final row in db.select('SELECT geohash FROM tiles')) {
        final box = Geohash.decode(row['geohash'] as String);
        any = true;
        if (box.minLat < minLat) minLat = box.minLat;
        if (box.minLon < minLon) minLon = box.minLon;
        if (box.maxLat > maxLat) maxLat = box.maxLat;
        if (box.maxLon > maxLon) maxLon = box.maxLon;
      }
      if (!any) throw const PackInstallException('pack has no tiles');
      return [minLat, minLon, maxLat, maxLon];
    } finally {
      db.close();
    }
  }
}

/// Collects the single digest a chunked hash conversion emits.
class _DigestSink implements Sink<Digest> {
  Digest? _digest;

  String get hex => _digest?.toString() ?? '';

  @override
  void add(Digest data) => _digest = data;

  @override
  void close() {}
}
