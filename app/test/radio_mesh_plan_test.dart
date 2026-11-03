import 'package:drivalry/features/convoy/radio/mesh_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MeshPlan', () {
    test('the lower user id offers', () {
      final plan = MeshPlan('b');
      expect(plan.offersTo('c'), isTrue);
      expect(plan.offersTo('a'), isFalse);
    });

    test('joining opens one link per present peer with the right role', () {
      final plan = MeshPlan('b');
      final actions = plan.onJoined({'a', 'b', 'c'}, 0);
      expect(actions, hasLength(2));
      expect(actions, contains(const MeshAction(MeshActionKind.await_, 'a')));
      expect(actions, contains(const MeshAction(MeshActionKind.offer, 'c')));
      expect(plan.isOfferer('c'), isTrue);
      expect(plan.isOfferer('a'), isFalse);
    });

    test('a newcomer hello opens a link; a later hello replaces it', () {
      final plan = MeshPlan('a', helloGraceMs: 10_000);
      expect(plan.onHello('b', 0), [
        const MeshAction(MeshActionKind.offer, 'b'),
      ]);
      // Same join seen twice (presence then hello): ignored while young.
      expect(plan.onHello('b', 5000), isEmpty);
      // A connected peer saying hello again has restarted: replace.
      plan.onHealth('b', LinkHealth.connected, 6000);
      expect(plan.onHello('b', 7000), [
        const MeshAction(MeshActionKind.remove, 'b'),
        const MeshAction(MeshActionKind.offer, 'b'),
      ]);
      // An old link still connecting is also replaced.
      expect(plan.onHello('b', 30_000), hasLength(2));
      expect(plan.onHello('a', 0), isEmpty, reason: 'own hello is ignored');
    });

    test('an unsolicited offer opens an awaiting link once', () {
      final plan = MeshPlan('z');
      expect(plan.onUnsolicitedOffer('a', 0), [
        const MeshAction(MeshActionKind.await_, 'a'),
      ]);
      expect(plan.onUnsolicitedOffer('a', 0), isEmpty);
    });

    test('bye and lost presence remove links; new presence opens them', () {
      final plan = MeshPlan('a')..onJoined({'b', 'c'}, 0);
      expect(plan.onBye('b'), [const MeshAction(MeshActionKind.remove, 'b')]);
      expect(plan.onBye('b'), isEmpty);
      expect(plan.onPresence({'a'}, 0), [
        const MeshAction(MeshActionKind.remove, 'c'),
      ]);
      expect(plan.peers, isEmpty);
      expect(plan.onPresence({'a', 'd'}, 0), [
        const MeshAction(MeshActionKind.offer, 'd'),
      ]);
      expect(plan.onPresence({'a', 'd'}, 1), isEmpty, reason: 'no change');
    });

    test('a presence sync without me is partial and ignored', () {
      final plan = MeshPlan('a')..onJoined({'b'}, 0);
      expect(plan.onPresence(const {}, 0), isEmpty);
      expect(plan.onPresence({'c'}, 0), isEmpty);
      expect(plan.has('b'), isTrue);
    });

    test('a stalled link restarts after 10 s from the offerer side only', () {
      final plan = MeshPlan('a', restartAfterMs: 10_000)
        ..onJoined({'b', 'c'}, 0);
      // 'a' offers to both (lowest id).
      plan.onHealth('b', LinkHealth.stalled, 1000);
      expect(plan.onTick(5000), isEmpty);
      expect(plan.onTick(11_000), [
        const MeshAction(MeshActionKind.restart, 'b'),
      ]);
      // Not again until another full period.
      expect(plan.onTick(15_000), isEmpty);
      expect(plan.onTick(21_000), [
        const MeshAction(MeshActionKind.restart, 'b'),
      ]);
      // Recovery clears the timer.
      plan.onHealth('b', LinkHealth.connected, 22_000);
      expect(plan.onTick(40_000), isEmpty);
    });

    test('the awaiting side never restarts; it waits for the offerer', () {
      final plan = MeshPlan('z', restartAfterMs: 10_000)..onJoined({'a'}, 0);
      plan.onHealth('a', LinkHealth.failed, 0);
      expect(plan.onTick(10_000), isEmpty);
    });

    test('too many restarts drops the link', () {
      final plan = MeshPlan('a', restartAfterMs: 1000, maxRestarts: 2)
        ..onJoined({'b'}, 0);
      plan.onHealth('b', LinkHealth.failed, 0);
      expect(plan.onTick(1000).single.kind, MeshActionKind.restart);
      expect(plan.onTick(2000).single.kind, MeshActionKind.restart);
      expect(plan.onTick(3000), [const MeshAction(MeshActionKind.remove, 'b')]);
      expect(plan.has('b'), isFalse);
    });

    test('leaving removes everything', () {
      final plan = MeshPlan('a')..onJoined({'b', 'c'}, 0);
      final actions = plan.onLeave();
      expect(actions.map((a) => a.kind).toSet(), {MeshActionKind.remove});
      expect(actions, hasLength(2));
      expect(plan.peers, isEmpty);
    });
  });
}
