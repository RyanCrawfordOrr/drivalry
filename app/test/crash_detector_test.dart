import 'package:drivalry/tracking/crash_detector.dart';
import 'package:flutter_test/flutter_test.dart';

/// Feeds a realistic sequence: cruising at [cruise] m/s for 10 s, an impact
/// of [peak] m/s² half a second after the last cruising fix, then [after] m/s
/// for 8 s. Returns the confirmed candidate, if any.
CrashCandidate? drive(
  CrashDetector d, {
  double cruise = 15,
  double peak = 45,
  double after = 0,
  int t0 = 1_000_000,
}) {
  var t = t0;
  for (var i = 0; i < 10; i++) {
    d.onSpeed(t, cruise);
    t += 1000;
  }
  final tPeak = t - 500;
  d.onAccel(tPeak, peak);
  CrashCandidate? fired;
  for (var i = 0; i < 8; i++) {
    fired ??= d.onSpeed(t, after);
    t += 1000;
  }
  return fired;
}

void main() {
  test('hard impact at speed followed by a dead stop fires once', () {
    final d = CrashDetector();
    final c = drive(d);
    expect(c, isNotNull);
    expect(c!.peakMps2, 45);
    expect(c.speedBeforeMps, 15);
    expect(d.fired, isTrue);
    // A second impact on the same trip is ignored.
    expect(drive(d, t0: 2_000_000), isNull);
    d.reset();
    expect(drive(d, t0: 3_000_000), isNotNull);
  });

  test('a speed bump at parking speed never counts (speed gate)', () {
    expect(drive(CrashDetector(), cruise: 3, peak: 60), isNull);
  });

  test('a dropped phone at a standstill never counts', () {
    final d = CrashDetector();
    expect(drive(d, cruise: 0, peak: 80), isNull);
    expect(d.pending, isFalse);
  });

  test('fixes without a speed after the impact count as stopped', () {
    final d = CrashDetector();
    var t = 1_000_000;
    for (var i = 0; i < 5; i++) {
      d.onSpeed(t, 15);
      t += 1000;
    }
    expect(d.onAccel(t, 50), isTrue);
    // The OS tends to drop the speed field at a standstill: those fixes are
    // the "car is not moving" evidence, not a reason to give up.
    expect(d.onSpeed(t + 1000, null), isNull);
    final c = d.onSpeed(t + 5000, null);
    expect(c, isNotNull);
    expect(c!.speedBeforeMps, 15);
    expect(d.fired, isTrue);
  });

  test('a pothole (movement resumes within 5 s) is cancelled', () {
    expect(drive(CrashDetector(), after: 6), isNull);
  });

  test('a peak under the threshold is ignored', () {
    expect(drive(CrashDetector(), peak: 30), isNull);
  });

  test('confirmation needs the full after-window and two stopped samples', () {
    final d = CrashDetector();
    var t = 0;
    for (var i = 0; i < 5; i++) {
      d.onSpeed(t, 20);
      t += 1000;
    }
    expect(d.onAccel(t - 500, 50), isTrue, reason: 'opens a candidate');
    expect(d.pending, isTrue);
    expect(d.onSpeed(t, 0.2), isNull);
    expect(d.onSpeed(t + 1000, 0.1), isNull);
    expect(d.onSpeed(t + 3000, 0.0), isNull, reason: 'window not over');
    final c = d.onSpeed(t + 5000, 0.0);
    expect(c, isNotNull);
    expect(c!.t, t - 500);
  });

  test('no fixes after the impact: gives up instead of firing', () {
    final d = CrashDetector();
    var t = 0;
    for (var i = 0; i < 5; i++) {
      d.onSpeed(t, 20);
      t += 1000;
    }
    d.onAccel(t, 50);
    // Speedless fixes carry no evidence either way.
    expect(d.onSpeed(t + 2000, null), isNull);
    expect(d.onSpeed(t + 9000, null), isNull);
    expect(d.pending, isFalse);
    expect(d.fired, isFalse);
  });

  test('the hardest hit inside the window is the one reported', () {
    final d = CrashDetector();
    var t = 0;
    for (var i = 0; i < 5; i++) {
      d.onSpeed(t, 20);
      t += 1000;
    }
    expect(d.onAccel(t, 42), isTrue);
    expect(d.onAccel(t + 200, 70), isFalse, reason: 'same candidate');
    d.onSpeed(t + 1000, 0);
    final c = d.onSpeed(t + 5500, 0);
    expect(c!.peakMps2, 70);
    expect(c.t, t + 200);
  });
}
