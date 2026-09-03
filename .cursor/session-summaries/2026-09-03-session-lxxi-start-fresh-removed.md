# 2026-09-03 (later) — (lxxi): "Zacznij od nowa" removed, never-published residue discarded by the server's word; 0.2.1 DEPLOYED (web-only, carries (lxix)+(lxx) too)

**Date:** 2026-09-03 (afternoon session; picks up the morning's `HANDOFF.md` batch, item A)

## What was done

**Owner decisions taken at session start (asked, not assumed):** A = "delete + auto-fresh on
partial+no-bundle"; deploy (lxix)+(lxx) *after* A as 0.2.1; keep the `OWN_DEVICE_LIST_UNVERIFIED`
diag (owner: "keep but I've no clue what it does" — explained: one forensic line in the hacker-mode
log when the primary cannot verify its own signed list; nothing user-visible); the §3 thief matrix
comes AFTER A and BEFORE B.

**Proof that drove the shape (all from source, `fireplace-0a` @ `bbea48e`):**
- `identityIncomplete` — the banner's only trigger — was set in exactly two places in
  `EncryptionService.initialize`: absent + server `true` (`:937`, enrolled by definition) and
  `partial`/residue (`:963`, NO server check). A fresh account (server `false`) went straight to
  `_generateKeys()` and never saw the banner. So "never-enrolled keeps the plain start" was
  already true without the button; the only non-enrolled shape that could reach it was
  *partial + upload never landed*.
- The hole: `_runIdentityRecovery` (`encryption_provider.dart:1473-1475,1501`) set
  `_e2eInitialized = true` and fired `onE2EReady` BEFORE the `uploadKeyBundle` the registration
  lock refuses. Deleting the path closes it without the deeper "flip on ack" change.
- Why an explicit server `false` may authorize a mint: `handleCheckOwnKeyBundle` answers PER DEVICE
  (`hasKeyBundle(userId, deviceId)`), and a password login resolves to the LIVE PRIMARY
  (`resolveLoginDeviceId`, (xxii)). The primary's bundle is absent only if never published or if a
  completed §6.2 reset awaits its spending upload — minting is the designed outcome in both. A
  revoked device's purged bundle can never produce `false` (a login never resolves to a revoked id).

**Built (spec §12 amendment (lxxi), D23, then code):**
- `IdentityDamagedBanner`: link only. Confirm dialog, `recoverFromIncompleteIdentity`,
  `_runIdentityRecovery`, `identityRecoveryInFlight`, `regenerateIdentityAfterConfirmedLoss`, five
  ARB strings (`identityDamagedAction/ConfirmTitle/ConfirmBody/ConfirmAction/RecoveryFailed`) deleted;
  `identityDamagedBody` re-worded en+pl (no longer says "start fresh"). `flutter gen-l10n` re-run.
- `EncryptionService.initialize`: every non-`loaded` outcome — absent, absent+residue, partial —
  consults `checkServerBundleExists`. `true` → `E2eIdentityIncompleteException` (diag
  `IDENTITY_INCOMPLETE` when residue was found, else `IDENTITY_GUARD_SERVER_BUNDLE_EXISTS`);
  UNKNOWN → `E2eIdentityCheckUnavailableException` (deferred, as the empty-store case always was);
  explicit `false` → `_wipeSignalMaterial` + peer-warning/rebuild-intent clear +
  `IDENTITY_RESIDUE_DISCARDED {userId}` + `_generateKeys()`. Behaviour change worth knowing: a
  damaged-identity install now needs ONE server round trip before the banner (its only action needs
  the server anyway); previously `partial` raised the banner offline.
- Dead `test_e2e/recovered_identity_probe_test.dart` (`RECOVERED_USER_ID`, skip-by-default) removed
  — it probed the deleted path. e2e count 44/3 → 43/2.

**Tests re-pinned to the server-decided contract:**
- `encryption_identity_guard_test.dart`: the four "partial loss" cases now assert refusal against
  server `true` (and that residue is left alone); new "partial + UNKNOWN defers"; the old "consented
  recovery" group became "residue on a NEVER-enrolled account is discarded" (+ "discard never runs
  on a bundle-exists answer").
- `encryption_service_sig_hardening_test.dart`: R1 (enumeration FAILING) refuses against server
  `true` with `IDENTITY_RESIDUE_UNKNOWN` ×1 and zero writes; NEW: enumeration failing + server
  `false` mints (the failed scan only means the best-effort discard removes nothing); residue+`true`
  refuses and leaves rows; residue+`false` discards + mints with the diag.
- `identity_banners_test.dart`: two start-fresh tests replaced by "no destructive action exists,
  collapsed or expanded" (exactly one `TextButton`, the link; copy contains no "start fresh").

**Falsification (mutant PRINTED, substitution count asserted =1 each, restored sha-exact):**
`if (residue)` → `if (false)` → RED on "residue wiped, new identity minted" (`:317`);
`serverBundleExists == true && !residue` + `!= false && !residue` (residue bypasses the server) →
RED on "discard never runs on a bundle-exists answer" (`:349`).

**Live on a rebuilt release bundle (local stack, 8093):**
- 697 `mdqa0903a` in a FRESH context (enrolled, keyless): red banner, "Połącz to urządzenie" only;
  disclosure shows the new copy and NO "Zacznij od nowa".
- NEW user 699 `mdqa0903r` registered via REST only (never connected → never enrolled); seeded
  `flutter.sig_e2e_699_session_1_1` + `next_pre_key_id` in localStorage (values must be
  JSON-encoded — a raw string breaks `SharedPreferencesAsync.getAll()` and the sealed store refuses
  with `SIG_KEY_UNAVAILABLE {stage: probe}`; first attempt hit exactly that); UI login → diag
  `IDENTITY_RESIDUE_DISCARDED {userId: 699}`, residue row gone, identity minted, `key_bundles` row
  `699|1` on the server, no banner.

**Docs:** spec §12 (lxxi); `frontend/CLAUDE.md` §5 identity rule rewritten (it ALSO claimed the
residue probe "biases toward the FRESH INSTALL when readAll fails" — wrong since B2b R1; it fails
closed as residue-present); runbook `e2e-decryption-failed.md` step 3E rewritten (was pointing at
the deleted action and misdescribing `IDENTITY_RESIDUE_UNKNOWN`); `web-sig-sealing.md` method name.

**Shipped:** master `a9b477f` (CI `33708540388` 5/5 SUCCESS). `deploy-web.ps1` from the worktree →
`PUBLISHED_OK`, `/version.json` 0.2.1; its smoke gate cannot run there (no `scripts/smoke/node_modules`)
so `post-deploy-smoke.mjs --commit a9b477f` ran from the main checkout: **SMOKE PASSED 5/5**
(bundle contains `a9b477f`). Backend untouched `0.2.0/5ffef19b` — correct, frontend-only.
**Owner: close + reopen the PWA once.**

## Key files

`frontend/lib/services/encryption_service.dart` (initialize; regenerate method deleted),
`frontend/lib/providers/encryption_provider.dart` (recover path deleted),
`frontend/lib/widgets/identity_damaged_banner.dart`, `frontend/lib/l10n/app_{en,pl}.arb` (+3 generated),
`frontend/test/services/encryption_identity_guard_test.dart`,
`frontend/test/services/encryption_service_sig_hardening_test.dart`,
`frontend/test/widgets/identity_banners_test.dart`, `frontend/test_e2e/recovered_identity_probe_test.dart` (D),
`docs/design/multi-device.md` §12 (lxxi), `docs/runbooks/e2e-decryption-failed.md`,
`docs/design/web-sig-sealing.md`, `frontend/CLAUDE.md` §5, `CLAUDE.md` §3 counts, `frontend/pubspec.yaml` 0.2.1.

## Verification

analyze clean; targeted files green; full suite **1718/10sk** (was 1715: banner −1, guard +2,
sig-hardening +2), `verify-claude-frontend-test-counts.mjs --log` OK; two mutants red; CI 5/5;
live two-account check on the rebuilt bundle; prod smoke 5/5 at `a9b477f`.

## Notes for next session

- Drift from the morning handoff: the owner's main checkout is on **`feat/passcode-lock`** (dirty,
  passcode-lock feature in progress), not `feat/video-messages`. Still: never touch its tree.
  `scripts/smoke/node_modules` exists only there.
- Next in the ratified order: **§3 thief matrix** (bring the actor × capability table; #4 hostile
  password change = account gone deserves a rule before B), then B composer gate → C reset door →
  D collapse placeholders → E rename → F.
- C should now extend THIS banner's disclosure (the reset door) — (lxxi) already names it as
  "the next amendment".
- Local throwaway accounts on the dev DB: 697 (P #1 / N #5), 699 (fresh, enrolled by this session's
  live check).
- Trap added to the recipe: seeding localStorage for the web sig store needs `JSON.stringify`
  values; keys live under `flutter.sig_e2e_<uid>_…` before the sealed drain, bare `sig_…` after.
