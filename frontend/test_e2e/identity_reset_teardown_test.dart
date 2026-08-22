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
          final accepted = await recovering!.uploadKeyBundleRaw(freshKeys);
          expect(accepted['success'], isTrue, reason: '$accepted');
          final newDeviceId = accepted['deviceId'] as int;

          // (f)(i): a FRESH id, never device 1 again, never a reused one.
          expect(newDeviceId, nextDeviceIdBefore);
          expect(newDeviceId, isNot(1));
          expect(newDeviceId, isNot(deviceTwoId));

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
}
