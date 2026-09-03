# Passcode Lock (Zangi-inspired app-level gate) — built TDD on `feat/passcode-lock`, live-verified in the PWA

**Date:** 2026-09-03

## What was done

Owner asked for Zangi's Passcode Lock: a padlock on the Chats header next to `+`, a
4-digit / 6-digit / custom-alphanumeric setup flow, and an app-wide lock. Research first
(owner rule: prove, then ask), five decisions taken by the owner, then implementation.

**Research (`.planning/passcode-lock/findings.md`)**

- Zangi's own FAQ (`zangi.com/faq/20`) splits the feature: **Passcode Lock is free**; *Wipe
  Passcode* (decoy code erases local data) and *Hide Conversation PIN* are **Premium**. Their
  "forget it and you lose the account" copy exists because Zangi has no accounts/password.
- Telegram re-keys its local SQLCipher DB from the passcode (PBKDF2, ~260–320k iters), i.e. real
  at-rest crypto; auto-lock 1 min–45 h, default 1 h; device-local, never synced.
- **PWA capability matrix:** custom passcode UI + PBKDF2/AES-GCM via `crypto.subtle` → yes;
  `local_auth` biometrics → **no web implementation at all**; hardware-throttled brute force and
  `FLAG_SECURE`-style screenshot blocking → impossible on web, already shipping on Android.
- Recovery lever Zangi cannot offer: `AuthProvider.login(identifier, password)` exists and root
  `CLAUDE.md` §6 says Signal keys survive logout ⇒ **forgetting the passcode can cost a logout and
  nothing else.**

**Owner decisions (2026-09-03)**: Tier A gate now / key-wrapping later as opt-in; forgot = forced
logout + re-login (lossless); all three code shapes; auto-lock configurable, default 1 minute; no
biometrics, no wipe passcode, no hidden chats. Header padlock in scope.

**Implementation (TDD, red proven before every green; seams confirmed with the owner first)**

- `lib/utils/passcode_autolock.dart` — pure `shouldLockOnForeground` + `passcodeBackoffFor`
  (5 free attempts → 30 s/1 m/5 m/15 m). Fail-closed on a null stamp or a backwards clock.
- `lib/services/passcode_kdf.dart` — `PasscodeKdf` seam + `Pbkdf2PasscodeKdf` (PBKDF2-HMAC-SHA256,
  600k iters via `webcrypto`), salt from `Random.secure()` so enabling never needs the native lib,
  `constantTimeBytesEqual`.
- `lib/services/passcode_store.dart` — `PasscodeMode`, immutable `PasscodeRecord`, `PasscodeStore`
  seam, `DevicePasscodeStore` mirroring `AuthTokenStore`'s dual backend (secure storage on real
  Android only; prefs on web because `flutter_secure_storage_web` keeps its master key in the same
  localStorage). A partial credential reads as DISABLED.
- `lib/providers/passcode_provider.dart` — 8th top-level provider. `unknown/disabled/unlocked/locked`,
  `enable/disable/change/unlock/verifyCurrent/lockNow/noteBackgrounded/evaluateOnForeground/clearForRecovery`.
- `lib/widgets/passcode_entry_view.dart` — the app's own hex keypad (pointy-top hexes, phone-keypad
  letters, hex dots), auto-submit at the last digit, alphanumeric mode uses a real field + submit.
- `lib/widgets/passcode_gate.dart` + `lib/screens/passcode_unlock_screen.dart` — barrier in
  `MaterialApp.builder`, `Offstage` (not unmount) so the socket/chat state survive a lock.
- `lib/screens/passcode_lock_screen.dart` — intro vs management faces, "Passcode Options" glass
  sheet, auto-lock chooser, change/disable gated on the current code.
- Wiring: `main.dart` (provider + gate), `main_shell.dart` (lifecycle + web visibility),
  Chats header padlock, Settings SECURITY row, 37 ARB keys in both arbs, `flutter gen-l10n`.
- Version left at `0.1.24`: root §5 scopes the PATCH bump to production releases, and prod already
  serves 0.1.24 off `feat/video-messages` — two branches must not claim the same number. Whoever
  releases this bumps it then.

## Key files

- New: `frontend/lib/utils/passcode_autolock.dart`, `frontend/lib/services/passcode_kdf.dart`,
  `frontend/lib/services/passcode_store.dart`, `frontend/lib/providers/passcode_provider.dart`,
  `frontend/lib/widgets/passcode_entry_view.dart`, `frontend/lib/widgets/passcode_gate.dart`,
  `frontend/lib/screens/passcode_unlock_screen.dart`, `frontend/lib/screens/passcode_lock_screen.dart`,
  `frontend/test/support/passcode_fakes.dart` + 6 test files.
- Edited: `frontend/lib/main.dart`, `frontend/lib/screens/main_shell.dart`,
  `frontend/lib/screens/conversations_screen.dart`, `frontend/lib/screens/settings_screen.dart`,
  `frontend/lib/l10n/app_pl.arb` + `app_en.arb`, `frontend/CLAUDE.md` (§2 + new §10), root `CLAUDE.md` §3 counts.
- Test harnesses that now need a `PasscodeProvider` or a prefs mock: `test/widget_test.dart`,
  `test/main/*`, `test/screens/settings_console_test.dart`,
  `test/screens/settings_screen_scroll_physics_test.dart`,
  `test/screens/settings_screen_version_footer_test.dart`,
  `test/screens/conversations_honeycomb_picker_test.dart`.

## Verification

- `flutter analyze --no-fatal-infos lib test` → **No issues found**.
- `flutter test` → **1436 passed / 14 skipped**; `node scripts/verify-claude-frontend-test-counts.mjs`
  → OK (root §3 updated). The 4 new skips are the real-PBKDF2 tests (host has no native webcrypto —
  confirmed by the skip count, and the published PBKDF2-SHA256 vector among them; the real primitive
  was instead exercised live in the browser, see below).
- **Live PWA run** (`flutter run -d web-server :8099` against the dev backend on :3000, driven with
  the browser tool, throwaway account `passcodeqa` in the fireplace-0a dev DB): header padlock left
  of `+` → intro → Options sheet → 4-digit set → repeat → management screen ("Włączona · Po 1
  minucie") → padlock locks the app → wrong code shows the error and stays locked → right code
  returns to Chats. **This exercised the real browser WebCrypto PBKDF2 path that host tests skip.**
- **Auto-lock proven across a cold boot:** aged `flutter.passcode_last_active_at` by 10 min, hard
  reload → lock screen; a reload 9 s after backgrounding stayed unlocked (the 1-minute policy).
  Screens captured light + dark (`.planning/passcode-lock/shots/`).
- While locked, the app vanishes from the accessibility tree (Offstage), and a widget test proves
  guarded subtree STATE survives a lock/unlock cycle.

## Late correction (post-commit, advisory-driven)

`PasscodeStore` originally resolved "enabled flag set but salt/verifier missing" to DISABLED
(fail-open). That is the error-as-absence inversion `AuthTokenStore` was hardened against: a wiped
or tampered Keystore entry would silently UNLOCK the app. Now `PasscodeRecord.credentialDamaged`
carries that case and the gate fails **CLOSED** (`PASSCODE_CREDENTIAL_DAMAGED`; every entry answers
`unavailable`, the recovery door is the way through). The opposite polarity is kept — and now
documented — for an unreadable/hanging store: with no readable FLAG we cannot invent a lock for a
user who may never have set one, so that stays "no passcode" (`PASSCODE_STORE_UNREADABLE`). Follow-up in the same review round: on Android a Keystore fault THROWS rather than returning null,
and that throw escaped `load()` into branch (a) — so the flag is now read FIRST from prefs and
`_readSecrets` retries the whole triple (150/400 ms, `AuthTokenStore`'s cadence and reasoning)
before reporting nulls with `PASSCODE_SECRET_UNREADABLE`. A transient hiccup therefore cannot read
as damage, and a persistent fault cannot read as absence. Eleven new tests pin both polarities, retry recovery, and the budget
ordering: the retry budget (`DevicePasscodeStore.secretReadBudget`, 1.05 s worst case with a 250 ms
per-attempt timeout) MUST stay below the provider's `kPasscodeStoreReadTimeout` (raised 1.5 s →
2.5 s), or the outer timeout fires first, the provider takes the no-readable-flag branch, and a
flagged-but-slow store unlocks — an assertion now guards that ordering.

## Notes for next session

- **Not deployed.** Branch `feat/passcode-lock` off `1f9d96f` (= `feat/video-messages`, what prod
  serves). Master is still behind prod; do not merge without the owner.
- **Not device-verified on Android.** The APK path (Keystore-backed verifier + `FLAG_SECURE`) was
  not exercised this session; `integration_test/` is the place for a real-Keystore acceptance run.
- Three defects were found by the work's own tests/screens and fixed: the entry column overflowed a
  600 px viewport (recovery button off-screen), a hanging `SharedPreferences` read held the gate on
  `unknown` forever (now bounded 1.5 s + `PASSCODE_STORE_UNREADABLE`), and the keypad announced
  "1 1" to screen readers.
- Tier B (passcode-derived key wrapping, web-first, opt-in) is designed but deliberately unbuilt —
  rationale and the data-loss tradeoff are in `.planning/passcode-lock/findings.md` and §10.
