# Traps — permanent, one line each

Standing warnings that used to live in the `LATEST.md` banner and in rotated-out entries. **One line per trap; link the dated summary that earned it.** `grep` this file for the area you are about to touch. New traps: append here in the same commit as the session summary (the `## Traps` section of the summary lists them too). Never delete a line because it is old — delete it only when the code that made it true is gone.

## Composer / attachments / media
- **Nothing ships in the composer or attachment picker without a green repro AND the owner's explicit OK; never `git revert 0cbf17b`** — owner: "we made huge regress on composer and now all old bugs are back" (`2026-08-19-session-composer-regression.md`).
- **Dependabot #174 (`file_picker` 11.0.3) is deliberately OPEN** — `web_file_input.dart` exists because of 11.0.2's DOM behaviour; no host test sees that path (`2026-09-08-session-dependabot-sweep-and-pc-health.md`).
- A video RETRY must carry the full payload (poster/dimensions), not url/key/iv/duration only — a once-failed clip reached the peer as a 220 px blank square (`2026-09-05-session-video-nits.md`).
- A route pushed over the chat must RELEASE the inline video slot (`2026-09-05-session-video-nits.md`).
- The WebKit `videoWidth == 0` probe fix is **NOT iOS-verified** — owner owes a recording from the iPhone PWA camera (`2026-09-05-session-video-nits.md`).
- The attach picker must stay EXEMPT from the passcode lock, or a 0 s auto-lock loses the pick (`2026-09-05-session-video-merge-e2e-fix.md`).
- **Composer focus must NEVER move the bar:** `bottomInteractivePadding`'s `keyboardVisible` may only read real insets (`viewInsets.bottom`/shared visualViewport) — folding `_focusNode.hasFocus` in (H1) dropped the input row by the whole resting clearance on every tap, behind the bottom nav on desktop web (`2026-09-12-session-composer-focus-drop.md`).

## Deploy / CI / release
- **Check CI with `gh api repos/Lentach/Fireplace/commits/master/check-runs`, never `gh run list --branch master`** — it returned weeks-old rows twice (`2026-09-08-session-dependabot-sweep-and-pc-health.md`).
- **`deploy-web.ps1` overwrites `frontend/build/web` with the PROD bundle** — rebuild locally before any 8093 check (`2026-09-03-session-lxxii-reset-door.md`).
- `deploy-web.ps1` exits 1 in a worktree after `PUBLISHED_OK` — run the gate from the main checkout, never `-SkipVerify` (`2026-09-06-session-auth-clarity.md`).
- **Merging an older release branch must never roll the pubspec back** — prod served a branch as a test until the 0.2.0 deploy (`2026-09-01-session-video-messages.md`).
- "Merge it and deploy, I've tested it" may mean the BRANCH — confirm WHICH build was tested (`2026-09-05-session-video-merge-e2e-fix.md`).
- CI never runs on a plain branch push — only `master` pushes and pull requests (`2026-09-05-session-video-nits.md`).
- Deploy order is BACKEND FIRST whenever the change adds a wire field or a migration (D26 `0017`, D27 `platform`/`identityReplacedTo`, (lxxiii) opt-in lock).
- **Rollback hazards:** never serve a web build below `d446a9d` to a browser with the passcode ON; never below 0.2.23 to an account with a phrase backup; never below 0.2.26 (0.2.25 gates an install for the life of the process after one mistyped phrase). Tag `pre-multidevice-master` = `9b6ea1a`; migration `0015` is not code-reversible.
- CI lint ratchet is a release gate: hand-formatted backend edits fail the run AFTER tests pass — prettier only the files you touched (`2026-09-08-session-d27-rename-and-review.md`).
- Actions billing/CI economics history: `2026-08-18-session-actions-billing-and-0.1.16.md`.

- **`Desktop/Fireplace` is on `feat/passcode-lock`, not master, and master is LOCKED in the `fireplace-0a` worktree** — root §1 claimed master until 2026-09-10 and the accuracy audit missed it (a git-state claim, not a code claim); push docs commits with `git push origin HEAD:master`, then push the branch too (`2026-09-10-session-workflow-2.0.md`).

- **CI Flutter is pinned through `frontend/pubspec.yaml` `environment.flutter:` (`flutter-version-file`)** — before 2026-09-10 CI floated on `channel: stable` (Dart 3.13) while the box ran 3.12, so a green CI could mean a different SDK than you tested. Bump the SDK by editing that one line; never re-float it (`2026-09-10-session-workflow-2.0.md`).
- **A `.java` file wakes CodeQL default-setup `Analyze (java-kotlin)` autobuild, which cannot build a Flutter module** — master went red on an unrelated check; default setup re-pinned to `["actions"]` via `PATCH …/code-scanning/default-setup` (`2026-09-12-session-batch-8-tooling.md`).
- **`up -d --no-deps db` drops the backend pool** — `docker restart fireplace-backend-1` after any db recreate; backend image/`/version` stay untouched (`2026-09-12-session-batch-8-tooling.md`).


## Tests / harness / falsification
- **If a mutant survives, the test is the thing that is wrong** — assert behaviour from the real gated state, never a diag marker (`2026-09-08-session-d27-rename-and-review.md`).
- **A harness can only find bugs in the shapes it builds** — the never-enrolled reset had a live population of exactly 0 (`2026-08-26-session-t10-reset-addressability.md`).
- **Never-enrolled is the DEFAULT population** — a probe can die on its own premise with its real assertions never running (`2026-09-05-session-video-merge-e2e-fix.md`).
- Never assume a red harness is the harness's fault: a red `e2e-wire` was three stale tests while a red `e2e-isolated-probes` was a real gap (lxxv) (`2026-09-05-session-video-merge-e2e-fix.md`).
- A mutation runner once left the mutant ON DISK — `git diff` after every mutation script (`2026-09-03-session-lxxii-reset-door.md`).
- A unit suite that pre-arms the engine cannot fail — the revoke button failed live with nothing in the log; drive the production path (`2026-08-21-session-t6-revocation.md`).
- `find.textContaining('dev')` also matches "device" — pin exact strings (`2026-09-09-session-c9-phrase-at-the-door.md`).
- A `str.count`/grep matcher must be CRLF-aware — F42 found 0 occurrences until it was; a CRLF-blind `sed` once missed the pubspec bump (`2026-09-09-…`, `2026-09-08-session-c8-…`).
- **Artillery socketio: the token can only reach `auth` as `{{ $processEnvironment.X }}`** — the launcher templates `config.socketio` before workers start (unresolved vars dropped) and the engine connects before the first flow step; `response` validates immediately only on an exact `data` match (`2026-09-12-session-batch-8-tooling.md`).
- **`flutter analyze` prints "N issues found" on stderr; Node ≥ 20 needs `shell: true` to spawn `flutter.bat`** — scrape both streams (`scripts/dart-lint-ratchet.mjs`) (`2026-09-12-session-batch-8-tooling.md`).
- **Take the Dart lint baseline on a clean worktree** — the main checkout flapped ±30 infos while a concurrent session edited `chat_input_bar.dart` (`2026-09-12-session-batch-8-tooling.md`).
- **Existing `testWidgets` device files are not Patrol tests** — under `patrol test` they hang in "Executing tests"; keep `flutter test integration_test -d` (`2026-09-12-session-batch-8-tooling.md`).
- **`auth.service.spec` recoverPassword second-boundary test flakes on slow runners** (equal second, expected greater) — rerun once; if it recurs, fake the clock (`2026-09-12-session-batch-8-tooling.md`).

## E2E / multi-device / recovery
- Registration lock is OPT-IN — arms only once `account_authorizations` has a row; a client that sees no `linkingEnabled` field fails CLOSED to the old gate (`2026-09-05-session-optin-lock-gate.md`).
- A `registrationId` may not change under an unchanged identity; the OTP replenishment path bypasses `upsertKeyBundle` so BOTH uploads carry the (lxiv) guard; residual `_reenrollAfterReset` has no in-flight latch — recorded, not fixed (`2026-08-30-session-bounded-gate-lxiv.md`).
- A warning the user cannot act on is a dead end; recovery state must survive a restart — read the THREE addenda (`2026-08-29-session-d1-d2-recovery.md`).
- A term added to a gate predicate needs an owner that clears it — read `clearAll()` when adding state to a process singleton (`2026-09-08-session-c7-final-review.md`).
- Login hardcoding `deviceId = 1` locked owners out after a reset — login resolves the LIVE PRIMARY; session gates deny only on an EXPLICIT `revokedAt`; `getServedMessageIds` answers a revoked device with SILENCE (`2026-08-21-session-t6-revocation.md`).
- Hostile `nextListVersion` inflation is bounded by a plausibility ceiling (`2026-08-26-session-t10-reset-addressability.md`).
- Wake delivers `hidden → inactive → resumed`; the privacy curtain is the DOM `#fp-curtain`, not a Flutter widget (`2026-09-06-session-passcode-wake-curtain-merge.md`).
- Multi-device permanent record: `.planning/multi-device/` (`FINISH-HERE.md`, `progress.md`, `task_plan.md`) and `docs/design/multi-device.md` §12 — not LATEST.

## Auth
- A 409 the client could not SPEAK created a duplicate account — `ApiException` carries the STATUS, `classifyAuthFailure` maps per door, registration signs in and tries the typed credentials on 409 BEFORE refusing (`2026-09-06-session-register-409-diagnosis.md`).
- iOS Safari freezes a tab's socket in the background; the first POST after resume hangs — "server error" reports from iPhone browser tabs are usually this (`2026-09-08-session-c8-register-ceremony.md`).

## Android / push
- **versionCode floor 10024**; `am force-stop` silently drops FCM; `FLAG_SECURE` blocks screencap; verify an installed APK's dart-defines by byte-searching `kernel_blob.bin` (`2026-09-02-session-fcm-e2e.md`).
- PWA notification regression history: `2026-08-20-session-notif-regression.md`.

## Agent tooling / editing
- **`String.replace` treats `$` in the REPLACEMENT as special** — a doc patch containing `` {1,32}$` `` spliced `CLAUDE.md` into itself twice; use `() => to` (`2026-09-08-session-d27-rename-and-review.md`).
- The `edit` tool needs a tag from a `read`, never from `grep`; in a multi-worktree checkout give `edit` an ABSOLUTE path (`2026-09-08-session-d27-…`, `2026-09-08-session-dependabot-…`).
- **This worktree is shared: other agents/the owner edit it concurrently** — foreign uncommitted diffs appeared mid-session twice (`local/` sweep 09-08; six frontend files 09-10). NEVER `git add -A` here; stage by explicit path and `git show --stat` the commit before pushing (`2026-09-08-session-d27-rename-and-review.md`, `2026-09-10-session-workflow-2.0.md`).
- **NEVER leave a tracked file reverted in this shared worktree for an A/B measurement** — a concurrent session's docs commit (`eec7d98`) staged the temporarily pre-fix `chat_input_bar.dart` and pushed the shipped fix off master; A/B on a separate clone, or restore + re-verify immediately (`2026-09-12-session-composer-focus-drop.md`).
- **Live browser drive of the local dev build works headless:** `docker-compose up`, `flutter run -d web-server` (spawn via `cmd /c`, `flutter` is a .bat), seed users by `POST /auth/register` + a `conversations` row in the dev DB, then measure Flutter web geometry from `document.activeElement.getBoundingClientRect()` (the real editing host) instead of pixel-reading screenshots; a fresh PORT gives a fresh origin when an old passcode blocks the old one (`2026-09-12-session-composer-focus-drop.md`).
- Flutter's `flt-semantics-placeholder` never populates from a synthetic click — `observe()` is useless; drive with two isolated Chromes on `--remote-debugging-port`, pixel clicks from screenshots, CDP `Input.insertText` (`2026-09-08-session-c7-final-review.md`).
- A cold Chrome profile needs ~15 s before the first form paints (`2026-09-09-session-c9-phrase-at-the-door.md`).
- Brand sweeps MUST eyeball the RENDERED page — split-span wordmarks defeat grep; re-verify subagent compliance claims, one fabricated its version bump (`2026-08-26-session.md`).
- **Subagents on 7–15 min tasks null-yield ~half the time** (3 of 6 auditors, 2026-09-10) — the work is on disk, the context is intact. Two rules: (1) write the task so the FILE is the deliverable and the yield is a one-line pointer to it (the four researchers did this: 0 losses); (2) if a yield is still null, `hub send … await:true` asking for the report — never rerun (`2026-09-10-session-workflow-2.0.md`).
- `read` of `LATEST.md` truncates lines at 768 chars — measure with `wc`, not by eye; NEVER re-emit a whole entry from the displayed text (the tail, incl. the `➡` pointer, is silently dropped): `sed -n '<n>p'` it, patch only the stale clause, diff the new line against `git show <prev>:…LATEST.md` (`2026-09-10-session-workflow-2.0.md`, `2026-09-12-session-composer-focus-drop.md`).
- **npm override of a dep you also depend on directly needs the `"$pkg"` reference form** — `overrides.multer: "$multer"` + `multer ^2.3.0`; a nested literal is ignored and `npm ls` shows `invalid` (`2026-09-12-session-batch-8-tooling.md`).
- **NEVER override `csv-parse` to v7 in `scripts/smoke`** — artillery 2.0.34 (latest; still depends on `csv-parse ^4`) does `import _csv from 'csv-parse'` in its ESM build, and v7 exports `{ parse }`, so oclif cannot load `run`/`quick`/`run-*` at all (`run is not a artillery command`); `npm ls` looks clean, only running it reveals it. Alert #119 dismissed `not_used` instead: dev-only dep, and the vulnerable `columns` path needs a `payload:` CSV no scenario defines (`2026-09-12-session-alert-119-csv-parse.md`).
- **`/auth/register` throttles 10 per 15 min per IP** — repeated smoke runs 429; reuse a throwaway account via `FP_SMOKE_USER/PASS` (`2026-09-12-session-batch-8-tooling.md`).
- **In the shared worktree, `git commit` ships whatever the OTHER session has STAGED** — explicit-path `git add` does not protect you; run `git diff --cached --stat` and `git reset -q -- <foreign>` before every commit (`2026-09-12-session-batch-8-tooling.md`).
- **`gh run rerun` on an old run cancels the master tip's run via the concurrency group** — rerun the tip's own run id, never an older one (`2026-09-12-session-batch-8-tooling.md`).

## Handoff / LATEST budget history
- **2026-08-14, owner decision: per-entry WORD budgets (≤3900 total / ≤700 per entry) were REMOVED** — the shared banner counted as an "entry", so adding a genuinely new binding fact to it got the commit BLOCKED, and the cheapest escape was deleting evidence from a summary written minutes earlier; three sessions in a row burned time on the arithmetic instead of the handoff.
- **2026-09-10, workflow 2.0 re-introduced a per-entry CHAR cap (≤900, hook 1000) — and the 08-14 failure mode is gone by construction:** there is no banner (standing warnings live here, one line each, uncapped), so nothing binding ever has to fit inside an entry; the entry only has to link the dated file. If the cap ever forces deleting evidence again, that is a regression of this exact decision — move the fact here or to the dated file, never trim it away.

- **OMP injects only `AGENTS.md`** at depth 0 (it shadows root `CLAUDE.md`); root/tier files are deliberate reads. A `.omp/rules` edit-time rule needs `condition: ".*"` + explicit `scope: "tool:edit(<glob>), tool:write(<glob>)"` — the YAML-list `condition:` shorthand silently registers nothing; comma-string `globs:` in `.cursor/rules` is inert in OMP (YAML array works). Proven by fresh-session probes 2026-09-10 (`docs/research/2026-09-agent-harness-practice.md` §8) (`2026-09-10-session-workflow-2.0.md`).

## Owner-owed decisions (open)
- README screenshot recapture, GitHub repo renames, the domain decision (`2026-08-26-session.md`).
- Thief-with-password matrix answers (`2026-09-03-session-lxxii-reset-door.md`).
- iPhone PWA camera recording for the WebKit probe fix; iOS eyeballing of reset-ceremony statuses, revoke/mismatch notices, fingerprint sheet, phrase reveal (`2026-09-08-session-c8-register-ceremony.md`).
- Signed 0.1.24+ APK release waits on the passcode feature (now shipped) — re-plan (`2026-09-02-session-fcm-e2e.md`).
- `dependabot.yml` group fix UNPROVEN; Kaspersky not running + Defender stood down — the dev box is unprotected; 5× Kernel-Power 41 (`2026-09-08-session-dependabot-sweep-and-pc-health.md`).
- Install the Mend Renovate app, then delete `.github/dependabot.yml` in the first green Renovate PR; Patrol web leg still not green; the artillery socket smoke is **4/5 locally** (one reproducible `errors.response timeout`, `vusers.failed == 0` red on `e5cd287`) despite the batch-8 "5/5" claim (`2026-09-12-session-batch-8-tooling.md`, `2026-09-12-session-alert-119-csv-parse.md`).
