# Full-stack E2E Signal wire harness + burned-but-never-served OTP backend fix

**Date:** 2026-07-08 (0.0.96, branch `feat/e2e-wire-harness`)

## What was done

**1. New two-account full-stack E2E wire harness (`frontend/test_e2e/`)** — the missing verification layer for the E2E stack: real `ApiService` (REST auth) + real `SocketService` (Socket.IO) + real `EncryptionService` (real libsignal, in-memory-mocked key storage only) driven headless against a live local backend (`docker-compose up`). Deliberately a **sibling of `test/`** so the default `flutter test` and CI never pick it up. 7 tests, ~3 s of test time:

1. register → `socketReady` → WS key upload (two fresh accounts)
2. friend request/accept → conversation open (accept-flow and `startConversation` land on the same conversation)
3. first message PreKey (`3:`), server stores only `[encrypted]`, peer decrypts exact plaintext
4. replies ratchet to whisper (`2:`) both directions in order; same plaintext twice ⇒ distinct ciphertexts, both decrypt
5. mid-conversation session rebuild (`deleteSession` → fetch bundle → `3:` again, peer recovers) — the shape of the 2026-07 field incidents
6. `editMessage` ciphertext swap (`messageEdited` both sides + re-decrypt) and non-sender rejection (`not_sender`)
7. reactions round-trip + strict no-unexpected-`error`-events sweep

Design decisions that matter:
- **Fresh accounts every run** (random-suffix usernames). Reusing accounts with fresh client keys would deterministically be served a STALE previous-run OTP (`fetchPreKeyBundle` claims oldest-first; uploads never purge) → phantom bad-MAC. Persisting the client Signal store across runs was rejected as fragile test infra. Register throttle 10/hr/IP is in-memory → `docker compose restart backend` resets it.
- flutter_test's binding 400-blocks ALL real HTTP incl. the WS upgrade; harness resets `HttpOverrides.global` (global, not zone-local — socket.io reconnect timers escape zones).
- Bundle fetches are paced 850 ms per peer to stay under the server's 750 ms per-pair limiter.
- `/health` preflight fails fast with a "start docker-compose up" message instead of timeout soup.

**2. REAL PRODUCTION BUG found by the harness on its first run and fixed:** `key-bundles.service.ts` `fetchPreKeyBundle` destructured `const [otp] = await repo.query(UPDATE … RETURNING …)` — but Postgres returns `[rows, rowCount]` for UPDATE (the documented backend/CLAUDE.md §4 trap, same class as the secret-notes 42703 bug). Result: **every pre-key bundle ever served had `oneTimePreKeyId: null` while still burning the OTP (`used=true`)** — X3DH always ran without the one-time pre-key's forward-secrecy contribution, and OTPs were consumed for nothing. Empirically confirmed (DB showed `used=t` while wire delivered null). Fixed the destructure; fixed the unit spec mocks that had encoded the wrong rows-only shape (which is why 407 unit tests never caught it).

**3. Latent bug flagged, NOT fixed (needs owner decision):** identity regeneration (fresh install, same account) re-uploads bundle + new OTPs but old unused OTPs are never purged; peers then get served a stale OTP oldest-first → undecryptable PreKey messages. `backend/src/key-bundles/key-bundles.service.ts:50+`. Suggest: delete user's OTPs on `upsertKeyBundle` (bundle re-upload implies new identity/prekey generation) — separate change, not in this branch.

## Key files

- `frontend/test_e2e/support/e2e_test_client.dart` — NEW: `E2eClient` (per-account service stack) + buffered `EventLog.next()` awaiter + `enableRealNetwork()` + `/health` preflight
- `frontend/test_e2e/full_stack_e2e_test.dart` — NEW: setUpAll pipeline + the 7 flows
- `backend/src/key-bundles/key-bundles.service.ts` — OTP claim `[rows, rowCount]` destructure fix
- `backend/src/key-bundles/key-bundles.service.spec.ts` — mocks now use the real Postgres tuple shape
- `frontend/pubspec.yaml` — 0.0.96
- `CLAUDE.md`, `AGENTS.md`, `frontend/CLAUDE.md`, `backend/CLAUDE.md` — harness invocation contract + §4 trap example extended
- `.planning/e2e-wire-harness/` — task plan + scout findings

## Verification

- `cd frontend && flutter test test_e2e` (live docker backend): **7/7 green**, twice consecutively (rerun stability with fresh accounts proven). First run pre-fix failed exactly on the OTP bug.
- DB evidence for the bug: `one_time_pre_keys` showed `keyId 0, used=t` for the fetched user while the wire carried `oneTimePreKeyId: null`.
- `cd backend && npm test`: **407/407, 42 suites** (count unchanged → CLAUDE verifier intact).
- `cd frontend && flutter analyze --no-fatal-infos`: **No issues found**.

## Notes for next session

- **Backend deploy owed after merge**: the OTP fix must reach prod via `./deploy-backend.sh` on the VPS (no schema change; no frontend rebuild needed — harness + version bump only touch repo/docs). All existing prod sessions are unaffected (they were built without OTPs; new fetches simply start serving them).
- PR from `feat/e2e-wire-harness` — do NOT merge to `master` without owner OK.
- Latent stale-OTP-on-identity-regeneration bug (see above) awaits owner approval for a purge-on-reupload fix.
- Harness phase 2 candidates: encrypted media round trip (needs `webcrypto` native setup on the test VM), disappearing messages, delete flows, push-skip assertions via `pushClientState`.
