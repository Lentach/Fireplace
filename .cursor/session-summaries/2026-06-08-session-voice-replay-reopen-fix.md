# Received voice messages fail to replay after reopening chat — fixed (0.0.41–0.0.44)

**Date:** 2026-06-08

## Symptom
A→B voice: B plays it live fine, but after B closes/reopens the app, B can't replay A's voice ("failed to load audio"). Own (B's sent) messages always replay; only **received** messages broke. iOS Safari + Android Chrome (PWA) both affected.

## Root cause (two coupled bugs)
For received E2E media, `mediaKey`/`mediaIv` come only from decrypting the envelope **once** (Double Ratchet consumes the message key). The persisted decrypted-content cache is the only copy that survives reload.
1. **Keys destroyed:** on reopen, the row was re-decrypted → `DuplicateMessage` → the handler wrote `{content:'[Decryption failed]'}`, **overwriting the keyed entry** (keyless). Re-decrypt is impossible afterward → permanently dead.
2. **Keys ignored:** even once preserved, restore-on-reopen rejected the keyed row because a decrypted voice/image has empty text, so its content stays `[encrypted]` (`displayAsEncryptedPlaceholder`); `_hasUsableDecryptedContent` treated that as "undecrypted" → re-decrypted anyway → `DuplicateMessage` → `[Decryption failed]` in memory.

## Fix (both needed)
- **Guard** (`encryption_service.dart` `saveDecryptedContent`): refuse a keyless write when the stored entry already has `mediaKey` — never downgrade keyed media. +3 regression tests in `encryption_service_content_cache_test.dart`.
- **Restore acceptance** (`messaging_provider.decrypt.dart` `_hasUsableDecryptedContent`): a row with `mediaKey`+`mediaIv`+`mediaUrl` and non-TEXT type is usable even when `content == '[encrypted]'` → restore uses the keys, skips the pointless re-decrypt.

## The detour (the real time sink)
The fix (`ba414b3`) was pushed but **never actually built into the served bundle** — `flutter build web` served a **cached compile** at `958edfc`, and the PWA cached it. The Settings footer showed version `0.0.43` while `gitCommit` was `958edfc` (= 0.0.42). We were testing pre-fix code for many rounds. **`flutter clean` + redeploy + PWA reinstall** made it live → confirmed working. Lesson documented in CLAUDE.md §0: trust `gitCommit`, not the version number; `flutter clean` + hard cache-bust when a frontend change won't take.

## Key files
- `frontend/lib/services/encryption_service.dart` — downgrade guard.
- `frontend/lib/providers/messaging/messaging_provider.decrypt.dart` — `_hasUsableDecryptedContent` media acceptance.
- `frontend/test/services/encryption_service_content_cache_test.dart` — +3 guard tests.
- `0.0.44` (`d04c7a7`) — stripped all temp voice/persist/cache diagnostics; **kept** the two fixes. (iOS `mic.start` diagnostic retained — that investigation is still open.)

## Verification
- `flutter analyze lib/` clean · `flutter test` **299** green · `flutter build web --release` OK.
- On-device: a post-fix received voice (7470/7475) plays after a full reopen once `ba414b3` was actually built+loaded.

## Unrecoverable
Messages received **before** `0.0.41` (e.g. 7440/7441/7442) had their keys overwritten and the ciphertext is one-shot — permanently unplayable. Nothing can recover them.

## Notes for next session
- **Deploy the clean `0.0.44`**: `cd ~/fireplace && git pull && cd frontend && flutter clean && cd .. && ./deploy.sh && cp -a frontend/build/web/. frontend-build/`, confirm `gitCommit` = `d04c7a7`, then PWA cache-bust. (0.0.43 already works; 0.0.44 only removes debug logging.)
- **Open:** iOS PWA mic re-prompt investigation (Part B, `mic.start` diagnostic still in build) — never concluded; the `loadNonce`/`permState` data was never captured because the voice bug took over.
- Consider hardening `deploy.sh`: `flutter clean` before build and echo the `gitCommit` being built, to prevent the stale-build trap recurring.
