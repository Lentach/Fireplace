# 2026-08-16 — 0.1.10 SHIPPED: tri-state identity guard + boot-marker forensics, reviewed, wire-tested, DEPLOYED

**Prod: frontend `0.1.10 / 275e75d` + backend `0.1.10 / 275e75de`, both live, smoke 5/5.**
Implements handoff §5.1 + §5.3 (owner authorized same day, after confirming the guard moves no
key material). Commits: `422104d` (feature), `275e75d` (review fixes). CI run `31924009326`
green on all four jobs including `e2e-wire`.

## What shipped

- **Backend:** `checkOwnKeyBundle` → `ownKeyBundleStatus {exists}` — read-only, caller-only,
  throttled like its siblings, never consumes an OTP (`hasKeyBundle` in
  `key-bundles.service.ts`; handler in `chat-key-exchange.service.ts`; gateway wiring + specs).
- **Frontend guard:** `EncryptionService.initialize(userId, {checkServerBundleExists})` — on a
  truly empty keystore: server says exists → durable `IDENTITY_GUARD_SERVER_BUNDLE_EXISTS` +
  `E2eIdentityIncompleteException` (recovery stays the consented
  `regenerateIdentityAfterConfirmedLoss`); explicit false → generate; **UNKNOWN (timeout,
  error, malformed payload, absent callback) → NEW `E2eIdentityCheckUnavailableException`,
  transient: E2E stays down, retried next connect.** Absent callback = UNKNOWN by design — no
  future caller can skip the check (pinned by test).
- **Forensics (§5.3):** tri-store boot marker (localStorage + IndexedDB + CacheStorage,
  read-before-plant, per-arm fail-shut, whole-call 4 s bound, IDB `onblocked` handled,
  `isCompleted`-guarded handlers) recorded durably as `BOOT_MARKERS {ls,idb,cache}`;
  `STORAGE_PERSIST` now carries `storage.estimate()` usage/quota; **both probes moved BEFORE
  keystore creation**; `main.dart` persist request awaited with a 3 s bound (was
  fire-and-forget).
- **Review round (reviewer subagent) found 1 MAJOR, fixed in `275e75d`:** the single-flight
  check's `.timeout()` resolved only the first awaiter and orphaned concurrent ones, and
  `initializeE2E` had no re-entrancy guard → a reconnect inside the 6 s window could hang or
  race a double `_generateKeys()`. Fix: timeout completes the SHARED completer; owner-guarded
  field clear; `initializeE2E` in-flight latch (same user shares one run). Regression test:
  two concurrent `initializeE2E` ⇒ exactly one key upload.
- Banner copy reworded new-device-first in the arbs — **deliberately NOT in this commit**: the
  sibling video-feature session owns the l10n files right now (they removed
  `localMessageCache` while their screen change was uncommitted; committing l10n here would
  have produced an unbuildable commit). The wording rides with their branch.

## Verification ledger

unit: backend 676/49 + ratchet PASS 912 · flutter 1269→1270/10sk + analyze clean · both count
verifiers green · **e2e-wire harness 13/2sk against a local docker stack at the exact commit**
· **live-socket smoke of the new event: fresh user → `{exists:false}`, after `uploadKeyBundle`
→ `{exists:true}`** · CI 4/4 · post-deploy smoke 5/5 (bundle grep `275e75d`, headless boot).

## Traps paid (new or recurred)

- **`deploy-web.ps1` exit-21 silent publish halt RECURRED** (4th occurrence: 07-08, 07-15,
  07-16, now). Build fine, log ends at the "Publish via ssh/scp" banner, ssh-from-PowerShell
  dies silently. Manual publish (staging-dir + scp + atomic swap + `chmod -R a+rX`) works
  verbatim from bash. Also: a git worktree has no `deploy-web.config.ps1` (gitignored) — copy
  it in before building.
- **Shared-file commit race:** `git add CLAUDE.md` swept the sibling agent's simultaneous
  count-line edit (681/1301) into a commit whose tree holds 676/1270 — count verifiers would
  have gone red at that commit. Caught and amended. Rule: while a sibling session is live,
  never `git add` a shared file without re-reading it, and make each commit's counts true for
  ITS OWN tree.
- **The mixed working tree is unbuildable mid-flight** — all verification ran in throwaway
  `git worktree`s at exact commits (also how the deploy build was produced). The dev compose
  **bind-mounts `backend/` wholesale** (`npm install` runs in-container): installing anything
  on the host inside that dir corrupts the container's deps; test tooling goes OUTSIDE the
  repo dir.
- OTP epoch note for future forensics: `one_time_pre_keys.createdAt` batch-inserts date
  re-mints to the second; the register throttle (10/hr/IP) makes wire smokes fail silently —
  restart backend to reset.

## State / follow-ups

- Sibling branch `feat/video-ux-batch` (video messages + UX batch) is UNMERGED and carries the
  l10n wording + lockfile; its own deploy order note applies (staging rehearsal for migration
  0012, backend before web). LATEST.md will conflict on merge — both 08-16 entries are real,
  keep both.
- **Still open, still authorized-pending: §5.4** — `auth_token_store.dart:51-53/:68-70/:79`
  converts a transient storage READ error into a permanent local logout (`_tokens.clear()`).
  This is the remaining manufactured-logout path; the guard does not fix it.
- Field expectations: user 54's next wipe now produces a banner + a `BOOT_MARKERS` triple that
  finally answers §10.3 (whole bucket vs localStorage-only). A Safari PWA can take ~14 h to
  pick up 0.1.10; he must fully close + reopen the PWA — never reinstall.
