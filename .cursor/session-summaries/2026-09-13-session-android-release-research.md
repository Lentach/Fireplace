# Android release: runbook corrected, 0.2.41 smoke-driven, issue #175 found AND fixed in 0.2.42

**Date:** 2026-09-13 · **Version:** 0.2.41 → **0.2.42** · **Tiers deployed:** none (APK only)

## What was done
- `docs/runbooks/android-release.md` user wording retired the pre-multi-device "create a new
  account / one-account-one-device" text for the link ceremony; corrected again after the live run
  (see Verification). `build-android.ps1:152-153` printed the same retired guidance — fixed.
- Built the release APK from `master@3122cc1`: 0.2.41, versionCode 20041, 105.2 MB, SHA256
  `9fdc7ef1…`, signer cert SHA-256 **matches the recorded keystore-backup fingerprint**, 16KB 16/16.
- Measured the merged manifest (`:app:processReleaseManifest`, no keystore): exactly 9
  `uses-permission`; `BIND_JOB_SERVICE` is an attribute, not a request; no `READ_MEDIA_*`.
- Found the Play FGS gate: `light_compressor_v2` merges `CompressionForegroundService`
  (`dataSync`) + 2 permissions, but `video_transcode_io.dart:37-56` passes no `BackgroundConfig`,
  so it can never start — Play would demand a demo video for dead code. Strip option recorded.
- Recorded the APK size anatomy (100.3 of 105.2 MB is 3 ABIs) and ranked the size levers;
  `useUnbundled` for ML Kit evaluated and deliberately NOT applied.
- Drove the full smoke on the release APK (emulator + real prod + a real browser peer).
- **Fixed issue #175 in TWO commits** — `23be77d`: `DeviceLinkGateRouteGuard` (new,
  `utils/device_link_route_guard.dart`) removes page routes pushed while the gate is up (dialogs
  and the ceremony's scanner, `kLinkScanRouteName`, are kept) + a once-per-process latch on the
  local-notification launch intent. `fa97358`: the SAME latch for
  `FirebaseMessaging.getInitialMessage()`, whose stickiness is identical — the FCM-tap arm was
  still open when the issue was first closed. 3 new tests; suite 2112/14.
- **`633f4dd`: the wrong mental model the bug exposed, plus its second victim.** The doc comment
  claimed `PushService.initialize` "runs once per app run" — it runs once per LOGIN, which is why
  the sticky reads replayed. Corrected, and acted on: `onTokenRefresh` was re-listened every
  login and never cancelled (N logins ⇒ N live listeners re-registering the token), now held in
  `_tokenRefreshSubscription` and cancelled before re-listen and on unregister. Both dead
  `@visibleForTesting` latch-reset hooks deleted (no host caller can reach either path; they also
  raised fatal `unused_shown_name` warnings).
- Root `CLAUDE.md`: the "format only the lines you edited" clause is GONE (owner's call); the
  whole-tree-formatter ban is KEPT as its own bullet with the evidence for why.

## Key files
- Edited: `docs/runbooks/android-release.md`, `build-android.ps1`, `docs/agents/traps.md`,
  `frontend/lib/main.dart`, `frontend/lib/screens/link_{scan,this_device,device}_screen.dart`,
  `frontend/lib/services/android_fcm_local_notifications.dart`, `frontend/pubspec.yaml`,
  `CLAUDE.md` (test count), `scripts/dart-lint-baseline.json`.
- New: `frontend/lib/utils/device_link_route_guard.dart`,
  `frontend/test/main/auth_gate_link_gate_stays_on_top_test.dart`.
- Read only (load-bearing): `docs/design/multi-device.md` §1/§5.1/§8/§9, `main.dart:255-292`,
  `device_link_gate_screen.dart`, `link_crypto.dart:379-431`, `devices_screen.dart:425-426`,
  `encryption_provider.dart:2116,1523`, `backend/src/auth/auth.service.ts:158`.

## Verification
- Prod: `/version` `0.2.41/49c77c10`, `/version.json` `0.2.41/9d13d25`;
  `git merge-base --is-ancestor 2c553b2 <both>` PASSES → multi-device IS deployed.
- `gh release list` EMPTY → no APK ever published → the Play App Signing cert choice is still free.
- `/privacy` and `/.well-known/assetlinks.json` return 200 with the **SPA shell**; neither exists.
- **Smoke on 0.2.41, Pixel_7 AVD, prod backend** (driven via `uiautomator` + `adb input`;
  `FLAG_SECURE` blocks `screencap`): item 1 PASS (`apkeae3#4259` registered, phrase offered +
  confirmed), item 2 PASS (PreKey APK→web, whisper web→APK, both decrypted), item 3 PASS
  (`am kill` → FCM notification in <5 s → **tap cold-started into the RIGHT chat**, the leg open
  since 2026-09-02), item 6 PASS (enroll → SAS `334 092` identical → approve → `android · #2` →
  gate closed → **self-sync phone→primary proven**; the primary kept decrypting its own history).
  Items 4, 5, 7 NOT RUN.
- Cold start after `am kill` rendered previously-decrypted plaintext ⇒ SQLCipher + Keystore
  content keys work on a real device.
- NOT verified: physical phone (emulator only), voice/image, delete-for-everyone, the un-enrolled
  flip-flop drill, iOS, Play Console (nothing touched).
- **Fix verification (0.2.42, versionCode 20042, `pm clear` install, prod):** 3 new tests green
  and the sweep test is RED without the observer; full suite **2112 pass / 14 skip**; ratchet
  3175 → 3174 (floor lowered). On device: push wakes a killed app in <5 s, then the SAME
  notification-tap → logout → login-as-enrolled sequence lands on the link gate with no chat over
  it, and the gate's own scanner opens and stays for 18+ s. Issue #175 closed.
- **CI 6/6 green on `633f4dd`** (`gh api …/commits/633f4dd/check-runs`). Note `fa97358`'s Flutter
  and wire jobs read `cancelled` — superseded by a later push via the concurrency group, not a
  failure; and a `.cursor/**`+`docs/**`-only tip runs ONLY CodeQL `Analyze` because of
  `paths-ignore`, so always check the code commit.
- **Shippable artifact: 0.2.42 / versionCode 20042 / `633f4dd` / SHA256 `7818786948ca79e11674a48e4999cc291bd749ba061361a9197efca200085bf0`.**
  Installed, launched, footer reads `633f4dd`. Two earlier 0.2.42 builds are recorded as
  NOT-shippable: `601248e0…` (uncommitted tree — footer names a fix-less commit) and
  `7c8bb2ce…` (predates the listener fix). The device drill was run on `601248e0…` and is still
  OWED on `7818786…`; it needs two fresh throwaway accounts.

## Notes for next session
- **Issue #175 FIXED (`23be77d`) — do not re-simplify.** The guard must stay a NavigatorObserver:
  a route push never rebuilds `AuthGate`, so any build-time `popUntil` (edge-triggered or not)
  cannot see it. Dialogs and `kLinkScanRouteName` are deliberate carve-outs.
- **OPEN, needs a look:** after `pm clear` re-minted `apkeae3`'s identity, messages the web sent
  AFTERWARDS (02:38, 02:44) still rendered `[Decryption failed]` on the phone, even though the
  web had shown the "nowe urządzenie — klucze zaktualizowane" note. Expected a fresh PreKey
  session. Not investigated; "Clear storage" / reinstall is a real user action, so this matters.
- Owner-owed, unchanged: Play vs sideload-forever; Play Console account status; report-user UX;
  who writes privacy policy + ToS; R8 for libsignal/drift/Firebase.
- **Never let Play generate the app signing key** — PEPK-transfer this `.jks` instead, or every
  sideloaded friend is stranded (uninstall = identity + history loss).
- Before any friends build: linking cannot be enabled from a browser TAB (must be an installed
  PWA), the match code is 6 digits, and the ceremony is symmetric — the shipped wording now says so.
- Test fixtures on prod: `apkeae3#4259` / `webb2e6#6353` were throwaway smoke accounts sharing one
  password (`<REDACTED>` — it WAS committed in `f35ef7b` on this PUBLIC repo). Both accounts were
  DELETED at session end and the exposed password now returns `401 Invalid credentials` on
  `POST /auth/login` for both identifiers. **Never put a working credential in a summary.**
  `test_web_sender#7207` was logged OUT of the dev browser (password unknown, keys still in that
  profile's localStorage).
