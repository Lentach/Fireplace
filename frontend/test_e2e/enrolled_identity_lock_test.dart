// Amendment (liv), finding F1 — WIRE LEVEL, against a real backend and a real
// Postgres.
//
// F1 is the most severe finding on this branch: a compromised LINKED device
// could seize the account identity with no ceremony and no delay, because the
// §5.1 link blob ships `ikPriv` to every linked device and §6.1's signature
// clause accepted a signature by the PREVIOUS identity key. (liv) closes that
// clause for any account that has an `account_authorizations` row.
//
// WHY THIS FILE EXISTS AT ALL. The gate's only other coverage is
// `key-bundles.service.spec.ts`, where the predicate is a mocked
// `authorizationRepo.findOne`. That mock proves the BRANCH but cannot prove the
// QUERY: it would stay green if the gate were wired to the wrong table, if the
// partial `select: { userId: true }` behaved unexpectedly against real TypeORM,
// or if the entity were missing from the DataSource — the last of which actually
// shipped in Phase 0a and only the live harness caught it. So this drives the
// real socket wire, then reads the server's own tables back.
//
// It is deliberately the SAME proof shape as `registration_lock_test.dart`: a
// refusal is exactly what a unit test can assert while the deployed server
// happily accepts everything.
//
// WHY IT IS OPT-IN, like the reset probe. `/auth/register` is 10 per HOUR per IP
// and every account in `test_e2e/` shares one bucket; the default run already
// spends it to the edge. This file registers TWO accounts (the enrolled subject
// and a non-enrolled positive control), so it runs in the isolated CI job that
// gets a FRESH backend — never in the shared `test_e2e` run. The production cap
// is not raised to fit a test.
//
//   docker-compose up
//   cd frontend && flutter test test_e2e/enrolled_identity_lock_test.dart \
//     --dart-define=ENROLLED_LOCK_PROBE=true
//
// THE POSITIVE CONTROL IS THE POINT. Asserting only that the enrolled account
// refuses would pass if uploads were broken for any unrelated reason. The
// control replays the IDENTICAL flow — same helper calls, same proof
// construction — on an account that is merely NOT enrolled, and requires it to
// SUCCEED. That pins the refusal to enrollment and nothing else.

// Mock-store setup is legitimate here: this file is a test, but `test_e2e/` is a
// sibling of `test/` so the analyzer does not treat it as one.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:convert';

import 'package:fireplace/services/device_list/device_authority_engine.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/e2e_test_client.dart';

/// Opt-in, for the register-bucket reason in the header.
const bool _enabled = bool.fromEnvironment('ENROLLED_LOCK_PROBE');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  enableRealNetwork();
  // The skip lives on the GROUP, not on the tests. A test-level `skip:` still
  // runs `setUpAll` — which registers TWO accounts and enrolls one — so the
  // default run would pay this probe's entire register-bucket cost only to skip
  // it. `identity_reset_teardown_test.dart:54-58` records the same lesson, and I
  // reproduced it here: with per-test skips this file failed in tearDownAll on
  // an uninitialized client after setUpAll had already tried to register.
  group(
    '(liv) an ENROLLED account loses the §6.1 signature path',
    () {
      final baseUrl = e2eBaseUrl();
      late E2eClient enrolled;
      late E2eClient control;
      E2eClient? attacker;
      E2eClient? controlSecond;
      // Captured while each account's identity record still exists: modelling a
      // second installation wipes the shared mock stores and destroys it.
      late String enrolledPair;
      late String controlPair;

      /// A single scalar from the harness's Postgres.
      Future<String?> scalar(String sql) async {
        final rows = await e2eSql(sql);
        if (rows.isEmpty || rows.first.isEmpty) return null;
        return rows.first.first;
      }

      /// Registers an account, uploads its keys, and returns its identity pair.
      Future<String> bootAccount(E2eClient client) async {
        await client.registerFresh();
        await client.connectSocket();
        await client.initializeAndUploadKeys();
        return client.exportIdentityPair();
      }

      /// Produces a validly-signed identity change from a SECOND installation on
      /// [account], signed by [signerPair] — i.e. exactly the proof a legitimate
      /// §6.1 rotation carries, and exactly what a linked device holding `ikPriv`
      /// can construct.
      Future<Map<String, dynamic>> attemptSignedIdentityChange(
        E2eClient account,
        String signerPair,
        String label,
      ) async {
        FlutterSecureStorage.setMockInitialValues({});
        SharedPreferences.setMockInitialValues({});
        final second = E2eClient(label, baseUrl)..adoptAccountFrom(account);
        await second.connectSocket();
        final keys = await second.initializeKeys();
        final newIdentity =
            (keys['keyBundle'] as Map)['identityPublicKey'] as String;
        final nonce = await second.fetchRegistrationLockNonce();
        final proof = await second.signIdentityChange(
          signerPairBase64: signerPair,
          newIdentityPublicKeyBase64: newIdentity,
          nonceBase64: nonce,
        );
        final answer = await second.uploadKeyBundleRaw(
          keys,
          identitySignature: proof,
          nonce: nonce,
        );
        // Hand the caller the session so it can be disposed, plus the key the
        // attempt tried to install.
        return {
          'answer': answer,
          'client': second,
          'attemptedIdentity': newIdentity,
        };
      }

      setUpAll(() async {
        await requireBackendUp(baseUrl);
        FlutterSecureStorage.setMockInitialValues({});
        SharedPreferences.setMockInitialValues({});

        // ---- the subject: an account that IS enrolled ----
        enrolled = E2eClient('enrlock', baseUrl);
        enrolledPair = await bootAccount(enrolled);

        // Enroll it for real, through the production engine and the real wire.
        // This is the state (liv) keys off, and it must be a genuine
        // `account_authorizations` row rather than anything this test fabricates.
        final engine = DeviceAuthorityEngine();
        final result = await engine.enroll(
          userId: enrolled.userId,
          identity: IdentityKeyPair.fromSerialized(base64Decode(enrolledPair)),
          send: enrolled.enrollDeviceAuthority,
          deviceId: 1,
          version: 1,
        );
        expect(
          result.accepted,
          isTrue,
          reason: 'the whole test is about the enrolled state: ${result.error}',
        );

        // ---- the control: an account that is NOT enrolled ----
        FlutterSecureStorage.setMockInitialValues({});
        SharedPreferences.setMockInitialValues({});
        control = E2eClient('ctllock', baseUrl);
        controlPair = await bootAccount(control);
      });

      tearDownAll(() {
        enrolled.dispose();
        control.dispose();
        attacker?.dispose();
        controlSecond?.dispose();
      });

      test(
        'a VALIDLY SIGNED identity change is refused, and the account is byte-identical afterwards',
        () async {
          // The server's own view before the attempt.
          final identityBefore = await scalar(
            'SELECT "identityPublicKey" FROM key_bundles '
            'WHERE "userId" = ${enrolled.userId} ORDER BY "deviceId" ASC LIMIT 1;',
          );
          expect(identityBefore, isNotNull);
          final dakBefore = await scalar(
            'SELECT "dakPub" FROM account_authorizations '
            'WHERE "userId" = ${enrolled.userId};',
          );
          expect(
            dakBefore,
            isNotNull,
            reason: 'the (liv) predicate reads THIS row — it must really exist',
          );
          final versionBefore = await scalar(
            'SELECT "listVersion" FROM account_authorizations '
            'WHERE "userId" = ${enrolled.userId};',
          );

          final outcome = await attemptSignedIdentityChange(
            enrolled,
            enrolledPair,
            'enratk',
          );
          attacker = outcome['client'] as E2eClient;
          final answer = outcome['answer'] as Map<String, dynamic>;

          // THE FINDING. Pre-(liv) this answered success:true and the account
          // identity became the attacker's.
          expect(answer['success'], isFalse, reason: 'answer was $answer');
          expect(answer['error'], 'identity_locked');

          // And nothing moved. A refusal that still wrote would be worse than no
          // refusal, because the alarm would not fire either.
          expect(
            await scalar(
              'SELECT "identityPublicKey" FROM key_bundles '
              'WHERE "userId" = ${enrolled.userId} ORDER BY "deviceId" ASC LIMIT 1;',
            ),
            identityBefore,
            reason: 'the primary bundle must be untouched',
          );
          expect(
            await scalar(
              'SELECT "dakPub" FROM account_authorizations '
              'WHERE "userId" = ${enrolled.userId};',
            ),
            dakBefore,
            reason: 'list authority must stay with the primary',
          );
          expect(
            await scalar(
              'SELECT "listVersion" FROM account_authorizations '
              'WHERE "userId" = ${enrolled.userId};',
            ),
            versionBefore,
          );
          // No audit row either: §6.1 refuses BEFORE any write, and an audit row
          // would mean the identity-churn path had been entered.
          expect(
            await scalar(
              'SELECT count(*) FROM identity_change_audit '
              'WHERE "userId" = ${enrolled.userId};',
            ),
            '0',
          );
          // The served bundle still carries the original identity, so a peer
          // fetching now cannot be handed the attacker's key.
          final served = await enrolled.fetchBundleFor(enrolled.userId);
          expect(served['identityPublicKey'], identityBefore);
        },
      );

      test(
        'POSITIVE CONTROL: the identical flow on a NON-enrolled account is ACCEPTED',
        () async {
          expect(
            await scalar(
              'SELECT count(*) FROM account_authorizations '
              'WHERE "userId" = ${control.userId};',
            ),
            '0',
            reason: 'this account must NOT be enrolled, or the control is void',
          );

          final outcome = await attemptSignedIdentityChange(
            control,
            controlPair,
            'ctlatk',
          );
          controlSecond = outcome['client'] as E2eClient;
          final answer = outcome['answer'] as Map<String, dynamic>;

          // Phase 0b behaviour, unchanged: one device, one holder of ikPriv, so
          // the signature is still sufficient. This is what pins the refusal
          // above to ENROLLMENT rather than to a broken upload path.
          expect(answer['success'], isTrue, reason: 'answer was $answer');
          expect(
            await scalar(
              'SELECT "identityPublicKey" FROM key_bundles '
              'WHERE "userId" = ${control.userId} ORDER BY "deviceId" ASC LIMIT 1;',
            ),
            outcome['attemptedIdentity'],
            reason: 'the rotation really landed, so the flow itself works',
          );
        },
      );
    },
    skip: _enabled
        ? false
        : 'set --dart-define=ENROLLED_LOCK_PROBE=true (needs a fresh register bucket)',
  );
}
