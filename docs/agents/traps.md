# Traps — permanent, one line each

Standing warnings that used to live in the `LATEST.md` banner and in rotated-out entries. **One line per trap; link the dated summary that earned it.** `grep` this file for the area you are about to touch. New traps: append here in the same commit as the session summary (the `## Traps` section of the summary lists them too). Never delete a line because it is old — delete it only when the code that made it true is gone.

## Composer / attachments / media
- **Nothing ships in the composer or attachment picker without a green repro AND the owner's explicit OK; never `git revert 0cbf17b`** — owner: "we made huge regress on composer and now all old bugs are back" (`2026-08-19-session-composer-regression.md`).
- **Dependabot #174 (`file_picker` 11.0.3) is deliberately OPEN** — `web_file_input.dart` exists because of 11.0.2's DOM behaviour; no host test sees that path (`2026-09-08-session-dependabot-sweep-and-pc-health.md`).
- A video RETRY must carry the full payload (poster/dimensions), not url/key/iv/duration only — a once-failed clip reached the peer as a 220 px blank square (`2026-09-05-session-video-nits.md`).
- A route pushed over the chat must RELEASE the inline video slot (`2026-09-05-session-video-nits.md`).
- The WebKit `videoWidth == 0` probe fix is **NOT iOS-verified** — owner owes a recording from the iPhone PWA camera (`2026-09-05-session-video-nits.md`).
- The attach picker must stay EXEMPT from the passcode lock, or a 0 s auto-lock loses the pick (`2026-09-05-session-video-merge-e2e-fix.md`).

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

## Tests / harness / falsification
- **If a mutant survives, the test is the thing that is wrong** — assert behaviour from the real gated state, never a diag marker (`2026-09-08-session-d27-rename-and-review.md`).
- **A harness can only find bugs in the shapes it builds** — the never-enrolled reset had a live population of exactly 0 (`2026-08-26-session-t10-reset-addressability.md`).
- **Never-enrolled is the DEFAULT population** — a probe can die on its own premise with its real assertions never running (`2026-09-05-session-video-merge-e2e-fix.md`).
- Never assume a red harness is the harness's fault: a red `e2e-wire` was three stale tests while a red `e2e-isolated-probes` was a real gap (lxxv) (`2026-09-05-session-video-merge-e2e-fix.md`).
- A mutation runner once left the mutant ON DISK — `git diff` after every mutation script (`2026-09-03-session-lxxii-reset-door.md`).
- A unit suite that pre-arms the engine cannot fail — the revoke button failed live with nothing in the log; drive the production path (`2026-08-21-session-t6-revocation.md`).
- `find.textContaining('dev')` also matches "device" — pin exact strings (`2026-09-09-session-c9-phrase-at-the-door.md`).
- A `str.count`/grep matcher must be CRLF-aware — F42 found 0 occurrences until it was; a CRLF-blind `sed` once missed the pubspec bump (`2026-09-09-…`, `2026-09-08-session-c8-…`).

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
- `git add -A` staged 51 files from the ignored-by-intent `local/` dir — check `git status` before staging wide (`2026-09-08-session-d27-rename-and-review.md`).
- Flutter's `flt-semantics-placeholder` never populates from a synthetic click — `observe()` is useless; drive with two isolated Chromes on `--remote-debugging-port`, pixel clicks from screenshots, CDP `Input.insertText` (`2026-09-08-session-c7-final-review.md`).
- A cold Chrome profile needs ~15 s before the first form paints (`2026-09-09-session-c9-phrase-at-the-door.md`).
- Brand sweeps MUST eyeball the RENDERED page — split-span wordmarks defeat grep; re-verify subagent compliance claims, one fabricated its version bump (`2026-08-26-session.md`).
- Subagents doing long audits tend to `yield` with null data after 7–10 min of real work — the edits are on disk and the context is intact; `hub send … await:true` asking for the report recovers it, do not rerun (`2026-09-10-session-workflow-2.0.md`).
- `read` of `LATEST.md` truncates lines at 768 chars — measure with `wc`, not by eye (`2026-09-10-session-workflow-2.0.md`).

## Handoff / LATEST budget history
- **2026-08-14, owner decision: per-entry WORD budgets (≤3900 total / ≤700 per entry) were REMOVED** — the shared banner counted as an "entry", so adding a genuinely new binding fact to it got the commit BLOCKED, and the cheapest escape was deleting evidence from a summary written minutes earlier; three sessions in a row burned time on the arithmetic instead of the handoff.
- **2026-09-10, workflow 2.0 re-introduced a per-entry CHAR cap (≤900, hook 1000) — and the 08-14 failure mode is gone by construction:** there is no banner (standing warnings live here, one line each, uncapped), so nothing binding ever has to fit inside an entry; the entry only has to link the dated file. If the cap ever forces deleting evidence again, that is a regression of this exact decision — move the fact here or to the dated file, never trim it away.

## Owner-owed decisions (open)
- README screenshot recapture, GitHub repo renames, the domain decision (`2026-08-26-session.md`).
- Thief-with-password matrix answers (`2026-09-03-session-lxxii-reset-door.md`).
- iPhone PWA camera recording for the WebKit probe fix; iOS eyeballing of reset-ceremony statuses, revoke/mismatch notices, fingerprint sheet, phrase reveal (`2026-09-08-session-c8-register-ceremony.md`).
- Signed 0.1.24+ APK release waits on the passcode feature (now shipped) — re-plan (`2026-09-02-session-fcm-e2e.md`).
- `dependabot.yml` group fix UNPROVEN; Kaspersky not running + Defender stood down — the dev box is unprotected; 5× Kernel-Power 41 (`2026-09-08-session-dependabot-sweep-and-pc-health.md`).
