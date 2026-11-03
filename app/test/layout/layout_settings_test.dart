// Layout audit for the settings and garage area (docs/12 §2): every screen
// and state rendered at the two phone sizes, with fonts loaded so the
// measurements are real.
//
//   DRIVALRY_LAYOUT=1 flutter test test/layout/layout_settings_test.dart
//
// On top of the shared audit this file fails on any text that was cut off
// (an ellipsis on a label or caption is never acceptable, docs/12 §2),
// which the geometry audit cannot see. It also knows two things the audit
// does not: rows scrolled under the pinned title bar and the page behind an
// open sheet are covered, so an "overlap" with them is not visible.
import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drivalry/data/crash/crash_escalator.dart';
import 'package:drivalry/data/crash/crash_monitor.dart';
import 'package:drivalry/data/crash/crash_speaker.dart';
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/garage/vehicle_matcher.dart';
import 'package:drivalry/data/push/push_service.dart';
import 'package:drivalry/data/push/quiet_hours.dart';
import 'package:drivalry/data/repos/garage_repo.dart';
import 'package:drivalry/data/supabase/supabase_providers.dart';
import 'package:drivalry/features/crash/crash_countdown_screen.dart';
import 'package:drivalry/features/crash/crash_status_card.dart';
import 'package:drivalry/features/cues/cue_settings.dart';
import 'package:drivalry/features/garage/garage_screen.dart';
import 'package:drivalry/features/garage/vehicle_detail_screen.dart';
import 'package:drivalry/features/garage/vehicle_edit_screen.dart';
import 'package:drivalry/features/garage/widgets/new_vehicle_prompt_card.dart';
import 'package:drivalry/features/profile/profile_model.dart';
import 'package:drivalry/features/profile/profile_repo.dart';
import 'package:drivalry/features/settings/attribution_screen.dart';
import 'package:drivalry/features/settings/auto_reply_settings_screen.dart';
import 'package:drivalry/features/settings/crash_settings_screen.dart';
import 'package:drivalry/features/settings/cues_settings_screen.dart';
import 'package:drivalry/features/settings/diagnostics_screen.dart';
import 'package:drivalry/features/settings/emergency_contacts_screen.dart';
import 'package:drivalry/features/settings/notifications_settings_screen.dart';
import 'package:drivalry/features/settings/settings_screen.dart';
import 'package:drivalry/tracking/providers.dart';
import 'package:drivalry/tracking/tracking_models.dart';
import 'package:drivalry/widgets/placeholder_screen.dart';
import 'package:drivalry/widgets/signed_in_scope.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../art/art_harness.dart';
import '../support/fake_tracking_port.dart';
import '../support/scored_trips.dart';
import '../support/sqlite_support.dart';
import '../support/widget_support.dart';
import 'layout_audit.dart';

void main() {
  setUpAll(() async {
    if (layoutShots) await loadArtFonts();
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  final sqliteSkip = skipWithoutSqlite();

  for (final scene in _scenes) {
    for (final size in phoneSizes) {
      testWidgets(
        '${scene.name} lays out on $size',
        (tester) async {
          final f = _Fixture();
          try {
            final app = await scene.build(f);
            final report = await auditLayout(
              tester,
              name: scene.name,
              app: app,
              size: size,
              prepare: scene.prepare == null
                  ? null
                  : (t) => scene.prepare!(t, f),
            );
            final cut = _truncatedText(tester);
            final hidden = _hiddenText(tester);
            await scene.cleanup?.call(tester);
            await pumpFor(tester, const Duration(milliseconds: 400));
            await unmountAndSettle(tester);
            final blocking = [
              for (final i in report.blocking)
                if (i.kind != 'overlap' ||
                    !hidden.any((t) => i.detail.contains('"$t"')))
                  i,
            ];
            expect(blocking, isEmpty, reason: report.summary());
            expect(
              cut,
              isEmpty,
              reason: '[layout] ${scene.name} @ $size: text cut off: $cut',
            );
          } finally {
            // The binding checks this before tearDown runs.
            debugDefaultTargetPlatformOverride = null;
            await f.dispose();
          }
        },
        skip: sqliteSkip != null || !layoutShots,
        timeout: const Timeout(Duration(minutes: 3)),
      );
    }
  }
}

/// Every painted paragraph that was cut: it ran past its `maxLines` (an
/// ellipsis), or it does not wrap and is wider than its box (a tab label
/// fading out), as plain text.
List<String> _truncatedText(WidgetTester tester) {
  final out = <String>[];
  for (final ro in _paragraphs(tester)) {
    final wide = ro.textSize.width > ro.size.width + 1;
    if (!ro.didExceedMaxLines && !wide) continue;
    out.add(_plain(ro));
  }
  return out;
}

/// Text the shared audit cannot tell is covered: anything scrolled under a
/// pinned app bar it does not belong to, and the whole page once a bottom
/// sheet is open over it. Shortened the way the audit quotes it.
Set<String> _hiddenText(WidgetTester tester) {
  final bars = [
    for (final e in find.byType(SliverAppBar).evaluate()) e.renderObject!,
  ];
  final sheets = [
    for (final e in find.byType(BottomSheet).evaluate()) e.renderObject!,
  ];
  final hidden = <String>{};
  for (final ro in _paragraphs(tester)) {
    final rect = _rectOf(ro);
    final underBar = bars.any(
      (bar) => !_inside(ro, bar) && rect.overlaps(_rectOf(bar)),
    );
    final behindSheet = sheets.isNotEmpty && !sheets.any((s) => _inside(ro, s));
    if (underBar || behindSheet) hidden.add(_short(_plain(ro)));
  }
  return hidden;
}

Iterable<RenderParagraph> _paragraphs(WidgetTester tester) sync* {
  final seen = Set<RenderObject>.identity();
  for (final ro in tester.allRenderObjects) {
    if (ro is! RenderParagraph || !ro.attached || !ro.hasSize) continue;
    if (!seen.add(ro) || !_painted(ro)) continue;
    if (_plain(ro).isEmpty) continue;
    yield ro;
  }
}

bool _painted(RenderObject ro) {
  for (var n = ro.parent; n != null; n = n.parent) {
    if (n is RenderOffstage && n.offstage) return false;
    if (n is RenderOpacity && n.opacity == 0) return false;
    if (n is RenderAnimatedOpacity && n.opacity.value == 0) return false;
  }
  return true;
}

bool _inside(RenderObject ro, RenderObject ancestor) {
  for (var n = ro.parent; n != null; n = n.parent) {
    if (identical(n, ancestor)) return true;
  }
  return false;
}

Rect _rectOf(RenderObject ro) =>
    MatrixUtils.transformRect(ro.getTransformTo(null), ro.paintBounds);

String _plain(RenderParagraph ro) =>
    ro.text.toPlainText().replaceAll('\n', ' ').trim();

String _short(String s) => s.length <= 40 ? s : '${s.substring(0, 37)}...';

class _Scene {
  const _Scene(this.name, this.build, {this.prepare, this.cleanup});

  final String name;
  final Future<Widget> Function(_Fixture f) build;

  /// Runs after the first frames: scroll, open a tab or a sheet.
  final Future<void> Function(WidgetTester tester, _Fixture f)? prepare;

  /// Runs after the capture, before unmount (stop a running countdown).
  final Future<void> Function(WidgetTester tester)? cleanup;
}

/// A fresh in-memory database and fake plugin per scene, plus the app shell
/// every scene renders inside.
class _Fixture {
  _Fixture() : db = memoryDatabase(), port = FakeTrackingPort();

  final AppDatabase db;
  final FakeTrackingPort port;
  final List<String> navigated = [];

  /// A fixed "now" so dates and countdowns render the same every run.
  final int now = DateTime(2026, 11, 3, 9, 41).millisecondsSinceEpoch;

  static const _day = 24 * 60 * 60 * 1000;

  List<Override> get _base => [
    databaseProvider.overrideWithValue(db),
    trackingPortProvider.overrideWithValue(port),
    crashSpeakerProvider.overrideWithValue(const SilentCrashSpeaker()),
    crashMonitorConfigProvider.overrideWithValue(
      CrashMonitorConfig(
        now: () => now,
        navigate: navigated.add,
        haptics: false,
        lifecycle: () => AppLifecycleState.resumed,
      ),
    ),
  ];

  /// A build with the online service and someone signed in.
  List<Override> get signedIn => [
    cloudConfiguredProvider.overrideWithValue(true),
    currentUserIdProvider.overrideWithValue('me'),
    myProfileProvider.overrideWith(
      (_) => Stream.value(
        const Profile(id: 'me', handle: 'ryan', displayName: 'Ryan Orr'),
      ),
    ),
  ];

  /// A build with the online service and nobody signed in.
  List<Override> get signedOut => [
    cloudConfiguredProvider.overrideWithValue(true),
  ];

  /// [screen] inside the themed app. A [pushed] screen sits over an empty
  /// root so its app bar shows the back button, as it does in the real app.
  Widget app(
    Widget screen, {
    List<Override> overrides = const [],
    bool pushed = false,
    Brightness brightness = Brightness.dark,
  }) {
    return ProviderScope(
      overrides: [..._base, ...overrides],
      child: MaterialApp(
        theme: artTheme(Brightness.light),
        darkTheme: artTheme(),
        themeMode: brightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light,
        debugShowCheckedModeBanner: false,
        initialRoute: pushed ? '/screen' : '/',
        routes: {
          '/': (_) => pushed ? const Scaffold() : screen,
          '/screen': (_) => screen,
        },
      ),
    );
  }

  Future<void> seedVehicles() async {
    await db.upsertVehicle(
      VehiclesCompanion.insert(
        id: 'v1',
        name: 'Mazda',
        make: const Value('Mazda'),
        model: const Value('CX-5'),
        year: const Value(2021),
        tankLitres: const Value(58),
        bluetoothNames: Value(VehicleMatcher.encodeNames(['Mazda CX-5'])),
        createdAt: 1,
      ),
    );
    await db.upsertVehicle(
      VehiclesCompanion.insert(
        id: 'v2',
        name: 'Work truck',
        neverTrack: const Value(true),
        createdAt: 2,
      ),
    );
    for (var i = 0; i < 3; i++) {
      final id = 't$i';
      await seedScoredTrip(
        db,
        id: id,
        startedAt: now - (i + 1) * _day,
        score: 84 + i * 4,
        distanceM: 12_300 + i * 4_000,
      );
      await db.setTripVehicle(id, 'v1', 'Mazda');
    }
  }

  Future<void> seedFuel() async {
    Future<void> entry(
      String id,
      int daysAgo,
      double odo,
      double litres,
      int cents, {
      bool full = true,
    }) => db.upsertFuelEntry(
      FuelEntriesCompanion.insert(
        id: id,
        vehicleId: 'v1',
        at: now - daysAgo * _day,
        odometerKm: Value(odo),
        litres: litres,
        costCents: Value(cents),
        fullTank: Value(full),
      ),
    );
    await entry('f1', 20, 42_000, 48.2, 6_420);
    await entry('f2', 10, 42_610, 45.0, 5_980);
    await entry('f3', 2, 43_180, 20.5, 2_740, full: false);
  }

  Future<void> seedMaintenance() async {
    Future<void> item(
      String id,
      String title, {
      double? km,
      int? days,
      double? lastKm,
      int? lastDaysAgo,
    }) => db.upsertMaintenance(
      MaintenanceItemsCompanion.insert(
        id: id,
        vehicleId: 'v1',
        title: title,
        intervalKm: Value(km),
        intervalDays: Value(days),
        lastDoneKm: Value(lastKm),
        lastDoneAt: Value(
          lastDaysAgo == null ? null : now - lastDaysAgo * _day,
        ),
        createdAt: 1,
      ),
    );
    await item('m1', 'Oil change', km: 8_000, lastKm: 40_000, lastDaysAgo: 90);
    await item('m2', 'Tyre rotation', km: 10_000, lastKm: 42_000);
    await item('m3', 'Registration', days: 365, lastDaysAgo: 300);
    await item('m4', 'Inspection', days: 365, lastDaysAgo: 400);
  }

  Future<void> seedDocuments() async {
    Future<void> doc(String id, String title, int daysAgo) => db.insertDocument(
      VehicleDocumentsCompanion.insert(
        id: id,
        vehicleId: 'v1',
        title: title,
        path: 'unused',
        mimeType: 'image/jpeg',
        createdAt: now - daysAgo * _day,
      ),
    );
    await doc('d1', 'Insurance card', 30);
    await doc('d2', 'Registration', 12);
  }

  Future<void> seedContacts() async {
    await db.upsertEmergencyContact(
      EmergencyContactsCompanion.insert(
        id: 'c1',
        name: 'Sam Orr',
        phone: '+15550102020',
        createdAt: 1,
      ),
    );
    await db.upsertEmergencyContact(
      EmergencyContactsCompanion.insert(
        id: 'c2',
        name: 'Jordan Lee',
        phone: '+15550107777',
        userId: const Value('u-jordan'),
        createdAt: 2,
      ),
    );
  }

  /// An alert that went out ten minutes ago and is still open.
  Future<void> seedOpenAlert() => db.setSetting(
    CrashKeys.unresolved,
    jsonEncode(
      CrashAlertRecord(
        alertId: 'a1',
        tripId: 't0',
        t: now - 600_000,
        lat: 36.16,
        lon: -86.78,
        createdAt: now - 600_000,
        contactsTexted: 1,
        cloudSent: true,
      ).toJson(),
    ),
  );

  Future<void> seedCrashHistory() async {
    await db.setSetting(CrashKeys.falsePositives, '2');
    await db.setSetting(CrashKeys.lastCandidateAt, '${now - 3 * _day}');
  }

  CrashCandidateEvent candidate() => CrashCandidateEvent(
    tripId: 't0',
    t: now,
    peakMps2: 45,
    speedBeforeMps: 15,
    lat: 36.16,
    lon: -86.78,
    accuracy: 10,
  );

  Future<void> dispose() async {
    await port.dispose();
    await db.close();
  }
}

/// `pushControllerProvider` pinned to one state, so the notifications screen
/// can show each permission state without Firebase.
class _FixedPush extends PushController {
  _FixedPush(this.status);
  final PushStatus status;

  @override
  PushStatus build() => status;
}

Future<void> _scrollBy(WidgetTester tester, double px) async {
  final position = tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position;
  position.jumpTo(px.isFinite ? px : position.maxScrollExtent);
  await pumpFor(tester, const Duration(milliseconds: 400));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await pumpFor(tester, const Duration(milliseconds: 800));
}

Future<void> _openTab(WidgetTester tester, String label) => _tap(
  tester,
  find.descendant(of: find.byType(TabBar), matching: find.text(label)),
);

/// The crash monitor of the screen on stage.
CrashMonitor _monitor(WidgetTester tester, Type screen) =>
    ProviderScope.containerOf(
      tester.element(find.byType(screen)),
    ).read(crashMonitorProvider.notifier);

final List<_Scene> _scenes = [
  // ---------------------------------------------------------- settings --
  _Scene(
    'settings-signed-out',
    (f) async =>
        f.app(const SettingsScreen(), overrides: f.signedOut, pushed: true),
  ),
  _Scene('settings-signed-in', (f) async {
    await f.seedContacts();
    await f.db.setSetting(
      QuietHours.settingsKey,
      const QuietHours(enabled: true).toJson(),
    );
    return f.app(const SettingsScreen(), overrides: f.signedIn, pushed: true);
  }),
  _Scene(
    'settings-no-cloud',
    (f) async => f.app(const SettingsScreen(), pushed: true),
  ),
  _Scene(
    'settings-scrolled',
    (f) async =>
        f.app(const SettingsScreen(), overrides: f.signedIn, pushed: true),
    prepare: (tester, _) => _scrollBy(tester, 200),
  ),
  _Scene(
    'settings-bottom',
    (f) async =>
        f.app(const SettingsScreen(), overrides: f.signedIn, pushed: true),
    prepare: (tester, _) => _scrollBy(tester, double.infinity),
  ),
  _Scene(
    'settings-light',
    (f) async => f.app(
      const SettingsScreen(),
      overrides: f.signedIn,
      pushed: true,
      brightness: Brightness.light,
    ),
  ),
  _Scene(
    'notifications-pending',
    (f) async => f.app(
      const NotificationsSettingsScreen(),
      overrides: [
        pushControllerProvider.overrideWith(
          () => _FixedPush(const PushPending()),
        ),
      ],
      pushed: true,
    ),
  ),
  _Scene('notifications-on', (f) async {
    await f.db.setSetting(
      QuietHours.settingsKey,
      const QuietHours(enabled: true).toJson(),
    );
    return f.app(
      const NotificationsSettingsScreen(),
      overrides: [
        pushControllerProvider.overrideWith(
          () => _FixedPush(const PushRegistered('token')),
        ),
      ],
      pushed: true,
    );
  }),
  _Scene(
    'notifications-blocked',
    (f) async => f.app(
      const NotificationsSettingsScreen(),
      overrides: [
        pushControllerProvider.overrideWith(
          () => _FixedPush(const PushPermissionDenied()),
        ),
      ],
      pushed: true,
    ),
  ),
  _Scene(
    'crash-settings',
    (f) async => f.app(const CrashSettingsScreen(), pushed: true),
  ),
  _Scene('crash-settings-alert', (f) async {
    await f.seedContacts();
    await f.seedOpenAlert();
    await f.seedCrashHistory();
    return f.app(const CrashSettingsScreen(), pushed: true);
  }),
  _Scene(
    'contacts-empty',
    (f) async => f.app(const EmergencyContactsScreen(), pushed: true),
  ),
  _Scene('contacts-populated', (f) async {
    await f.seedContacts();
    return f.app(const EmergencyContactsScreen(), pushed: true);
  }),
  _Scene(
    'contacts-add-sheet',
    (f) async => f.app(const EmergencyContactsScreen(), pushed: true),
    prepare: (tester, _) =>
        _tap(tester, find.widgetWithText(FilledButton, 'Add contact')),
  ),
  _Scene(
    'cues-off',
    (f) async => f.app(const CuesSettingsScreen(), pushed: true),
  ),
  _Scene('cues-on', (f) async {
    await f.db.setSetting(CueKeys.enabled, 'true');
    await f.db.setSetting(CueKeys.rate, '1.1');
    return f.app(const CuesSettingsScreen(), pushed: true);
  }),
  _Scene('auto-reply-android', (f) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    return f.app(const AutoReplySettingsScreen(), pushed: true);
  }),
  _Scene('auto-reply-ios', (f) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    return f.app(const AutoReplySettingsScreen(), pushed: true);
  }),
  _Scene('diagnostics', (f) async {
    await f.seedVehicles();
    await f.seedCrashHistory();
    return f.app(const DiagnosticsScreen(), pushed: true);
  }),
  _Scene('about', (f) async => f.app(const AttributionScreen(), pushed: true)),

  // ------------------------------------------------------------- crash --
  _Scene(
    'crash-countdown',
    (f) async => f.app(const CrashCountdownScreen(), pushed: true),
    prepare: (tester, _) async {
      _monitor(tester, CrashCountdownScreen).startTest();
      await pumpFor(tester, const Duration(milliseconds: 400));
    },
    cleanup: (tester) => _monitor(tester, CrashCountdownScreen).imOk(),
  ),
  _Scene('crash-help-requested', (f) async {
    await f.seedOpenAlert();
    return f.app(const CrashCountdownScreen(), pushed: true);
  }),
  _Scene(
    'crash-none',
    (f) async => f.app(const CrashCountdownScreen(), pushed: true),
  ),
  _Scene(
    'crash-card-countdown',
    (f) async => f.app(const _DriveSheetStandIn(child: CrashStatusCard())),
    prepare: (tester, f) async {
      await _monitor(tester, CrashStatusCard).onCandidate(f.candidate());
      await pumpFor(tester, const Duration(milliseconds: 400));
    },
    cleanup: (tester) => _monitor(tester, CrashStatusCard).imOk(),
  ),
  _Scene('crash-card-unresolved', (f) async {
    await f.seedOpenAlert();
    return f.app(const _DriveSheetStandIn(child: CrashStatusCard()));
  }),
  _Scene('vehicle-prompt-card', (f) async {
    await f.seedVehicles();
    return f.app(
      const _DriveSheetStandIn(
        child: NewVehiclePromptCard(
          prompt: VehiclePrompt(tripId: 't0', name: 'Mazda CX-5'),
        ),
      ),
    );
  }),

  // ------------------------------------------------------------ garage --
  _Scene('garage-empty', (f) async => f.app(const GarageScreen())),
  _Scene(
    'garage-loading',
    (f) async => f.app(
      const GarageScreen(),
      overrides: [
        vehiclesProvider.overrideWith(
          (_) => Completer<List<Vehicle>>().future.asStream(),
        ),
      ],
    ),
  ),
  _Scene('garage-populated', (f) async {
    await f.seedVehicles();
    await f.db.setSetting(
      VehicleMatcher.ignoredNamesKey,
      VehicleMatcher.encodeNames(['Dad Camry', 'Uber Prius']),
    );
    return f.app(const GarageScreen());
  }),
  _Scene('garage-light', (f) async {
    await f.seedVehicles();
    await f.db.setSetting(
      VehicleMatcher.ignoredNamesKey,
      VehicleMatcher.encodeNames(['Dad Camry']),
    );
    return f.app(const GarageScreen(), brightness: Brightness.light);
  }),
  _Scene('vehicle-stats', (f) async {
    await f.seedVehicles();
    await f.seedFuel();
    return f.app(const VehicleDetailScreen(vehicleId: 'v1'), pushed: true);
  }),
  _Scene('vehicle-stats-imperial', (f) async {
    await f.seedVehicles();
    await f.seedFuel();
    await f.db.setSetting('units', 'mph');
    return f.app(const VehicleDetailScreen(vehicleId: 'v1'), pushed: true);
  }),
  _Scene('vehicle-stats-empty', (f) async {
    await f.seedVehicles();
    return f.app(const VehicleDetailScreen(vehicleId: 'v2'), pushed: true);
  }),
  _Scene('vehicle-fuel-empty', (f) async {
    await f.seedVehicles();
    return f.app(const VehicleDetailScreen(vehicleId: 'v1'), pushed: true);
  }, prepare: (tester, _) => _openTab(tester, 'Fuel')),
  _Scene('vehicle-fuel', (f) async {
    await f.seedVehicles();
    await f.seedFuel();
    return f.app(const VehicleDetailScreen(vehicleId: 'v1'), pushed: true);
  }, prepare: (tester, _) => _openTab(tester, 'Fuel')),
  _Scene('vehicle-fuel-imperial', (f) async {
    await f.seedVehicles();
    await f.seedFuel();
    await f.db.setSetting('units', 'mph');
    return f.app(const VehicleDetailScreen(vehicleId: 'v1'), pushed: true);
  }, prepare: (tester, _) => _openTab(tester, 'Fuel')),
  _Scene(
    'vehicle-fuel-sheet',
    (f) async {
      await f.seedVehicles();
      await f.seedFuel();
      return f.app(const VehicleDetailScreen(vehicleId: 'v1'), pushed: true);
    },
    prepare: (tester, _) async {
      await _openTab(tester, 'Fuel');
      await _tap(tester, find.widgetWithText(FloatingActionButton, 'Fill-up'));
    },
  ),
  _Scene('vehicle-maintenance-empty', (f) async {
    await f.seedVehicles();
    return f.app(const VehicleDetailScreen(vehicleId: 'v1'), pushed: true);
  }, prepare: (tester, _) => _openTab(tester, 'Upkeep')),
  _Scene('vehicle-maintenance', (f) async {
    await f.seedVehicles();
    await f.seedFuel();
    await f.seedMaintenance();
    return f.app(const VehicleDetailScreen(vehicleId: 'v1'), pushed: true);
  }, prepare: (tester, _) => _openTab(tester, 'Upkeep')),
  _Scene(
    'vehicle-maintenance-sheet',
    (f) async {
      await f.seedVehicles();
      await f.seedFuel();
      await f.seedMaintenance();
      return f.app(const VehicleDetailScreen(vehicleId: 'v1'), pushed: true);
    },
    prepare: (tester, _) async {
      await _openTab(tester, 'Upkeep');
      await _tap(tester, find.widgetWithText(FloatingActionButton, 'Reminder'));
    },
  ),
  _Scene('vehicle-documents-empty', (f) async {
    await f.seedVehicles();
    return f.app(const VehicleDetailScreen(vehicleId: 'v1'), pushed: true);
  }, prepare: (tester, _) => _openTab(tester, 'Papers')),
  _Scene('vehicle-documents', (f) async {
    await f.seedVehicles();
    await f.seedDocuments();
    return f.app(const VehicleDetailScreen(vehicleId: 'v1'), pushed: true);
  }, prepare: (tester, _) => _openTab(tester, 'Papers')),
  _Scene(
    'vehicle-documents-sheet',
    (f) async {
      await f.seedVehicles();
      await f.seedDocuments();
      return f.app(const VehicleDetailScreen(vehicleId: 'v1'), pushed: true);
    },
    prepare: (tester, _) async {
      await _openTab(tester, 'Papers');
      await _tap(tester, find.widgetWithText(FloatingActionButton, 'Document'));
    },
  ),
  _Scene(
    'vehicle-new',
    (f) async => f.app(const VehicleEditScreen(), pushed: true),
  ),
  _Scene('vehicle-edit', (f) async {
    await f.seedVehicles();
    return f.app(const VehicleEditScreen(vehicleId: 'v1'), pushed: true);
  }),

  // ------------------------------------------------------------- gates --
  _Scene(
    'gate-signed-out',
    (f) async => f.app(const _GateHost(), overrides: f.signedOut),
  ),
  _Scene('gate-no-cloud', (f) async => f.app(const _GateHost())),
  _Scene(
    'placeholder',
    (f) async => f.app(
      const PlaceholderScreen(
        title: 'Garage',
        tagline: 'Your cars, their fuel and their papers.',
        planned: ['Fuel log', 'Maintenance reminders', 'Documents'],
      ),
    ),
  ),
];

/// The Drive sheet's column, as the crash card meets it: a tonal surface
/// with the sheet's gutters and a line of content above and below.
class _DriveSheetStandIn extends StatelessWidget {
  const _DriveSheetStandIn({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Drive')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
        children: [
          Text('Last trip', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 12),
          child,
          const SizedBox(height: 12),
          Text('Recent', style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

/// A social tab root with the gate in front of its body.
class _GateHost extends StatelessWidget {
  const _GateHost();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Convoy')),
      body: const SignedInScope(
        message: 'Sign in to drive with friends in a convoy.',
        icon: Icons.route_outlined,
        child: Text('convoy body'),
      ),
    );
  }
}
