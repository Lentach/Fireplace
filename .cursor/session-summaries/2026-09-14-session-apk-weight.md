# The shared APK halves to 48.9 MiB by compressing native libs — nothing removed, no ABI dropped

**Date:** 2026-09-14 · **Version:** 0.2.46 → 0.2.47 · **Tiers deployed:** none (Android APK built + installed on the owner's phone)

## What was done
- `frontend/android/app/build.gradle.kts`: added `packaging { jniLibs { useLegacyPackaging = true } }`. The 24 `.so` entries were STORED (AGP default for minSdk >= 23) and deflate **100.29 → 44.19 MiB (44.1%)**, taking the universal APK **105.2 → 48.9 MiB**. Every ABI still ships.
- `frontend/pubspec.yaml`: 0.2.46 → 0.2.47 (versionCode 20047; 20046 was already in the field on the phone AND in prod, so reusing it would have made two different binaries report one version).
- `docs/runbooks/android-release.md`: rewrote the size section with measured numbers; four wrong claims corrected (below); added the define-extraction procedure and the 0.2.47 build record.
- `docs/agents/traps.md`: stale floor 20044 → 20046, plus 5 new Android/tooling traps.
- **Declined: ABI narrowing** (19.7 MiB arm64-only). The APK goes to friends on unknown hardware and `armeabi-v7a` is the only ABI a 32-bit phone accepts — there is no fallback, the install just fails. Dropping only x86_64 (33.6 MiB) would also kill the release-APK emulator drill. Owner decision.
- **Declined: unbundled ML Kit** (−2.8 MiB), `--split-debug-info` (unmeasured, costs symbolized logcat), R8 (~1 MiB vs keep-rule risk in libsignal/drift/Firebase), replacing `emoji_picker_flutter` (1.38 MiB of Dart).

## Key files
- Edited: `frontend/android/app/build.gradle.kts`, `frontend/pubspec.yaml`, `docs/runbooks/android-release.md`, `docs/agents/traps.md`
- New: `.cursor/session-summaries/2026-09-14-session-apk-weight.md`
- Read only (load-bearing): `scripts/verify-apk-16k.mjs` (`entryData` inflates method-8 — why the gate survives compression), `build-android.ps1:122-143`, and in the pinned SDK `FlutterPlugin.kt:137,156-160,350,589-598,655-677`, `FlutterPluginConstants.kt:39-63`, `FlutterPluginUtils.kt:41,292-294`

## Verification
- **Shipped build 0.2.47 `320c11dd`**: 48.9 MB, SHA256 `788aba471ba4af3664289a56f2e4aa2e59de19b2f0b3619f43ff346c1466fec5`, signer DN `CN=Rick Sanches`, **certificate SHA-256 MEASURED `8e9a6bf3…5cdf405d` = record-of-truth**, 16KB gate **16/16 on the packed APK**. All 24 libs `compress_type=8`.
- **All three dart-defines confirmed inside the EXTRACTED `lib/arm64-v8a/libapp.so`**: `BASE_URL` ×2, `GIT_COMMIT` `320c11dd` ×1, the 32-char Giphy key ×1. Same search on the RAW apk bytes = **0 hits** — the reason the runbook procedure changed.
- **Installed on the owner's real phone `f849cc68` (Mi 11 Lite 5G, arm64)**, `adb install -r` 20046 → 20047 in 6.5 s: on-device `base.apk` hashes to `788aba47…`; `firstInstallTime` PRESERVED (2026-09-13 23:53:44) while `lastUpdateTime` moved; app cold-started and was live (pid 19052, `MainActivity` visible).
- **Only the ONE matching ABI is extracted, so the device footprint SHRINKS too** — phone `base.apk` 105.3 MiB + empty `lib/` before vs 49.0 + 33.9 = **82.9 MiB** after (−22.4). On `emulator-5554` (x86_64) the packed APK installed in 9.8 s and cold-started in **3.94 s** with no `dlopen`/`UnsatisfiedLink`/FATAL.
- **CI 6/6 success on `320c11dd`** (`gh api …/commits/master/check-runs`). Pushed to `master` and `feat/passcode-lock`.
- Measured, then corrected in the runbook: `--target-platform android-arm64` alone lands at **57.26 MiB**, not ~42 (real release build; 18.5 MiB of third-party natives still ×3); the 1000×ABI versionCode offset is exclusive to `--split-per-abi`; `--split-debug-info` does NOT strip ELF symbols (release AOT has no `.symtab`/`.debug_*`, only `.text` 7.58 + `.rodata` 5.73 MB).
- `libapp.so` by package (`--analyze-size`, 12.75 MiB fully accounted): `flutter` 3.17, `fireplace` 1.76, `emoji_picker_flutter` 1.38, `@unknown` 1.06, `unorm_dart` 0.81 (transitive from `bip39_mnemonic` — BIP-39 mandates NFKD, load-bearing).
- **NOT verified:** no UI was driven on the phone (MIUI blocks synthetic input, `FLAG_SECURE` blocks screencap) — the version footer, a live E2E round trip and voice/image on 0.2.47 are owner-eyeball items. No web/backend deploy; prod still reports 0.2.46 / `43481643`.

## Notes for next session
- **Owner-owed:** eyeball 0.2.47 on the phone (footer reads `320c11dd`, one E2E round trip, one voice note) before sharing the APK with friends. Shareable file staged at `C:/Users/Lentach/Desktop/umbra-0.2.47-320c11dd.apk`, hash re-verified after the copy.
- Keystore backups CONFIRMED by the owner in two places (cloud + paper). The cert is a one-way door: every future update must be signed by that `.jks`. No APK is published yet, so Play App Signing can still adopt it via PEPK.
- A concurrent agent held uncommitted backend deletion-tombstone work (`message-tombstone.entity.ts`, `migrations/0018_deletion_tombstones.sql`, 7 backend files) throughout; it was deliberately NOT committed. `master` is clean at `320c11dd` for them to build on.
- Traps (all appended to `docs/agents/traps.md`): a `--debug` probe poisons the next `-SkipClean` release build via `GeneratedPluginRegistrant.java`; a release build writes the APK to TWO output paths; `useLegacyPackaging` makes the on-device footprint SMALLER for a universal APK; `adb` needs `cmd /c` + a bare filename; `--target-platform` does not narrow third-party ABIs.
