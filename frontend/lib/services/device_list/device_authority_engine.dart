// Device-authorization engine (multi-device spec §3/§5.2, Phase 2 T2).
//
// Owns the T2 slice of the DAK lifecycle that exists BEFORE provisioning:
// mint the DAK keypair, build the IK-signed enrollment record E, author and
// DAK-sign the canonical v1 device list (the current device set — device 1
// until T3 links anything), emit the enrollment, and verify a PEER's signed
// list along the I7 chain (their TOFU'd IK → E → DAK → list → version).
//
// Signature domain separation (spec §12 Stage-0 amendment (d), NORMATIVE):
// every construction carries an ASCII context prefix whose first byte ≠ 0x05,
// so nothing here can ever reinterpret as the frozen §6.1 registration-lock
// layout (33-byte 0x05-leading key first) or as each other:
//
//   E    = sig_IK ("fp-enroll-v1\0" ‖ utf8(userId) ‖ dakPub ‖ utf8(createdAtMs))
//   list = sig_DAK("fp-list-v1\0"   ‖ listCanonical bytes)
//
// Falsification 25: a signature minted for any one construction is REJECTED
// by every other construction's verifier — pinned in this module's unit tests
// and, cross-language, by the backend's Dart-generated vector spec.
//
// T3 handover point (NO user-facing surface here by design, exactly like the
// §6.1 signature path precedent): production enrollment happens when the user
// enables linking (spec §8 — no DAK exists before that), which is T3's
// provisioning UI. Until then the wire harness is the production-shaped
// caller of [enroll], and the minted DAK lives in this engine instance's
// memory — persisting it in platform Keystore is T3's job, alongside wiring
// [SocketService] as the transport. The staleness-bounce consumption point of
// [verifyPeerDeviceList] (deviceListStale re-verify before resend, §5.2) is
// T4/T5 territory and lands with envelope sends.
//
// Library caveat honored everywhere below: `Curve.calculateSignature` and
// `Curve.verifySignature` MUTATE the buffers they are handed — every retained
// key/message/signature is passed as a fresh copy.

import 'dart:convert';

import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:flutter/foundation.dart';

import 'device_list_canonical.dart';

/// Context prefix of the enrollment record E (amendment (d)).
const String kEnrollContext = 'fp-enroll-v1\x00';

/// Context prefix of the signed device list (amendment (d)).
const String kListContext = 'fp-list-v1\x00';

/// Context prefix of a DAK rotation (§6.3). Reserved here so the three
/// domains are declared in one place; the rotation construction itself is
/// T3/T6 and is deliberately NOT built in T2.
const String kDakRotateContext = 'fp-dak-rotate-v1\x00';

/// Serialized Curve25519 public keys are 33 bytes with a leading 0x05.
const int kSerializedPublicKeyLength = 33;

/// Exact bytes the identity key signs for the enrollment record E.
Uint8List buildEnrollmentMessage({
  required int userId,
  required Uint8List dakPubSerialized,
  required int createdAtMs,
}) {
  if (dakPubSerialized.length != kSerializedPublicKeyLength) {
    throw ArgumentError('dakPub must be $kSerializedPublicKeyLength bytes');
  }
  return Uint8List.fromList([
    ...utf8.encode(kEnrollContext),
    ...utf8.encode(userId.toString()),
    ...dakPubSerialized,
    ...utf8.encode(createdAtMs.toString()),
  ]);
}

/// Exact bytes the DAK signs for the device list: context ‖ canonical bytes.
Uint8List buildDeviceListMessage(Uint8List canonicalBytes) =>
    Uint8List.fromList([...utf8.encode(kListContext), ...canonicalBytes]);

/// Fails closed: any malformed input or thrown error is a rejection.
bool _verify({
  required Uint8List signerPubSerialized,
  required Uint8List message,
  required Uint8List signature,
}) {
  if (signerPubSerialized.length != kSerializedPublicKeyLength ||
      signature.length != 64) {
    return false;
  }
  try {
    // decodePoint copies the key bytes; message/signature copies keep the
    // library's in-place sign-bit stripping off caller-owned buffers.
    final key = Curve.decodePoint(Uint8List.fromList(signerPubSerialized), 0);
    return Curve.verifySignature(
      key,
      Uint8List.fromList(message),
      Uint8List.fromList(signature),
    );
  } catch (_) {
    return false;
  }
}

/// Verifies the enrollment record E against an identity key (I7 chain link
/// IK → E → DAK).
bool verifyEnrollmentSignature({
  required Uint8List identityPubSerialized,
  required int userId,
  required Uint8List dakPubSerialized,
  required int createdAtMs,
  required Uint8List signature,
}) {
  if (dakPubSerialized.length != kSerializedPublicKeyLength) return false;
  return _verify(
    signerPubSerialized: identityPubSerialized,
    message: buildEnrollmentMessage(
      userId: userId,
      dakPubSerialized: dakPubSerialized,
      createdAtMs: createdAtMs,
    ),
    signature: signature,
  );
}

/// Verifies the device-list signature against a DAK (chain link DAK → list).
/// [canonicalBytes] MUST be the received bytes verbatim — never re-serialized
/// (falsification 23).
bool verifyDeviceListSignature({
  required Uint8List dakPubSerialized,
  required Uint8List canonicalBytes,
  required Uint8List signature,
}) => _verify(
  signerPubSerialized: dakPubSerialized,
  message: buildDeviceListMessage(canonicalBytes),
  signature: signature,
);

/// Outcome of a wire enrollment attempt.
class DeviceEnrollmentResult {
  const DeviceEnrollmentResult({required this.accepted, this.error});

  final bool accepted;

  /// Server refusal code (`already_enrolled`, `invalid_enrollment_signature`,
  /// …) when [accepted] is false.
  final String? error;
}

/// Outcome of [DeviceAuthorityEngine.verifyPeerDeviceList].
class PeerDeviceListVerification {
  const PeerDeviceListVerification._(this.ok, this.reason, this.deviceList);

  const PeerDeviceListVerification.failure(String reason)
    : this._(false, reason, null);

  const PeerDeviceListVerification.success(DeviceList list)
    : this._(true, null, list);

  final bool ok;

  /// Stable failure code: `malformed_answer`, `invalid_enrollment_signature`,
  /// `invalid_list_signature`, `invalid_canonical`, `user_mismatch`,
  /// `version_mismatch`, or `version_rollback` (the loud flag of
  /// falsification 3 — the caller renders the identity-changed surface for
  /// it; that surface itself lands with the T4/T5 consumption point).
  final String? reason;

  final DeviceList? deviceList;
}

/// Mints and holds the account's device authorization (T2 slice).
class DeviceAuthorityEngine {
  /// Private half lives ONLY here (in memory — Keystore persistence is T3).
  ECKeyPair? _dakPair;

  /// Serialized DAK public key, available after [mintEnrollment].
  Uint8List? get dakPubSerialized => _dakPair?.publicKey.serialize();

  /// Builds the complete enrollment wire payload: fresh DAK, enrollment
  /// record E signed by [identity], and the DAK-signed canonical v1 list of
  /// the CURRENT device set — device 1 only, until T3 links devices.
  Map<String, dynamic> mintEnrollment({
    required int userId,
    required IdentityKeyPair identity,
    required int createdAtMs,
    String platform = 'android',
  }) {
    final dakPair = Curve.generateKeyPair();
    _dakPair = dakPair;
    final dakPub = dakPair.publicKey.serialize();

    final enrollmentSig = Curve.calculateSignature(
      identity.getPrivateKey(),
      // calculateSignature mutates its message buffer — hand it its own copy.
      buildEnrollmentMessage(
        userId: userId,
        dakPubSerialized: dakPub,
        createdAtMs: createdAtMs,
      ),
    );

    final listUpdate = signList(
      DeviceList(
        userId: userId,
        version: 1,
        devices: [
          DeviceListEntry(
            deviceId: 1,
            platform: platform,
            addedAtMs: createdAtMs,
          ),
        ],
      ),
    );

    return {
      'dakPub': base64Encode(dakPub),
      'enrollmentSig': base64Encode(enrollmentSig),
      'createdAt': createdAtMs,
      ...listUpdate,
    };
  }

  /// DAK-signs [list] and returns the `{listCanonical, listSignature}` wire
  /// fields — the payload shape of every later list mutation (`version` > 1).
  Map<String, dynamic> signList(DeviceList list) {
    final dakPair = _dakPair;
    if (dakPair == null) {
      throw StateError('no DAK minted — call mintEnrollment first');
    }
    final canonical = encodeCanonicalDeviceList(list);
    final signature = Curve.calculateSignature(
      dakPair.privateKey,
      buildDeviceListMessage(canonical),
    );
    return {
      'listCanonical': base64Encode(canonical),
      'listSignature': base64Encode(signature),
    };
  }

  /// DAK-signs ARBITRARY canonical-slot bytes, bypassing the writer's
  /// constraints. Falsification tooling only (23/25 need a correctly-signed
  /// but malformed canonical to prove the server rejects it AT PARSE);
  /// production list mutations go through [signList].
  @visibleForTesting
  Uint8List debugSignCanonicalBytes(Uint8List canonicalBytes) {
    final dakPair = _dakPair;
    if (dakPair == null) {
      throw StateError('no DAK minted — call mintEnrollment first');
    }
    return Curve.calculateSignature(
      dakPair.privateKey,
      buildDeviceListMessage(canonicalBytes),
    );
  }

  /// Runs one wire enrollment through the injected [send] transport (emit
  /// `enrollDeviceAuthority`, await `deviceAuthorityEnrolled`) and interprets
  /// the acknowledgement. The harness supplies the real socket round trip;
  /// T3's enable-linking flow becomes the production caller.
  Future<DeviceEnrollmentResult> enroll({
    required int userId,
    required IdentityKeyPair identity,
    required Future<Map<String, dynamic>> Function(Map<String, dynamic> payload)
    send,
    int? createdAtMs,
    String platform = 'android',
  }) async {
    final payload = mintEnrollment(
      userId: userId,
      identity: identity,
      createdAtMs: createdAtMs ?? DateTime.now().millisecondsSinceEpoch,
      platform: platform,
    );
    final answer = await send(payload);
    if (answer['success'] == true) {
      return const DeviceEnrollmentResult(accepted: true);
    }
    // A refusal retires the minted DAK: it authorized nothing, and keeping it
    // around invites signing a list the server never pinned an E for.
    _dakPair = null;
    return DeviceEnrollmentResult(
      accepted: false,
      error: answer['error'] is String ? answer['error'] as String : 'refused',
    );
  }

  /// Verifies a peer's `getDeviceList` answer along the I7 chain:
  /// their TOFU'd IK → E → DAK → list signature → strict canonical parse →
  /// version, byte-exact on `listCanonical` throughout (falsification 23:
  /// signature and parse both run over the received bytes verbatim).
  ///
  /// [previousVersion] is the last version this client pinned for the peer;
  /// an answer at or below it is `version_rollback` (falsification 3).
  static PeerDeviceListVerification verifyPeerDeviceList({
    required Map<String, dynamic> authorization,
    required String tofuIdentityKeyBase64,
    required int expectedUserId,
    int? previousVersion,
  }) {
    final Uint8List identityPub;
    final Uint8List dakPub;
    final Uint8List enrollmentSig;
    final Uint8List listSignature;
    final Uint8List canonicalBytes;
    final int createdAtMs;
    final int listVersion;
    try {
      identityPub = base64Decode(tofuIdentityKeyBase64);
      dakPub = base64Decode(authorization['dakPub'] as String);
      enrollmentSig = base64Decode(authorization['enrollmentSig'] as String);
      listSignature = base64Decode(authorization['listSignature'] as String);
      canonicalBytes = base64Decode(authorization['listCanonical'] as String);
      createdAtMs = authorization['enrollmentCreatedAt'] as int;
      listVersion = authorization['listVersion'] as int;
    } catch (_) {
      return const PeerDeviceListVerification.failure('malformed_answer');
    }

    if (!verifyEnrollmentSignature(
      identityPubSerialized: identityPub,
      userId: expectedUserId,
      dakPubSerialized: dakPub,
      createdAtMs: createdAtMs,
      signature: enrollmentSig,
    )) {
      return const PeerDeviceListVerification.failure(
        'invalid_enrollment_signature',
      );
    }

    if (!verifyDeviceListSignature(
      dakPubSerialized: dakPub,
      canonicalBytes: canonicalBytes,
      signature: listSignature,
    )) {
      return const PeerDeviceListVerification.failure('invalid_list_signature');
    }

    final DeviceList list;
    try {
      list = parseCanonicalDeviceList(canonicalBytes);
    } on CanonicalDeviceListException {
      return const PeerDeviceListVerification.failure('invalid_canonical');
    }
    if (list.userId != expectedUserId) {
      return const PeerDeviceListVerification.failure('user_mismatch');
    }
    if (list.version != listVersion) {
      return const PeerDeviceListVerification.failure('version_mismatch');
    }
    if (previousVersion != null && list.version <= previousVersion) {
      return const PeerDeviceListVerification.failure('version_rollback');
    }
    return PeerDeviceListVerification.success(list);
  }
}
