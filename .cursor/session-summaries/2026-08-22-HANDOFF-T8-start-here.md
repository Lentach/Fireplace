# HANDOFF — start here for T8 (harness sweep), written 2026-08-22

**Read this once, then work from the books.** This file carries only what the books do not: the T8
execution brief and the operational knowledge behind it. Everything historical lives in the books, and
they are authoritative wherever this file disagrees with them.

> **EXPIRY, and it is binding.** Three previous `HANDOFF-*-start-here.md` files exist in this directory
> and all three rotted within a day, because they duplicated the books and then drifted. **The moment T8
> closes, delete this file or give it a SUPERSEDED banner, and do NOT write a replacement.** The books
> plus `.planning/multi-device/` are the permanent handoff; they are rewritten every session.

---

## 0. Where you are, and where everything lives

The program spans **two directories** and getting this wrong starts you on two-ticket-old facts.

| | Path | Notes |
|---|---|---|
| **Work here** | `C:/Users/Lentach/Desktop/fireplace-0a` | worktree, branch `feat/takeover-alarm-0a`, == `origin` at `d0fd6aa` |
| **Books (current)** | that worktree's `.cursor/session-summaries/LATEST.md` | 5 dated entries, newest = T7 + T7.5 |
| **What is OWED** | `C:/Users/Lentach/Desktop/Fireplace/.planning/multi-device/` | **gitignored**, main-checkout ONLY, never pushable |
| **Stale trap** | `C:/Users/Lentach/Desktop/Fireplace/.cursor/session-summaries/LATEST.md` | `master`'s copy, stops at 2026-08-20; it now opens with a warning banner |

Read order: this file → worktree `LATEST.md` → `2026-08-22-session-t7-edit-refan.md` → root `CLAUDE.md`
§3 (counts) and §7 (wire contracts) → `frontend/CLAUDE.md` §1 (harness) → frozen spec
`docs/design/multi-device.md` (§5.x for the surface you touch + **every** dated §12 amendment, which now
run (a)–(xxxiv)) → `docs/plans/2026-08-19-phase2-stage0-decision-record.md` §12 (T7 closure, and the
list of what T7 left owed) → the three planning files.

**State:** T1–T7 plus T7.5 are built, reviewed, wire-proven and app-proven. **Nothing is merged, nothing
is deployed.** PR #144 is a review surface only. One decision is pending with the owner: a docs-only
commit `0e1c2b2` sits **unpushed on `master`** in the main checkout (the banner above); leave it alone
unless the owner rules on it.

---

## 1. Owner rules — binding, each earned by an incident

1. **PROVE, then ASK, before writing code.** Diagnostics count as code. Work inside the approved T1–T8
   DAG is pre-authorized; anything outside a ticket needs an ask first.
2. **Ask before opening the browser tool — every time.** Grants are per-session and expire with the
   session. T7's grant is dead.
3. **Never merge, never deploy.** One branch, one merge at program end, owner's call. `gh run list
   --branch feat/takeover-alarm-0a` after pushing; never merge on red. (CI note: the `push` trigger is
   `branches: [master]` and the `pull_request` trigger has not fired since 2026-08-19, so pushes to this
   branch currently run NOTHING. Nothing is red. Fixing the workflow is outside a ticket → ask.)
4. **Never self-review.** Fresh `reviewer` subagent at every ticket close; **re-review after a
   non-trivial fold** (T5's second review found a P1 in already-reviewed code; T7's fold review found a
   vacuous test); **THREE independent reviewers at a phase gate**. Use defensive framing ("verify our
   protections hold") — adversarial wording gets content-filtered.
5. **Writers ≤2 concurrent, read-only scouts fine, Anthropic-only.** Expect writer subagents to
   **429-die**: T7's two died in 1.3 s with a 3.3-DAY retry-after, so the orchestrator carried T5, T6 and
   T7 solo. Scouts still work. Plan for solo execution.
6. **Never `dart format lib/`** or prettier globs — exact touched files only.
7. **Never give `flutter test` a file list.** Full suites only, including `test_e2e`. (45 files once
   timed out past 11 min; the whole suite runs in ~200 s.) A name filter (`--plain-name`) is allowed but
   beware: it skips the setup tests, so ceremony tests fail spuriously under it.
8. **Owner is non-native English — explain plainly.** And: **test delays in SECONDS via SQL timestamp
   updates; never wait out a 24 h/72 h window.** This is how T8's item 14d becomes possible at all.
9. **Session end:** dated `.cursor/session-summaries/YYYY-MM-DD-session-*.md` + `LATEST.md`, which caps
   at **5 dated entries** (a pre-commit hook rejects a 6th — roll the oldest into a "Still binding, from
   the rolled-off …" line).
10. **Maintain the planning files** at `C:/Users/Lentach/Desktop/Fireplace/.planning/multi-device/`.

---

## 2. Verification — reproduce, never trust these numbers

```bash
cd backend  && npm test                                    # 1002 tests / 61 suites
cd backend  && node ../scripts/lint-ratchet.mjs            # PASS at 889 real (floor 906 — do NOT lower it)
cd frontend && cmd /c flutter analyze --no-fatal-infos      # clean
cd frontend && cmd /c flutter test                          # 1520 / 10 skipped
cd frontend && E2E_BASE_URL=http://127.0.0.1:3000 cmd /c flutter test test_e2e   # 43 / 2 skipped
cd backend  && node ../scripts/verify-claude-backend-test-counts.mjs
cd frontend && node ../scripts/verify-claude-frontend-test-counts.mjs   # run BARE; --log parses instead of running
```

Update root `CLAUDE.md` §3 counts in the SAME commit tree as the change that moves them; both verifiers
must agree. Delete `frontend/test-output.txt` before committing. `npx jest` needs
`--config jest.config.json` (two configs exist). `cmd /c flutter …` on Windows (bare = os error 193).

**Pre-existing flakes — re-run the full suite once, do not chase:** `chat_input_bar_attachment_test.dart`
"video-then-caption keeps the media-first ordering contract", and `unread_badge_sync_test.dart` "falls
back to the window Badging API".

---

## 3. Environment, and the traps that cost real time

- Docker stack `fireplace-0a-*`; DB `chatdb` on **:5433**; backend **`127.0.0.1:3000`** — never
  `localhost` (stale wslrelay on `[::1]`). `docker ps` for squatters first; **ask before stopping a stack
  that is not yours.**
- **`docker compose restart backend` from the wrong cwd silently does nothing** (compose resolves a
  different project) and the wire suite then dies at `setUpAll` with `ThrottlerException`. Restart **from
  the repo root** and confirm a **fresh Nest boot line**, not just `/health` = 200. Cold boot measured
  **~3 min**; poll patiently.
- A restart **refunds in-memory throttles** (register 10/hr/IP, and every WS throttle). Restart before
  each wire run, wait ≥20 s after `/health` flips, and run the wire suite **alone**.
- SQL: `docker exec fireplace-0a-db-1 psql -U postgres -d chatdb -A -F'|' -c "…"`. Schema quirks: no
  `devices.id`/`isActive` (columns are `"userId","deviceId","isPrimary","revokedAt"`); `messages` uses
  `conversation_id`, `sender_id`, `"deliveryStatus"`, **`"createdAt"`** (not `created_at`);
  `refresh_tokens` is snake_case.
- Commit bodies: **backticks get shell-expanded and silently delete words.** Write the body to a file
  OUTSIDE the repo and use `git commit -F` (`.git` is a FILE in a worktree).
- The `edit` tool resolves a bare relative path against the **session cwd** (the main checkout). Use
  worktree-absolute paths in edit section headers.
- Live fixtures: **193** = `pg5802614#6248` / `Fireplace!2620` (device 1 live, device 2 REVOKED in T6);
  **297** = `t4peer0821#2955` / `FireplaceT4!2026`; **205** = `pr8963550rc489731` / `FireplaceFixed!7`.
  Conversation **92** holds the proof messages 649 (T4), 698 (T5), 775 (T6), **1012 (T7)**. Login DTO
  field is `identifier`.
- **Browser (ASK FIRST).** Spawn Chrome with `app.path` + `--user-data-dir=C:\Users\Lentach\.omp\run\daemons\9fe300f4492cdc1d\omp.browser.headed.profile`.
  The app is **portrait-only** — the `open` viewport arg did NOT take effect for T7; call
  `page.setViewport({width:480,height:900})` inside `run` or you get "Obróć urządzenie". **Two tab NAMES
  can resolve to ONE page** — create the second with `browser.newPage()` and select pages by
  `location.origin`. Click `flt-semantics-placeholder` after every reload; `aria-ref` clicks time out, so
  click **geometry** from a screenshot; screenshots are ground truth (the a11y tree lags). The composer
  needs a click to focus, then `keyboard.sendCharacter` per char (CDP `insertText` does NOT reach the
  framework); clear via framework Ctrl+A/Backspace, never by zeroing `input.value`. Serve the release
  build per origin (`python -m http.server`), rebuild after any `lib/` change, and evict with CDP
  `Network.setCacheDisabled`.

---

## 4. T8 — the ticket, item by item

Rows **14a–14g** of `.planning/multi-device/task_plan.md`. Every item is owed work from an earlier
ticket, so none of it is optional scope. **Settle any ambiguity as a dated §12 amendment BEFORE code**
(T6 and T7 each had an amendment that prevented a bug on paper).

### 14a — a SECOND enrolled account in the wire harness. Do this first; 14c depends on it.

The cliff: `provisioningComplete` is throttled **10 per 15 minutes keyed by USER**
(`WsThrottlerGuard.getTracker` returns `socket.data.user.id`), and every ceremony client does
`adoptAccountFrom(alice)` — so they all share ONE budget. The suite already spends exactly 10, so an 11th
ceremony gets **no answer at all** (the guard throws; see T7.5 — it now answers, but the budget is still
10). T7 worked around it with a memoized fixture, `secondDeviceOfAlice()` at
`frontend/test_e2e/full_stack_e2e_test.dart:1311` (state at `:1308`, teardown at `:1363`), shared by
falsifications 6 and 24.

What you need to know to build it:
- `registerFresh()` is called exactly **twice** today (`:179` alice, `:180` bob), so the 10/hr/IP
  registration budget has room for a third account. Add `carol` in the same `setUpAll`.
- **`bob` must stay UNENROLLED.** His refusal tests at `:1206` and `:1226` feed
  `enrollDeviceAuthority` deliberately-bad payloads and assert `success:false`; enrolling him for real
  would invalidate them. Use a NEW client.
- The DAK private key lives ONLY inside the single `DeviceAuthorityEngine` declared at `:61` and shared
  by the T2 and T3 groups (comment says so). The second account needs its **own** engine instance plus
  its own `enrollDeviceAuthority` (alice's enrollment happens at `:939`).
- Acceptance: the suite runs with room to spare for at least two more ceremonies, `43/2sk` becomes
  `N/2sk` with every pre-existing test unchanged in meaning, and the fixture is reusable by 14b/14c.

### 14b — a wire proof that a REAL self-envelope DECRYPTS (owed since T5)

Falsification 6 proves **routing only**: its self ciphertext is the synthetic
`3:selfsync-own-$runTag`, and the server treats ciphertext as opaque. Nothing yet shows a sender's second
device can actually **decrypt** its own self-sync copy. The obstacle is concrete: a linked harness device
adopts the account but never installs Signal state (this is exactly why falsification 24 had to use
synthetic ciphertext — its first version crashed with `Bad state: EncryptionService is not initialized`).
The shortcuts that make it possible are `uploadDeviceKeyBundle({deviceId, identityPublicKey,
registrationId})` at `e2e_test_client.dart:771` and `uploadDeviceOneTimePreKeys` at `:795`, plus
`fetchPreKeyBundle` taking an optional `deviceId`. Acceptance: device 2 decrypts a real self-sync
ciphertext to the expected plaintext, on the wire.

### 14c — `list_device_mismatch` on the wire (owed since T6, unit-proven only)

Needs **two linked non-primary devices in one run** → blocked on 14a. The refusal precedence in
`chat-device-revocation.service.ts` is `cannot_revoke_self` → `not_primary` → `unknown_device` →
`already_revoked` → `list_device_mismatch`; the last fires when the submitted canonical bytes do not show
the target as revoked, so signature and teardown can never disagree.

### 14d — falsification 12: per-device epoch after a §6.2 reset (owed since T6, unit-proven only)

Also owed: **the §6.2 reset teardown has never run against a live account.** The blocker was always the
72 h delay (1 h with a valid recovery phrase). **Owner rule 8 is the key: age it with a SQL timestamp
UPDATE, in seconds — never wait out the window.** Decide (and record) whether the live-account teardown
lands here or stays owed.

### 14e — widget test: the calm skew note borrows nothing from the identity surface (owed since T5's review)

Amendments (xvii)/(xx) govern the calm inline skew state; the test must show it does not reuse the
identity/takeover surface.

### 14f — a throttled `pinMessage` leaves optimistic pin state (owner routed here 2026-08-22)

Pre-existing and strictly improved by T7.5 (it used to be silence), but the same class as the edit
divergence T7 closed. Either map it in `THROTTLE_ANSWERS`
(`backend/src/chat/guards/ws-throttler.guard.ts`) with a client revert, or state plainly why the `error`
fallback suffices. Only handlers that ACTUALLY carry `@UseGuards(WsThrottlerGuard)` belong in that table
— an entry for an unthrottled handler is unreachable code (`uploadKeyBundle` was removed for exactly
that reason).

### 14g — falsification 24's envelope-stamp gap

The wire has **no read path** for `message_envelopes.deliveredAt`/`readAt`, so falsification 24 asserts
the message-ROW projection only, and its comment says so explicitly — **do not upgrade that comment into
a claim.** Stamp survival currently rests on a unit assertion plus SQL evidence recorded in the T7
summary (message 1012: `deliveredAt 04:41:15.544` and `createdAt 04:41:15.511` both predate the 04:42:25
edit). Either give the harness a way to observe those columns or formally accept the SQL step.
Related fact worth knowing: **`readAt` is never written by any code path** — `stampEnvelope` has one call
site and it always passes `'deliveredAt'`; `markConversationRead` drives the ROW to READ and leaves the
envelope alone.

---

## 5. How to close a ticket here

Sequential stages, **a full-suite-green commit per stage**; root `CLAUDE.md` §3 counts and §7 contracts
updated in the same tree. Then: fresh `reviewer` → fold → **re-review if the fold moved logic** →
app-prove (**ask for the browser first**) → push → books (decision record closure §, dated summary,
LATEST 5-cap rotation, all three planning files) → `gh run list`.

After T8: the **three-reviewer phase gate**, then the owner decides the single merge.

---

## 6. The five lessons that cost this program the most

1. **A test that cannot fail is not evidence.** Three shipped this program: T6's revoke test pre-armed
   the DAK engine (the live button was broken); T7's budget test bounced four times and tripped the very
   path that clears the counter; T7.5's two refusal tests set their flag unconditionally. **Any test
   whose whole value is being a guard gets the two-way proof: break the production line, watch that exact
   test fail, restore it, watch it pass.** Do it in the same session and say so in the commit.
2. **For every refusal you add, name the client code that drives it to a conclusion.** T7 gave the edit
   path a `deviceListStale` answer nothing listened for; the optimistic edit would have sat on that
   device forever. T7.5 generalized the same bug class: a throttled request answered with silence.
3. **Read an existing file before writing it.** A `write` overwrote the tracked
   `ws-throttler.guard.spec.ts` (a file whose last commit was titled "fix false-positive tests, close
   coverage gaps"); it was caught only because the jest FILE count stayed at 61 while tests rose by 6.
4. **Every line number in a handoff is a lie eventually.** T7's brief pointed at `:1005`/`:1014`; the
   real emit sites were `:1023`/`:1029`. Re-verify first-hand before trusting any cite in this file.
5. **The app-proof earns its keep.** T6's revoke button was broken with five green suites; T7's whole
   defect (an edit was not durable across a reload) is invisible to a unit test. Prove it in the app.
