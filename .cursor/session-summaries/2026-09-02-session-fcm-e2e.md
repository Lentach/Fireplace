# 2026-09-02 — FCM enabled on prod and PROVEN end-to-end on the Pixel_7 emulator; app-shell no-cache shipped; emulator "lag" root-caused (8 GB guest on a 16 GB host)

**Date:** 2026-09-02 (session continued from 08-30/09-01 rebrand rollout)

## Outcome

- **Production FCM works end to end.** A real message sent from the web app (`test_web_sender`) to a
  fresh APK account (`test_apk_receiver`, throwaway, id 2683-tagged) produced a native Android
  notification on the emulator with the app in the background: hex `ic_stat_umbra` in the status bar,
  shade card **"Umbra · now / Umbra / You have a new message"**. Screenshots (gitignored):
  `.planning/push1.png` (status bar), `.planning/push2.png` (shade). Device-side proof:
  `FLTFireMsgReceiver: broadcast received for message` in logcat at delivery time. Server-side proof:
  first-ever row in prod `fcm_token` (platform `android`, created at login), **zero**
  `FCM multicast send failed` / `Firebase Admin init failed` lines in the 15 min around the send, and the
  token was NOT pruned as stale. (The success line `FCM push attempted … success=1` is `logger.debug`
  and prod keeps error/warn/log only — do not go looking for it in `docker logs`.)
- **`FIREBASE_SERVICE_ACCOUNT` is set in `~/fireplace/.env`** (delivered as an scp'd fragment appended
  server-side, never inlined through ssh quoting; backend recreated with
  `docker compose -f docker-compose.prod.yml up -d backend`). Boot log has `Firebase Admin initialized`.
  **The local Downloads copy of the service-account JSON is DELETED** — the only copies are the Firebase
  console and the VM `.env` (chmod 600). Both repos are public; the key must never touch git.
- **App-shell `Cache-Control: no-cache` is LIVE** (nginx `location /` block, same pattern as
  `/welcome/`): `/`, `/index.html`, `/flutter.js`, `/version.json`, `/main.dart.js` all answer
  `cache-control: no-cache` + ETag. Closes the "old app for hours after deploy" trap from 08-14. Config
  backup `/home/ubuntu/nginx-fireplace.bak.1788300884`. `add_header` inheritance was checked first: the
  file has no server-level `add_header`, so nothing was shadowed.

## The trap that ate the previous attempt: the installed APK was pointing at LOCAL docker

The AVD already had `com.fireplace.app` installed with an account (`vtest_a`) that did **not exist on
prod**, and every app launch produced `SessionRefreshTransientException` with zero requests reaching
nginx. Pulled the installed base.apk and read the kernel blob: `String.fromEnvironment('BASE_URL')` had
been compiled as **`http://10.0.2.2:3000`** and `GIT_COMMIT` as `dev` — i.e. that APK was a
local-backend build, not the prod build the 08-30 handoff claimed. **A debug APK carries its dart-defines
in `assets/flutter_assets/kernel_blob.bin`; verify with a byte search for the origin before trusting
any "built against prod" claim.** Rebuilt with
`flutter build apk --debug --dart-define=BASE_URL=https://fireplace.ignorelist.com --dart-define=GIT_COMMIT=<sha>`
(auth footer then shows the sha; kernel blob contains the origin and no `10.0.2.2`).

Other device-side gotchas hit on the way:
- `POST_NOTIFICATIONS` was `granted=false` with `USER_FIXED` on the stale install — `requestPermission`
  returns denied and `PushService.initialize` returns early **silently** (`catch (_)` at the end of the
  method swallows everything). `pm clear` + `pm grant com.fireplace.app android.permission.POST_NOTIFICATIONS`
  before the first login avoids the dialog dance on the emulator.
- Usernames are `[A-Za-z0-9_]` only (the register form says so after submit); `test-*` names are rejected,
  use `test_*`.
- Messaging requires an accepted invite first (Kontakty → `username#tag` → Wyślij zaproszenie; accept
  in the APK under the local-node badge), then Wiadomość from the contact sheet. Only messages push
  (`PushNotificationCoalescingService.notify`); invites do not.
- `adb shell input text` into a Flutter field while the keyboard is up shifts the layout ~270 px; take a
  screencap after the first tap and re-derive coordinates.

## Emulator "lag" — root cause, not GPU

Owner: *"emulator shouldn't lag that hard, something is wrong with it."* Correct. Findings:
- `~/.android/avd/Pixel_7.avd/config.ini` had **`hw.ramSize=8192`** on a **16 GB** host. With Steam,
  the browser tool and a Gradle build alive, Windows had **~1 GB free** and CPU at 100%; `qemu-system-x86_64`
  sat at ~6 GB working set and was being paged — that is the Pixel Launcher ANRs, the "vanish mid-wait",
  and most likely the broker-abort/exit-2147483647 launch failure from 08-30.
- Hypervisor and GPU were fine all along: `emulator -accel-check` → WHPX usable; the emulator log shows
  `NVIDIA GeForce GTX 1070 Ti` selected for GLES+Vulkan. **`-gpu host` is correct; never
  `swiftshader_indirect`.**
- Changed: `hw.ramSize=3072`, `hw.cpu.ncore=4` (i7-7700 has 4c/8t). Result: cold boot to
  `boot_completed` in ~14 s, app to auth screen in ~15 s (was 45–90 s), no ANRs for the whole e2e run.
  Launch line unchanged:
  `emulator.exe -avd Pixel_7 -no-snapshot-load -no-audio -gpu host`.

## Verification ledger

| Claim | Evidence |
|---|---|
| Push delivered on device | `.planning/push1.png` (status-bar hex icon), `.planning/push2.png` (shade card), logcat `FLTFireMsgReceiver: broadcast received for message` |
| Token registered on prod | `select … from fcm_token` → 1 row, platform `android`, created at APK login |
| Backend send healthy | 0 hits for `FCM multicast send failed|Firebase Admin init failed` in the send window; token not pruned |
| APK targets prod | kernel blob contains `https://fireplace.ignorelist.com`, 0× `http://10.0.2.2:3000`; footer shows the build sha |
| App-shell no-cache | `curl -I` on `/`, `/index.html`, `/flutter.js`, `/version.json`, `/main.dart.js` → `cache-control: no-cache`; `nginx -t` ok before reload |
| Downloads key gone | `rm -v` output |

## Later the same day — `.jks` backup, first signed release APK, emulator pre-smoke

- `.jks` backed up off-PC (USB plain copy + AES-256 `.enc` in the owner's cloud), restore proven by
  signing an APK from the USB copy → production cert. Fingerprints + recipe in
  `docs/runbooks/android-release.md` §"Backing it up".
- `build-android.ps1` reads the Giphy key ONLY from `$env:GIPHY_API_KEY` (dot-source
  `deploy-web.config.ps1` first). Built `0.1.24` / versionCode **10024** from `feat/video-messages`
  `1f9d96f` (what prod web runs — owner: "the number doesn't really matter"), release cert, 16 KB ELF
  10/10, SHA256 `743612453b44ff2a961760cb010a4dac9b87868594080517c9c1ac1a2bc40ef1`.
- Emulator pre-smoke on prod, release build: `test_apk_release` (id 106) registered → `fcm_token` row;
  invite from web accepted; `am kill` → `pidof` empty, `stopped=false`; web message → NEW process,
  `FLTFireMsgReceiver: broadcast received for message` → `FlutterFirebaseMessagingBackgroundService
  started!` → shade card "Umbra · You have a new message"; tap cold-starts `MainActivity`.
  Screenshots `.planning/push-release-shade.png`, `.planning/push-release-statusbar.png`.
- **Trap 1:** the first attempt used `am force-stop` → package in Android *stopped state* → FCM
  dropped silently. Kill = `am kill` / swipe-away only.
- **Trap 2:** release `MainActivity` sets `FLAG_SECURE` → `screencap` rc=1 while the app window is
  live. Verify via logcat / prod DB / shade with the app dead.
- **versionCode floor 10024** — master is 0.1.21 → 10021 is a downgrade; bump past 0.1.24 always.
- Runbook wording changed to NEW ACCOUNTS ONLY (owner green-lit).

## Still owed (owner decisions / actions)

- **Release waits for the owner's PIN/passcode-to-enter-app feature** → bump version, rebuild,
  re-run emulator pre-smoke, real-phone smoke (runbook items 2/4/5/6 + tap opens the right chat),
  GitHub Release with SHA256 + new-accounts wording.
- Domain: NOT an APK blocker (see LATEST 09-02); owner's pick pending.
- GitHub repo renames → then remotes, landing README link, landing `CLAUDE.md:5`, dependabot comment.
- Kaspersky stays off by owner's choice — exclusions are no longer a gate.
- Personal iOS reinstall for the ember icon.
- Throwaway prod accounts (`test_web_sender` 104, `test_apk_receiver` 105, `test_apk_release` 106)
  can be deleted from Settings whenever.
