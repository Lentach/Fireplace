import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/utils/app_badge_math.dart';

void main() {
  group('app_badge_math', () {
    test('sumUnreadBadgeCounts sums map values', () {
      expect(sumUnreadBadgeCounts({1: 3, 2: 5}), 8);
      expect(sumUnreadBadgeCounts({}), 0);
      expect(sumUnreadBadgeCounts({10: 0, 11: 7}), 7);
    });
  });
}
