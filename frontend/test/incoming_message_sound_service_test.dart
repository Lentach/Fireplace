import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/services/incoming_message_sound_service.dart';

void main() {
  group('IncomingMessageSoundService', () {
    // The only observable contract of play() is that it is best-effort: it
    // NEVER throws. Disabled it must short-circuit before touching audio;
    // enabled it must swallow the (test-env) plugin failure. Bare getter/setter
    // round-trips proved nothing, so those tautological tests are gone.

    test('play() is a true no-op when disabled (constructs no player)', () async {
      final svc = IncomingMessageSoundService();
      svc.setEnabledForTest(false);

      // The `!_enabled` guard must return BEFORE any AudioPlayer is built. In
      // this unit-test env just_audio's constructor leaks UNHANDLED async
      // errors (binding not initialized), so were the guard removed this call
      // would fail the test — that is what makes the no-op contract falsifiable.
      await expectLater(svc.play(), completes);

      // dispose() with a never-constructed (null) player must not throw.
      expect(svc.dispose, returnsNormally);
    });

    test('play() swallows failures and never throws when enabled', () async {
      final svc = IncomingMessageSoundService();
      svc.setEnabledForTest(true);

      // Enabled, play() builds an AudioPlayer and calls setAsset, which throws
      // in the plugin-less test env. play() must catch it internally and still
      // complete normally. just_audio's constructor ALSO leaks background async
      // errors that are not this service's contract, so they are absorbed by a
      // guarded zone; we assert only that play() itself never propagates.
      Object? playError;
      await runZonedGuarded(() async {
        try {
          await svc.play();
          svc.dispose();
        } catch (e) {
          playError = e; // play() itself threw -> best-effort contract broken.
        }
      }, (_, _) {
        // Absorb just_audio / audio_session background failures.
      });

      expect(playError, isNull);
    });
  });
}
