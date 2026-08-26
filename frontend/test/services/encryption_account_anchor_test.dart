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

  test('a pre-existing device-1 pin is ADOPTED as the account pin (upgrade path)', () async {
    final accountKey = freshKey();
    // Every install that predates this change has ONLY the per-device rows.
    // Losing their anchor on upgrade would fail-close every conversation at
    // once, which is far worse than the bug being fixed.
    await peerStore.saveIdentity(SignalProtocolAddress('$peerId', 1), accountKey);
    // Prove the ADOPTION, not just the read: with the legacy row deleted the
    // anchor must survive, which it only can if the fallback wrote it through.
    expect(await service.peerTofuIdentityBase64(peerId), b64(accountKey));
    await const FlutterSecureStorage().delete(
      key: 'e2e_17_trusted_identity_${peerId}_1',
    );

    expect(
      await service.peerTofuIdentityBase64(peerId),
      b64(accountKey),
      reason: 'the fallback must ADOPT the legacy key, not re-read it forever',
    );
  });

  test('an established anchor is NOT moved by a newly accepted key', () async {
    final accountKey = freshKey();
    final injected = freshKey();
    await peerStore.saveIdentity(SignalProtocolAddress('$peerId', 1), accountKey);
    expect(await service.peerTofuIdentityBase64(peerId), b64(accountKey));

    // The receive path has no (xxxix) bundle check, and TOFU auto-accepts every
    // rotation, so one injected ciphertext from a device the peer's list
    // legitimately names reaches here. If that moved the anchor, the peer's
    // REAL list would stop verifying — the very lockout this amendment cures,
    // and it would not self-heal, because an unchanged key never re-writes.
    await peerStore.isTrustedIdentity(
      SignalProtocolAddress('$peerId', 9),
      injected,
      Direction.receiving,
    );

    expect(
      await service.peerTofuIdentityBase64(peerId),
      b64(accountKey),
      reason: 'the anchor must never move without a human acknowledgement',
    );
  });

  test('acknowledgement is what advances the anchor', () async {
    final oldKey = freshKey();
    final newKey = freshKey();
    await peerStore.saveIdentity(SignalProtocolAddress('$peerId', 1), oldKey);
    await service.peerTofuIdentityBase64(peerId);

    // Their §6.2 reset: new identity on a device id we have never seen.
    await peerStore.isTrustedIdentity(
      SignalProtocolAddress('$peerId', 4),
      newKey,
      Direction.receiving,
    );
    await service.recordPeerIdentityChangedFromServer(peerId);
    expect(
      await service.peerTofuIdentityBase64(peerId),
      b64(oldKey),
      reason: 'before acknowledgement the anchor holds',
    );

    await service.acknowledgePeerIdentity(peerId);

    expect(
      await service.peerTofuIdentityBase64(peerId),
      b64(newKey),
      reason:
          'without this the peer stays unverifiable for good — the anchor must '
          'advance, but only at a moment the user actually saw',
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
