# Media-send de-duplication via EncryptedMediaUploadService

**Date:** 2026-06-08

## What was done
Refactored the four media-send paths in `MessagingProvider` (`sendImageMessage`/`sendVoiceMessage`/`sendGif`/`sendFileMessage`) to remove ~4× duplicated encrypt→upload→patch boilerplate, **behavior-preserving**.

- **New `EncryptedMediaUploadService`** (`services/encrypted_media_upload_service.dart`): pure, injectable wrapper over `MediaCryptoService.encrypt` + `ApiService.uploadEncryptedMedia`, returning `EncryptedMediaUpload{mediaUrl, keyBase64, ivBase64, mediaDuration?}`. Fires an `onEncrypted(key, iv)` callback **between encrypt and the upload await** so callers persist `mediaKey`/`mediaIv` into `_pendingSendContent` before any await (preserves the documented invariant). First unit-testable encrypt+upload core (3 tests, fake crypto + fake api — no WebCrypto/HTTP).
- **`_buildOptimisticMediaMessage` factory** in the provider core — centralizes the optimistic `MessageModel` every media path builds; voice passes its `mediaUrl`/`mediaDuration` extras.
- **Test seam**: `_mediaUpload` getter (`_mediaUploadOverrideForTest ?? _mediaUploadDefault`) + `@visibleForTesting setMediaUploadServiceForTest`, mirroring `_activeConversationIdOverrideForTest`. Enables provider-level tests with an injected fake.
- **New provider tests** (`messaging_provider_media_send_test.dart`): image/voice/file success + failure paths (success patches `mediaUrl`; upload-throw → `deliveryStatus = failed`, no `mediaUrl`). Gif's download→encrypt→upload path is **manual-review-only** (Giphy `http.get` is non-injectable) — flagged for an optional follow-up http-client seam.
- Per-type divergence preserved exactly: voice (`_tokenForReconnect`, `updateLastMessage`, `mediaDuration`×3, local-file delete, `conv.disappearingTimer`), file (no `expiresIn` on upload, `content: fileName`), gif (5 MB guard).
- Discovered + recorded: `_markMessageFailed` discards its `errorMsg` arg (sets `deliveryStatus` only); `_encryptAndSend` early-returns to failed when `_encryptionProvider` is null (lets provider tests run without E2E setup).
- Version `0.0.44 → 0.0.45` (plan said 0.0.37 but the repo had drifted to 0.0.44; bumped from current per `.cursor/rules/version-bump.mdc`). CLAUDE.md §2 Services + §1 media-send bullet + §9 large-files note updated.

## Key files
- `frontend/lib/services/encrypted_media_upload_service.dart` (new)
- `frontend/test/services/encrypted_media_upload_service_test.dart` (new)
- `frontend/test/providers/messaging_provider_media_send_test.dart` (new)
- `frontend/lib/providers/messaging_provider.dart` (seam + `_buildOptimisticMediaMessage`)
- `frontend/lib/providers/messaging/messaging_provider.send.dart` (four methods rewired; ~1106→1052 LOC)
- `frontend/pubspec.yaml` (0.0.45), `CLAUDE.md`
- Plan: `docs/superpowers/plans/2026-06-07-messaging-send-media-collapse.md`

## Verification
- `flutter test test/services/encrypted_media_upload_service_test.dart` → 3 passed
- `flutter test test/providers/messaging_provider_media_send_test.dart test/providers/messaging_provider_voice_test.dart test/providers/messaging_provider_reply_media_test.dart` → all passed
- `flutter analyze` → No issues found! (24.5s)
- `flutter test` (full) → **308** passed
- Commits: `cad36d9` (service), `0d673bf` (image), `e92f58f` (voice/gif/file), + docs/version commit.

## Part 2 — Decrypt-failure decision logic extracted to a pure policy
The highest-risk branching in the app (wrong branch deletes a working Signal session) is now a pure, characterization-tested function.

- **New `decideDecryptionFailure`** (`utils/decryption_failure_policy.dart`): pure, no provider state/side effects. Input = `DecryptionFailureKind` (duplicate/badMac/noSession/unknown) + `hadIdentityReset` + `isHistory`; output = `DecryptionFailureDecision{rule, persistTerminalFailure, markContentFailed, retryAction}`. Precedence preserved exactly: duplicate/badMac (terminal+persist, no retry) > identityReset (terminal, no persist, no retry) > noSession (keep `[encrypted]`, retry) > unknown (live: terminal+retry; history: keep `[encrypted]`, retry).
- **7 characterization tests** (`decryption_failure_policy_test.dart`) pin all kind × reset × history combinations.
- **Wiring**: `_decryptMessageAsync`'s catch now classifies via `_classifyDecryptError`, applies the decision (log/persist/retry/content). Same logs (`DECRYPT_DUPLICATE`/`BAD_MAC`/`IDENTITY_RESET`/`SKIP`/`FAIL`), same side effects. Behavior preserved byte-for-byte.
- Verification: `flutter analyze` clean; policy + `messaging_provider_race_test` + `encryption_provider_test` green; full suite **315** passed. Commits `60b0bfb` (policy+tests), `6e4cece` (wiring), `03a1343` (docs). No version bump (kept 0.0.45 per request).

## Notes for next session
- **Manual QA** recommended for gif/voice/file send (gif download path has no automated test). Voice capture *can* be tested on the dev PC (it has a working mic).
- **Optional follow-ups** (captured in the plan): (1) add an injectable `http.Client` seam to `sendGif` to make its download path testable; (2) the higher-value extraction is the **decrypt-failure decision logic** (`DuplicateMessage`/`Bad Mac`/`NoSession`/identity-reset → terminal vs retry) into a pure, unit-tested function — currently no isolated test and a wrong branch destroys working sessions.
- Not yet deployed — run `./deploy.sh` on the VM when shipping (remember the stale-build trap: verify `gitCommit`, not version number).
