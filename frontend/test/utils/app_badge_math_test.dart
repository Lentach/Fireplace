import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/utils/app_badge_math.dart';

void main() {
  group('app_badge_math', () {
    test('sumUnreadBadgeCounts sums map values', () {
      expect(sumUnreadBadgeCounts({1: 3, 2: 5}), 8);
      expect(sumUnreadBadgeCounts({}), 0);
      expect(sumUnreadBadgeCounts({10: 0, 11: 7}), 7);
    });

    test('capUnreadForBadge returns 0 for non-positive', () {
      expect(capUnreadForBadge(0), 0);
      expect(capUnreadForBadge(-1), 0);
    });

    test('capUnreadForBadge passes through 1..19', () {
      expect(capUnreadForBadge(1), 1);
      expect(capUnreadForBadge(19), 19);
    });

    test('capUnreadForBadge saturates at 19', () {
      expect(capUnreadForBadge(20), 19);
      expect(capUnreadForBadge(999), 19);
    });
  });
}
