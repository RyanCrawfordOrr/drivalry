import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/widget_support.dart';
import 'art_harness.dart';
import 'scenes/trip_scene.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadArtFonts);
  testWidgets('probe iOS score fonts', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final scene = TripScene();
    try {
      final widget = await scene.build();
      await tester.pumpWidget(widget);
      await pumpFor(tester, const Duration(seconds: 3));
      await scene.prepare(tester);
      for (final text in ['58', '+46 XP', 'Score breakdown']) {
        final found = find.text(text);
        for (final element in found.evaluate()) {
          final w = element.widget as Text;
          final inherited = DefaultTextStyle.of(element).style;
          debugPrint('PROBE "$text" style=${w.style} inherited=$inherited theme=${Theme.of(element).textTheme.headlineMedium}');
        }
      }
    } finally {
      await unmountAndSettle(tester);
      await scene.dispose();
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
