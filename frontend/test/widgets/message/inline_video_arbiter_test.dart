import 'package:fireplace/widgets/message/inline_video_arbiter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InlineVideoArbiter', () {
    test('exactly one holder at a time; a higher priority takes the slot', () {
      final arbiter = InlineVideoArbiter.forTest();
      final older = Object();
      final newer = Object();

      expect(arbiter.request(older, () {}, priority: 1), isTrue);
      expect(arbiter.holds(older), isTrue);

      expect(arbiter.request(newer, () {}, priority: 2), isTrue);
      expect(arbiter.holds(newer), isTrue);
      expect(arbiter.holds(older), isFalse);
    });

    test('a lower priority against a live holder is denied, holder untouched '
        '(the owner\'s "second-to-last plays, last is blurred" on chat open)', () {
      final arbiter = InlineVideoArbiter.forTest();
      final newest = Object();
      final older = Object();
      var newestRevoked = false;

      arbiter.request(newest, () => newestRevoked = true, priority: 20);
      // Mount order put the older bubble's request AFTER the newest one's;
      // "latest requester wins" would have stolen the slot here.
      expect(arbiter.request(older, () {}, priority: 10), isFalse);

      expect(arbiter.holds(newest), isTrue);
      expect(arbiter.holds(older), isFalse);
      expect(newestRevoked, isFalse);
    });

    test('equal priority behaves like the old newest-requester rule', () {
      final arbiter = InlineVideoArbiter.forTest();
      final a = Object();
      final b = Object();

      arbiter.request(a, () {}, priority: 5);
      expect(arbiter.request(b, () {}, priority: 5), isTrue);
      expect(arbiter.holds(b), isTrue);
    });

    test('granting to a higher priority fires the previous holder\'s revoke '
        'callback, after the slot has already moved', () {
      final arbiter = InlineVideoArbiter.forTest();
      final a = Object();
      final b = Object();
      var aRevoked = false;

      arbiter.request(a, () {
        aRevoked = true;
        // The revoked holder's teardown releases; by contract that must be a
        // no-op because the slot already belongs to the new requester.
        arbiter.release(a);
      }, priority: 1);
      arbiter.request(b, () {}, priority: 2);

      expect(aRevoked, isTrue);
      expect(arbiter.holds(b), isTrue);
    });

    test('re-requesting while holding does not self-revoke', () {
      final arbiter = InlineVideoArbiter.forTest();
      final a = Object();
      var revoked = false;

      arbiter.request(a, () => revoked = true, priority: 1);
      arbiter.request(a, () => revoked = true, priority: 1);

      expect(revoked, isFalse);
      expect(arbiter.holds(a), isTrue);
    });

    test('releasing as a non-holder is a no-op', () {
      final arbiter = InlineVideoArbiter.forTest();
      final holder = Object();
      final stranger = Object();
      var holderRevoked = false;

      arbiter.request(holder, () => holderRevoked = true, priority: 1);
      arbiter.release(stranger);

      expect(arbiter.holds(holder), isTrue);
      expect(holderRevoked, isFalse);
    });

    test('release by the holder empties the slot, notifies, and lets a '
        'previously denied lower priority in', () {
      final arbiter = InlineVideoArbiter.forTest();
      final newest = Object();
      final older = Object();
      var revoked = false;
      var notified = 0;
      arbiter.addListener(() => notified++);

      arbiter.request(newest, () => revoked = true, priority: 20);
      expect(arbiter.request(older, () {}, priority: 10), isFalse);
      arbiter.release(newest);

      expect(arbiter.holds(newest), isFalse);
      expect(revoked, isFalse);
      // One for the grant, one for the release — the denied request must
      // NOT notify (it changed nothing), or every denial would re-trigger
      // every bubble's re-evaluation.
      expect(notified, 2);
      expect(arbiter.request(older, () {}, priority: 10), isTrue);
    });
  });
}
