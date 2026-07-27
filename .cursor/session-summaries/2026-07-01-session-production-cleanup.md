# Production cleanup review

**Date:** 2026-07-01

## What was done

Reviewed recent Fireplace frontend/backend/scripts/docs churn and removed only confirmed garbage.

- Frontend cleanup:
  - Deleted obsolete root widget re-export shims:
    - `frontend/lib/widgets/chat_input_bar.dart`
    - `frontend/lib/widgets/chat_message_bubble.dart`
    - `frontend/lib/widgets/voice_message_bubble.dart`
  - Updated `ChatDetailScreen` to import the real widget locations directly.
  - Replaced a stale `voice_message_content.dart` comment that referenced the deleted voice shim.
- Backend cleanup:
  - Deleted unused `RefreshTokensService.deleteExpired()` and the now-unused TypeORM `LessThan` import.
  - Reworded stale Cloudinary-only media URL comments/test names to current allowlist/self-hosted-or-legacy wording.
- Scripts/config/docs cleanup:
  - Deleted obsolete root manual JS flow scripts that used old auth/socket/friend-request contracts and their root npm manifest/lockfile.
  - Corrected `docs/manual-e2e-testing.md` for Signal ciphertext type `2`, quoted camelCase columns, and encrypted media-envelope semantics.
  - Hardened `scripts/verify-claude-backend-test-counts.mjs` by removing `shell: true`, adding Windows `cmd.exe /c` handling, explicit spawn errors, and larger Jest output buffer.
  - Added `.planning/` and `.tmp/` to `.gitignore` so local planning/visual-capture artifacts do not leak into commits.
- Ran `graphify update .` after code changes.

## Key files

- `frontend/lib/screens/chat_detail_screen.dart`
- `frontend/lib/widgets/message/voice_message_content.dart`
- `backend/src/auth/refresh-tokens.service.ts`
- `backend/src/chat/dto/chat.dto.ts`
- `backend/src/chat/dto/chat.dto.spec.ts`
- `backend/src/chat/services/chat-message.service.spec.ts`
- `backend/src/chat/utils/dto.validator.spec.ts`
- `docs/manual-e2e-testing.md`
- `scripts/verify-claude-backend-test-counts.mjs`
- `.gitignore`
- Deleted: `frontend/lib/widgets/chat_input_bar.dart`, `frontend/lib/widgets/chat_message_bubble.dart`, `frontend/lib/widgets/voice_message_bubble.dart`
- Deleted: root `package.json`, root `package-lock.json`, `scripts/README.md`, `scripts/test-*.js`

## Verification

- `cd frontend && flutter analyze --no-fatal-infos` — PASS, no issues found.
- `cd frontend && flutter test test/widgets/message/bubble_redesign_test.dart` — PASS, 8 tests.
- `cd backend && npm test -- refresh-tokens.service.spec.ts` — PASS, 3 tests.
- `cd backend && npm test -- chat.dto.spec.ts dto.validator.spec.ts` — PASS, 41 tests.
- `cd backend && npm test -- chat-message.service.spec.ts` — PASS, 23 tests.
- `cd backend && npm run build` — PASS (`nest build`).
- `grep` for stale manual E2E type examples after review follow-up — PASS, no matches.
- `cd backend && npm test` — PASS, 328 tests / 41 suites (run through the verifier after script cleanup).
- `node scripts/verify-claude-backend-test-counts.mjs` — PASS, `OK: CLAUDE.md matches Jest (328 tests, 41 suites)`, no DEP0190 warning after fix.
- `graphify update .` — PASS, graph rebuilt (`7654 nodes`, `10931 edges`, `483 communities`).

## Notes for next session

Suspicious but not removed:

- `ComposerDiagnosticsOverlay` / `composer_probe*` still smell like temporary iOS WebKit instrumentation, but recent composer keyboard/flash work is not definitively closed. Do not remove without device evidence.
- E2E storage/liveness diagnostics are explicitly protected by `frontend/CLAUDE.md` until the underlying field issue is closed.
- Firebase `TODO_REPLACE` placeholders are setup placeholders, not safe cleanup without real Firebase config replacement.
- Code-reviewer approved tracked cleanup diff with no Critical/Important findings; minor manual E2E example consistency note was fixed before commit.
- Legacy Cloudinary URL support stays for backward compatibility.
- Historical `docs/plans/**`, `docs/futures/**`, and old session archive files still contain obsolete Cloudinary/Render/old-contract text by design; they are historical artifacts, not current instructions.

No version bump: cleanup removed dead/internal code and stale docs/scripts; no user-visible runtime behavior changed.
