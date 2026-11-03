import 'package:drivalry/data/crash/crash_countdown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CrashCountdownController make({
    required List<String> log,
    bool testMode = false,
  }) => CrashCountdownController(
    startedAt: 1_000_000,
    testMode: testMode,
    onEscalate: () async => log.add('escalate'),
    onFinished: (o) => log.add('finished:${o.name}'),
    onSpeak: (t) => log.add('speak'),
  );

  test('counts down and escalates when nobody answers', () {
    final log = <String>[];
    final c = make(log: log);
    expect(c.tick(1_000_000), 30);
    expect(c.tick(1_010_000), 20);
    expect(c.tick(1_029_400), 1);
    expect(c.finished, isFalse);
    expect(c.tick(1_030_000), 0);
    expect(c.finished, isTrue);
    expect(c.outcome, CrashOutcome.escalated);
    expect(log.where((e) => e == 'escalate').length, 1);
    expect(log.last, 'finished:escalated');
    // Further ticks are inert.
    expect(c.tick(1_040_000), 0);
    expect(log.where((e) => e.startsWith('finished')).length, 1);
  });

  test("I'm OK cancels without escalating", () {
    final log = <String>[];
    final c = make(log: log);
    c.tick(1_005_000);
    c.imOk();
    expect(c.outcome, CrashOutcome.ok);
    expect(log, isNot(contains('escalate')));
    expect(log.last, 'finished:ok');
    c.tick(1_031_000);
    expect(log.where((e) => e.startsWith('finished')).length, 1);
  });

  test('send help now escalates immediately', () {
    final log = <String>[];
    final c = make(log: log);
    c.tick(1_001_000);
    c.sendHelpNow();
    expect(c.outcome, CrashOutcome.escalated);
    expect(log, contains('escalate'));
  });

  test('test mode never escalates, on timeout or on send help', () {
    final log = <String>[];
    final c = make(log: log, testMode: true);
    c.tick(1_031_000);
    expect(c.outcome, CrashOutcome.testEnded);
    expect(log, isNot(contains('escalate')));
    final log2 = <String>[];
    final c2 = make(log: log2, testMode: true);
    c2.sendHelpNow();
    expect(c2.outcome, CrashOutcome.testEnded);
    expect(log2, isNot(contains('escalate')));
  });

  test('speaks at 30, 20 and 10 seconds left, once each', () {
    final log = <String>[];
    final c = make(log: log);
    for (var ms = 1_000_000; ms < 1_030_000; ms += 500) {
      c.tick(ms);
    }
    expect(log.where((e) => e == 'speak').length, 3);
  });
}
