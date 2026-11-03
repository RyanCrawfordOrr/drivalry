import 'package:drivalry/app/ui/ui.dart';
import 'package:drivalry/widgets/placeholder_screen.dart';
import 'package:drivalry/widgets/signed_in_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The gate and the placeholder share the empty-state grammar: a kicker, a
/// headline, one line, and at most one button (docs/12 §7).
void main() {
  testWidgets('without the online service the gate has no button', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SignedInScope(
              message: 'Sign in to drive with friends in a convoy.',
              icon: Icons.route_outlined,
              child: Text('convoy body'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('CONVOY'), findsOneWidget);
    expect(find.text('Not available in this version yet.'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.text('convoy body'), findsNothing);
    expect(find.textContaining('build'), findsNothing);
    expect(find.textContaining('cloud project'), findsNothing);
  });

  testWidgets('the placeholder uses the same grammar', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PlaceholderScreen(
          title: 'Garage',
          tagline: 'Your cars, their fuel and their papers.',
          planned: ['Fuel log', 'Maintenance reminders'],
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Not available in this version yet.'), findsOneWidget);
    expect(find.text('Your cars, their fuel and their papers.'), findsOneWidget);
    expect(find.text('COMING SOON'), findsOneWidget);
    expect(find.text('Fuel log'), findsOneWidget);
    expect(find.text('Coming in this tab'), findsNothing);
  });
}
