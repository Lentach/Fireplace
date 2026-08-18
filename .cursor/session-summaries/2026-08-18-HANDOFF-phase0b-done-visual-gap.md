# HANDOFF — Multi-device: 0a + 0b BUILT, live-fired and gate-reviewed. Start here.

**Date:** 2026-08-18 (written ~05:00 CEST, §0/§7 rewritten ~07:00 after the
live-fire and the phase-gate review)

**⛔ Do NOT rebuild 0a or 0b. Both are done, pushed, and evidence-backed.**
The visual gap this handoff was written around is CLOSED. Everything below is
still current; nothing here is guessed — every claim was produced by a command
run on this machine.

---

## 0. THE VISUAL GAP IS CLOSED — what the live-fire proved (and broke)

Run in a real headless Chromium against the dockerized stack, 2026-08-18
~06:20–06:45 CEST, owner-approved.

**Proven working, end to end:**

1. **Settings → Recovery key row** renders under BEZPIECZEŃSTWO and navigates.
2. **`RecoveryKeyScreen`** renders; "Wygeneruj klucz odzyskiwania" produces 12
   BIP39 words in a read-only field with the show-once warning.
3. **The ack round-trip — the one nothing tested — IS correctly wired.**
   "Zapisałem/am" returned the success toast in ~1.2 s (the 6 s poll never got
   near its bound) and Postgres held
   `$argon2id$v=19$m=19456,p=1,t=2` for that user: the OWASP profile, live.
4. **The registration lock refuses an unauthorized re-mint in the real client.**
   Deleting the `sig_e2e_<uid>_*` keys and reloading reproduces a keyless
   device; consenting to "Utwórz nowe klucze" now ends in the locked banner
   ("your new keys were not published"), not a silent identity swap.
5. **The recovery key shortens the ceremony:** "Użyj klucza" → banner reading
   "za 59 minut", DB row `shortened=t`, deadline exactly 1 h after the request.
6. **Cancel is room-wide:** clicking it in one tab cleared the countdown in a
   second open tab, and the row went `cancelled` server-side.

**Two real defects the live-fire and the review found — both now FIXED and
re-verified live:**

- **The countdown did not survive a restart.** Reloading the page with a
  pending ceremony showed the *locked* banner claiming 72 h and offering to
  start a reset that was already running — no countdown, no Cancel. The
  deadline lives in memory only and was hydrated exclusively by
  `checkOwnKeyBundle`, which the client emitted ONLY when its local identity
  was absent. So the push that says "open the app and cancel" led to a screen
  with nothing to cancel. `ConnectionProvider._onSocketReady` now calls
  `EncryptionProvider.refreshOwnAccountStatus()` on every connect. Re-verified:
  after a reload the banner reads "za 43 minuty" with Cancel.
- **`synchronize` was deleting the one-pending guard in every non-prod
  database.** Migration 0014 creates the partial unique index
  `uq_identity_reset_requests_one_pending`, but the entity did not declare it,
  and TypeORM `synchronize` (on everywhere except production) DROPS indexes it
  does not know. Proven by hand: created the index, restarted the backend,
  watched it disappear once Nest finished booting. Every dev and CI run — and
  therefore the earlier "partial index proven behaviourally" claim — had no
  index; the only thing refusing a second pending row was the application-level
  pre-check, which is exactly the read-then-write the index exists to replace.
  The entity now mirrors it; after a restart the index survives and a manual
  double `INSERT ... 'pending'` is refused by the constraint.

**CanvasKit traps (still true):** the accessibility tree is EMPTY until you
click Flutter's "Enable accessibility" placeholder (`flt-semantics-placeholder`);
`tab.click('aria-ref=…')` sometimes times out on banner buttons — read the
`flt-semantics` node's bounding box and use `page.mouse.click`; typing into a
freshly-focused field can drop characters (a registration typed `lf2` instead of
the full name), so snapshot the field before submitting.

---

## 1. Where everything lives

| Thing | Value |
|---|---|
| Worktree (ALL multi-device work) | `C:/Users/Lentach/Desktop/fireplace-0a` |
| Branch | `feat/takeover-alarm-0a`, == origin at `7ab6495` |
| Main checkout (master, other sessions) | `C:/Users/Lentach/Desktop/Fireplace` |
| master head | `4bd4316` (docs-only pointer to this branch) |
| PR | **#144**, open, title `[HOLD until full multi-device]` |
| Spec | `docs/design/multi-device.md` — **v5 FROZEN** |

Commits on the branch, newest first:

```
7ab6495 feat: recovery-key enrolment UI — generate, show once, use during reset
d79feb5 fix: do not warn a device about the identity replacement it performed
ea0f7bf docs: Phase 0b session summary + LATEST rotation
4475e0f test: Phase 0b wire harness + fix the recovery flow 0b silently broke
321f530 feat: Phase 0b frontend — reset countdown banner, cancel, hydration
07c4a39 feat: Phase 0b backend — registration lock, reset ceremony, recovery key
50434a8 docs: 0a evidence  ← Phase 0a ends here
```

**Reading order:** root `CLAUDE.md` → `backend/CLAUDE.md` → `frontend/CLAUDE.md`
(§5) → `docs/design/multi-device.md` §6 → `2026-08-17-HANDOFF-multidevice-execution.md`
(Phase 1/2 landmines, still fully valid) → `2026-08-18-session-phase0b-registration-lock.md`
(this phase's detail) → this file.

---

## 2. Owner rules — binding, learned the hard way

1. **Investigate and PROVE, then ASK before writing code.** Diagnostics count as
   code. I nearly broke this tonight by starting the enrolment UI unprompted;
   caught it, reverted to a clean tree, asked, got approval. Do the same.
2. **Ask before opening the browser tool — every single time.**
3. **Never merge or deploy without explicit OK.** Ruling 2026-08-18: the WHOLE
   multi-device program (0b → 1 → 2 → 3 → optional 4) accumulates on this one
   branch, ONE merge at the end. PR #144 is a review surface, not a merge queue.
4. **Never self-review.** Use a subagent (`reviewer` type, defensive framing —
   `security-reviewer` gets content-filtered on adversarial wording).
5. Anthropic-only subagents, writer concurrency ≤ 2.
6. Keep security prose defensive (detection / protection / recovery). Attack
   framing has tripped provider content filters three times across sessions.

---

## 3. What Phase 0a shipped (already reviewed SHIP, live-fired)

Identity-replacement alarm. `upsertKeyBundle` replacing a stored identity writes
a durable `identity_change_audit` row (migration `0013`) and fans out:
`ownIdentityReplaced {occurredAt}` to the account's OTHER sockets (uploader
excluded by `client.to(room)`), a content-free `{type:'identity_changed'}` push,
and `peerIdentityChanged {userId, occurredAt}` to every conversation peer.

**Landmine that cost a live debug session:** the entity must be registered in
BOTH `KeyBundlesModule.forFeature` AND the `app.module.ts` DataSource `entities`
array. Missing the second throws `EntityMetadataNotFoundError` at runtime while
every mocked unit test stays green. Only the wire harness caught it. Same rule
applies to 0b's two new entities.

---

## 4. What Phase 0b shipped

### 4.1 Registration lock (§6.1)

Replacing a stored identity key now requires authorization. Two things grant it:

- an XEdDSA signature by the **previous** identity key over
  `newIdentityPublicKey ‖ userId ‖ serverNonce`, or
- a **completed** reset ceremony, which the upload SPENDS (single-use).

A refusal writes **nothing at all** — no bundle, no OTP purge, no audit row, no
alarm — and answers `keyBundleUploaded { success:false, error:'identity_locked' }`.
Same-identity re-uploads (the every-connect path) and first-ever uploads are
untouched.

Nonces: `getRegistrationLockNonce` → `registrationLockNonce { nonce }`, 32
CSPRNG bytes, TTL 5 min, stored on `client.data.registrationLockNonce`, consumed
by ONE upload attempt **whether or not that attempt was valid**.

Verification lives in `backend/src/key-bundles/identity-signature.util.ts`; the
gate itself is in `key-bundles.service.ts` `authorizeIdentityChange`, called
BEFORE the upsert.

### 4.2 Reset ceremony (§6.2)

Table `identity_reset_requests` (migration `0014`). Terminal states
`pending → cancelled | completed`. 72 h delay. One pending per account enforced
by a **PARTIAL UNIQUE INDEX**, not a read-then-write check. 24 h cooldown after a
cancel. Per-minute cron (`completeDueResets`) whose `status='pending'` predicate
**is** the serialization point against a racing cancel.

A completed grant is spendable for **24 h only** (`COMPLETED_GRANT_TTL_MS`) —
see §6 for why that bound exists.

### 4.3 Recovery key (§6.2.1)

Table `recovery_keys`. Server stores ONLY an Argon2id verifier
(19 MiB / t=2 / p=1, owner-pinned OWASP profile). Presenting a valid phrase
shortens the delay to 1 h — it never silences notifications, never grants an
instant replacement. Single-use, spent in the same transaction that creates the
ceremony, invalidated by any completed reset, lockout after 5 failures.

### 4.4 Client

- Countdown banner in `main_shell.dart` with one-tap cancel; also covers the
  "your keys were refused" state with a **Start reset** action.
- `startIdentityResetFlow` asks for a recovery phrase FIRST at every entry point
  (BIP39 checksum validated locally so a typo cannot burn one of the five
  server attempts). Backing out starts nothing.
- Settings → Recovery key screen: generates 12 BIP39 words locally, shows once,
  never persists them.
- Push branches for `identity_reset_pending` / `identity_reset_cancelled` in
  `web/web-push-sw.js` and `android_fcm_local_notifications.dart`.

### 4.5 Owner decisions (do not relitigate)

| Decision | Value | Why |
|---|---|---|
| Signature verify lib | **`curve25519-js`** | backend image is `node:22-alpine`; `@signalapp/libsignal-client` ships NO musl prebuild and dies at require-time |
| Argon2id params | m=19456, t=2, p=1 | OWASP profile; 64 MiB default is a DoS lever on the small VPS |
| Phrase format | true BIP39, 12 words | checksum catches typos before they cost a rate-limited attempt |
| Peer pending-reset surface | **deferred** | 0b notifies the account's own sessions only |
| Dart BIP39 package | **`bip39_mnemonic` 4.1.0** | the `bip39` package the owner named pins `sdk <3.0.0` (pre-null-safety) and cannot resolve — same standard, same 2048-word list |

---

## 5. Wire contract (also in root `CLAUDE.md` §7 on this branch)

**There are NO socket.io callback acks in this codebase — everything is
request-event → response-event.** I nearly shipped two incompatible shapes by
assuming otherwise.

| Client emits | Server emits back |
|---|---|
| `getRegistrationLockNonce` | `registrationLockNonce { nonce }` |
| `uploadKeyBundle` (+ optional `identitySignature`, `nonce`) | `keyBundleUploaded { success }` or `{ success:false, error:'identity_locked' }` |
| `resetIdentityRequest { recoveryPhrase? }` | `identityResetStatus { status, deadlineAt?, shortened? }` — status ∈ pending·existing·cooldown·invalid_phrase·locked |
| `resetIdentityCancel` | `identityResetCancelResult { cancelled }` |
| `setRecoveryKey { phrase }` | `recoveryKeySet { success }` |
| `checkOwnKeyBundle` | `ownKeyBundleStatus { exists, identityReset, identityReplacedAt }` |

Room broadcasts: `identityResetPending { deadlineAt, shortened, occurredAt }`
and `identityResetCancelled { occurredAt }` go to the WHOLE user room including
the requester. Pushes are content-free: `{type:'identity_reset_pending'}` /
`{type:'identity_reset_cancelled'}`.

`ownKeyBundleStatus` extras are ADDITIVE — a missing/malformed payload must
still mean UNKNOWN and must never authorize key generation (0.1.10 invariant).

---

## 6. Three defects found and fixed while building — do not reintroduce

1. **Permanent standing grant.** `cancelReset` only touches a `pending` row, so
   once the sweep flipped a ceremony to `completed`, nothing could ever clear
   it: an account whose owner recovered and simply stopped kept an indefinite,
   un-cancellable instant-replacement grant — exactly the zero-delay path
   §6.2.1 forbids. Fixed with `COMPLETED_GRANT_TTL_MS` (24 h).
2. **0b silently broke consented recovery.** `_runIdentityRecovery` cleared the
   damaged-identity state and reported success BEFORE its fire-and-forget
   upload, which 0b refuses. A user who lost their keys would be told they
   recovered while the server still served their OLD bundle — peers keep
   encrypting to keys that device cannot read, with no indication. Fixed: the
   refusal is durable and the banner offers the only action that resolves it.
3. **Self-inflicted false alarm.** The new connect-time replay
   (`identityReplacedAt`) warned the recovering device about its OWN recovery —
   it is a fresh install with no dismissal watermark. Fixed with
   `markOwnIdentityPublished()` (10-minute clock-skew allowance, because the
   audit row is server-stamped and the watermark device-stamped).

---

## 7. Evidence ledger — what is proven and HOW

| Claim | Evidence |
|---|---|
| Backend suite | **763 tests / 51 suites** green (`cd backend && npm test`) |
| Lint ratchet | **PASS, held at 906** baseline; formatting improved 154 → 147 |
| Frontend suite | **1361 / 10 skipped**, `flutter analyze` clean |
| Wire harness | **19 / 2 skipped** against real backend + real Postgres |
| Signature compatibility | vector generated by the REAL Flutter client verifies under `curve25519-js`; tamper / replay / wrong-key all fail; 33-byte key throws unless the `0x05` prefix is stripped. **Pinned as `identity-signature.util.spec.ts`** so a dependency swap fails loudly |
| Red-first | pre-0b code ACCEPTED an attacker-chosen identity with no authorization; post-0b the same attempt throws `IdentityLockedError`. Demonstrated by reverting the gate file and re-running |
| Migration 0014 | applied in the REAL boot path — `applying` → `applied` in container logs |
| One-pending index | live Postgres: with the index present a 2nd pending insert is refused by `uq_identity_reset_requests_one_pending`. **⚠️ Until 2026-08-18 07:00 the index was NOT present in dev/CI at all** — `synchronize` dropped it on every boot because the entity did not declare it (§0). Now mirrored on the entity and re-proven to survive a restart |
| Completed ceremony | live-fire: backdated the deadline, the REAL per-minute cron committed it, unsigned replacement then ACCEPTED once, second REFUSED, `consumedAt` set |
| **0b UI rendering** | **VERIFIED live in Chromium — §0.** Enrolment round trip, `$argon2id$v=19$m=19456,p=1,t=2` row, lock refusal in the real client, 1 h shortened ceremony, room-wide cancel across two tabs |

The completed-ceremony probe was a throwaway (it shells out to
`docker compose exec`) and was deleted, so that cron→gate path now has **unit
coverage only**. Re-create it from §0's psql snippet if you touch the sweep.

---

## 8. Open items

### Blocked on the owner

- **GitHub Actions is not scheduling runs at all.** Six pushes to a
  `pull_request`-triggered workflow produced ZERO runs; earlier runs died in
  2–4 s with no logs, on ALL branches, while githubstatus was green. Almost
  certainly an Actions minutes / spending limit →
  **github.com/settings/billing**. Never merge on red (and never merge at all
  until program end).
- `FIREBASE_SERVICE_ACCOUNT` absent from `~/fireplace/.env` on the VM → FCM dead
  in prod. 0b's pushes reach PWA endpoints only. Verify with a REAL device push.
- `.jks` keystore off-PC backup (`docs/runbooks/android-release.md`).

### Phase-gate review — DONE 2026-08-18 ~06:30 CEST

Two `reviewer` subagents over the full delta `50434a8..HEAD`, split
backend/protocol and frontend, defensively framed.

- **Backend verdict: GATE PASS.** State machine terminal and correctly
  serialized, completed-grant bound genuinely closes the standing-grant hole,
  signature verification fail-closed with buffer copies and a single-use
  socket-bound nonce, Argon2id at the pinned profile with no phrase logging,
  and exactly one caller of the bundle-write gate (no REST bypass).
- **Frontend verdict: one Priority-1 protection gap** — the pending-reset
  banner never re-hydrated for a healthy device. Reproduced live, fixed, and
  re-verified live (§0). The reviewer also confirmed by static trace what the
  live-fire then confirmed by execution: the recovery-key enrolment round trip
  IS correctly wired.
- **Findings fixed on the branch:** connect-time hydration; `containsKey` so an
  ABSENT `identityReset` field cannot wipe a live countdown (Dart returns null
  for both absent and explicit-null); the phrase-spend rollback when a
  concurrent request wins the insert race (the loser used to commit its spent
  single-use phrase and still get the winner's un-shortened 72 h); the
  failed-attempt counter is now incremented in SQL instead of read-modify-write.
- **Findings ACCEPTED, not fixed** (both Priority-3, owner's call): the reset
  banner is not a `Semantics(liveRegion: true)`, so a screen reader does not
  announce it; and a recovery-key save with a down socket shows the generic
  failure toast after ~6 s rather than "you are offline".

### Gaps in OUR OWN 0b code — read before trusting the green suites

- **No automated test ever reaches `status='completed'`.** Every wire test
  asserts a REFUSAL. The single proof that a locked-out user can get back in
  was the throwaway probe, now deleted (§7). So the chain
  sweep → `completed` → `consumeCompletedReset` → gate-allows is covered only
  by mocked unit tests. **Re-create the probe from §0's psql snippet whenever
  you touch the ceremony or the sweep**, and treat "suite green" as saying
  nothing about that path.
- **Two hygiene defects were found late and FIXED in the final commit** — named
  here so you spot the pattern rather than re-introduce it: (a)
  `_expectingOwnIdentityPublish` was set before the upload emit but never
  cleared on the refusal returns, so a later unrelated success could stamp a
  self-publish watermark it never earned and mute a genuine
  `identityReplacedAt` alarm for the 10-minute skew allowance — the enrolment
  work made refusal the DESIGNED path, which is what made it reachable; (b)
  enrolment sent `words.join(' ')` while verification sent `normalize(input)`
  — identical today, but nothing enforced it, and a normalization change would
  produce a different byte string, a failing `argon2.verify`, and lockout
  attempts burned on a phrase the client had just called valid. Both now go
  through one function and are pinned by tests.
- **The 10-minute skew allowance is a deliberate trade, not an oversight.** A
  replacement by another session within 10 minutes of this device's own publish
  is not surfaced by the connect-time path. It is still refused by the lock
  unless signed or ceremony-backed, so the exposure is a missed notification,
  not a missed defence.

### Known bug, NOT ours

`frontend/test/widgets/input/chat_input_bar_attachment_test.dart` →
"video-then-caption keeps the media-first ordering contract" fails roughly **two
runs in three** (`Expected: ['VIDEO','TEXT'] Actual: ['VIDEO']`). Proven
independent of 0b by stashing every `lib/` change and reproducing it. It will
redden CI intermittently. Deserves its own session; do not drive-by fix it.

---

## 9. Traps and recipes (all paid for in real time)

**Verification commands**

```bash
cd backend && npm test                       # 763/51
node ../scripts/lint-ratchet.mjs             # must stay ≤ 906 real errors
cd frontend && flutter analyze --no-fatal-infos && flutter test   # 1361/10sk
# wire harness (needs the stack up):
cd frontend && E2E_BASE_URL=http://127.0.0.1:3000 flutter test test_e2e   # 19/2sk
```

- **`localhost:3000` is broken on this PC** — a stale `wslrelay.exe` squats
  `[::1]:3000` (accepts then closes, curl exit 52) and docker-proxy binds only
  `0.0.0.0`. **Always `127.0.0.1:3000`.**
- **`flutter test` must NEVER get a file list** — per-argument compile cost; 45
  files timed out past 11 min while the whole suite runs in ~3 min. One file or
  one directory is fine.
- **⚠️ Harness registration ceiling.** `/auth/register` is throttled **10/hour
  per IP**, in-memory, and the suite now spends **exactly 10**. Adding an
  account to ANY harness file trips it. `docker compose restart backend` resets
  the counter (then wait 2–4 min for the nest watch build).
- The nest `--watch` container sometimes recompiles without relaunching —
  `docker compose restart backend` fixes it.
- Count verifiers re-run the whole suite unless you feed them a log:
  `flutter test > test-output.txt 2>&1` then
  `node scripts/verify-claude-frontend-test-counts.mjs --log frontend/test-output.txt`.
  **Delete the log before committing.** Root `CLAUDE.md` §3 counts must be true
  for the tree of EACH commit.
- `LATEST.md` keeps **≤5 dated entries** and the agent adding one DELETES the
  oldest — a pre-commit hook enforces it.
- **Never run `dart format lib/`** or `prettier` on the whole tree. Format only
  the files you touched (`npx prettier --write <paths>`).
- The lint ratchet counts type-safety errors repo-wide. New code must be written
  cleaner than the file around it — a typed socket-data accessor and typed
  mock-call helpers are how 0b stayed at 906 instead of +84.
- **`Curve.calculateSignature` / `verifySig` MUTATE the buffers passed to them.**
  Always hand them copies. Same for `curve25519-js.verify` on the server.
- Editing tip, learned four times tonight: a `PUT` whose body silently drops a
  line that OPENS a construct (`style: TextButton.styleFrom(`, a `test(`
  callback, a `CREATE INDEX ... ON`) leaves the file unparseable. Re-read the
  FULL replaced range, not just the anchor.

---

## 10. What comes after the UI check and the review

Per spec §9, in order. `2026-08-17-HANDOFF-multidevice-execution.md` holds the
file:line landmines for these — read it before starting Phase 1.

- **Phase 1 (schema, invisible):** `devices` table, `(userId, deviceId)` bundles
  and OTPs, re-keyed 3-site identity epoch, `deviceId` in the JWT,
  `originDeviceId` + `sendToken`. ONE transaction, plain (non-CONCURRENT)
  indexes. Build the two-devices-one-account harness suite FIRST.
- **Phase 2 (the feature):** provisioning, DAK + signed device list, envelopes,
  self-sync, revocation, edit re-fan. **Requires its own spec-level review round
  BEFORE implementation** — that is a standing owner ruling.
- **Phase 3:** device-management UI. **Phase 4:** optional history-on-link.
- **At final merge only:** PATCH version bump (deliberately NOT bumped on this
  branch), backend deploys BEFORE web, staging dress rehearsal for schema
  phases, prod acceptance per spec §9.
