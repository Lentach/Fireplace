// Amendment (lxv) — the (lxiv) recovery must be COMPLETABLE.
//
// Live QA (2026-08-31, Android primary + real-browser web install) proved the
// promised recovery dead-ended at `adoptProvisionedIdentity`'s T3 invariant
// lock: a revoked install that signed back in still holds its dead identity,
// so the SAS-confirmed re-link aborted with `adopt_failed`. The carve-out is
// exactly one shape — the ceremony passes `disposeStaleMaterial: true` — and
// the lock must hold for every other caller.
//
// These tests drive the REAL EncryptionService over mock storage.
//
// Falsification contract: removing the (lxv) disposal branch turns the
// "disposes and adopts" test RED (StateError); removing the lock turns the
// refusal test RED.

import 'dart:convert';

import 'package:fireplace/providers/encryption_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const ownUserId = 7;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  ({String ikPub, String ikPriv, String dakPub}) mintBlobInputs() {
    final pair = generateIdentityKeyPair();
    return (
      ikPub: base64Encode(pair.getPublicKey().serialize()),
      ikPriv: base64Encode(pair.getPrivateKey().serialize()),
      dakPub: base64Encode(List<int>.filled(32, 3)),
    );
  }

  Future<EncryptionProvider> mintedInstall({required int deviceId}) async {
    final provider = EncryptionProvider();
    provider.setEmitCallback((event, data) {
      if (event == 'checkOwnKeyBundle') {
        provider.onOwnKeyBundleStatus({'exists': false});
      }
    });
    provider.setOwnDeviceId(deviceId);
    await provider.initializeE2E(ownUserId);
    await pumpEventQueue(times: 200);
    return provider;
  }

  test('the T3 lock holds: adopting over an existing identity without the '
      '(lxv) authorization refuses', () async {
    await mintedInstall(deviceId: 2);
    final blob = mintBlobInputs();

    final fresh = EncryptionProvider();
    await expectLater(
      fresh.encryptionService.adoptProvisionedIdentity(
        userId: ownUserId,
        ikPubBase64: blob.ikPub,
        ikPrivBase64: blob.ikPriv,
        dakPubBase64: blob.dakPub,
      ),
      throwsStateError,
    );
  });

  test('the (lxv) carve-out: a ceremony-authorized adopt disposes the stale '
      'material and installs the blob identity', () async {
    final life1 = await mintedInstall(deviceId: 2);
    final staleIdentity = await life1.encryptionService
        .currentIdentityPublicKeyBase64();
    expect(staleIdentity, isNotNull);
    final staleSlots = await const FlutterSecureStorage().readAll();
    final stalePairSlot = staleSlots['e2e_${ownUserId}_identity_key_pair'];
    final staleRecordSlot = staleSlots['e2e_${ownUserId}_identity_record_v1'];

    final blob = mintBlobInputs();
    final fresh = EncryptionProvider();
    await fresh.encryptionService.adoptProvisionedIdentity(
      userId: ownUserId,
      ikPubBase64: blob.ikPub,
      ikPrivBase64: blob.ikPriv,
      dakPubBase64: blob.dakPub,
      disposeStaleMaterial: true,
    );

    // The installed identity is the BLOB's, not the stale one.
    final adopted = await fresh.encryptionService
        .currentIdentityPublicKeyBase64();
    expect(adopted, blob.ikPub);
    expect(adopted, isNot(staleIdentity));

    // Whatever identity slot shape the store persists, it must no longer hold
    // the STALE bytes — the disposal ran and the adopt overwrote the slot.
    final all = await const FlutterSecureStorage().readAll();
    if (stalePairSlot != null) {
      expect(all['e2e_${ownUserId}_identity_key_pair'], isNot(stalePairSlot),
          reason: 'stale legacy identity slot must not survive the disposal');
    }
    if (staleRecordSlot != null) {
      expect(all['e2e_${ownUserId}_identity_record_v1'], isNot(staleRecordSlot),
          reason: 'stale atomic identity record must not survive the disposal');
    }
  });

  test('a malformed blob fails BEFORE the disposal wipes anything', () async {
    await mintedInstall(deviceId: 2);
    final before = await const FlutterSecureStorage().readAll();
    final staleSignalSlots = {
      for (final e in before.entries)
        if (e.key.startsWith('e2e_${ownUserId}_') &&
            (e.key.contains('identity_') ||
                e.key.contains('pre_key_') ||
                e.key.contains('signed_pre_key_')))
          e.key: e.value,
    };
    expect(staleSignalSlots, isNotEmpty);

    final fresh = EncryptionProvider();
    await expectLater(
      fresh.encryptionService.adoptProvisionedIdentity(
        userId: ownUserId,
        ikPubBase64: 'not-base64!!',
        ikPrivBase64: 'also-not-base64!!',
        dakPubBase64: 'nope',
        disposeStaleMaterial: true,
      ),
      throwsA(anything),
    );

    // The stale material must still be byte-identical: the wipe is only
    // justified by an adopt that can actually follow it.
    final after = await const FlutterSecureStorage().readAll();
    for (final e in staleSignalSlots.entries) {
      expect(after[e.key], e.value,
          reason: 'a bad blob must not strand the install keyless '
              '(lost ${e.key})');
    }
  });
}
