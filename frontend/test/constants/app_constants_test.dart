import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/constants/app_constants.dart';

void main() {
  group('AppConstants', () {
    test('layoutBreakpointDesktop is 600', () {
      expect(AppConstants.layoutBreakpointDesktop, 600);
    });

    test('conversationsRefreshDelay is 500ms', () {
      expect(AppConstants.conversationsRefreshDelay.inMilliseconds, 500);
    });

    test('messagePageSize is 50', () {
      expect(AppConstants.messagePageSize, 50);
    });

    test('reconnect constants are positive', () {
      expect(AppConstants.reconnectMaxAttempts, greaterThan(0));
      expect(AppConstants.reconnectInitialDelay.inSeconds, greaterThan(0));
      expect(AppConstants.reconnectMaxDelay.inSeconds, greaterThanOrEqualTo(1));
    });
  });
}
