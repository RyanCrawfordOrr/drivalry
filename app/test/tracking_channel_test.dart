import 'package:drivalry/tracking/tracking_channel.dart';
import 'package:drivalry/tracking/tracking_models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TrackingEvent.fromMap', () {
    test('phase with optional fields', () {
      final e = TrackingEvent.fromMap({
        'type': 'phase',
        'tripId': 't1',
        't': 1000,
        'phase': 'active',
        'reason': 'activity',
        'startedAt': 900,
      });
      expect(e, isA<PhaseEvent>());
      final p = e as PhaseEvent;
      expect(p.phase, TripPhaseSignal.active);
      expect(p.reason, 'activity');
      expect(p.startedAt, 900);
      expect(p.toMap()['phase'], 'active');
    });

    test('phase without optional fields', () {
      final e =
          TrackingEvent.fromMap({
                'type': 'phase',
                'tripId': 't1',
                't': 1000,
                'phase': 'discarded',
              })
              as PhaseEvent;
      expect(e.reason, isNull);
      expect(e.startedAt, isNull);
      expect(e.toMap().containsKey('reason'), isFalse);
    });

    test('fixes with and without optional fields', () {
      final e =
          TrackingEvent.fromMap({
                'type': 'fixes',
                'tripId': 't1',
                't': 5000,
                'fixes': [
                  {
                    't': 4000,
                    'lat': 1.5,
                    'lon': 2.5,
                    'speed': 12.0,
                    'accuracy': 5.0,
                    'heading': 90.0,
                    'altitude': 10.0,
                  },
                  {'t': 5000, 'lat': 1.6, 'lon': 2.6, 'accuracy': 8},
                ],
              })
              as FixesEvent;
      expect(e.fixes, hasLength(2));
      expect(e.fixes.first.heading, 90.0);
      expect(e.fixes.last.speed, isNull);
      expect(e.fixes.last.heading, isNull);
      expect(e.fixes.last.accuracy, 8.0);
      expect(e.toMap()['fixes'], hasLength(2));
    });

    test('motion peaks', () {
      final e =
          TrackingEvent.fromMap({
                'type': 'motion',
                'tripId': 't1',
                't': 7000,
                'events': [
                  {'t': 6000, 'kind': 'accelPeak', 'peak': 3.1},
                ],
              })
              as MotionPeaksEvent;
      expect(e.peaks.single.peak, 3.1);
    });

    test('phone kinds', () {
      for (final kind in PhoneSignal.values) {
        final e =
            TrackingEvent.fromMap({
                  'type': 'phone',
                  'tripId': 't1',
                  't': 1,
                  'kind': kind.name,
                })
                as PhoneEventRaw;
        expect(e.kind, kind);
      }
      expect(
        TrackingEvent.fromMap({
          'type': 'phone',
          'tripId': 't1',
          't': 1,
          'kind': 'bogus',
        }),
        isNull,
      );
    });

    test('hint and error', () {
      final h =
          TrackingEvent.fromMap({
                'type': 'hint',
                'tripId': 't1',
                't': 1,
                'kind': 'bluetooth',
                'name': 'My Car',
              })
              as HintEvent;
      expect(h.name, 'My Car');
      final err =
          TrackingEvent.fromMap({
                'type': 'error',
                'tripId': null,
                't': 1,
                'code': 'permission',
                'message': 'lost',
              })
              as TrackingError;
      expect(err.code, 'permission');
      expect(err.tripId, isNull);
    });

    test('unknown type is ignored', () {
      expect(
        TrackingEvent.fromMap({'type': 'future', 'tripId': 'x', 't': 1}),
        isNull,
      );
    });
  });

  group('state maps', () {
    test('TrackingState.fromMap', () {
      final s = TrackingState.fromMap({
        'phase': 'tentative',
        'tripId': 'abc',
        'enabled': true,
        'pausedUntil': 0,
        'spooledEvents': 4,
        'permissions': {
          'location': 'always',
          'preciseLocation': true,
          'motion': 'granted',
          'notifications': 'denied',
          'bluetooth': 'notDetermined',
        },
      });
      expect(s.phase, TrackingPhase.tentative);
      expect(s.tripId, 'abc');
      expect(s.spooledEvents, 4);
      expect(s.permissions.sufficientForAutoTracking, isTrue);
      expect(s.permissions.notifications, SimplePermission.denied);
      expect(s.pluginAvailable, isTrue);
    });

    test('permissions default to denied / notDetermined', () {
      final p = TrackingPermissions.fromMap(null);
      expect(p.location, LocationPermission.denied);
      expect(p.sufficientForManualTracking, isFalse);
    });

    test('diagnostics round-trip', () {
      final d = TrackingDiagnostics.fromMap({
        'lastTriggerAt': 12,
        'lastTriggerKind': 'bluetooth',
        'tentativeStarts': 2,
        'confirmedTrips': 1,
        'discardedTentatives': 1,
        'batteryLevel': 0.5,
        'serviceRunning': true,
      });
      expect(d.toMap()['lastTriggerKind'], 'bluetooth');
      expect(d.serviceRunning, isTrue);
    });
  });

  group('TrackingChannel', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    test('missing plugin answers unavailable instead of throwing', () async {
      final channel = TrackingChannel(
        methods: const MethodChannel('test/none'),
        events: const EventChannel('test/none/events'),
      );
      final s = await channel.getState();
      expect(s.pluginAvailable, isFalse);
      expect(await channel.drainSpool(), isEmpty);
      expect((await channel.getDiagnostics()).confirmedTrips, 0);
    });

    test('method results are decoded', () async {
      const methods = MethodChannel('test/tracking');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methods, (call) async {
            switch (call.method) {
              case 'getState':
                return {'phase': 'active', 'tripId': 'x', 'enabled': true};
              case 'drainSpool':
                return [
                  {
                    'type': 'phase',
                    'tripId': 'x',
                    't': 1,
                    'phase': 'tentative',
                  },
                  {'type': 'junk'},
                ];
              case 'setEnabled':
                expect(call.arguments, {'enabled': false});
                return {'phase': 'idle', 'enabled': false};
            }
            return null;
          });
      final channel = TrackingChannel(
        methods: methods,
        events: const EventChannel('test/tracking/events'),
      );
      expect((await channel.getState()).phase, TrackingPhase.active);
      final spool = await channel.drainSpool();
      expect(spool, hasLength(1));
      expect((await channel.setEnabled(false)).enabled, isFalse);
    });
  });
}
