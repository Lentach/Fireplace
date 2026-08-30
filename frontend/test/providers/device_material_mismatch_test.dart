// Amendment (lxiv) clause 2 — GATE2-REVOKED-DEVICE-RELOGIN-CLOBBER.
//
// A revoked linked device that signs back in with the password is resolved by
// the server onto the LIVE PRIMARY's device id, still holds the shared account
// identity plus its OWN locally minted material, and re-uploads its bundle on
// every connect — silently clobbering the primary's published keys and making
// peers' first messages permanently undecryptable by every device.
//
// The client half of the fix: the install stamps which device id its material
// was provisioned for (TOFU on the first server-confirmed id; cleared by every
// authorized re-homing), and refuses E2E duty when the session's confirmed id
// contradicts the stamp. These tests drive the REAL EncryptionService and the
// REAL EncryptionProvider over mock storage — no fake provider state.
//
// Falsification contract: disarming `_verifyMaterialDeviceStamp` (or the init
// gate) must turn the mismatch tests RED; the positive controls must stay
// green so the gate cannot block ordinary single-device operation.

import 'package:fireplace/providers/encryption_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const ownUserId = 7;

  late List<(String, dynamic)> emitted;

  EncryptionProvider buildProvider() {
    final provider = EncryptionProvider();
    provider.setEmitCallback((event, data) {
      emitted.add((event, data));
      if (event == 'checkOwnKeyBundle') {
        provider.onOwnKeyBundleStatus({'exists': false});
      }
    });
    return provider;
  }

  List<(String, dynamic)> emitsOf(String event) =>
      emitted.where((e) => e.$1 == event).toList();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    emitted = [];
  });

  test('positive control: TOFU stamp + matching confirm keeps E2E ready', () async {
    final provider = buildProvider();
    provider.setOwnDeviceId(1);
    await provider.initializeE2E(ownUserId);
    await pumpEventQueue(times: 200);

    expect(provider.isE2EReady, isTrue);
    expect(provider.deviceMaterialMismatch, isFalse);
    expect(emitsOf('uploadKeyBundle'), hasLength(1),
        reason: 'a healthy install must keep publishing');

    // The stamp is real: the same engine confirming the SAME id stays clean.
    provider.setOwnDeviceId(1);
    await pumpEventQueue(times: 200);
    expect(provider.deviceMaterialMismatch, isFalse);
  });

  test(
      'the revoked-relogin shape: material stamped for device 2, session '
      'confirmed as device 1 -> E2E duty refused, nothing published', () async {
    // Life 1: the install is device 2 (a linked laptop). Init mints material
    // and the confirmed id TOFU-stamps 2.
    final life1 = buildProvider();
    life1.setOwnDeviceId(2);
    await life1.initializeE2E(ownUserId);
    await pumpEventQueue(times: 200);
    expect(life1.isE2EReady, isTrue);
    expect(life1.deviceMaterialMismatch, isFalse);

    // Life 2: the device was revoked and signs back in. Same storage (Signal
    // material survives logout by design), but the server resolves the login
    // onto the PRIMARY's id. A fresh provider models the fresh app session.
    emitted = [];
    final life2 = buildProvider();
    var notified = 0;
    life2.addListener(() => notified++);
    life2.setOwnDeviceId(1);
    await life2.initializeE2E(ownUserId);
    await pumpEventQueue(times: 200);

    expect(life2.deviceMaterialMismatch, isTrue,
        reason: 'the stamp (2) contradicts the session id (1)');
    expect(life2.isE2EReady, isFalse,
        reason: 'a mismatched install must not join E2E flows');
    expect(notified, greaterThan(0),
        reason: 'the banner cannot appear without a notify');
    expect(emitsOf('uploadKeyBundle'), isEmpty,
        reason: 'the clobbering re-upload is exactly the write this gate exists to stop');
    expect(emitsOf('uploadOneTimePreKeys'), isEmpty);

    // The preKeysLow replenishment path is also refused while mismatched.
    life2.onPreKeysLow(null);
    await pumpEventQueue(times: 200);
    expect(emitsOf('uploadOneTimePreKeys'), isEmpty,
        reason: 'a mismatched install must not deposit OTPs into a foreign pool');
  });

  test('reconnect path: a contradicting confirm AFTER init flips the gate', () async {
    final provider = buildProvider();
    provider.setOwnDeviceId(2);
    await provider.initializeE2E(ownUserId);
    await pumpEventQueue(times: 200);
    expect(provider.isE2EReady, isTrue);

    // The reconnect path skips _initializeE2EInner, so setOwnDeviceId's own
    // verification is what must catch a contradicting confirm.
    provider.setOwnDeviceId(1);
    await pumpEventQueue(times: 200);

    expect(provider.deviceMaterialMismatch, isTrue);
    expect(provider.isE2EReady, isFalse);
  });

  test('positive control: an authorized re-homing (rebind clear) re-stamps', () async {
    final life1 = buildProvider();
    life1.setOwnDeviceId(1);
    await life1.initializeE2E(ownUserId);
    await pumpEventQueue(times: 200);
    expect(life1.isE2EReady, isTrue);

    // The §6.2 rebind adoption clears the stamp before reconnecting under the
    // freshly allocated id — the recovering device must NOT trip the gate.
    await life1.encryptionService.clearMaterialDeviceStamp();

    emitted = [];
    final life2 = buildProvider();
    life2.setOwnDeviceId(9);
    await life2.initializeE2E(ownUserId);
    await pumpEventQueue(times: 200);

    expect(life2.deviceMaterialMismatch, isFalse);
    expect(life2.isE2EReady, isTrue);
    expect(emitsOf('uploadKeyBundle'), hasLength(1),
        reason: 'the recovering device must keep publishing under its new id');
  });

  test('the OTP replenishment carries the (lxiv) registrationId install proof', () async {
    final provider = buildProvider();
    provider.setOwnDeviceId(1);
    await provider.initializeE2E(ownUserId);
    await pumpEventQueue(times: 200);

    provider.onPreKeysLow(null);
    await pumpEventQueue(times: 200);

    final uploads = emitsOf('uploadOneTimePreKeys');
    expect(uploads, hasLength(1));
    final payload = (uploads.single.$2 as Map).cast<String, dynamic>();
    final expected = await provider.encryptionService.currentRegistrationId();
    expect(expected, isNotNull);
    expect(payload['registrationId'], expected,
        reason: 'without the proof the server cannot tell this install from a '
            'foreign one sharing the account identity');
  });
}
