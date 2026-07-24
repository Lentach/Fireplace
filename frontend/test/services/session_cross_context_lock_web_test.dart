import 'dart:async';

import 'package:fireplace/services/encryption/session_cross_context_lock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Web Lock serializes two independent callers with the same name',
    () async {
      if (!kIsWeb) return;

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
  );
}
