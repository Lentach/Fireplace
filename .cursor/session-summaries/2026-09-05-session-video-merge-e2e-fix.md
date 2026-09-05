# 2026-09-05 (evening → late) — video-nits merged, both CI reds explained and fixed, (lxxv) ruled, master deployed as 0.2.16, passcode-lock rebased + picker-guard bug fixed

Owner's brief, in order: (1) "make sure the passcode lock works correctly and is ready to deploy; we
changed video messages, it might conflict"; (2) "video messages are done and ready but I'm not sure it
was merged and deployed — if not, merge it and deploy, I've tested it"; (3) on being shown that master
itself was red: "merge video to master now; hold deploy until a71ed33's red is resolved"; (4) "fix the
3 wire tests now (enrol DAK first), then re-run the harness".

## State at the start (all re-verified this session, not inherited)

- Prod `/version.json` → `0.2.15 / c8f662e`, `/version` → `0.2.14 / 7e957d64`. Both from
  `test/video-nits-0.2.3`, i.e. the branch test the owner had been using. **Video WAS live; what was
  missing was the merge.** That branch is 3 commits behind master — it does NOT contain `a71ed33`
  ((lxxiii)/(lxxiv), frontend 0.2.4), so the opt-in-lock work has never been in front of users.
- `origin/master` = `a71ed33`; `feat/video-nits` 24 ahead / 0 behind (clean fast-forward); PR #163 open.
- `feat/passcode-lock` = `1d682e4`, 14 ahead of master, 0 behind.
- CI: master run 943 (`5d669ce`, 0.2.3) fully green → run 944 (`a71ed33`) the FIRST red: `E2E wire
  harness` (3 tests) + `E2E isolated probes` (1). The video-nits PR run had the same two reds plus
  `Backend tests` — that one was only the count verifier (1063 documented, Jest has 1064).
- `gh repo view --json isPrivate` → **false**. The repo is PUBLIC; root `CLAUDE.md` §3 "private
  free-plan repo" wording is stale on that word (the PII rule is identical either way).

## Passcode × video: no code conflict

Trial merge of `feat/passcode-lock` into `feat/video-nits` in a throwaway worktree: only `CLAUDE.md`
(the Tests count line) and `LATEST.md` conflicted. Real code overlap was `settings_screen.dart`
(passcode adds two imports + a `Consumer<PasscodeProvider>` row; video adds the autoplay switch —
additive) and the l10n ARBs/generated files (unioned; `gen-l10n` afterwards produced ZERO drift).
`flutter analyze` clean; **full suite 1929 passed / 14 skipped** on the merged tree.

Runtime interaction checked by reading, not guessed: the lock is mounted in `MaterialApp.builder`
(`PasscodeGate`), so the fullscreen video `showDialog` route is under it; `VideoMessageContent`
pauses on `AppLifecycleState.paused`. One nit left for the owner, NOT fixed: on **Android** (no reload
on lock) a manual padlock tap during a fullscreen clip with sound leaves the audio playing behind the
`Offstage` lock. Web is immune — a lock there is a process replacement.

## Merge: `feat/video-nits` → master

Fast-forward, pushed from a detached worktree as `git push origin HEAD:refs/heads/master` (the local
`master` ref is checked out in `fireplace-0a`, never move it). Plus one docs commit `29e5734`
(backend count 1063 → 1064). GitHub auto-marked PR #163 MERGED on the push. Master `Backend tests`
went green on `29e5734`; the two E2E reds stayed — they are `a71ed33`'s.

## The e2e-wire red, proven

Ran the harness locally against master's backend (`docker compose up -d db backend`, dev watch mode
takes ~2 min to compile; `E2E_DB_CONTAINER=fireplace-db-1` is REQUIRED for the SQL channel or the
recovery-key tests fail with `e2eSql failed (exit 1)` — the default in `e2e_test_client.dart:66` is
`fireplace-0a-db-1`).

`registration_lock_test` ×2 failed with `Expected: false / Actual: true`: the replacement upload on a
fresh account SUCCEEDED. Source: `key-bundles.service.ts:173-195` refuses only when `isEnrolled`
(an `account_authorizations` row); otherwise `authorizedBy = 'unlocked'`. `:516-524` exempts the OTP
site for un-enrolled accounts too, with the comment naming "(lxxiii) clause 1". So all three wire
failures asserted the PRE-opt-in mandatory lock on never-enrolled accounts — stale tests, not a
key-exchange bug. Also learned: for an ENROLLED account the signature-proof path is refused outright
(`:395-399`, (liv)), so the §6.1 nonce single-spend is no longer observable on the wire at all —
un-enrolled falls through to `unlocked`, enrolled refuses regardless. `authorizedBy`/`via` is only
logged (`[identity-churn] … via=`), never persisted or acked.

Fix (`95df1fb`, master):
- `registration_lock_test.dart`: test 1 = un-enrolled account, unsigned replacement ACCEPTED, stored
  identity moves, the OTHER session receives `ownIdentityReplaced` (the only protection such an account
  has). Test 2 = enrol a DAK through the real `enrollDeviceAuthority` wire (`DeviceAuthorityEngine()
  .enroll(...)`, the T2 pattern) under the identity that now owns the bundle, then a third install's
  unsigned upload → `identity_locked`, bundle byte-identical, `events.none('ownIdentityReplaced')`.
  The nonce half was removed with a comment pointing at `chat-key-exchange.service.spec.ts`.
- `full_stack_e2e_test.dart`: the OTP-under-unpublished-identity refusal moved into the T2 group AFTER
  alice's enrolment (it captures the published identity itself; `sharedIdentity` was group-scoped).
- No overlap with master's opt-in probe `enrolled_identity_lock_test.dart` (isolated job, (liv):
  SIGNED refusal + positive control); the shared run now covers the unsigned refusal and the alarm.
- Proof: `flutter test test_e2e` → **44 passed / 5 skipped, 0 failed**, exit 0, after `docker compose
  restart backend` to clear the in-memory `/auth/register` 10/h bucket that my earlier partial runs had
  spent (the first full run showed 3 `ThrottlerException` setUpAll failures — that is the harness's
  own documented ceiling, not a regression). `CLAUDE.md` §3 harness figure updated 43/2 → 44/5.

## The isolated-probe red — a REAL gap, ruled (lxxv)

`identity_reset_teardown_test.dart:542` "§6.2 reset on a NEVER-ENROLLED account" failed at its PREMISE
(`:562-566`, `expect(error, 'identity_locked')`), which (lxxiii) removed — so its actual guard
assertions (`events.none('deviceList')`, `liveDeviceIds`) had never executed since `a71ed33`. Not
stale, though: `requestIdentityReset` had NO enrolment check (`identity-reset.service.ts` never consulted
`isEnrolled`), and `device_link_gate_screen.dart:136` shows the reset door in every non-pending state
including `checkingOnly`. So an un-enrolled owner could start the 72 h ceremony; its completion
teardown revokes device 1 and allocates id ≥ 2 while the account stays un-enrolled — (xlv) clause 2
then keeps the server silent, and the only live device is unaddressable until it re-enrols. And
(lxxiii) turned never-enrolled from "a live population of exactly 0" (the header's own words) into the
DEFAULT population: every user who never linked a second device.

Owner delegated the ruling ("I've not enough knowledge to take that decision, please make it for me").
Ruled **(a): refuse the ceremony for an un-enrolled account.** Reasoning: §6.1 never refuses such an
account, so the unlocked remint under device 1 IS its recovery and a ceremony can only harm it;
enrolment is monotonic ((xxix)), so the refusal can never trap an account that later needs the
ceremony. Rejected (b) skip roster reallocation when un-enrolled — keeps a 72 h wait that buys nothing
and leaves the door's copy lying; rejected (c) rewrite the probe around the stranding — documents the
gap instead of closing it. Recorded as spec §12 D25 (lxxv).

Implementation (`dbd3cc8` + count `9a1c439`, master):
- Backend: `RequestResetStatus` gains `not_enrolled`; `requestReset` answers it when no
  `account_authorizations` row exists, BEFORE the phrase is examined (nothing written, phrase neither
  spent nor counted), AFTER the pending check (a pre-rule row still answers `existing`, stays
  cancellable). `IdentityResetService` injects the `AccountAuthorization` repo (already in the module's
  forFeature list). Red→green unit tests; key-bundles jest 223/223; backend count 1064 → **1066**.
- Client: `identityResetAnswerMessage` maps `not_enrolled` → `identityResetNotEnrolled` (EN+PL:
  "no linked devices, keys not locked, sign in on the new device");
  `identityResetAnswerIsRefusal` counts it. Older clients: unknown status → silent (`default`).
- Probe: the never-enrolled group rewritten to prove the contract end to end — unlocked remint under
  device 1 (no re-homed `deviceId` in the ack, nothing revoked), `not_enrolled` with no ceremony row and
  `usedAt IS NULL AND failedAttempts = 0`, `authorization: null` served, `DeviceListCache.adopt` →
  `liveDeviceIds == [1]` and `isLiveDevice(1)`, fresh bundle served under device 1. Ran locally exactly
  as CI does: RESET_PROBE **2/2**, ENROLLED_LOCK_PROBE **2/2**, then the shared harness again **44/5**.
- Root `CLAUDE.md` §7 reset-ceremony line carries the new status.

**Master CI on `9a1c439`: 5/5 GREEN** — the first fully green master since `5d669ce` (0.2.3).

## `feat/passcode-lock` — rebased ×3, and a real bug the advisor caught

Rebased onto `29e5734`, `95df1fb`, `8a5c41c`, then `9a1c439`; now **`83afc18`**, 15 commits, pushed
`--force-with-lease` each time. Every rebase was diffed against `git merge-tree --write-tree` of a plain
merge: **byte-identical for every code path**; only `CLAUDE.md:67` (a three-number line: backend /
Flutter / harness — take the branch side then force all three; the first sed no-op'd once because the
intermediate commit read 1908, not 1909) and `LATEST.md` needed hands. Docs invariants after each: one
`Still binding` bullet, five dated entries, the four passcode session files, §10a entropy bullets.

⚠️ The rebases were done IN THE OWNER'S MAIN WORKTREE while his branch was checked out there — the
advisor rightly flagged it. Code identical, but a running `flutter run` would have been on different
files. He had said testing was paused; restart any dev server before trusting it.

**Picker-guard bug (advisor finding, verified in source, fixed `cdf2a27`):** `main_shell.dart:88-89`
fires `noteBackgrounded()` on ANY visibility loss, while `:120` right below suppresses the frozen-page
reload for exactly the `composerNativePickerActive` case. The attach camera/file sheet IS a visibility
loss (and `paused` on Android), so at auto-lock 0 s: tap attach → `_lock()` → keys revoked → on web the
process replaced → picked bytes lost. `PasscodeProvider` now takes `nativePickerActive` (default
`composerNativePickerActive.value`, injectable): `noteBackgrounded` still stamps the clock (so a 60 s
window is measured from the picker, not a stale departure) but holds the immediate lock;
`evaluateOnForeground` returns early while the span is up. The span self-caps at 3 min, so a stuck flag
degrades to the old behaviour. Three tests, proven by MUTATION — removing either guard fails two of them.
Suite **1932 / 14 skipped**, analyze clean. Draft PR **#164** opened so the branch finally gets CI runs
(CI triggers on master pushes and `pull_request` only — the branch had NEVER had one); the pre-rebase
run was green except the isolated probe it inherited from master, now fixed.

Still open on the branch: Android-only — a manual padlock during a fullscreen clip with sound leaves
audio playing behind the `Offstage` lock (web relaunches). Owner's UX verdicts (reload-on-lock, 0 s
desktop auto-lock, 6-digit vs alphanumeric) outstanding; his sequencing: test the branch, then merge.

## Deploy — master live, both tiers

Preflight: `git diff 7e957d6 origin/master` touched NO migrations, entities, `docker-compose.prod.yml`
or `backend/Dockerfile` → no staging rehearsal. Order per `a71ed33`'s own note, backend FIRST:
VM `git checkout master && git pull --ff-only && ./deploy-backend.sh` → healthy in 10 s, `/version` →
`0.2.4 / 9a1c4396` (the `version` string is the pubspec at the VM's checkout; the 0.2.16 bump landed one
commit later — `gitCommit` is the truth). Then `chore(release): frontend 0.2.16` (`fda92b3`, CRLF-aware
sed, re-grepped), `deploy-web.ps1` from a detached `../fireplace-deploy` worktree → `PUBLISHED_OK`, exit
1 from the dep-less gate as documented, smoke from the main checkout `--commit fda92b3` → **5/5**.
Served bundle: `tylko MP4` 1, `reset nie jest potrzebny` 1, `not_enrolled` 2, `Blokada kodem` 0
(passcode is not on master — correct). Live now: `/version.json` **0.2.16 / fda92b3**, `/version`
**9a1c4396**, `/health` ok. First time in front of users: `a71ed33`'s opt-in lock + gate, (lxxv), and
the whole video-nits line as MASTER rather than a branch test. Rollback: web redeploy `c8f662e`;
backend `git checkout test/video-nits-0.2.3 && ./deploy-backend.sh`.

## Traps recorded

- `flutter test test_e2e` locally: set `E2E_DB_CONTAINER=fireplace-db-1` (via `cmd /c "set …&&
  flutter.bat test …"` — a git-bash `export` does not reach the Windows child; the default in
  `e2e_test_client.dart:66` is `fireplace-0a-db-1`), and expect the `/auth/register` 10/h/IP bucket to
  bite on the second run within an hour; `docker compose restart backend` resets it (in-memory).
- Docker Desktop QUIT between two runs an hour apart (npipe gone). `powershell Start-Process 'C:\Program
  Files\Docker\Docker\Docker Desktop.exe'`; daemon answered in ~10 s. A fresh backend worktree needs
  `npm ci` before jest (`'jest' is not recognized`), and `npx jest` refuses (two configs) — use `npm test --`.
- To run the dev backend from a DIFFERENT worktree against the same containers: `docker compose -p
  fireplace up -d --force-recreate backend` from that worktree (bind mount follows the cwd); verify with
  `docker inspect … Mounts`.
- dart2js escapes non-ASCII in string literals — grep the served bundle for an ASCII substring of a
  Polish string (`nie ma połączonych` → 0, `nie ma po` → 1).
- `git worktree` + `comm <(…)` fails on this Windows git-bash — write the two lists to files first.
- The `CLAUDE.md:67` Tests line collides three ways on every rebase; taking one side and sed-fixing the
  others silently reverts whichever number you forgot. Grep all three after resolving.
- Ask the deploy question BEFORE assuming "merge and deploy" means master: here the tested build was a
  branch, master carried untested work, and deploying master blind would have shipped it on red.
