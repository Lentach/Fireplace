import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/services/encryption_service.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cross-race probe for the 2026-07-07 "[Decryption failed]" field reports.
/// HISTORICAL BUG (fixed by the 0.0.94 `_sessionTails` lock): the 0.0.90 fix
/// serialized encrypt-vs-encrypt per recipient, but encrypt and decrypt ran
/// under TWO SEPARATE locks (the old EncryptionService._encryptTails vs
/// MessagingProvider._decryptChainBySender) while both do load→mutate→store
/// on the SAME Signal SessionRecord. Today EVERY session mutator (encrypt,
/// decrypt, buildSession, deleteSession) shares the in-process per-peer queue
/// plus an origin-wide lock across PWA engines.
///
/// Lost-update mechanics: an encrypt loads the session, a concurrent decrypt
/// loads the same session, one stores, then the other stores a STALE record
/// over it. When the decrypt's store lands last, the sender chain rolls back
/// and the NEXT encrypt reuses a chain counter the receiver already consumed
/// → receiver throws DuplicateMessageException → permanent
/// "[Decryption failed]" on a brand-new message.
///
/// Real-world trigger: replying while a history/resume decrypt pass is still
/// running (iOS PWA resume churn), or receiving a live message mid-send.
///
/// Both parties run the real EncryptionService over real libsignal.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const aliceId = 1;
  const bobId = 2;

  late EncryptionService alice;
  late EncryptionService bob;
  late _InMemoryCrossContextLock crossContextLock;

  Map<String, dynamic> flatBundleFrom(EncryptionService peer) {
    final upload = peer.getKeysForUpload();
    final keyBundle = (upload!['keyBundle'] as Map).cast<String, dynamic>();
    final otp = (upload['oneTimePreKeys'] as List)
        .cast<Map<String, dynamic>>()
        .first;
    return {
      ...keyBundle,
      'oneTimePreKeyId': otp['keyId'],
      'oneTimePreKeyPublic': otp['publicKey'],
    };
  }

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    crossContextLock = _InMemoryCrossContextLock();
    alice = EncryptionService(sessionCrossContextLock: crossContextLock.run);
    bob = EncryptionService(sessionCrossContextLock: crossContextLock.run);
    await alice.initialize(aliceId, checkServerBundleExists: () async => false);
    await bob.initialize(bobId, checkServerBundleExists: () async => false);
  });

  Future<void> settleHandshake() async {
    await alice.buildSession(bobId, flatBundleFrom(bob), expectedIdentityBase64: null);
    expect(
      await bob.decrypt(aliceId, await alice.encrypt(bobId, 'opener')),
      'opener',
    );
    expect(
      await alice.decrypt(bobId, await bob.encrypt(aliceId, 'ack')),
      'ack',
    );
  }

  test(
    'decrypting inbound WHILE encrypting outbound keeps both ratchet chains intact',
    () async {
      await settleHandshake();

      // Bob pre-encrypts a clean sequential batch — every wire is valid.
      const n = 10;
      final inboundPlain = List.generate(n, (i) => 'inbound #$i');
      final inboundWires = <String>[];
      for (final p in inboundPlain) {
        inboundWires.add(await bob.encrypt(aliceId, p));
      }

      // Alice runs the app's two real loops CONCURRENTLY:
      //  - decrypt loop: sequential per sender (what _runDecryptSerialized does)
      //  - encrypt loop: sequential per recipient (what the 0.0.90 queue did)
      // Pre-0.0.94 nothing serialized the two AGAINST EACH OTHER — the bug this
      // probe was written for; the shared _sessionTails queue now must.
      final decryptFailures = <String>[];
      final decrypted = <String>[];
      final outboundWires = <String>[];
      final decryptTask = () async {
        for (var i = 0; i < inboundWires.length; i++) {
          try {
            decrypted.add(await alice.decrypt(bobId, inboundWires[i]));
          } catch (e) {
            decryptFailures.add('inbound #$i: ${e.runtimeType}: $e');
          }
        }
      }();
      final encryptTask = () async {
        for (var i = 0; i < n; i++) {
          outboundWires.add(await alice.encrypt(bobId, 'reply #$i'));
        }
      }();
      await Future.wait([decryptTask, encryptTask]);

      // Alice's own inbound decrypts must all have survived the overlap.
      expect(
        decryptFailures,
        isEmpty,
        reason: 'inbound decrypts failed during overlap: $decryptFailures',
      );
      expect(decrypted, inboundPlain);

      // Duplicate ciphertexts would prove two encrypts consumed the same
      // ratchet step (sender-chain rollback via lost update).
      expect(
        outboundWires.toSet().length,
        outboundWires.length,
        reason: 'encrypts overlapping decrypts produced identical ciphertext',
      );

      // Bob decrypts Alice's replies in emit order (serialized, as the app does).
      final replyFailures = <String>[];
      for (var i = 0; i < outboundWires.length; i++) {
        try {
          final out = await bob.decrypt(aliceId, outboundWires[i]);
          if (out != 'reply #$i') {
            replyFailures.add('#$i: WRONG PLAINTEXT (got "$out")');
          }
        } catch (e) {
          replyFailures.add('#$i: ${e.runtimeType}: $e');
        }
      }
      expect(
        replyFailures,
        isEmpty,
        reason:
            'replies sent during an inbound decrypt pass must all decrypt; '
            'failures: $replyFailures',
      );
    },
  );

  test(
    'control: alternating sequential decrypt/encrypt stays intact',
    () async {
      await settleHandshake();

      for (var i = 0; i < 10; i++) {
        final inbound = await bob.encrypt(aliceId, 'inbound #$i');
        expect(await alice.decrypt(bobId, inbound), 'inbound #$i');
        final reply = await alice.encrypt(bobId, 'reply #$i');
        expect(await bob.decrypt(aliceId, reply), 'reply #$i');
      }
    },
  );

  test('GATED lost update: decrypt store landing after a concurrent encrypt '
      'must not roll back the sender chain (counter reuse)', () async {
    await settleHandshake();

    final gate = _GatedSessionStore.install(alice);

    final inbound = await bob.encrypt(aliceId, 'inbound during overlap');

    // Deterministic interleave, mirroring "reply while a history/resume
    // decrypt pass is running":
    //  1. decrypt loads the session and is HELD at its storeSession;
    //  2. an encrypt starts. Unserialized (the bug), it loads the same
    //     pre-decrypt record, emits counter k, stores k+1;
    //  3. the held decrypt store is released and writes its record — whose
    //     sender chain is still k — over the encrypt's k+1 (lost update);
    //  4. the next encrypt re-emits counter k → receiver already consumed it
    //     → DuplicateMessageException → permanent "[Decryption failed]".
    // With encrypt+decrypt on ONE per-peer lock, step 2 cannot start until
    // the decrypt (including its store) finishes, so the rollback is
    // impossible.
    final storeAttempted = gate.armOneShotHold();
    final decryptF = alice.decrypt(bobId, inbound);
    unawaited(decryptF); // held at storeSession below (pre-fix)

    // Post-fix the decrypt may be gated behind nothing (it acquires first);
    // its store attempt always arrives — await it before starting encrypt.
    await storeAttempted;

    final encryptF = alice.encrypt(bobId, 'reply #0');
    // Give the (buggy, unserialized) encrypt every chance to run to
    // completion while the decrypt store is held.
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    gate.release();

    expect(await decryptF, 'inbound during overlap');
    final wire0 = await encryptF;
    final wire1 = await alice.encrypt(bobId, 'reply #1');

    expect(await bob.decrypt(aliceId, wire0), 'reply #0');
    // Pre-fix this throws DuplicateMessageException: wire1 reuses wire0's
    // chain counter because the released decrypt store rolled the sender
    // chain back.
    expect(await bob.decrypt(aliceId, wire1), 'reply #1');
  });

  test(
    'GATED two app engines sharing one account cannot roll back the ratchet',
    () async {
      await settleHandshake();

      // A second PWA tab/engine has a separate in-memory _sessionTails queue but
      // reads and writes the same persisted identity/session records.
      final aliceTwin = EncryptionService(
        sessionCrossContextLock: crossContextLock.run,
      );
      await aliceTwin.initialize(aliceId, checkServerBundleExists: () async => false);

      final gate = _GatedSessionStore.install(alice);
      final inbound = await bob.encrypt(
        aliceId,
        'inbound during two-engine race',
      );

      final storeAttempted = gate.armOneShotHold();
      final decryptF = alice.decrypt(bobId, inbound);
      unawaited(decryptF);
      await storeAttempted;

      // The twin has a separate in-memory queue. Only the shared cross-context
      // backend can keep it from loading the pre-decrypt record while alice's
      // updated store is held.
      var twinCompleted = false;
      final wire0F = aliceTwin
          .encrypt(bobId, 'two-engine reply #0')
          .whenComplete(() => twinCompleted = true);
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(
        twinCompleted,
        isFalse,
        reason: 'the second engine must wait on the shared account/peer lock',
      );

      gate.release();
      expect(await decryptF, 'inbound during two-engine race');
      final wire0 = await wire0F;

      // Alice's held store lands last and can roll the shared sender chain back.
      // If coordination is only process-local, this emits wire0's counter again.
      final wire1 = await aliceTwin.encrypt(bobId, 'two-engine reply #1');
      expect(await bob.decrypt(aliceId, wire0), 'two-engine reply #0');
      expect(await bob.decrypt(aliceId, wire1), 'two-engine reply #1');
      expect(
        crossContextLock.acquisitions['fireplace-e2e-session-1-2'],
        greaterThanOrEqualTo(1),
        reason: 'the test must exercise the injected cross-context backend',
      );
    },
  );

  test(
    'a second app engine replays the same message plaintext without consuming '
    'the Signal key twice',
    () async {
      await settleHandshake();
      final aliceTwin = EncryptionService(
        sessionCrossContextLock: crossContextLock.run,
      );
      await aliceTwin.initialize(aliceId, checkServerBundleExists: () async => false);

      final wire = await bob.encrypt(aliceId, 'one socket event, two engines');
      expect(
        await alice.decrypt(bobId, wire, messageId: 7001),
        'one socket event, two engines',
      );
      await alice.saveDecryptedContent(7001, {
        'content': 'one socket event, two engines',
        'messageType': 'TEXT',
      });
      expect(
        await aliceTwin.decrypt(bobId, wire, messageId: 7001),
        'one socket event, two engines',
        reason: 'the second engine must use the durable raw replay',
      );

      final editedWire = await bob.encrypt(aliceId, 'same id, new ciphertext');
      expect(
        await aliceTwin.decrypt(bobId, editedWire, messageId: 7001),
        'same id, new ciphertext',
        reason: 'replay is bound to exact ciphertext, not message id alone',
      );

      await alice.clearDecryptedContentCache();
      final aliceThird = EncryptionService(
        sessionCrossContextLock: crossContextLock.run,
      );
      await aliceThird.initialize(aliceId, checkServerBundleExists: () async => false);
      await expectLater(
        aliceThird.decrypt(bobId, editedWire, messageId: 7001),
        throwsA(isA<DuplicateMessageException>()),
        reason: 'a privacy cache clear must remove raw replay plaintext',
      );
    },
  );

  test('raw plaintext replay cache retains at most 40 messages', () async {
    await settleHandshake();
    final wires = <String>[];

    for (var i = 0; i <= 40; i++) {
      final plaintext = 'bounded replay $i';
      final wire = await bob.encrypt(aliceId, plaintext);
      wires.add(wire);
      expect(await alice.decrypt(bobId, wire, messageId: 8000 + i), plaintext);
    }

    final aliceTwin = EncryptionService(
      sessionCrossContextLock: crossContextLock.run,
    );
    await aliceTwin.initialize(aliceId, checkServerBundleExists: () async => false);
    await expectLater(
      aliceTwin.decrypt(bobId, wires.first, messageId: 8000),
      throwsA(isA<DuplicateMessageException>()),
      reason: 'the 41st raw replay must evict the oldest plaintext',
    );
    expect(
      await aliceTwin.decrypt(bobId, wires.last, messageId: 8040),
      'bounded replay 40',
      reason: 'the newest replay must remain available',
    );
  });
}

class _InMemoryCrossContextLock {
  final Map<String, Future<void>> _tails = {};
  final Map<String, int> acquisitions = {};

  Future<T> run<T>(String name, Future<T> Function() action) {
    final tail = _tails[name] ?? Future<void>.value();
    final result = tail.then((_) {
      acquisitions.update(name, (count) => count + 1, ifAbsent: () => 1);
      return action();
    });
    _tails[name] = result.then<void>((_) {}, onError: (_) {});
    return result;
  }
}

/// SessionStore wrapper with a one-shot hold on [storeSession] — lets the
/// probe freeze one path mid load→mutate→store while the other runs.
class _GatedSessionStore extends SessionStore {
  _GatedSessionStore(this._inner);

  static _GatedSessionStore install(EncryptionService service) {
    late _GatedSessionStore gate;
    service.debugWrapSessionStore((inner) {
      gate = _GatedSessionStore(inner);
      return gate;
    });
    return gate;
  }

  final SessionStore _inner;
  Completer<void>? _held;
  Completer<void>? _attempted;

  /// Arm: the NEXT storeSession call completes the returned future, then
  /// waits until [release]. Subsequent stores pass through untouched.
  Future<void> armOneShotHold() {
    _held = Completer<void>();
    _attempted = Completer<void>();
    return _attempted!.future;
  }

  void release() {
    final held = _held;
    _held = null;
    if (held != null && !held.isCompleted) held.complete();
  }

  @override
  Future<void> storeSession(
    SignalProtocolAddress address,
    SessionRecord record,
  ) async {
    final attempted = _attempted;
    final held = _held;
    if (attempted != null && !attempted.isCompleted && held != null) {
      attempted.complete();
      await held.future;
    }
    await _inner.storeSession(address, record);
  }

  @override
  Future<SessionRecord> loadSession(SignalProtocolAddress address) =>
      _inner.loadSession(address);

  @override
  Future<List<int>> getSubDeviceSessions(String name) =>
      _inner.getSubDeviceSessions(name);

  @override
  Future<bool> containsSession(SignalProtocolAddress address) =>
      _inner.containsSession(address);

  @override
  Future<void> deleteSession(SignalProtocolAddress address) =>
      _inner.deleteSession(address);

  @override
  Future<void> deleteAllSessions(String name) => _inner.deleteAllSessions(name);
}
