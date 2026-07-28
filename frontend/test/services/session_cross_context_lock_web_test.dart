import 'dart:async';

import 'package:fireplace/services/encryption/session_cross_context_lock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // WITHOUT `--platform chrome` there is no navigator.locks, so this cannot
  // run. It used to open with `if (!kIsWeb) return;`, which made the default
  // VM suite report it as PASSED while asserting nothing — the origin-wide
  // Web Lock could have been deleted from production and the suite would have
  // stayed green. An honest skip says so, and
  // `node scripts/verify-session-lock-probe.mjs` (CI job `session-lock`)
  // exercises the real API in a headless browser.
  test(
    'Web Lock serializes two independent callers with the same name',
    () async {
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      var secondStarted = false;

      final first = runSessionCrossContextLocked(
        'e2e-web-lock-probe',
        () async {
          firstStarted.complete();
          await releaseFirst.future;
          return 'first';
        },
      );
      await firstStarted.future;

      final second = runSessionCrossContextLocked(
        'e2e-web-lock-probe',
        () async {
          secondStarted = true;
          return 'second';
        },
      );
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(
        secondStarted,
        isFalse,
        reason: 'the browser must queue the second same-name lock request',
      );

      releaseFirst.complete();
      expect(await first, 'first');
      expect(await second, 'second');
    },
    skip: kIsWeb
        ? false
        : 'needs --platform chrome for navigator.locks; the real API is '
              'covered by scripts/verify-session-lock-probe.mjs in CI',
  );
}
