# HANDOFF — the remaining backlog, ready to execute

**Written:** 2026-08-02, after shipping `0.1.1`. Owner wants **all** of the items below done.

**Read first:** root `CLAUDE.md`, then `frontend/CLAUDE.md` or `backend/CLAUDE.md` for the tier you
touch. Then `2026-08-02-HANDOFF-post-incident-state.md` — it carries the July incident, the **three
deliberate asymmetries**, and the canary gate. Do not duplicate that content here; this file is the
work queue.

Every fact below was verified by a command at write time. **Re-verify anything volatile before
acting on it** — git state, versions, CI, PR lists (root `CLAUDE.md` §1).

## State at handoff

| | |
|---|---|
| Prod frontend | `0.1.1 / 8415b31` — carries the decrypt ledger |
| Prod backend | `0.0.140 / da120460` — carries the per-minute secret-note sweep |
| `master` | `ee171cd` (docs-only on top of `8415b31`; **prod runs current code**) |
| CI | green 4/4 on `ee171cd` |
| Tests | backend **578 / 47 suites**, Flutter **1134 + 10 skipped** |
| lint-ratchet | at its **817** floor — do not raise it |

Shipped earlier today: PR #111 (Android Phase 2) merged and live on web; `0.1.0`; the decrypt
ledger; the canary gate re-scoped to web-only; the keystore backup procedure.

**The ledger is live and gates decryption.** `0.1.1` is its first run against a populated real
store. The failure mode to watch: a message rendering *"no longer stored on this device"* that the
owner expects to be readable. That is a false positive — some probe answered "definitely absent"
about data that was still there. If it appears, take the `E2ePersistentDiag` dump **first** (it is
capped at 80 and rotates) and look for `LEDGER_RECORD_LOST`, which is durable for exactly this.

---

## 1. FCM service account — BLOCKER for any APK

**Verified still broken:** `grep -c '^FIREBASE_SERVICE_ACCOUNT=' ~/fireplace/.env` on the VM
returns **0**, and every backend boot logs
`WARN [PushNotificationsService] FIREBASE_SERVICE_ACCOUNT not set — FCM push disabled`.

`push-notifications.service.ts:32` reads `process.env.FIREBASE_SERVICE_ACCOUNT` and expects the
**service-account JSON as a string**; absent means FCM is silently disabled.

Meanwhile `frontend/android/app/google-services.json` **is tracked**, so the client half is fully
configured: an APK will register an FCM token via `POST /users/fcm-token`, the backend will store
it, and nothing will ever be delivered. **Android notifications are dead on arrival.** Web Push
(VAPID) is present and unaffected, which is exactly why nobody noticed.

- Owner generates the service-account JSON in the Firebase console; it is a **secret** and belongs
  only in `~/fireplace/.env` (gitignored, never committed, never pasted into a summary).
- Then `./deploy-backend.sh` on the VM.
- **Verify by delivery, not by silence.** The warning disappearing only proves the var parsed. Send
  a real push to a real device and confirm arrival.

Nothing else on the Android path is worth doing until this is true.

## 2. Dependabot #113–#119, plus a failing security run

Seven open PRs, verified `gh pr list` at write time:

| PR | Bump |
|---|---|
| #113 | `actions/setup-node` 6 → 7 |
| #114 | backend-minor-patch group |
| #115 | `typescript` 5.9.3 → **6.0.3** (major) |
| #116 | `dotenv` 16.6.1 → **17.4.2** (major) |
| #117 | `emoji_picker_flutter` 4.4.0 → 4.5.3 |
| #118 | `device_info_plus` 11.5.0 → **12.4.0** (major) |
| #119 | `flutter_local_notifications` 21.0.0 → ? |

A separate **Dependabot security run reported failure on backend `brace-expansion`** — this is the
only outstanding security debt on the board and it is not part of `ci.yml`.

Traps specific to this repo before you merge any of these:
- **Pins that are load-bearing and must NOT drift** (`frontend/CLAUDE.md` §5): `drift >=2.31 <2.32`,
  `sqlite3 >=2.9 <3.0`, `sqlcipher_flutter_libs 0.6.8`, `webcrypto 0.6.0`. sqlite3 3.x and drift
  ≥2.32 use native-assets build hooks that demand MSVC on **every local `flutter test`**.
- `firebase-admin` must stay on **13.x** (`backend/CLAUDE.md` §9): v14 drops the
  `admin.apps`/`admin.credential`/`admin.messaging()` namespace this service uses. The scoped
  `overrides.firebase-admin.uuid` pin must stay scoped.
- `emoji_picker_flutter` renders nothing under the widget-test binding — test emoji selection
  through the suggested row keys only (`frontend/CLAUDE.md` §6).
- `flutter_local_notifications` is the Android push renderer; a bump wants a real-device check, and
  right now push is dead anyway (item 1).
- Run the full tier suite for whichever tier a PR touches, and `node scripts/lint-ratchet.mjs`
  before pushing anything backend.

## 3. `delete for me` leaves the server row forever

`messages.service.ts:609-627` `hideMessageForUser` appends the caller to `hiddenByUserIds`
(comma-separated text, `message.entity.ts:72`) and saves. **Nothing ever checks whether every
participant is now in that set**, so a row both sides deleted survives until expiry — or forever if
it has no expiry.

The fix is to hard-delete once all participants have hidden it. Two things make this
destruction-adjacent, so treat it with the repo's usual bias:

- It cannot drop on the first delete — the other participant still needs to read it.
- Deleting the row must also delete self-hosted media **before** the row goes
  (`backend/CLAUDE.md` §8), the same as delete-for-everyone.
- Conversations are two-party today; write the check against the actual participant set rather than
  hardcoding 2, or a future group feature silently deletes early.

Reuse the existing parse helper (`MessagesService.parseHiddenIds`). Raw SQL must quote camelCase:
`"hiddenByUserIds"`.

## 4. The expiry sweep logs nothing on success

`EncryptionProvider.sweepDestroyablePlaintext` (`encryption_provider.dart:349`), driven from
`ConnectionProvider._runLocalPlaintextMaintenance` (`connection_provider.dart:331-338`) and the
per-minute timer at `:404`. It records `PLAINTEXT_PURGE_INCOMPLETE` on failure and **nothing at
all** on success.

That gap made the July diagnosis materially harder: there was no way to tell "the sweep ran and
destroyed these ids" from "the sweep never ran". Add a success-side diagnostic — ids destroyed,
count, and the fact it ran at all with zero destroyed.

Keep it cheap and keep it **metadata only** — ids and counts, never plaintext or key material.
`E2eDiagLog` (200-entry ring) is the right home for the routine case; reserve `E2ePersistentDiag`
(capped 80, durable, rotates) for the destructive/failure edge, or the useful evidence gets pushed
out by noise. That cap is why the incident's evidence was already gone.

## 5. Web at-rest sealing (B2) — the largest remaining privacy gap

On web, **all** Signal key material and decrypted history is plaintext base64 in localStorage
(`sig_*`, `e2e_*_decrypt*`). Android is sealed as of Phase 2; web is not.

This is the effort the canary actually gates. Read the "canary gate" section of
`2026-08-02-HANDOFF-post-incident-state.md` before starting — the short version:

- `ContentKeyCanary` measures `flutter_secure_storage` on **web** (IndexedDB + WebCrypto), the
  backend `signal_stores.dart:11-15` abandoned after keys vanished across tab closes.
- **`CONTENT_KEY_CANARY_LOST` in field diags ⇒ B2 MUST NOT proceed on that storage.**
- **Nobody can check that remotely.** `E2ePersistentDiag` has **no upload path** — grep
  `frontend/lib` and `backend/src` and confirm it yourself. The only way to read the canary is the
  owner opening Privacy & Safety in hacker mode and dumping it.
- Absence is weak evidence: the log caps at 80, rotates, and was observed *at cap* during the P0.

So step one is not code. It is: ask the owner for the dump, and interpret a clean one as "no
surviving evidence of loss", not "safe".

## 6. Housekeeping

- **Owner's working copy** `C:/Users/Lentach/Desktop/Fireplace` is **40 commits behind** and still
  checked out on `feature/android-encrypted-store`, which is merged and dead.
  `git checkout master && git pull`. Only after he is off it may the branch be deleted (local +
  remote) — deleting it while checked out orphans his copy.
- `fireplace-e2e-audit` worktree (`audit/e2e-safety`, `77876f9`) is long merged and removable.
- Work in `fireplace-wt-invitation` — it is the checkout on `master`, and `deploy-web.ps1` builds
  **the checkout it lives in**.

---

## Rules the owner holds you to

- **Never deploy or merge to master without explicit OK.** Both were given for the work already
  shipped; none of the items above carry standing permission.
- **Never tell him to uninstall or clear site data.** That destroys Signal keys and all history,
  irreversibly.
- The PWA is his **live workstation with ~25 real conversations**. Not a test surface.
- Lead with the verdict. No hedging, no flattery. Say "I don't know" rather than dressing an
  inference as proof, and distinguish **mechanism proven** from **cause proven**.
- Governing rule for anything destructive: **over-retention is recoverable, over-destruction is
  not.** Every destructive rule must fail closed.
- **Do not self-review load-bearing work.** Independent review found four real defects in the
  ledger — two CRITICAL data-loss paths — in code that already had 16 tests and four falsified
  guards. Spawn parallel reviewers (Standards / Spec / data-loss) and use the same model class.
- **Falsify before trusting green.** Disable the guard, confirm the test goes red, restore. A
  passing suite that cannot detect the regression proves nothing.

## Traps that cost real time

- **`sed` with `$` anchors silently no-ops on this CRLF repo.** Reports success, changes nothing.
  Use the edit tool or a Python rewrite.
- **`flutter test --platform chrome` hangs at load** (dart2js + libsignal). 15 minutes, no output.
- **CI runs only on `master` pushes and PRs** — a feature-branch push gets no run.
- **`post-deploy-smoke.mjs` defaults to the working copy's HEAD** — pass `--commit <sha>` otherwise.
- **Commit a version bump BEFORE building.** `deploy-web.ps1` stamps `GIT_COMMIT` from the checkout
  HEAD, so building dirty ships a bundle labelled with the previous commit.
- **The `LATEST.md` budget is enforced by `.githooks/pre-commit` on the STAGED blob** — ≤5 entries,
  ≤2600 words, ≤700 per entry. Measure with
  `git add` then `git show ":.cursor/session-summaries/LATEST.md" | wc -w`; measuring the working
  tree wastes commits.
- **Test-count verifiers gate CI.** Adding tests means updating root `CLAUDE.md` §3 in the same
  commit (`verify-claude-frontend-test-counts.mjs` / `-backend-`).
- **`prefs.getKeys()` and `getString` serve the plugin's in-memory cache**, which still lists keys
  whose commit was refused. Anything acting destructively on absence must read
  `_authoritativeSnapshot()`. This bit the ledger twice.
