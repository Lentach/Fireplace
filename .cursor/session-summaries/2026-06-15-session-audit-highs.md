# Audit High fixes — H-04 / H-01 / H-02 (0.0.57)

**Date:** 2026-06-15

## What was done
Implemented the three verified High findings from the full security audit
(`docs/audit/FINDINGS.md`, on branch `audit/full-review` / PR #8), per the
reviewer recommendation in `docs/audit/REVIEW-RECOMMENDATION.md` ("implement
H-04, H-01, H-02 now; defer the rest"). All three TDD (failing test → fix →
green). Feature branch `fix/audit-highs` off `master` — **does NOT auto-deploy;
goes live only after merge to `master`** (substantial security work).

- **H-04 — media-fetch JWT exfiltration (frontend).** `ApiService.fetchMediaBytes`
  attached `Authorization: Bearer <jwt>` on any URL whose *path* contained
  `/media/msgs/`. The media `mediaUrl` comes from the sender-controlled,
  server-unvalidated E2E envelope, so a peer's media message pointing at
  `https://attacker/media/msgs/x` harvested the recipient's access token
  (account takeover) on chat open. Fix: attach the JWT only when the resolved
  URL's origin == `baseUrl` (scheme+host+port); refuse any host that is neither
  the backend origin nor legacy `res.cloudinary.com` (throws before fetching).
- **H-01 — getMessages IDOR (backend).** `handleGetMessages` passed `userId`
  only as the deleted-for-me filter; `findByConversation` has no participant
  predicate, so any user could read any (sequential-id) conversation's history.
  Fix: load the conversation and verify caller ∈ {userOne, userTwo} before
  serving history (mirrors `handleMarkConversationRead`); non-members get an
  empty `messageHistory` and the query never runs.
- **H-02 — mediaUrl path traversal → arbitrary file delete (backend).**
  `MEDIA_URL_REGEX` ended in `/media/.+` (allowed `../`); the value is later
  `unlink`ed (delete-for-everyone / block / per-minute expiry cron), as root in
  the container. Fix (defense in depth): anchor the self-hosted branch to a
  single `(avatars|msgs)/<file>.<ext>` segment (no `/`, no `..`), AND a
  resolved-path containment check in `LocalStorageService.deleteFile`
  (`path.relative` vs `MEDIA_DIR`) that refuses anything escaping the root.

## Key files
- `frontend/lib/services/api_service.dart` (`fetchMediaBytes`) + `frontend/test/services/api_service_media_url_test.dart`
- `backend/src/chat/services/chat-message.service.ts` (`handleGetMessages`) + `backend/src/chat/services/chat-message.service.spec.ts`
- `backend/src/chat/dto/chat.dto.ts` (`MEDIA_URL_REGEX`) + `backend/src/chat/dto/chat.dto.spec.ts`
- `backend/src/media/local-storage.service.ts` (`deleteFile`) + `backend/src/media/local-storage.service.spec.ts`
- `CLAUDE.md` (H-01/H-02/H-04 notes + test count 295→305), `frontend/pubspec.yaml` (0.0.56→0.0.57)

## Verification
- `cd backend && npm test` → **305 passed / 40 suites** (was 295; +10: H-01 ×2, H-02 ×6, dto already existed).
- `node scripts/verify-claude-backend-test-counts.mjs --log …` → **OK (305/40)**.
- `cd frontend && flutter test` → **375 passed**; `flutter analyze` → **No issues found**.
- Each fix watched fail first (RED) before the fix (GREEN): H-04 "untrusted host refused",
  H-01 "non-member queried messages", H-02 "traversal accepted / deleteFile escaped".

## Notes for next session
- **VM test before merge** (per REVIEW-RECOMMENDATION §2): H-04 is device-dependent —
  verify on iPhone/Android that legit voice/image/file/gif still load and a PWA cache-bust
  is done; H-01/H-02 are backend (verify normal media send/delete + history still work).
- **Deferred (tracked, not in this PR):** M-07 (`synchronize:true` in prod — pair with a
  schema-completeness check, no migration system exists), H-03 (E2E identity pin-and-warn +
  safety-number UI — a feature), verify+fix M-02 (unscoped fcm-token delete) / M-05 (WS skips
  `passwordChangedAt`), the Low/Info sweep, and I-03 (`npm audit` / `flutter pub outdated`
  outside the sandbox). Full list: `docs/audit/REVIEW-RECOMMENDATION.md` §3.
- **Version collision note:** master was 0.0.56; this branch bumps to 0.0.57. The unmerged
  `fix/android-pwa-push-reliability` branch also bumped to 0.0.57 — whichever merges second
  must re-bump pubspec.
