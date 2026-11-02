/// The JavaScript-semantics helpers: the places where Dart and JS numbers disagree.
library;

import 'package:drivalry_scoring/src/js_compat.dart';
import 'package:test/test.dart';

void main() {
  group('jsRound (Math.round)', () {
    test('rounds ties toward +infinity, unlike double.round', () {
      expect(jsRound(2.5), 3);
      expect(jsRound(-2.5), -2);
      expect((-2.5).round(), -3, reason: 'Dart rounds ties away from zero');
      expect(jsRound(-0.5), 0);
      expect(jsRound(0.5), 1);
      expect(jsRound(1.5), 2);
    });

    test('is exact next to the tie', () {
      expect(jsRound(0.49999999999999994), 0);
      expect(jsRound(-0.49999999999999994), 0);
      expect(jsRound(2.4999999999999996), 2);
    });

    test('passes non-finite values through', () {
      expect(jsRound(double.nan).isNaN, isTrue);
      expect(jsRound(double.infinity), double.infinity);
      expect(jsRound(double.negativeInfinity), double.negativeInfinity);
    });
  });

  group('jsIntegerString', () {
    test('renders like a JS template literal', () {
      expect(jsIntegerString(45), '45');
      expect(jsIntegerString(-0.0), '0');
      expect(jsIntegerString(-7), '-7');
      expect(jsIntegerString(double.nan), 'NaN');
      expect(jsIntegerString(double.infinity), 'Infinity');
      expect(jsIntegerString(double.negativeInfinity), '-Infinity');
    });
  });

  group('stableSorted', () {
    test('keeps insertion order for equal keys', () {
      final items = [
        (k: 1, v: 'a'),
        (k: 0, v: 'b'),
        (k: 1, v: 'c'),
        (k: 0, v: 'd'),
        (k: 1, v: 'e'),
      ];
      final sorted = stableSorted(items, (a, b) => a.k.compareTo(b.k));
      expect(sorted.map((e) => e.v).join(), 'bdace');
    });

    test('does not mutate its input', () {
      final items = [3, 1, 2];
      stableSorted(items, (a, b) => a.compareTo(b));
      expect(items, [3, 1, 2]);
    });
  });
}
