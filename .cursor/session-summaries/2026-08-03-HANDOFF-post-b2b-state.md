# HANDOFF — post-B2b state, remaining queue ready to execute

**Written:** 2026-08-03 (end of the B2b session). **Read first, in order:** root `CLAUDE.md`,
the tier `CLAUDE.md` for whichever tier you touch first, `.cursor/session-summaries/LATEST.md`,
then this file. Re-verify every volatile fact below with a command you ran yourself
(`CLAUDE.md` §1) — this repo has burned agents on inherited state before.

## State at handoff

| | |
|---|---|
| Prod frontend | `0.1.6 / 0014684` — terminal-duplicate retirement + `DECRYPT_DECISION` dedupe, deployed + smoke 5/5 |
| Prod backend | `0.1.2 / ded8e1a2` — unchanged by design |
| `master` | `d404700`, tree clean, CI 4/4 green on every commit (incl. e2e-wire) |
| Tests | backend **578/47**; Flutter **1224 + 10 skipped**; analyze clean; both count verifiers OK |
| **⛔ ON MASTER, NOT DEPLOYED** | **B2b `sig_*` sealing (`13a9fd1`)** — the next frontend deploy SHIPS IT, whatever the deploy was for. See gate below. |
| Owner device | iOS Safari home-screen PWA, iPhone 14, NO Mac → no devtools EVER. Hacker-mode diag dump + Storage-sets panel are the only field instruments. iOS partitions PWA storage from Safari tabs. |
| Owner directives | Subagents: Anthropic models ONLY. Ask before the browser tool. NEVER deploy without a fresh explicit OK per deploy. NEVER tell a user to uninstall / clear site data. |

## ⛔ THE B2b DEPLOY GATE — read before ANY frontend deploy

B2b (all web Signal key material sealed as `fpsig1:` AES-256-GCM envelopes) is merged but
gated. **Two gates, in order, both owner-side:**

1. A diag dump showing **`CANARY_OK {ageDays > 7}`** (it was 5 on 08-03 → crosses ~08-05/06).
   If instead the dump shows `CONTENT_KEY_LOST` / `CONTENT_KEY_CANARY_LOST` — **STOP: do not
   deploy B2b**; that store just proved unreliable and sealing the identity into it is off
   until understood.
2. A **fresh owner deploy OK** after he has seen gate 1 pass.

Then: bump `frontend/pubspec.yaml` to `0.1.7`, commit, push, CI green, `powershell
-ExecutionPolicy Bypass -File deploy-web.ps1` from repo root (no `.\` prefix — bash eats the
backslash), smoke, owner fully closes + reopens the PWA.

**Post-deploy expectations:** `SIG_SEAL_OPEN {sealed, legacy, ms}` ring per boot (`legacy`
~126 on first boot → 0 after the drain), ONE `SIG_SEAL_DRAIN_DONE {sealed}` durable.
**Escalate on sight:** `SIG_KEY_UNAVAILABLE`, `SIG_ROWS_UNREADABLE`, or `SIG_STORE_FALLBACK`
after the first boot. Rollback story (test-pinned): old code over envelopes = E2E DOWN but
NOTHING destroyed; roll-forward recovers — never treat that state as a fresh install.

Spec + complete review record: `docs/design/web-sig-sealing.md` (§5 = 17-item falsification
plan; §3.3 lock discipline is load-bearing — ONE lock per row, NEVER nested; the reviewed
design's nested shape was an ABBA deadlock, do not reintroduce it).

## Work queue (priority order)

### 1. §2 Delete-for-me hard-delete (backend, small)

`backend/src/.../messages.service.ts` `hideMessageForUser` appends to `hiddenByUserIds` and
never checks whether EVERY participant has hidden the row — a message both sides deleted
survives until expiry, or forever without one. Fix: hard-delete once all participants hid it.
- Cannot drop on the FIRST delete; the other participant still reads it.
- Check the ACTUAL participant set, never hardcode 2. Reuse `MessagesService.parseHiddenIds`.
- Self-hosted media deleted BEFORE the row (`backend/CLAUDE.md` §8), same as
  delete-for-everyone.
- Raw SQL quotes camelCase: `"hiddenByUserIds"`. Read `backend/CLAUDE.md` before first change.
- Run `node scripts/lint-ratchet.mjs` locally before pushing (it only runs in CI otherwise).
- It is a deletion rule: falsify the guard (a one-participant hide must NEVER delete), and
  keep the backend count verifier in sync if tests change.

### 2. §3 Expiry-sweep success diagnostics (frontend, small, observability-only)

`sweepDestroyablePlaintext` records `PLAINTEXT_PURGE_INCOMPLETE` on failure and NOTHING on
success. Add success-side: ids destroyed, count, and "ran with zero destroyed". Channel rule:
`E2eDiagLog` (ring) for routine, `E2ePersistentDiag` ONLY for destructive/failure edges — the
durable log is cap-80 and noise evicts evidence (0.1.6 just cleaned it; do not re-pollute).

### 3. Owner-only blockers (nag at every natural opportunity; you cannot do these)

- **Keystore backup** — `frontend/android/keystore/fireplace-release.jks` is SINGLE-COPY on
  the dev PC. Runbook: `docs/runbooks/android-release.md` §"Backing it up".
- **`FIREBASE_SERVICE_ACCOUNT`** in VM `~/fireplace/.env` + `./deploy-backend.sh`; verify by a
  REAL push to a device, never by the boot warning disappearing.
- **Fingerprint-verify peers 54 and 90** (`PEER_IDENTITY_CHANGED` 08-03 and 07-31).

### 4. §5 Android release track — only after blockers 3 clear

Device smoke checklist in `docs/runbooks/android-release.md` (+ release-APK screenshot must be
refused), then first sideload APK. Firebase major bumps (#128) belong to the FCM session.

### Parked by owner (do NOT start unbidden)

App lock, cert pinning, sealed sender, encrypted cloud backups, app-wide incognito keyboard.
Also deferred by design: key rotation/shredding for BOTH web sealing layers (envelopes carry
`kid` from day one — code-only later); lazy open-unseal (only if `SIG_SEAL_OPEN.ms` blows the
budget).

## Watch items on any new dump

- **0.1.6 rollout:** first 3 owner boots → `DUP_TERMINAL_SEEN` (ring), then ≤14 one-time
  `DUP_TERMINAL_RETIRED {msgId, senderId, sessions}` durables for the known rows (peers
  49/52/60/83); the rows flip to the retired label. A `DUP_TERMINAL_RETIRED` for an id
  OUTSIDE that set = the class is still growing → investigate the producer.
- **Standing escalations:** any `CONTENT_STORE_FALLBACK{web-*}` / `CONTENT_KEY_LOST` /
  `CONTENT_RECORDS_UNREADABLE`; any NEW `LEDGER_RECORD_LOST` (all benign causes fixed — dump
  FIRST, cap-80 rotates, then Storage-sets). `WEB_SEAL_OPEN` should show `legacy: 0`.
- Benign, noted, not chased: ~19-20 stored-but-unledgered rows (own-message reconcile skips
  the ledger append; fail-open direction); ledger-orphans = the same ~20 pre-0.1.4 ids.

## Standing invariants (hard-won; violating any re-arms a fixed bug class)

- **Over-retention is recoverable, over-destruction is not; destructive rules fail closed.**
  Anything destruction-adjacent runs the FULL gauntlet: design doc → independent design review
  → falsified (run-RED-first) tests → parallel data-loss + spec reviews (Anthropic reviewers)
  → owner OK before deploy. Never self-review. It has paid every single time: the B2b design
  review found two identity-destruction CRITICALs in a design that already looked careful, and
  a mid-implementation advisory caught an ABBA deadlock the review itself had introduced.
- A storage/crypto failure must NEVER read as absence: absence answers drive identity
  regeneration, ratchet resets, prekey id reuse, and permanent retirement. Tri-state
  (`true/false/null`) with null strictly inert, or throw.
- Test count changes sync root `CLAUDE.md` §3 IN THE SAME COMMIT
  (`node scripts/verify-claude-frontend-test-counts.mjs` / backend twin; CI verifies).
- `flutter test` full suite ~2min; NEVER pass long explicit file lists (pathological).
  Iterate one file or `--plain-name`, full suite before commit.
- CI is detection, not prevention: `gh run list --branch master --limit 1` after every push;
  never deploy on red.
- Session end: dated summary + LATEST.md update (≤5 entries/≤2600 words, pre-commit-enforced).

## Traps paid for in the B2b session (fresh, not yet in a tier file)

- **Far-from-read hashline edits on large files corrupt sections silently** — an edit
  auto-repair swallowed a test fake's override once (the "impossible" failure looked like an
  async race) and a design-doc section once. Re-read the exact range immediately before every
  structural edit; re-verify after; grep for the symbol before debugging timing.
- Web Locks test fakes must serialize PER NAME (a single shared tail deadlocks legitimate
  nested acquisitions that real browsers allow — and hides real ABBA inversions; the
  `_RecordingLock` in `sealed_web_signal_kv_test.dart` also records acquisitions requested
  while sig-keys is held).
- `ContentKeyManager` is prefix-parameterized; sig keys are `fp_sig_key_*`. Content rotation
  must NEVER be able to destroy them — the cross-family test in
  `sealed_web_signal_kv_test.dart` pins it.
- `EncryptionService.debugSetDualStorage(...)` is the seam for throwing-storage tests
  (`encryption_service_sig_hardening_test.dart` shows the pattern).
- The `duplicate` policy keeps `persist: false` BY DESIGN (a persisted `[Decryption failed]`
  poisons the durable cache); the 0.1.6 retire rule is the complement for never-ledgered rows
  — do not "unify" them.
