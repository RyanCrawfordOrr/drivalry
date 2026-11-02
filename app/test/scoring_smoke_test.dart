import 'package:drivalry_scoring/drivalry_scoring.dart';
import 'package:flutter_test/flutter_test.dart';

/// Proves the Dart scoring engine is wired into the app build. The engine's
/// own behaviour is covered by packages/drivalry_scoring and the shared
/// fixtures; this only checks the dependency resolves and runs.
void main() {
  test('clean commute scores well and beats the messy one', () {
    final clean = scoreTrip(cleanCommute());
    final messy = scoreTrip(messyCommute());

    expect(clean.scored, isTrue);
    expect(clean.reckless, isFalse);
    expect(clean.score, greaterThanOrEqualTo(90));
    expect(clean.xp, greaterThan(0));

    expect(messy.scored, isTrue);
    expect(messy.score, lessThan(clean.score));
    expect(messy.events, isNotEmpty);
  });
}
