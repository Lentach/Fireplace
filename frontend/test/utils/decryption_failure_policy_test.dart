import 'package:fireplace/utils/decryption_failure_policy.dart';
import 'package:flutter_test/flutter_test.dart';

/// Characterization tests: these encode the EXACT behavior of the decrypt-failure
/// branches in `_decryptMessageAsync` (messaging_provider.decrypt.dart). A wrong
/// branch here destroys working Signal sessions, so every combination is pinned.
void main() {
  group('decideDecryptionFailure', () {
    test(
      'duplicate → persist + terminal, no retry (regardless of reset/history)',
      () {
        for (final hadReset in [false, true]) {
          for (final isHistory in [false, true]) {
            final d = decideDecryptionFailure(
              DecryptionFailureKind.duplicate,
              hadIdentityReset: hadReset,
              isHistory: isHistory,
            );
            expect(d.rule, DecryptionFailureRule.duplicate);
            expect(d.persistTerminalFailure, isTrue);
            expect(d.markContentFailed, isTrue);
            expect(d.retryAction, DecryptionRetryAction.none);
            expect(d.notifyPeerRebuild, isFalse);
          }
        }
      },
    );

    test('badMac → persist + terminal, no retry, notify peer to re-key', () {
      for (final hadReset in [false, true]) {
        for (final isHistory in [false, true]) {
          final d = decideDecryptionFailure(
            DecryptionFailureKind.badMac,
            hadIdentityReset: hadReset,
            isHistory: isHistory,
          );
          expect(d.rule, DecryptionFailureRule.badMac);
          expect(d.persistTerminalFailure, isTrue);
          expect(d.markContentFailed, isTrue);
          expect(d.retryAction, DecryptionRetryAction.none);
          expect(d.notifyPeerRebuild, isTrue);
        }
      }
    });

    test(
      'identity reset overrides noSession/unknown → terminal, no persist, no retry, notify peer',
      () {
        for (final kind in [
          DecryptionFailureKind.noSession,
          DecryptionFailureKind.unknown,
        ]) {
          for (final isHistory in [false, true]) {
            final d = decideDecryptionFailure(
              kind,
              hadIdentityReset: true,
              isHistory: isHistory,
            );
            expect(d.rule, DecryptionFailureRule.identityReset);
            expect(d.persistTerminalFailure, isFalse);
            expect(d.markContentFailed, isTrue);
            expect(d.retryAction, DecryptionRetryAction.none);
            // The peer's session targets our DEAD identity — telling them to
            // re-key destroys nothing recoverable and stops further dead sends.
            expect(d.notifyPeerRebuild, isTrue);
          }
        }
      },
    );

    test(
      'noSession (history) → keep [encrypted], mark history peer for retry',
      () {
        final d = decideDecryptionFailure(
          DecryptionFailureKind.noSession,
          hadIdentityReset: false,
          isHistory: true,
        );
        expect(d.rule, DecryptionFailureRule.noSession);
        expect(d.persistTerminalFailure, isFalse);
        expect(d.markContentFailed, isFalse);
        expect(d.retryAction, DecryptionRetryAction.markHistoryPeerForRetry);
        expect(d.notifyPeerRebuild, isFalse);
      },
    );

    test('noSession (live) → keep [encrypted], schedule live retry', () {
      final d = decideDecryptionFailure(
        DecryptionFailureKind.noSession,
        hadIdentityReset: false,
        isHistory: false,
      );
      expect(d.rule, DecryptionFailureRule.noSession);
      expect(d.persistTerminalFailure, isFalse);
      expect(d.markContentFailed, isFalse);
      expect(d.retryAction, DecryptionRetryAction.scheduleLiveRetry);
      expect(d.notifyPeerRebuild, isFalse);
    });

    test(
      'unknown (history) → keep [encrypted], mark history peer for retry',
      () {
        final d = decideDecryptionFailure(
          DecryptionFailureKind.unknown,
          hadIdentityReset: false,
          isHistory: true,
        );
        expect(d.rule, DecryptionFailureRule.unknown);
        expect(d.persistTerminalFailure, isFalse);
        expect(d.markContentFailed, isFalse);
        expect(d.retryAction, DecryptionRetryAction.markHistoryPeerForRetry);
        expect(d.notifyPeerRebuild, isFalse);
      },
    );

    test(
      'unknown (live) → terminal [Decryption failed], schedule live retry',
      () {
        final d = decideDecryptionFailure(
          DecryptionFailureKind.unknown,
          hadIdentityReset: false,
          isHistory: false,
        );
        expect(d.rule, DecryptionFailureRule.unknown);
        expect(d.persistTerminalFailure, isFalse);
        expect(d.markContentFailed, isTrue);
        expect(d.retryAction, DecryptionRetryAction.scheduleLiveRetry);
        expect(d.notifyPeerRebuild, isFalse);
      },
    );
  });
}
