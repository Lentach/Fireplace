# 2026-09-05 — Passcode re-lock made real, an Android lockout fixed, `feat/video-messages` merged to master

**Date:** 2026-09-05

## What was done

Two branches touched, deliberately kept separate:

- **`feat/passcode-lock`** → branch tip (resolve with `git rev-parse feat/passcode-lock`; a literal SHA here would be
  wrong the moment the next doc commit lands). The feature work. NOT merged, NOT deployed, left checked out in the
  main worktree so the owner can test it.
- **`origin/master`** → `95dd243`, a merge commit bringing in `feat/video-messages`. CI green. NOT deployed.

### 1. A mid-session re-lock now REVOKES, it does not just cover the screen

Before this, locking dropped the KEK and closed the E2E gate for the NEXT boot, while the already-open stores kept
their content keys — and the content store kept the **plaintext of every sealed row it had read** — in RAM. Only a
cold boot was arithmetic. `PasscodeProvider._lock()` now does three things in order:

1. **Drops the KEK, zeroing the bytes first.** `AesGcmContentSealer` memoizes its imported `AesGcmSecretKey` in an
   `Expando` keyed on that exact byte list, so a surviving reference keeps a *usable* key alive in the heap even
   after the field is nulled.
2. **Tears the live stack down** through the new `E2eLockRevoker`: `SealedWebSignalKv.revoke()` and
   `SealedWebContentKv.revoke()` forget their keys and (content store) `_view` + `_unsealMemo`,
   `EncryptionService.revokeForPasscodeLock` drops the in-RAM Signal identity and both store memos, and
   `EncryptionProvider.revokeForPasscodeLock` drops `_decryptedContentCache`.
3. **Replaces the process** on web. The message list, conversation previews and rendered text live OUTSIDE the E2E
   stack — only a reload takes the whole heap. It is the same replacement `page_lifecycle_web.dart` already performs
   on every thaw of a frozen PWA, so it lands on this app's best-tested boot, which then demands the code (a wrapped
   device boots locked whatever the auto-lock window says).

**What keeps revocation from becoming the identity-loss bug in a new costume:** a revoked store is never destructive
and never answers "absent". Sealed sig reads throw `SigStoreUnreadable('revoked')` (a null identity read is what
mints a new identity); sealed content rows are served AS THEIR RAW ENVELOPE so `recordExists` still answers TRUE and
nothing is retired as lost; `readAll` stays presence-preserving so `_hasPriorInstallResidue` still sees the rows;
sealed WRITES are refused rather than sealed under a dropped key. `isE2EReady` is cleared BEFORE the teardown, so no
decrypt can run against a revoked store — that is what stops a permanent `[Decryption failed]` being persisted over
a readable row. Revoke and restore are serialized, so an immediate unlock cannot overtake the teardown.

**Android keeps the UI-barrier shape on purpose:** with wrapping off the same keys are readable again the instant the
store re-opens, so a teardown would cost an E2E re-init and buy nothing. `_lock()` checks
`_wrapKeys && await _vault.isWrappingOn()` first, so a passcode whose wrap-enable failed also does not revoke.

### 2. The Android run found a LOCKOUT that destroys data, and a BYPASS

With a **250 ms** per-attempt Keystore budget, EVERY cold boot of the debug build on a loaded Pixel emulator lost all
three attempts. A device with a perfectly intact credential reported `PASSCODE_CREDENTIAL_DAMAGED`, refused the
correct 4-digit code with *"Nie udało się zabezpieczyć kodu na tym urządzeniu"*, and offered only the destructive
erase. A first Keystore read after process start unwraps a key and is simply not a 250 ms operation.

The boot read now has **three** verdicts, not two:

- **(a) nothing readable, not even the flag** ⇒ no passcode (`PASSCODE_STORE_UNREADABLE`). Unchanged.
- **(b) flag TRUE and the read ANSWERED that the secret is gone** ⇒ `credentialDamaged`. Terminal, erase is the way
  out. Unchanged.
- **(c) flag TRUE and the read never ANSWERED** ⇒ `credentialUnavailable`. NEW. Locked but retryable: the provider
  re-reads with backoff (400 ms → 8 s, capped, cancelled in `dispose`) until storage answers, and
  `credentialResolved` drives `passcodeCredentialLoading` with the keypad disabled instead of an error.

Per-attempt budget **250 ms → 1.5 s**; `_readSecrets` now reports `readFailed` distinctly from "absent".

**The same pass closed a BYPASS in the other direction.** The enabled flag used to come out of the TIMED `load()`, so
a load that overran the ceiling was indistinguishable from "no passcode was ever set" — and that branch UNLOCKS the
app. A slow Keystore was a way in. The flag is now read separately and FIRST (`PasscodeStore.readEnabledFlag`, prefs
only), so a flagged device can only ever answer LOCKED. Budgets stay ordered and a test asserts it:
`secretReadBudget` 4.8 s < `kPasscodeStoreReadTimeout` 6 s (was 1.05 s < 2.5 s).

### 3. `feat/video-messages` merged into master (`95dd243`)

Six files conflicted. Resolutions:

- **`frontend/pubspec.yaml` version → kept master's `0.2.2`.** ⚠️ **Merging an older release branch must NEVER roll
  the pubspec back**: the user-visible version is semver from this file only (§5), so a rollback would advertise a
  version older than what is already live. The branch's `light_compressor_v2` pin was carried over — the native
  transcode needs it.
- **`chat_input_bar.sendPickedVideo` → took the BRANCH entirely.** Master still held the pre-branch version, which
  probed duration separately, capped at a hardcoded 60 s, and called `videoTooLong`/`videoTooLarge` with **no
  arguments**. The merged ARB has those keys PARAMETERISED (the branch added the placeholders), so master's calls no
  longer typecheck; and the branch's version is the one that shipped from the branch and was device-verified.
- **Both ARBs → union.** Each side had appended DIFFERENT keys to the tail, so keeping either side alone left a
  dangling reference.
- **`CLAUDE.md` / `LATEST.md` → master's**, plus a merge entry; the oldest 09-02 entry rotated out per the
  five-entry cap (the pre-commit hook caught that). The branch's dated summaries merged cleanly as separate files.

## Key files

- `frontend/lib/services/e2e_lock_revoker.dart` — NEW. Process-wide revoke/restore seam, serialized.
- `frontend/lib/utils/app_relaunch{,_stub,_web}.dart` — NEW. Web-only in-place process restart.
- `frontend/lib/providers/passcode_provider.dart` — `_lock()` three-step, `readEnabledFlag` first, the
  `credentialUnavailable` retry loop, `credentialResolved`, `dispose` cancels the timer.
- `frontend/lib/services/passcode_store.dart` — third verdict, `readFailed`, budgets 250 ms → 1.5 s / 1.05 s → 4.8 s.
- `frontend/lib/services/encryption/sealed_web_signal_kv.dart`, `sealed_web_content_kv.dart` — `revoke()`, nullable
  active key/kid, revoked reads throw / serve raw envelopes, revoked writes refused.
- `frontend/lib/services/encryption/content_key_wrap.dart` — `lock()` zeroes the KEK.
- `frontend/lib/services/encryption/content_kv_opener_{stub,io}.dart`, `signal_stores.dart` — memo teardown.
- `frontend/lib/services/encryption_service.dart` — `revokeForPasscodeLock`; `SecureIdentityKeyStore.forgetInMemoryIdentity`.
- `frontend/lib/providers/encryption_provider.dart` — `revokeForPasscodeLock` / `restoreAfterPasscodeUnlock`,
  registration on the seam, deregistration in `dispose`.
- `frontend/lib/screens/passcode_unlock_screen.dart` + both ARBs — `passcodeCredentialLoading`, keypad gated on
  `credentialResolved`.
- Tests: `test/services/e2e_lock_revoker_test.dart` (NEW), plus revocation and unavailable-credential cases in the
  two sealed-store suites, `passcode_provider_test.dart` and `passcode_store_test.dart`.

## Verification

- **Re-lock, at heap level not visually:** `window.__relockProbe = 'alive'` planted while unlocked came back
  **undefined** after the padlock — the document really was replaced. Fresh boot showed the lock screen,
  `fp_passcode_kek_meta_v1` still present, 26 sealed `sig_e2e_*` rows untouched, durable log **0**
  `IDENTITY_MINTED` / **0** `SIG_STORE_FALLBACK`, and the right code brought the app back up.
- **Android, end to end** (shots `.planning/passcode-lock/shots/relock-android-*.png`): fresh install → login →
  identity mint → 4-digit accepted (`_modeAllowed` allows it with wrapping off); prefs held only `passcode_enabled`
  + `passcode_mode`, `FlutterSecureStorage.xml` held `fp_passcode_{salt,verifier,iterations}_v1`, **no**
  `fp_passcode_kek_meta_v1` and **zero** `fpwk1:` envelopes; cold boot locks and the code opens it with no
  `PASSCODE_SECRET_UNREADABLE`; mid-session lock/unlock leaves E2E up; erase took prefs 5 → 1, secure storage
  **33 → 0**, `files/fp_content.db{,-wal,-shm}` **3 → 0**, back at the login screen.
- **Branch:** `flutter analyze --no-fatal-infos lib test` clean; `flutter test` **1499 / 14 skipped**; count line and
  `verify-claude-frontend-test-counts.mjs` OK.
- **Merged master:** analyze clean; `flutter test` **1741 / 10 skipped**; count line 1721 → 1741; verifier OK;
  **CI run 33924078694 green** (including `e2e-wire` and the isolated probes).
- **Production, before the deploy (curl + SHA resolution):** `version.json` → `0.2.2 / b73b7cd`.
  `git log -1 b73b7cd` = *"feat(multi-device): (lxxii) the keyless banner carries the reset door — 0.2.2"*, dated
  2026-09-03; `git branch -a --contains b73b7cd` → `master` only; ancestor of the PRE-merge master `90b4273` =
  **yes**; ancestor of `origin/feat/passcode-lock` = **no**. That last probe is what earns "the passcode lock is not
  on production" — it is not in the live commit's history, and it is not in `5d669ce` either.
- **Production, after the deploy:** `version.json` → **`0.2.3 / 5d669ce`**; smoke **5/5** including the stale-build
  gate; the served bundle contains `"tylko MP4"` and `"maks. 3 minuty"`. Backend deliberately untouched at
  `0.2.0 / 5ffef19b`.

## Notes for next session

### ✅ DEPLOYED as 0.2.3 — this is what put video messages in front of users

The owner asked for it at the end of the session ("deploy video messages i need to test it"). Frontend-only release:
bump `0.2.2 → 0.2.3` (`5d669ce`, pushed to master, CI run 33925447274 green), then `deploy-web.ps1`.

- **Verified:** `/version.json` → `0.2.3 / 5d669ce`; smoke **5/5** including the stale-build gate (the served
  `main.dart.js` literally contains `5d669ce`), `/health` ok, headless boot ok.
- **The video code is provably in the live bundle:** the served JS contains `"tylko MP4"` (the MP4-only extension
  gate) and `"maks. 3 minuty"` (the parameterised duration cap). **Grep a localized STRING, never a Dart
  identifier** — dart2js renames identifiers, so my first pass on `videoUnsupportedFormat`/`videoTooLong` returned 0
  on a perfectly good build and briefly looked like a failed deploy.
- **⚠️ THE SMOKE GATE CANNOT CATCH A STALE-BUT-CONSISTENT BUILD**, which is why that string check matters. The gate
  compares the SERVED commit against the commit it just built, so building from a tree at the wrong commit — e.g.
  `fireplace-0a`, which still holds local `master` at the pre-merge `90b4273` — would publish `0.2.3` containing no
  video work at all and still pass 5/5. The build worktree was therefore checked directly:
  `git rev-parse HEAD` = `95dd243` before the bump, `5d669ce` after.
- ⚠️ **`"Kompresowanie wideo…"` is ABSENT from the web bundle, correctly.**
  `utils/video_transcode_stub.dart` defines `bool get isVideoTranscodeSupported => false;` (a getter, NOT a
  `const`), and `chat_input_bar.dart:476` returns early on `override == null && !isVideoTranscodeSupported`, so the
  transcode branch is unreachable on web and its string does not survive into the bundle. The absence is the
  OBSERVED fact; I first wrote that dart2js "constant-folds a `const false`", which the source does not say — do not
  assert a compiler mechanism you have not read. Encoding was ruled out before trusting the zero: the fetched body
  starts `(functio`, has no gzip magic, and other Polish strings in the SAME file hit. **On the PWA an oversize
  (>20 MB) pick is still REFUSED, not transcoded** — native transcode is Android-only and **no APK was built by this
  deploy**. If the owner tests oversize video on the PWA and sees a refusal, that is the designed behaviour.
- No `deploy-backend.sh` run (the branch was frontend-only), so the two version surfaces disagree by design:
  frontend `0.2.3`, backend `0.2.0 / 5ffef19b`.
- Run from a throwaway detached worktree because the main checkout is on `feat/passcode-lock` for owner testing;
  `deploy-web.config.ps1` (gitignored) had to be copied in and was removed afterwards.

**Two traps re-hit, both cheap to lose an hour to:**

1. The `pubspec.yaml` version line is **CRLF**, so `sed -i 's/^version: 0\.2\.2$/…/'` matched NOTHING and reported
   success. The 09-02 deploy hit the same thing ("two perl misfires… CRLF pubspec line"). Bump it with an editor, or
   re-read the file afterwards.
2. **`deploy-web.ps1` exited 1 with `PUBLISHED_OK` already in the log.** The publish had SUCCEEDED; the failure was
   only the stale-build gate refusing to run because `scripts/smoke/node_modules` does not exist in a fresh
   worktree. Read the log — the exit code alone would have said "deploy failed" and invited a pointless retry. The
   gate was then run from the main checkout with `node post-deploy-smoke.mjs --commit 5d669ce`.

### ⚠️ Another stale fact killed: the backend is NOT at `0.0.1/unknown`

Docs had carried *"backend `/version` answers `{"version":"0.0.1","gitCommit":"unknown"}`, which makes
`deploy-web.ps1` exit 1 on its smoke gate"* since 09-01. Verified twice this session (deploy script output and the
smoke run): `/version` → **`0.2.0 / 5ffef19b`**. It was re-stamped by the 09-02 `deploy-backend.sh` run and the note
was never updated. The exit-1 in this deploy had a completely different cause (see trap 2 above).

### ⚠️ Deploying a merge whose pubspec was never bumped

`95dd243` kept pubspec at **0.2.2 — the version already live**. §5 requires a PATCH bump on production releases, and
the smoke gate compares the version only, so deploying the merge as-is would have **passed its gate while the footer
still read 0.2.2** — exactly the §4 "trust `gitCommit`, never semver alone" trap. Hence `5d669ce`.

### ⚠️ `origin/master` is `95dd243`; the LOCAL `master` ref is deliberately still `90b4273`

The local ref is **shared across worktrees** and `fireplace-0a` has `master` checked out. Moving it would yank that
worktree's HEAD out from under its files and show a giant phantom diff. So the merge was made in a throwaway
detached worktree and pushed with `git push origin HEAD:refs/heads/master`. `fireplace-0a` simply reads "behind
origin/master" — fast-forward it whenever convenient. **Do not "fix" the local ref while another worktree holds it.**

### ⚠️ What production's video support actually is — and a claim I got wrong TWICE

I told the owner that "video messages silently regressed out of production on 09-03". **Both halves were wrong.**

**(a) Prod is not missing video.** Verified by grepping the live commit's tree: `b73b7cd` **does** contain video
messages (`sendVideo` in 4 files, `videoTooLong` in 6, `MessageType.video` in 9). What it does NOT contain is the
branch's newer work — `sendPickedVideo`, `kSendableVideoExtensions`, `probeVideoPreview`, `transcodeVideoToFit` all
return zero files at that commit, and `light_compressor_v2` is absent from its pubspec. So: **production runs the
OLDER video shape; the branch's improvements (MP4-only extension gate, native transcode of oversize picks, the
single `probeVideoPreview` pass feeding geometry + ThumbHash, immediate send instead of staging) were never on
master's line until this merge, and are therefore not live.** The next deploy of master introduces them.

**(b) It was neither silent nor 09-03 — it was recorded, escalated, and 09-02.** The commit that shipped 0.2.0
(`b27f242`, docs in `2026-09-02-session-perfection-pass-lxvii-lxviii.md`) states it plainly: *"Pre-deploy surprises:
prod web was `feat/video-messages` **0.1.24** (8 frontend-only commits, deployed as a branch test)"*, and lists
under **Open for the owner**: *"video messages are OFF prod until `feat/video-messages` merges to master (it is 8
frontend commits behind nothing — master has 182 it lacks; merge master in, then PR)"*. Its LATEST entry carries the
same note. So the branch build WAS live at 0.1.24, shipping 0.2.0 from master on **09-02** replaced it deliberately,
and the consequence was written down and handed to the owner rather than lost. **The 09-04 merge closes that open
item.**

⚠️ One deviation worth noting: the recorded plan was *"merge master IN, then PR"* — i.e. bring master into the
branch and open a PR. The owner instead instructed master ← branch directly on 09-04 ("merge video-messages into
master"). Same resulting tree, opposite merge direction, no PR. Not a problem, but if anyone later wonders why there
is no PR for it, that is why.

What is STILL not evidence: exactly what the VM served on any given past date. Prod history is not observable after
the fact — the 09-02 record is a contemporaneous observation by the session that deployed, which is as good as it
gets, but the 0.1.22-on-09-01 step rests on branch testimony alone.

### ⚠️ The `LATEST.md` deploy banner had been stale since the 09-02 `0.2.0` deploy, and misled this session

It claimed prod was running `feat/video-messages` at 0.1.22/0.1.24. I repeated that to the owner several times before
checking. **Always `curl https://fireplace.ignorelist.com/version.json` and resolve the returned SHA with
`git log -1` + `git branch -a --contains` before believing any banner — including the corrected one.** Note also that
`git merge-base --is-ancestor <sha> master` is ambiguous about which ref `master` resolved to; name the SHA
explicitly (`90b4273` vs `95dd243`) or the answer proves nothing.

### Still open

- **Owner is testing the passcode lock.** His calls: the reload-on-lock UX, auto-lock at 0 s on desktop web (a tab
  switch counts as backgrounding, so every return costs a reload), and 6-digit vs alphanumeric — 10⁶ candidates
  through 600k PBKDF2 is a speed bump, not a wall, against someone who copies the browser storage.
- **Rebasing `feat/passcode-lock` (10 commits) onto `95dd243`.** Still stacked on the old `feat/video-messages` head.
  Its commits touch `signal_stores.dart`, both sealed web stores, `encryption_service.dart` and
  `encryption_provider.dart` — multi-device territory, so expect real conflicts.
- The non-extractable `CryptoKey` hardening for the unlocked session (Element Web's pickle-key trick) is designed but
  unbuilt: it stops an XSS foothold EXFILTRATING the unwrapped keys, not using them.
- Android acceptance in `frontend/integration_test/` for the real Keystore verifier path, if the owner wants it.
- Known flake, unrelated: `encryption_service_decrypt_ledger_test.dart: a failed plaintext commit is NEVER recorded`
  failed once under full-suite load and passes in isolation.
- ⚠️ Doc conflict noticed, not resolved: root `CLAUDE.md:20` says the repo is **PRIVATE** (verified 07-27) while
  `LATEST.md`'s binding note says **PUBLIC since 08-18**. The PII rule is the same either way, but one of them is
  wrong and should be settled with `gh repo view --json isPrivate`.

### Tooling trap

`git worktree add` with a `/c/tmp/...` style path put the tree at literal `C:/c/tmp/...` and the shell could not
`cd` into it. Use a Windows-style sibling path (`../fireplace-merge`).
