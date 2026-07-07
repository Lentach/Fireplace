import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/services/encryption_service.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cross-race probe for the ongoing "[Decryption failed]" field reports
/// (2026-07-07): the 0.0.90 fix serialized encrypt-vs-encrypt per recipient,
/// but encrypt and decrypt still run under TWO SEPARATE locks
/// (EncryptionService._encryptTails vs MessagingProvider._decryptChainBySender)
/// while both do load→mutate→store on the SAME Signal SessionRecord.
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
    alice = EncryptionService();
    bob = EncryptionService();
    await alice.initialize(aliceId);
    await bob.initialize(bobId);
  });

  Future<void> settleHandshake() async {
    await alice.buildSession(bobId, flatBundleFrom(bob));
    expect(await bob.decrypt(aliceId, await alice.encrypt(bobId, 'opener')),
        'opener');
    expect(await alice.decrypt(bobId, await bob.encrypt(aliceId, 'ack')),
        'ack');
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
    //  - encrypt loop: sequential per recipient (what the 0.0.90 queue does)
    // Nothing serializes the two AGAINST EACH OTHER — the bug under probe.
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
    expect(decryptFailures, isEmpty,
        reason: 'inbound decrypts failed during overlap: $decryptFailures');
    expect(decrypted, inboundPlain);

    // Duplicate ciphertexts would prove two encrypts consumed the same
    // ratchet step (sender-chain rollback via lost update).
    expect(outboundWires.toSet().length, outboundWires.length,
        reason: 'encrypts overlapping decrypts produced identical ciphertext');

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
    expect(replyFailures, isEmpty,
        reason:
            'replies sent during an inbound decrypt pass must all decrypt; '
            'failures: $replyFailures');
  });

  test('control: alternating sequential decrypt/encrypt stays intact',
      () async {
    await settleHandshake();

    for (var i = 0; i < 10; i++) {
      final inbound = await bob.encrypt(aliceId, 'inbound #$i');
      expect(await alice.decrypt(bobId, inbound), 'inbound #$i');
      final reply = await alice.encrypt(bobId, 'reply #$i');
      expect(await bob.decrypt(aliceId, reply), 'reply #$i');
    }
  });

  test(
      'GATED lost update: decrypt store landing after a concurrent encrypt '
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
      SignalProtocolAddress address, SessionRecord record) async {
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
  Future<void> deleteAllSessions(String name) =>
      _inner.deleteAllSessions(name);
}
