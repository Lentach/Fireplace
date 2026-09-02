# Android release runbook

Status: **Phase 1 (release plumbing) — DONE 2026-07-29. Phase 2 (encrypted local message store) —
DONE and ON MASTER** (verified 2026-08-04: `native_content_store.dart` etc. live in
`frontend/lib/services/encryption/`; the old `feature/android-encrypted-store` branch ref is gone —
an earlier revision of this header said "not yet merged", which was stale).
A release APK keeps decrypted plaintext, media keys, pending-send plaintext
and the JWT out of the SharedPreferences XML: content lives sealed in a SQLCipher database
(`files/fp_content.db`) and the JWT lives in Keystore-backed secure storage. **Distribution is
gated on the real-phone smoke (owner task):** voice play/seek/cached replay, push with the app
KILLED on a release-signed build, upgrade from a pre-Phase-2 install. The **`.jks` off-PC backup
is DONE (2026-09-02)** — see "Backing it up" for the fingerprints and where the copies are.
See `frontend/CLAUDE.md` §5 for the store's invariants.

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
# GIVE THE SAME VALUE FOR BOTH. keytool writes PKCS12, where the key password MUST equal the
# store password. A mismatch does not say so — it fails later with the opaque
# "final block not properly padded". This cost a debugging session on 2026-07-29.
copy key.properties.example key.properties
# Edit key.properties: fill storePassword/keyPassword with that SAME value; keyAlias=fireplace
# and storeFile=../keystore/fireplace-release.jks are already correct.
```

- `key.properties` and `keystore/` are gitignored (both `frontend/keystore/` and
  `frontend/android/keystore/` are covered). **Never commit either.** Verified 2026-08-02:
  neither path is tracked, and `git check-ignore -v` names the rules
  (`frontend/android/.gitignore:12`, root `.gitignore:47`).

### Backing it up (the one unrecoverable artifact) — DONE 2026-09-02

`frontend/android/keystore/fireplace-release.jks` is the app's identity. Lose it and existing
installs can never be updated again — the only path left for a user is uninstall, which destroys
their Signal keys and history. This outranks every other gate in this runbook.

**Known-good fingerprints (public-safe, record-of-truth):**

| What | SHA-256 | Meaning |
|---|---|---|
| `fireplace-release.jks` file (4430 bytes) | `9559773E3232D091F5CECB2149B8D5A1B937E2540DC2F31F6370AA8E6421052C` | every backup copy must hash to this |
| Signing certificate (alias `fireplace`, PKCS12, created 2026-07-29, valid to 2053-12-14) | `8E:9A:6B:F3:7B:58:A8:43:2C:42:D8:9E:31:99:00:7C:4A:A9:07:7E:29:7A:96:6A:2F:2C:A7:58:5C:DF:40:5D` | what `apksigner verify --print-certs` must print on every shipped APK; what Play/Firebase ask for |
| `fireplace-release.jks.enc` (4448 bytes, AES-256-CBC, PBKDF2 600k iters) | `B0FF9B2F7F412D48D772DB7CC25D0BAF5A61D47BDE0590A4A18EE2C1F7165BED` | the cloud copy; check before decrypting |

**Where the copies are (two failure domains, neither is the dev PC):**
1. Plain `.jks` + a restore `README.txt` on an external USB drive the owner keeps off-site.
   Written, cache-flushed (`Write-VolumeCache`), read back → file hash matched.
2. `fireplace-release.jks.enc` in the owner's personal cloud storage — ciphertext only; the provider
   never sees the key. Passphrase is NOT the keystore password and exists only on paper (transcription
   was PROVEN: the paper copy was typed back and decrypted the archive to the file hash above; the first
   attempt had several base64 confusables mistranscribed, which is why the round-trip check is mandatory).
3. **Passwords are on paper, hidden, separate from the USB**: the keystore/key password (also in the
   gitignored `frontend/android/key.properties` on the dev PC) and the archive passphrase.

**Restore proof done 2026-09-02:** an APK signed with the USB copy
(`apksigner sign --ks <usb>/fireplace-release.jks --ks-key-alias fireplace …`) verifies with the
certificate SHA-256 above — the backup is usable, not merely byte-identical.

**Restore recipe:**
```powershell
# from the USB: copy, then hash must equal the file SHA-256 above
Get-FileHash fireplace-release.jks -Algorithm SHA256
# from Google Drive: check the .enc hash, then decrypt (openssl ships with Git for Windows)
Get-FileHash fireplace-release.jks.enc -Algorithm SHA256
openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -in fireplace-release.jks.enc -out fireplace-release.jks
# then: place at frontend/android/keystore/, recreate android/key.properties from key.properties.example
# (storeFile=../keystore/fireplace-release.jks, keyAlias=fireplace, both passwords from the paper),
# build, and confirm: apksigner verify --print-certs app-release.apk  → certificate SHA-256 above
```

**Re-doing a backup (e.g. new USB):** copy → `Write-VolumeCache -DriveLetter X` → `Get-FileHash` on the
copy must equal the file hash. For a new encrypted copy: `openssl enc -aes-256-cbc -pbkdf2 -iter 600000
-salt -in fireplace-release.jks -out fireplace-release.jks.enc -pass file:<passfile>`; put the passphrase
in a local file (never in a chat/terminal history), strip CRLF (`tr -d '\r\n'`) before use, decrypt
back and hash-compare, have the paper copy typed back and verified the same way, then delete the
pass files. apksigner reads `--ks-pass file:` and `--key-pass file:` from the SAME file line by line —
write the password twice.

## Build

```powershell
# repo root, on the PC (never the VM)
.\build-android.ps1              # clean build + all gates
.\build-android.ps1 -SkipClean   # faster iteration
```

Output: `frontend/build/app/outputs/flutter-apk/app-release.apk` + SHA256 in the summary.
The script reads `GiphyApiKey` ONLY from the `GIPHY_API_KEY` env var — dot-source the config first:
`. .\deploy-web.config.ps1; $env:GIPHY_API_KEY = $GiphyApiKey; .\build-android.ps1` (there is no
embedded fallback key despite the script's warning text; empty = GIF search disabled). `BASE_URL`
defaults to production; override with `-BaseUrl` for a staging build. Requires an Android SDK with
build-tools (for `apksigner`) via `ANDROID_HOME`/`ANDROID_SDK_ROOT`/`%LOCALAPPDATA%\Android\Sdk`.

**versionCode floor — 10024.** The first release build (2026-09-02) was `0.1.24` from
`feat/video-messages` (`1f9d96f`) → versionCode `10024`, SHA256
`743612453b44ff2a961760cb010a4dac9b87868594080517c9c1ac1a2bc40ef1`, built for the owner's phone.
`master` was still `0.1.21` at the time, so a build from master would derive `10021` and Android
would REFUSE it as a downgrade. Every build meant to install over an existing one must bump
`frontend/pubspec.yaml` past the highest version ever installed — regardless of branch.

**Release builds cannot be screenshotted** — `MainActivity.kt` sets `FLAG_SECURE` when not
debuggable, so `screencap` returns rc=1 while the app window is live (even from recents). Verify
release behavior via logcat, the prod DB, and the notification shade with the app dead.

## Device smoke checklist (before any distribution)

Build from a **fresh clone** at least once (proves no local-only file is load-bearing), then on a real device:

1. Install APK, register/login → conversations load.
2. E2E round trip with a PWA peer: PreKey (`3:`) first message, whisper (`2:`) replies, both directions decrypt.
3. **Push with the app killed** (data-only FCM → local notification, tap opens the right chat). This
   specifically validates the no-options Firebase init from `google-services.json`.
   ⚠️ "Killed" = swipe away from recents or `adb shell am kill <pkg>` — **never `am force-stop`**:
   force-stop puts the package in Android's *stopped state*, in which the OS drops every FCM message
   until the user launches the app again. A force-stopped app receiving nothing is not a push bug.
4. Voice note record + playback; image send/receive (validates the 16KB-patched webcrypto at runtime).
5. Delete-for-everyone + expiry: plaintext purged locally (Privacy & Safety diags clean).
6. **Same-account flip-flop drill**: log the SAME account into APK + PWA, force reconnects on both →
   observe identity thrash (peers see repeated identity-changed banners). Log OUT of the PWA → epochs
   stabilize, E2E round trip recovers. We ship migration instructions we have watched fail and recover.

**Emulator pre-smoke of the first release build (2026-09-02, Pixel_7 AVD, prod backend):** items 1
and 3 PASS on the release-signed, R8-minified APK — fresh account registered on prod, `fcm_token` row
written, process killed with `am kill`, a web→APK message woke a NEW process
(`FLTFireMsgReceiver: broadcast received for message` → background engine → local notification),
shade shows "Umbra / You have a new message" with the hex icon, tap cold-starts `MainActivity`.
Screenshots (gitignored): `.planning/push-release-shade.png`, `.planning/push-release-statusbar.png`.
Items 2, 4, 5, 6 and "tap opens the RIGHT chat" remain for the real phone (release screenshots are
impossible, see `FLAG_SECURE` above).

## Distribution (decision 2026-07-29: direct APK first, Play later)

- Attach `app-release.apk` + its SHA256 to a GitHub Release on `Lentach/Fireplace`.
- No auto-update exists for sideloaded APKs: announce updates in-app/manually; users re-install
  over the top (same signature = data survives).
- Play Store later: needs `flutter build appbundle` (same gates apply), data-safety forms, and the
  16KB + targetSdk requirements already satisfied here.

## User wording (APK) — decision 2026-09-02: NEW ACCOUNTS ONLY (until multi-device DEPLOYS)

The 0.1.24 APK was built from `feat/video-messages`, i.e. the single-device protocol prod runs today
(one key bundle per account, no `deviceId`): an existing PWA user logging into it would either
thrash identities (both live) or have to abandon the PWA. **PR #144 (multi-device, linked devices)
merged to master on 2026-09-02 but is NOT deployed** — once it ships on both tiers AND the APK is
rebuilt from master, replace this section with the link-device ceremony wording
(`docs/design/multi-device.md`). Until then the APK is marketed as **a fresh start** — use EXACTLY this:

> Umbra for Android is a new install: **create a new account in the app** (pick a new username — your
> web account stays as it is). One account works on one device; don't log the same account into the
> app and the web at the same time. Friends can re-add you by your new `username#tag`.
> **Never delete your web account and never clear the browser's site data** — that destroys your web
> history for nothing. iPhone users: keep using the web app as-is; nothing changes for you.

(Superseded 2026-09-02: the previous "log in with your existing account, then log out of the web app"
migration text. It still works technically — see the flip-flop drill — but is no longer what we tell
users.) A Play listing must state one-account-one-device.

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
