import 'package:drivalry/data/repos/presence_repo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PresenceGate', () {
    test('unknown hide state counts as hidden', () {
      final gate = PresenceGate(userId: 'u1');
      expect(gate.allowed, isFalse);
      expect(gate.onUserChanged('u1'), PresenceGateAction.none);
    });

    test('publishes once on the transition to visible, not per emission', () {
      final gate = PresenceGate(userId: 'u1');
      expect(gate.onHiddenChanged(false), PresenceGateAction.publish);
      expect(gate.allowed, isTrue);
      expect(gate.onHiddenChanged(false), PresenceGateAction.none);
      expect(gate.onHiddenChanged(false), PresenceGateAction.none);
    });

    test('hiding clears the row once; unhiding publishes again', () {
      final gate = PresenceGate(hidden: false, userId: 'u1');
      expect(gate.onHiddenChanged(true), PresenceGateAction.clear);
      expect(gate.allowed, isFalse);
      expect(gate.onHiddenChanged(true), PresenceGateAction.none);
      expect(gate.onHiddenChanged(false), PresenceGateAction.publish);
    });

    test('no audience: clear once, publish again when someone can see', () {
      final gate = PresenceGate(hidden: false, userId: 'u1');
      expect(gate.allowed, isTrue, reason: 'unknown audience still publishes');
      expect(gate.onAudienceChanged(null), PresenceGateAction.none);
      expect(gate.onAudienceChanged(true), PresenceGateAction.none);
      expect(gate.onAudienceChanged(false), PresenceGateAction.clear);
      expect(gate.allowed, isFalse);
      expect(gate.onAudienceChanged(false), PresenceGateAction.none);
      expect(gate.onAudienceChanged(true), PresenceGateAction.publish);
      expect(gate.allowed, isTrue);
    });

    test('audience changes do nothing while hidden or signed out', () {
      final hidden = PresenceGate(hidden: true, userId: 'u1');
      expect(hidden.onAudienceChanged(false), PresenceGateAction.none);
      expect(hidden.onAudienceChanged(true), PresenceGateAction.none);
      final signedOut = PresenceGate(hidden: false);
      expect(signedOut.onAudienceChanged(false), PresenceGateAction.none);
      // Signing in while hiding everywhere still publishes nothing.
      expect(signedOut.onUserChanged('u1'), PresenceGateAction.none);
    });

    test('signed out never publishes; signing in while visible does', () {
      final gate = PresenceGate(hidden: false);
      expect(gate.allowed, isFalse);
      expect(
        gate.onHiddenChanged(true),
        PresenceGateAction.none,
        reason: 'nothing to clear without a user',
      );
      expect(gate.onHiddenChanged(false), PresenceGateAction.none);
      expect(gate.onUserChanged('u1'), PresenceGateAction.publish);
      expect(gate.onUserChanged(null), PresenceGateAction.none);
      expect(gate.allowed, isFalse);
    });
  });
}
