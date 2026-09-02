import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/services/encryption_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Race probe for the "10 rapid sends → some [Decryption failed]" field report
/// (2026-07-07, anti-quantum note burst): [EncryptionService.encrypt] has no
/// per-recipient serialization, so concurrent encrypts can interleave at store
/// await points, load the same ratchet state, and emit duplicate chain
/// counters — the receiver then fails on the duplicates.
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
    await alice.initialize(aliceId, checkServerBundleExists: () async => false);
    await bob.initialize(bobId, checkServerBundleExists: () async => false);
  });

  test('10 CONCURRENT encrypts to one recipient all decrypt (send-race probe)',
      () async {
    await alice.buildSession(bobId, flatBundleFrom(bob), expectedIdentityBase64: null);

    // Settle the handshake so all burst messages ride the established ratchet.
    expect(await bob.decrypt(aliceId, await alice.encrypt(bobId, 'opener')),
        'opener');
    expect(await alice.decrypt(bobId, await bob.encrypt(aliceId, 'ack')),
        'ack');

    // The burst: fired without awaiting between them — exactly what ten rapid
    // sendAntiQuantumNote -> sendMessage -> _encryptAndSend calls do.
    final plaintexts =
        List.generate(10, (i) => 'burst note #$i with unique payload');
    final wires =
        await Future.wait(plaintexts.map((p) => alice.encrypt(bobId, p)));

    // Duplicate ciphertexts would prove two encrypts consumed the same
    // ratchet step.
    expect(wires.toSet().length, wires.length,
        reason: 'concurrent encrypts must never produce identical ciphertext');

    // Receiver decrypts in emit order (serialized, as the app does).
    final failures = <String>[];
    for (var i = 0; i < wires.length; i++) {
      try {
        final out = await bob.decrypt(aliceId, wires[i]);
        if (out != plaintexts[i]) {
          failures.add('#$i: WRONG PLAINTEXT (got "$out")');
        }
      } catch (e) {
        failures.add('#$i: ${e.runtimeType}: $e');
      }
    }
    expect(failures, isEmpty,
        reason: 'every burst message must decrypt; failures: $failures');
  });

  test('control: 10 SEQUENTIAL encrypts all decrypt', () async {
    await alice.buildSession(bobId, flatBundleFrom(bob), expectedIdentityBase64: null);
    expect(await bob.decrypt(aliceId, await alice.encrypt(bobId, 'opener')),
        'opener');
    expect(await alice.decrypt(bobId, await bob.encrypt(aliceId, 'ack')),
        'ack');

    for (var i = 0; i < 10; i++) {
      final p = 'sequential note #$i';
      expect(await bob.decrypt(aliceId, await alice.encrypt(bobId, p)), p);
    }
  });
}
