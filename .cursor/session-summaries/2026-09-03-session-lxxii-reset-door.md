# 2026-09-03 (evening) — (lxxii) reset door on the keyless banner; QR/deep-link re-verified first-hand; 0.2.2 DEPLOYED

**Date:** 2026-09-03 (evening; continues `2026-09-03-session-lxxi-start-fresh-removed.md`)

## What was done

**Owner questions answered:**
- "Is QR working? Did you test it?" — honest answer: not by this session until asked. Then tested
  on the LOCAL rebuilt bundle with the surviving browser contexts (they outlive the harness; the
  primary is the context holding `sig_dak_record_v1_697`): new keyless device showed the QR → jsQR
  decode of the screenshot pixels = `http://127.0.0.1:8093/link#fp-link.v1.…` (code in the fragment)
  → deep link cold-opened on the primary → SAS `853 145` on both in 12 s ((lxx) clause 3 wait held)
  → one Approve → both popped to Devices ((lxx) clause 2), new device = **web · #6** with identity +
  `material_device "6"`, banner gone. Trap hit once: `deploy-web.ps1` overwrites
  `frontend/build/web` with the PROD bundle, so 8093 served a prod-pointing app (CORS + wss 400) —
  rebuild locally before any 8093 check.
- "What can a user do with a 'disabled' app?" — only E2E is down. Keyless: chat/contact lists,
  profile edits, add/block/delete contacts, delete conversations (server rows), settings, push,
  start the reset. Cannot: read history, send, self-link, revoke.
- Batch decisions: C agreed (done here) → thief matrix (delivered as a table + 3 questions, owner
  to answer) → B yes → D agreed → E yes → F explained, not started.

**(lxxi) riders (both on master before C, not separately deployed):** `caf8bbc` — the residue
discard is proven, never attempted blind: `_wipeSignalMaterial` now returns whether the wipe is
complete; `6c784c4` — a seen-but-surviving row (delete threw) also defers. Both →
`IDENTITY_RESIDUE_DISCARD_DEFERRED` + `E2eIdentityCheckUnavailableException`. Two new tests, two
mutants red.

**(lxxii) — C, the reset door.** The ordering hazard of (lxxi): the refused "start fresh" was the
only route from a plain keyless install to the §6.2 reset (`IdentityResetPendingBanner` renders
its "Start reset" only under `identityUploadLocked`). 0.2.1 shipped with that gap open.
`IdentityDamagedBanner` now carries `identityResetStartAction` as its disclosure secondary action
via `startIdentityResetFlow` (phrase asked first, same flow as the lock-refused banner), hidden
while `identityResetDeadline != null`; body closes with the 72 h / 1 h / other devices signed out /
undecrypted ciphertext gone sentence (en+pl). Reset itself unchanged.

**Falsified:** `secondaryAction: true` → "reset door lives in the disclosure" red;
`secondaryAction: false` → "hides while a ceremony is already running" red. ⚠️ The first mutant
runner crashed mid-flight with the mutant ON DISK (advisory caught it); the re-run restored first
and wrapped in try/finally — verify `git diff` after any mutation script.

**Live on the rebuilt local bundle:** fresh keyless 697 login → banner disclosure shows the door →
tap → "Masz klucz odzyskiwania?" prompt → "Nie mam go" → 71 h pending banner on the keyless device
AND on the primary; door hidden on the keyless banner → primary "Anuluj" →
`identity_reset_requests` row `cancelled` → door back.

**Shipped:** master `b73b7cd` (CI `33712100252` 5/5), `deploy-web.ps1` → `PUBLISHED_OK`, smoke from
the main checkout **5/5** at `b73b7cd`. **Prod frontend 0.2.2 / b73b7cd; backend untouched
0.2.0/5ffef19b.** Owner: close + reopen the PWA.

## Key files

`frontend/lib/widgets/identity_damaged_banner.dart`, `frontend/lib/l10n/app_{en,pl}.arb` (+generated),
`frontend/lib/services/encryption_service.dart` (riders), `frontend/test/widgets/identity_banners_test.dart`,
`frontend/test/services/encryption_service_sig_hardening_test.dart`, `docs/design/multi-device.md`
§12 (lxxi) riders + (lxxii), `frontend/CLAUDE.md` §5, `CLAUDE.md` §3 count, `frontend/pubspec.yaml` 0.2.2.

## Verification

analyze clean; suite **1721/10sk** + verifier OK; 4 mutants red (2 riders, 2 for C); CI 5/5 ×3
(`caf8bbc`, `6c784c4`, `b73b7cd`); QR ceremony + reset round trip live; prod smoke 5/5.

## Notes for next session

- Owner owes answers to the thief matrix (Q1 keyless read-only?, Q2 notify on destructive actions,
  Q3 hostile password change: a primary-confirm / b delay+undo / c nothing; my pick b).
- Then B (composer gated on `needsDeviceLink`), D (collapse `none_for_device` rows), E (rename,
  backend), F (explained only).
- Local accounts on the dev DB: 697 now has #1 primary, #5, #6 (contexts BA0F / D7D3 / A659), one
  fresh keyless context (__C) — reset cancelled, cooldown may apply for a while; 699 fresh.
- Browser contexts survive the harness; `globalThis.__*` handles do not — find the primary by
  `sig_dak_record_v1_<uid>` in localStorage.
