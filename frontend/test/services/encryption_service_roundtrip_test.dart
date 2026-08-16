import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/services/encryption_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Clean two-party E2E round trip where BOTH sides run the app's real
/// [EncryptionService] (real libsignal X3DH + Double Ratchet, no crypto
/// mocking). Storage keys are per-user prefixed (`e2e_${userId}_`), so two
/// service instances with different userIds coexist in one mock store.
///
/// Wire format contract (shared with backend, see root CLAUDE.md §7):
/// ciphertext is `"{type}:{base64}"` — `3` = PreKeySignalMessage (X3DH
/// handshake carrier), `2` = SignalMessage (whisper, established ratchet).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const aliceId = 1;
  const bobId = 2;

  late EncryptionService alice;
  late EncryptionService bob;

  /// Asserts the `"{type}:{base64}"` wire format and returns the type.
  int wireType(String ciphertext) {
    expect(
      ciphertext,
      matches(RegExp(r'^\d+:[A-Za-z0-9+/]+=*$')),
      reason: 'ciphertext must be "{type}:{base64}"',
    );
    return int.parse(ciphertext.substring(0, ciphertext.indexOf(':')));
  }

  /// Assembles the FLAT map [EncryptionService.buildSession] expects from
  /// the nested `getKeysForUpload()` shape (keyBundle + one one-time pre-key),
  /// exactly like the server serves `fetchPreKeyBundle`.
  Map<String, dynamic> flatBundleFrom(EncryptionService peer) {
    final upload = peer.getKeysForUpload();
    expect(upload, isNotNull,
        reason: 'fresh install must produce keys for upload');
    final keyBundle = (upload!['keyBundle'] as Map).cast<String, dynamic>();
    final otps =
        (upload['oneTimePreKeys'] as List).cast<Map<String, dynamic>>();
    expect(otps, isNotEmpty);
    final otp = otps.first;
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

  group('EncryptionService two-party round trip', () {
    test('A builds session from B\'s bundle; first message is a PreKey (3:) '
        'and B decrypts it to the exact plaintext', () async {
      await alice.buildSession(bobId, flatBundleFrom(bob));

      const plaintext = 'hello Bob, this is the X3DH opener';
      final wire = await alice.encrypt(bobId, plaintext);
      expect(wireType(wire), 3,
          reason: 'first message after buildSession must be a PreKey message');

      expect(await bob.decrypt(aliceId, wire), plaintext);
    });

    test('B replies over the established session and messages settle to '
        'whisper (2:) once both directions have flowed', () async {
      await alice.buildSession(bobId, flatBundleFrom(bob));

      // A -> B: X3DH handshake carrier.
      final opener = await alice.encrypt(bobId, 'opener');
      expect(wireType(opener), 3);
      expect(await bob.decrypt(aliceId, opener), 'opener');

      // B -> A: the responder never sends PreKey messages — its session is
      // born from the inbound PreKey message, so the reply is a whisper.
      const reply = 'hi Alice, session established';
      final replyWire = await bob.encrypt(aliceId, reply);
      expect(wireType(replyWire), 2,
          reason: 'responder side sends whisper messages from the start');
      expect(await alice.decrypt(bobId, replyWire), reply);

      // A -> B again: A has now processed B's whisper, so the handshake is
      // acknowledged and A's pending pre-key state is cleared — later
      // messages settle to type 2.
      const followUp = 'ack received, switching to whisper';
      final followUpWire = await alice.encrypt(bobId, followUp);
      expect(wireType(followUpWire), 2,
          reason: 'after the round trip completes, A must send whisper too');
      expect(await bob.decrypt(aliceId, followUpWire), followUp);
    });

    test('multiple sequential messages in both directions decrypt correctly '
        '(ratchet advances)', () async {
      await alice.buildSession(bobId, flatBundleFrom(bob));

      // Complete the handshake first.
      expect(await bob.decrypt(aliceId, await alice.encrypt(bobId, 'ping')),
          'ping');
      expect(await alice.decrypt(bobId, await bob.encrypt(aliceId, 'pong')),
          'pong');

      // Alternating volleys — each turn advances the DH ratchet.
      for (var i = 0; i < 5; i++) {
        final aMsg = 'alice volley #$i';
        final aWire = await alice.encrypt(bobId, aMsg);
        expect(wireType(aWire), 2);
        expect(await bob.decrypt(aliceId, aWire), aMsg);

        final bMsg = 'bob volley #$i';
        final bWire = await bob.encrypt(aliceId, bMsg);
        expect(wireType(bWire), 2);
        expect(await alice.decrypt(bobId, bWire), bMsg);
      }

      // Consecutive same-direction messages advance the symmetric chain:
      // identical plaintext must never produce identical ciphertext.
      const repeated = 'same words, new ratchet step';
      final first = await alice.encrypt(bobId, repeated);
      final second = await alice.encrypt(bobId, repeated);
      expect(first, isNot(second),
          reason: 'ratchet must yield fresh message keys per encrypt');
      expect(await bob.decrypt(aliceId, first), repeated);
      expect(await bob.decrypt(aliceId, second), repeated);
    });

    test('non-ASCII and emoji plaintext survives the round trip (utf8)',
        () async {
      await alice.buildSession(bobId, flatBundleFrom(bob));

      const samples = <String>[
        'Zażółć gęślą jaźń — ЁЖИК — 你好世界',
        '🔥🛋️ fireplace 🧑‍🚒 family: 👨‍👩‍👧‍👦',
        'mixed: café ☕ + naïve 12°C → ∑(π) ≠ ∅',
      ];

      // A -> B opener plus follow-ups.
      var firstFromAlice = true;
      for (final sample in samples) {
        final wire = await alice.encrypt(bobId, sample);
        expect(wireType(wire), firstFromAlice ? 3 : anyOf(2, 3));
        firstFromAlice = false;
        expect(await bob.decrypt(aliceId, wire), sample);
      }

      // B -> A the same payloads back over the established session.
      for (final sample in samples) {
        final wire = await bob.encrypt(aliceId, sample);
        expect(wireType(wire), 2);
        expect(await alice.decrypt(bobId, wire), sample);
      }
    });
  });
}
