# 2026-09-05 (evening) — video-nits merged to master, the e2e-wire red explained and fixed, passcode-lock rebased and green

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

## The isolated-probe red — NOT fixed, needs a ruling

`identity_reset_teardown_test.dart:542` "§6.2 reset on a NEVER-ENROLLED account" fails at its PREMISE
(`:562-566`, `expect(error, 'identity_locked', reason: '§6.1 is what makes a reset necessary at
all')`). Under (lxxiii) a never-enrolled recovering install remints unlocked; it never needs the
ceremony, and the product routes it that way (`IDENTITY_GUARD_UNLOCKED_REMINT`). The test cannot be
adapted mechanically: once the unlocked upload succeeds, the later post-reset upload is not an identity
change, so no roster teardown runs and `accepted['deviceId']` is absent.

But the reset is still REACHABLE for an un-enrolled account: the wire `requestIdentityReset` has no
enrolment check (`identity-reset.service.ts` never consults `isEnrolled`), and
`device_link_gate_screen.dart:136` shows the reset door on every non-pending state including
`checkingOnly` (identity check unavailable). If such an account completes the 72 h ceremony, the
teardown revokes device 1 and allocates id ≥ 2 while the account stays un-enrolled — exactly the
un-addressable shape the probe guards ((xlv) clause 2 keeps the server silent, so it is fail-closed,
but the account is stranded until it re-enrols). The LATEST header already records "the never-enrolled
reset had a live population of exactly 0". Options for the owner / the (lxxiii) agent: (a) refuse
`requestIdentityReset` for un-enrolled accounts (the unlocked remint IS their recovery); (b) make the
teardown skip roster reallocation when un-enrolled; (c) keep the mechanism and rewrite the probe to
force the ceremony without the `identity_locked` premise. Until ruled, `e2e-isolated-probes` stays red
and **"never deploy on red" still applies to master**.

## `feat/passcode-lock`

Rebased twice (onto `29e5734`, then `95df1fb`); now `dfdf846`, 14 commits, pushed with
`--force-with-lease`. Each time the rebased tree was diffed against `git merge-tree --write-tree` of a
plain merge: **byte-identical for every code path**; only `CLAUDE.md:67` and `LATEST.md` needed hands
(the count line is a three-way collision every time — video 1768/10, passcode 1909/14, merged
1929/14). Docs invariants re-checked after each rebase: exactly one `Still binding` bullet, the four
passcode session files present, §10a entropy-floor bullets present. Analyze clean; full suite **1929 /
14 skipped** on the rebased branch. Owner's UX verdicts (reload-on-lock, 0 s auto-lock on desktop web,
6-digit vs alphanumeric) are STILL outstanding; nothing in the branch changed this session.

## Deploy status

**Nothing deployed.** Prod is still `0.2.15 / c8f662e` + backend `0.2.14 / 7e957d64` from the test
branch. When the isolated-probe red is ruled on and master is green: `deploy-backend.sh` on the VM
FIRST (the VM is checked out on `test/video-nits-0.2.3` — `git checkout master` there first; (lxxiii)
needs the server's `via=unlocked` before the web build ships), then bump `frontend/pubspec.yaml`
0.2.4 → **0.2.16** (PATCH above the live 0.2.15; the file is CRLF — use the editor), `deploy-web.ps1`,
smoke `--commit <sha>` from the main checkout, and grep the served bundle for a localized string.
Merging `feat/passcode-lock` needs the owner's explicit OK; he has not given it.

## Traps recorded

- `flutter test test_e2e` locally: set `E2E_DB_CONTAINER=fireplace-db-1` (via `cmd /c "set …&&
  flutter.bat test …"` — a git-bash `export` does not reach the Windows child), and expect the
  `/auth/register` 10/h/IP bucket to bite on the second run within an hour; `docker compose restart
  backend` resets it (in-memory throttler).
- `git worktree` + `comm <(…)` fails on this Windows git-bash ("fd redirections beyond stdin/stdout/
  stderr") — write the two lists to files first.
- Ask the deploy question BEFORE assuming "merge and deploy" means master: here the tested build was a
  branch, master carried untested work, and deploying master would have shipped it on red.
