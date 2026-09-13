# The APK is on the owner's phone, linked to bob208 as device #11, and the sideload update path is proven forward-only and data-preserving

**Date:** 2026-09-14 · **Version:** 0.2.43 → 0.2.44 · **Tiers deployed:** none (prod web/backend still 0.2.41; only the phone runs 0.2.44)

## What was done
- Built + shipped **0.2.43** (`aae1defe`, versionCode 20043, SHA256 `40f02824…`) and then **0.2.44** (`c7bcee7e`, 20044, `20f46b67…`). Signer cert MEASURED both times: `8e9a6bf3…5cdf405d` = record-of-truth.
- Installed on the owner's Mi 11 Lite 5G (`f849cc68`, Android 11) — nothing was installed before, so 0.1.24 never lived there. Login as `bob208` hit the §6.1 lock on real hardware; link ceremony committed **device #11 `android`**.
- **Found and fixed a user-visible defect**: a freshly linked device's ENTIRE chat list printed raw `[encrypted]`. `conversation_tile.dart:_lastMessagePreview` never consulted the 0.2.43 sentinel mapping, and `displayAsEncryptedPlaceholder` (needs a legacy ciphertext column) misses every new-model row.
- Added `sentinelPreviewText()` (`utils/message_display_text.dart`) — the preview-side counterpart to `sentinelDisplayText()`; `[encrypted]` → NEUTRAL encrypted label (a waiting row must not be accused), the other three sentinels get their honest sentences. Tile delegates AFTER the media branches (keyed media keeps `content == '[encrypted]'` for life).
- Proved the **update path** twice (emulator, then the owner's phone): `adb install -r` over a logged-in install preserves session, identity and history; `identity_change_audit` stays empty, so no peer is asked to confirm a safety number.
- Recorded in `docs/runbooks/android-release.md`: 0.2.43/0.2.44 build records, the emulator pre-flight, the phone pre-install state check, versionCode floor 10024 → **20043** (now 20044), and the ⛔ forward-only/no-rollback rule.
- Corrected two over-strong doc claims: "primary must be an INSTALLED PWA" (that gate is the `notEnrolled` branch only; an enrolled account can approve from a plain tab — `holdsDak` is the real gate), and a trap that credited an a11y toggle for populating `uiautomator` dumps (A/B-measured: it changed nothing; the cause was grepping `text=` instead of `content-desc`).

## Key files
- Edited: `frontend/lib/utils/message_display_text.dart`, `frontend/lib/widgets/conversation_tile.dart`, `frontend/pubspec.yaml`, `CLAUDE.md` (test count 2120 → 2126), `docs/runbooks/android-release.md`, `docs/agents/traps.md`
- New: `frontend/test/widgets/conversation_tile_sentinel_preview_test.dart` (6 tests)
- Read only (load-bearing): `providers/messaging/messaging_provider.{decrypt,events,history,send}.dart`, `widgets/audio/playback_controller.dart`, `backend/src/messages/{messages.service,message.mapper}.ts`, `backend/src/chat/services/chat-conversation.service.ts`

## Verification
- `flutter test` **2126 passed / 14 skipped**; `flutter analyze --no-fatal-infos` at the 3172-info floor; count verifier OK. New test is red-green: 4 of 6 fail on the pre-fix tile (proven by reverting both files), the 2 guards pass both ways.
- CI on `c7bcee7e`: **6/6 green** (`gh api …/commits/c7bcee7e/check-runs`). `4831fff8` is docs-only.
- Phone, measured: install `Success`; on-device `base.apk` hash = the built APK (both builds); `versionCode 20043 → 20044` with `firstInstallTime` PRESERVED; device #11 `lastSeenAt` advanced 43 s after the upgrade with NO login; key bundle re-uploaded with the account identity key `BQLKjKiYsGSO…` shared by devices 1/5/11; `identity_change_audit` 0 rows throughout.
- Gate on real hardware (logcat): `[EncryptionService] Identity incomplete — refusing to regenerate` + `E2eIdentityIncompleteException`.
- E2E on prod: text both directions, voice both directions (`24385` in / `24386`, `24387` out), self-sync to the iOS PWA primary seen AND heard by the owner. Pre-link history renders as the `historyBeforeDeviceLinked` pill.
- **0.2.44 fix confirmed ON SCREEN** (a11y tree): every previously-raw row now reads `Wiadomość zaszyfrowana` / `Wiadomość głosowa`; zero raw `[encrypted]` left in the list.
- **Push with the app KILLED — PASS, 3.54 s** to `Start proc … FlutterFirebaseMessagingReceiver caller=com.google.android.gms`, 3.65 s to `FLTFireMsgReceiver: broadcast received`, measured against the peer's server `createdAt` `23:01:51.931Z` with the device clock 585 ms behind and corrected. Tap opened the RIGHT chat and the row decrypted. No other message existed between 23:00:00 and 23:01:50, so the pairing cannot be confused.
- **Image both directions — PASS:** IMAGE `24390` phone→peer and IMAGE `24392` peer→phone, both with `mediaUrl`, owner confirmed images work. First runtime proof of the 16KB-patched `libwebcrypto.so` on a real ARM device (encrypt-on-send AND decrypt-on-receive). VIDEO `24391` (peer→phone) arrived with a `mediaUrl` and an envelope for device #11 but its RENDERING was never confirmed — the owner was answering an images-only instruction; treat video as arrived-but-unverified.
- **NOT verified:** the un-enrolled flip-flop drill (item 7) — deliberately skipped, it would damage the peer account; prod web/backend untouched at 0.2.41.
- **Disappearing messages: arming VERIFIED, disappearance NOT OBSERVED.** Two 60 s rows (`24393`/`24394`) sat at `DELIVERED` / `expiresAt` NULL for 7 min because the timer is **read-triggered** (`messages.service.ts:811-813`), and the peer never opened the thread — correct behaviour, not a defect. Never-read backstop = 1 day (`disappearing.constants.ts:8`); expired rows are HARD-deleted by an `EVERY_MINUTE` cron with media unlinked first (`message-cleanup.service.ts:39-99`). Owed: read as the peer, then confirm the rows leave Postgres and both screens.

## Notes for next session
- Owner-owed: publish the APK as a GitHub Release or keep hand-delivery (PEPK/cert one-way door, trap); deploy prod web 0.2.41 → 0.2.44 so the primary matches the phone; Play vs sideload-forever.
- The "0 s voice note" is **CLOSED, not a defect**: the label is `position/duration` and the a11y tree reads `0:00/0:11` for the 11 s clip (`0:00/0:06`, `0:00/0:04` for the owner's own). The leading `0:00` is playback POSITION. When a user reports a "0 second" clip, ask what the WHOLE label said. Incidental: that thread has disappearing messages ON at 2 days, which explains the "bubble disappeared" impression.
- Dates are now consistent: the 0.2.43/0.2.44 build records and trap `:79` all read `2026-09-14` (local). The 0.2.41/0.2.42 records keep `2026-09-13` because that is genuinely when they were built — do NOT "fix" those.
- Traps (also in `docs/agents/traps.md`): forward-only updates / no rollback on a linked device; a patch install over the top loses nothing; list previews are NOT a body surface; enrolled accounts can approve a link from a plain tab; MIUI blocks `adb shell input` (`INJECT_EVENTS`) so the owner drives and the agent observes; an "empty" `uiautomator` tree is a `text=` grep, not a missing a11y service.
