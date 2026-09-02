// D1 (spec §12 amendment (xlvii)): after a peer completes a §6.2 reset, this
// client must be able to recover them — and the action offered to the user must
// not destroy the only warning.
//
// This is the pipeline proof that (xlvi)'s own tests could not give. They call
// `SecureIdentityKeyStore.isTrustedIdentity` directly, so the test plays the
// decrypt path's part. In production that method is reached only from inside the
// Signal decrypt, and the accept gate of (e)/(xxvii) runs BEFORE it:
//
//   peer resets → their re-enrolled list cannot verify (we still hold their OLD
//   key as the account anchor) → `getVerifiedDeviceList` throws → the accept
//   gate withholds every row from their new device id
//   (messaging_provider.decrypt.dart:155; the escape hatch at :146 admits
//   device 1 ONLY, and a post-§6.2 account has no device 1 because ids are
//   never reused) → Signal decrypt never runs → `isTrustedIdentity` never runs
//   → the pending candidate is never written (its ONLY writer is
//   signal_stores.dart:585-588).
//
// Before (xlvii) the story ended there: `acknowledgePeerIdentity` dropped the
// alarm FIRST and unconditionally, then found nothing to promote, so the user
// lost the warning and got no repair. Now the recovery runs off the key the
// server currently serves, shown to a human and pinned only on confirmation.
//
// WHAT EACH TEST IS FOR:
//   1. the row is still withheld and the LOCAL path still stays silent — an
//      ACCEPTED RESIDUAL, deliberately not fixed (see its own comment)
//   2. acknowledging with nothing to pin is REFUSED and the warning survives
//      ((xlvii) clause 1 — this assertion is the inversion of the D1 baseline)
//   3. the served key, confirmed by a human, advances the anchor and makes the
//      peer's list verify again ((xlvii) clause 3 — the actual recovery)
//   4. COUNTERFACTUAL: the same ciphertext as a legacy row DOES alarm, which
//      pins the silence in 1 to the GATE ORDERING and nothing else
//   5. POSITIVE CONTROL: the served list is genuinely valid
//
// Everything here is a real production object except the socket transport.

import 'dart:convert';

import 'package:fireplace/models/message_model.dart';
import 'package:fireplace/providers/conversations_provider.dart';
import 'package:fireplace/providers/encryption_provider.dart';
import 'package:fireplace/providers/messaging_provider.dart';
import 'package:fireplace/services/device_list/device_authority_engine.dart';
import 'package:fireplace/services/encryption/signal_stores.dart';
import 'package:fireplace/services/device_list/device_list_cache.dart';
import 'package:fireplace/services/device_list/device_list_canonical.dart';
import 'package:fireplace/services/encryption_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const ownUserId = 7;
  const peerId = 42;
  const conversationId = 10;

  /// The peer's post-§6.2 device id. Ids are never reused ((a)).
  const peerNewDeviceId = 5;

  late EncryptionProvider enc;
  late MessagingProvider messaging;
  late ConversationsProvider conversations;
  late EncryptionService peerBeforeReset;
  late EncryptionService peerAfterReset;
  late DeviceAuthorityEngine peerEngine;
  late IdentityKeyPair peerNewIdentity;
  late Map<String, dynamic> enrollment;

  Map<String, dynamic> flatBundleFrom(EncryptionService source) {
    final upload = source.getKeysForUpload();
    expect(upload, isNotNull);
    final keyBundle = (upload!['keyBundle'] as Map).cast<String, dynamic>();
    final otps = (upload['oneTimePreKeys'] as List).cast<Map<String, dynamic>>();
    expect(otps, isNotEmpty);
    return {
      ...keyBundle,
      'oneTimePreKeyId': otps.first['keyId'],
      'oneTimePreKeyPublic': otps.first['publicKey'],
    };
  }

  /// The peer's list AFTER recovery: signed by a fresh DAK under their NEW
  /// identity, naming only the freshly allocated id. Exactly what (xlv)
  /// clause 1 makes the recovering device publish.
  Map<String, dynamic> postResetAuthorization() {
    final signed = peerEngine.signList(
      DeviceList(
        userId: peerId,
        version: 2,
        devices: const [
          DeviceListEntry(
            deviceId: peerNewDeviceId,
            platform: 'web',
            addedAtMs: 2000,
          ),
        ],
      ),
    );
    return {
      'dakPub': enrollment['dakPub'],
      'enrollmentSig': enrollment['enrollmentSig'],
      'enrollmentCreatedAt': enrollment['createdAt'],
      'listVersion': 2,
      'listSignature': signed['listSignature'],
      'listCanonical': signed['listCanonical'],
    };
  }

  /// The bundle the server serves for the peer's post-reset device.
  ///
  /// `identityPublicKey` is the key that SIGNED the enrollment above, because §3
  /// gives an account exactly ONE identity key — in production the bundle
  /// identity and the list-signing identity are the same value. This file's
  /// setup keeps two objects for convenience (`peerAfterReset` to produce real
  /// ciphertext, `peerNewIdentity` to drive the DAK chain), so the served bundle
  /// must name the one the chain anchors on. Serving the other would make
  /// adoption unable to fix the list, and the recovery test would then be
  /// asserting the opposite of what it claims.
  Map<String, dynamic> postResetBundle() => {
    ...flatBundleFrom(peerAfterReset),
    'identityPublicKey': base64Encode(
      peerNewIdentity.getPublicKey().serialize(),
    ),
  };

  Map<String, dynamic> inboundRow({
    required String ciphertext,
    int? originDeviceId,
  }) => {
    'id': 900,
    'conversationId': conversationId,
    'senderId': peerId,
    'senderUsername': 'bob',
    'content': '[encrypted]',
    'encryptedContent': ciphertext,
    'messageType': 'TEXT',
    'deliveryStatus': 'DELIVERED',
    'createdAt': DateTime.utc(2026, 1, 2, 12).toIso8601String(),
    // Omitted entirely when null — a LEGACY row, which is what makes
    // `decrypt.dart:97` default the origin device to 1.
    'originDeviceId': ?originDeviceId,
  };

  Map<String, dynamic> conversationJson() => {
    'id': conversationId,
    'userOne': {'id': ownUserId, 'username': 'alice', 'tag': '0001'},
    'userTwo': {'id': peerId, 'username': 'bob', 'tag': '0002'},
    'createdAt': '2026-01-01T00:00:00.000Z',
    'unreadCount': 0,
    'lastMessage': null,
  };

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});

    enc = EncryptionProvider();
    enc.setEmitCallback((event, data) {
      if (event == 'checkOwnKeyBundle') {
        enc.onOwnKeyBundleStatus({'exists': false});
      }
      if (event == 'getDeviceList') {
        // The server serves the peer's post-recovery list. It is perfectly
        // valid — it just cannot be verified against the key WE still hold.
        enc.onDeviceList({
          'userId': peerId,
          'authorization': postResetAuthorization(),
        });
      }
      if (event == 'fetchPreKeyBundle') {
        // The server answers with the peer's CURRENT bundle, on whichever
        // device was asked for. This is the only place the peer's post-reset
        // account identity can come from once the accept gate has refused
        // every one of their rows.
        enc.onPreKeyBundleResponse({
          'userId': peerId,
          'deviceId': (data as Map)['deviceId'] ?? 1,
          'bundle': postResetBundle(),
        });
      }
    });
    await enc.initializeE2E(ownUserId);

    // The peer BEFORE the reset. First contact pins their old key as our
    // account anchor, exactly as an ordinary conversation would.
    peerBeforeReset = EncryptionService();
    await peerBeforeReset.initialize(
      peerId,
      checkServerBundleExists: () async => false,
    );
    await enc.encryptionService.buildSession(
      peerId,
      flatBundleFrom(peerBeforeReset),
      expectedIdentityBase64: null,
    );
    expect(enc.peersWithChangedIdentity, isEmpty);

    // The peer AFTER the reset: a genuinely new identity, and a fresh DAK
    // enrollment signed under it.
    peerAfterReset = EncryptionService();
    await peerAfterReset.initialize(
      9001,
      checkServerBundleExists: () async => false,
    );
    peerEngine = DeviceAuthorityEngine();
    peerNewIdentity = generateIdentityKeyPair();
    enrollment = peerEngine.mintEnrollment(
      userId: peerId,
      identity: peerNewIdentity,
      createdAtMs: 1234567890,
    );

    conversations = ConversationsProvider()..setCurrentUserId(ownUserId);
    conversations.onConversationsList([conversationJson()]);
    conversations.openConversation(conversationId, notify: false);

    messaging = MessagingProvider();
    messaging.setIncomingMessageSoundEnabledForTest(false);
    messaging.setConversationsProvider(conversations);
    messaging.setEncryptionProvider(enc);
    messaging.setCurrentUserId(ownUserId);
    messaging.setToken('tok');
    messaging.setEmitCallback((event, data) {});
    messaging.onConnect(false);
    messaging.setActiveConversationIdForTest(conversationId);
    messaging.seedCacheForTest(conversationId, <MessageModel>[]);
    messaging.loadCachedMessages(conversationId);
  });

  /// A REAL ciphertext from the peer's post-reset identity to us. Using real
  /// ciphertext is the point: this row COULD have decrypted and raised the
  /// alarm, so withholding it is a decision, not an inability.
  Future<String> resetPeerCiphertext() async {
    final ourUpload = enc.encryptionService.getKeysForUpload();
    expect(ourUpload, isNotNull);
    final ourKeyBundle = (ourUpload!['keyBundle'] as Map)
        .cast<String, dynamic>();
    final ourOtps = (ourUpload['oneTimePreKeys'] as List)
        .cast<Map<String, dynamic>>();
    await peerAfterReset.buildSession(ownUserId, {
      ...ourKeyBundle,
      'oneTimePreKeyId': ourOtps.first['keyId'],
      'oneTimePreKeyPublic': ourOtps.first['publicKey'],
    }, expectedIdentityBase64: null);
    return peerAfterReset.encrypt(ownUserId, 'hello after my reset');
  }

  /// SUPERSEDED by amendment (lii). This WAS an accepted residual; RC-01 showed
  /// the residual was the defect.
  ///
  /// The old rationale: the only signal at the gate is "this peer's list will
  /// not verify", which a malicious or broken server can produce at will, so
  /// alarming on it would let the server manufacture identity warnings for any
  /// peer and train the user to dismiss the one surface that detects a real
  /// takeover. Sound about fatigue, and it remains true that a genuine rotation
  /// and a forged enrollment cannot be told apart locally.
  ///
  /// What overturned it: the alternative was not silence but a PERMANENT
  /// lockout. Every other path that could tell the peer is closed — the accept
  /// gate withholds before Signal can stage a candidate, and the live
  /// `peerIdentityChanged` never reaches a peer who was offline — and BOTH
  /// (xlvii) doors are gated on this warning set. Decisively, the send ALREADY
  /// fails in this state, so the alarm is not noise on a working conversation:
  /// it names a failure the user can already see and exposes the only exit.
  /// I7 mandated this surface all along.
  ///
  /// The candidate is still NOT staged — that half of the residual stands, and
  /// it is why (xlvii) clause 3's served-key ceremony remains load-bearing.
  test(
    'the reset peer row is withheld AND the identity surface is raised ((lii))',
    () async {
      final ciphertext = await resetPeerCiphertext();

      messaging.onNewMessage(
        inboundRow(ciphertext: ciphertext, originDeviceId: peerNewDeviceId),
      );
      await pumpEventQueue(times: 200);

      final row = messaging.messages.firstWhere((m) => m.id == 900);
      expect(
        row.content,
        isNot('hello after my reset'),
        reason: 'the accept gate withholds the row before Signal ever sees it',
      );
      expect(
        enc.peersWithChangedIdentity,
        contains(peerId),
        reason:
            'I7: an enrollment that does not verify under the pinned anchor is '
            'a loud identity-changed surface, and it is the only door back',
      );
    },
  );

  /// The other half of (lii): the allow-list. A server must NOT be able to flag
  /// every contact as identity-changed by answering garbage — that would trade a
  /// silent lockout for a server-driven false alarm on the same surface.
  test('a MALFORMED list raises no identity surface ((lii) allow-list)', () async {
    // Separate own-user id for a clean `e2e_<uid>_` storage prefix.
    final p = EncryptionProvider();
    p.setEmitCallback((event, data) {
      if (event == 'checkOwnKeyBundle') {
        p.onOwnKeyBundleStatus({'exists': false});
      }
      if (event == 'getDeviceList') {
        // Unparseable: `malformed_answer`, not an anchor mismatch.
        p.onDeviceList({
          'userId': peerId,
          'authorization': {'dakPub': 'not-base64!!', 'listVersion': 1},
        });
      }
    });
    await p.initializeE2E(12);
    // We DO hold an anchor, so the anchor gate is not what makes this silent —
    // the reason code is.
    await p.encryptionService.debugSavePeerIdentity(
      peerId,
      base64Encode(peerNewIdentity.getPublicKey().serialize()),
    );

    await expectLater(
      p.getVerifiedDeviceList(peerId),
      throwsA(isA<DeviceListVerificationException>()),
      reason: 'still fail-closed — (lii) adds an alarm, not permissiveness',
    );

    // The recorder is fire-and-forget, so without this the assertion below
    // races it and passes no matter what the guard does.
    await pumpEventQueue(times: 200);

    expect(
      p.peersWithChangedIdentity,
      isEmpty,
      reason:
          'garbage is not evidence about anyone key; alarming on it is what '
          'trains users to dismiss the surface that catches a real takeover',
    );
  });

  /// (xlvii) clause 1. THIS IS THE INVERTED D1 ASSERTION: the warning used to
  /// be dropped here, unconditionally and before anything was checked, so the
  /// single persisted notice of a real event was destroyed in exchange for
  /// nothing. It must now survive an acknowledgement that could not repair.
  test('acknowledging with nothing to pin is refused and the warning survives', (
  ) async {
    // The production trigger for this shape.
    await enc.encryptionService.recordPeerIdentityChangedFromServer(peerId);
    expect(enc.peersWithChangedIdentity, contains(peerId));

    final anchorBefore = await enc.encryptionService.peerTofuIdentityBase64(
      peerId,
    );

    // No offered key, and no candidate was ever recorded — the D1 shape.
    final advanced = await enc.acknowledgePeerIdentity(peerId);

    expect(advanced, isFalse, reason: 'there was nothing to pin');
    expect(
      enc.peersWithChangedIdentity,
      contains(peerId),
      reason:
          'THE INVERSION: an acknowledgement that repaired nothing must not '
          'clear the warning it could not act on',
    );
    expect(
      await enc.encryptionService.peerTofuIdentityBase64(peerId),
      anchorBefore,
      reason: 'and it must not move the anchor either',
    );
  });

  /// (xlvii) clause 3 — the recovery itself, end to end: alarm → served key →
  /// human confirmation → anchor advances → the peer's list verifies again.
  test('a human-confirmed served key advances the anchor and restores the peer', () async {
    await enc.encryptionService.recordPeerIdentityChangedFromServer(peerId);
    final anchorBefore = await enc.encryptionService.peerTofuIdentityBase64(
      peerId,
    );
    final peerNewKeyBase64 = base64Encode(
      peerNewIdentity.getPublicKey().serialize(),
    );
    expect(
      peerNewKeyBase64,
      isNot(anchorBefore),
      reason: 'sanity: the peer really did change identity',
    );

    // BEFORE: the peer's genuinely valid list cannot verify against our stale
    // pin, which is what makes them unreachable in both directions.
    await expectLater(
      enc.getVerifiedDeviceList(peerId),
      throwsA(isA<DeviceListVerificationException>()),
    );

    // The ceremony: what does the user get shown?
    final verification = await enc.loadPeerIdentityVerification(peerId);
    expect(
      verification.hasOffer,
      isTrue,
      reason:
          'with no candidate on hand the offer must come from the served '
          'key, or there is nothing for the user to compare and the peer '
          'stays unreachable for good',
    );
    expect(
      verification.offeredWasServed,
      isTrue,
      reason: 'and the user must be told it is uncorroborated',
    );
    expect(verification.offeredIdentityBase64, peerNewKeyBase64);
    expect(
      verification.offeredFingerprint,
      isNot(verification.pinnedFingerprint),
      reason: 'the two numbers on screen must actually differ',
    );

    // The human confirms the fingerprint they were shown.
    final advanced = await enc.acknowledgePeerIdentity(
      peerId,
      adoptIdentityBase64: verification.offeredIdentityBase64,
    );

    expect(advanced, isTrue);
    expect(
      await enc.encryptionService.peerTofuIdentityBase64(peerId),
      peerNewKeyBase64,
      reason: 'the anchor advanced to the key the user compared',
    );
    expect(enc.peersWithChangedIdentity, isEmpty);

    // The anchor is necessary but NOT sufficient: (xlvii) clause 3 makes the
    // poison-clearing load-bearing, because a stale ratchet keyed to the old
    // identity would keep every send failing while the anchor looked fine.
    // Device 1 is always marked — it is the legacy address that predates any
    // list, and the only one we can name before a list verifies.
    expect(
      enc.needsSessionRebuild(peerId, deviceId: 1),
      isTrue,
      reason:
          'the sessions the stale anchor poisoned must be rebuilt, or the '
          'anchor advances and the sends still fail',
    );

    // AFTER: the same served list now verifies, so the peer is addressable
    // again. This is the assertion the whole amendment exists for.
    final verified = await enc.getVerifiedDeviceList(peerId);
    expect(verified.enrolled, isTrue);
    expect(verified.liveDeviceIds, [peerNewDeviceId]);
    expect(verified.version, 2);
  });

  /// The OTHER half of clause 3's poison-clearing, which the recovery test
  /// above cannot reach: there, nothing was ever cached (every verification
  /// failed), so the cache invalidation was a no-op and could have been deleted
  /// with the suite still green. This sets up a peer whose list DOES verify,
  /// caches it, and then adopts a different key.
  test('adoption drops the cached list and marks its devices for rebuild', () async {
    const cachedDeviceId = 3;
    final peerOldIdentity = generateIdentityKeyPair();
    final oldEngine = DeviceAuthorityEngine();
    final oldEnrollment = oldEngine.mintEnrollment(
      userId: peerId,
      identity: peerOldIdentity,
      createdAtMs: 1000,
    );
    final oldList = oldEngine.signList(
      DeviceList(
        userId: peerId,
        version: 1,
        devices: const [
          DeviceListEntry(
            deviceId: cachedDeviceId,
            platform: 'web',
            addedAtMs: 1000,
          ),
        ],
      ),
    );

    // The key the peer rotates TO. Served by the server on request, exactly as
    // clause 3's ceremony obtains it — an invented key would (correctly) be
    // refused now, because only a key this device recorded may be pinned.
    final rotatedTo = generateIdentityKeyPair();

    // A separate own-user id gives a clean `e2e_<uid>_` storage prefix.
    final p = EncryptionProvider();
    p.setEmitCallback((event, data) {
      if (event == 'checkOwnKeyBundle') {
        p.onOwnKeyBundleStatus({'exists': false});
      }
      if (event == 'getDeviceList') {
        p.onDeviceList({
          'userId': peerId,
          'authorization': {
            'dakPub': oldEnrollment['dakPub'],
            'enrollmentSig': oldEnrollment['enrollmentSig'],
            'enrollmentCreatedAt': oldEnrollment['createdAt'],
            'listVersion': 1,
            'listSignature': oldList['listSignature'],
            'listCanonical': oldList['listCanonical'],
          },
        });
      }
      if (event == 'fetchPreKeyBundle') {
        p.onPreKeyBundleResponse({
          'userId': peerId,
          'deviceId': (data as Map)['deviceId'] ?? 1,
          'bundle': {
            ...flatBundleFrom(peerAfterReset),
            'identityPublicKey': base64Encode(
              rotatedTo.getPublicKey().serialize(),
            ),
          },
        });
      }
    });
    await p.initializeE2E(11);
    await p.encryptionService.debugSavePeerIdentity(
      peerId,
      base64Encode(peerOldIdentity.getPublicKey().serialize()),
    );

    // The list verifies against the anchor we hold, so it is CACHED.
    final before = await p.getVerifiedDeviceList(peerId);
    expect(before.liveDeviceIds, [cachedDeviceId]);
    expect(p.cachedDeviceList(peerId), isNotNull);

    // The peer's key changes and the user runs the ceremony and accepts it.
    await p.encryptionService.recordPeerIdentityChangedFromServer(peerId);
    final verification = await p.loadPeerIdentityVerification(peerId);
    expect(
      verification.offeredIdentityBase64,
      base64Encode(rotatedTo.getPublicKey().serialize()),
    );
    final advanced = await p.acknowledgePeerIdentity(
      peerId,
      adoptIdentityBase64: verification.offeredIdentityBase64,
    );
    expect(advanced, isTrue);

    expect(
      p.cachedDeviceList(peerId),
      isNull,
      reason:
          'the cached list was verified against the OLD anchor, so holding it '
          'after the anchor moved would keep addressing the peer from data '
          'this device can no longer justify',
    );
    expect(
      p.needsSessionRebuild(peerId, deviceId: cachedDeviceId),
      isTrue,
      reason: 'every device we believed the peer had must re-key',
    );
    expect(p.needsSessionRebuild(peerId, deviceId: 1), isTrue);
  });

  /// Hardening from the (xlvii) security review. `adoptIdentityBase64` was
  /// opaque caller input: decoded and pinned with no check that the bytes had
  /// ever been recorded or displayed, so "the pinned key is the key the human
  /// was shown" rested on ONE call site happening to pass the right value. Any
  /// future caller could have moved the I7 anchor to a key nobody ever saw.
  test('an unrecorded key is refused and moves nothing', () async {
    await enc.encryptionService.recordPeerIdentityChangedFromServer(peerId);
    final anchorBefore = await enc.encryptionService.peerTofuIdentityBase64(
      peerId,
    );

    final advanced = await enc.acknowledgePeerIdentity(
      peerId,
      adoptIdentityBase64: base64Encode(
        generateIdentityKeyPair().getPublicKey().serialize(),
      ),
    );

    expect(
      advanced,
      isFalse,
      reason: 'this device never recorded that key from anywhere',
    );
    expect(
      await enc.encryptionService.peerTofuIdentityBase64(peerId),
      anchorBefore,
      reason: 'the I7 anchor must be unreachable from invented bytes',
    );
    expect(
      enc.peersWithChangedIdentity,
      contains(peerId),
      reason: 'and a refused adoption leaves the warning standing',
    );
  });

  /// Hardening from review. The candidate slot is read TWICE by the ceremony —
  /// once to display a fingerprint, once to promote — and it has several
  /// unconditional writers. A plain "check, then promote" therefore has a window
  /// where the candidate moves in between, and the user compares fingerprint A
  /// out of band while key B gets pinned. That is the (xlvii) clause 2 defect
  /// wearing a different hat, so the promotion is compare-and-swap.
  test('a candidate that changes after display is refused, not substituted', () async {
    await enc.encryptionService.recordPeerIdentityChangedFromServer(peerId);
    final anchorBefore = await enc.encryptionService.peerTofuIdentityBase64(
      peerId,
    );

    // The ceremony obtains and displays key A (the served one).
    final displayed = await enc.loadPeerIdentityVerification(peerId);
    expect(displayed.hasOffer, isTrue);
    final keyA = displayed.offeredIdentityBase64!;

    // While the dialog sits open, the candidate is replaced by key B — exactly
    // what an inbound ciphertext (via isTrustedIdentity) or a second served
    // fetch would do. Driven through the REAL store on the service's own
    // storage prefix, so this is a genuine competing writer and not a seam.
    final keyB = generateIdentityKeyPair().getPublicKey();
    final store = SecureIdentityKeyStore(
      DualStorage(const FlutterSecureStorage()),
      'e2e_${ownUserId}_',
    );
    await store.stagePendingAccountIdentity(peerId.toString(), keyB);
    expect(base64Encode(keyB.serialize()), isNot(keyA));

    // The user confirms the number they actually compared: key A.
    final advanced = await enc.acknowledgePeerIdentity(
      peerId,
      adoptIdentityBase64: keyA,
    );

    expect(
      advanced,
      isFalse,
      reason: 'A is no longer the candidate, so nothing may be pinned',
    );
    expect(
      await enc.encryptionService.peerTofuIdentityBase64(peerId),
      anchorBefore,
      reason:
          'and above all B must NOT have been pinned — that would pin a key '
          'the user never compared',
    );
    expect(
      enc.peersWithChangedIdentity,
      contains(peerId),
      reason: 'the warning stands so the ceremony can be re-run',
    );
  });

  /// Clause 1 must not create a NEW dead end. If the served key turns out to be
  /// the one already pinned, the warning is STILL standing — and because clause
  /// 1 only clears on an advance, suppressing the offer in that case left an
  /// alarm with no control to resolve it. Re-affirming the compared key is a
  /// legitimate resolution. (Found by the (xlvii) spec-conformance review.)
  test('a served key identical to the pin still resolves the warning', () async {
    await enc.encryptionService.recordPeerIdentityChangedFromServer(peerId);
    final pinned = await enc.encryptionService.peerTofuIdentityBase64(peerId);

    final v = await enc.encryptionService.peerIdentityVerification(
      peerId,
      servedIdentityBase64: pinned,
    );

    expect(
      v.hasOffer,
      isTrue,
      reason: 'the user must be left SOME control over a standing warning',
    );
    expect(v.offerMatchesPin, isTrue);
    expect(
      v.offeredFingerprint,
      isNull,
      reason:
          'and it must not be dressed up as a change — the same number under '
          '"new" and "previous" labels reads as a mismatch',
    );

    final advanced = await enc.acknowledgePeerIdentity(
      peerId,
      adoptIdentityBase64: v.offeredIdentityBase64,
    );

    expect(advanced, isTrue);
    expect(enc.peersWithChangedIdentity, isEmpty);
  });

  test(
    'COUNTERFACTUAL: the same ciphertext as a legacy row DOES alarm',
    () async {
      final ciphertext = await resetPeerCiphertext();

      // No originDeviceId — a legacy send. `decrypt.dart:97` defaults it to 1,
      // which takes the device-1 escape hatch at :146, so the decrypt runs and
      // isTrustedIdentity fires. This isolates the cause to the GATE ORDERING:
      // identical ciphertext, identical stores, opposite outcome.
      messaging.onNewMessage(inboundRow(ciphertext: ciphertext));
      await pumpEventQueue(times: 200);

      expect(
        enc.peersWithChangedIdentity,
        contains(peerId),
        reason:
            'the store and the service are fine; only the gate ordering '
            'decides whether the user is ever told',
      );
    },
  );

  test(
    'POSITIVE CONTROL: the SAME served list verifies against the peer NEW key',
    () async {
      // Without this, the whole file could be proving nothing more than
      // "a malformed list is rejected". The authorization served above is built
      // by the real `DeviceAuthorityEngine` — `mintEnrollment` under the peer's
      // new identity, then `signList` with that engine's DAK — so it is
      // genuinely valid and must VERIFY for a client whose anchor is the
      // peer's post-reset key. That pins the D1 failure to our stale pin and
      // nothing else.
      //
      // A different own-user id gives a different `e2e_<uid>_` storage prefix,
      // i.e. a clean anchor: this stands in for an install that met the peer
      // only AFTER their recovery.
      final fresh = EncryptionProvider();
      fresh.setEmitCallback((event, data) {
        if (event == 'checkOwnKeyBundle') {
          fresh.onOwnKeyBundleStatus({'exists': false});
        }
        if (event == 'getDeviceList') {
          fresh.onDeviceList({
            'userId': peerId,
            'authorization': postResetAuthorization(),
          });
        }
      });
      await fresh.initializeE2E(8);
      await fresh.encryptionService.debugSavePeerIdentity(
        peerId,
        base64Encode(peerNewIdentity.getPublicKey().serialize()),
      );

      final verified = await fresh.getVerifiedDeviceList(peerId);

      expect(
        verified.enrolled,
        isTrue,
        reason:
            'the served list is well-formed and correctly signed; if this '
            'fails, the other tests prove only "malformed list rejected"',
      );
      expect(verified.liveDeviceIds, [peerNewDeviceId]);
      expect(verified.version, 2);
    },
  );
}
