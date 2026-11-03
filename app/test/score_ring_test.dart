import 'package:drivalry/features/drive/widgets/score_ring.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  double fraction(WidgetTester tester) {
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(ScoreRing),
        matching: find.byType(CustomPaint),
      ),
    );
    return (paint.painter! as ScoreRingPainter).fraction;
  }

  testWidgets('score ring renders the number and the reckless stamp', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              ScoreRing(score: 87, label: '+70 XP'),
              ScoreRing(score: 12, reckless: true),
              ScoreRing(score: null, size: 56),
            ],
          ),
        ),
      ),
    );
    expect(find.text('87'), findsOneWidget);
    expect(find.text('+70 XP'), findsOneWidget);
    expect(find.text('RECKLESS'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('with animate the ring sweeps from zero', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: ScoreRing(score: 87, animate: true)),
        ),
      ),
    );
    // First frame: nothing drawn yet, the number starts at 0.
    expect(fraction(tester), 0);
    expect(find.text('0'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    final mid = fraction(tester);
    expect(mid, greaterThan(0));
    expect(mid, lessThan(0.87));
    expect(find.text('87'), findsNothing);

    await tester.pump(ScoreRing.sweep);
    expect(fraction(tester), closeTo(0.87, 1e-9));
    expect(find.text('87'), findsOneWidget);
  });

  testWidgets('without animate, or under reduce motion, it is full at once', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: ScoreRing(score: 64))),
      ),
    );
    expect(fraction(tester), closeTo(0.64, 1e-9));

    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Scaffold(
            body: Center(child: ScoreRing(score: 64, animate: true)),
          ),
        ),
      ),
    );
    expect(fraction(tester), closeTo(0.64, 1e-9));
    expect(find.text('64'), findsOneWidget);
  });
}
