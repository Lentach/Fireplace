# Android release: runbook was three-ways wrong, 0.2.41 APK built and smoke-driven, two defects found

**Date:** 2026-09-13 · **Version:** unchanged (0.2.41) · **Tiers deployed:** none

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

## Key files
- Edited: `docs/runbooks/android-release.md`, `build-android.ps1`, `docs/agents/traps.md`.
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

## Notes for next session
- **DEFECT 1 (user-visible):** the device-link gate is a `Stack` child (`main.dart:283-288`) and
  its `popUntil` defence is edge-triggered once (`:276-281`). A route pushed AFTER the verdict
  covers it — observed: a pending notification deep-link survived logout→login in the SAME process
  and pushed a chat over the gate, leaving a keyless `[encrypted]` shell with no hint. Back
  reveals the gate. Fix candidates: make the gate a route, or re-assert `popUntil` while gated.
- **DEFECT 2:** that pending deep-link was consumed by the NEXT account; only a shared
  conversation id made it look harmless. Cross-account pending state should be cleared on logout.
- Owner-owed, unchanged: Play vs sideload-forever; Play Console account status; report-user UX;
  who writes privacy policy + ToS; R8 for libsignal/drift/Firebase.
- **Never let Play generate the app signing key** — PEPK-transfer this `.jks` instead, or every
  sideloaded friend is stranded (uninstall = identity + history loss).
- Before any friends build: linking cannot be enabled from a browser TAB (must be an installed
  PWA), the match code is 6 digits, and the ceremony is symmetric — the shipped wording now says so.
- Test fixtures on prod: `apkeae3#4259` / `webb2e6#6353` (both `SmokeTest2609`, phrases in the
  transcript); `test_web_sender#7207` was logged OUT of the dev browser (password unknown, keys
  still in that profile's localStorage).
