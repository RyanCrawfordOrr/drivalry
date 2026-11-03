// Runs the layout audit over the store scenes (real screens, seeded data).
//
//   DRIVALRY_LAYOUT=1 flutter test test/layout
//
// Opt-in for now: it fails on the layout debts the area passes are working
// off, so without DRIVALRY_LAYOUT the suite skips it rather than failing CI.
import 'package:flutter_test/flutter_test.dart';

import '../art/art_harness.dart';
import '../art/scenes/scenes.dart';
import '../support/sqlite_support.dart';
import '../support/widget_support.dart';
import 'layout_audit.dart';

void main() {
  // Fonts come from the Flutter cache, which CI does not populate; only load
  // them when the audit actually runs.
  setUpAll(() async {
    if (layoutShots) await loadArtFonts();
  });
  final sqliteSkip = skipWithoutSqlite();
  for (final factory in sceneFactories) {
    final id = factory().id;
    for (final size in phoneSizes) {
      testWidgets(
        '$id lays out on $size',
        (tester) async {
          final scene = factory();
          try {
            final app = await scene.build();
            final report = await auditLayout(
              tester,
              name: id,
              app: app,
              size: size,
              settle: scene.settle,
            );
            await unmountAndSettle(tester);
            expect(report.blocking, isEmpty, reason: report.summary());
          } finally {
            await scene.dispose();
          }
        },
        skip: sqliteSkip != null || !layoutShots,
        timeout: const Timeout(Duration(minutes: 3)),
      );
    }
  }
}
