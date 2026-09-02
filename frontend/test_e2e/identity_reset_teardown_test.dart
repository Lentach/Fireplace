// §6.2 identity reset, END TO END against a real backend and a real Postgres:
// the roster teardown (amendment (f)/(xxviii)) and falsification 12, the
// per-device epoch claim.
//
//   docker-compose up
//   cd frontend && flutter test test_e2e/identity_reset_teardown_test.dart \
//     --dart-define=RESET_PROBE=true
//
// WHY THIS IS OPT-IN, and it is not squeamishness. Two hard constraints:
//
//  1. `/auth/register` is 10 per HOUR per IP and — with no nginx in front —
//     every account in `test_e2e/` shares one bucket. Measured 2026-08-22: the
//     default run already spends it to the edge, and adding a THIRD account to
//     `full_stack_e2e_test.dart` pushed `takeover_alarm_test.dart` into
//     `ThrottlerException` on register. So a new account cannot simply be added
//     to the shared suite; the alternative was raising a production anti-abuse
//     cap to fit a test, which is not a trade this program makes.
//  2. The ceremony is DESTRUCTIVE. It replaces the account identity, revokes
//     every device and burns a device id forward permanently. It therefore
//     needs an account nothing else depends on — never a shared fixture.
//
// It follows the house pattern for probes with special preconditions
// (`seed_long_history_probe_test.dart`, `recovered_identity_probe_test.dart`):
// skipped unless a dart-define asks for it.
//
// THE DELAY IS AGED, NOT WAITED (spec §12 (xxxvi)). §6.2's shortest real path
// is one hour with a valid recovery phrase. This ages
// `identity_reset_requests."deadlineAt"` by direct SQL and then lets the REAL
// per-minute `completeDueResets` sweep authorize the replacement. Forcing
// `status` to `completed` would skip that sweep and prove less.

// Mock-store setup is legitimate here: this file is a test, but `test_e2e/` is
// a sibling of `test/` so the analyzer does not treat it as one.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:convert';

import 'package:fireplace/services/device_list/device_authority_engine.dart';
import 'package:fireplace/services/device_list/device_list_cache.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/e2e_test_client.dart';
import 'support/link_ceremony.dart';

const _enabled = bool.fromEnvironment('RESET_PROBE');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  enableRealNetwork();

  // The skip lives on the GROUP, not on the test. A test-level `skip:` still
  // runs the group's `setUpAll` — which registers an account and links a
  // device — so the default run would pay this probe's whole cost, including
  // the registration the budget has no room for, to then skip it. Observed,
  // not assumed.
  group(
    '§6.2 reset teardown + falsification 12 (per-device epoch)',
    () {
      final baseUrl = e2eBaseUrl();
      final runTag = DateTime.now().millisecondsSinceEpoch.toString();

      late E2eClient carol;
      late IdentityKeyPair carolIdentity;
      late String carolIdentityPublic;
      final carolEngine = DeviceAuthorityEngine();
      E2eClient? deviceTwo;
      late int deviceTwoId;
      E2eClient? recovering;

      /// A single scalar from the harness's Postgres.
      Future<String?> scalar(String sql) async {
        final rows = await e2eSql(sql);
        if (rows.isEmpty || rows.first.isEmpty) return null;
        return rows.first.first;
      }

      setUpAll(() async {
        await requireBackendUp(baseUrl);
        FlutterSecureStorage.setMockInitialValues({});
        SharedPreferences.setMockInitialValues({});

        // An account of its own, enrolled with its OWN device authority:
        // `DeviceAuthorityEngine` holds ONE DAK pair and minting overwrites it,
        // so an engine may never be shared between accounts.
        carol = E2eClient('rst', baseUrl);
        await carol.registerFresh();
        await carol.connectSocket();
        await carol.initializeAndUploadKeys();
        carolIdentity = IdentityKeyPair.fromSerialized(
          base64Decode(await carol.exportIdentityPair()),
        );
        carolIdentityPublic = base64Encode(
          carolIdentity.getPublicKey().serialize(),
        );

        final enrolled = await carolEngine.enroll(
          userId: carol.userId,
          identity: carolIdentity,
          send: carol.enrollDeviceAuthority,
        );
        expect(enrolled.accepted, isTrue, reason: '${enrolled.error}');

        // THE SECOND PARTITION, and it is the whole reason this setup is not
        // trivial. Falsification 12 claims purge/claim/count stay strictly
        // inside `(identityPublicKey, deviceId)`. With ONE device that claim is
        // trivially true and the test cannot fail (§12 (xxxvi)), so the account
        // gets a real second device through the real ceremony, with its own
        // one-time pre-keys carrying a marker this test can look for afterwards.
        final primary = CeremonyPrimary(
          client: carol,
          engine: carolEngine,
          identity: carolIdentity,
        );
        final linked = await linkNewDevice(primary, 'rstd2', baseUrl);
        deviceTwo = linked.$1;
        deviceTwoId = linked.$2;

        await deviceTwo!.uploadDeviceKeyBundle(
          deviceId: deviceTwoId,
          identityPublicKey: carolIdentityPublic,
          registrationId: 4242,
        );
        await deviceTwo!.uploadDeviceOneTimePreKeys(
          deviceId: deviceTwoId,
          identityPublicKey: carolIdentityPublic,
          keyIds: const [0, 1, 2],
          // The marker: opaque to the server, and the thing whose SURVIVAL would
          // falsify the per-device epoch claim.
          publicKeyPrefix: 'carol-d2-otp-$runTag-',
        );
      });

      tearDownAll(() {
        carol.dispose();
        deviceTwo?.dispose();
        recovering?.dispose();
      });

      test(
        'the replacement is refused until the SQL-aged sweep authorizes it, then '
        'the teardown re-keys strictly within (identity, deviceId): every sibling '
        'device is revoked and purged, a FRESH id is allocated, and the '
        'enrollment row is REPLACED not dropped '
        '(spec §6.2, amendments (f)/(xxviii)/(xxix)/(xxxvi), falsification 12)',
        () async {
          // ---- the pre-reset world, read from the server's own tables ----
          final devicesBefore = await e2eSql(
            'SELECT "deviceId","isPrimary","revokedAt" FROM devices '
            'WHERE "userId" = ${carol.userId} ORDER BY "deviceId";',
          );
          expect(
            devicesBefore.length,
            greaterThanOrEqualTo(2),
            reason: 'the epoch claim needs two partitions to be non-vacuous',
          );
          final markerBefore = await scalar(
            'SELECT count(*) FROM one_time_pre_keys WHERE "userId" = '
            '${carol.userId} AND "publicKey" LIKE \'carol-d2-otp-$runTag-%\';',
          );
          expect(
            markerBefore,
            '3',
            reason: 'device 2 must really own OTP rows before the reset',
          );
          final authBefore = await scalar(
            'SELECT "listCanonical" FROM account_authorizations '
            'WHERE "userId" = ${carol.userId};',
          );
          expect(authBefore, isNotNull, reason: 'carol is enrolled');
          final authVersionBefore = await scalar(
            'SELECT "listVersion" FROM account_authorizations '
            'WHERE "userId" = ${carol.userId};',
          );
          final nextDeviceIdBefore = int.parse(
            (await scalar(
              'SELECT "nextDeviceId" FROM users WHERE id = ${carol.userId};',
            ))!,
          );

          // ---- a second installation, which is what a recovery looks like ----
          // Brand-new Signal keys on carol's account: the shape of a legitimate
          // reinstall AND of a password-only takeover, which is exactly why §6.1
          // refuses it without proof.
          recovering = E2eClient('rstr', baseUrl)..adoptAccountFrom(carol);
          await recovering!.connectSocket();
          FlutterSecureStorage.setMockInitialValues({});
          final freshKeys = await recovering!.initializeKeys();
          final freshIdentity =
              (freshKeys['keyBundle'] as Map)['identityPublicKey'] as String;
          expect(freshIdentity, isNot(carolIdentityPublic));

          final locked = await recovering!.uploadKeyBundleRaw(freshKeys);
          expect(locked['success'], isFalse);
          expect(
            locked['error'],
            'identity_locked',
            reason: 'the §6.1 lock is what makes a reset necessary at all',
          );

          // ---- the ceremony ----
          expect(
            await carol.setRecoveryKey('reset-probe-phrase-$runTag'),
            isTrue,
          );
          // §12 (xlii): a phrase younger than the full reset delay may not
          // SHORTEN, or a password thief would enrol one and skip the wait it
          // exists to gate. Carol is the legitimate owner, so age the row in
          // seconds instead of waiting three days.
          await e2eSql(
            'UPDATE recovery_keys SET "createdAt" = NOW() - INTERVAL \'4 days\' '
            'WHERE "userId" = ${carol.userId};',
          );
          final requested = await carol.requestIdentityReset(
            recoveryPhrase: 'reset-probe-phrase-$runTag',
          );
          expect(requested['status'], 'pending', reason: '$requested');
          expect(
            requested['shortened'],
            isTrue,
            reason: 'a valid phrase SHORTENS the delay; it never silences it',
          );

          // PENDING IS NOT COMPLETED. Without this the aging step below could be
          // doing nothing and the test would still pass — the upload would just
          // be succeeding for a reason nobody checked.
          final stillLocked = await recovering!.uploadKeyBundleRaw(freshKeys);
          expect(
            stillLocked['error'],
            'identity_locked',
            reason: 'a PENDING ceremony must not yet authorize a replacement',
          );

          // Age the deadline into the past and let the REAL per-minute sweep
          // find it (§12 (xxxvi)). Forcing `status` here would skip the sweep.
          await e2eSql(
            'UPDATE identity_reset_requests SET "deadlineAt" = now() - '
            'interval \'5 seconds\' WHERE "userId" = ${carol.userId} '
            'AND status = \'pending\';',
          );
          var status = 'pending';
          for (var i = 0; i < 40 && status != 'completed'; i++) {
            await Future<void>.delayed(const Duration(seconds: 3));
            status = (await scalar(
              'SELECT status FROM identity_reset_requests WHERE "userId" = '
              '${carol.userId} ORDER BY id DESC LIMIT 1;',
            ))!;
          }
          expect(
            status,
            'completed',
            reason:
                'the real completeDueResets sweep must be what completes it — '
                'if this times out the cron is not running, which is the bug',
          );

          // ---- the replacement now lands, and fires the teardown ----
          // Drop anything buffered so the assertion below can only be satisfied
          // by the silence of THIS teardown, never by an empty backlog.
          recovering!.events.discard('deviceRevoked');
          final accepted = await recovering!.uploadKeyBundleRaw(freshKeys);
          expect(accepted['success'], isTrue, reason: '$accepted');
          final newDeviceId = accepted['deviceId'] as int;

          // (f)(i): a FRESH id, never device 1 again, never a reused one.
          expect(newDeviceId, nextDeviceIdBefore);
          expect(newDeviceId, isNot(1));
          expect(newDeviceId, isNot(deviceTwoId));

          // §12 (xli) ON THE WIRE — the guard that was wrong TWICE, and until
          // now was proven only against a mock. This socket is still
          // authenticated as its PRE-reset device id, so it sits in a room the
          // teardown just revoked. `_onOwnDeviceRevoked` does NOT filter on
          // device id: it reads the id for a diagnostic line, then logs out
          // unconditionally. So a room-wide announcement would make the
          // recovering client wipe the session it adopted three lines above,
          // and the recovery would strand on every run. The server must
          // exclude the caller from the announcement, not merely from the
          // disconnect.
          await recovering!.events.none(
            'deviceRevoked',
            within: const Duration(seconds: 3),
            reason:
                'the recovering caller must never be told its own old device '
                'id was revoked',
          );

          // REBIND, and it is not ceremony. The teardown allocated a new device
          // id and issued a token bound to it; this socket is still authenticated
          // as the OLD device 1, which the teardown just revoked. Uploading
          // anything before rebinding files it under the revoked partition —
          // observed first-hand here: 20 fresh-epoch pre-keys landed on device 1
          // instead of the recovering device, unreachable behind a revoked row.
          recovering!.socketService.disconnect();
          recovering!.accessToken = accepted['access_token'] as String;
          await recovering!.connectSocket();

          // ---- falsification 12: the teardown stayed inside its partitions ----
          final devicesAfter = await e2eSql(
            'SELECT "deviceId","isPrimary","revokedAt" FROM devices '
            'WHERE "userId" = ${carol.userId} ORDER BY "deviceId";',
          );
          for (final row in devicesAfter) {
            final id = int.parse(row[0]);
            final revokedAt = row[2];
            if (id == newDeviceId) {
              expect(row[1], 't', reason: 'the recovering device is primary');
              expect(revokedAt, isEmpty, reason: 'and it is live');
            } else {
              expect(
                revokedAt,
                isNotEmpty,
                reason: 'every sibling device must be revoked: device $id',
              );
            }
          }

          // The marker is the load-bearing half: device 2's key material lived in
          // its OWN (identity, deviceId) partition, and the reset had to reach
          // into that partition to remove it — while never serving, counting or
          // resurrecting it anywhere else.
          expect(
            await scalar(
              'SELECT count(*) FROM one_time_pre_keys WHERE "userId" = '
              '${carol.userId} AND "publicKey" LIKE \'carol-d2-otp-$runTag-%\';',
            ),
            '0',
            reason:
                'a revoked sibling device keeps no claimable pre-keys after a '
                'reset — this is the row a cross-partition purge would miss',
          );
          // Every pre-key of the OLD epoch is gone — including the recovering
          // device's own, because the epoch is `(identityPublicKey, deviceId)`
          // and the identity half just changed.
          expect(
            await scalar(
              'SELECT count(*) FROM one_time_pre_keys '
              'WHERE "userId" = ${carol.userId};',
            ),
            '0',
          );
          // The CLAIM/COUNT half of falsification 12, which the purge alone does
          // not prove: the recovering device republishes under the NEW epoch, and
          // every surviving row must sit in exactly that one partition. Without
          // this the "no row outside the partition" check iterates an empty set
          // and cannot fail.
          await recovering!.uploadOneTimePreKeys(
            freshKeys,
            tagIdentityEpoch: true,
          );
          final partitions = await e2eSql(
            'SELECT "deviceId","identityPublicKey",count(*) '
            'FROM one_time_pre_keys WHERE "userId" = ${carol.userId} '
            'GROUP BY "deviceId","identityPublicKey";',
          );
          expect(
            partitions.length,
            1,
            reason:
                'exactly ONE (identity, deviceId) partition may hold pre-keys',
          );
          expect(int.parse(partitions.single[0]), newDeviceId);
          expect(partitions.single[1], freshIdentity);
          expect(
            int.parse(partitions.single[2]),
            (freshKeys['oneTimePreKeys'] as List).length,
            reason: 'the count is exactly what the new epoch uploaded',
          );
          final bundleDevices = await e2eSql(
            'SELECT "deviceId","identityPublicKey" FROM key_bundles '
            'WHERE "userId" = ${carol.userId};',
          );
          expect(bundleDevices.length, 1);
          expect(int.parse(bundleDevices.single[0]), newDeviceId);
          expect(
            bundleDevices.single[1],
            freshIdentity,
            reason: 'the served identity is the NEW epoch',
          );

          // (xxix): the enrollment row survives the reset. Dropping it would
          // destroy the listVersion (f)(iii) requires be carried forward and make
          // the account read as never-enrolled, which the (xix) rollback pin
          // refuses. It is REPLACED later, by a fresh IK-signed enrollment.
          expect(
            await scalar(
              'SELECT "listCanonical" FROM account_authorizations '
              'WHERE "userId" = ${carol.userId};',
            ),
            authBefore,
            reason:
                'the reset must NOT clear, drop or version-restart the '
                'enrollment — a test expecting that asserts a spec violation',
          );

          // ...and "REPLACED later" is amendment (xlv) clause 1. Until the
          // recovering device re-enrolls, the surviving row still names the
          // devices this teardown just revoked and omits the id it allocated,
          // and the DAK that signed it died with the lost devices — so
          // `updateDeviceList` is not open to this client.
          //
          // AMENDMENT (l) — this used to FETCH that row and assert it does not
          // verify under the new identity. The server no longer serves it at
          // all. (xlv) clause 2 already withheld the roster for the
          // never-enrolled shape; (l) widened that to the SURVIVING-row shape
          // for the reason finding F3 proved: the row still names the pre-reset
          // devices LIVE, so a peer holding the pre-reset anchor VERIFIES that
          // dead roster — it was signed by the very key it pinned — commits
          // with a null envelope, and the loss is silent, permanent and
          // bidirectional. Withholding downgrades that to a visible send
          // failure. Silence is fail-closed on the client (I5: "cannot verify",
          // never "no devices"), matching the entitlement and error paths.
          //
          // The property the old fetch asserted still holds and is still
          // proven, deductively and by stronger evidence than a wire read: the
          // enrollment row is byte-identical to the pre-reset one (asserted
          // immediately above) while the served identity is the NEW epoch
          // (asserted at the key_bundles check), so the surviving row is signed
          // by a key that is no longer the account's and cannot verify under
          // it. If the reset had NOT changed the identity, that key_bundles
          // assertion would already have failed.
          recovering!.events.discard('deviceList');
          recovering!.socketService.socket!.emit('getDeviceList', {
            'userId': carol.userId,
          });
          await recovering!.events.none(
            'deviceList',
            within: const Duration(seconds: 4),
            reason:
                'a surviving enrollment row names only revoked devices, and a '
                'peer with the pre-reset anchor would VERIFY that dead roster '
                'and lose every message in both directions ((l))',
          );

          // The server names the version the replacement must carry, because
          // the client cannot read a row it cannot verify.
          expect(
            accepted['nextListVersion'],
            int.parse(authVersionBefore!) + 1,
            reason: 'the replacement must ADVANCE past the surviving version',
          );

          // The replacement itself: a FRESH DAK, signed by the NEW identity,
          // naming the freshly allocated id. In the app this is driven by
          // ConnectionProvider off the rebind ack; here the harness plays that
          // part so the SERVER half is proven end to end.
          final replacement = DeviceAuthorityEngine();
          final replaced = await replacement.enroll(
            userId: carol.userId,
            identity: IdentityKeyPair.fromSerialized(
              base64Decode(await recovering!.exportIdentityPair()),
            ),
            send: recovering!.enrollDeviceAuthority,
            deviceId: newDeviceId,
            version: accepted['nextListVersion'] as int,
          );
          expect(replaced.accepted, isTrue, reason: '${replaced.error}');

          // ...and now a peer can address the account again.
          final repaired = DeviceListCache().adopt(
            userId: carol.userId,
            authorization:
                (await recovering!.fetchDeviceList(
                      carol.userId,
                    ))['authorization']
                    as Map<String, dynamic>?,
            tofuIdentityKeyBase64: freshIdentity,
          );
          expect(
            repaired.liveDeviceIds,
            [newDeviceId],
            reason:
                'the peer-visible list must name the recovering device; naming '
                'the revoked ones loses every message in both directions',
          );
          expect(repaired.isLiveDevice(newDeviceId), isTrue);

          // (f)(iv): the allocator only ever moves forward.
          expect(
            int.parse(
              (await scalar(
                'SELECT "nextDeviceId" FROM users WHERE id = ${carol.userId};',
              ))!,
            ),
            greaterThan(nextDeviceIdBefore),
          );
        },
        timeout: const Timeout(Duration(minutes: 6)),
      );
    },
    skip: _enabled ? false : 'set --dart-define=RESET_PROBE=true',
  );

  // ---------------------------------------------------------------------
  // The shape the harness above never builds, and that is exactly why this
  // exists. The probe above LINKS a device before it resets, because
  // falsification 12 needs two partitions to be non-vacuous — so every reset
  // this suite has ever run happened on an ENROLLED account. A single-device
  // account is the majority shape, and §6.2 is precisely the "I lost my only
  // device" ceremony, so the never-enrolled reset is the COMMON path and has
  // never once been exercised.
  // ---------------------------------------------------------------------
  group(
    '§6.2 reset on a NEVER-ENROLLED account: peers must still be able to '
    'address the recovering device (amendments (a)/(f)/(x)/(xxix))',
    () {
      final baseUrl = e2eBaseUrl();
      final runTag = DateTime.now().millisecondsSinceEpoch.toString();

      late E2eClient solo;
      E2eClient? recovering;

      Future<String?> scalar(String sql) async {
        final rows = await e2eSql(sql);
        if (rows.isEmpty || rows.first.isEmpty) return null;
        return rows.first.first;
      }

      setUpAll(() async {
        await requireBackendUp(baseUrl);
        FlutterSecureStorage.setMockInitialValues({});
        SharedPreferences.setMockInitialValues({});

        // ONE device, and deliberately NO `enrollDeviceAuthority` and NO link
        // ceremony. `enrollDeviceAuthority` is emitted only by the linking
        // controller (`link_ceremony_controller.dart`), so an account that
        // never links a second device never enrolls — which is every user who
        // owns one phone.
        solo = E2eClient('nre', baseUrl);
        await solo.registerFresh();
        await solo.connectSocket();
        await solo.initializeAndUploadKeys();
      });

      tearDownAll(() {
        solo.dispose();
        recovering?.dispose();
      });

      test(
        'after the teardown allocates a fresh id, the account is still '
        'un-enrolled, so a peer synthesizes device 1 and can neither address '
        'nor accept the only device that exists',
        () async {
          expect(
            await scalar(
              'SELECT count(*) FROM account_authorizations '
              'WHERE "userId" = ${solo.userId};',
            ),
            '0',
            reason: 'the whole point: this account never enrolled',
          );

          // ---- the ceremony, same aged-not-waited shape as the probe above --
          recovering = E2eClient('nrer', baseUrl)..adoptAccountFrom(solo);
          await recovering!.connectSocket();
          FlutterSecureStorage.setMockInitialValues({});
          final freshKeys = await recovering!.initializeKeys();

          expect(
            (await recovering!.uploadKeyBundleRaw(freshKeys))['error'],
            'identity_locked',
            reason: '§6.1 is what makes a reset necessary at all',
          );

          expect(await solo.setRecoveryKey('nre-phrase-$runTag'), isTrue);
          await e2eSql(
            'UPDATE recovery_keys SET "createdAt" = NOW() - INTERVAL \'4 days\' '
            'WHERE "userId" = ${solo.userId};',
          );
          final requested = await solo.requestIdentityReset(
            recoveryPhrase: 'nre-phrase-$runTag',
          );
          expect(requested['status'], 'pending', reason: '$requested');

          await e2eSql(
            'UPDATE identity_reset_requests SET "deadlineAt" = now() - '
            'interval \'5 seconds\' WHERE "userId" = ${solo.userId} '
            'AND status = \'pending\';',
          );
          var status = 'pending';
          for (var i = 0; i < 40 && status != 'completed'; i++) {
            await Future<void>.delayed(const Duration(seconds: 3));
            status = (await scalar(
              'SELECT status FROM identity_reset_requests WHERE "userId" = '
              '${solo.userId} ORDER BY id DESC LIMIT 1;',
            ))!;
          }
          expect(status, 'completed', reason: 'the real sweep must complete it');

          final accepted = await recovering!.uploadKeyBundleRaw(freshKeys);
          expect(accepted['success'], isTrue, reason: '$accepted');
          final newDeviceId = accepted['deviceId'] as int;

          // (a)/(f)(i): ids are never reused, so the ONLY live device is >= 2.
          expect(newDeviceId, greaterThanOrEqualTo(2));
          expect(
            await scalar(
              'SELECT string_agg("deviceId"::text, \',\' ORDER BY "deviceId") '
              'FROM devices WHERE "userId" = ${solo.userId} '
              'AND "revokedAt" IS NULL;',
            ),
            '$newDeviceId',
            reason: 'exactly one live device, and it is not device 1',
          );

          // ---- (xlv) CLAUSE 2: the roster is REFUSED, not answered ---------
          // The teardown deliberately does not touch `account_authorizations`
          // ((xxix)) — correct for an account that HAD a row, but this one
          // never did and never gets one. Answering `authorization: null` here
          // would make every peer synthesize the single device 1 that a
          // non-enrolled account is supposed to have, and device 1 is exactly
          // what this teardown revoked. So the server stays SILENT, which is
          // fail-closed on the client (I5), until the replacement lands.
          recovering!.events.discard('deviceList');
          recovering!.socketService.socket!.emit('getDeviceList', {
            'userId': solo.userId,
          });
          await recovering!.events.none(
            'deviceList',
            within: const Duration(seconds: 4),
            reason:
                'an un-enrolled account whose live devices exclude device 1 '
                'must not be answered — a synthesized device 1 would silently '
                'lose every message in both directions',
          );

          // ---- (xlv) CLAUSE 1: the replacement enrollment ------------------
          // No surviving row, so the replacement is a FIRST enrollment and the
          // server says so.
          expect(
            accepted['nextListVersion'],
            1,
            reason: 'an account that never enrolled re-enrolls at version 1',
          );
          final replacement = DeviceAuthorityEngine();
          final replaced = await replacement.enroll(
            userId: solo.userId,
            identity: IdentityKeyPair.fromSerialized(
              base64Decode(await recovering!.exportIdentityPair()),
            ),
            send: recovering!.enrollDeviceAuthority,
            deviceId: newDeviceId,
            version: accepted['nextListVersion'] as int,
          );
          expect(replaced.accepted, isTrue, reason: '${replaced.error}');

          // ---- and now peers can reach the account, both directions --------
          final roster = await recovering!.fetchDeviceList(solo.userId);
          final verified = DeviceListCache().adopt(
            userId: solo.userId,
            authorization: roster['authorization'] as Map<String, dynamic>?,
            tofuIdentityKeyBase64: base64Encode(
              IdentityKeyPair.fromSerialized(
                base64Decode(await recovering!.exportIdentityPair()),
              ).getPublicKey().serialize(),
            ),
          );

          // Peer -> reset user: the fan-out addresses `liveDeviceIds`
          // (`messaging_provider.send.dart`).
          expect(
            verified.liveDeviceIds,
            [newDeviceId],
            reason:
                'a peer must fan out to the device that EXISTS; addressing the '
                'synthesized device 1 loses every inbound message',
          );

          // Reset user -> peer: `_originDeviceIsLive`
          // (`messaging_provider.decrypt.dart`) refuses an origin the list does
          // not contain, so the peer withholds every message this account sends.
          expect(
            verified.isLiveDevice(newDeviceId),
            isTrue,
            reason:
                'a peer must accept the recovering device as a live origin, or '
                'it withholds as DECRYPT_REFUSED_REVOKED_ORIGIN forever',
          );
        },
        timeout: const Timeout(Duration(minutes: 6)),
      );
    },
    skip: _enabled ? false : 'set --dart-define=RESET_PROBE=true',
  );
}
