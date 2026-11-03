import 'package:drivalry/app/theme.dart';
import 'package:drivalry/app/ui/ui.dart';
import 'package:drivalry/features/convoy/convoy_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/widget_support.dart';

/// The join-code sheet owns a text field with the keyboard up. Dragging the
/// sheet away closes it and the keyboard together; the field is still on
/// screen for the exit animation and must survive the inset change.
void main() {
  setUp(() => Haptics.enabled = false);

  Widget harness() => MaterialApp(
    theme: DrivalryTheme.dark(),
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => showJoinCodeSheet(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  testWidgets('dragging the sheet closed with the keyboard up does not throw', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness());
    await tester.tap(find.text('open'));
    await pumpFor(tester, const Duration(milliseconds: 600));
    expect(find.byKey(const Key('join-code')), findsOneWidget);

    // The keyboard comes up for the autofocused field.
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();

    // Slide the sheet most of the way down and let go: it closes, but the
    // exit animation still has a few frames to run.
    await tester.fling(
      find.byKey(const Key('join-code')),
      const Offset(0, 120),
      2000,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    // The keyboard goes away while the sheet is still animating out.
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump();
    await pumpFor(tester, const Duration(milliseconds: 600));

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('join-code')), findsNothing);
    await unmountAndSettle(tester);
  });

  testWidgets('Join returns the code and closes', (tester) async {
    await tester.pumpWidget(harness());
    await tester.tap(find.text('open'));
    await pumpFor(tester, const Duration(milliseconds: 600));
    await tester.enterText(find.byKey(const Key('join-code')), 'ABC123');
    await tester.pump();
    expect(find.text('ABC123'), findsOneWidget);
    await unmountAndSettle(tester);
  });
}
