import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import 'package:fireplace/services/device_list/device_authority_engine.dart';
import 'package:fireplace/services/device_list/device_list_cache.dart';
import 'package:fireplace/services/device_list/device_list_canonical.dart';
import 'package:fireplace/services/encryption/signal_stores.dart';
import 'package:fireplace/services/encryption_service.dart';

/// ON-DEVICE acceptance for amendments (xlviii) and (xlix): real Android
/// Keystore-backed secure storage and the real SharedPreferences XML, not
/// mocks.
///
///   cd frontend && flutter test integration_test -d `emulator id`
///
/// WHY THIS EXISTS SEPARATELY FROM THE UNIT TESTS. Every property here is a
/// PERSISTENCE property, and the unit suite proves them against
/// `SharedPreferences.setMockInitialValues` — an in-memory map. That mock
/// cannot fail the way a real device fails: a key that exceeds a platform
/// limit, a value that does not survive a genuinely new process, a
/// Keystore-backed read that returns null on a cold start. A recovery the user
/// completed has to survive an app kill on a REAL phone, so it is verified on
/// one. `EncryptionService` is constructed twice against the same on-device
/// storage; the second construction is the relaunch.
///
/// Each test uses a distinct peer id namespace so a rerun on a dirty device
/// cannot make an assertion pass for the wrong reason.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final runId = DateTime.now().millisecondsSinceEpoch % 100000;
  final ownUserId = 700000 + runId;

  IdentityKey freshKey() => generateIdentityKeyPair().getPublicKey();

  Future<EncryptionService> serviceFor(int userId) async {
    final service = EncryptionService();
    await service.initialize(userId, checkServerBundleExists: () async => false);
    return service;
  }

  test('rebuild intent survives a REAL relaunch on device storage', () async {
    final peerId = 810000 + runId;
    final first = await serviceFor(ownUserId);

    // Pin an anchor for the peer the way first contact does, so the identity
    // warning is legitimate and the acknowledgement has something to re-affirm.
    final store = SecureIdentityKeyStore(
      DualStorage(const FlutterSecureStorage()),
      'e2e_${ownUserId}_',
    );
    final peerKey = freshKey();
    await store.saveIdentity(SignalProtocolAddress('$peerId', 1), peerKey);

    await first.recordPeerIdentityChangedFromServer(peerId);
    expect(first.peersWithChangedIdentity, contains(peerId));

    await first.recordSessionRebuilds(peerId, const [1, 4]);
    final advanced = await first.acknowledgePeerIdentity(
      peerId,
      adoptIdentityBase64: base64Encode(peerKey.serialize()),
    );
    expect(advanced, isTrue, reason: 're-affirming the pinned key resolves it');

    // RELAUNCH: a brand new service over the same real device storage.
    final second = await serviceFor(ownUserId);
    expect(
      second.pendingSessionRebuilds,
      containsAll(<(int, int)>[(peerId, 1), (peerId, 4)]),
      reason:
          'the poisoned sessions must still be scheduled after a cold start, '
          'or the next send silently encrypts to the replaced identity',
    );
    // The warning is genuinely gone, which is what makes the intent the ONLY
    // remaining repair path and therefore load-bearing.
    expect(second.peersWithChangedIdentity, isNot(contains(peerId)));

    // Satisfying it is also durable.
    await second.clearSessionRebuild(peerId, 1);
    final third = await serviceFor(ownUserId);
    expect(third.pendingSessionRebuilds, isNot(contains((peerId, 1))));
    expect(third.pendingSessionRebuilds, contains((peerId, 4)));
  });

  test('rollback pin survives a REAL relaunch and still refuses an older list',
      () async {
    final peerId = 820000 + runId;
    final first = await serviceFor(ownUserId);

    final engine = DeviceAuthorityEngine();
    final identity = generateIdentityKeyPair();
    final enrollment = engine.mintEnrollment(
      userId: peerId,
      identity: identity,
      createdAtMs: 1234567890,
    );
    final tofu = base64Encode(identity.getPublicKey().serialize());

    Map<String, dynamic> authorizationAt(int version) {
      final signed = engine.signList(
        DeviceList(
          userId: peerId,
          version: version,
          devices: [
            DeviceListEntry(
              deviceId: version,
              platform: 'android',
              addedAtMs: 1000 * version,
            ),
          ],
        ),
      );
      return {
        'dakPub': enrollment['dakPub'],
        'enrollmentSig': enrollment['enrollmentSig'],
        'enrollmentCreatedAt': enrollment['createdAt'],
        'listVersion': version,
        'listSignature': signed['listSignature'],
        'listCanonical': signed['listCanonical'],
      };
    }

    final cache = DeviceListCache();
    cache.onPinAdvanced = (id, version) => first.recordDeviceListPin(id, version);
    cache.adopt(
      userId: peerId,
      authorization: authorizationAt(4),
      tofuIdentityKeyBase64: tofu,
    );
    expect(cache.pinnedVersion(peerId), 4);
    // The hook is fire-and-forget from adopt(); let its write land.
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final second = await serviceFor(ownUserId);
    final revived = DeviceListCache()..seedPins(second.deviceListPins);
    expect(
      revived.pinnedVersion(peerId),
      4,
      reason: 'a cold start must not reopen the rollback window',
    );
    expect(
      () => revived.adopt(
        userId: peerId,
        authorization: authorizationAt(2),
        tofuIdentityKeyBase64: tofu,
      ),
      throwsA(
        isA<DeviceListVerificationException>().having(
          (e) => e.reason,
          'reason',
          'version_rollback',
        ),
      ),
    );
  });

  test('a server identity change for an unknown peer is ignored on device',
      () async {
    final service = await serviceFor(ownUserId);
    final stranger = 830000 + runId;
    await service.recordPeerIdentityChangedFromServer(stranger);
    expect(
      service.peersWithChangedIdentity,
      isNot(contains(stranger)),
      reason: 'no pinned anchor means there was no identity to change',
    );
    // And nothing was persisted for it either.
    final revived = await serviceFor(ownUserId);
    expect(revived.peersWithChangedIdentity, isNot(contains(stranger)));
  });

  test('re-affirming the pin refuses a candidate staged under the dialog',
      () async {
    final peerId = 840000 + runId;
    final service = await serviceFor(ownUserId);
    final store = SecureIdentityKeyStore(
      DualStorage(const FlutterSecureStorage()),
      'e2e_${ownUserId}_',
    );
    final honest = freshKey();
    await store.saveIdentity(SignalProtocolAddress('$peerId', 1), honest);
    await service.recordPeerIdentityChangedFromServer(peerId);

    // The attacker's key reaches the candidate slot while the ceremony is open.
    final evil = freshKey();
    await store.stagePendingAccountIdentity('$peerId', evil);

    final advanced = await service.acknowledgePeerIdentity(
      peerId,
      adoptIdentityBase64: base64Encode(honest.serialize()),
    );
    expect(
      advanced,
      isFalse,
      reason: 'the confirmed key is not what is staged; refuse and re-display',
    );
    expect(service.peersWithChangedIdentity, contains(peerId));
    final held = await store.pendingAccountIdentity('$peerId');
    expect(
      held == null ? null : base64Encode(held.serialize()),
      base64Encode(evil.serialize()),
      reason: 'the evidence must survive on real storage too',
    );
  });
}
