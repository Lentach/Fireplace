// The I7 chain anchor is an ACCOUNT property, not a device-1 property
// (spec §12 amendment (xlvi)).
//
// A peer's device list is verified against "the account identity key THIS
// device has accepted for that peer". Reading it from a fixed
// `(peer, device 1)` address was a category error: §3 gives one identity key
// per ACCOUNT, shared to every linked device, and ids are never reused ((a)).
// A peer who completes a §6.2 reset therefore has NO device 1 — so the anchor
// lookup found their pre-reset key, or nothing, and their freshly re-enrolled
// list could never verify. T10 restored the list; this restores the ability to
// CHECK it.

import 'dart:convert';

import 'package:fireplace/services/encryption/signal_stores.dart';
import 'package:fireplace/services/encryption_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secure = FlutterSecureStorage();
  const peerId = 42;

  late EncryptionService service;
  late SecureIdentityKeyStore peerStore;

  /// A distinct identity key, standing in for a peer account's IK.
  IdentityKey freshKey() =>
      generateIdentityKeyPair().getPublicKey();

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    service = EncryptionService();
    await service.initialize(17, checkServerBundleExists: () async => false);
    peerStore = SecureIdentityKeyStore(DualStorage(secure), 'e2e_17_');
  });

  String b64(IdentityKey k) => base64Encode(k.serialize());

  test('anchors on a peer device that is NOT device 1', () async {
    final accountKey = freshKey();
    // The post-§6.2 shape: the peer's only live device is a freshly allocated
    // id, and device 1 was revoked and will never be reused.
    await peerStore.saveIdentity(SignalProtocolAddress('$peerId', 3), accountKey);

    expect(
      await service.peerTofuIdentityBase64(peerId),
      b64(accountKey),
      reason:
          'the anchor is the ACCOUNT identity; a peer with no device 1 must '
          'still be verifiable, or their reset locks us out of them forever',
    );
  });

  test('a pre-existing device-1 pin still anchors (upgrade path)', () async {
    final accountKey = freshKey();
    // Every install that predates this change has ONLY the per-device rows.
    // Losing their anchor on upgrade would fail-close every conversation at
    // once, which is far worse than the bug being fixed.
    await peerStore.saveIdentity(SignalProtocolAddress('$peerId', 1), accountKey);

    expect(await service.peerTofuIdentityBase64(peerId), b64(accountKey));
  });

  test('the account pin FOLLOWS the peer through an identity change', () async {
    final oldKey = freshKey();
    final newKey = freshKey();
    await peerStore.saveIdentity(SignalProtocolAddress('$peerId', 1), oldKey);
    // Their reset: new identity, new device id, and device 1 is gone. The
    // stale device-1 row must not out-vote the key we have since accepted.
    await peerStore.saveIdentity(SignalProtocolAddress('$peerId', 4), newKey);

    expect(
      await service.peerTofuIdentityBase64(peerId),
      b64(newKey),
      reason: 'anchoring on the revoked device would refuse the current list',
    );
  });

  test('no pin at all is still null — first contact stays fail-closed', () async {
    // Irreducible TOFU. The caller renders "cannot verify"; it must never
    // invent an anchor.
    expect(await service.peerTofuIdentityBase64(peerId), isNull);
  });

  // --- clause 2: an account-level change must not arrive in silence -------

  test('a NEW device carrying a DIFFERENT identity reports a change', () async {
    final changed = <String>[];
    peerStore.onIdentityChanged = (a) => changed.add(a.getName());
    await peerStore.saveIdentity(SignalProtocolAddress('$peerId', 1), freshKey());

    // The dangerous shape: per-ADDRESS this is first contact, so the old
    // per-device rule stayed quiet — exactly how a peer's reset, or a server
    // introducing a device under an identity of its own choosing, could slip
    // past unannounced.
    await peerStore.isTrustedIdentity(
      SignalProtocolAddress('$peerId', 7),
      freshKey(),
      Direction.receiving,
    );

    expect(
      changed,
      ['$peerId'],
      reason:
          'the account identity changed even though this ADDRESS is new; '
          'silence here is what §6.2 promises never to do',
    );
  });

  test('a NEW device carrying the SAME identity is silent', () async {
    final accountKey = freshKey();
    final changed = <String>[];
    peerStore.onIdentityChanged = (a) => changed.add(a.getName());
    await peerStore.saveIdentity(SignalProtocolAddress('$peerId', 1), accountKey);

    // An ordinary link. Alarming here would train people to dismiss the one
    // surface that detects a real takeover.
    await peerStore.isTrustedIdentity(
      SignalProtocolAddress('$peerId', 2),
      accountKey,
      Direction.receiving,
    );

    expect(changed, isEmpty);
  });
}
