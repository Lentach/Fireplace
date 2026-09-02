// Device-authorization engine (multi-device spec §3/§5.2 + §12 amendment (d),
// Phase 2 T2).
//
// Falsification 25 is pinned here in Dart (the signing language): a signature
// minted for any one construction — enrollment E, the DAK-signed list, or the
// frozen §6.1 registration-lock layout — is REJECTED by every other
// construction's verifier. The cross-language half (the REAL server verifiers
// against REAL Dart-minted signatures) is pinned by the backend's
// device-list-signature.util.spec.ts vectors and by the wire harness.

import 'dart:convert';
import 'dart:typed_data';

import 'package:fireplace/services/device_list/device_authority_engine.dart';
import 'package:fireplace/services/device_list/device_list_canonical.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

void main() {
  const userId = 4242;
  const createdAtMs = 1755600000000;
  final identity = generateIdentityKeyPair();
  final identityPub = identity.getPublicKey().serialize();

  Map<String, dynamic> mint(DeviceAuthorityEngine engine) =>
      engine.mintEnrollment(
        userId: userId,
        identity: identity,
        createdAtMs: createdAtMs,
      );

  /// The server's `deviceList` answer for a freshly minted enrollment.
  Map<String, dynamic> authorizationOf(Map<String, dynamic> payload) => {
    'dakPub': payload['dakPub'],
    'enrollmentSig': payload['enrollmentSig'],
    'enrollmentCreatedAt': payload['createdAt'],
    'listVersion': 1,
    'listSignature': payload['listSignature'],
    'listCanonical': payload['listCanonical'],
  };

  group('mintEnrollment', () {
    test('mints a payload whose whole I7 chain verifies', () {
      final engine = DeviceAuthorityEngine();
      final payload = mint(engine);

      final dakPub = base64Decode(payload['dakPub'] as String);
      expect(dakPub, hasLength(33));
      expect(dakPub[0], 0x05);
      expect(
        verifyEnrollmentSignature(
          identityPubSerialized: identityPub,
          userId: userId,
          dakPubSerialized: dakPub,
          createdAtMs: createdAtMs,
          signature: base64Decode(payload['enrollmentSig'] as String),
        ),
        isTrue,
      );

      final canonical = base64Decode(payload['listCanonical'] as String);
      expect(
        verifyDeviceListSignature(
          dakPubSerialized: dakPub,
          canonicalBytes: canonical,
          signature: base64Decode(payload['listSignature'] as String),
        ),
        isTrue,
      );

      final list = parseCanonicalDeviceList(canonical);
      expect(list.userId, userId);
      expect(list.version, 1);
      expect(
        list.devices.single.deviceId,
        1,
        reason: 'the current device set is device 1 until T3 links devices',
      );
    });

    test('signList requires a minted DAK and signs later versions', () {
      final engine = DeviceAuthorityEngine();
      expect(
        () => engine.signList(
          const DeviceList(
            userId: userId,
            version: 2,
            devices: [
              DeviceListEntry(deviceId: 1, platform: 'android', addedAtMs: 1),
            ],
          ),
        ),
        throwsStateError,
      );

      final payload = mint(engine);
      final update = engine.signList(
        const DeviceList(
          userId: userId,
          version: 2,
          devices: [
            DeviceListEntry(deviceId: 1, platform: 'android', addedAtMs: 1),
          ],
        ),
      );
      expect(
        verifyDeviceListSignature(
          dakPubSerialized: base64Decode(payload['dakPub'] as String),
          canonicalBytes: base64Decode(update['listCanonical'] as String),
          signature: base64Decode(update['listSignature'] as String),
        ),
        isTrue,
      );
    });
  });

  group('cross-construction rejection (falsification 25)', () {
    late DeviceAuthorityEngine engine;
    late Map<String, dynamic> payload;
    late Uint8List dakPub;
    late Uint8List enrollmentSig;
    late Uint8List listSig;
    late Uint8List canonical;

    setUp(() {
      engine = DeviceAuthorityEngine();
      payload = mint(engine);
      dakPub = base64Decode(payload['dakPub'] as String);
      enrollmentSig = base64Decode(payload['enrollmentSig'] as String);
      listSig = base64Decode(payload['listSignature'] as String);
      canonical = base64Decode(payload['listCanonical'] as String);
    });

    test('an enrollment signature is rejected by the list verifier', () {
      expect(
        verifyDeviceListSignature(
          dakPubSerialized: dakPub,
          canonicalBytes: canonical,
          signature: enrollmentSig,
        ),
        isFalse,
      );
      // Even verified against the key that MADE it (IK), the context differs.
      expect(
        verifyDeviceListSignature(
          dakPubSerialized: identityPub,
          canonicalBytes: canonical,
          signature: enrollmentSig,
        ),
        isFalse,
      );
    });

    test('a list signature is rejected by the enrollment verifier', () {
      expect(
        verifyEnrollmentSignature(
          identityPubSerialized: identityPub,
          userId: userId,
          dakPubSerialized: dakPub,
          createdAtMs: createdAtMs,
          signature: listSig,
        ),
        isFalse,
      );
      expect(
        verifyEnrollmentSignature(
          identityPubSerialized: dakPub,
          userId: userId,
          dakPubSerialized: dakPub,
          createdAtMs: createdAtMs,
          signature: listSig,
        ),
        isFalse,
      );
    });

    test(
      'a §6.1 registration-lock signature is rejected by both verifiers',
      () {
        // The FROZEN §6.1 layout: newIK(33, leading 0x05) ‖ utf8(userId) ‖
        // nonce(32) — no context prefix, first byte 0x05 by construction.
        final nonce = Uint8List.fromList(List<int>.generate(32, (i) => i));
        final lockMessage = Uint8List.fromList([
          ...identityPub,
          ...utf8.encode('$userId'),
          ...nonce,
        ]);
        final lockSig = Curve.calculateSignature(
          identity.getPrivateKey(),
          Uint8List.fromList(lockMessage),
        );

        expect(
          verifyEnrollmentSignature(
            identityPubSerialized: identityPub,
            userId: userId,
            dakPubSerialized: dakPub,
            createdAtMs: createdAtMs,
            signature: lockSig,
          ),
          isFalse,
        );
        expect(
          verifyDeviceListSignature(
            dakPubSerialized: identityPub,
            canonicalBytes: canonical,
            signature: lockSig,
          ),
          isFalse,
        );
      },
    );

    test('context prefixes are disjoint and never 0x05-leading', () {
      expect(kEnrollContext.codeUnitAt(0), isNot(0x05));
      expect(kListContext.codeUnitAt(0), isNot(0x05));
      expect(kDakRotateContext.codeUnitAt(0), isNot(0x05));
      expect(kEnrollContext, isNot(kListContext));
      expect(kEnrollContext.endsWith('\x00'), isTrue);
      expect(kListContext.endsWith('\x00'), isTrue);
    });
  });

  group('verifyPeerDeviceList (I7 chain)', () {
    test('accepts a server-shaped answer and returns the parsed list', () {
      final payload = mint(DeviceAuthorityEngine());
      final result = DeviceAuthorityEngine.verifyPeerDeviceList(
        authorization: authorizationOf(payload),
        tofuIdentityKeyBase64: base64Encode(identityPub),
        expectedUserId: userId,
      );
      expect(result.ok, isTrue, reason: 'reason=${result.reason}');
      expect(result.deviceList!.version, 1);
      expect(result.deviceList!.devices.single.deviceId, 1);
    });

    test('rejects a single flipped canonical byte (byte-exact, fals. 23)', () {
      final payload = mint(DeviceAuthorityEngine());
      final canonical = base64Decode(payload['listCanonical'] as String);
      canonical[canonical.length - 3] ^= 0x01;
      final result = DeviceAuthorityEngine.verifyPeerDeviceList(
        authorization: {
          ...authorizationOf(payload),
          'listCanonical': base64Encode(canonical),
        },
        tofuIdentityKeyBase64: base64Encode(identityPub),
        expectedUserId: userId,
      );
      expect(result.ok, isFalse);
      expect(result.reason, 'invalid_list_signature');
    });

    test('rejects an IK-signed list (falsification 2, client half)', () {
      final payload = mint(DeviceAuthorityEngine());
      final canonical = base64Decode(payload['listCanonical'] as String);
      final ikListSig = Curve.calculateSignature(
        identity.getPrivateKey(),
        buildDeviceListMessage(canonical),
      );
      final result = DeviceAuthorityEngine.verifyPeerDeviceList(
        authorization: {
          ...authorizationOf(payload),
          'listSignature': base64Encode(ikListSig),
        },
        tofuIdentityKeyBase64: base64Encode(identityPub),
        expectedUserId: userId,
      );
      expect(result.ok, isFalse);
      expect(result.reason, 'invalid_list_signature');
    });

    test('rejects the wrong TOFU identity (forged enrollment)', () {
      final payload = mint(DeviceAuthorityEngine());
      final otherIdentity = generateIdentityKeyPair();
      final result = DeviceAuthorityEngine.verifyPeerDeviceList(
        authorization: authorizationOf(payload),
        tofuIdentityKeyBase64: base64Encode(
          otherIdentity.getPublicKey().serialize(),
        ),
        expectedUserId: userId,
      );
      expect(result.ok, isFalse);
      expect(result.reason, 'invalid_enrollment_signature');
    });

    test('flags a rollback against the pinned version (falsification 3)', () {
      final payload = mint(DeviceAuthorityEngine());
      final result = DeviceAuthorityEngine.verifyPeerDeviceList(
        authorization: authorizationOf(payload),
        tofuIdentityKeyBase64: base64Encode(identityPub),
        expectedUserId: userId,
        previousVersion: 2,
      );
      expect(result.ok, isFalse);
      expect(result.reason, 'version_rollback');
    });

    test('rejects a listVersion field disagreeing with the canonical', () {
      final payload = mint(DeviceAuthorityEngine());
      final result = DeviceAuthorityEngine.verifyPeerDeviceList(
        authorization: {...authorizationOf(payload), 'listVersion': 2},
        tofuIdentityKeyBase64: base64Encode(identityPub),
        expectedUserId: userId,
      );
      expect(result.ok, isFalse);
      expect(result.reason, 'version_mismatch');
    });

    test('rejects a list replayed onto a different user', () {
      final payload = mint(DeviceAuthorityEngine());
      final result = DeviceAuthorityEngine.verifyPeerDeviceList(
        authorization: authorizationOf(payload),
        tofuIdentityKeyBase64: base64Encode(identityPub),
        expectedUserId: userId + 1,
      );
      expect(result.ok, isFalse);
      expect(result.reason, 'invalid_enrollment_signature');
    });

    test('fails closed on a malformed answer', () {
      final result = DeviceAuthorityEngine.verifyPeerDeviceList(
        authorization: {'dakPub': 42},
        tofuIdentityKeyBase64: base64Encode(identityPub),
        expectedUserId: userId,
      );
      expect(result.ok, isFalse);
      expect(result.reason, 'malformed_answer');
    });

    test('does not mutate caller-supplied buffers (library caveat)', () {
      final payload = mint(DeviceAuthorityEngine());
      final canonical = base64Decode(payload['listCanonical'] as String);
      final signature = base64Decode(payload['listSignature'] as String);
      final dakPub = base64Decode(payload['dakPub'] as String);
      final canonicalCopy = Uint8List.fromList(canonical);
      final signatureCopy = Uint8List.fromList(signature);
      final dakPubCopy = Uint8List.fromList(dakPub);

      expect(
        verifyDeviceListSignature(
          dakPubSerialized: dakPub,
          canonicalBytes: canonical,
          signature: signature,
        ),
        isTrue,
      );
      expect(canonical, canonicalCopy);
      expect(signature, signatureCopy);
      expect(dakPub, dakPubCopy);
      // Verifying twice must give the same verdict — a mutated buffer would
      // flip it.
      expect(
        verifyDeviceListSignature(
          dakPubSerialized: dakPub,
          canonicalBytes: canonical,
          signature: signature,
        ),
        isTrue,
      );
    });
  });

  group('enroll over an injected transport', () {
    test('accepted ack keeps the DAK; refusal retires it', () async {
      final engine = DeviceAuthorityEngine();
      Map<String, dynamic>? seen;
      final accepted = await engine.enroll(
        userId: userId,
        identity: identity,
        createdAtMs: createdAtMs,
        send: (payload) async {
          seen = payload;
          return {'success': true, 'listVersion': 1};
        },
      );
      expect(accepted.accepted, isTrue);
      expect(engine.dakPubSerialized, isNotNull);
      expect(
        seen!.keys,
        containsAll([
          'dakPub',
          'enrollmentSig',
          'createdAt',
          'listCanonical',
          'listSignature',
        ]),
      );

      final refused = await engine.enroll(
        userId: userId,
        identity: identity,
        createdAtMs: createdAtMs,
        send: (_) async => {'success': false, 'error': 'already_enrolled'},
      );
      expect(refused.accepted, isFalse);
      expect(refused.error, 'already_enrolled');
      expect(
        engine.dakPubSerialized,
        isNull,
        reason: 'a refused enrollment must not leave a live DAK behind',
      );
    });
  });
}
