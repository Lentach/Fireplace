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
