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

## Notes for next session

- **Phase 2 is the LAUNCH GATE**: Drift+SQLCipher encrypted store for categories 7–18 (decrypted cache, raw pairs, pendsend, backlog/retention/diag, JWT→secure storage, voice cache), key in Keystore, no auth binding, armed-gate, rotate-and-destroy on purge (shredding = key rotation, NOT SQLite deletes). Design inputs: `plaintext_record_codec.dart`, #105. **Do not distribute any APK before Phase 2** — first-install sealing is the only fully-clean shredding story.
- **OWNER TASK pending**: generate the release keystore per the runbook and back up the .jks + passwords off-PC.
- Backend quick win any time: friendship/block gate on `fetchPreKeyBundle`.
- Phase 3 smoke additions agreed: fresh-clone build + killed-app push (validates no-options Firebase init), same-account flip-flop drill then PWA logout recovery.
