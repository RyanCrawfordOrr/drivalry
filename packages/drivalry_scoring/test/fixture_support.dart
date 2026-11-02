/// Shared helpers for the fixture-driven tests.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

/// Absolute tolerance used for every double in the fixtures.
const double doubleTolerance = 1e-6;

/// `packages/scoring/fixtures`, resolved from this package's own location (not the CWD).
Future<Directory> fixturesDirectory() async {
  final libUri = await Isolate.resolvePackageUri(
    Uri.parse('package:drivalry_scoring/drivalry_scoring.dart'),
  );
  final packageDir = libUri != null
      ? File.fromUri(libUri).parent.parent
      : _packageRootFromCwd();
  final dir = Directory.fromUri(packageDir.uri.resolve('../scoring/fixtures/'));
  if (!dir.existsSync()) {
    throw StateError(
      'Fixture directory not found at ${dir.path}. '
      'Run `npm run fixtures` from the repo root to generate it.',
    );
  }
  return dir;
}

Directory _packageRootFromCwd() {
  var dir = Directory.current.absolute;
  while (true) {
    final pubspec = File.fromUri(dir.uri.resolve('pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('name: drivalry_scoring')) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('Could not locate the drivalry_scoring package root');
    }
    dir = parent;
  }
}

/// Every `*.json` fixture, sorted by file name, decoded.
Future<List<(String, Map<String, dynamic>)>> loadFixtures() async {
  final dir = await fixturesDirectory();
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  if (files.isEmpty) {
    throw StateError('No fixtures in ${dir.path}; run `npm run fixtures`');
  }
  return [
    for (final f in files)
      (
        f.uri.pathSegments.last,
        jsonDecode(f.readAsStringSync()) as Map<String, dynamic>,
      ),
  ];
}

/// Asserts that [actual] (a `toJson()` tree) matches [expected] (a decoded fixture tree).
///
/// Rules, as documented in `fixtures/README.md`:
///  - integers, strings, booleans and null must match exactly;
///  - doubles must be within [doubleTolerance];
///  - the strings `"NaN"`, `"Infinity"` and `"-Infinity"` stand for those doubles;
///  - a key that is absent in the fixture (TS `undefined`) must be absent or null in [actual].
void expectJsonMatches(Object? actual, Object? expected, {String path = r'$'}) {
  switch (expected) {
    case Map():
      expect(actual, isA<Map>(), reason: '$path: expected an object');
      final a = actual as Map;
      for (final key in expected.keys) {
        expectJsonMatches(a[key], expected[key], path: '$path.$key');
      }
      for (final entry in a.entries) {
        if (entry.value != null && !expected.containsKey(entry.key)) {
          fail('$path.${entry.key}: unexpected key with value ${entry.value}');
        }
      }
    case List():
      expect(actual, isA<List>(), reason: '$path: expected a list');
      final a = actual as List;
      expect(a.length, expected.length, reason: '$path: length');
      for (var i = 0; i < expected.length; i++) {
        expectJsonMatches(a[i], expected[i], path: '$path[$i]');
      }
    case 'NaN':
      expect(
        actual,
        isA<double>().having((d) => d.isNaN, 'isNaN', isTrue),
        reason: path,
      );
    case 'Infinity':
      expect(actual, double.infinity, reason: path);
    case '-Infinity':
      expect(actual, double.negativeInfinity, reason: path);
    case num():
      switch (actual) {
        case int():
          expect(
            actual,
            expected,
            reason: '$path: integers must match exactly',
          );
        case double():
          expect(
            actual,
            closeTo(expected.toDouble(), doubleTolerance),
            reason: path,
          );
        default:
          fail('$path: expected a number, got ${actual.runtimeType} ($actual)');
      }
    default:
      expect(actual, expected, reason: path);
  }
}
