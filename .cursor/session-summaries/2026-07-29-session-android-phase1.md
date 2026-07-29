# Android release — investigation + Phase 1 release plumbing

**Date:** 2026-07-29

## What was done

Owner discovered the local plaintext-at-rest hole ("messages readable after deletion") and decided to go native Android. Session had two halves: a 4-scout investigation feeding a brainstorm, then Phase 1 (release plumbing) implemented.

### Investigation corrections (evidence-checked, keep these straight)

- The exposure is **localStorage + raw SharedPreferences, not IndexedDB**. IndexedDB on web holds only the push deep-link DB and the B2 canary. Signal keys: `sig_*` plaintext base64 in localStorage on web (deliberate, `signal_stores.dart`); Keystore-backed on native via DualStorage. **Decrypted plaintext / media keys / pending-send / JWT go through RAW SharedPreferences on EVERY platform** (`encryption_service.dart:79`) — plaintext XML on Android. Going native fixes nothing by itself.
- `audit/e2e-safety` **is MERGED (PR #108) and live** as 0.0.135/0.0.136 — the 2026-07-28 summaries' "NOT merged" lines are stale. "Gone from the app" is shipped; "gone from the disk" (B2 sealing, #105 M4) is the remaining half.
- Native Android can seal WITHOUT the web canary gate (no IndexedDB tab-close abort), BUT Keystore keys still die (factory reset, new-device restore, auth-binding invalidation) and the plaintext cache is NOT re-derivable (ratchet consumed the keys; media records hold the only `mediaKey`/`mediaIv`). Content-key loss = whole local history unreadable — design budgets for it (no auth binding, co-locate with Signal keys, armed-gate, `CONTENT_KEY_LOST` → retired-id rendering).
- Sealed sender: 9 structural server dependencies on known senderId, no sender-cert infra — **deferred**. Cheap wins noted: `fetchPreKeyBundle` has NO friendship/block gate (anyone can burn anyone's OTPs); reactions stored cleartext `{emoji:[userId]}`.
- Same-account PWA+APK is a **flip-flop, not last-wins**: `uploadKeyBundle` re-fires on every connect. Migration wording = log in on APK, **log OUT of the PWA**.

### Decisions (owner)

1A direct APK first (GitHub Releases, Play later) · 2B PWA stays for iOS users · 3B dedicated encrypted DB (Drift+SQLCipher, key in Keystore) on native · 4 same-account re-login, no key export, accept fresh identity + banner.

### Phase 1 implemented (this session)

- **Gradle signing gate**: release task without `android/key.properties` now THROWS (was: silent debug-sign fallback). Falsified both ways: `assembleRelease --dry-run` fails with the message, `assembleDebug` unaffected.
- **Backup lockdown**: `allowBackup=false` + `fullBackupContent=false` + `res/xml/data_extraction_rules.xml` (all domains, cloud + d2d). Dual purpose: plaintext-prefs leak AND flutter_secure_storage's restore-blob-without-Keystore-key corruption. Verified in the merged manifest of a real assembleDebug build.
- **16KB hard gate**: `scripts/verify-apk-16k.mjs` parses the built APK (zip central dir + ELF program headers) and fails if any 64-bit `.so` has PT_LOAD align <16384 — catches every way `patch_webcrypto_16k.ps1` (pub-cache, PowerShell-only) silently drops. Falsification harness `verify-apk-16k.selftest.mjs`: 5/5 (misaligned→1, aligned→0, no-libs→1, 32-bit-only→1, garbage→1). Also proven on the real debug APK: 7 libs OK, libwebcrypto at 16384.
- **Firebase init fix**: native now calls `Firebase.initializeApp()` with NO options (native default app from committed `google-services.json`) in `main.dart` AND the FCM background isolate. Deleted `firebase_options.dart` + `firebase_secrets.dart`(+example) — their tracked PLACEHOLDER values meant every clean-checkout APK had silently dead push. No secrets provisioning needed anymore.
- **Manifest/SDK pins**: explicit `INTERNET` in main manifest (was debug/profile-only, release rode Firebase's manifest merge); compileSdk=36, minSdk=24, targetSdk=36 (= Flutter 3.44.6 defaults, now explicit).
- **`build-android.ps1`** (repo root): pub get → 16KB patch → `flutter build apk --release --build-number=(major*1e6+minor*1e4+patch)` → `apksigner verify --print-certs` rejecting `CN=Android Debug` (NOT keytool — minSdk 24 = v2/v3-only signatures keytool can't read) → node 16KB gate → SHA256 summary.
- **Runbook** `docs/runbooks/android-release.md`: keystore generation (OWNER TASK — .jks backup is the single unrecoverable artifact), smoke checklist (incl. fresh-clone push test + flip-flop drill), migration wording, Phase 2 launch-gate statement.
- `.gitignore`: `frontend/android/keystore/` added (key.properties.example's storeFile resolves there; only `frontend/keystore/` was covered). CLAUDE.md root §5 + frontend §1/§5/§7 updated.

## Key files

`build-android.ps1`, `scripts/verify-apk-16k.mjs` + `.selftest.mjs`, `frontend/android/app/build.gradle.kts`, `frontend/android/app/src/main/AndroidManifest.xml`, `res/xml/data_extraction_rules.xml`, `frontend/lib/main.dart`, `frontend/lib/services/android_fcm_local_notifications.dart`, deleted `frontend/lib/firebase_{options,secrets}.dart{,.example}`, `docs/runbooks/android-release.md`.

## Verification

- `flutter analyze` clean; full suite **1069 passed + 5 skipped** (matches §3 count).
- Gradle gate falsified both directions (release throws, debug builds).
- 16KB gate: 5/5 selftest + real debug APK (7 libs aligned).
- Merged manifest grep: `allowBackup="false"`, `fullBackupContent="false"`, `dataExtractionRules`, `INTERNET` all present.
- Backend untouched. No version bump (no production release).

## Later same session: review, keystore, first signed APK

- **Two-axis review of `21074ba`** (reviewer subagents): Spec 10/10 clean. Standards: one P3, fixed in `a4c3697` — the signing gate moved from config-time `startParameter.taskNames` (missed bare `gradlew build`/`assemble`, over-matched lintRelease) to an execution-time `doFirst` on EXACTLY `packageRelease`/`packageReleaseBundle` (NOT a `package*Release*` prefix: `packageReleaseResources` feeds lint/unit tests), plus release `signingConfig = null` without a keystore (missed path ⇒ inert UNSIGNED apk, never debug-signed). Falsified: throws at `:app:packageRelease` with the runbook message; debug green.
- **Owner generated the release keystore** (`fireplace-release.jks`, alias `fireplace`, RSA-4096, PKCS12 one-password). Password on paper, verified char-by-char against `key.properties`; .jks off-PC copy still on the owner. First `key.properties` had a one-char typo in `keyPassword` → Gradle error "Given final block not properly padded" at `:app:packageRelease` (store opened, key read failed = keyPassword wrong); fixed by copying storePassword over it programmatically (never displayed).
- **First signed release APK built end-to-end** via `build-android.ps1`: 0.0.137 / versionCode 137, 69.2 MB, apksigner OK, 16KB gate 8/8 (incl. release `libapp.so`). Shakedown fixes committed (`cb09dfe`): script stops gradle daemons before `flutter clean` (live daemon ⇒ half-deleted `frontend\build` ⇒ lint dies on locked jars), and `:app` `lint { checkReleaseBuilds = false }` (VERIFIED effective for the whole graph: `--dry-run` lists 0 lintVital tasks incl. `:file_picker:` — library lintVital only runs as a dependency of the app's pipeline).
- Master moved twice under the session (PR #109 merged, **0.0.137 released** by owner) — commits rebased cleanly on top.

## Notes for next session

- **Phase 2 handoff is COMPLETE and self-contained: `docs/plans/2026-07-29-android-phase2-handoff.md`** — required reading list, agreed design (no relitigating), storage inventory, gotchas (SQLCipher .so must pass the 16KB gate!), acceptance criteria. Fresh agent starts there.
- **Do not distribute any APK before Phase 2** — first-install sealing is the only fully-clean shredding story. Owner MAY sideload for self-testing: main account = log OUT of PWA first; cleanest is a throwaway account on the APK chatting with the main PWA account (avoids the uploadKeyBundle flip-flop).
- Backend quick win any time: friendship/block gate on `fetchPreKeyBundle`.
- Phase 3 smoke additions agreed: fresh-clone build + killed-app push (validates no-options Firebase init), same-account flip-flop drill then PWA logout recovery.
