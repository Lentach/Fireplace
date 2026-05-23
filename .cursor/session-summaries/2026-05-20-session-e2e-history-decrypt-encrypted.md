# Session summary — 2026-05-20 (E2E `[encrypted]` fix)

## Context (from prod investigation)

- GuyFawkes (user 43) → bob208 (37): messages 4664/4665 at ~10:36 CEST showed `[encrypted]` in UI.
- DB: `encryptedContent` present (`HAS_ENC`) — server OK; bug is client history decrypt.
- VM logs: no backend E2E errors; reconnect/offline pattern for bob208.

## Fix (re-applied after log/DB analysis)

`frontend/lib/providers/messaging_provider.dart`:

- `_hasUsableDecryptedContent` — do not treat `[encrypted]` RAM/persisted cache as decrypted.
- `_decryptMessageHistory` — wait up to ~10s for `isE2EReady` before pass.
- After history pass: `_retryHistoryDecryptForPeers` for peers with leftover `[encrypted]` or `[Decryption failed]` (session reset + chronological replay).
- Live decrypt catch: only return memory cache when usable.

## Tests

- `flutter test test/providers/messaging_provider_race_test.dart` — 11 passed
- New: `history decrypt ignores memory cache that still has [encrypted] placeholder`

## Deploy

Rebuild/deploy Flutter web on VM (`~/deploy.sh`) so PWA picks up the fix.

## Not in this change

- MessageCleanupService FK on reply-to delete (separate backend ticket)
- Missing media `.bin` ENOENT (separate)
