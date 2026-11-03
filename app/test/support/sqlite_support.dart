import 'package:drivalry/data/db/database.dart';
import 'package:sqlite3/sqlite3.dart';

/// Whether sqlite3 is usable in this host test run.
///
/// `package:sqlite3` 3.x bundles SQLite through Dart build hooks, which
/// `flutter test` runs for the host platform. When that is not available
/// (an old toolchain, or a sandbox without network for the prebuilt download)
/// the database-backed tests skip with this reason instead of failing.
String? sqliteUnavailableReason() {
  if (_checked) return _reason;
  _checked = true;
  try {
    sqlite3.openInMemory().close();
    return _reason = null;
  } catch (e) {
    return _reason = 'sqlite3 native library not available on this host: $e';
  }
}

bool _checked = false;
String? _reason;

/// Skip string for `test(..., skip: skipWithoutSqlite())`.
String? skipWithoutSqlite() => sqliteUnavailableReason();

/// A fresh in-memory database. Call [sqliteUnavailableReason] first.
AppDatabase memoryDatabase() => AppDatabase.memory();
