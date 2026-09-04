import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/providers/passcode_provider.dart';
import 'package:fireplace/services/encryption/content_key_wrap.dart';
import 'package:fireplace/services/passcode_unlock_gate.dart';
import 'package:fireplace/services/passcode_kdf.dart';
import 'package:fireplace/services/passcode_store.dart';
import 'package:fireplace/utils/passcode_autolock.dart';

import '../support/passcode_fakes.dart';

void main() {
  const t0 = 1757000000000;

  late MemoryPasscodeStore store;
  late FakePasscodeKdf kdf;
  late int now;
  late PasscodeProvider passcode;

  late MemorySecureKv vaultStore;
  late ContentKeyWrap vault;
  late PasscodeUnlockGate gate;

  PasscodeProvider build({bool wrapKeys = false}) => PasscodeProvider(
    store: store,
    kdf: kdf,
    nowMs: () => now,
    vault: vault,
    gate: gate,
    wrapKeys: wrapKeys,
  );

  setUp(() {
    store = MemoryPasscodeStore();
    kdf = FakePasscodeKdf();
    now = t0;
    vaultStore = MemorySecureKv();
    vault = ContentKeyWrap(sealer: FakeContentSealer(), meta: vaultStore);
    gate = PasscodeUnlockGate();
    passcode = build();
  });

  String hex(int seed) => List<int>.generate(32, (i) => (seed + i) & 0xff)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();

  group('key wrapping (Phase 2)', () {
    test('enabling wraps the existing content keys and opens the E2E gate',
        () async {
      vaultStore.store['fp_sig_key_kidA'] = hex(9);
      vaultStore.store['fp_content_key_kidB'] = hex(20);
      await passcode.initialize();
      final wrapping = build(wrapKeys: true);
      await wrapping.initialize();

      final ok = await wrapping.enable(
        passcode: '123456',
        mode: PasscodeMode.digits6,
      );

      expect(ok, isTrue);
      expect(await vault.isWrappingOn(), isTrue);
      expect(vault.isLocked, isFalse);
      expect(
        WrappedContentKey.isEnvelope(vaultStore.store['fp_sig_key_kidA']!),
        isTrue,
      );
      expect(gate.isOpen, isTrue);
    });

    test('a wrapped device boots LOCKED even inside the auto-lock window',
        () async {
      // The KEK exists only in RAM, so a fresh process cannot read the key
      // material however recently the app was used. Demanding the code is
      // arithmetic here, not policy.
      final wrapping = build(wrapKeys: true);
      await wrapping.initialize();
      await wrapping.enable(passcode: '123456', mode: PasscodeMode.digits6);
      await wrapping.noteBackgrounded();
      now += 1000; // well inside the 60 s window
      // A real process restart loses the RAM-only KEK; the vault object is
      // shared in this test, so lock it to model the reboot honestly.
      vault.lock();

      final rebooted = build(wrapKeys: true);
      await rebooted.initialize();

      expect(rebooted.state, PasscodeLockState.locked);
      expect(gate.isOpen, isFalse, reason: 'E2E must wait for the unlock');
    });

    test('the right code reopens the vault and the gate', () async {
      final wrapping = build(wrapKeys: true);
      await wrapping.initialize();
      await wrapping.enable(passcode: '123456', mode: PasscodeMode.digits6);
      vault.lock();
      gate.close();
      wrapping.lockNow();

      expect(await wrapping.unlock('123456'), PasscodeUnlockResult.ok);
      expect(vault.isLocked, isFalse);
      expect(gate.isOpen, isTrue);
    });

    test('locking drops the KEK and closes the gate for the next boot',
        () async {
      final wrapping = build(wrapKeys: true);
      await wrapping.initialize();
      await wrapping.enable(passcode: '123456', mode: PasscodeMode.digits6);

      wrapping.lockNow();

      expect(vault.isLocked, isTrue);
      expect(gate.isOpen, isFalse);
    });

    test('4-digit codes are refused wherever wrapping is on', () async {
      final wrapping = build(wrapKeys: true);
      await wrapping.initialize();

      expect(
        await wrapping.enable(passcode: '1234', mode: PasscodeMode.digits4),
        isFalse,
        reason: '10k candidates are minutes offline once the code IS the key',
      );
      expect(await vault.isWrappingOn(), isFalse);
      // Still fine while the passcode is only a gate.
      expect(
        await passcode.enable(passcode: '1234', mode: PasscodeMode.digits4),
        isTrue,
      );
    });

    test('disabling unwraps every key first, so nothing is orphaned',
        () async {
      vaultStore.store['fp_content_key_kidB'] = hex(20);
      final wrapping = build(wrapKeys: true);
      await wrapping.initialize();
      await wrapping.enable(passcode: '123456', mode: PasscodeMode.digits6);

      expect(await wrapping.disable(passcode: '123456'), isTrue);

      expect(await vault.isWrappingOn(), isFalse);
      expect(vaultStore.store['fp_content_key_kidB'], hex(20));
      expect(wrapping.state, PasscodeLockState.disabled);
    });

    test('changing the code re-wraps the keys under the new KEK', () async {
      vaultStore.store['fp_content_key_kidB'] = hex(20);
      final wrapping = build(wrapKeys: true);
      await wrapping.initialize();
      await wrapping.enable(passcode: '123456', mode: PasscodeMode.digits6);
      final firstKekId = WrappedContentKey.kekIdOf(
        vaultStore.store['fp_content_key_kidB']!,
      );
      now += 5000;

      final ok = await wrapping.change(
        current: '123456',
        next: '654321',
        mode: PasscodeMode.digits6,
      );

      expect(ok, isTrue);
      final secondKekId = WrappedContentKey.kekIdOf(
        vaultStore.store['fp_content_key_kidB']!,
      );
      expect(secondKekId, isNot(firstKekId));
      // And the new code opens it on a fresh process.
      vault.lock();
      final rebooted = build(wrapKeys: true);
      await rebooted.initialize();
      expect(await rebooted.unlock('654321'), PasscodeUnlockResult.ok);
      expect(vault.isLocked, isFalse);
    });
  });

  group('initialize', () {
    test('a device with no passcode ends up disabled and never locked',
        () async {
      await passcode.initialize();

      expect(passcode.state, PasscodeLockState.disabled);
      expect(passcode.isEnabled, isFalse);
      expect(passcode.isLocked, isFalse);
    });

    test('an enabled passcode boots LOCKED once the auto-lock window passed',
        () async {
      await passcode.initialize();
      await passcode.enable(passcode: '1234', mode: PasscodeMode.digits4);
      await passcode.noteBackgrounded();
      now += const Duration(minutes: 5).inMilliseconds;

      final rebooted = build();
      await rebooted.initialize();

      expect(rebooted.state, PasscodeLockState.locked);
      expect(rebooted.isLocked, isTrue);
    });

    test('boots UNLOCKED inside the window, because a web PWA cold-boots on '
        'thaw and a stricter rule would make the timer meaningless there',
        () async {
      await passcode.initialize();
      await passcode.enable(passcode: '1234', mode: PasscodeMode.digits4);
      await passcode.setAutoLockSeconds(60);
      await passcode.noteBackgrounded();
      now += const Duration(seconds: 5).inMilliseconds;

      final rebooted = build();
      await rebooted.initialize();

      expect(rebooted.state, PasscodeLockState.unlocked);
    });

    test('an enabled passcode with no stamp on disk boots locked', () async {
      await passcode.initialize();
      await passcode.enable(passcode: '1234', mode: PasscodeMode.digits4);
      await store.saveLastActiveAt(null);

      final rebooted = build();
      await rebooted.initialize();

      expect(rebooted.state, PasscodeLockState.locked);
    });
  });

  group('a store that throws', () {
    test('never leaves the gate holding on unknown', () async {
      // Holding `unknown` forever would brick the app behind a blank
      // surface. Fail open, same call the store makes for a partial
      // credential.
      final broken = PasscodeProvider(
        store: _ThrowingStore(),
        kdf: kdf,
        nowMs: () => now,
      );

      await broken.initialize();

      expect(broken.state, PasscodeLockState.disabled);
      expect(broken.isLocked, isFalse);
    });

    testWidgets('a store that HANGS cannot hold the gate forever',
        (tester) async {
      // Worse than throwing: no error, no completion. Observed for real —
      // `SharedPreferences.getInstance()` never answers under the widget-test
      // binding without mock values, and the gate covered the app forever.
      final hung = PasscodeProvider(
        store: _HangingStore(),
        kdf: kdf,
        nowMs: () => now,
      );

      final done = hung.initialize();
      await tester.pump(kPasscodeStoreReadTimeout + const Duration(seconds: 1));
      await done;

      expect(hung.state, PasscodeLockState.disabled);
    });
  });

  group('a damaged credential', () {
    // Flag true, verifier unreadable: a passcode EXISTS and cannot be
    // checked. Fail CLOSED — the opposite polarity to an unreadable store,
    // because here there is positive evidence the user set one.
    PasscodeProvider damagedProvider() {
      store.record = PasscodeRecord(
        enabled: false,
        credentialDamaged: true,
        mode: PasscodeMode.digits4,
        salt: null,
        verifier: null,
        iterations: 1,
        autoLockSeconds: 3600,
        lastActiveAtMs: now,
        failedAttempts: 0,
        lockoutUntilMs: null,
      );
      return build();
    }

    test('boots LOCKED even though nothing can verify a code', () async {
      final damaged = damagedProvider();
      await damaged.initialize();

      expect(damaged.state, PasscodeLockState.locked);
    });

    test('every code attempt reports unavailable, never wrong', () async {
      final damaged = damagedProvider();
      await damaged.initialize();

      expect(await damaged.unlock('1234'), PasscodeUnlockResult.unavailable);
      expect(damaged.state, PasscodeLockState.locked);
      expect(damaged.failedAttempts, 0);
    });

    test('an erase is the way out and it clears the wreckage', () async {
      final damaged = damagedProvider();
      await damaged.initialize();

      // What the eraser does to storage, then the gate's re-read.
      await store.clearCredential();
      await damaged.initialize();

      expect(damaged.state, PasscodeLockState.disabled);
      expect(store.record.enabled, isFalse);
      expect(store.record.credentialDamaged, isFalse);
    });
  });

  group('enable', () {
    test('stores a credential and leaves the app unlocked', () async {
      await passcode.initialize();

      final ok = await passcode.enable(
        passcode: '123456',
        mode: PasscodeMode.digits6,
      );

      expect(ok, isTrue);
      expect(passcode.state, PasscodeLockState.unlocked);
      expect(passcode.isEnabled, isTrue);
      expect(passcode.mode, PasscodeMode.digits6);
      expect(store.record.enabled, isTrue);
      expect(store.record.verifier, isNotNull);
      expect(store.record.iterations, kPasscodeKdfIterations);
    });

    test('rejects a code that does not match its mode length', () async {
      await passcode.initialize();

      expect(
        await passcode.enable(passcode: '123', mode: PasscodeMode.digits4),
        isFalse,
      );
      expect(
        await passcode.enable(passcode: '12345', mode: PasscodeMode.digits6),
        isFalse,
      );
      expect(
        await passcode.enable(passcode: 'ab', mode: PasscodeMode.alphanumeric),
        isFalse,
      );
      expect(store.credentialWrites, 0);
      expect(passcode.state, PasscodeLockState.disabled);
    });

    test('a derivation failure enables nothing at all', () async {
      await passcode.initialize();
      kdf.broken = true;

      expect(
        await passcode.enable(passcode: '1234', mode: PasscodeMode.digits4),
        isFalse,
      );
      expect(store.credentialWrites, 0);
      expect(passcode.state, PasscodeLockState.disabled);
    });
  });

  group('unlock', () {
    setUp(() async {
      await passcode.initialize();
      await passcode.enable(passcode: '1234', mode: PasscodeMode.digits4);
      passcode.lockNow();
    });

    test('the right code unlocks and clears the failure count', () async {
      expect(await passcode.unlock('1234'), PasscodeUnlockResult.ok);
      expect(passcode.state, PasscodeLockState.unlocked);
      expect(passcode.failedAttempts, 0);
    });

    test('a wrong code stays locked and counts the attempt', () async {
      expect(await passcode.unlock('9999'), PasscodeUnlockResult.wrong);
      expect(passcode.state, PasscodeLockState.locked);
      expect(passcode.failedAttempts, 1);
      expect(store.record.failedAttempts, 1);
    });

    test('a correct code after failures resets the counter', () async {
      await passcode.unlock('9999');
      await passcode.unlock('8888');
      expect(passcode.failedAttempts, 2);

      expect(await passcode.unlock('1234'), PasscodeUnlockResult.ok);
      expect(passcode.failedAttempts, 0);
      expect(store.record.failedAttempts, 0);
      expect(store.record.lockoutUntilMs, isNull);
    });

    test('a derivation failure is reported, not counted as a wrong code',
        () async {
      kdf.broken = true;

      expect(await passcode.unlock('1234'), PasscodeUnlockResult.unavailable);
      expect(passcode.failedAttempts, 0);
      expect(passcode.state, PasscodeLockState.locked);
    });

    test('unlocking while the backoff is active is refused without a derive',
        () async {
      for (var i = 0; i < kPasscodeAttemptsBeforeBackoff; i++) {
        await passcode.unlock('0000');
      }
      expect(passcode.lockoutRemaining, isNotNull);

      final callsBefore = kdf.calls;
      expect(
        await passcode.unlock('1234'),
        PasscodeUnlockResult.temporarilyBlocked,
      );
      expect(kdf.calls, callsBefore, reason: 'must not even hash while blocked');

      now += passcodeBackoffFor(kPasscodeAttemptsBeforeBackoff).inMilliseconds;
      expect(await passcode.unlock('1234'), PasscodeUnlockResult.ok);
    });
  });

  group('auto-lock', () {
    setUp(() async {
      await passcode.initialize();
      await passcode.enable(passcode: '1234', mode: PasscodeMode.digits4);
      await passcode.setAutoLockSeconds(60);
    });

    test('backgrounding stamps the clock and returning early stays unlocked',
        () async {
      await passcode.noteBackgrounded();
      expect(store.record.lastActiveAtMs, t0);

      now += const Duration(seconds: 30).inMilliseconds;
      await passcode.evaluateOnForeground();

      expect(passcode.state, PasscodeLockState.unlocked);
    });

    test('returning after the window locks', () async {
      await passcode.noteBackgrounded();
      now += const Duration(seconds: 61).inMilliseconds;

      await passcode.evaluateOnForeground();

      expect(passcode.state, PasscodeLockState.locked);
    });

    test('with immediate auto-lock, backgrounding locks on the spot', () async {
      await passcode.setAutoLockSeconds(0);
      await passcode.noteBackgrounded();

      expect(passcode.state, PasscodeLockState.locked);
    });

    test('a disabled passcode never locks on return', () async {
      await passcode.disable(passcode: '1234');
      await passcode.noteBackgrounded();
      now += const Duration(days: 1).inMilliseconds;

      await passcode.evaluateOnForeground();

      expect(passcode.state, PasscodeLockState.disabled);
    });
  });

  group('disable and change', () {
    setUp(() async {
      await passcode.initialize();
      await passcode.enable(passcode: '1234', mode: PasscodeMode.digits4);
    });

    test('the right code disables and destroys the credential', () async {
      expect(await passcode.disable(passcode: '1234'), isTrue);
      expect(passcode.state, PasscodeLockState.disabled);
      expect(store.record.enabled, isFalse);
      expect(store.record.verifier, isNull);
    });

    test('a wrong code changes nothing', () async {
      expect(await passcode.disable(passcode: '0000'), isFalse);
      expect(passcode.state, PasscodeLockState.unlocked);
      expect(store.record.enabled, isTrue);
    });

    test('change swaps the credential and the new code unlocks', () async {
      expect(
        await passcode.change(
          current: '1234',
          next: '654321',
          mode: PasscodeMode.digits6,
        ),
        isTrue,
      );
      expect(passcode.mode, PasscodeMode.digits6);

      passcode.lockNow();
      expect(await passcode.unlock('1234'), PasscodeUnlockResult.wrong);
      expect(await passcode.unlock('654321'), PasscodeUnlockResult.ok);
    });

    test('change with a wrong current code keeps the old credential',
        () async {
      expect(
        await passcode.change(
          current: '0000',
          next: '654321',
          mode: PasscodeMode.digits6,
        ),
        isFalse,
      );
      expect(passcode.mode, PasscodeMode.digits4);

      passcode.lockNow();
      expect(await passcode.unlock('1234'), PasscodeUnlockResult.ok);
    });
  });

  group('forgotten passcode', () {
    test('has no provider-side escape: only an erase can clear the credential',
        () async {
      // Owner ruling 2026-09-04: no password door. The provider deliberately
      // exposes nothing that drops the credential — that power lives in
      // `services/local_data_eraser.dart`, behind a typed confirmation, and
      // it destroys the guarded data along with the code. Re-reading a wiped
      // store is what actually opens the gate.
      await passcode.initialize();
      await passcode.enable(passcode: '1234', mode: PasscodeMode.digits4);
      passcode.lockNow();

      await store.clearCredential();
      await passcode.initialize();

      expect(passcode.state, PasscodeLockState.disabled);
      expect(store.record.enabled, isFalse);
      expect(store.record.verifier, isNull);
    });
  });

  group('notifications', () {
    test('lockNow notifies listeners exactly once', () async {
      await passcode.initialize();
      await passcode.enable(passcode: '1234', mode: PasscodeMode.digits4);

      var notifications = 0;
      passcode.addListener(() => notifications++);
      passcode.lockNow();

      expect(notifications, 1);
      expect(passcode.isLocked, isTrue);
    });

    test('lockNow on a disabled passcode does nothing and does not notify',
        () async {
      await passcode.initialize();

      var notifications = 0;
      passcode.addListener(() => notifications++);
      passcode.lockNow();

      expect(notifications, 0);
      expect(passcode.state, PasscodeLockState.disabled);
    });
  });
}

class _ThrowingStore implements PasscodeStore {
  @override
  Future<PasscodeRecord> load() async => throw StateError('storage down');

  @override
  Future<void> clearCredential() async {}

  @override
  Future<void> saveAttemptState({
    required int failedAttempts,
    required int? lockoutUntilMs,
  }) async {}

  @override
  Future<void> saveAutoLockSeconds(int seconds) async {}

  @override
  Future<void> saveCredential({
    required PasscodeMode mode,
    required Uint8List salt,
    required Uint8List verifier,
    required int iterations,
  }) async {}

  @override
  Future<void> saveLastActiveAt(int? epochMs) async {}
}

/// Never completes — models a platform channel that silently stops answering.
class _HangingStore extends _ThrowingStore {
  @override
  Future<PasscodeRecord> load() => Completer<PasscodeRecord>().future;
}
