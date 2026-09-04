import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:fireplace/services/e2e_lock_revoker.dart';

void main() {
  test('an unregistered revoker is a no-op, not a crash', () async {
    final revoker = E2eLockRevoker();
    await revoker.revoke();
    await revoker.restore();
    expect(revoker.isBusy, isFalse);
  });

  test('a restore can never overtake the teardown it follows', () async {
    final order = <String>[];
    final teardown = Completer<void>();
    final revoker = E2eLockRevoker()
      ..onRevoke = () async {
        order.add('revoke-start');
        await teardown.future;
        order.add('revoke-end');
      }
      ..onRestore = () async => order.add('restore');

    // Lock, then unlock before the teardown finishes — the shape a user
    // produces by tapping the padlock and typing the code immediately.
    // Both are queued, neither has started: the tail is a microtask chain.
    final revoked = revoker.revoke();
    final restored = revoker.restore();
    await Future<void>.delayed(Duration.zero);
    expect(order, ['revoke-start']);

    teardown.complete();
    await Future.wait([revoked, restored]);

    // Not merely "both ran": the restore must land AFTER the teardown, or it
    // re-initialises E2E onto stores that are about to lose their keys.
    expect(order, ['revoke-start', 'revoke-end', 'restore']);
  });

  test('a failed teardown surfaces to its caller and unblocks the queue',
      () async {
    var restored = false;
    final revoker = E2eLockRevoker()
      ..onRevoke = () async {
        throw StateError('storage gone');
      }
      ..onRestore = () async => restored = true;

    await expectLater(revoker.revoke(), throwsStateError);
    // The tail must not stay poisoned: one bad lock cannot wedge every later
    // unlock behind it.
    await revoker.restore();
    expect(restored, isTrue);
  });
}
