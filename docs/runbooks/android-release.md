# Android release runbook

Status: **Phase 1 (release plumbing) — DONE 2026-07-29. Phase 2 (encrypted local message store) —
DONE 2026-07-29 on `feature/android-encrypted-store`, device-verified, not yet merged.**
A release APK built from that branch keeps decrypted plaintext, media keys, pending-send plaintext
and the JWT out of the SharedPreferences XML: content lives sealed in a SQLCipher database
(`files/fp_content.db`) and the JWT lives in Keystore-backed secure storage. **Distribution is
gated on two things, both owner tasks:** (1) the real-phone smoke — voice play/seek/cached
replay, push, upgrade from a pre-Phase-2 install; (2) the **`.jks` off-PC backup**, still
outstanding — see "Backing it up" below, because a lost keystore permanently ends updates for
everyone who installed. See `frontend/CLAUDE.md` §5 for the store's invariants.

**`CONTENT_KEY_CANARY_LOST` is NOT one of these gates.** `ContentKeyCanary.checkAndArm()` is
`if (!_isWeb) return;` — a no-op on native; it measures web IndexedDB+WebCrypto durability and
gates a separate web-sealing effort. It can produce no evidence about Android Keystore. What
covers Android key loss instead: no auth binding, keys co-located with the Signal identity, the
armed-gate, and `CONTENT_KEY_LOST` → retired-id rendering.

## What is enforced mechanically (do not re-implement by hand)

| Gate | Where | Failure mode it kills |
|---|---|---|
| Release packaging without a keystore **throws at execution time** (exactly `packageRelease`/`packageReleaseBundle` — covers bare `gradlew build`/`assemble`; release `signingConfig` is NULL without a keystore, so any missed path yields an inert UNSIGNED apk) | `frontend/android/app/build.gradle.kts` | silent fallback to debug signing |
| Signer check on the built APK (`apksigner verify --print-certs`; NOT keytool — minSdk 24 means v2/v3-only signatures, which keytool can't read) | `build-android.ps1` | debug-signed APK shipping anyway |
| 16KB ELF alignment of every 64-bit `.so` | `scripts/verify-apk-16k.mjs` (falsified by `verify-apk-16k.selftest.mjs`) | webcrypto pub-cache patch silently dropped → crash on Android 15 16KB devices |
| Backup lockdown | `AndroidManifest.xml` `allowBackup=false` + `res/xml/data_extraction_rules.xml` | plaintext SharedPreferences uploaded to Google Drive; secure-storage blob restored without its Keystore key (= permanently dead Signal identity) |
| versionCode monotonicity | `build-android.ps1` derives `major*1_000_000 + minor*10_000 + patch` | Play rejecting non-incrementing uploads; `+N` never enters pubspec (root CLAUDE.md §5) |

Firebase/FCM needs **no secret provisioning**: Android initializes from the committed
`google-services.json` natively (`Firebase.initializeApp()` with no options — the Dart-side
`firebase_options.dart`/`firebase_secrets.dart` placeholder files were deleted 2026-07-29; passing
their placeholder options was why a clean-checkout APK had dead push).

## One-time setup: release keystore (OWNER TASK)

The keystore IS the app's identity. **Lose it → you can never update the app for existing installs**
(users must uninstall, which destroys their local Signal keys and history). Treat it like the VM SSH key.

```powershell
cd frontend/android
mkdir keystore
# keytool ships with a JDK, which is often NOT on PATH when only Android Studio
# is installed. If `keytool` is not recognized, use Android Studio's bundled JBR:
#   & "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" ...
# (or "$env:JAVA_HOME\bin\keytool.exe" if JAVA_HOME is set).
keytool -genkeypair -v `
  -keystore keystore/fireplace-release.jks `
  -alias fireplace -keyalg RSA -keysize 4096 -validity 10000
# It prompts for: keystore password, name/org fields (values are cosmetic), key password.
copy key.properties.example key.properties
# Edit key.properties: fill storePassword/keyPassword; keyAlias=fireplace and
# storeFile=../keystore/fireplace-release.jks are already correct.
```

- `key.properties` and `keystore/` are gitignored (both `frontend/keystore/` and
  `frontend/android/keystore/` are covered). **Never commit either.** Verified 2026-08-02:
  neither path is tracked, and `git check-ignore -v` names the rules
  (`frontend/android/.gitignore:12`, root `.gitignore:47`).

### Backing it up (the one unrecoverable artifact)

`frontend/android/keystore/fireplace-release.jks` exists on the dev PC and **nowhere else**.
Lose it and existing installs can never be updated again — the only path left for a user is
uninstall, which destroys their Signal keys and history. This outranks every other gate in
this runbook.

```powershell
# 1. Fingerprint the live keystore. Record this value somewhere you will still have it later.
Get-FileHash frontend/android/keystore/fireplace-release.jks -Algorithm SHA256

# 2. Copy to at least TWO destinations that are not this PC and not the same failure domain
#    (e.g. an encrypted password-manager attachment AND an offline USB / external drive).
#    The two passwords live in the password manager as fields, NOT next to the file:
#    key.properties is plaintext, so a backup holding both the .jks and key.properties in
#    one place is a single-object compromise.

# 3. Verify each copy AFTER writing it — a backup you have not read back is a guess.
Get-FileHash <path-to-copy> -Algorithm SHA256   # must equal step 1
```

A restore is only proven when a build signed by the restored keystore reports the same
certificate as the shipped one: `apksigner verify --print-certs <apk>`. Do that check once,
now, while a known-good original still exists — not on the day you need the backup.

## Build

```powershell
# repo root, on the PC (never the VM)
.\build-android.ps1              # clean build + all gates
.\build-android.ps1 -SkipClean   # faster iteration
```

Output: `frontend/build/app/outputs/flutter-apk/app-release.apk` + SHA256 in the summary.
The script reuses `deploy-web.config.ps1` for `GiphyApiKey` if present. `BASE_URL` defaults to
production; override with `-BaseUrl` for a staging build. Requires an Android SDK with build-tools
(for `apksigner`) via `ANDROID_HOME`/`ANDROID_SDK_ROOT`/`%LOCALAPPDATA%\Android\Sdk`.

## Device smoke checklist (before any distribution)

Build from a **fresh clone** at least once (proves no local-only file is load-bearing), then on a real device:

1. Install APK, register/login → conversations load.
2. E2E round trip with a PWA peer: PreKey (`3:`) first message, whisper (`2:`) replies, both directions decrypt.
3. **Push with the app killed** (data-only FCM → local notification, tap opens the right chat). This
   specifically validates the no-options Firebase init from `google-services.json`.
4. Voice note record + playback; image send/receive (validates the 16KB-patched webcrypto at runtime).
5. Delete-for-everyone + expiry: plaintext purged locally (Privacy & Safety diags clean).
6. **Same-account flip-flop drill**: log the SAME account into APK + PWA, force reconnects on both →
   observe identity thrash (peers see repeated identity-changed banners). Log OUT of the PWA → epochs
   stabilize, E2E round trip recovers. We ship migration instructions we have watched fail and recover.

## Distribution (decision 2026-07-29: direct APK first, Play later)

- Attach `app-release.apk` + its SHA256 to a GitHub Release on `Lentach/Fireplace`.
- No auto-update exists for sideloaded APKs: announce updates in-app/manually; users re-install
  over the top (same signature = data survives).
- Play Store later: needs `flutter build appbundle` (same gates apply), data-safety forms, and the
  16KB + targetSdk requirements already satisfied here.

## User migration wording (PWA → APK) — use EXACTLY this

> Install the Fireplace app, **log in with your existing account**, then **log out of the web app**.
> Don't run both at once. Your friends and chats come with you; old message history stays on the old
> device (end-to-end encryption means it physically cannot follow). Your friends will see a one-time
> "security identity changed" notice — that's expected; the fingerprint dialog lets them verify it's you.
> **Never delete your account and never clear the browser's site data** — that destroys data for nothing.
> iPhone users: keep using the web app as-is; nothing changes for you.

Why logout matters: the client re-uploads its key bundle on EVERY socket connect
(`encryption_provider.dart`), so two live devices on one account clobber each other's identity epoch
on every reconnect (not "last one wins" — a permanent flip-flop that burns both sides' prekeys and
spams identity banners). A logged-out PWA never authenticates the socket, so it goes quiet; its local
keys deliberately survive logout (frontend/CLAUDE.md §5), so old history stays readable on the old device.

## Known-not-done (tracked, do not rediscover)

- **Phase 2 (launch gate) — BUILT, see `frontend/CLAUDE.md` §5.** Drift+SQLCipher store with the DB
  key and rotating content keys in Keystore-backed secure storage, armed-gate before any use,
  rotate-and-destroy shredding. Shredding still comes from key rotation, NOT from SQLite deletes —
  freed pages/WAL keep old bytes; `PRAGMA secure_delete` is defense-in-depth only. Content-key loss
  = whole local history unreadable (plaintext cache is NOT re-derivable: the ratchet consumed the
  keys, and media records hold the only copy of `mediaKey`/`mediaIv`) — budgeted, not denied, and
  rendered as retired ids rather than `[Decryption failed]`.
  Acceptance is executable: `cd frontend && flutter test integration_test -d <deviceId>` (8 tests,
  including a real-Keystore content-key wipe that must retire history, never crash).
- R8/minify is OFF (default): enable later with keep-rules if APK size matters; not a security gate.
- `network_security_config` now EXISTS and is deliberately narrow: `frontend/android/app/src/main/res/xml/`
  permits cleartext to `127.0.0.1`/`localhost` ONLY (just_audio serves unsealed voice bytes through a
  loopback proxy; API 28+ blocks that otherwise), with no `base-config`, so every other host keeps
  the platform block. The debug variant adds `10.0.2.2` for a local backend. Never widen this to
  `usesCleartextTraffic="true"`.
- iOS: no Firebase app, no runner signing — out of scope until an iOS release is planned.
