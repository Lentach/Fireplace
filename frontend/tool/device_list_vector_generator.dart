// Generates the cross-language regression vectors pinned in
// backend/src/key-bundles/device-list-signature.util.spec.ts (Phase 2 T2,
// spec §3 + §12 amendment (d), falsification 25).
//
// Run from frontend/:  cmd /c dart run tool/device_list_vector_generator.dart
//
// Uses the REAL client signer (libsignal_protocol_dart Curve.calculateSignature)
// over the REAL constructions — enrollment E, the DAK-signed list, and the
// frozen §6.1 registration-lock layout — so the backend spec verifies exactly
// what a real client produces. Keys are minted fresh per run; the pinned
// constants are one recorded run's output (same provenance discipline as the
// §6.1 vector in identity-signature.util.spec.ts).
// ignore_for_file: avoid_print — dev tool; printing the vectors IS the output.

import 'dart:convert';
import 'dart:typed_data';

import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import 'package:fireplace/services/device_list/device_authority_engine.dart';
import 'package:fireplace/services/device_list/device_list_canonical.dart';

void main() {
  const userId = 4242;
  const createdAtMs = 1755600000000;

  final identity = generateIdentityKeyPair();
  final ikPub = identity.getPublicKey().serialize();

  final engine = DeviceAuthorityEngine();
  final enrollPayload = engine.mintEnrollment(
    userId: userId,
    identity: identity,
    createdAtMs: createdAtMs,
  );

  // A later (v2) list signed by the same DAK, for monotonicity tests.
  final v2 = engine.signList(
    const DeviceList(
      userId: userId,
      version: 2,
      devices: [
        DeviceListEntry(
          deviceId: 1,
          platform: 'android',
          addedAtMs: createdAtMs,
          name: 'primary',
        ),
      ],
    ),
  );

  // A frozen §6.1 registration-lock signature by the SAME identity key:
  // newIK(33, leading 0x05) ‖ utf8(userId) ‖ nonce(32) — no context prefix.
  final nonce = Uint8List.fromList(
    List<int>.generate(32, (i) => (i * 7) & 0xff),
  );
  final newIdentity = generateIdentityKeyPair();
  final newIkPub = newIdentity.getPublicKey().serialize();
  final lockSig = Curve.calculateSignature(
    identity.getPrivateKey(),
    Uint8List.fromList([...newIkPub, ...utf8.encode('$userId'), ...nonce]),
  );

  print(
    const JsonEncoder.withIndent('  ').convert({
      'userId': userId,
      'createdAtMs': createdAtMs,
      'identityPublicKey': base64Encode(ikPub),
      'dakPub': enrollPayload['dakPub'],
      'enrollmentSig': enrollPayload['enrollmentSig'],
      'listCanonical': enrollPayload['listCanonical'],
      'listSignature': enrollPayload['listSignature'],
      'v2ListCanonical': v2['listCanonical'],
      'v2ListSignature': v2['listSignature'],
      'lockNewIdentityPublicKey': base64Encode(newIkPub),
      'lockNonce': base64Encode(nonce),
      'lockSignature': base64Encode(lockSig),
    }),
  );
}
