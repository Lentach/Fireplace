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
6. **Link ceremony on the release build** (the instructions we now ship — see "User wording"): web
   primary enables linked devices → APK logs in → `DeviceLinkGateScreen` appears → **the PHONE
   displays the QR/out-of-band code and the WEB PRIMARY scans it** (spec §5.1: `ephPubN` travels
   only over that scan) → the same SAS words appear on both screens → **approve on the primary**.
   Then: both devices receive a peer's message, a send from the phone self-syncs to the web, and
   revoking the phone from the web kicks it.
7. **Un-enrolled flip-flop drill** (the hazard the wording steers users away from): on an account
   that never enabled linking, log in on APK + PWA and force reconnects on both → identity thrash
   (peers see repeated identity-changed notices). Log OUT of the PWA → epochs stabilize, E2E round
   trip recovers. Ship no instruction we have not watched fail and recover.

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
- Play Store later: needs `flutter build appbundle` — and the signer + 16KB gates must move onto the
  BUNDLE's output, because `build-android.ps1` only ever inspects an APK — plus a privacy policy,
  the data-safety form, and an in-app report path (UGC policy); 16KB + targetSdk are already met.
- **The signing certificate is a one-way door.** No APK has ever been published (`gh release list`
  empty, 2026-09-13), so Play App Signing can still adopt THIS keystore (PEPK) as the app signing
  key. Once sideloaded APKs are in users' hands, letting Google generate its own key means Play
  updates are refused on those installs (different cert) and the only path left is uninstall —
  which destroys the user's Signal identity and local history. Decide the cert before the first
  APK leaves the building; rotation later does not repair already-installed sideloads.
- **Foreground-service declaration (Play only, and avoidable).** `light_compressor_v2-1.9.1`'s
  library manifest merges `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_DATA_SYNC` and a
  `CompressionForegroundService` (`foregroundServiceType="dataSync"`) into our APK
  unconditionally. At targetSdk 34+ Play then requires an App-content declaration for that type:
  use-case description, user impact, **and a link to a demo video showing the user steps that
  trigger it** — a mismatch is a rejection. **We never start that service**: `transcodeVideoToFit`
  (`frontend/lib/utils/video_transcode_io.dart:37-56`) passes no `BackgroundConfig`, which is the
  plugin's opt-in for background execution. So the honest options are (a) strip the service and
  both permissions with `tools:node="remove"` in our manifest and re-verify against the MERGED
  manifest, or (b) file a declaration plus a video for a service that cannot run. Prefer (a).
  Unrelated but recorded from the same README: that plugin needs no R8/ProGuard keep rules.
- **The permission set Play sees is the MERGED one — MEASURED 2026-09-13, not inferred.** Generate
  it with `cd frontend/android && sh ./gradlew :app:processReleaseManifest` (~2.5 min, needs NO
  keystore — the signing gate fires at `packageRelease`), then read
  `frontend/build/app/intermediates/merged_manifest/release/outputReleaseAppLinkSettings/AndroidManifest.xml`.
  Exactly nine `uses-permission` entries: `INTERNET`, `POST_NOTIFICATIONS`, `CAMERA` (ours),
  `RECORD_AUDIO` (record_android), `VIBRATE` (flutter_local_notifications), `WAKE_LOCK` +
  `ACCESS_NETWORK_STATE` (firebase_messaging), `FOREGROUND_SERVICE` +
  `FOREGROUND_SERVICE_DATA_SYNC` (light_compressor_v2, with its
  `foregroundServiceType="dataSync"` service at line 237). `BIND_JOB_SERVICE`/`DUMP` appear only
  as `android:permission` attributes on Google services — they are NOT requested permissions.
  **No `READ_MEDIA_*`/`READ_EXTERNAL_STORAGE`** (image_picker/file_picker declare none), so Play's
  Photo and Video Permissions policy does not apply. Re-measure after any plugin bump.

## User wording (APK) — rewritten 2026-09-13: LINK THE DEVICE, never a new account

**Multi-device is LIVE on prod** (verified 2026-09-13: `/version` → `0.2.41 / 49c77c10`,
`/version.json` → `0.2.41 / 9d13d25`; `git merge-base --is-ancestor 2c553b2 <each>` passes for the
PR #144 merge). The previous "NEW ACCOUNTS ONLY / one account works on one device" text was written
while #144 was merged-but-undeployed and is now simply false.

The model (`docs/design/multi-device.md` §1, §5.1, §8): one account = **1 primary + up to 2 linked
= 3 concurrent devices**; adding one REQUIRES physical possession of the primary (QR + SAS word
comparison; the QR is a link step, never a credential — I3). **Logging in does not create a
device**: `resolveLoginDeviceId` (`backend/src/auth/auth.service.ts:158`) hands a fresh install the
LIVE PRIMARY's id.

Two starting states, and they do NOT behave the same:

1. **Account already enrolled** (linked devices enabled on the web): the §6.1 registration lock
   refuses a password-only identity replacement, and `AuthGate` renders `DeviceLinkGateScreen`
   (`frontend/lib/screens/device_link_gate_screen.dart:24-35`) — link here, or take the
   recovery-phrase / reset path. This is the happy path.
2. **Account NOT enrolled** (linking never enabled): §6.1 is not armed (§8, amendment (lxxiii)), so
   the phone silently re-mints the identity **into the primary slot** — and because every client
   re-uploads its key bundle on EVERY socket connect (`encryption_provider.dart`), two live devices
   then clobber each other's identity epoch on every reconnect: a permanent flip-flop that burns
   both sides' prekeys and spams identity notices. **Enable linking on the web FIRST, then link the
   phone.** Never install-and-log-in on an un-enrolled account while the PWA is still live.

History does NOT transfer on link (Phase 4 "history-on-link" is unbuilt, §9): the phone starts
empty and fills from new traffic. Old history stays readable on the device that already has it.

**NOT device-proven** — nobody has run the link ceremony from a release APK yet; that is smoke
checklist item 6. Until item 6 passes on a real phone, this is the wording we INTEND to ship, and
it must not be sent to a user. Use EXACTLY this:

> Umbra for Android joins your existing account as a second device — **do not create a new
> account**. On the web app first: turn on linked devices. Then install the app and log in — **the
> phone will show a QR code**, with the same code underneath as text you can copy. On the web app,
> open your devices screen and **scan the code off the phone's screen** — or, if that machine has
> no camera (most desktops), paste the text code there instead. Both screens then show the same
> short list of words: check they match, and approve on the web app. Your old
> messages stay on the web — the phone starts fresh and receives everything sent from then on. Up
> to three devices per account. **Never delete your web account and never clear the browser's site
> data.** iPhone users: keep using the web app as-is.

A Play listing must state **up to 3 devices per account, and adding one needs the first device in
hand** — the old "one account, one device" claim must not ship.

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
