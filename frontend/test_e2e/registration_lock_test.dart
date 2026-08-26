// Phase 0b registration lock + reset ceremony (multi-device spec §6.1/§6.2),
// wire-level against a real backend and a real Postgres.
//
// The mechanism under test is a REFUSAL, and a refusal is exactly what unit
// tests can assert while the deployed server happily accepts everything (wrong
// DTO field name, handler never registered, entity missing from the DataSource
// — the last one shipped in 0a and only the live harness caught it). So this
// drives the real socket wire and then reads the server's own view back to
// confirm nothing moved.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/e2e_test_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  enableRealNetwork();

  group('registration lock (Phase 0b §6.1)', () {
    final baseUrl = e2eBaseUrl();
    late E2eClient owner;
    E2eClient? replacement;
    // Third authenticated session, minted by the carve-out test's re-login —
    // same account, so it costs nothing against the register throttle.
    E2eClient? relogin;
    // Captured while the owner's record still exists: the first test wipes the
    // shared mock stores to model a second installation, which destroys it.
    late String ownerPair;

    setUpAll(() async {
      await requireBackendUp(baseUrl);
      // ignore: invalid_use_of_visible_for_testing_member
      FlutterSecureStorage.setMockInitialValues({});
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});

      owner = E2eClient('lockown', baseUrl);
      await owner.registerFresh();
      await owner.connectSocket();
      await owner.initializeAndUploadKeys();
      ownerPair = await owner.exportIdentityPair();
    });

    tearDownAll(() {
      owner.dispose();
      replacement?.dispose();
      relogin?.dispose();
    });

    test(
      'an unauthorized identity replacement is refused and changes nothing',
      () async {
        final storedBefore = await owner.fetchBundleFor(owner.userId);
        final originalIdentity = storedBefore['identityPublicKey'] as String;

        // A second installation on the same account with brand-new keys: the
        // shape of both a legitimate reinstall AND a password-only takeover.
        // ignore: invalid_use_of_visible_for_testing_member
        FlutterSecureStorage.setMockInitialValues({});
        // ignore: invalid_use_of_visible_for_testing_member
        SharedPreferences.setMockInitialValues({});
        replacement = E2eClient('lockrpl', baseUrl)..adoptAccountFrom(owner);
        await replacement!.connectSocket();
        final freshKeys = await replacement!.initializeKeys();
        final freshIdentity =
            (freshKeys['keyBundle'] as Map)['identityPublicKey'] as String;
        expect(
          freshIdentity,
          isNot(originalIdentity),
          reason: 'the test is meaningless unless the identity really differs',
        );

        final answer = await replacement!.uploadKeyBundleRaw(freshKeys);

        expect(answer['success'], isFalse);
        expect(answer['error'], 'identity_locked');

        // The stored bundle must be identical afterwards: a refusal that still
        // wrote would silently redirect every future conversation.
        final storedAfter = await owner.fetchBundleFor(owner.userId);
        expect(storedAfter['identityPublicKey'], originalIdentity);

        // Nothing changed, so nothing may be announced — a false alarm here
        // would train users to ignore the real one.
        await owner.events.none(
          'ownIdentityReplaced',
          within: const Duration(seconds: 3),
          reason: 'a refused replacement must not alarm the account',
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test('an issued nonce is spent by ONE attempt, valid or not, and a proof '
        'signed by the previous identity key is then accepted', () async {
      final storedBefore = await owner.fetchBundleFor(owner.userId);
      final originalIdentity = storedBefore['identityPublicKey'] as String;
      final rotatedKeys = await replacement!.initializeKeys();
      final rotatedIdentity =
          (rotatedKeys['keyBundle'] as Map)['identityPublicKey'] as String;

      // Issue a nonce, then burn it on an attempt carrying no proof.
      final spentNonce = await owner.fetchRegistrationLockNonce();
      final burn = await owner.uploadKeyBundleRaw(rotatedKeys);
      expect(burn['success'], isFalse);

      // A perfectly valid proof over that SAME nonce must now be refused:
      // one issued nonce authorizes at most one attempt, so a captured
      // proof cannot be replayed into a later window.
      final staleProof = await owner.signIdentityChange(
        signerPairBase64: ownerPair,
        newIdentityPublicKeyBase64: rotatedIdentity,
        nonceBase64: spentNonce,
      );
      final replay = await owner.uploadKeyBundleRaw(
        rotatedKeys,
        identitySignature: staleProof,
        nonce: spentNonce,
      );
      expect(replay['success'], isFalse);
      expect(replay['error'], 'identity_locked');
      expect(
        (await owner.fetchBundleFor(owner.userId))['identityPublicKey'],
        originalIdentity,
        reason: 'neither refused attempt may move the stored identity',
      );

      // Control: a fresh nonce with the same signing key IS the legitimate
      // rotation path, and it goes through.
      final freshNonce = await owner.fetchRegistrationLockNonce();
      final goodProof = await owner.signIdentityChange(
        signerPairBase64: ownerPair,
        newIdentityPublicKeyBase64: rotatedIdentity,
        nonceBase64: freshNonce,
      );
      final accepted = await owner.uploadKeyBundleRaw(
        rotatedKeys,
        identitySignature: goodProof,
        nonce: freshNonce,
      );

      expect(accepted['success'], isTrue);
      final storedAfter = await owner.fetchBundleFor(owner.userId);
      expect(storedAfter['identityPublicKey'], rotatedIdentity);
      expect(storedAfter['identityPublicKey'], isNot(originalIdentity));
    }, timeout: const Timeout(Duration(minutes: 3)));

    // /auth/register is throttled to 10/hour per IP and the rest of the
    // harness already spends 9, so a fresh account per group would push the
    // suite over the ceiling. `replacement` is already a second authenticated
    // session of this account, which is what the broadcast assertions need.
    //
    // This drives the RECOVERY-KEY path because it exercises strictly more
    // machinery than a bare request (verifier + shortening + the same
    // notify/cancel/cooldown plumbing). The 72 h default and the Argon2id
    // parameters are pinned by the backend unit suite, which can assert them
    // without spending an account.
    test('a recovery key shortens the window, still notifies every session, '
        'and the ceremony cancels', () async {
      final user = owner;
      final secondSession = replacement!;
      const phrase =
          'legal winner thank year wave sausage worth useful legal winner '
          'thank yellow';

      expect(await user.setRecoveryKey(phrase), isTrue);

      // §12 (xlii): a phrase enrolled less than the full reset delay ago may
      // NOT shorten. Without that gate a password thief simply enrols a fresh
      // recovery key and skips the very 72 h wait the key is an exception to.
      // This test is the LEGITIMATE case — an owner whose phrase long predates
      // the theft — so the row is aged here, in seconds, rather than by
      // waiting three days. The young-phrase refusal itself is proven in the
      // backend suite (identity-reset.service.spec.ts); it cannot be added to
      // THIS flow, because refusing it still starts a ceremony whose cancel
      // would arm the 24 h cooldown that the next test inherits.
      await e2eSql(
        'UPDATE recovery_keys SET "createdAt" = NOW() - INTERVAL \'4 days\' '
        'WHERE "userId" = ${user.userId};',
      );

      // A wrong phrase must authorize nothing at all — no ceremony, no
      // deadline, nothing for the caller to act on.
      final wrong = await user.requestIdentityReset(
        recoveryPhrase: 'wrong wrong wrong wrong wrong wrong',
      );
      expect(wrong['status'], 'invalid_phrase');
      expect(wrong['deadlineAt'], isNull);

      secondSession.events.discard('identityResetPending');
      final started = await user.requestIdentityReset(recoveryPhrase: phrase);
      expect(started['status'], 'pending');
      expect(started['shortened'], isTrue);
      final deadline = DateTime.parse(started['deadlineAt'] as String);
      final minutes = deadline.difference(DateTime.now().toUtc()).inMinutes;
      expect(minutes, lessThanOrEqualTo(60));
      expect(
        minutes,
        greaterThan(50),
        reason: 'the phrase shortens the wait to an hour, never to zero',
      );

      // The OTHER session learns without asking — shortened still rings
      // every bell, which is the whole rule of §6.2.1.
      final broadcast =
          await secondSession.events.next(
                'identityResetPending',
                reason: 'the shortened path must still notify every session',
              )
              as Map;
      expect(broadcast['deadlineAt'], started['deadlineAt']);
      expect(broadcast['shortened'], isTrue);

      // Asking again must not restart the clock.
      final again = await user.requestIdentityReset();
      expect(again['status'], 'existing');
      expect(again['deadlineAt'], started['deadlineAt']);

      // Connect-time state, for a session that was offline when it started.
      final status = await secondSession.checkOwnKeyBundle();
      expect((status['identityReset'] as Map)['status'], 'pending');

      // Any session can stop it, with no key.
      secondSession.events.discard('identityResetCancelled');
      expect(await user.cancelIdentityReset(), isTrue);
      await secondSession.events.next(
        'identityResetCancelled',
        reason: 'every session must be told it was cancelled',
      );

      // Cancelling twice is a no-op, never a rollback of something else.
      expect(await user.cancelIdentityReset(), isFalse);

      // The cooldown now blocks a retry, and the spent phrase must not buy a
      // way around it either.
      final blocked = await user.requestIdentityReset();
      expect(blocked['status'], 'cooldown');
      final reuse = await user.requestIdentityReset(recoveryPhrase: phrase);
      expect(reuse['status'], anyOf('cooldown', 'invalid_phrase'));
      expect(reuse['shortened'], isFalse);

      final cleared = await secondSession.checkOwnKeyBundle();
      expect(cleared['identityReset'], isNull);
    }, timeout: const Timeout(Duration(minutes: 4)));

    // Inherits its precondition from the previous test: the cancel up there
    // just armed the 24 h cooldown. Spec §12 amendment 2026-08-19: a password
    // change VOIDS a cooldown armed before it — the refusal copy tells the
    // user whose ceremony an intruder cancelled to change their password, so
    // once they have, the attacker-authored cancel must not keep the owner
    // locked out. Runs LAST in this file because it retires the account's
    // original password.
    test(
      'a password change voids the cooldown a cancel armed before it',
      () async {
        const newPassword = 'E2eHarness2y';
        final user = owner;

        // The cooldown binds right up to the password change.
        final still = await user.requestIdentityReset();
        expect(still['status'], 'cooldown');

        // The production REST route: revokes every refresh token, stamps
        // passwordChangedAt, invalidates every earlier JWT.
        await user.api.resetPassword(
          user.accessToken,
          E2eClient.password,
          newPassword,
        );
        // JwtStrategy rejects iat <= passwordChangedAt at one-second
        // granularity; a login inside the same second would be refused.
        await Future<void>.delayed(const Duration(milliseconds: 1500));

        // A real client logs back in; the old token is dead. New session,
        // same account — no register-throttle spend.
        final fresh = await user.api.login(
          '${user.username}#${user.tag}',
          newPassword,
        );
        relogin = E2eClient('lockrelog', user.baseUrl)
          ..adoptAccountFrom(user)
          ..accessToken = fresh['access_token'] as String;
        await relogin!.connectSocket();

        // The cooldown armed BEFORE the change is void: a request now starts
        // a real ceremony instead of bouncing.
        final started = await relogin!.requestIdentityReset();
        expect(started['status'], 'pending');
        expect(started['deadlineAt'], isNotNull);

        // Leave nothing pending behind the suite. The cancel arms a fresh
        // cooldown — armed AFTER the change, so it must bind again, which
        // also proves the carve-out is not "password change disables
        // cooldowns forever".
        expect(await relogin!.cancelIdentityReset(), isTrue);
        final rearmed = await relogin!.requestIdentityReset();
        expect(rearmed['status'], 'cooldown');
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}
