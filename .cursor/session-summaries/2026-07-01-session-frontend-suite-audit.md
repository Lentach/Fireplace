# Frontend test suite audit — resumed after window crash, completed

**Date:** 2026-07-01

## What was done
Resumed the frontend test audit whose chat window crashed mid-investigation (state recovered from `.planning/frontend-test-audit/findings.md`; branch `test/frontend-suite-audit` had zero commits). Completed it end-to-end, mirroring the backend audit:

- **Suspects cleared:** `bubble_redesign_test.dart` (8 distinct real tests) and `settings_screen_version_footer_test.dart` (1 real test) — the "~20 duplicate completions" from session 1 was just Flutter's progress reporter re-printing the running test's name. Not duplication.
- **Full sweep:** 4 parallel read-only agents audited all 82 test files against lib/ source.
- **Deleted 6 whole files** that tested nothing real: `notification_cleaner_web_test.dart` (asserted a test-local reimplementation, imported zero lib/ code), `utils/web_viewport_scroll_test.dart` + `utils/ping_sound_test.dart` (returnsNormally on empty VM stubs / asserted `kIsWeb` constant), `widgets/main_tab_screen_header_test.dart` (tight-constraint tautology — assertion couldn't fail), `crypto/anti_quantum_note_crypto_test.dart` (self-contained pointycastle copy; real path is webcrypto; referenced nonexistent `chat_provider.dart`), `constants/app_constants_test.dart` (constant-equals-itself).
- **Pruned 5 tests inside otherwise-good files:** race_test subset-duplicate (identity reset), cache_test idx==-1 "guard" test that asserted its own setup, 2 constant/type-trivia tests in recording_controller_test, mic-stub constant test in page_load_nonce_test.
- **Fixed 2:** friends_provider `onConnect(false)` test was vacuous (never-populated provider) — now seeds full state first; stale "(BUG)" comment in signal_stores_test corrected.
- **Filled the headline gap:** new `test/services/encryption_service_roundtrip_test.dart` (4 tests) — both parties are real `EncryptionService` instances (real libsignal 0.7.4, no crypto mocks) coexisting via `e2e_${userId}_` prefixes; asserts PreKey `3:` → whisper `2:` transition, ratchet advance (identical plaintext → distinct ciphertexts), 5 alternating volleys, non-ASCII/emoji utf8 survival.

## Key files
- `frontend/test/services/encryption_service_roundtrip_test.dart` (new)
- 6 deleted test files (see findings), 5 files with pruned/fixed tests
- `.planning/frontend-test-audit/findings.md` + `progress.md` (full verdict trail)

## Verification
- `cd frontend && flutter analyze --no-fatal-infos` → No issues found.
- `cd frontend && flutter test` → **All tests passed! 402 tests** (baseline 422 − 24 pruned + 4 new).
- `graphify update .` ran clean.

## Notes for next session
- Branch `test/frontend-suite-audit` pushed; PR to master pending user OK (test-only, no version bump needed — no shipped-code change).
- Named coverage GAPS deliberately NOT filled (scope): onMessageSent temp→real replacement (core send happy path, zero tests), reactions, typing indicators, onLinkPreviewReady, markSendingMessagesFailed, e2e_envelope messageType/mediaDuration/linkPreview parse, exhaustive MessageModel.copyWith 22-field preservation, ConversationModel pinnedMessage parse, always-mounted trailing-slot identity, real webcrypto anti-quantum round trip, GifService fetch seam. Full list in `.planning/frontend-test-audit/findings.md`.
