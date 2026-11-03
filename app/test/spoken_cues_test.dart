import 'dart:async';

import 'package:drivalry/features/cues/cue_settings.dart';
import 'package:drivalry/features/cues/cue_speaker.dart';
import 'package:drivalry/features/cues/live_limit.dart';
import 'package:drivalry/features/cues/spoken_cues.dart';
import 'package:drivalry/tracking/tracking_models.dart';
import 'package:flutter_test/flutter_test.dart';

const mph = 0.44704;
const t0 = 1_700_000_000_000;

LiveLimitState at(
  int t, {
  int? posted,
  double? speedMph,
  double confidence = 0.9,
  String trip = 'a',
}) => LiveLimitState(
  tripId: trip,
  limitMps: posted == null ? null : posted * mph,
  posted: posted,
  unitLabel: 'mph',
  confidence: confidence,
  speedMps: speedMph == null ? null : speedMph * mph,
  updatedAt: t,
);

void main() {
  const on = CueSettings(enabled: true);

  group('CueRules', () {
    test('nothing in the first 10 s, then the limit once', () {
      final r = CueRules()..startTrip(t0);
      expect(r.onState(at(t0, posted: 25, speedMph: 20), on), isEmpty);
      expect(r.onState(at(t0 + 5000, posted: 25, speedMph: 20), on), isEmpty);
      // Value was already seen before the quiet window ended: it is not
      // re-announced until it changes.
      expect(r.onState(at(t0 + 10_000, posted: 25, speedMph: 20), on), isEmpty);
      expect(r.onState(at(t0 + 15_000, posted: 35, speedMph: 20), on), [
        "Limit's 35",
      ]);
      expect(r.onState(at(t0 + 20_000, posted: 35, speedMph: 20), on), isEmpty);
    });

    test('a limit is announced when first known after the quiet window', () {
      final r = CueRules()..startTrip(t0);
      expect(r.onState(at(t0 + 5000, speedMph: 20), on), isEmpty);
      expect(r.onState(at(t0 + 12_000, posted: 25, speedMph: 20), on), [
        "Limit's 25",
      ]);
    });

    test('the same value is debounced for 20 s, then repeats', () {
      final r = CueRules()..startTrip(t0);
      expect(r.onState(at(t0 + 15_000, posted: 25, speedMph: 20), on), [
        "Limit's 25",
      ]);
      expect(r.onState(at(t0 + 20_000, posted: 35, speedMph: 20), on), [
        "Limit's 35",
      ]);
      // Back to 25 within 20 s of its last announcement: silent.
      expect(r.onState(at(t0 + 25_000, posted: 25, speedMph: 20), on), isEmpty);
      expect(
        r.onState(at(t0 + 30_000, posted: 35, speedMph: 20), on),
        isEmpty,
        reason: '35 was spoken 10 s ago',
      );
      expect(r.onState(at(t0 + 41_000, posted: 25, speedMph: 20), on), [
        "Limit's 25",
      ]);
    });

    test('low confidence or no limit stays silent', () {
      final r = CueRules()..startTrip(t0);
      expect(
        r.onState(
          at(t0 + 15_000, posted: 25, speedMph: 40, confidence: 0.5),
          on,
        ),
        isEmpty,
      );
      expect(r.onState(at(t0 + 20_000, speedMph: 80), on), isEmpty);
    });

    test(
      'over by needs 8 continuous seconds and repeats at most every 60 s',
      () {
        final r = CueRules()..startTrip(t0);
        r.onState(at(t0 + 15_000, posted: 30, speedMph: 30), on);
        // 7 mph over from t+20 s.
        expect(
          r.onState(at(t0 + 20_000, posted: 30, speedMph: 37), on),
          isEmpty,
        );
        expect(
          r.onState(at(t0 + 25_000, posted: 30, speedMph: 37), on),
          isEmpty,
        );
        expect(r.onState(at(t0 + 28_000, posted: 30, speedMph: 37), on), [
          'Over by 7',
        ]);
        expect(
          r.onState(at(t0 + 60_000, posted: 30, speedMph: 38), on),
          isEmpty,
        );
        expect(r.onState(at(t0 + 88_000, posted: 30, speedMph: 40), on), [
          'Over by 10',
        ]);
      },
    );

    test('dropping under the threshold resets the hold', () {
      final r = CueRules()..startTrip(t0);
      r.onState(at(t0 + 15_000, posted: 30, speedMph: 30), on);
      r.onState(at(t0 + 20_000, posted: 30, speedMph: 37), on);
      r.onState(at(t0 + 25_000, posted: 30, speedMph: 33), on); // only 3 over
      expect(r.onState(at(t0 + 29_000, posted: 30, speedMph: 37), on), isEmpty);
      expect(r.onState(at(t0 + 34_000, posted: 30, speedMph: 37), on), isEmpty);
      expect(r.onState(at(t0 + 37_000, posted: 30, speedMph: 37), on), [
        'Over by 7',
      ]);
    });

    test(
      'smooth after five clean minutes, reset by over-limit or harsh peak',
      () {
        final r = CueRules()..startTrip(t0);
        r.onState(at(t0 + 15_000, posted: 30, speedMph: 30), on);
        expect(
          r.onState(at(t0 + 299_000, posted: 30, speedMph: 30), on),
          isEmpty,
        );
        expect(r.onState(at(t0 + 300_000, posted: 30, speedMph: 30), on), [
          'Smooth',
        ]);
        // Not again for 10 minutes.
        expect(
          r.onState(at(t0 + 600_000, posted: 30, speedMph: 30), on),
          isEmpty,
        );
        r.onMotionPeak(t0 + 700_000, 4.0);
        expect(
          r.onState(at(t0 + 900_000, posted: 30, speedMph: 30), on),
          isEmpty,
        );
        expect(r.onState(at(t0 + 1_000_000, posted: 30, speedMph: 30), on), [
          'Smooth',
        ]);
        // Over the limit resets the clean window too.
        r.onState(at(t0 + 1_100_000, posted: 30, speedMph: 40), on);
        expect(
          r.onState(at(t0 + 1_399_000, posted: 30, speedMph: 30), on),
          isEmpty,
        );
      },
    );

    test('a soft peak does not reset the clean window', () {
      final r = CueRules()..startTrip(t0);
      r.onMotionPeak(t0 + 200_000, 2.0);
      expect(r.onState(at(t0 + 300_000, speedMph: 30), on), ['Smooth']);
    });

    test('per-cue toggles', () {
      final r = CueRules()..startTrip(t0);
      const noLimit = CueSettings(enabled: true, limit: false);
      expect(
        r.onState(at(t0 + 15_000, posted: 25, speedMph: 20), noLimit),
        isEmpty,
      );
      const noOver = CueSettings(enabled: true, over: false);
      r.onState(at(t0 + 20_000, posted: 25, speedMph: 40), noOver);
      expect(
        r.onState(at(t0 + 30_000, posted: 25, speedMph: 40), noOver),
        isEmpty,
      );
      const noSmooth = CueSettings(enabled: true, smooth: false);
      final r2 = CueRules()..startTrip(t0);
      expect(r2.onState(at(t0 + 400_000, speedMph: 30), noSmooth), isEmpty);
    });

    test('nothing outside a trip; a new trip starts fresh', () {
      final r = CueRules();
      expect(r.onState(at(t0 + 15_000, posted: 25, speedMph: 20), on), isEmpty);
      r.startTrip(t0);
      expect(r.onState(at(t0 + 15_000, posted: 25, speedMph: 20), on), [
        "Limit's 25",
      ]);
      r.endTrip();
      expect(r.onState(at(t0 + 20_000, posted: 35, speedMph: 20), on), isEmpty);
      r.startTrip(t0 + 100_000);
      expect(
        r.onState(at(t0 + 115_000, posted: 25, speedMph: 20), on),
        ["Limit's 25"],
        reason: 'debounce state does not survive a trip',
      );
    });

    test('km/h roads speak km/h numbers', () {
      final r = CueRules()..startTrip(t0);
      const s50 = LiveLimitState(
        tripId: 'a',
        limitMps: 50 / 3.6,
        posted: 50,
        unitLabel: 'km/h',
        confidence: 0.9,
        speedMps: 60 / 3.6,
        updatedAt: t0 + 15_000,
      );
      expect(r.onState(s50, on), ["Limit's 50"]);
      final later = LiveLimitState(
        tripId: 'a',
        limitMps: 50 / 3.6,
        posted: 50,
        unitLabel: 'km/h',
        confidence: 0.9,
        speedMps: 60 / 3.6,
        updatedAt: t0 + 24_000,
      );
      expect(r.onState(later, on), ['Over by 10']);
    });
  });

  group('SpokenCuesRunner', () {
    test('speaks cues through the speaker, follows trip events', () async {
      final speaker = SilentCueSpeaker();
      final states = StreamController<LiveLimitState>();
      final events = StreamController<TrackingEvent>();
      var cfg = on;
      final runner = SpokenCuesRunner(
        speaker: speaker,
        settings: () => cfg,
        blocked: () => false,
      )..attach(states.stream, events.stream);

      events.add(
        PhaseEvent(
          tripId: 'a',
          t: t0,
          phase: TripPhaseSignal.active,
          startedAt: t0,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      states.add(at(t0 + 15_000, posted: 25, speedMph: 20));
      await Future<void>.delayed(Duration.zero);
      expect(speaker.spoken, ["Limit's 25"]);
      expect(speaker.rate, 0.9);

      // Disabled: rules still track, nothing is said.
      cfg = const CueSettings(enabled: false);
      states.add(at(t0 + 40_000, posted: 35, speedMph: 20));
      await Future<void>.delayed(Duration.zero);
      expect(speaker.spoken, ["Limit's 25"]);

      // Blocked by a crash countdown.
      cfg = const CueSettings(enabled: true, rate: 1.1);
      final blockedRunner = SpokenCuesRunner(
        speaker: speaker,
        settings: () => cfg,
        blocked: () => true,
      );
      blockedRunner.rules.startTrip(t0);
      await blockedRunner.onState(at(t0 + 15_000, posted: 45, speedMph: 20));
      expect(speaker.spoken, ["Limit's 25"]);

      // Harsh peaks reach the rules.
      events.add(
        MotionPeaksEvent(
          tripId: 'a',
          t: t0 + 50_000,
          peaks: [MotionPeakSample(t: t0 + 50_000, peak: 4.2)],
        ),
      );
      await Future<void>.delayed(Duration.zero);
      states.add(at(t0 + 340_000, posted: 35, speedMph: 20));
      await Future<void>.delayed(Duration.zero);
      expect(speaker.spoken, [
        "Limit's 25",
      ], reason: 'clean window reset at 50 s');
      states.add(at(t0 + 351_000, posted: 35, speedMph: 20));
      await Future<void>.delayed(Duration.zero);
      expect(speaker.spoken.last, 'Smooth');
      expect(speaker.rate, 1.1);

      events.add(
        PhaseEvent(tripId: 'a', t: t0 + 400_000, phase: TripPhaseSignal.ended),
      );
      await Future<void>.delayed(Duration.zero);
      expect(runner.rules.inTrip, isFalse);
      runner.dispose();
      blockedRunner.dispose();
      await states.close();
      await events.close();
    });

    test('engine rate maps the multiplier onto the TTS scale', () {
      expect(TtsCueSpeaker.engineRate(1.0), 0.5);
      expect(TtsCueSpeaker.engineRate(0.6), closeTo(0.3, 1e-9));
      expect(TtsCueSpeaker.engineRate(3.0), 1.0);
    });
  });
}
