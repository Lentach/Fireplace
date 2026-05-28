# fix(e2e): Stop [Decryption failed] cascade that broke all future messages

**Date:** 2026-05-28

## Root Cause

Commit `1871194` introduced a 900ms `retryDecryptActiveConversation()` call in `_onSocketReady`. Combined with three related bugs, this caused a cascade: one failed decrypt → all future messages from that peer permanently unreadable.

**The three bugs:**

1. `_conversationHasUndecryptedInbound` (line ~479) included `m.content == _kDecryptionFailedLabel` in its check. `[Decryption failed]` is a terminal state — it caused the 900ms timer to trigger a new decrypt pass on **every reconnect** for any conversation that ever had a failure.

2. `peersNeedingRetry` comprehension in `_decryptMessageHistory` also included `[Decryption failed]` messages, causing `_retryDecryptForPeers` to run for those peers.

3. The main decrypt loop didn't skip `[Decryption failed]` rows. They'd fail to decrypt → peer added to `_historyDecryptFailedPeers` → `_retryDecryptForPeers` → `deleteSessionWithPeer`.

**The cascade:** `deleteSessionWithPeer` destroys the working Signal session. New messages from that peer fail → also become `[Decryption failed]` → trigger the same path on next reconnect → loop continues until "most messages are not readable."

## Fixes

Three targeted changes to `messaging_provider.dart`:

1. **`_conversationHasUndecryptedInbound`**: now only checks `displayAsEncryptedPlaceholder`, not `[Decryption failed]`.

2. **Main decrypt loop** (after `_hasUsableDecryptedContent` check): added `if (rowForDecrypt.content == _kDecryptionFailedLabel) continue;` — skips permanently failed messages entirely, preventing them from adding the peer to `_historyDecryptFailedPeers`.

3. **`peersNeedingRetry` comprehension**: removed `|| m.content == _kDecryptionFailedLabel` — only `displayAsEncryptedPlaceholder` triggers the retry set.

## New Regression Test

Added `_AlwaysFailWithSessionCountEncryption` class and test:
> "retryDecryptActiveConversation does NOT delete session when messages are already [Decryption failed]"

Verifies that `deleteSessionWithPeer` is called exactly once (first pass) and NOT called again when `retryDecryptActiveConversation()` fires on subsequent reconnects.

## Files Changed

- `frontend/lib/providers/messaging_provider.dart` — 3 surgical changes
- `frontend/test/providers/messaging_provider_race_test.dart` — new mock class + regression test

## Verification

- `flutter analyze` → No issues found
- `flutter test` → 247/247 passed (was 246 before; +1 new test)

## Notes for Next Session

- This was a **regression from commit 1871194** — the 900ms `retryDecryptActiveConversation()` timer was new there
- `[Decryption failed]` messages are permanently unrecoverable (Signal ratchet can't go back); they're now skipped in all retry loops
- Existing `[Decryption failed]` messages in production remain unreadable (can't recover old ciphertexts); the fix prevents NEW messages from breaking
- If users still see widespread failures, check production logs for `[E2E-FLOW] DECRYPT_FAIL` to identify whether it's `NoSessionException` (signal session lost from storage) vs `Bad Mac` (ratchet mismatch)
- Backend VM logs won't show E2E details (encryption is client-side only); check browser devtools console for `[E2E-FLOW]` logs
