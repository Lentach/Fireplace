import 'package:fireplace/widgets/message/inline_video_arbiter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InlineVideoArbiter', () {
    test('exactly one holder at a time; newest requester wins', () {
      final arbiter = InlineVideoArbiter.forTest();
      final a = Object();
      final b = Object();

      arbiter.request(a, () {});
      expect(arbiter.holds(a), isTrue);

      arbiter.request(b, () {});
      expect(arbiter.holds(b), isTrue);
      expect(arbiter.holds(a), isFalse);
    });

    test('granting to a new requester fires the previous holder\'s revoke '
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
      });
      arbiter.request(b, () {});

      expect(aRevoked, isTrue);
      expect(arbiter.holds(b), isTrue);
    });

    test('re-requesting while holding does not self-revoke', () {
      final arbiter = InlineVideoArbiter.forTest();
      final a = Object();
      var revoked = false;

      arbiter.request(a, () => revoked = true);
      arbiter.request(a, () => revoked = true);

      expect(revoked, isFalse);
      expect(arbiter.holds(a), isTrue);
    });

    test('releasing as a non-holder is a no-op', () {
      final arbiter = InlineVideoArbiter.forTest();
      final holder = Object();
      final stranger = Object();
      var holderRevoked = false;

      arbiter.request(holder, () => holderRevoked = true);
      arbiter.release(stranger);

      expect(arbiter.holds(holder), isTrue);
      expect(holderRevoked, isFalse);
    });

    test('release by the holder empties the slot without firing revoke', () {
      final arbiter = InlineVideoArbiter.forTest();
      final a = Object();
      var revoked = false;

      arbiter.request(a, () => revoked = true);
      arbiter.release(a);

      expect(arbiter.holds(a), isFalse);
      expect(revoked, isFalse);
    });
  });
}
