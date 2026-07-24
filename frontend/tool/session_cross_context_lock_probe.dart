import 'dart:async';
import 'dart:js_interop';

import 'package:fireplace/services/encryption/session_cross_context_lock.dart';
import 'package:web/web.dart' as web;

@JS('disableWebLocksForProbe')
external void disableWebLocksForProbe();

/// Browser smoke probe for the origin-wide Signal session lock.
///
/// Compile and serve using the commands in
/// `docs/runbooks/e2e-decryption-failed.md` Step 3A. The page title becomes
/// `SESSION_LOCK_PASS` only when same-name requests queue and a missing Web
/// Locks API fails closed without running the guarded action.
Future<void> main() async {
  final firstStarted = Completer<void>();
  final releaseFirst = Completer<void>();
  var secondStarted = false;

  final first = runSessionCrossContextLocked('same-name', () async {
    firstStarted.complete();
    await releaseFirst.future;
    return 'first';
  });
  await firstStarted.future;
  final second = runSessionCrossContextLocked('same-name', () async {
    secondStarted = true;
    return 'second';
  });
  await Future<void>.delayed(Duration.zero);
  if (secondStarted) throw StateError('same-name lock did not queue');
  releaseFirst.complete();
  if (await first != 'first' || await second != 'second') {
    throw StateError('wrong lock result');
  }

  disableWebLocksForProbe();
  var unlockedActionRan = false;
  try {
    await runSessionCrossContextLocked('unsupported', () async {
      unlockedActionRan = true;
      return 'unsafe';
    });
    throw StateError('missing Web Locks API did not fail closed');
  } on UnsupportedError {
    if (unlockedActionRan) throw StateError('Signal mutation ran unlocked');
  }

  web.document.title = 'SESSION_LOCK_PASS';
}
