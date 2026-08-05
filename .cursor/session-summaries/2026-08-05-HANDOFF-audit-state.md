# HANDOFF — where the audit stands, in plain language

**Written 2026-08-05.** For the owner and for any fresh agent who needs orientation rather than
detail. Nothing in here is a task; it is the map. The two task queues live at
`.planning/full-audit/REMAINING-WORK.md` (backend) and
`.planning/full-audit/frontend/REMAINING-WORK.md` (frontend) — both local-only, both gitignored.

---

## The one-paragraph version

Over 2026-08-04/05 the whole codebase was read end to end — backend and frontend, separately, by
two agents — looking for anything that could lose data, break encryption, or silently fail. That
produced 52 backend findings and 31 frontend findings. **Zero of them were CRITICAL.** The ones
worth fixing now were fixed: three pull requests, all merged to `master`, all green in CI. **None
of it is on the production server yet**, and that is deliberate — deploying is gated on a decision
only the owner can make. Everything left over is written down, ordered, and safe to pick up later.

---

## What actually got fixed and merged

| PR | Commit | What |
|---|---|---|
| #133 | `41e2f0b` | Backend — 16 findings. Blocking someone now works correctly in every direction; several paths that could lose data or half-apply a change were made atomic. |
| #134 | `195d894` | Frontend — 19 findings. Detail below. |
| #135 | `2db65d9` | Backend — multi-tab delivery. Opening a second tab used to silently stop the first tab receiving messages. |
| #130/#131/#132 | `953f98a` | Backend dependencies — undici, socket.io-parser, fast-uri. Three PRs that had been sitting open; merging them took GitHub's security alerts from **7 open (3 high, 4 moderate) to 0**. Backend-only; they ride the next backend deploy alongside migration `0011`. |

CI was 4/4 green on each merge, including the end-to-end wire harness. There are now **zero open
pull requests** and **zero open security alerts**.

**The three frontend fixes that mattered most:**

1. **Every network call in the app was unbounded.** All 21 could hang forever. They now all have
   deadlines. The worst case this closed: a stalled session-refresh left the app spinning on a
   loading screen until you force-quit it.
2. **A voice note could be destroyed silently.** If you left the screen at the exact moment a
   recording stopped, the file was deleted before it was ever sent, with no error.
3. **A future build flag would have deleted the multi-tab encryption lock.** Two files detected
   "am I on the web?" using a check that goes false under `--wasm`. Under wasm they would have
   quietly compiled to do-nothing stubs — no lock, no storage-persistence request, no warning —
   and the existing verification script would still have passed, because it tests the browser API
   rather than which file compiled.

Plus: a watchdog for connections that attach but never authenticate, timeouts on
accept/decline/send acknowledgements, a mute setting that could be dropped by the pin handlers,
several timer and memory leaks, and hardening against malformed timestamps from the server.

Frontend test suite went 1236 → **1247 passing / 10 skipped**, `flutter analyze` clean.
Backend went 589 → **670** across 49 suites.

---

## What is deliberately NOT done

- **Seven frontend findings on the decryption path are parked.** That code is where a mistake
  costs someone their messages permanently, so the rule is one small, owner-approved change at a
  time with a test per branch — never a batch. None are known to be hurting anyone today.
- **A handful of backend items are queued by tier**, the top one being a nightly media-cleanup
  window that is real but **not currently reachable in production** (verified against the live
  environment).
- **Two findings were closed as "won't fix" with reasons**, and one turned out to be already
  fixed — the audit had read an out-of-date version of the file.

---

## ⛔ The two deploy gates (nothing reaches users until these clear)

1. **Frontend.** The next deploy from `master` also ships the at-rest key sealing that was built
   earlier and held back. It needs a diagnostics dump proving the canary survived more than seven
   days, plus a fresh owner OK. Production currently runs a deliberate branch build (`c01317c`,
   0.1.8) that is *supposed* to differ from master. The next master deploy will be 0.1.9.
2. **Backend.** `master` now contains a database migration, so it needs a staging dress rehearsal
   first (root `CLAUDE.md` §6).

---

## Three things only the owner can decide

1. **Clear or hold the frontend deploy gate** — the canary dump, then the go/no-go.
2. **Android push is dead.** `FIREBASE_SERVICE_ACCOUNT` is missing from the production `.env`, so
   the server logs "FCM disabled" on every boot. An Android build would register for
   notifications the server can never send. Web push is unaffected, which is why this went
   unnoticed.
3. **Sign off on the revised prekey rate-limit** before the backend ships its crypto PR.

---

## The deploy, reviewed (2026-08-05)

Three reviewers (backend, frontend, crypto/data-loss) went over the exact prod-vs-master delta.
**All three: SHIP-WITH-CHECKS. No blocker.** What is undeployed:

- Backend `ded8e1a2` (0.1.2, built 08-03) → master: 7 commits, 57 files.
- Frontend `c01317c` (0.1.8) → master: 3 commits, 38 files — B2b sealing, sweep diagnostics,
  the 19 audit fixes.

**Four things to check before the backend deploy, in order:**

1. Fresh encrypted backup on the VM: `cd ~/fireplace && ./backup-db.sh`. Non-negotiable — the
   first boot of the new backend hard-deletes messages both participants had already hidden, and
   that is irreversible.
2. Zero duplicate conversation pairs, or migration `0011` aborts the boot (by design — it refuses
   to dedupe rather than risk destroying messages):
   `docker compose -f docker-compose.prod.yml exec db psql -U postgres -d chatdb -tAc "SELECT LEAST(user_one_id,user_two_id), GREATEST(user_one_id,user_two_id), count(*) FROM public.conversations GROUP BY 1,2 HAVING count(*)>1"`
   → must print **nothing**. Failure is safe: the transaction rolls back, the container never goes
   healthy, and the old backend keeps serving.
3. Every proxied nginx location still sets `X-Real-IP`. The throttler dropped its
   `X-Forwarded-For` fallback, so a location missing that header collapses all callers into one
   rate-limit bucket — i.e. a site-wide login lockout. Verified on 2026-08-04 across 11 locations;
   re-grep `/etc/nginx/sites-enabled/fireplace` because that config is not in this repo.
4. Staging dress rehearsal (mandatory — the delta touches a migration and an entity):
   `.\staging.ps1 up` → `restore <newest dump>` → `sql backend\migrations\0011_unique_conversation_user_pair.sql` → `harness` → `down`.

**Deploy the backend first.** It is wire-compatible with the 0.1.8 clients already in the field —
no socket event was renamed or repayloaded, and the four tightened DTOs all accept what 0.1.8
sends. Then verify `/health`, `/version`, and the log line applying `0011`.

**The frontend is the one-way door.** The B2b sealing rewrites every Signal key row in the
browser in place. The rewrite itself is safe (it verifies each seal by unsealing it in RAM before
overwriting, and re-checks the row has not changed). But **rolling the frontend back afterwards
does not undo it**: the old 0.1.8 bundle cannot parse the sealed rows and end-to-end encryption
goes down for every web user until you roll forward again. Nothing is destroyed — the old code
throws rather than regenerating an identity, verified by reading `c01317c`'s own
`encryption_service.dart` — but there is no going back. So: satisfy the canary gate first, bump
`frontend/pubspec.yaml` to `0.1.9` (it still reads 0.1.8, which is exactly what prod serves), and
treat the frontend deploy as a separate decision from the backend one.

### Canary reading — 2026-08-05 12:29, dev PWA (owner device)

**`CANARY_OK {ageDays: 7}` — the gate is `> 7`, so it is NOT met. It tips over on 2026-08-06.**
No `CONTENT_KEY_CANARY_LOST` and no `CONTENT_KEY_LOST` anywhere in the durable log, so nothing
here is a stop signal — the counter is simply one day short.

Everything else in that dump is healthy or already-known:
- `WEB_SEAL_OPEN {sealed: 202, legacy: 0, unreadable: 0, lostRows: 0, ms: 116}` — the B2a
  **content** sealing is fully drained on this device with zero unreadable and zero lost rows,
  in the same IndexedDB/WebCrypto store family B2b will use. This is the strongest field
  evidence we have that the sealed-storage machinery survives real use.
- `STORAGE_PERSIST {supported: true, granted: true}`, `SESSION_INVENTORY {count: 33}` — storage
  is persistent and every session survived.
- The five `LEDGER_RECORD_LOST` at 08-02 23:55 are the **already-diagnosed and fixed** expiry-stamp
  destruction bug (`2026-08-03-session-expiry-stamp-destruction-fix.md`;
  `encryption_service.dart:2073-2077` documents them by name). Not new, not recurring.
- One `badMac` + `SESSION_RESET {peerId: 60}` on 08-01, and `PEER_IDENTITY_CHANGED` for peers 90
  and 54 — handled by the existing policy.

**So: re-dump on 2026-08-06.** If it reads `ageDays: 8` with still no loss, the gate is met. The
backend deploy does not depend on this and can go first.

**Watch for the first few hours:** in the app's own diagnostics (Settings → Privacy & Safety →
E2E Diagnostic Log → Copy) `SIG_SEAL_OPEN` with `legacy` marching to 0 and one
`SIG_SEAL_DRAIN_DONE`; escalate on `SIG_KEY_UNAVAILABLE`, `SIG_ROWS_UNREADABLE` or
`CONTENT_KEY_LOST`. In the VM logs, `applied 0011`, no `friendRequestFailed` storm, and no
socket-addressing errors from the multi-tab change.

One review finding was fixed rather than accepted: media *downloads* had been bounded at 20 s
while uploads got 60 s, so a large received image on a slow link could newly fail. Both now share
a 60 s media budget.

---

## Where to look next

| You want | Read |
|---|---|
| The frontend task queue | `.planning/full-audit/frontend/REMAINING-WORK.md` |
| The backend task queue | `.planning/full-audit/REMAINING-WORK.md` |
| Full frontend finding text + traps | `.planning/full-audit/frontend/findings.md`, `HANDOFF-NEXT-SESSION.md` |
| Full backend finding text | `.planning/full-audit/backend/FINDINGS.md` |
| The narrative of each session | `2026-08-04-session.md` (the audit), `2026-08-04-session-frontend-audit-fixes.md`, `2026-08-05-session.md` |

**Why the queues are not in git:** `.planning/` is gitignored on purpose. Those files are a
concentrated, indexed list of unfixed weaknesses in a live end-to-end-encrypted messenger. They
stay on the dev machine. This file is the committed, safe-to-share summary of them.
