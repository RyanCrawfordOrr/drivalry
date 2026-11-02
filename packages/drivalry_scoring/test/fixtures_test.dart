/// Replays every fixture in `packages/scoring/fixtures/` through the Dart engine.
///
/// The TypeScript package wrote these files (`npm run fixtures`); they are the contract.
library;

import 'package:drivalry_scoring/drivalry_scoring.dart';
import 'package:drivalry_scoring/src/roast/roast.dart' show hash;
import 'package:test/test.dart';

import 'fixture_support.dart';

Future<void> main() async {
  final fixtures = await loadFixtures();
  for (final (fileName, fixture) in fixtures) {
    final kind = fixture['kind'] as String;
    switch (kind) {
      case 'trip':
        _tripFixture(fixture);
      case 'hash':
        _hashFixture(fixture);
      case 'format':
        _formatFixture(fixture);
      case 'computeXp':
        _xpFixture(fixture);
      case 'templates':
        _templatesFixture(fixture);
      default:
        throw StateError('Unknown fixture kind "$kind" in $fileName');
    }
  }
}

void _tripFixture(Map<String, dynamic> fixture) {
  final name = fixture['name'] as String;
  final inputJson = fixture['input'] as Map<String, dynamic>;
  final input = TripInput.fromJson(inputJson);
  final options = ScoreOptions.fromJson(
    fixture['options'] as Map<String, dynamic>,
  );
  final expected = fixture['expected'] as Map<String, dynamic>;
  final expectedScore = Map<String, dynamic>.from(expected)
    ..remove('eventLines')
    ..remove('severityOrder')
    ..remove('feedbackVariants');
  final source = fixture['source'] as Map<String, dynamic>;
  final builder = source['builder'] as String;

  group('fixture $name', () {
    test('TripInput survives a JSON round trip', () {
      expectJsonMatches(input.toJson(), inputJson);
    });

    test('scoreTrip matches the TypeScript output', () {
      expectJsonMatches(scoreTrip(input, options).toJson(), expectedScore);
    });

    if (builder != 'manual') {
      test('$builder reproduces the fixture input', () {
        final built = switch (builder) {
          'buildSyntheticTrip' => buildSyntheticTrip(
            SyntheticSpec.fromJson(source['spec'] as Map<String, dynamic>),
          ),
          'cleanCommute' => cleanCommute(source['id'] as String),
          'messyCommute' => messyCommute(source['id'] as String),
          _ => throw StateError('unknown builder $builder'),
        };
        final actual = built.toJson();
        for (final key in ['samples', 'segments', 'phoneEvents']) {
          expectJsonMatches(actual[key], inputJson[key], path: '\$.$key');
        }
      });
    }

    test('sortBySeverity order matches', () {
      final r = scoreTrip(input, options);
      final order = [
        for (final e in sortBySeverity(r.events))
          r.events.indexWhere((x) => identical(x, e)),
      ];
      expect(order, expected['severityOrder']);
    });

    test('formatDuration, formatSaved and roastEvent per event', () {
      final r = scoreTrip(input, options);
      final lines = expected['eventLines'] as List;
      expect(lines.length, r.events.length);
      for (final raw in lines) {
        final line = raw as Map<String, dynamic>;
        final i = line['index'] as int;
        final e = r.events[i];
        expect(
          formatDuration(e.durationS),
          line['durationText'],
          reason: 'event $i durationText',
        );
        final detail = e.detail;
        if (detail is SpeedingDetail) {
          expect(
            formatSaved(detail.timeSavedS),
            line['savedText'],
            reason: 'event $i savedText',
          );
        } else {
          expect(
            line.containsKey('savedText'),
            isFalse,
            reason: 'event $i has no savedText',
          );
        }
        expectJsonMatches(
          roastEvent(e, r.tripId, i, options).toJson(),
          line['roast'],
          path: '\$.eventLines[$i].roast',
        );
      }
    });

    test('buildFeedback matches for every intensity and unit', () {
      for (final raw in expected['feedbackVariants'] as List) {
        final v = raw as Map<String, dynamic>;
        final opts = ScoreOptions(
          intensity: Intensity.fromWire(v['intensity'] as String),
          units: SpeedUnits.fromWire(v['units'] as String),
        );
        expectJsonMatches(
          scoreTrip(input, opts).feedback.toJson(),
          {'headline': v['headline'], 'lines': v['lines']},
          path: '\$.feedbackVariants[${v['intensity']}/${v['units']}]',
        );
      }
    });
  });
}

void _hashFixture(Map<String, dynamic> fixture) {
  group('FNV-1a hash vectors', () {
    for (final raw in fixture['vectors'] as List) {
      final v = raw as Map<String, dynamic>;
      final seed = v['seed'] as String;
      test('hash("$seed")', () {
        expect(hash(seed), v['hash']);
      });
    }
  });
}

void _formatFixture(Map<String, dynamic> fixture) {
  group('format vectors', () {
    test('formatDuration', () {
      for (final raw in fixture['formatDuration'] as List) {
        final v = raw as Map<String, dynamic>;
        final input = (v['input'] as num).toDouble();
        expect(
          formatDuration(input),
          v['expected'],
          reason: 'formatDuration($input)',
        );
      }
    });
    test('formatSaved', () {
      for (final raw in fixture['formatSaved'] as List) {
        final v = raw as Map<String, dynamic>;
        final input = (v['input'] as num).toDouble();
        expect(
          formatSaved(input),
          v['expected'],
          reason: 'formatSaved($input)',
        );
      }
    });
  });
}

void _xpFixture(Map<String, dynamic> fixture) {
  group('computeXp vectors', () {
    for (final raw in fixture['vectors'] as List) {
      final v = raw as Map<String, dynamic>;
      final score = v['score'] as int;
      final distanceM = (v['distanceM'] as num).toDouble();
      final ctxJson = v['context'] as Map<String, dynamic>?;
      final ctx = ctxJson == null ? null : TripContext.fromJson(ctxJson);
      final reckless = v['reckless'] as bool;
      test(
        'computeXp($score, $distanceM, ${ctxJson ?? 'none'}, $reckless)',
        () {
          expect(computeXp(score, distanceM, ctx, reckless), v['expected']);
        },
      );
    }
  });
}

void _templatesFixture(Map<String, dynamic> fixture) {
  test('template library is identical to the TypeScript library', () {
    final actual = {
      for (final entry in templates.entries)
        entry.key.key: {
          for (final by in entry.value.entries) by.key.wire: by.value,
        },
    };
    expect(actual, equals(fixture['templates']));
  });
}
