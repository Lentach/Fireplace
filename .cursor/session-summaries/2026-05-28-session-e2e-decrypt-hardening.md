# E2E decrypt hardening — 3 follow-up fixes after cascade fix

**Date:** 2026-05-28

## What was done

### Fix 1: DuplicateMessageException must not delete session
`DuplicateMessageException` means the Signal ratchet already consumed that message key (the message was live-decrypted earlier). The session itself is valid. The old code placed it in the same retry queue as genuine failures, which triggered `deleteSessionWithPeer` and destroyed the working session for future messages.

**Fix:** Separate `DuplicateMessageException` from `NoSessionException` in `_decryptMessageAsync`. `DuplicateMessageException` now immediately returns `[Decryption failed]` without touching the session or retry queue. `NoSessionException` keeps existing retry behavior (session delete is harmless when there is no session).

### Fix 2: Increase plaintext cache cap from 500 to 2000
The 500-entry cap was too low — 5 conversations × 100 messages = 500, causing early eviction of old entries. Evicted entries hit live decrypt on reload → `DuplicateMessageException` (ratchet key consumed) → now correctly marks `[Decryption failed]` without session deletion (Fix 1). Raising to 2000 covers typical users (~800KB localStorage, well within Safari's 5MB limit).

### Fix 3: Identity reset (reinstall / storage loss) must not delete sessions
Root cause of the initial production failure: user reinstalled app → new Signal identity → old messages encrypted for old identity → `NoSessionException` on all history → cascade bug amplified it to all contacts. With the cascade fix (0.0.16) and Fix 1 in place, the remaining gap was that `NoSessionException` from an identity reset still went through the retry queue and `deleteSessionWithPeer`.

**Fix:** `EncryptionProvider.hadIdentityReset` getter exposes `EncryptionService.needsKeyUpload`. In `_decryptMessageAsync`, when `hadIdentityReset == true`, any decrypt exception immediately marks `[Decryption failed]` without adding to retry queue or deleting sessions. A fresh session for each peer will be built by the next PreKey message they send.

## Key files

- `frontend/lib/providers/messaging_provider.dart` — `_decryptMessageAsync`: split `DuplicateMessageException` / `NoSessionException`, added `hadIdentityReset` guard
- `frontend/lib/providers/encryption_provider.dart` — added `bool get hadIdentityReset`
- `frontend/lib/services/encryption_service.dart` — `decryptedContentCacheLimit` default 500 → 2000
- `frontend/test/providers/messaging_provider_race_test.dart` — 2 new regression tests + 2 new fake classes
- `CLAUDE.md` — updated Decrypt ordering note + cache cap

## Verification

- `flutter test test/providers/messaging_provider_race_test.dart` — 22/22 pass (was 20)
- `flutter test` — 249/249 pass (was 247)

## Notes for next session

All three E2E fragility points from `e2e-knowledge-handoff.md` are now addressed:
1. ✅ `DuplicateMessageException` — no longer deletes session
2. ✅ Cache cap — increased 500 → 2000
3. ✅ Identity reset — no longer deletes sessions, marks failed immediately

Remaining known limitation: messages encrypted for the old identity after reinstall are permanently `[Decryption failed]` — this is correct E2E behavior (no key recovery). Future messages work once the peer sends a new PreKey message.

Consider next: in-app E2E diagnostic log (circular buffer in Settings) to make debugging PWA issues possible without DevTools. See `e2e-knowledge-handoff.md` § "What to investigate next".

Version still 0.0.16 (no user-visible behavior change; these are defensive/correctness fixes). Bump to 0.0.17 when shipping next user-visible feature.
