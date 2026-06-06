import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/services/incoming_message_sound_service.dart';

void main() {
  group('IncomingMessageSoundService', () {
    test('is enabled by default', () {
      final svc = IncomingMessageSoundService();
      expect(svc.enabled, isTrue);
    });

    test('setEnabledForTest(false) disables it', () {
      final svc = IncomingMessageSoundService();
      svc.setEnabledForTest(false);
      expect(svc.enabled, isFalse);
    });

    test('play() is a safe no-op when disabled (constructs no player)', () async {
      final svc = IncomingMessageSoundService();
      svc.setEnabledForTest(false);
      await svc.play(); // guard returns before any AudioPlayer is created
      svc.dispose();    // dispose with a null player must not throw
      // Reaching here without an exception is the assertion.
    });
  });
}
