import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fireplace/providers/encryption_provider.dart';
import 'package:fireplace/services/device_link/identity_backup.dart';
import 'package:fireplace/services/device_list/device_list_canonical.dart';
import 'package:fireplace/services/encryption_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/passcode_fakes.dart';

/// The (lxxviii) clause-3 restore state machine, driven over a scripted
/// socket (the emit seam records every event and answers like the server).
///
/// The identity in the backup is REAL: a first EncryptionService mints it,
/// the payload is exported, the mock stores are wiped (the "lost device"),
/// and a second service + provider restore from the sealed blob. The restore
/// proof is verified with real XEdDSA — the exact §6.1 byte layout.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userId = 9;
  const phrase = 'abandon ability able about above absent '
      'absorb abstract absurd abuse access accident';
  const wrongPhrase = 'zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong';

  IdentityBackupCodec codec() =>
      IdentityBackupCodec(kdf: FakePasscodeKdf(), sealer: FakeContentSealer());

  /// Mints a real identity + DAK for [userId], exports the backup payload,
  /// seals it, then WIPES the stores — the state a restoring install is in.
  Future<SealedIdentityBackup> arrangeSealedBackup({bool withDak = true}) async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final original = EncryptionService();
    await original.initialize(
      userId,
      checkServerIdentity: () async =>
          const ServerIdentityGuard(exists: false),
    );
    var payload = await original.exportIdentityForBackup();
    if (withDak) {
      final dakPair = Curve.generateKeyPair();
      payload = IdentityBackupPayload(
        userId: payload.userId,
        identity: payload.identity,
        dak: jsonEncode({
          'userId': userId,
          'dakPub': base64Encode(dakPair.publicKey.serialize()),
          'dakPriv': base64Encode(dakPair.privateKey.serialize()),
          'createdAtMs': 1000,
        }),
      );
    }
    final sealed = await codec().seal(payload, phrase);
    // The lost device: nothing local survives.
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    return sealed;
  }

  /// Provider over a fresh service, `_currentUserId` seeded the way the gate
  /// seeds it (an init pass that could not ask the server).
  Future<EncryptionProvider> buildProvider() async {
    final provider = EncryptionProvider(
      service: EncryptionService(),
      backupCodec: codec(),
    );
    await provider.initializeE2E(userId);
    return provider;
  }

  String oldListCanonicalB64() => base64Encode(
    encodeCanonicalDeviceList(
      const DeviceList(
        userId: userId,
        version: 3,
        devices: [
          DeviceListEntry(deviceId: 1, platform: 'web', addedAtMs: 100),
          DeviceListEntry(deviceId: 2, platform: 'android', addedAtMs: 200),
        ],
      ),
    ),
  );

  test('happy path: nonce → proof upload → rebind → OTPs → list → rebuilds',
      () async {
    final sealed = await arrangeSealedBackup();
    final provider = await buildProvider();
    final nonce = base64Encode(List<int>.generate(24, (i) => i));

    final log = <String>[];
    final payloads = <String, dynamic>{};
    provider.sessionRebuildPeers = () => [11, 22];
    provider.setEmitCallback((event, data) {
      log.add(event);
      payloads[event] = data;
      switch (event) {
        case 'getIdentityBackup':
          scheduleMicrotask(() => provider.onIdentityBackup({
                'exists': true,
                'blob': sealed.blob,
                'salt': sealed.salt,
                'iterations': sealed.iterations,
              }));
        case 'getRegistrationLockNonce':
          scheduleMicrotask(
            () => provider.onRegistrationLockNonce({'nonce': nonce}),
          );
        case 'uploadKeyBundle':
          // The ConnectionProvider contract: adopt + reconnect FIRST, only
          // then deliver the ack (which flushes the OTP stash).
          scheduleMicrotask(() {
            log.add('RECONNECTED');
            provider.onKeyBundleUploaded({
              'success': true,
              'identityChanged': false,
              'restored': true,
              'deviceId': 7,
              'access_token': 'a',
              'refresh_token': 'r',
              'nextListVersion': 4,
            });
          });
        case 'getDeviceList':
          scheduleMicrotask(() => provider.onDeviceList({
                'userId': userId,
                'authorization': {'listCanonical': oldListCanonicalB64()},
              }));
        case 'updateDeviceList':
          scheduleMicrotask(() => provider
              .onDeviceListUpdated({'success': true, 'listVersion': 4}));
      }
    });

    await provider.restoreFromPhrase(phrase);

    expect(provider.restoreStage, IdentityRestoreStage.done);
    expect(provider.restoreFailure, isNull);

    // Order: every stage's wire step in the spec's sequence, and the OTP
    // upload strictly AFTER the reconnect.
    int at(String e) => log.indexOf(e);
    expect(at('getIdentityBackup'), lessThan(at('getRegistrationLockNonce')));
    expect(at('getRegistrationLockNonce'), lessThan(at('uploadKeyBundle')));
    expect(at('uploadKeyBundle'), lessThan(at('RECONNECTED')));
    expect(
      at('RECONNECTED'),
      lessThan(at('uploadOneTimePreKeys')),
      reason: 'OTPs must ride the rebound device id, never the revoked one',
    );
    expect(at('uploadOneTimePreKeys'), lessThan(at('updateDeviceList')));
    expect(at('getDeviceList'), lessThan(at('updateDeviceList')));
    expect(at('updateDeviceList'), lessThan(at('requestSessionRebuild')));
    expect(
      log.where((e) => e == 'requestSessionRebuild'),
      hasLength(2),
      reason: 'one rebuild request per conversation peer',
    );

    // The upload carries the restore proof: real XEdDSA over
    // identityPublicKey ‖ userId ‖ nonce by the RESTORED (unchanged) key.
    final upload = payloads['uploadKeyBundle'] as Map<String, dynamic>;
    expect(upload['nonce'], nonce);
    final identityB64 = upload['identityPublicKey'] as String;
    final identityBytes = base64Decode(identityB64);
    final ok = Curve.verifySignature(
      Curve.decodePoint(Uint8List.fromList(identityBytes), 0),
      Uint8List.fromList([
        ...identityBytes,
        ...utf8.encode('$userId'),
        ...base64Decode(nonce),
      ]),
      Uint8List.fromList(
        base64Decode(upload['restoreSignature'] as String),
      ),
    );
    expect(ok, isTrue, reason: 'F7: the proof must verify under the §6.1 layout');

    // The new list: server-named version, every OLD device tombstoned, the
    // rebound device present and live.
    final signed = payloads['updateDeviceList'] as Map<String, dynamic>;
    final list = parseCanonicalDeviceList(
      base64Decode(signed['listCanonical'] as String),
    );
    expect(list.version, 4);
    expect(list.userId, userId);
    final byId = {for (final d in list.devices) d.deviceId: d};
    expect(byId.keys, containsAll([1, 2, 7]));
    expect(byId[1]!.revokedAtMs, isNotNull);
    expect(byId[2]!.revokedAtMs, isNotNull);
    expect(byId[7]!.revokedAtMs, isNull);
  });

  test('F10: a wrong phrase emits NO nonce request and NO upload', () async {
    final sealed = await arrangeSealedBackup();
    final provider = await buildProvider();

    final log = <String>[];
    provider.setEmitCallback((event, data) {
      log.add(event);
      if (event == 'getIdentityBackup') {
        scheduleMicrotask(() => provider.onIdentityBackup({
              'exists': true,
              'blob': sealed.blob,
              'salt': sealed.salt,
              'iterations': sealed.iterations,
            }));
      }
    });

    await provider.restoreFromPhrase(wrongPhrase);

    expect(provider.restoreStage, IdentityRestoreStage.failed);
    expect(provider.restoreFailure, IdentityRestoreFailure.wrongPhrase);
    expect(log, isNot(contains('getRegistrationLockNonce')));
    expect(log, isNot(contains('uploadKeyBundle')));
  });

  test('exists:false without an error rider is noBackup', () async {
    await arrangeSealedBackup();
    final provider = await buildProvider();
    provider.setEmitCallback((event, data) {
      if (event == 'getIdentityBackup') {
        scheduleMicrotask(() => provider.onIdentityBackup({'exists': false}));
      }
    });
    await provider.restoreFromPhrase(phrase);
    expect(provider.restoreFailure, IdentityRestoreFailure.noBackup);
  });

  test('exists:false with the fail-closed error rider is failed, not noBackup',
      () async {
    await arrangeSealedBackup();
    final provider = await buildProvider();
    provider.setEmitCallback((event, data) {
      if (event == 'getIdentityBackup') {
        scheduleMicrotask(() => provider.onIdentityBackup(
            {'exists': false, 'error': 'backup_failed'}));
      }
    });
    await provider.restoreFromPhrase(phrase);
    expect(provider.restoreFailure, IdentityRestoreFailure.failed);
  });

  test('a restore_refused ack fails as refused, no list mutation', () async {
    final sealed = await arrangeSealedBackup();
    final provider = await buildProvider();
    final log = <String>[];
    provider.setEmitCallback((event, data) {
      log.add(event);
      switch (event) {
        case 'getIdentityBackup':
          scheduleMicrotask(() => provider.onIdentityBackup({
                'exists': true,
                'blob': sealed.blob,
                'salt': sealed.salt,
                'iterations': sealed.iterations,
              }));
        case 'getRegistrationLockNonce':
          scheduleMicrotask(() => provider
              .onRegistrationLockNonce({'nonce': base64Encode([1, 2, 3])}));
        case 'uploadKeyBundle':
          scheduleMicrotask(() => provider.onKeyBundleUploaded(
              {'success': false, 'error': 'restore_refused'}));
      }
    });
    await provider.restoreFromPhrase(phrase);
    expect(provider.restoreStage, IdentityRestoreStage.failed);
    expect(provider.restoreFailure, IdentityRestoreFailure.refused);
    expect(log, isNot(contains('updateDeviceList')));
    expect(log, isNot(contains('requestSessionRebuild')));
  });

  test('hasIdentityBackup parses only an explicit bool', () async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final provider = EncryptionProvider(
      service: EncryptionService(),
      backupCodec: codec(),
    );
    expect(provider.hasIdentityBackup, isNull);
    provider.onOwnKeyBundleStatus({'exists': true});
    expect(provider.hasIdentityBackup, isNull,
        reason: 'an older server must read as UNKNOWN, never false');
    provider.onOwnKeyBundleStatus({'exists': true, 'hasIdentityBackup': false});
    expect(provider.hasIdentityBackup, isFalse);
    provider.onOwnKeyBundleStatus({'exists': true, 'hasIdentityBackup': true});
    expect(provider.hasIdentityBackup, isTrue);
    provider.onOwnKeyBundleStatus({'exists': true});
    expect(provider.hasIdentityBackup, isTrue,
        reason: 'absence must not erase a known answer');
  });

  // The failure a code review caught, and the reason it was severe: the gate
  // that HOSTS this machine's progress and errors is mounted on
  // `needsDeviceLink`. Clearing `identityIncomplete` at adopt showed the shell
  // the instant the identity landed, so a failure in any later stage died on
  // an unmounted widget — invisible — while the freshly minted prekeys were
  // never published and peers kept fetching the stale server bundle.
  test('a failure AFTER adopt keeps the gate up, and the restore retries',
      () async {
    final sealed = await arrangeSealedBackup();
    final nonce = base64Encode(List<int>.generate(24, (i) => i));
    var failUpload = true;
    final log = <String>[];
    // Start from the REAL gated state, not the harness's deferred-init one:
    // no local identity + a server that says a bundle exists is what makes
    // the service refuse to mint, sets `identityIncomplete`, and mounts the
    // gate this machine's UI lives on. Asserting on a diag marker instead
    // would pin the marker, not the behaviour — a mutant that re-added the
    // early clear survived exactly that weaker assertion.
    final provider = EncryptionProvider(
      service: EncryptionService(),
      backupCodec: codec(),
    );
    addTearDown(provider.dispose);

    provider.setEmitCallback((event, data) {
      log.add(event);
      switch (event) {
        case 'checkOwnKeyBundle':
          scheduleMicrotask(() => provider.onOwnKeyBundleStatus(
              {'exists': true, 'linkingEnabled': true}));
        case 'getIdentityBackup':
          scheduleMicrotask(() => provider.onIdentityBackup({
                'exists': true,
                'blob': sealed.blob,
                'salt': sealed.salt,
                'iterations': sealed.iterations,
              }));
        case 'getRegistrationLockNonce':
          scheduleMicrotask(
            () => provider.onRegistrationLockNonce({'nonce': nonce}),
          );
        case 'uploadKeyBundle':
          scheduleMicrotask(() {
            if (failUpload) {
              // A refusal stands in for every post-adopt way this can die:
              // the nonce wait, the 45 s ack timeout, the roster re-sign.
              provider.onKeyBundleUploaded(
                  {'success': false, 'error': 'restore_refused'});
            } else {
              provider.onKeyBundleUploaded({
                'success': true,
                'identityChanged': false,
                'restored': true,
                'deviceId': 7,
                'access_token': 'a',
                'refresh_token': 'r',
                'nextListVersion': 4,
              });
            }
          });
        case 'getDeviceList':
          scheduleMicrotask(() => provider.onDeviceList({
                'userId': userId,
                'authorization': {'listCanonical': oldListCanonicalB64()},
              }));
        case 'updateDeviceList':
          scheduleMicrotask(() => provider
              .onDeviceListUpdated({'success': true, 'listVersion': 4}));
      }
    });

    await provider.initializeE2E(userId);
    expect(
      provider.needsDeviceLink,
      isTrue,
      reason: 'precondition: this is the gated, keyless install',
    );

    await provider.restoreFromPhrase(phrase);
    expect(provider.restoreStage, IdentityRestoreStage.failed);
    expect(
      provider.needsDeviceLink,
      isTrue,
      reason: 'a half-done restore must not drop the gate that shows it',
    );

    // The retry re-adopts the SAME identity this device now holds. Refusing
    // that was what made the stuck state permanent.
    failUpload = false;
    await provider.restoreFromPhrase(phrase);

    expect(provider.restoreStage, IdentityRestoreStage.done);
    expect(provider.restoreFailure, isNull);
    expect(
      provider.needsDeviceLink,
      isFalse,
      reason: 'only a finished restore may drop the gate',
    );
    expect(log.where((e) => e == 'uploadKeyBundle'), hasLength(2));
  });

  // The case the FIRST version of the clause-6 fix still got wrong. Stages
  // after the rebind (`listing`, the session rebuilds) run once the reconnect
  // has re-run E2E init, and the init success path clears `identityIncomplete`
  // (:1384) behind the machine's back — so that flag alone cannot be what
  // holds the gate. This drives the predicate directly: a provider whose init
  // SUCCEEDED (so `identityIncomplete` is false) must still be gated while a
  // restore sits unfinished.
  test('an unfinished restore holds the gate even when init cleared the flag',
      () async {
    await arrangeSealedBackup();
    final provider = await buildProvider();
    expect(
      provider.needsDeviceLink,
      isFalse,
      reason: 'precondition: nothing else is holding the gate',
    );

    provider.setEmitCallback((event, data) {
      if (event == 'getIdentityBackup') {
        scheduleMicrotask(() => provider.onIdentityBackup({'exists': false}));
      }
    });
    await provider.restoreFromPhrase(phrase);

    expect(provider.restoreStage, IdentityRestoreStage.failed);
    expect(
      provider.needsDeviceLink,
      isTrue,
      reason: 'an unfinished restore is itself a reason to keep the gate — the '
          'user has to see the failure and retry it',
    );
  });
}
