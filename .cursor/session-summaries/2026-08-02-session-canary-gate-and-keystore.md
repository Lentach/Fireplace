# The canary gates web, not Android — and the keystore is single-copy

**Date:** 2026-08-02

## What was done

Owner asked whether the pre-APK canary gate should be honoured. Answer: no, and the gate as
written was a category error. Also levelled `feature/android-encrypted-store` with master and
verified the earlier merges had not broken anything.

- **`CONTENT_KEY_CANARY_LOST` does not and cannot gate the Android APK.**
  `ContentKeyCanary.checkAndArm()` opens with `if (!_isWeb) return;`
  (`content_key_canary.dart:96`) — a **no-op on native**. Its class doc (`:62-72`) says it
  measures `flutter_secure_storage` on **web**, i.e. IndexedDB + WebCrypto, the backend
  `signal_stores.dart:11-15` abandoned after keys vanished across tab closes. On Android the
  same plugin is Keystore-backed, which `signal_stores.dart:17-18` calls hardware-backed and
  reliable. **Same plugin API, different backend.** The prior handoff claimed "the SQLCipher
  key comes from the same place the canary measures" — it does not, and blocking Android on it
  meant waiting forever for a signal that cannot arrive. `2026-07-29-session-android-phase1.md`
  had already said "Native Android can seal WITHOUT the web canary gate".
- **The gate was re-scoped, not deleted.** It is still the correct gate for web B2 sealing,
  which has not started. Do not remove it because Android shipped without it.
- **There is no telemetry.** `E2ePersistentDiag` is a SharedPreferences list read by exactly one
  file — `privacy_safety_screen.dart` (display / copy / clear). Grepped `frontend/lib` and
  `backend/src`: **no upload path exists**. "Watch field diags" only ever meant the owner
  opening the hacker-mode panel. And absence is weak evidence: the log caps at 80 and rotates,
  and was observed *at cap* during the P0, so a late-July event may already be evicted.
- **"Not canary-gated" is not "safe".** Keystore keys still die (factory reset, new-device
  restore, auth-binding invalidation) and the plaintext cache is not re-derivable — the ratchet
  consumed the keys and media records hold the only `mediaKey`/`mediaIv`. Android's real
  protection is four mitigations: no auth binding, keys co-located with the Signal identity, the
  armed-gate (write → fresh read-back before use), and `CONTENT_KEY_LOST` → retired-id
  rendering. The gate is that those are present, not that a canary went quiet.
- **The release keystore is single-copy and that is the only irreversible risk on the board.**
  `frontend/android/keystore/fireplace-release.jks` (4430 bytes, 2026-07-29) exists on the dev
  PC and nowhere else. Protection verified: neither it nor `key.properties` is tracked, and
  `git check-ignore -v` names the rules (`frontend/android/.gitignore:12`, root
  `.gitignore:47`). The runbook's backup guidance was one aspirational bullet; it is now a
  fingerprint → copy → **read-back-and-compare** procedure.

## Key files

- `.cursor/session-summaries/2026-08-02-HANDOFF-post-incident-state.md` — new section "The
  canary gate — what it actually gates" replaces the wrong claim, with code citations.
- `docs/runbooks/android-release.md` — "Backing it up (the one unrecoverable artifact)" with the
  `Get-FileHash` loop; the rule that the `.jks` and plaintext `key.properties` must **not** share
  a backup object; instruction to rehearse the restore while a known-good original still exists.
  On the branch, the status header now names the two real distribution gates and refutes the
  canary inline. The runbook's mechanical gate table never mentioned the canary — that error was
  confined to the handoff.
- No code changed this session. Every commit is docs.

## Verification

- Branch merge: `flutter test` **1115 passed / 10 skipped / exit 0**, `flutter analyze` clean,
  `verify-claude-frontend-test-counts.mjs` OK. Backend not re-run — `git diff
  origin/master...HEAD -- backend/` is **empty**, byte-identical to master.
- **Reload-race suite falsified, not just run green:** with
  `PrefsContentKv.debugForceAuthoritative = false`, exactly three tests went red with the
  incident's symptoms (`Actual: <null>` twice, `Actual: Set:[]`). Probe reverted.
- Three deliberate asymmetries re-checked in source at `encryption_service.dart:1372`, `:1420`,
  `:1434`, `:1296`.
- CI green 4/4 on both refs at session end: master `26a088e`, branch `287902e`, 0 behind.
- Detail on the merge itself: `2026-08-02-session-android-branch-merge-verify.md` (branch only).

## Notes for next session

- **The `.jks` off-PC backup is the highest-value outstanding item and only the owner can do
  it.** Single copy since 2026-07-29. Lose it ⇒ no updates ever for existing installs, and the
  only user remedy is uninstall, which destroys their Signal keys.
- Owner's main copy is still behind — needs `git pull`.
- PR #111 open, mergeable, CI green, **not merged, needs explicit OK**.
- Process note: five docs commits to master this session, each putting the branch behind and
  costing a merge + CI cycle. Batch doc edits into one commit before merging.

## Addendum — PR #111 merged (same session)

Owner gave explicit OK. `feature/android-encrypted-store` merged to master as **`ac880f6`**
(merge commit, matching the repo's convention — #109/#110/#112 all used merge commits, not squash).
Master CI green **4/4**. Frontend only: 38 files, +4754/-144; `git diff origin/master...HEAD --
backend/` was empty pre-merge, so backend is untouched.

**Deliberately NOT bumped.** The branch carried no version bump and I left it that way: a bump
signals a release, and bumping while prod stays on `3a33bf9` would invite someone to "catch prod
up". Detection still works because CLAUDE.md §4 already says to trust `gitCommit`, never semver —
prod `3a33bf9` vs master `ac880f6`.

**The hazard this creates, recorded at the top of LATEST.md:** master's frontend now contains
Phase 2, which refactored the *web* read path too (`_authoritativeSnapshot()` moved out of
`encryption_service.dart` into the `ContentKv`/`PrefsContentKv` seam). A routine
`git pull ; .\deploy-web.ps1` would ship it to the owner's live PWA. Web behaviour is
**test-equivalent** — 1115 green plus the reload-race falsification — **not byte-identical
source**, and the PWA holds ~25 real conversations. Do not web-deploy without explicit OK.
`./deploy-backend.sh` is unaffected.

The branch ref was **kept**, not deleted: the owner's working copy is checked out on it, and
deleting the remote would orphan his checkout. Delete it after he moves that copy to master.

A Dependabot security-update run (npm `brace-expansion`, backend) reports failure on `ac880f6`.
It is a separate workflow from `ci.yml` and unrelated to this merge — CI itself is 4/4 green.
PRs #113-#119 remain untriaged.

## Addendum 2 — secret-note expiry tightened to per-minute

`secret-notes.service.ts:53`: `@Cron(EVERY_DAY_AT_3AM)` → `@Cron(EVERY_MINUTE)`, matching
`MessageCleanupService`. An unread expired note's ciphertext sat in `secret_notes` for up to ~24h
past its TTL; the API refuses to serve it, but the AES key travels in the note URL and that URL
is stored as ordinary plaintext message content, so DB access plus device access read a note the
UI already called self-destructed.

**The cadence is now pinned by a test**, because no behavioural assertion would catch a revert —
`deleteExpiredNotes` does the same thing either way, just less often. Fail-before proven:
restoring the daily cron gives `Expected "*/1 * * * *" / Received "0 03 * * *"`. Verified twice,
once before and once after the lint rewrite below, so the assertion cannot be silently reading
`undefined`.

**Lint trap worth remembering.** The obvious version of that test added **+3 real eslint errors**
and failed `lint-ratchet` (817 → 820): `Reflect.getMetadata` returns `any`, so the assignment,
the member access and the argument all tripped `no-unsafe-*`. Narrowing the return with `as
{ cronTime?: string } | undefined` cleared two. The last one was `unbound-method` on the bare
`SecretNotesService.prototype.deleteExpiredNotes` reference — fixed by reading the property
descriptor instead. Final state: **817, exactly at baseline.** Do not "fix" this by running
`lint-ratchet --update`; the floor is the point.

Backend suite **578 passed / 47 suites**, and root `CLAUDE.md` §3 was bumped 577 → 578 in the same
commit or `verify-claude-backend-test-counts.mjs` fails CI. `backend/CLAUDE.md` §11 said "daily at
03:00" and now says otherwise.

**This needs `./deploy-backend.sh` to take effect.** That deploy is independent of the undeployed
frontend — backend is untouched by the #111 merge.

## Addendum 3 — backend deployed, and an Android push blocker found

**Deployed** `./deploy-backend.sh` on the VM with owner OK. Backend is now
`0.0.140 / da120460`, `/health` `{"status":"ok","db":"ok"}`, boot log `[Migrations] schema up to
date` — no migrations ran.

**Verified safe BEFORE deploying, correcting an unverified claim I had made.** I had said "backend
is byte-identical to prod apart from this change" on the basis of `git diff origin/master...HEAD --
backend/`, which compares the branch to master, NOT master to the deployed commit. The right check
is against the deployed SHA:

```
git diff --stat 6fb36bf..origin/master -- backend/      # 3 files: service, spec, CLAUDE.md
git diff --name-only 6fb36bf..origin/master -- backend/migrations/   # empty
```

Zero migrations, one runtime file. Had a migration been in there, `deploy-backend.sh` would have
been a schema change needing a staging rehearsal, not a cron tweak. **Diff against the deployed
commit, never against a branch base.**

**Pulling master onto the VM does not ship the frontend.** `deploy-backend.sh` runs `git pull`, so
the VM checkout now contains Phase 2 source — but nginx serves `~/fireplace/frontend-build/`, which
is UNTRACKED (`??` in `git status`) and only written by `deploy-web.ps1`. Confirmed after the
deploy: `/version.json` still reports `3a33bf9`. This is why the frontend hazard survives a backend
deploy untouched.

**🔴 FCM is disabled in production.** Boot logs carry
`WARN [PushNotificationsService] FIREBASE_SERVICE_ACCOUNT not set — FCM disabled`, and
`grep -c '^FIREBASE_SERVICE_ACCOUNT=' ~/fireplace/.env` returns **0**. Meanwhile
`frontend/android/app/google-services.json` IS tracked, so the client half is configured: an APK
will happily register an FCM token via `POST /users/fcm-token`, the backend will store it, and
nothing will ever be delivered. **Android notifications are dead on arrival until that env var is
set on the VM.** Web Push VAPID is present, so the PWA is unaffected — which is exactly why this
has gone unnoticed. This belongs on the Android release checklist above the APK build itself.

## Addendum 4 — RELEASED 0.1.0, both surfaces live

Owner picked **0.1.0** over 0.0.141 and authorised the web deploy. Prod is now
`0.1.0 / a60610f` on the frontend and `0.0.140 / da120460` on the backend, both healthy,
**smoke 5/5** including the definitive gate: the served `main.dart.js` literally contains
`a60610f`.

Pre-deploy verification, in order: full Flutter suite **1115 passed / 10 skipped / exit 0** and
`analyze` clean on the exact tree; grepped `frontend/test`, `frontend/lib` and `scripts` for a
pinned `0.0.140` (none); **committed the bump before building**, because `deploy-web.ps1` stamps
`GIT_COMMIT` from the checkout HEAD and building dirty would have shipped a bundle labelled with
the previous commit; then waited for master CI green on `a60610f` before touching prod.

`versionCode` derives to **10000** (`0*1e6 + 1*1e4 + 0`), up from 137, still monotonic — checked
because a non-incrementing value is rejected by Play and silently breaks sideloaded upgrades. No
APK has ever been built or distributed, so nothing depends on the old numbering.

**Backend `/version` reads `0.0.140`, not `0.1.0`.** Its CODE is level with master; the label is
just the pubspec value at the moment `deploy-backend.sh` ran, which is the documented convention
for surfaces that deploy independently. Not drift, and not worth a container recreate to relabel.

**The frontend now runs the Phase 2 web read path in production** — `_authoritativeSnapshot()`
via the `ContentKv`/`PrefsContentKv` seam. Test-equivalent, not byte-identical source, and it has
never run against a populated store at real volume before today. If `[Decryption failed]`
reappears, take the `E2ePersistentDiag` dump BEFORE anything else; it caps at 80 and rotates, and
that is exactly what cost us the evidence window in July.

## Addendum 5 — the decrypt ledger (built, NOT deployed)

`e2e_<uid>_decrypted_ledger_v1` records ids whose plaintext was successfully persisted at least
once. That is the fact the app could never establish before: a record missing NOW might have been
lost, or might never have existed, and the two were indistinguishable — so it re-ran Signal
decrypt against a consumed ratchet key, hit DuplicateMessage, and burned the row into a permanent
`[Decryption failed]`. The July incident's mechanism, reachable from any storage loss.

`_decryptMessageAsync` consults the ledger before touching the ratchet. Definitely-absent record
⇒ `markRetired` + "no longer stored on this device", which a resend fixes.

**Three fail-open rules, each with a test. Do not simplify them:**

1. **Recorded only after a CONFIRMED commit of real plaintext.** Recording an id whose write
   failed would refuse the one decrypt that still would have worked — turning a recoverable
   write failure into permanent loss. Falsified: moving the call above the `ok` check goes red.
2. **Absence decided by the tri-state `recordExists`, never `getDecryptedContent() == null`.**
   That method returns null for an unbound user and for *any caught exception* as well as a real
   miss, so acting on it would let a transient storage error permanently retire a message whose
   bytes are on disk. `null` means "don't touch it". A review caught this after the first draft
   shipped exactly that bug.
3. **An edit drops the entry** via `invalidateDecryptionCache`, because an edit puts NEW
   ciphertext under the SAME id. Without it, every edited message would render "no longer
   stored" forever.

Cap 3000 tracks the 2000-record store rather than being an independent guess: anything evicted
past the record cap already goes through `markRetired`, so the ledger only has to cover ids whose
records still exist and might yet be lost. Eviction degrades to the OLD behaviour, never to a
false "unavailable". Writes are buffered and flushed at pass boundaries — a 50-row page costs one
write, not fifty, which matters because per-row storage work on web is what made the plaintext
reload 65-77 ms per page.

**Verification:** 13 new tests (9 storage semantics, 4 gate behaviour through the real
MessagingProvider path). Flutter **1128 + 10 skipped**, analyze clean, CI green 4/4 on `4ff1c52`.
Both the placeholder guard and the failed-commit ordering were falsified, and disabling the gate
turns two gate tests red.

**NOT DEPLOYED.** Prod frontend is `0.1.0 / a60610f`; master is `4ff1c52`. This feature can call
`markRetired`, which is permanent, and it has never run against a populated real store. The next
`deploy-web.ps1` is a release of this feature, not a routine publish — snapshot localStorage
first.
