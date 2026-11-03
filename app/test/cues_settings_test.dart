import 'package:drivalry/app/ui/ui.dart';
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/features/cues/cue_settings.dart';
import 'package:drivalry/features/cues/cue_speaker.dart';
import 'package:drivalry/features/settings/cues_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sqlite_support.dart';
import 'support/widget_support.dart';

void main() {
  final skip = skipWithoutSqlite() != null;
  late AppDatabase db;
  late SilentCueSpeaker speaker;

  setUp(() {
    db = memoryDatabase();
    speaker = SilentCueSpeaker();
  });
  tearDown(() => db.close());

  Widget harness() => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      cueSpeakerProvider.overrideWithValue(speaker),
    ],
    child: const MaterialApp(home: CuesSettingsScreen()),
  );

  Switch switchIn(WidgetTester tester, Key key) => tester.widget<Switch>(
    find.descendant(of: find.byKey(key), matching: find.byType(Switch)),
  );

  testWidgets('defaults: off, sub-toggles disabled until enabled', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(switchIn(tester, const Key('cues-enabled')).value, isFalse);
    final limit = switchIn(tester, const Key('cues-limit'));
    expect(limit.value, isTrue);
    expect(limit.onChanged, isNull);
    expect(find.text('VOICE SPEED'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Say a sample'), findsOneWidget);
    expect(find.byType(SecondaryButton), findsOneWidget);
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('toggles write the settings; sample speaks', (tester) async {
    await tester.pumpWidget(harness());
    await pumpFor(tester, const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const Key('cues-enabled')));
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(await db.getSetting(CueKeys.enabled), 'true');

    await tester.tap(find.byKey(const Key('cues-over')));
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(await db.getSetting(CueKeys.over), 'false');

    await tester.ensureVisible(find.byKey(const Key('cues-sample')));
    await pumpFor(tester, const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('cues-sample')));
    await pumpFor(tester, const Duration(milliseconds: 200));
    expect(speaker.spoken, ["Limit's 35. Smooth."]);

    // The settings stream feeds the switches back.
    expect(switchIn(tester, const Key('cues-over')).value, isFalse);
    expect(switchIn(tester, const Key('cues-limit')).value, isTrue);
    expect(switchIn(tester, const Key('cues-limit')).onChanged, isNotNull);
    await unmountAndSettle(tester);
  }, skip: skip);

  test('CueSettings parses and clamps', () {
    final cfg = CueSettings.fromMap({
      CueKeys.enabled: 'true',
      CueKeys.smooth: 'false',
      CueKeys.rate: '5',
    });
    expect(cfg.enabled, isTrue);
    expect(cfg.smooth, isFalse);
    expect(cfg.limit, isTrue);
    expect(cfg.rate, CueSettings.maxRate);
    expect(CueSettings.fromMap(const {}).rate, 0.9);
  });
}
