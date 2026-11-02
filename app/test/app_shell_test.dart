import 'package:drivalry/app/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shell shows five tabs and switches between them', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: DrivalryApp()));
    await tester.pumpAndSettle();

    for (final label in ['Drive', 'Leagues', 'Friends', 'Convoy', 'Garage']) {
      expect(find.widgetWithText(NavigationDestination, label), findsOneWidget);
    }

    // Drive is the initial tab.
    expect(find.widgetWithText(AppBar, 'Drive'), findsOneWidget);

    await tester.tap(find.widgetWithText(NavigationDestination, 'Convoy'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Convoy'), findsOneWidget);

    await tester.tap(find.widgetWithText(NavigationDestination, 'Garage'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Garage'), findsOneWidget);
  });
}
