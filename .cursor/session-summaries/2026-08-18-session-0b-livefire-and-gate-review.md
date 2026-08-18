# Session — Phase 0b live-fire + independent phase-gate review

**Date:** 2026-08-18 (~06:00–07:15 CEST) · branch `feat/takeover-alarm-0a` ·
worktree `C:/Users/Lentach/Desktop/fireplace-0a` · **not merged, not deployed**

Continuation of `2026-08-18-session-phase0b-registration-lock.md`. Two items
were outstanding: the 0b UI had never been rendered, and the phase-gate review
had never run (subagent quota). Both are done. Four defects came out of them;
all four are fixed on the branch and re-verified.

---

## 1. The live-fire (owner approved, browser tool)

Real Chromium against the dockerized stack (`fireplace-0a`, backend on
`127.0.0.1:3000`, Flutter web-server on `:8080`).

| Step | Result |
|---|---|
| Register + login (fresh account, user 93) | OK |
| Settings → "Klucz odzyskiwania" row | renders under BEZPIECZEŃSTWO, navigates |
| `RecoveryKeyScreen` | renders; explains 72 h → 1 h and the show-once rule |
| Generate | 12 BIP39 words in a read-only field + red show-once warning |
| **"Zapisałem/am"** | success toast in **~1.2 s**, pops back to Settings |
| Server proof | `recovery_keys` row for user 93, `$argon2id$v=19$m=19456,p=1,t=2` — the OWASP profile the spec pins |
| Keyless-device simulation (delete `sig_e2e_93_*`, reload) | pre-existing "no keys on this device" banner, consent dialog |
| Consent to re-mint | **refused by the lock** — locked banner "your new keys were not published", no silent swap |
| "Rozpocznij reset" → "Użyj klucza" + the 12 words | banner "za 59 minut"; DB row `shortened=t`, deadline exactly 1 h |
| Cancel from tab 1 | countdown cleared in **both** open tabs; row `cancelled` server-side |

**The chain nothing tested is correct.** `_confirmSaved` polls
`recoveryKeySetResult`, which only arrives via `setRecoveryKey` → server →
`recoveryKeySet` → `ConnectionProvider._registerEventListeners` →
`EncryptionProvider.onRecoveryKeySet`. It answered in ~1.2 s against a real
socket — the 6 s poll bound was never approached.

---

## 2. Defect A — the countdown did not survive a restart (Priority 1)

Found by the frontend reviewer, then reproduced live: with a pending ceremony
running, a page reload showed the **locked** banner claiming 72 h and offering
to start a reset that was already running. No countdown, no Cancel.

`_identityResetDeadline` is memory-only by design, hydrated from
`ownKeyBundleStatus` — but the only emit of `checkOwnKeyBundle` sat inside the
identity guard, which runs **only when the local identity is absent**
(`encryption_service.dart` gated on `IdentityLoadResult.absent`). A healthy
device therefore never re-hydrated. The content-free push tells the user to
open the app and cancel; the app opened with nothing to cancel. The cancel
affordance is the entire reason the delay exists.

Fix: `EncryptionProvider.refreshOwnAccountStatus()` emitting `checkOwnKeyBundle`,
called from `ConnectionProvider._onSocketReady` on **every** connect — next to
the four list fetches already made there, so the cost argument is settled by
precedent. Re-verified live: after a reload the banner reads "za 43 minuty"
with Cancel, and cancelling still clears both tabs.

Also fixed alongside it: `_hydrateIdentityResetState` now asks
`data.containsKey('identityReset')`. Dart returns null for both an absent key
and an explicit null, so a payload that merely omitted the field would have
wiped a live countdown instead of leaving it alone, contradicting the
function's own contract.

---

## 3. Defect B — `synchronize` was deleting the one-pending guard

Migration `0014` creates the partial unique index
`uq_identity_reset_requests_one_pending`. The entity did not declare it, and
TypeORM `synchronize` (on in every environment except production) **drops
indexes the entity does not know about**.

Proven, not inferred:

1. `\d identity_reset_requests` on the dev database — index absent, even though
   `schema_migrations` records `0014_identity_reset.sql` as applied.
2. Created it by hand; `pg_indexes` showed three indexes.
3. `docker compose restart backend`, waited for `/health` 200 — index gone.

So every dev and CI run had **no** one-pending guard; the only thing refusing a
second pending row was the application-level pre-check, which is precisely the
read-then-write the index exists to replace. Production (synchronize off) kept
the index, so this was a dev/CI divergence in the environments meant to catch a
regression — and it means the earlier "partial index proven behaviourally"
claim did not hold for the tree that produced it.

Fix: the entity mirrors the index under the same name. After a restart
`pg_indexes` shows it surviving, and a manual double
`INSERT ... status='pending'` is refused by the constraint.

---

## 4. Defect C — a lost race could burn the recovery phrase

`requestReset` spends the phrase (stamping `usedAt`) *before* inserting the
pending row, inside one transaction. If a concurrent phrase-less request
committed first, the loser hit the unique index, and the old catch block
returned the winner's 72 h deadline **from inside the transaction** — which
commits. The user's single-use phrase was spent on a ceremony it did not
create, leaving them on the un-shortened deadline with nothing left to shorten
a retry (and a 24 h cooldown if they cancelled to try again).

Fix: the conflict now throws `PendingResetConflict`, so the transaction rolls
back and un-spends the phrase; the winner is read afterwards, outside the
transaction, and reported as `existing`. Pinned by a test that asserts both the
reported deadline and that the transaction rejected (a real transaction rolls
back on exactly that).

## 5. Defect D — the failed-attempt counter was read-modify-write

`spendRecoveryPhrase` read `failedAttempts`, added one in JS, and wrote it
back, so two concurrent failures both stored the same value and bought extra
attempts before the 5-failure lockout. Now a single
`SET "failedAttempts" = "failedAttempts" + 1` with the lockout decided by a
`CASE` on the row's own value and `RETURNING` the stored count. Defence in
depth was never gone (10/15 min throttle, 19 MiB Argon2id per verify, 128-bit
phrase), but the counter is now honest.

---

## 6. Review verdicts

Two `reviewer` subagents over the full delta `50434a8..HEAD`, split
backend/protocol and frontend, defensively framed.

- **Backend: GATE PASS.** Terminal, correctly serialized state machine;
  `COMPLETED_GRANT_TTL_MS` genuinely closes the standing-grant hole with
  `consumedAt` single-use; signature verification fail-closed, buffer copies,
  single-use socket-bound nonce with TTL; Argon2id at the pinned profile with
  no phrase or verifier logging; exactly one caller of the bundle-write gate,
  no REST bypass. Findings were the two races above plus the entity/index
  divergence and the known completed-ceremony coverage gap.
- **Frontend: the P1 above**, plus confirmation by static trace that the
  enrolment round trip is correctly wired (the live-fire then confirmed it by
  execution), and that alarm-suppression clearing, phrase hygiene, push
  branches, the UNKNOWN invariant and en/pl ARB parity are all correct.

**Accepted, not fixed** (both Priority 3, owner's call): the reset banner is
not a `Semantics(liveRegion: true)`, so a screen reader does not announce it;
and a recovery-key save attempted with a down socket shows the generic failure
toast after ~6 s instead of "you are offline".

---

## 7. Verification run on this machine

| Check | Result |
|---|---|
| `cd backend && npm test` | **763 / 51 suites** green (+1 new test) |
| `node scripts/lint-ratchet.mjs` | **PASS**, real errors held at 906, formatting 147 |
| `cd frontend && flutter analyze --no-fatal-infos` | clean |
| `cd frontend && flutter test` | **1361 / 10 skipped** (+2 new tests) |
| `E2E_BASE_URL=http://127.0.0.1:3000 flutter test test_e2e` | **19 / 2 skipped** against real backend + Postgres |
| Index survives a backend boot | `pg_indexes` after restart + refused duplicate insert |
| 0b UI | live-fired, §1 |

Root `CLAUDE.md` §3 counts updated to 763 / 1361 in the same commit, per the
per-tree truth rule.

---

## 8. Traps added tonight

- **CanvasKit `tab.click('aria-ref=…')` can time out on banner buttons** even
  though the node exists. Read the `flt-semantics` element's bounding box and
  use `page.mouse.click(x, y)`.
- **Typing into a freshly focused Flutter web field drops characters** — a
  registration meant to be `lf26631221` was stored as `lf2`. Snapshot the field
  and read back its value before submitting.
- **Postgres in this stack stores UTC** while the shell shows CEST. A deadline
  that looks two hours stale is usually not stale — convert before concluding
  the cron is broken.
- `docker compose restart backend` needs **2–4 min** before `/health` answers
  200; the index/synchronize check is only meaningful after that, because
  synchronize runs when Nest initialises TypeORM, not at container start.

---

## 9. What is next

1. **Actions billing** (owner) — six pushes, zero runs. Then re-run PR #144 and
   require 4/4 green. Never merge on red, and not at all until program end.
2. Phase 1 (schema: `devices`, `(userId, deviceId)` bundles/OTPs, re-keyed
   3-site epoch, JWT `deviceId`, `originDeviceId` + `sendToken`) — read
   `2026-08-17-HANDOFF-multidevice-execution.md` for its file:line landmines
   and build the two-devices-one-account harness suite first.
3. Standing owner blockers unchanged: `FIREBASE_SERVICE_ACCOUNT` on the VM,
   `.jks` off-PC backup.
