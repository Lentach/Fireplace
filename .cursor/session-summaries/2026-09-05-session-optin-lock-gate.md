# (lxxiii)+(lxxiv): opt-in registration lock, full-screen link gate, web-primary install rule — 0.2.4

**Date:** 2026-09-05 (night, after the 0.2.3 video release)

## What was done

Owner ratified three yes/no questions (opt-in lock YES, web-primary install rule YES, "QR as login"
DROPPED), then "build all three… it must work 100%, ship today". Spec amendments (lxxiii)/(lxxiv)
written to `docs/design/multi-device.md` §12 (line ~2457) and §8 rewritten BEFORE code, shown to
the owner in plain words, then implemented by three parallel slices (backend / gate / web-install)
with mutants F1–F10 printed, counted, restored.

1. **Registration lock is OPT-IN — enabling linking arms it.** `IdentityLockedError` is thrown at
   BOTH refusal sites (`upsertKeyBundle`, `uploadOneTimePreKeys`) only when `account_authorizations`
   has a row (`KeyBundlesService.isEnrolled`). Un-enrolled replacement is admitted as
   `authorizedBy = 'unlocked'`, logged `[identity-churn] … via=unlocked`, and rides the SAME audit
   row + §6.0 alarm fan-out (both keyed on `identityChanged`, verified — nothing widened); the §6.2
   roster teardown stays keyed on `'reset'`. `ownKeyBundleStatus` gains additive `linkingEnabled`.
2. **Client guard is a pair.** `EncryptionService.initialize(checkServerIdentity)` →
   `ServerIdentityGuard {exists, linkingEnabled}`; absent field ⇒ `true` (fail-closed to the old
   gate). `exists && !linkingEnabled` ⇒ proven residue discard + mint, diag
   `IDENTITY_GUARD_UNLOCKED_REMINT`. UNKNOWN now has a flag, `identityCheckUnavailable` (NOT cleared
   on disconnect — an offline keyless install must never fall back to a keyless shell) and
   `retryE2EInit()`.
3. **`DeviceLinkGateScreen`** mounted by `AuthGate` above an `Offstage` `MainShell` while
   `needsDeviceLink || identityCheckUnavailable`. Four provider-driven states: link (inline
   `LinkThisDeviceBody`, extracted from `LinkThisDeviceScreen`), reset-pending (countdown + Anuluj,
   link still below, start-reset hidden), unknown (spinner + retry), stale (link + disposal note).
   Footer: reset door + Wyloguj. A gate arming while a route is pushed pops to root ((lxvi)-style).
   `IdentityDamagedBanner` + `DeviceMismatchBanner` DELETED; `IdentityResetPendingBanner` keeps only
   the countdown branch (for the account's other sessions). Devices screen's keyless branch removed.
4. **Link approval wipes never-published residue** (`adoptProvisionedIdentity`: residue =
   held identity OR `_hasPriorInstallResidue`; unproven ⇒ `LINK_RESIDUE_DISPOSAL_DEFERRED`, ceremony
   aborts `adopt_failed`, gate stays).
5. **Web primary must be installed** (`utils/web_display_mode*.dart`: `display-mode: standalone` OR
   `navigator.standalone`, never `persisted()`). Plain tab ⇒ install-first text instead of the
   button; installed ⇒ warning dialog ⇒ `enableLinking` ⇒ `RecoveryKeyScreen` pushed; enrolled
   non-installed web primary ⇒ one-line install nudge.

## Key files

`backend/src/key-bundles/key-bundles.service.ts` (+spec), `backend/src/chat/services/chat-key-exchange.service.ts` (+spec),
`frontend/lib/services/encryption_service.dart`, `frontend/lib/providers/encryption_provider.dart`,
`frontend/lib/main.dart`, `frontend/lib/screens/device_link_gate_screen.dart` (new),
`frontend/lib/screens/link_this_device_screen.dart`, `frontend/lib/screens/devices_screen.dart`,
`frontend/lib/screens/main_shell.dart`, `frontend/lib/widgets/identity_reset_pending_banner.dart`,
`frontend/lib/utils/web_display_mode{,_web,_stub}.dart` (new), `frontend/lib/l10n/app_{pl,en}.arb`,
`docs/design/multi-device.md` §8 + §12 (lxxiii)/(lxxiv), `frontend/CLAUDE.md` §5, root `CLAUDE.md` §3 counts.
Tests new: `test/screens/device_link_gate_screen_test.dart`, `test/screens/devices_screen_web_install_test.dart`,
`test/services/encryption_service_identity_guard_test.dart`. Deleted: `test/widgets/device_mismatch_banner_test.dart`.

## Verification

- Backend `npm test` 1063/62 green; lint-ratchet PASS; count verifier OK. Flutter suite green (see
  LATEST for the post-rebase count), analyze clean, count verifier OK.
- **Live on the rebuilt local bundle (`fpweb4` :8093, worktree compose stack):**
  - un-enrolled 699, fresh keyless context → login → shell opens, 29 `sig_` keys, diag
    `IDENTITY_GUARD_UNLOCKED_REMINT {userId: 699}`, server `[identity-churn] userId=699 … via=unlocked`;
  - enrolled 697, fresh keyless context → GATE (QR + code + reset door + Wyloguj), diag
    `IDENTITY_GUARD_SERVER_BUNDLE_EXISTS`; Rozpocznij reset → phrase prompt → "Nie mam go" →
    reset-pending state (71 h countdown, Anuluj, link still below, start-reset hidden; OOB code
    byte-identical ⇒ the ceremony survived the state switch) → Anuluj → link state → Wyloguj → AuthScreen;
  - NEW account 700 (`mdqa0905p` / `MdQa!20260905`): plain tab ⇒ install-first text; standalone
    (main-world `matchMedia` override via CDP new-document script) ⇒ Włącz łączenie → dialog → Włącz
    → `sig_dak_record_v1_700` + `RecoveryKeyScreen`; fresh keyless context N → gate → QR decoded with
    jsQR (`/link#fp-link.v1…`) → P opened the deep link → SAS `613 779` on both → Zatwierdź →
    `LINK_IDENTITY_ADOPTED`, N left the gate into the shell (30 keys), P lists `#1 główne` + `#2`;
    clean P page (no override) ⇒ install nudge above "Połącz urządzenie".
- Prod: see LATEST for deploy state.

## Notes for next session

- ⚠️ **Puppeteer `page.evaluate` in this harness runs in an ISOLATED world**: a `window.matchMedia`
  override set there is invisible to the Dart app, and a CDP `Page.addScriptToEvaluateOnNewDocument`
  override (main world) is invisible to `page.evaluate` probes AND persists across `goto`. I burned
  20 minutes "proving" the install nudge was broken; it was my own override still answering
  "installed". Open a NEW page in the context to shed it.
- The `linkGateResetPendingBody` copy first claimed linking cancels a reset — FALSE (server
  `cancelReset` is reachable only via `resetIdentityCancel`). Fixed to "cancel first". A real
  auto-cancel on successful link would be a small follow-up (emit cancel in `_onLinked` when a
  deadline is set — check the no-pending answer shape first).
- Un-enrolled accounts are password-only takeover-able (loud). Owner accepted; the cure is one tap.
- (lxxi) spec text still names `checkServerBundleExists` — historical, left as written.
- Local: compose stack in the worktree (`docker compose up -d --force-recreate` after `ENOTFOUND db`);
  the main checkout's `fireplace-*` containers were stopped to free :3000/:5433. Static hub `fpweb4`.
