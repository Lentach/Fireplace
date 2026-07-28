import 'package:fireplace/services/server_clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ServerClock', () {
    setUp(() {
      ServerClock.instance.resetForTest();
    });

    test('has no estimate before a server observation', () {
      expect(ServerClock.instance.estimatedNow, isNull);
    });

    test('projects forward from an observed server instant', () {
      final observed = DateTime.utc(2026, 7, 28, 12);

      ServerClock.instance.observe(observed);

      final estimate = ServerClock.instance.estimatedNow;
      expect(estimate, isNotNull);
      expect(estimate!.isBefore(observed), isFalse);
    });

    test('observeIso ignores null, non-string, and malformed values', () {
      expect(() {
        ServerClock.instance.observeIso(null);
        ServerClock.instance.observeIso(123);
        ServerClock.instance.observeIso('not-an-iso-instant');
      }, returnsNormally);
      expect(ServerClock.instance.estimatedNow, isNull);
    });
  });
}
