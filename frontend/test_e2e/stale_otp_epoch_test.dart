// Full-stack regression for the 2026-07-11 stale-OTP bad-MAC outage, over the
// REAL wire (REST auth -> Socket.IO -> ChatGateway -> Postgres) with REAL
// libsignal on both ends.
//
//   docker-compose up                     # repo root: backend :3000 + Postgres
//   cd frontend && flutter test test_e2e/stale_otp_epoch_test.dart
//
// What it pins that the happy-path harness does NOT: a recipient who REGENERATES
// their Signal identity mid-life, re-uploading bundle + one-time pre-keys in the
// UNSAFE production order (OTPs racing the bundle, no client-side serialization),
// must never have a stale (old-epoch) OTP served again. Concretely:
//   * the sender always fetches the CURRENT identity epoch;
//   * every served OTP belongs to the current epoch and DECRYPTS (a stale one
//     would Bad-Mac exactly like the field logs — peers 37<->63);
//   * the current-epoch pool is non-empty after the unsafe re-upload (tagging +
//     purge kept the new keys and dropped the dead ones);
//   * both directions work.
//
// Scope of this test (precise): it pins the end-to-end PURGE + identity-TAGGING
// path — after regeneration the epoch-2 OTPs reuse keyId slots 0..N (UPSERT
// overwrites epoch-1) and upsertKeyBundle purges the rest, so no stale row
// physically survives here. It does NOT by itself isolate the fetch filter
// (a filter-less server would still serve only epoch-2 in this scenario).
// The identity fetch filter is pinned FAIL-CLOSED by the backend unit spec
// (key-bundles.service.spec.ts) — it asserts fetchPreKeyBundle's SQL carries
// `"identityPublicKey" = $2` with params [userId, bundle.identityPublicKey],
// so removing the filter reddens CI. Together: filter (unit spec) + purge +
// tagging (this test) are each guarded.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/e2e_test_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  enableRealNetwork();

  final baseUrl = e2eBaseUrl();
  final runTag = DateTime.now().millisecondsSinceEpoch.toString();

  late E2eClient alice; // recipient who regenerates identity
  late E2eClient bob; // sender
  late int conversationId;
  late String epoch1Identity;

  int wireType(String ciphertext) =>
      int.parse(ciphertext.substring(0, ciphertext.indexOf(':')));

  /// Re-upload alice's CURRENT (post-regeneration) keys in the UNSAFE production
  /// order: emit the one-time pre-keys (identity-tagged, like the real client)
  /// and the key bundle back-to-back with NO await between them, then wait for
  /// both server acks. Mirrors EncryptionProvider's two consecutive emits.
  Future<void> reuploadUnsafeConcurrent(E2eClient c) async {
    final keys = c.encryption.getKeysForUpload()!;
    final keyBundle = (keys['keyBundle'] as Map).cast<String, dynamic>();
    final otps = (keys['oneTimePreKeys'] as List).cast<Map<String, dynamic>>();
    final identity = keyBundle['identityPublicKey'];

    // OTPs FIRST (the risky order: they can land before the bundle upsert), with
    // the explicit identity epoch tag the new client sends.
    c.socketService.socket!.emit('uploadOneTimePreKeys', {
      'keys': otps,
      'identityPublicKey': identity,
    });
    c.socketService.socket!.emit('uploadKeyBundle', keyBundle);

    await c.events.next('oneTimePreKeysUploaded',
        reason: '${c.label} epoch-2 OTP ack');
    await c.events.next('keyBundleUploaded',
        reason: '${c.label} epoch-2 bundle ack');
  }

  setUpAll(() async {
    await requireBackendUp(baseUrl);
    // ignore: invalid_use_of_visible_for_testing_member
    FlutterSecureStorage.setMockInitialValues({});
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});

    alice = E2eClient('salice', baseUrl);
    bob = E2eClient('sbob', baseUrl);

    await alice.registerFresh();
    await bob.registerFresh();
    await alice.connectSocket();
    await bob.connectSocket();

    // Epoch 1: alice + bob upload their original identities and OTP pools.
    await alice.initializeAndUploadKeys();
    await bob.initializeAndUploadKeys();
    epoch1Identity =
        (alice.encryption.getKeysForUpload()!['keyBundle'] as Map)['identityPublicKey']
            as String;

    // Friendship + conversation.
    alice.socketService.sendFriendRequest(bob.userId);
    final request = await bob.events.next(
      'newFriendRequest',
      where: (p) =>
          p is Map &&
          p['sender'] is Map &&
          (p['sender'] as Map)['id'] == alice.userId,
      reason: 'bob receiving alice friend request',
    ) as Map;
    bob.events.discard('friendRequestAccepted');
    alice.events.discard('friendRequestAccepted');
    bob.events.discard('openConversation');
    alice.events.discard('openConversation');
    bob.socketService.acceptFriendRequest(request['id'] as int);
    final aliceAccepted =
        await alice.events.next('friendRequestAccepted', reason: 'alice accept')
            as Map;
    final bobAccepted =
        await bob.events.next('friendRequestAccepted', reason: 'bob accept')
            as Map;
    expect(aliceAccepted['conversationId'], isA<int>());
    expect(bobAccepted['conversationId'], isA<int>());
    expect(aliceAccepted['chatReady'], isTrue);
    expect(bobAccepted['chatReady'], isTrue);
    final aliceConversationId = aliceAccepted['conversationId'] as int;
    final bobConversationId = bobAccepted['conversationId'] as int;
    expect(bobConversationId, aliceConversationId);

    await bob.events.none(
      'openConversation',
      within: const Duration(seconds: 3),
      reason: 'accepting an invitation must not auto-open chat',
    );
    alice.events.discard('openConversation');
    alice.socketService.startConversation(bob.userId);
    final aliceOpen = await alice.events
        .next('openConversation', reason: 'alice startConversation') as Map;
    conversationId = bobConversationId;
    expect(aliceOpen['conversationId'], conversationId);
  });

  tearDownAll(() {
    alice.dispose();
    bob.dispose();
  });

  /// bob builds a fresh session from alice's CURRENT server bundle and sends a
  /// PreKey message; alice must decrypt it to the exact plaintext. Returns the
  /// served bundle so the caller can assert epoch identity/OTP presence.
  Future<Map<String, dynamic>> bobPreKeyToAlice(String content, String tempId) async {
    await bob.encryption.deleteSession(alice.userId); // force a fresh X3DH
    final bundle = await bob.fetchBundleFor(alice.userId);
    await bob.encryption.buildSession(alice.userId, bundle);
    final ct = await bob.encryptText(alice.userId, content);
    expect(wireType(ct), 3, reason: 'fresh session opener must be a PreKey (3:)');
    await bob.sendEncrypted(alice.userId, ct, tempId: tempId);
    final recv = await alice.awaitNewMessage(tempId);
    // The load-bearing assertion: a stale OTP would throw Bad Mac here.
    expect(await alice.decryptText(bob.userId, recv['encryptedContent'] as String),
        content,
        reason: 'alice must decrypt bob\'s PreKey message (no stale OTP served)');
    return bundle;
  }

  group('stale-OTP epoch regression', () {
    test(
      'after alice regenerates identity, no stale OTP is ever served and both '
      'directions decrypt (unsafe production upload order)',
      () async {
        // 1. alice regenerates identity (fresh install / key loss), SAME account.
        //    She now holds only epoch-2 private keys; epoch-1 OTP privates gone.
        await alice.encryption.clearAllKeys();
        await alice.encryption.initialize(alice.userId, checkServerBundleExists: () async => false);
        final epoch2Identity =
            (alice.encryption.getKeysForUpload()!['keyBundle'] as Map)['identityPublicKey']
                as String;
        expect(epoch2Identity, isNot(epoch1Identity),
            reason: 'regeneration must mint a new identity epoch');

        // 2. Re-upload in the unsafe production order (OTPs racing the bundle).
        await reuploadUnsafeConcurrent(alice);

        // 3. bob -> alice PreKey, repeated to drain several current-epoch OTPs.
        //    Every claim must be epoch-2 and must decrypt.
        for (var i = 0; i < 3; i++) {
          final bundle =
              await bobPreKeyToAlice('epoch2-msg-$i-$runTag', 's-b2a-$i-$runTag');
          expect(bundle['identityPublicKey'], epoch2Identity,
              reason: 'served bundle must carry the CURRENT identity epoch');
          expect(bundle['identityPublicKey'], isNot(epoch1Identity));
          // Non-empty current-epoch pool proves tagging + purge kept the new keys.
          expect(bundle['oneTimePreKeyId'], isNotNull,
              reason: 'current-epoch OTP pool must be non-empty after re-upload');
        }

        // 4. Reverse direction: alice -> bob (bob never rotated) must also work.
        await bob.encryption.deleteSession(alice.userId);
        final bobBundle = await alice.fetchBundleFor(bob.userId);
        await alice.encryption.buildSession(bob.userId, bobBundle);
        final ct = await alice.encryptText(bob.userId, 'reverse-$runTag');
        expect(wireType(ct), 3);
        await alice.sendEncrypted(bob.userId, ct, tempId: 's-a2b-$runTag');
        final recv = await bob.awaitNewMessage('s-a2b-$runTag');
        expect(
            await bob.decryptText(alice.userId, recv['encryptedContent'] as String),
            'reverse-$runTag');
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
