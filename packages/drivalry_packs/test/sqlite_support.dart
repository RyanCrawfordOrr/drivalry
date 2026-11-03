/// Shared helpers for tests that touch SQLite or files in the repository.
///
/// `package:sqlite3` 3.x bundles its own native library through Dart hooks
/// (a SHA-verified download on first build), so on every desktop platform
/// `dart test` just works. If loading fails anyway (offline first build, an
/// unsupported CPU), [sqliteSkipReason] turns the SQLite-backed tests into
/// skips with the reason instead of failures.
library;

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

String? _reason;
bool _checked = false;

/// The repository root, found by walking up from the current directory until
/// a `.git` entry appears. Falls back to `packages/<name>/../..`.
Directory repoRoot() {
  var dir = Directory.current.absolute;
  for (var i = 0; i < 6; i++) {
    final git = '${dir.path}${Platform.pathSeparator}.git';
    if (Directory(git).existsSync() || File(git).existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return Directory.current.absolute.parent.parent;
}

/// Null when SQLite can be loaded, otherwise a reason to skip.
String? sqliteSkipReason() {
  if (_checked) return _reason;
  _checked = true;
  try {
    sqlite3.version; // forces the native library to load
  } on Object catch (e) {
    _reason =
        'sqlite3 native library unavailable ($e). The sqlite3 package '
        'downloads it on first build; check network access or see '
        'tools/dev/fetch-sqlite3-dll.ps1.';
  }
  return _reason;
}
