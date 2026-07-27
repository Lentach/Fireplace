# E2E incident audit — cache-clear history destruction plus unresolved new-traffic failures

**Date:** 2026-07-11

## What was done

- Performed a read-only, chunk-by-chunk audit of the complete E2E path against the installed `libsignal_protocol_dart 0.8.2` source.
- Enumerated crypto-adjacent commits from 2026-06-26 through 2026-07-11. Liquid-glass changes did not touch Signal/session/storage/socket logic.
- Owner evidence: one installed PWA; mixed failures (some first-message, some mid-conversation, good and broken rows interleaved); sender can see own message while recipient cannot; owner used the in-app Privacy & Safety cache-clear operation immediately before widespread failures.
- CONFIRMED a release-blocking product/code bug: “Clear local message cache” deletes the persisted decrypted message/media-key records that are the only replayable representation after the Double Ratchet consumes message keys. History loading then retries old ciphertext, libsignal throws duplicate/old-counter, and Fireplace persists terminal `[Decryption failed]`.
- CONFIRMED separate structural defects: OTPs are not identity-generation-bound, bundle storage is last-writer-wins per account, peer identity changes are silently TOFU-overwritten, and process-local session locks do not coordinate multiple web instances.
- Did not attribute all newly arriving failures: exact durable diagnostics and ciphertext prefixes from both users remain missing. Current shortlist and discriminator table are in the local audit.
- No application code, keys, sessions, storage, DB state, branch, commit, PR, merge, or deploy changed.

## Key files

- Local/private audit: `docs/audit/2026-07-11-e2e-incident-audit.md` (`docs/audit/` is gitignored).
- `frontend/lib/services/encryption_service.dart`
- `frontend/lib/services/encryption/signal_stores.dart`
- `frontend/lib/providers/encryption_provider.dart`
- `frontend/lib/providers/messaging/messaging_provider.decrypt.dart`
- `backend/src/key-bundles/key-bundles.service.ts`
- `backend/src/key-bundles/key-bundle.entity.ts`
- `backend/src/key-bundles/one-time-pre-key.entity.ts`
- `backend/src/chat/services/chat-key-exchange.service.ts`
- Installed package source: Pub cache `libsignal_protocol_dart-0.8.2/lib/src/session_cipher.dart` and `session_builder.dart`.

## Verification

- Frontend focused proof: 40 tests passed:
  `flutter test test/services/encryption_service_content_cache_test.dart test/services/encryption_send_race_probe_test.dart test/services/encryption_encrypt_decrypt_race_probe_test.dart test/utils/e2e_envelope_test.dart test/providers/message_editing_test.dart`
- Backend focused proof: 58 tests / 3 suites passed:
  `npm test -- --runInBand src/key-bundles/key-bundles.service.spec.ts src/chat/services/chat-key-exchange.service.spec.ts src/chat/services/chat-message.service.spec.ts`
- `git check-ignore -v docs/audit/2026-07-11-e2e-incident-audit.md` confirmed `.gitignore:52:docs/audit/`; report stays local.
- Web-search tool failed internally (`ENOENT` in harness header-generator data). Package metadata and exact installed source were read directly instead.

## Notes for next session

- Do not clear data, reinstall, regenerate identity, or delete sessions.
- Obtain both users’ full durable E2E logs and Settings footers. Required discriminators:
  - `CACHE_CLEAR scope:decryptedContent` then `kind:duplicate,isHistory:true` confirms cache-clear history loss.
  - `E2E_INIT_DONE needsKeyUpload:true` / `E2E_KEYS_UPLOADED` confirms identity regeneration.
  - new `2:` + badMac means stale/mismatched sender session.
  - failed `3:` means PreKey/identity/OTP path.
  - new duplicate from confirmed post-0.0.94 sender reopens SessionRecord race.
- Owner approval gates before code:
  1. choose removal of message-plaintext cache clear (recommended) versus explicit irreversible “erase readable local history” semantics;
  2. approve a controlled future-session recovery only if logs prove new traffic is mismatched;
  3. then create `fix/e2e-incident`, write the real two-party cache-clear regression first, implement, run full suites/wire harness, open PR, and stop before merge/deploy.
- Old plaintext/media keys erased by cache clear are generally unrecoverable. Server ciphertext cannot recreate consumed Double Ratchet message keys.
