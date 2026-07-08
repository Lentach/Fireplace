// Full-stack two-account E2E Signal wire harness.
//
// NOT part of the default `flutter test` suite — this directory is a sibling
// of `test/` precisely so `flutter test` (local + CI) never picks it up.
//
// Invocation contract:
//
//   docker-compose up                     # repo root: backend :3000 + Postgres
//   cd frontend && flutter test test_e2e
//
// What it proves, over the REAL wire (REST auth -> Socket.IO -> ChatGateway ->
// DTO validation -> Postgres -> broadcast) with REAL libsignal on both ends:
//   1. register -> socketReady -> WS key upload for two fresh accounts
//   2. friend request/accept -> conversation open
//   3. first message is PreKey (3:), server stores only '[encrypted]',
//      recipient decrypts the exact plaintext
//   4. replies ratchet to whisper (2:) in both directions, in order
//   5. mid-conversation session rebuild (deleteSession -> fetch bundle ->
//      PreKey again) — the shape of the 2026-07 field incidents
//   6. editMessage swaps ciphertext (messageEdited both sides, re-decrypt);
//      non-sender edit rejected with not_sender
//   7. reactions round-trip (reactionUpdated both sides)
//
// Fresh accounts EVERY run, by design: the server never purges unused
// one-time pre-keys and serves them oldest-first, so reusing accounts with
// fresh client keys would deterministically produce phantom bad-MAC failures.
// Register throttle is 10/hr per IP; `docker compose restart backend` resets
// the in-memory counters when iterating.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/e2e_test_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Must come AFTER binding init: the binding's HttpOverrides answers every
  // real request with 400, which would silently break REST and the WS upgrade.
  enableRealNetwork();

  final baseUrl = e2eBaseUrl();
  final runTag = DateTime.now().millisecondsSinceEpoch.toString();

  late E2eClient alice;
  late E2eClient bob;
  late int conversationId;

  /// Asserts the `"{type}:{base64}"` wire format and returns the type
  /// (3 = PreKeySignalMessage, 2 = SignalMessage/whisper).
  int wireType(String ciphertext) {
    expect(
      ciphertext,
      matches(RegExp(r'^\d+:[A-Za-z0-9+/]+=*$')),
      reason: 'ciphertext must be "{type}:{base64}"',
    );
    return int.parse(ciphertext.substring(0, ciphertext.indexOf(':')));
  }

  /// Sends [content] from [sender] to [recipient] and asserts the full wire
  /// round trip: messageSent shape on the sender, newMessage on the
  /// recipient, exact plaintext after decrypt. Returns the server message id.
  Future<int> roundTrip(
    E2eClient sender,
    E2eClient recipient,
    String content, {
    required String tempId,
    required int expectedWireType,
  }) async {
    final ciphertext = await sender.encryptText(recipient.userId, content);
    expect(wireType(ciphertext), expectedWireType,
        reason: 'unexpected ciphertext type for tempId=$tempId');

    final sent = await sender.sendEncrypted(recipient.userId, ciphertext,
        tempId: tempId);
    expect(sent['content'], '[encrypted]',
        reason: 'server must never store plaintext');
    expect(sent['encryptedContent'], ciphertext);
    expect(sent['senderId'], sender.userId);
    expect(sent['conversationId'], conversationId);
    expect(sent['deliveryStatus'], 'SENT');
    expect(sent['messageType'], 'TEXT');
    expect(sent['editedAt'], isNull);
    final messageId = sent['id'] as int;
    expect(messageId, greaterThan(0));

    final received = await recipient.awaitNewMessage(tempId);
    expect(received['id'], messageId);
    expect(received['content'], '[encrypted]');
    expect(received['encryptedContent'], ciphertext);

    final plaintext = await recipient.decryptText(
        sender.userId, received['encryptedContent'] as String);
    expect(plaintext, content);
    return messageId;
  }

  setUpAll(() async {
    await requireBackendUp(baseUrl);

    // In-memory Signal key storage, same pattern as the in-process roundtrip
    // test. Both clients share one mock store via per-user key prefixes.
    // The analyzer only recognizes @visibleForTesting use under `test/`;
    // this IS a test, deliberately outside the default suite dir.
    // ignore: invalid_use_of_visible_for_testing_member
    FlutterSecureStorage.setMockInitialValues({});
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});

    alice = E2eClient('alice', baseUrl);
    bob = E2eClient('bob', baseUrl);

    // 1. Fresh accounts + tokens (REST).
    await alice.registerFresh();
    await bob.registerFresh();

    // 2. Real sockets, authenticated via handshake auth token.
    await alice.connectSocket();
    await bob.connectSocket();

    // 3. Signal identity + key bundle upload (WS, like EncryptionProvider).
    await alice.initializeAndUploadKeys();
    await bob.initializeAndUploadKeys();

    // 4. Friendship: request over WS, accept on the receiving side.
    alice.socketService.sendFriendRequest(bob.userId);
    final request = await bob.events.next(
      'newFriendRequest',
      where: (p) =>
          p is Map &&
          p['sender'] is Map &&
          (p['sender'] as Map)['id'] == alice.userId,
      reason: 'bob receiving alice friend request',
    ) as Map;
    bob.socketService.acceptFriendRequest(request['id'] as int);
    await alice.events.next('friendRequestAccepted',
        reason: 'alice accept confirmation');
    await bob.events.next('friendRequestAccepted',
        reason: 'bob accept confirmation');

    // 5. Conversation. The acceptor (bob) is auto-opened; alice starts
    //    explicitly. Both must land on the same conversation row.
    final bobOpen = await bob.events.next('openConversation',
        reason: 'acceptor auto-open') as Map;
    alice.socketService.startConversation(bob.userId);
    final aliceOpen = await alice.events.next('openConversation',
        reason: 'alice startConversation') as Map;
    conversationId = aliceOpen['conversationId'] as int;
    expect(bobOpen['conversationId'], conversationId,
        reason: 'accept-flow and startConversation must share one conversation');
  });

  tearDownAll(() {
    alice.dispose();
    bob.dispose();
  });

  group('full-stack E2E wire', () {
    test(
      'first message travels as PreKey (3:), server blind, peer decrypts',
      () async {
        final bundle = await alice.fetchBundleFor(bob.userId);
        expect(bundle['identityPublicKey'], isA<String>());
        expect(bundle['oneTimePreKeyId'], isNotNull,
            reason: 'fresh account must have unused one-time pre-keys');
        await alice.encryption.buildSession(bob.userId, bundle);

        await roundTrip(alice, bob, 'first-contact-$runTag',
            tempId: 't1-$runTag', expectedWireType: 3);
      },
      timeout: const Timeout(Duration(minutes: 1)),
    );

    test(
      'replies ratchet to whisper (2:) in both directions, in order',
      () async {
        await roundTrip(bob, alice, 'reply-1-$runTag',
            tempId: 't2-$runTag', expectedWireType: 2);
        await roundTrip(alice, bob, 'msg-2-$runTag',
            tempId: 't3-$runTag', expectedWireType: 2);
        await roundTrip(bob, alice, 'reply-2-$runTag',
            tempId: 't4-$runTag', expectedWireType: 2);

        // Same plaintext twice must produce different ciphertexts (ratchet
        // advanced), and both must decrypt.
        final ct1 = await alice.encryptText(bob.userId, 'twin-$runTag');
        final ct2 = await alice.encryptText(bob.userId, 'twin-$runTag');
        expect(ct1, isNot(ct2), reason: 'ratchet must advance per message');
        await alice.sendEncrypted(bob.userId, ct1, tempId: 't5-$runTag');
        await alice.sendEncrypted(bob.userId, ct2, tempId: 't6-$runTag');
        final r1 = await bob.awaitNewMessage('t5-$runTag');
        final r2 = await bob.awaitNewMessage('t6-$runTag');
        expect(
            await bob.decryptText(
                alice.userId, r1['encryptedContent'] as String),
            'twin-$runTag');
        expect(
            await bob.decryptText(
                alice.userId, r2['encryptedContent'] as String),
            'twin-$runTag');
      },
      timeout: const Timeout(Duration(minutes: 1)),
    );

    test(
      'mid-conversation session rebuild goes PreKey (3:) and peer recovers',
      () async {
        // The 2026-07 field-incident shape: sender loses/rebuilds its session
        // mid-conversation; next message is a type-3 that the receiver must
        // process over its existing session state.
        await alice.encryption.deleteSession(bob.userId);
        final bundle = await alice.fetchBundleFor(bob.userId);
        await alice.encryption.buildSession(bob.userId, bundle);

        await roundTrip(alice, bob, 'post-rebuild-$runTag',
            tempId: 't7-$runTag', expectedWireType: 3);

        // Bidirectional sanity after the rebuild.
        await roundTrip(bob, alice, 'post-rebuild-reply-$runTag',
            tempId: 't8-$runTag', expectedWireType: 2);
      },
      timeout: const Timeout(Duration(minutes: 1)),
    );

    test(
      'edit swaps ciphertext; both sides get messageEdited; peer re-decrypts',
      () async {
        final messageId = await roundTrip(alice, bob, 'original-$runTag',
            tempId: 't9-$runTag', expectedWireType: 2);

        final editedPlaintext = 'edited-$runTag';
        final newCiphertext =
            await alice.encryptText(bob.userId, editedPlaintext);
        expect(wireType(newCiphertext), 2,
            reason: 'edit rides the existing session');
        alice.emitEditMessage(messageId, newCiphertext);

        for (final client in [alice, bob]) {
          final edited = await client.events.next(
            'messageEdited',
            where: (p) => p is Map && p['messageId'] == messageId,
            reason: '${client.label} messageEdited',
          ) as Map;
          expect(edited['conversationId'], conversationId);
          expect(edited['content'], '[encrypted]');
          expect(edited['encryptedContent'], newCiphertext);
          expect(DateTime.tryParse(edited['editedAt'] as String), isNotNull,
              reason: 'editedAt must be an ISO timestamp');
        }

        expect(await bob.decryptText(alice.userId, newCiphertext),
            editedPlaintext);
      },
      timeout: const Timeout(Duration(minutes: 1)),
    );

    test(
      'edit by non-sender is rejected with not_sender',
      () async {
        final messageId = await roundTrip(alice, bob, 'no-touching-$runTag',
            tempId: 't10-$runTag', expectedWireType: 2);

        // Rejected before any store/decrypt, so a placeholder string is fine
        // (and never advances either ratchet).
        bob.emitEditMessage(messageId, 'rejected-probe-$runTag');
        final failed = await bob.events.next(
          'editMessageFailed',
          where: (p) => p is Map && p['messageId'] == messageId,
          reason: 'bob edit rejection',
        ) as Map;
        expect(failed['reason'], 'not_sender');
      },
      timeout: const Timeout(Duration(minutes: 1)),
    );

    test(
      'reactions round-trip to both sides and clear on removal',
      () async {
        final messageId = await roundTrip(alice, bob, 'react-target-$runTag',
            tempId: 't11-$runTag', expectedWireType: 2);

        bob.socketService.emitAddReaction(messageId, '🔥');
        for (final client in [alice, bob]) {
          final updated = await client.events.next(
            'reactionUpdated',
            where: (p) => p is Map && p['messageId'] == messageId,
            reason: '${client.label} reaction add',
          ) as Map;
          expect(updated['conversationId'], conversationId);
          expect((updated['reactions'] as Map)['🔥'], [bob.userId]);
        }

        bob.socketService.emitRemoveReaction(messageId, '🔥');
        for (final client in [alice, bob]) {
          final updated = await client.events.next(
            'reactionUpdated',
            where: (p) => p is Map && p['messageId'] == messageId,
            reason: '${client.label} reaction remove',
          ) as Map;
          expect(updated['reactions'], isEmpty);
        }
      },
      timeout: const Timeout(Duration(minutes: 1)),
    );

    test('no unexpected socket errors surfaced during the run', () {
      expect(alice.events.errors, isEmpty,
          reason: 'alice received server error events');
      expect(bob.events.errors, isEmpty,
          reason: 'bob received server error events');
    });
  });
}
