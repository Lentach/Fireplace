# Android release: the runbook's distribution story was three-ways wrong; Play gates mapped, nothing built

**Date:** 2026-09-13 · **Version:** unchanged (0.2.41) · **Tiers deployed:** none

## What was done
- `docs/runbooks/android-release.md` "User wording" rewritten: multi-device IS live, so the
  "create a new account / one-account-one-device" text is retired for the link ceremony.
- Same section, ceremony DIRECTION corrected after a first wrong draft: the NEW device shows the
  QR, the PRIMARY scans and approves (`multi-device.md:182-188`). Desktop primaries with no camera
  get the typed/pasted code path (`link_this_device_screen.dart:18-19`).
- Un-enrolled accounts documented as the live hazard: `needsDeviceLink`
  (`encryption_provider.dart:2116`) is driven by `_identityIncomplete`, set only on a guard FAILURE
  (`:1523`) — a clean fresh install meets NO gate and silently re-mints into the primary slot.
- Smoke checklist: link ceremony added as item 6 (release build), the flip-flop drill demoted to
  item 7 as the hazard drill. The wording block is marked NOT device-proven pending item 6.
- Distribution bullets added: appbundle gates must move onto the BUNDLE output (`build-android.ps1`
  only inspects an APK), and the signing-cert one-way door while `gh release list` is still empty.
- Foreground-service gate recorded: `light_compressor_v2-1.9.1` merges `CompressionForegroundService`
  (`foregroundServiceType="dataSync"`) + 2 permissions, but `transcodeVideoToFit`
  (`video_transcode_io.dart:37-56`) passes no `BackgroundConfig`, so it can never start.
- Merged manifest MEASURED and the inferred list it replaced corrected (`BIND_JOB_SERVICE` is an
  `android:permission` attribute, not a requested permission).

## Key files
- Edited: `docs/runbooks/android-release.md` (commits `c1e537f`, `5fda105`, `584980f`).
- New: none.
- Read only (load-bearing): `docs/design/multi-device.md` §1/§5.1/§8/§9,
  `frontend/lib/screens/device_link_gate_screen.dart`, `link_this_device_screen.dart`,
  `frontend/lib/providers/encryption_provider.dart:2116,1523`,
  `backend/src/auth/auth.service.ts:158`, `frontend/lib/utils/video_transcode_io.dart`,
  `build-android.ps1`, `frontend/android/app/build.gradle.kts`.

## Verification
- Prod: `/version` → `0.2.41 / 49c77c10`, `/version.json` → `0.2.41 / 9d13d25`.
  `git merge-base --is-ancestor 2c553b2 <each>` PASSES (PR #144 multi-device is in both deployed
  commits) — that, not LATEST, is why the runbook was rewritten.
- `gh release list --repo Lentach/Fireplace` → EMPTY. No APK has ever been published, so the Play
  App Signing cert choice is still free.
- `curl https://fireplace.ignorelist.com/.well-known/assetlinks.json` and `/privacy` → HTTP 200 but
  the body is the Flutter SPA shell. Neither exists; App Links cannot verify.
- `cd frontend/android && cmd /c gradlew.bat :app:processReleaseManifest` (also works as
  `sh ./gradlew …`) → BUILD SUCCESSFUL, no keystore needed. Merged output
  `frontend/build/app/intermediates/merged_manifest/release/outputReleaseAppLinkSettings/AndroidManifest.xml`
  holds exactly 9 `uses-permission` entries and the dataSync service at line 237.
- grep: no report-user code, no terms/privacy ARB strings, no analytics/crash SDK in `pubspec.yaml`.
- NOT verified: no APK built, no device run, no link ceremony exercised, no Play Console touched.
  Nothing was deployed. External Play/verification dates are from vendor docs read this session,
  not from a console.

## Notes for next session
- **Owner-owed, blocking everything else:** (1) Play, or sideload forever? (2) Play Console account
  — exists, personal or organisation, created when? (decides 12 testers x 14 active days).
  (3) The un-enrolled re-mint hazard: mechanism, or keep betting on wording? (4) Report-user UX
  shape. (5) Who writes privacy policy + ToS. (6) R8 for libsignal/drift/Firebase (the transcoder
  is confirmed keep-rule-free by its README).
- Play blockers if the answer is Play: no privacy policy, no ToS/UGC acceptance, no in-app report
  (block exists), no web account-deletion URL, no AAB pipeline, FGS declaration (or strip it).
  Store screenshots cannot come from a release build — `FLAG_SECURE`.
- Dates that matter: developer verification enforces 2026-09-30 in BR/ID/SG/TH via participating
  stores only (direct sideload unaffected this phase), global 2027; targetSdk 36 already met.
- The FGS strip (`tools:node="remove"` on the service + 2 permissions) is a proven runtime no-op
  but was NOT applied — it only pays off under Play, and needs a comment warning that a future
  `BackgroundConfig` opt-in would then fail at `startForeground`.
- Traps appended to `docs/agents/traps.md`: SPA 200-fallback fakes file existence; merged manifest
  != source manifest; inherited dataSync FGS; link ceremony direction + un-enrolled re-mint;
  `gradlew.bat` path resolution and `$?` after a pipe.
