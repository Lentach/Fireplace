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
//   1. register -> socketReady (parseable, plausible serverTime) -> WS key upload
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
// Each run leaves 2 throwaway accounts (+1 conversation, ~11 messages, key
// bundles/OTPs) in the TARGET dev DB — harmless local cruft; never point
// E2E_BASE_URL at production.

import 'dart:convert';
import 'dart:typed_data';

import 'package:fireplace/services/device_list/device_authority_engine.dart';
import 'package:fireplace/services/device_list/device_list_canonical.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
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

  /// Pins the server clock field which protects irreversible expiry purges.
  void expectSocketReadyServerTime(dynamic payload, String clientLabel) {
    expect(
      payload,
      isA<Map>(),
      reason: '$clientLabel socketReady must carry an object payload',
    );
    final serverTime = (payload as Map)['serverTime'];
    expect(
      serverTime,
      isA<String>(),
      reason: '$clientLabel socketReady.serverTime must be a string',
    );

    final serverTimeString = serverTime as String;
    expect(
      serverTimeString,
      isNotEmpty,
      reason: '$clientLabel socketReady.serverTime must not be empty',
    );
    final parsed = DateTime.tryParse(serverTimeString);
    expect(
      parsed,
      isNotNull,
      reason:
          '$clientLabel socketReady.serverTime must be a parseable ISO-8601 instant',
    );
    expect(
      parsed!.isUtc,
      isTrue,
      reason: '$clientLabel socketReady.serverTime must be UTC',
    );
    expect(
      parsed.difference(DateTime.now().toUtc()).abs(),
      lessThan(const Duration(minutes: 5)),
      reason:
          '$clientLabel socketReady.serverTime must be close to the test machine clock',
    );
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
    expect(
      wireType(ciphertext),
      expectedWireType,
      reason: 'unexpected ciphertext type for tempId=$tempId',
    );

    final sent = await sender.sendEncrypted(
      recipient.userId,
      ciphertext,
      tempId: tempId,
    );
    expect(
      sent['content'],
      '[encrypted]',
      reason: 'server must never store plaintext',
    );
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
      sender.userId,
      received['encryptedContent'] as String,
    );
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
    final aliceSocketReady = await alice.connectSocket();
    expectSocketReadyServerTime(aliceSocketReady, alice.label);
    await bob.connectSocket();

    // 3. Signal identity + key bundle upload (WS, like EncryptionProvider).
    await alice.initializeAndUploadKeys();
    await bob.initializeAndUploadKeys();

    // 4. Friendship: request over WS, accept on the receiving side.
    //
    // This also proves the GHOST INVITE contract across the tier boundary.
    // The backend emits `sentRequestsList` and the client parses it, but each
    // side is unit-tested against a mock, so only a live socket shows whether
    // the SENDER's own list is the one being refreshed. That is the half that
    // mocks cannot prove.
    //
    // Every wait below is preceded by a discard. Connecting already buffers an
    // empty `sentRequestsList`, and `EventLog.next` matches the first buffered
    // payload satisfying its predicate — so without discarding, a "must be
    // empty" wait happily consumes the empty from CONNECT time and passes even
    // if the action emitted nothing at all.
    alice.events.discard('sentRequestsList');
    alice.socketService.sendFriendRequest(bob.userId);

    final aliceGhosts =
        await alice.events.next(
              'sentRequestsList',
              where: (p) =>
                  p is List &&
                  p.any(
                    (e) =>
                        e is Map &&
                        e['receiver'] is Map &&
                        (e['receiver'] as Map)['id'] == bob.userId,
                  ),
              reason: 'sender must see their own outbound invite as a ghost',
            )
            as List;
    expect(
      aliceGhosts.length,
      1,
      reason: 'exactly the one invite alice just sent',
    );

    final rejected =
        await bob.events.next(
              'newFriendRequest',
              where: (p) =>
                  p is Map &&
                  p['sender'] is Map &&
                  (p['sender'] as Map)['id'] == alice.userId,
              reason: 'bob receiving alice first friend request',
            )
            as Map;

    // REJECT first. This is the riskier half of the lifecycle: the reject
    // path had to have `server` + `onlineUsers` threaded into it to reach the
    // ORIGINAL SENDER at all, and a mock cannot show which socket was hit.
    alice.events.discard('sentRequestsList');
    bob.socketService.rejectFriendRequest(rejected['id'] as int);
    await alice.events.next(
      'sentRequestsList',
      where: (p) => p is List && p.isEmpty,
      reason: 'rejecting must clear the sender ghost',
    );

    // Re-send, then accept, so the rest of the flow still has a friendship.
    alice.events.discard('sentRequestsList');
    alice.socketService.sendFriendRequest(bob.userId);
    await alice.events.next(
      'sentRequestsList',
      where: (p) =>
          p is List &&
          p.any(
            (e) =>
                e is Map &&
                e['receiver'] is Map &&
                (e['receiver'] as Map)['id'] == bob.userId,
          ),
      reason: 'the re-sent invite is a ghost again',
    );

    final request =
        await bob.events.next(
              'newFriendRequest',
              where: (p) =>
                  p is Map &&
                  p['sender'] is Map &&
                  (p['sender'] as Map)['id'] == alice.userId &&
                  p['id'] != rejected['id'],
              reason: 'bob receiving the re-sent request',
            )
            as Map;
    alice.events.discard('sentRequestsList');
    bob.events.discard('friendRequestAccepted');
    alice.events.discard('friendRequestAccepted');
    bob.events.discard('openConversation');
    alice.events.discard('openConversation');
    bob.socketService.acceptFriendRequest(request['id'] as int);
    final aliceAccepted =
        await alice.events.next(
              'friendRequestAccepted',
              reason: 'alice accept confirmation',
            )
            as Map;
    final bobAccepted =
        await bob.events.next(
              'friendRequestAccepted',
              reason: 'bob accept confirmation',
            )
            as Map;
    expect(
      aliceAccepted['conversationId'],
      isA<int>(),
      reason: 'alice accepted payload must carry a conversation id',
    );
    expect(
      bobAccepted['conversationId'],
      isA<int>(),
      reason: 'bob accepted payload must carry a conversation id',
    );
    expect(
      aliceAccepted['chatReady'],
      isTrue,
      reason: 'alice accepted payload must report chat readiness',
    );
    expect(
      bobAccepted['chatReady'],
      isTrue,
      reason: 'bob accepted payload must report chat readiness',
    );
    final aliceConversationId = aliceAccepted['conversationId'] as int;
    final bobConversationId = bobAccepted['conversationId'] as int;
    expect(
      bobConversationId,
      aliceConversationId,
      reason: 'both accepted payloads must identify the same conversation',
    );

    // The ghost must CLEAR on the sender's side once the invite resolves —
    // a ghost that outlives its invite is the whole failure mode here.
    await alice.events.next(
      'sentRequestsList',
      where: (p) => p is List && p.isEmpty,
      reason: 'accepting must clear the sender ghost',
    );

    // 5. Accepting reserves openConversation for explicit user intent only.
    await bob.events.none(
      'openConversation',
      within: const Duration(seconds: 3),
      reason: 'accepting an invitation must not auto-open chat',
    );
    alice.events.discard('openConversation');
    alice.socketService.startConversation(bob.userId);
    final aliceOpen =
        await alice.events.next(
              'openConversation',
              reason: 'alice startConversation',
            )
            as Map;
    conversationId = bobConversationId;
    expect(
      aliceOpen['conversationId'],
      conversationId,
      reason: 'startConversation must use the accepted conversation',
    );
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
        expect(
          bundle['oneTimePreKeyId'],
          isNotNull,
          reason: 'fresh account must have unused one-time pre-keys',
        );
        await alice.encryption.buildSession(bob.userId, bundle);

        await roundTrip(
          alice,
          bob,
          'first-contact-$runTag',
          tempId: 't1-$runTag',
          expectedWireType: 3,
        );
      },
      timeout: const Timeout(Duration(minutes: 1)),
    );

    test(
      'replies ratchet to whisper (2:) in both directions, in order',
      () async {
        await roundTrip(
          bob,
          alice,
          'reply-1-$runTag',
          tempId: 't2-$runTag',
          expectedWireType: 2,
        );
        await roundTrip(
          alice,
          bob,
          'msg-2-$runTag',
          tempId: 't3-$runTag',
          expectedWireType: 2,
        );
        await roundTrip(
          bob,
          alice,
          'reply-2-$runTag',
          tempId: 't4-$runTag',
          expectedWireType: 2,
        );

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
          await bob.decryptText(alice.userId, r1['encryptedContent'] as String),
          'twin-$runTag',
        );
        expect(
          await bob.decryptText(alice.userId, r2['encryptedContent'] as String),
          'twin-$runTag',
        );
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

        await roundTrip(
          alice,
          bob,
          'post-rebuild-$runTag',
          tempId: 't7-$runTag',
          expectedWireType: 3,
        );

        // Bidirectional sanity after the rebuild.
        await roundTrip(
          bob,
          alice,
          'post-rebuild-reply-$runTag',
          tempId: 't8-$runTag',
          expectedWireType: 2,
        );
      },
      timeout: const Timeout(Duration(minutes: 1)),
    );

    test(
      'edit swaps ciphertext; both sides get messageEdited; peer re-decrypts',
      () async {
        final messageId = await roundTrip(
          alice,
          bob,
          'original-$runTag',
          tempId: 't9-$runTag',
          expectedWireType: 2,
        );

        final editedPlaintext = 'edited-$runTag';
        final newCiphertext = await alice.encryptText(
          bob.userId,
          editedPlaintext,
        );
        expect(
          wireType(newCiphertext),
          2,
          reason: 'edit rides the existing session',
        );
        alice.emitEditMessage(messageId, newCiphertext);

        for (final client in [alice, bob]) {
          final edited =
              await client.events.next(
                    'messageEdited',
                    where: (p) => p is Map && p['messageId'] == messageId,
                    reason: '${client.label} messageEdited',
                  )
                  as Map;
          expect(edited['conversationId'], conversationId);
          expect(edited['content'], '[encrypted]');
          expect(edited['encryptedContent'], newCiphertext);
          expect(
            DateTime.tryParse(edited['editedAt'] as String),
            isNotNull,
            reason: 'editedAt must be an ISO timestamp',
          );
        }

        expect(
          await bob.decryptText(alice.userId, newCiphertext),
          editedPlaintext,
        );
      },
      timeout: const Timeout(Duration(minutes: 1)),
    );

    test(
      'edit by non-sender is rejected with not_sender',
      () async {
        final messageId = await roundTrip(
          alice,
          bob,
          'no-touching-$runTag',
          tempId: 't10-$runTag',
          expectedWireType: 2,
        );

        // Rejected before any store/decrypt, so a placeholder string is fine
        // (and never advances either ratchet).
        bob.emitEditMessage(messageId, 'rejected-probe-$runTag');
        final failed =
            await bob.events.next(
                  'editMessageFailed',
                  where: (p) => p is Map && p['messageId'] == messageId,
                  reason: 'bob edit rejection',
                )
                as Map;
        expect(failed['reason'], 'not_sender');
      },
      timeout: const Timeout(Duration(minutes: 1)),
    );

    test(
      'reactions round-trip to both sides and clear on removal',
      () async {
        final messageId = await roundTrip(
          alice,
          bob,
          'react-target-$runTag',
          tempId: 't11-$runTag',
          expectedWireType: 2,
        );

        bob.socketService.emitAddReaction(messageId, '🔥');
        for (final client in [alice, bob]) {
          final updated =
              await client.events.next(
                    'reactionUpdated',
                    where: (p) => p is Map && p['messageId'] == messageId,
                    reason: '${client.label} reaction add',
                  )
                  as Map;
          expect(updated['conversationId'], conversationId);
          expect((updated['reactions'] as Map)['🔥'], [bob.userId]);
        }

        bob.socketService.emitRemoveReaction(messageId, '🔥');
        for (final client in [alice, bob]) {
          final updated =
              await client.events.next(
                    'reactionUpdated',
                    where: (p) => p is Map && p['messageId'] == messageId,
                    reason: '${client.label} reaction remove',
                  )
                  as Map;
          expect(updated['reactions'], isEmpty);
        }
      },
      timeout: const Timeout(Duration(minutes: 1)),
    );

    test(
      'delete destroys the local plaintext and leaves the Signal session alive',
      () async {
        final plaintext = 'purge-me-$runTag';
        final messageId = await roundTrip(
          alice,
          bob,
          plaintext,
          tempId: 't12-$runTag',
          expectedWireType: 2,
        );

        // Persist exactly as the app does at decrypt time, including the
        // envelope metadata the sweeps select on.
        await bob.encryption.saveDecryptedContent(
          messageId,
          {'content': plaintext},
          conversationId: conversationId,
          createdAt: DateTime.now().toUtc(),
        );
        expect(
          (await bob.encryption.getDecryptedContent(messageId))?['content'],
          plaintext,
          reason:
              'precondition: the only copy of the plaintext is on the device',
        );

        // Real server delete over the real wire, hard-deleting the row.
        alice.emitDeleteMessage(messageId, forEveryone: true);
        for (final client in [alice, bob]) {
          await client.events.next(
            'messageDeleted',
            where: (p) => p is Map && p['messageId'] == messageId,
            reason: '${client.label} messageDeleted',
          );
        }

        // What the app's messageDeleted handler does. Asserted against a REAL
        // store with real Signal state present, because the risk is not that
        // the delete fails — it is that destroying plaintext also damages the
        // session and bricks the conversation.
        final purge = await bob.encryption.removeDecryptedContent([messageId]);
        expect(purge.isComplete, isTrue);
        expect(purge.removed, 1);
        expect(
          await bob.encryption.getDecryptedContent(messageId),
          isNull,
          reason: 'deleting a message must destroy its local plaintext',
        );

        // The session survived: new traffic still ratchets and decrypts. A
        // purge that quietly broke this would trade one bug for a worse one.
        await roundTrip(
          alice,
          bob,
          'after-purge-$runTag',
          tempId: 't13-$runTag',
          expectedWireType: 2,
        );
      },
      timeout: const Timeout(Duration(minutes: 1)),
    );

    test(
      'getServedMessageIds answers from the real history rules',
      () async {
        // The reconcile pass destroys the local plaintext of every id MISSING
        // from this answer, so a wrong "not served" is permanent data loss.
        // Mocked unit tests cannot see the assembled SQL; this can.
        final mine = await roundTrip(
          alice,
          bob,
          'served-mine-$runTag',
          tempId: 't14-$runTag',
          expectedWireType: 2,
        );
        final theirs = await roundTrip(
          bob,
          alice,
          'served-theirs-$runTag',
          tempId: 't15-$runTag',
          expectedWireType: 2,
        );
        final deleted = await roundTrip(
          alice,
          bob,
          'served-deleted-$runTag',
          tempId: 't16-$runTag',
          expectedWireType: 2,
        );
        final hiddenForBob = await roundTrip(
          alice,
          bob,
          'served-hidden-$runTag',
          tempId: 't17-$runTag',
          expectedWireType: 2,
        );

        alice.emitDeleteMessage(deleted, forEveryone: true);
        for (final client in [alice, bob]) {
          await client.events.next(
            'messageDeleted',
            where: (p) => p is Map && p['messageId'] == deleted,
            reason: '${client.label} hard delete',
          );
        }

        bob.emitDeleteMessage(hiddenForBob, forEveryone: false);
        await bob.events.next(
          'messageDeleted',
          where: (p) => p is Map && p['messageId'] == hiddenForBob,
          reason: 'bob delete-for-me',
        );

        const unknownId = 2147483000;
        final forAlice = await alice.servedMessageIds([
          mine,
          theirs,
          deleted,
          hiddenForBob,
          unknownId,
        ]);

        // THE trap: every unread-count query in MessagesService carries
        // `sender != me`. Copying one into the existence check would report
        // the user's entire outgoing history as gone and destroy it.
        expect(
          forAlice,
          contains(mine),
          reason: 'a message the caller SENT is still served',
        );
        expect(forAlice, contains(theirs));
        expect(
          forAlice,
          contains(hiddenForBob),
          reason: "bob's delete-for-me must not affect alice",
        );
        expect(forAlice, isNot(contains(deleted)));
        expect(forAlice, isNot(contains(unknownId)));

        final forBob = await bob.servedMessageIds([
          mine,
          theirs,
          deleted,
          hiddenForBob,
        ]);
        expect(forBob, contains(mine));
        expect(forBob, contains(theirs));
        expect(forBob, isNot(contains(deleted)));
        expect(
          forBob,
          isNot(contains(hiddenForBob)),
          reason: 'delete-for-me must read as gone for the user who did it',
        );
      },
      timeout: const Timeout(Duration(minutes: 1)),
    );

    test('a retry carrying the same sendToken re-acks the committed row and '
        'writes no second message (Phase 1 §5.4)', () async {
      // A lost ack is the dangerous case: the sending device holds the ONLY
      // plaintext copy until the ack lands, so a retry must recover the row
      // the server already wrote instead of duplicating the message.
      final token = 'tok-$runTag-${DateTime.now().microsecondsSinceEpoch}';
      final ciphertext = await alice.encryptText(
        bob.userId,
        'idempotent-$runTag',
      );

      final first = await alice.sendWithToken(
        bob.userId,
        ciphertext,
        tempId: 'tok-a-$runTag',
        sendToken: token,
      );
      final messageId = (first['id'] as num).toInt();
      expect(
        first['originDeviceId'],
        1,
        reason: 'the server records which device produced the message',
      );

      // Same token, new tempId: this is the client retrying, not a new send.
      final retry = await alice.sendWithToken(
        bob.userId,
        ciphertext,
        tempId: 'tok-b-$runTag',
        sendToken: token,
      );

      expect(
        (retry['id'] as num).toInt(),
        messageId,
        reason: 'the retry must resolve to the committed row',
      );
      // And the recipient must not see it twice — Signal decryption is not
      // idempotent, so a second delivery of the same ciphertext would fail
      // into the session-destroying policy.
      await bob.events.none(
        'newMessage',
        within: const Duration(seconds: 3),
        where: (p) => p is Map && p['tempId'] == 'tok-b-$runTag',
        reason: 'a retry must not deliver the message a second time',
      );
    }, timeout: const Timeout(Duration(minutes: 2)));

    // Phase 1 (spec §4 + §5.1 + §8): key material is namespaced by
    // (userId, deviceId), the device a bundle lands in comes from the
    // SESSION, and a device that published nothing is served nothing.
    //
    // Hosted here rather than in a file of its own because /auth/register is
    // throttled 10/hr per IP and this suite already spends every one of them;
    // alice is an account with real published keys, which is all this needs.
    group('per-device key material (Phase 1 §4)', () {
      late String sharedIdentity;
      late int deviceOneRegistration;

      setUpAll(() async {
        final deviceOne = await alice.fetchBundleFor(alice.userId, deviceId: 1);
        sharedIdentity = deviceOne['identityPublicKey'] as String;
        deviceOneRegistration = deviceOne['registrationId'] as int;
      });

      test(
        'an upload lands on the SESSION\'s device, whatever the payload claims',
        () async {
          // A client naming someone else's device could scatter key material
          // across namespaces peers later fetch, or park a bundle where the
          // account's real device-1 lookup never sees it (spec §5.1).
          final claimed = await alice.uploadDeviceKeyBundle(
            deviceId: 2,
            identityPublicKey: sharedIdentity,
            registrationId: deviceOneRegistration + 1,
          );
          expect(claimed['success'], isTrue);

          // It went to device 1 — this session's device...
          final one = await alice.fetchBundleFor(alice.userId, deviceId: 1);
          expect(one['registrationId'], deviceOneRegistration + 1);
          expect(
            one['identityPublicKey'],
            sharedIdentity,
            reason: 'the account identity is unchanged, so no lock refusal',
          );

          // ...and device 2 still does not exist.
          final two = await alice.fetchBundleRawFor(alice.userId, deviceId: 2);
          expect(two['bundle'], isNull);

          deviceOneRegistration = deviceOneRegistration + 1;
        },
        timeout: const Timeout(Duration(minutes: 1)),
      );

      test(
        'one-time pre-keys follow the session device too',
        () async {
          await alice.uploadDeviceOneTimePreKeys(
            deviceId: 2,
            identityPublicKey: sharedIdentity,
            keyIds: const [900, 901],
            publicKeyPrefix: 'claimed-dev2-otp-',
          );

          // Device 2 has no bundle, so nothing is served for it at all.
          final two = await alice.fetchBundleRawFor(alice.userId, deviceId: 2);
          expect(two['bundle'], isNull);

          // The keys landed in device 1's namespace, where this session lives.
          final one = await alice.fetchBundleFor(alice.userId, deviceId: 1);
          expect(one['oneTimePreKeyPublic'], isNotNull);
        },
        timeout: const Timeout(Duration(minutes: 1)),
      );

      test(
        'one-time pre-keys under an UNPUBLISHED identity are refused and the '
        'published pool survives (§5.1)',
        () async {
          // Observed live 2026-08-18: the lock refused a session's identity and
          // that same session still upserted 20 OTPs over the legitimate
          // device's keyId 0..19 slots. Unservable (the fetch filter pins the
          // published identity) but the victim's pool went empty until a peer
          // fetch re-triggered replenishment.
          await alice.uploadDeviceOneTimePreKeys(
            deviceId: 1,
            identityPublicKey: 'unpublished-identity-$runTag',
            keyIds: const [0, 1],
            publicKeyPrefix: 'foreign-otp-',
            expectRefusal: 'identity_locked',
          );

          // The account still serves a key, and never the refused epoch's.
          final served = await alice.fetchBundleFor(alice.userId, deviceId: 1);
          expect(served['identityPublicKey'], sharedIdentity);
          final otp = served['oneTimePreKeyPublic'] as String?;
          expect(
            otp,
            isNotNull,
            reason: 'the refusal must not have emptied the pool',
          );
          expect(otp, isNot(startsWith('foreign-otp-')));
        },
        timeout: const Timeout(Duration(minutes: 1)),
      );

      test(
        'an unknown device is served nothing, never another device\'s keys',
        () async {
          // Fail-closed: serving device 1's bundle for a device that never
          // uploaded one would build a session no such device can decrypt.
          final missing = await alice.fetchBundleRawFor(
            alice.userId,
            deviceId: 97,
          );

          expect(missing['bundle'], isNull);
        },
        timeout: const Timeout(Duration(minutes: 1)),
      );

      test(
        'a client that names no device still gets device 1 (§8 rollout)',
        () async {
          final legacy = await alice.fetchBundleFor(alice.userId);

          expect(legacy['identityPublicKey'], sharedIdentity);
          expect(legacy['registrationId'], deviceOneRegistration);
        },
        timeout: const Timeout(Duration(minutes: 1)),
      );
    });

    // Phase 2 T2 (spec §3/§5.2 + §12 amendments (d)/(g)): DAK enrollment,
    // the DAK-signed device list, and its falsifications — 2 (IK-signed
    // mutation), 3 (rollback/replay), 23 (byte-exact canonical), 25
    // (cross-construction signatures). Reuses alice (enrolling primary) and
    // bob (verifying peer): the register throttle budget is spent
    // (10/hr/IP across the suite), so NO new accounts here.
    group('DAK-signed device list (Phase 2 T2)', () {
      final engine = DeviceAuthorityEngine();
      late IdentityKeyPair aliceIdentity;
      late int enrolledCreatedAt;
      late Map<String, dynamic> enrollPayload;
      late Map<String, dynamic> enrolledAuthorization;

      setUpAll(() async {
        aliceIdentity = IdentityKeyPair.fromSerialized(
          base64Decode(await alice.exportIdentityPair()),
        );
      });

      test('enrollment pins DAK + v1 signed list, serves it byte-exact, and a '
          'peer chain-verifies IK→E→DAK→list (I7, falsification 23)', () async {
        // An unenrolled account answers null — the fail-closed shape a
        // legacy-server probe also relies on (§8).
        final before = await bob.fetchDeviceList(alice.userId);
        expect(before['authorization'], isNull);

        alice.events.discard('deviceListChanged');
        enrolledCreatedAt = DateTime.now().millisecondsSinceEpoch;
        final result = await engine.enroll(
          userId: alice.userId,
          identity: aliceIdentity,
          createdAtMs: enrolledCreatedAt,
          send: (payload) {
            enrollPayload = payload;
            return alice.enrollDeviceAuthority(payload);
          },
        );
        expect(result.accepted, isTrue, reason: 'error=${result.error}');

        // The account's sessions learn about the accepted write (§7 row
        // 424: deviceListChanged).
        final changed = await alice.events.next(
          'deviceListChanged',
          where: (p) => p is Map && p['userId'] == alice.userId,
          reason: 'alice deviceListChanged v1',
        );
        expect((changed as Map)['listVersion'], 1);

        // Served BYTE-EXACT: the stored base64 is the minted base64,
        // character for character (falsification 23 transport rule).
        final own = await alice.fetchDeviceList(alice.userId);
        final auth = (own['authorization'] as Map).cast<String, dynamic>();
        expect(auth['listCanonical'], enrollPayload['listCanonical']);
        expect(auth['listSignature'], enrollPayload['listSignature']);
        expect(auth['dakPub'], enrollPayload['dakPub']);
        expect(auth['enrollmentSig'], enrollPayload['enrollmentSig']);
        expect(
          auth['enrollmentCreatedAt'],
          enrolledCreatedAt,
          reason: 'peers re-verify E over the exact signed createdAt',
        );
        expect(auth['listVersion'], 1);

        // Peer view: bob fetches the list and verifies the FULL chain
        // against his TOFU'd view of alice's identity key (I7).
        final tofu = await bob.fetchBundleFor(alice.userId);
        final answer = await bob.fetchDeviceList(alice.userId);
        enrolledAuthorization = (answer['authorization'] as Map)
            .cast<String, dynamic>();
        expect(
          enrolledAuthorization['listCanonical'],
          enrollPayload['listCanonical'],
          reason: 'listCanonical must survive the wire byte-exact',
        );
        final verdict = DeviceAuthorityEngine.verifyPeerDeviceList(
          authorization: enrolledAuthorization,
          tofuIdentityKeyBase64: tofu['identityPublicKey'] as String,
          expectedUserId: alice.userId,
        );
        expect(verdict.ok, isTrue, reason: 'reason=${verdict.reason}');
        expect(verdict.deviceList!.devices.single.deviceId, 1);
      }, timeout: const Timeout(Duration(minutes: 2)));

      test('a second enrollment is refused — first-write-wins, the DAK '
          'authority is born once (I2)', () async {
        final second = DeviceAuthorityEngine();
        final result = await second.enroll(
          userId: alice.userId,
          identity: aliceIdentity,
          send: alice.enrollDeviceAuthority,
        );
        expect(result.accepted, isFalse);
        expect(result.error, 'already_enrolled');

        // Nothing moved: the pinned enrollment is the original one.
        final own = await alice.fetchDeviceList(alice.userId);
        final auth = (own['authorization'] as Map).cast<String, dynamic>();
        expect(auth['dakPub'], enrollPayload['dakPub']);
        expect(auth['listVersion'], 1);
      }, timeout: const Timeout(Duration(minutes: 1)));

      test('a list mutation signed by IK instead of DAK is rejected by the '
          'server and by the peer verifier (falsification 2)', () async {
        final canonical = encodeCanonicalDeviceList(
          DeviceList(
            userId: alice.userId,
            version: 2,
            devices: [
              DeviceListEntry(
                deviceId: 1,
                platform: 'android',
                addedAtMs: enrolledCreatedAt,
              ),
            ],
          ),
        );
        // Signed with the CORRECT list context but the WRONG authority:
        // the account's identity key (what a compromised linked PWA holds).
        final ikSignature = Curve.calculateSignature(
          aliceIdentity.getPrivateKey(),
          buildDeviceListMessage(canonical),
        );
        final answer = await alice.updateDeviceList({
          'listCanonical': base64Encode(canonical),
          'listSignature': base64Encode(ikSignature),
        });
        expect(answer['success'], isFalse);
        expect(answer['error'], 'invalid_list_signature');

        // Client half: the same forgery presented as a getDeviceList
        // answer is refused by the chain verifier.
        final verdict = DeviceAuthorityEngine.verifyPeerDeviceList(
          authorization: {
            ...enrolledAuthorization,
            'listVersion': 2,
            'listCanonical': base64Encode(canonical),
            'listSignature': base64Encode(ikSignature),
          },
          tofuIdentityKeyBase64: base64Encode(
            aliceIdentity.getPublicKey().serialize(),
          ),
          expectedUserId: alice.userId,
        );
        expect(verdict.ok, isFalse);
        expect(verdict.reason, 'invalid_list_signature');

        // The stored list did not move.
        final own = await alice.fetchDeviceList(alice.userId);
        expect((own['authorization'] as Map)['listVersion'], 1);
      }, timeout: const Timeout(Duration(minutes: 1)));

      test('version rollback, replay, and unsigned mutations are refused '
          'loudly; a valid v2 advances (falsification 3)', () async {
        final v2 = DeviceList(
          userId: alice.userId,
          version: 2,
          devices: [
            DeviceListEntry(
              deviceId: 1,
              platform: 'android',
              addedAtMs: enrolledCreatedAt,
              name: 'primary',
            ),
          ],
        );
        alice.events.discard('deviceListChanged');
        final v2Payload = engine.signList(v2);
        final accepted = await alice.updateDeviceList(v2Payload);
        expect(accepted['success'], isTrue, reason: '$accepted');
        expect(accepted['listVersion'], 2);
        final changed = await alice.events.next(
          'deviceListChanged',
          where: (p) => p is Map && p['listVersion'] == 2,
          reason: 'alice deviceListChanged v2',
        );
        expect((changed as Map)['userId'], alice.userId);

        // Replay of the accepted v2 → refused (version <= stored).
        final replayed = await alice.updateDeviceList(v2Payload);
        expect(replayed['success'], isFalse);
        expect(replayed['error'], 'stale_version');

        // Rollback: a FRESH valid signature over version 1 → refused.
        final rollback = await alice.updateDeviceList(
          engine.signList(
            DeviceList(
              userId: alice.userId,
              version: 1,
              devices: [
                DeviceListEntry(
                  deviceId: 1,
                  platform: 'android',
                  addedAtMs: enrolledCreatedAt,
                ),
              ],
            ),
          ),
        );
        expect(rollback['success'], isFalse);
        expect(rollback['error'], 'stale_version');

        // Unsigned/garbage signature at a NEW version → refused.
        final v3 = engine.signList(
          DeviceList(userId: alice.userId, version: 3, devices: v2.devices),
        );
        final unsigned = await alice.updateDeviceList({
          'listCanonical': v3['listCanonical'],
          'listSignature': base64Encode(Uint8List(64)),
        });
        expect(unsigned['success'], isFalse);
        expect(unsigned['error'], 'invalid_list_signature');

        // The stored list is exactly the accepted v2, byte-exact.
        final own = await alice.fetchDeviceList(alice.userId);
        final auth = (own['authorization'] as Map).cast<String, dynamic>();
        expect(auth['listVersion'], 2);
        expect(auth['listCanonical'], v2Payload['listCanonical']);

        // Client half of the rollback flag: a peer that pinned v2 and is
        // then served the old v1 answer raises the LOUD flag (I7).
        final verdict = DeviceAuthorityEngine.verifyPeerDeviceList(
          authorization: enrolledAuthorization,
          tofuIdentityKeyBase64: base64Encode(
            aliceIdentity.getPublicKey().serialize(),
          ),
          expectedUserId: alice.userId,
          previousVersion: 2,
        );
        expect(verdict.ok, isFalse);
        expect(verdict.reason, 'version_rollback');
      }, timeout: const Timeout(Duration(minutes: 2)));

      test('an ambiguous canonical is rejected AT PARSE even when correctly '
          'DAK-signed (falsification 23)', () async {
        // Duplicate-key bytes a canonical writer can never produce, signed
        // with the REAL enrolled DAK so only the parser can refuse them.
        final duplicateKey = Uint8List.fromList(
          utf8.encode(
            '{"userId":${alice.userId},"version":4,"version":4,"devices":'
            '[{"addedAt":1,"deviceId":1,"platform":"android"}]}',
          ),
        );
        // ignore: invalid_use_of_visible_for_testing_member
        final dupSig = engine.debugSignCanonicalBytes(duplicateKey);
        final dup = await alice.updateDeviceList({
          'listCanonical': base64Encode(duplicateKey),
          'listSignature': base64Encode(dupSig),
        });
        expect(dup['success'], isFalse);
        expect(dup['error'], 'invalid_canonical');

        // Whitespace re-serialization of a valid list: same rejection.
        final whitespace = Uint8List.fromList(
          utf8.encode(
            '{"userId":${alice.userId}, "version":4,"devices":'
            '[{"addedAt":1,"deviceId":1,"platform":"android"}]}',
          ),
        );
        // ignore: invalid_use_of_visible_for_testing_member
        final wsSig = engine.debugSignCanonicalBytes(whitespace);
        final ws = await alice.updateDeviceList({
          'listCanonical': base64Encode(whitespace),
          'listSignature': base64Encode(wsSig),
        });
        expect(ws['success'], isFalse);
        expect(ws['error'], 'invalid_canonical');

        // The client parser refuses the identical bytes (shared grammar).
        expect(
          () => parseCanonicalDeviceList(duplicateKey),
          throwsA(isA<CanonicalDeviceListException>()),
        );

        final own = await alice.fetchDeviceList(alice.userId);
        expect((own['authorization'] as Map)['listVersion'], 2);
      }, timeout: const Timeout(Duration(minutes: 1)));

      test('a signature minted for one construction is rejected by every '
          'other construction\'s verifier (falsification 25)', () async {
        // Enrollment signature presented as a list signature.
        final crossList = await alice.updateDeviceList({
          'listCanonical': enrollPayload['listCanonical'],
          'listSignature': enrollPayload['enrollmentSig'],
        });
        expect(crossList['success'], isFalse);
        expect(crossList['error'], 'invalid_list_signature');

        // bob (unenrolled) attempts enrollment whose E-slot carries other
        // constructions' signatures. His engine mints honestly, then the
        // signature is swapped — everything else stays valid.
        final bobIdentity = IdentityKeyPair.fromSerialized(
          base64Decode(await bob.exportIdentityPair()),
        );
        final bobEngine = DeviceAuthorityEngine();
        final bobPayload = bobEngine.mintEnrollment(
          userId: bob.userId,
          identity: bobIdentity,
          createdAtMs: DateTime.now().millisecondsSinceEpoch,
        );

        // (a) The DAK list signature presented as the enrollment sig.
        final listAsEnroll = await bob.enrollDeviceAuthority({
          ...bobPayload,
          'enrollmentSig': bobPayload['listSignature'],
        });
        expect(listAsEnroll['success'], isFalse);
        expect(listAsEnroll['error'], 'invalid_enrollment_signature');

        // (b) A FROZEN §6.1 registration-lock signature (0x05-leading
        // layout, no context) presented as the enrollment sig — the
        // CVE-2022-39250-class replay amendment (d) exists to kill.
        final ikSerialized = bobIdentity.getPublicKey().serialize();
        final lockMessage = Uint8List.fromList([
          ...ikSerialized,
          ...utf8.encode('${bob.userId}'),
          ...List<int>.generate(32, (i) => i),
        ]);
        final lockSig = Curve.calculateSignature(
          bobIdentity.getPrivateKey(),
          lockMessage,
        );
        final lockAsEnroll = await bob.enrollDeviceAuthority({
          ...bobPayload,
          'enrollmentSig': base64Encode(lockSig),
        });
        expect(lockAsEnroll['success'], isFalse);
        expect(lockAsEnroll['error'], 'invalid_enrollment_signature');

        // The refusals wrote nothing: bob is still unenrolled.
        final bobOwn = await bob.fetchDeviceList(bob.userId);
        expect(bobOwn['authorization'], isNull);
      }, timeout: const Timeout(Duration(minutes: 1)));
    });

    test('no unexpected socket errors surfaced during the run', () {
      expect(
        alice.events.errors,
        isEmpty,
        reason: 'alice received server error events',
      );
      expect(
        bob.events.errors,
        isEmpty,
        reason: 'bob received server error events',
      );
    });
  });
}
