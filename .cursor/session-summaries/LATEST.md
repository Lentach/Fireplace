# Latest session summary

**Date:** 2026-07-28 — **deleted and expired messages now actually die on the device.** Branch `audit/e2e-safety`. **Not deployed, not bumped** (0.0.132). Continues the 07-27 audit; owner: "all my messages are saved when they should be gone irreversible".

## What was done
1. **The record is the ONLY copy** — the server holds ciphertext whose ratchet key was consumed at first decrypt. So destroying EARLY is permanent loss, LATE is minutes of exposure. Everything is biased late.
2. **Delete purges inline** (server row already gone, no clock involved). **Expiry is two-phase:** hide on the local clock, destroy only against a confirmed `ServerClock` + 5-min grace for the per-minute cron. `socketReady` now carries **`serverTime`** (§7 wire contract); absent ⇒ client holds forever. The `Date` header CANNOT serve this — not CORS-safelisted, so the gate would have silently never fired on web.
3. **Records stamped `_cid/_savedAt/_createdAt/_expiresAt/_disappearAfter`** so purging is a prefix scan, not a walk of loaded rows — history pages ~50 while the store holds 2000. `_expiresAt` **re-stamped on `messageDelivered`**: read-mode messages get their deadline AFTER the record is written.
4. **Durable purge backlog**, written before anything is touched, cleared only on confirmed completion, cross-context locked ⇒ at-least-once across tab close. **Every removal gated on its commit result** — nothing reports success on residue. That is the guarantee the change rests on.
5. **NEW BUG FOUND: the 2000-entry LRU eviction was silently destroying history.** Eviction ≠ deletion — the server row stays alive, re-serves as `[encrypted]`, re-decrypt hits `DuplicateMessage` and bricks to a permanent `[Decryption failed]`. Fires constantly past 2000 messages; a likely source of old unexplained decrypt-failure reports. Those ids + retention's now go to a **retired set** rendering a deliberate "no longer stored on this device" state.
6. Also closed: **unfriend/block purged nothing at all**; decrypted **voice notes** survived; the old "clear cache" button touched text plaintext on **no** platform (no-op on web). Real **"delete all local history"** action added. **30-day retention** ages from a one-time epoch key, so existing history fades instead of being mass-destroyed on upgrade.
7. **`TZ: UTC` pinned in both compose files** — `expiresAt` is `timestamp WITHOUT time zone`, so a non-UTC backend ships deadlines shifted by the host offset and the client would destroy plaintext HOURS EARLY.

## Verification
- analyze **0 issues**; `flutter test` **956/5 skipped** (machine-verified); backend **541/47**; `test_e2e` **12 passed** vs a real backend, including a new test that a real `deleteMessage` destroys the plaintext and **leaves the Signal session alive**.
- **Live browser proof** (release build, real backend, real localStorage): seeded a record expired 1 h ago, a control expiring in 24 h, a backlog entry. After reload → expired **destroyed**, control **intact**, backlog target **destroyed**, backlog key **cleared**, all **26 Signal keys untouched**.
- Refused-commit tests install a prefs store whose `remove` returns false. Found doing it: `prefs.remove` drops its in-memory cache entry even when the backend refuses — the row reads as gone while bytes remain, which is why retry must come from the durable backlog.
- Wiring test **falsified both ways**.

## Notes for next session
- **B2 (at-rest encryption + key rotation) is NOT built and is the remaining half of the ask.** This delivers "gone from the app", NOT "gone from the disk": localStorage is LevelDB, `removeItem` leaves the value in the WAL until a compaction we don't control. Real unrecoverability needs records encrypted under a key **rotated and destroyed on purge**. Design agreed: `{kid, iv, ct}`, both keys live during rotation, old key destroyed only after a scan proves zero references.
- **NEVER describe the current state as "cannot be recovered"** — that repeats the exact defect this work removed.
- CI has never run on this branch; open the PR to run it. Rebase onto `origin/master` (`59d80ae`) — the `CLAUDE.md` count line WILL conflict.
- Local stack: another worktree holds :3000/:5433, so this ran on **:3100/:5533**; backend on the HOST with `TZ=UTC` (`nest start --watch` never bootstrapped in the bind mount). `flutter run -d web-server` bundles die on tab reconnect — **serve a release build statically**.
- ➡ Detail: `2026-07-28-session-local-plaintext-purge.md`; issue **#105** updated with the wider scope.

---
### Prior latest ↓

**Date:** 2026-07-27 — **full E2E safety audit + the chat-entry flicker/lag fix.** Branch `audit/e2e-safety` (separate worktree), cut from `d2f8aca`. **Not deployed, not bumped** — live stays 0.0.132 / `05fc423`.

## What was done
1. **Full E2E audit — SAFE WITH CAVEATS, no CRITICAL.** Both lock layers hold on all four session mutations, leaf-level (no deadlock), fail-closed Web Locks, monotonic plaintext, exact-ciphertext replay, server structurally cannot hold private keys, push content-free, `editMessage` blind and gated server-side, deletes really delete.
2. **Chat-entry flicker root-caused and MEASURED.** `onMessageHistory` painted server `[encrypted]` rows before hydrating, and `getDecryptedContent` reloaded prefs **per row** (`fd89e7e`). On web `reload()` enumerates every localStorage key + decodes each `flutter.` one against a 2000-cap cache: **65-77 ms per 50-row page, ~590 ms at 400 rows** (desktop i7; 4-6x worse on a phone) vs ~1.5 ms for one reload per pass. Fixed with `getDecryptedContentMany` + pre-paint hydration.
3. **Four of five MEDIUM findings closed.** Identity is now ONE atomic `identity_record_v1` (legacy pair still READ — the whole installed base has only that); partial loss throws and mints nothing, with a user-consented `IdentityDamagedBanner` escape hatch. Peer re-key surfaced (`PeerIdentityChangedBanner`, still TOFU, now cheaper than the old unconditional write). Prekey generation origin-locked. **The Web Lock is finally tested** — the old test opened `if (!kIsWeb) return;` and **reported as PASSED while asserting nothing**; now an honest skip + CI job `session-lock`.
4. **Verified in a REAL browser** (owner pushed back on deferring): real backend, real Chrome, real libsignal. Legacy-only install loads + migrates with identity unchanged; partial loss refuses; consented recovery republishes and a peer completes **X3DH against the regenerated identity**. The banner's action button was invisible (theme primary on red) — only a render caught it.
5. **The owner's actual bug was still there.** 300 fresh messages showed `[encrypted]` for 3-5 s: my first fix targeted the CACHED re-entry path, but a genuinely first entry has no plaintext to show. Now relabelled **"Decrypting…"** while a pass is in flight — confirmed in the browser, then real text.

## Verification
- analyze **0 issues**; `flutter test` **937 passed / 5 skipped**; count verifier OK; `flutter test test_e2e` **11 passed** vs a real backend.
- **Every fix falsified separately** (disable pre-paint hydration → red; ignore the batch → red at 30 reads vs 0; prekey lock ships a falsification case; the session-lock runner was proven to fail both ways before being trusted).

## Notes for next session
- **NOT deployed, NOT bumped** (0.0.132). **CI has never run on this branch** — the workflow triggers on push-to-`master` and `pull_request`, so opening the PR is what runs it.
- ⚠ **`origin/master` moved to `59d80ae` mid-session** ("post-merge count is 930"). This branch is behind and the `CLAUDE.md` count line WILL conflict — rebase and re-run the count verifier before merging.
- **Tried and REVERTED: progressive reveal.** The pass runs oldest-first (ratchet) while the list is `reverse: true` and shows newest, so mid-pass notifies resolve off-screen rows first.
- **M4 left undone on purpose:** plaintext is unencrypted at rest on **mobile** too; migrating ~2000 records into Keychain/Keystore is a data-loss hazard of exactly the class this branch removes.
- Remaining LOW: `/media/msgs/:filename` has no participant check (E2E blobs, no plaintext); deadlock and cross-peer parallelism still unpinned.
- ➡ Detail: `2026-07-27-session-e2e-audit-and-chat-entry-cost.md`; runbook **Steps 3D/3E/3F**; `frontend/CLAUDE.md` §5.

---
### Prior latest ↓

**Date:** 2026-07-27 — **RELEASED 0.0.132 / `05fc423`, both surfaces, smoke 5/5.** A workflow/infra session that ended up fixing **two disaster-recovery bugs in production code** (`backend/src/database/migration-runner.ts`), both surfaced by the new cross-tier CI job on its very first run. 18 commits, `05e0962..05fc423`.

## What was done
1. **MEASURED graphify instead of trusting it.** Its file→file import edges score **86.6%/90.7% on backend TS** but **0.5%/1.5% on frontend Dart** — every relative specifier collapses into one node attributed to an arbitrary file. It claimed `contact_network_view.dart`'s only importer was itself; truth is `contacts_screen.dart:13`. Kept and automated, but DEMOTED: never answer a Flutter dependency question from `GRAPH_REPORT.md`.
2. **`scripts/impact.mjs` (new)** — who depends on what I changed + which tests import it, parsed from source in ~0.6s. Handles Dart conditional imports, bare same-directory specifiers, `package:fireplace/…`, TS barrels, untracked files, deletions. **1639 specifiers, 0 unresolved.** 16 hermetic self-tests in CI.
3. **`.githooks/post-commit` rebuilds the graph** in the background, guarded to code-only commits (the graphify block claims "code files only" and does not filter).
4. **BUG: `0001_baseline.sql` could never run on a fresh database.** `pg_dump` brackets its dump with `\restrict`/`\unrestrict` psql meta-commands; node-postgres answers `syntax error at or near "\"`. **BUG 2, right behind it:** the baseline ends with `set_config('search_path','',false)`, so the runner's own unqualified tracking INSERT died with `relation "schema_migrations" does not exist`. Both hit only EMPTY databases — i.e. disaster recovery — because prod stamps the baseline instead of running it. Fixed in the runner (baseline is immutable), 3 regression tests.
5. **`e2e-wire` CI job added** — full-stack harness vs real Postgres+backend. It found both bugs on its first run. **11 wire tests green.**
6. **Repo is PRIVATE** (`gh repo view --json isPrivate` → true); docs said "public". All 226 dated summaries are committed now, and the false policy they carried is corrected.
7. Frontend test-count verifier added; `CLAUDE.md` §4–§6 moved to the runbook.

## Verification
- Backend **541/47 green**, Flutter **903 + 4 skipped green**, both counts now machine-verified in CI. `e2e-wire` **11 passed** against real Postgres.
- Migration fix falsified by reverting it (test goes red). Every parser fix checked against `grep`.
- **Release 0.0.132**: CI green on `05fc423` (all three jobs) BEFORE deploying. Backend healthy in 10s, `/health` `db:ok` — the runner booted clean on the live DB, confirming the fix misses the stamped-baseline path. **Smoke 5/5**, including `main.dart.js` literally containing `05fc423`.

## Notes for next session
- **`impact.mjs` is an inner-loop hint, NOT a coverage oracle** — static imports, 3 hops; blind to NestJS DI, §7 wire contracts, assets. Full tier suites are **required by project policy** before commits/PRs; nothing enforces that mechanically.
- **`e2e-wire` is now CI-failing** (`continue-on-error` removed after 5 consecutive greens; it caught two DR bugs on its first two runs). **But red is NOT a gate here** — branch protection is a paid feature, 403 on this private free-plan repo, so nothing blocks a push or merge and small fixes still go straight to `master`. Checking the run is a human/agent duty: `gh run list --branch master --limit 1`. If it flakes, restore `continue-on-error: true` deliberately and record it.
- **Owner must fully close + reopen the PWA** to pick up 0.0.132 (Settings footer → `0.0.132 / 05fc423`). **NEVER uninstall or clear site data** — that destroys the local E2E Signal keys.
- **Open work is now tracked as GitHub issues — read them, do not re-derive from here.**
  - **#100 (bug, do first): rotate `CONTACT_INBOX_KEY`.** A live 64-hex bearer key guarding `/contact/inbox` (every landing contact-form submission — third parties' names, emails, message text) is committed at `2026-07-22-session-inbox-extraction.md:63`. **PRE-EXISTING**: blob `bd5fe89` identical at `05e0962` and HEAD, from `2a70e38`, and in none of the 112 summaries published 2026-07-27. Rotation commands are in the issue.
  - **#101: install `gitleaks`.** Not installed, so `.githooks/pre-commit` falls back to a prefix-only regex that cannot catch high-entropy secrets — #100 is the proof it missed one. Never cite that hook as the reason a paste was safe.
  - **#102: finish Dependabot #95.** `207bc06` fixed only four of eight `brace-expansion` copies; root `1.1.16` + three nested `2.1.2` are still inside `<= 5.0.7`. Dev-only, not deploy-blocking. **Do not dismiss the alert.**
- ➡ Detail: **`2026-07-27-session-workflow-tooling.md`**; orientation for this directory: **`README.md`**.

---
### Prior latest ↓

**Date:** 2026-07-27 — three releases. `feat/nav-rework` → PR #98 → **0.0.130**; `feat/backlog-sweep` → PR #99 (`f4d3967`) → **0.0.131 on BOTH surfaces**, smoke 5/5. First backend production deploy of the run: `deploy-backend.sh` derives `APP_VERSION` from `frontend/pubspec.yaml`, so one bump versioned both. Query-only, **no schema migration**.

- **Ghost invites are LIVE and proven over a real socket** (`getSentRequests` + `sentRequestsList`, refreshed after send/accept/reject). Additive by design: `pendingRequestsCount` and `friendRequestsList` stay INBOUND-only. Needed the backend deploy; without it the client degrades to an empty list.
- **`EventLog.discard` exists because clear-assertions were VACUOUS without it** — `EventLog.next` scans the whole buffer with no cursor, and connecting already buffers an empty `sentRequestsList`, so a "must be empty" wait passed on the CONNECT-time empty. **Any E2E asserting a STATE TRANSITION must `discard` immediately before the action.**
- Chats `+` → glass honeycomb picker; glyph geometry moved onto `ConsoleGlyphGeometry`; `ContactNetworkView` stays provider-free (takes a default-empty `sentInvitees`).
- **PROCEDURE EXCEPTION, recorded honestly:** the 0.0.131 bump was NOT the last branch commit (`280a802` bump → `c0fcae1` test). Deploys key off the MERGE commit and both surfaces report `0.0.131 / f4d3967`, so nothing in prod is inconsistent. **Do not "fix" the history.** Next time hold the bump until verification is done.
- **RE-DEFERRED by the owner: the honeycomb `ListView` rewrite.** Build+layout is still O(N) (`SingleChildScrollView` + one full-height `Stack`; only visual subtrees are windowed). A throwaway probe measured 55.4/66.5/72.0/78.1/**135.5** ms at 20/50/100/200/400 — DIRECTIONAL ONLY, not comparable to the 2026-07-24 table. The cliff bites above ~200 contacts, which is not real yet. Do not record as done.
- ➡ `2026-07-27-session-backlog-sweep.md`, `2026-07-27-session-release-0.0.130.md`, `2026-07-27-session-nav-motion-and-glyphs.md`.

---
### Prior latest ↓

**Date:** 2026-07-25 — `feat/contact-network`: the whole visual pass. Contacts **Honeycomb Core** (header search, long-press → chat, People board with inbound port + add cell), **Chats list redesign** (hex avatars, unread as a lit row edge, live/normal/cold row weights), **Settings "local node console"**, and a rebuilt console glyph set + all three Settings sub-screens. Owner drove every step from renders and from his phone. Ephemeral branch deploy `85a04dc`, still 0.0.128 (branch deploys never bump semver), smoke 5/5.

- **`LocalNodeCore` is shared by Contacts and Settings on purpose** — same widget because it is the same entity (you). It stays a CIRCLE among hexes deliberately; that shape difference marks the local node.
- **Perf traps paid, keep them paid:** route fill REPAINTS, it no longer rebuilds (`AnimatedBuilder` wraps only the `CustomPaint`, not the `Stack` — it was ≈6k subtree builds per tap at N=100). Avatars arm lazily per row via `ValueNotifier` + `ValueListenableBuilder` around each avatar LEAF, never `setState` on the field. The high-water mark resets in `didUpdateWidget` compared **by `id`** (`UserModel` has no `==`).
- **Two things were built, shown, and DELETED at the owner's request — do NOT rebuild:** the "power-on scan" entrance, and the local node BUS (rail down the gutter). Both were rendered, tested and deployed before he rejected them on device.
- **Renders flatter what his hand rejects.** Render to pick a DIRECTION; deploy to get a VERDICT.
- `MainShell`'s `IndexedStack` wraps children in `Visibility(maintainAnimation: true)`, so an offstage tab's animations run at app boot — the honeycomb's entrance stagger has never actually been seen. Status quo, and FINE.
- **NEVER run `dart format lib/`** — it reformatted 70 untouched files. Format only files you edited.
- **Ask before opening the browser tool** — it is not headless and pops a window in front of the owner.
- ➡ Detail: `2026-07-25-session-console-glyphs.md` and `2026-07-25-session-settings-console.md`. The 2026-07-25 handoffs were DELETED on 2026-07-27 (they were banner-marked SUPERSEDED and one nearly got followed); `2026-07-26-HANDOFF-START-HERE.md` survives as historical context only — PR #98 shipped what it gated.

