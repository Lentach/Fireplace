# Sticky sessions auth hardening

**Date:** 2026-07-04

## What was done

- Root-caused spontaneous persistent logout to refresh-token single-use rotation, not storage eviction and not source-side JWT_SECRET regeneration.
- Changed backend refresh sessions from single-use rotation to stable 365-day sliding opaque refresh tokens: `/auth/refresh` now extends the existing hashed row and returns the same refresh token value, so a lost refresh response can be retried instead of converting into `401 Invalid refresh token` plus client logout.
- Added privacy-safe auth/session-end reason logs without token/secret values:
  - backend refresh invalid/expired;
  - backend HTTP JWT guard expired/invalid-signature/invalid access with query-stripped path;
  - backend socket auth missing/expired/invalid/password-changed;
  - frontend local session clears (`refresh_invalid`, `refresh_invalid_after_access_401`, `access_401_without_refresh`, `expired_access_without_refresh`, `password_changed`, `explicit_logout`).
- Added `AuthProvider.isRestoringSession` and made `AuthGate` show a neutral spinner while saved auth is being restored, so boot no longer flashes login before silent refresh resolves.
- Made frontend password reset clear local auth immediately with reason `password_changed`, matching backend refresh-token revocation/passwordChangedAt invalidation.
- Documented JWT_SECRET as generated once, persisted in VM `.env`/encrypted backups, and copied unchanged during host moves; normal deploys must never regenerate it.
- Updated docs for stable/sliding refresh tokens and bumped user-visible version to `0.0.86`.
- Ran code review twice; fixed the first review's Critical/Important findings. Follow-up review reported no Critical auth/security blockers; remaining process issues were test count docs and untracked files, both addressed before commit.

## Key files

- `backend/src/auth/refresh-tokens.service.ts`
- `backend/src/auth/refresh-tokens.service.spec.ts`
- `backend/src/auth/auth.service.ts`
- `backend/src/auth/auth.service.spec.ts`
- `backend/src/auth/jwt-auth.guard.ts`
- `backend/src/auth/jwt-auth.guard.spec.ts`
- `backend/src/chat/chat.gateway.ts`
- `frontend/lib/providers/auth_provider.dart`
- `frontend/lib/main.dart`
- `frontend/test/providers/auth_provider_session_test.dart`
- `frontend/test/main/auth_gate_session_restore_test.dart`
- `AGENTS.md`
- `CLAUDE.md`
- `backend/CLAUDE.md`
- `frontend/CLAUDE.md`
- `docker-compose.prod.yml`
- `deploy-backend.sh`
- `frontend/pubspec.yaml`

## Verification

- `cd backend && npm test` → 42 suites passed, 381 tests passed.
- `cd backend && npm test -- src/auth/auth.service.spec.ts src/auth/refresh-tokens.service.spec.ts src/auth/jwt.strategy.spec.ts src/auth/jwt-auth.guard.spec.ts src/chat/chat.gateway.spec.ts` → 5 suites passed, 28 tests passed.
- `cd backend && npm run build` → passed.
- `cd frontend && flutter test test/providers/auth_provider_session_test.dart test/main/auth_gate_session_restore_test.dart` → 6 tests passed.
- `cd frontend && flutter analyze --no-fatal-infos` → no issues.
- `node scripts/verify-claude-backend-test-counts.mjs` → `OK: CLAUDE.md matches Jest (381 tests, 42 suites)`.
- `graphify update .` → graph rebuilt.

## Notes for next session

- Branch: `fix/sticky-sessions`.
- Production deploy sequence after merge: backend deploy on VM via `./deploy-backend.sh`; frontend deploy from PC via the root `deploy-web.ps1` script. Do not build Flutter web on the VM.
- The production `JWT_SECRET` was exposed in chat during this session. After merging/deploying sticky-session refresh, rotate it in prod `.env`, redeploy backend, and copy the new value to Hetzner later; valid refresh sessions should silently recover new access JWTs.
- Password reset/recovery remains a product gap for users who are already logged out and forgot their password; this session only handled session invalidation after a successful in-app password reset.
