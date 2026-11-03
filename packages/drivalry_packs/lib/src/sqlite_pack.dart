/// A pack file on disk, read through `package:sqlite3`.
library;

import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import 'pack_source.dart';

/// Schema versions this reader understands.
const Set<String> supportedPackSchemas = {'1'};

/// Thrown when a pack file cannot be used by this build of the app.
class UnsupportedPackException implements Exception {
  const UnsupportedPackException(this.message);
  final String message;

  @override
  String toString() => 'UnsupportedPackException: $message';
}

/// Read-only access to a `.pack` SQLite file (`docs/07-pack-format.md` §1).
class SqlitePack extends PackSource {
  SqlitePack._(this.path, this._db, this._meta)
    : _tileStmt = _db.prepare('SELECT ways FROM tiles WHERE geohash = ?'),
      _nameStmt = _db.prepare('SELECT name FROM names WHERE name_id = ?');

  /// Opens the pack at [path] read-only and validates its schema version.
  ///
  /// Throws [UnsupportedPackException] for a schema this reader does not
  /// know, so callers can keep their previous pack.
  static SqlitePack open(String path) {
    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      db.execute('PRAGMA query_only = 1');
      final meta = <String, String>{
        for (final row in db.select('SELECT key, value FROM meta'))
          row['key'] as String: row['value'] as String,
      };
      final schema = meta['schema_version'];
      if (schema == null || !supportedPackSchemas.contains(schema)) {
        throw UnsupportedPackException(
          'Pack $path has schema_version ${schema ?? 'missing'}; '
          'this app understands $supportedPackSchemas',
        );
      }
      return SqlitePack._(path, db, Map.unmodifiable(meta));
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  /// File path this pack was opened from.
  final String path;
  final Database _db;
  final Map<String, String> _meta;
  final PreparedStatement _tileStmt;
  final PreparedStatement _nameStmt;
  final Map<int, String?> _nameCache = {};
  bool _closed = false;

  @override
  Map<String, String> get meta => _meta;

  /// Region code from `meta`.
  String get region => _meta['region'] ?? 'unknown';

  @override
  Uint8List? tileBlob(String geohash) {
    _checkOpen();
    final rows = _tileStmt.select([geohash]);
    if (rows.isEmpty) return null;
    final blob = rows.first['ways'];
    return blob is Uint8List ? blob : Uint8List.fromList(blob as List<int>);
  }

  @override
  String? name(int nameId) {
    _checkOpen();
    return _nameCache.putIfAbsent(nameId, () {
      final rows = _nameStmt.select([nameId]);
      return rows.isEmpty ? null : rows.first['name'] as String?;
    });
  }

  /// Number of tiles in the pack (counts rows; cheap for pack sizes).
  int get tileCount {
    _checkOpen();
    return _db.select('SELECT COUNT(*) AS c FROM tiles').first['c'] as int;
  }

  void _checkOpen() {
    if (_closed) throw StateError('SqlitePack $path is closed');
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _tileStmt.close();
    _nameStmt.close();
    _db.close();
  }
}
