# 2026-09-01 (evening) — Telegram-style video player + cap UX (branch `feat/video-messages`)

## Owner report driving this session
"Video displays correctly now but I can't pause or stop it — there is no indicator — same in fullscreen. It should be a player like Telegram's. Also do something about the 20 MB cap; if it's hard on PWA we could do it on native."

Root cause of "can't pause": in-place bubble playback DID toggle pause on tap, but with **zero visual state** (no pause glyph, no progress), and the bubble sits inside the message row's swipe/long-press gesture wrapper that is already proven to eat taps (same arena problem that killed double-tap-to-fullscreen). Invisible state + unreliable taps = "I can't pause it."

## Decisions (owner answered a structured questionnaire)
- **Bubble model: Telegram** — single tap opens the fullscreen player; the bubble is a static poster. In-place playback REMOVED.
- **Fullscreen controls:** owner left the control-set question blank; recommended baseline shipped — center play/pause, seek bar with current/total timestamps, auto-hiding chrome. Mute/speed NOT built.
- **Cap strategy: native first (roadmap move 4)** — on-device transcode on Android/iOS, PWA keeps 20 MB. Plan below; NOT implemented this session.
- **Cap UX:** oversize error now names the actual size; overlong error names the actual duration.

## Shipped (frontend only, wire contracts untouched)
- `video_message_content.dart` — now **stateless**: poster (ThumbHash) + play badge + duration chip; tap → `showVideoFullscreen`. No `VideoPlaybackSession`, no `VideoPlayerController`, expand button removed (`video_expand_button` key is GONE — tap does the job). Kills the gesture-arena fight and the "N live players" hazard at the root.
- `video_fullscreen_view.dart` — Telegram-shaped player:
  - Center **play/pause button** (`video_play_pause` key), the missing indicator.
  - Bottom bar: `m:ss` position (tabular figures), draggable seek **Slider**, `m:ss` total. Originally shipped as `VideoProgressIndicator(allowScrubbing: true)`, but the owner could not seek at all on his phone — the package scrubber is an 8 px strip with no thumb. Replaced with a Material `Slider` (`video_seek_slider` key): visible thumb, 48 px-tall gesture surface, drag cancels the hide timer (chrome never fades under the finger), thumb + position label follow the finger via `_dragMs`, controller seeked live during the drag, `onChangeEnd` re-schedules auto-hide if playing. Inert until the controller reports a duration.
  - **Chrome auto-hides after 3 s while playing** (`_kChromeAutoHide`); tap on the stage toggles CHROME, never playback — playback changes only via the button, so it is always visible when it changes. Pause/end pin the chrome visible. Hidden chrome is `IgnorePointer`ed so the invisible close button cannot swallow the reveal tap.
  - Rotation-aware aspect ratio + one-error-surface branches unchanged.
- `video_playback_session.dart` — doc comment updated (fullscreen-only owner now).
- Cap errors: `videoTooLarge` → "Video is too large ({size} MB, max 20 MB)", `videoTooLong` → "Video is too long ({duration}, max 3 minutes)" (en+pl; **template ARB is `app_pl.arb`** — placeholder metadata must go THERE, gen-l10n rejects en-only metadata). `chat_input_bar.dart:sendPickedVideo` passes actuals. NOTE: the tooLarge branch runs BEFORE the probe (deliberate, probe costs seconds), so it names size only; duration appears in the tooLong branch which runs after the probe.

## Tests / verification
- `video_message_wire_test.dart`: "tap does NOT open fullscreen" + "expand button opens" replaced by "tapping the tile opens the fullscreen viewer"; failure-state tests now tap the tile. Still 10 tests — count unchanged.
- `chat_input_bar_attachment_test.dart`: oversize toast assertion updated to "Video is too large (20.0 MB, max 20 MB)".
- `flutter analyze` clean. Full suite run: 1344 total, one failure = the stale toast assertion, fixed; affected files re-run green; clean full-suite confirmation run kicked off at session end.
- ⚠️ **Not device-verified**: no browser/phone run this session (browser tool needs owner permission per standing rule). The player is plain Flutter widgets — no platform-channel or Safari-specific surface — but the next deploy should eyeball: tap bubble → player opens → chrome fades → tap reveals → pause/scrub work.

## Move 4 plan (native transcode — AGREED direction, not built)
- **ffmpeg-kit is dead** (retired Jan 2025, binaries pulled Apr 2025) — do NOT reach for it.
- Candidates, all native-encoder based (MediaCodec / AVAssetExportSession, no GPL):
  - `light_compressor_v2` — actively maintained 2025, H.264/H.265, target-size mode, progress + cancellation, skips already-low-bitrate sources (min-bitrate check ~2 Mbps) so iOS's ~103 KB/s capture clips are NOT re-crunched. Requires minSdk 24. **Front-runner.**
  - `video_compress` — older, popular, coarser quality control.
  - `flutter_compress` — claims Android/iOS **and web via WebCodecs**; youngest, would need vetting, but is the only route that could eventually lift the PWA too.
- Integration point: `chat_input_bar.dart:sendPickedVideo`, between the extension gate and the size gate — transcode when `bytes > maxBytes` (or unconditionally >720p), THEN size-check the output. Keep the single-probe rule: probe the TRANSCODED file.
- Needs on-device acceptance (emulator recipe exists: `integration_test/video_probe_device_test.dart` pattern, fixture at `/data/local/tmp`, 0644).
- Do NOT raise `maxBytes`/nginx as a shortcut — the 08-31 roadmap note stands: no cap-nibbling instead of moves 4/5.

## Traps rediscovered
- `l10n.yaml` → `template-arb-file: app_pl.arb`. Placeholder `@` metadata in `app_en.arb` alone fails gen-l10n with a confusing "type Object in template" error.

## SECOND HALF (same day, owner granted full tool access + emulator): MOVE 4 SHIPPED AND EVERYTHING DEVICE-VERIFIED

### Move 4 implemented (native transcode, `light_compressor_v2 1.9.1`)
- `lib/utils/video_transcode_stub.dart` (web: unsupported) + `video_transcode_io.dart` (Android/iOS/macOS): oversize clip → temp file → `LightCompressor.compressVideo(targetSizeMb: 18, twoPass: true, isMinBitrateCheckEnabled: false, AudioConfig(96k), app-private storage)` → bytes back, temp files deleted. Any failure returns null → honest "too large" toast. **minSdk 24 already satisfied** (`build.gradle.kts:81`); plugin manifest merges cleanly.
- Gate in `chat_input_bar.dart:sendPickedVideo`: oversize → `_transcodeOversizeVideo` (shows new `videoCompressing` toast en/pl) → re-checks the REAL byte cap on the output → falls back to the sized "too large" toast when null/still-oversize. `ChatInputBarState.debugTranscodeOverride` is the test seam.
- **Physics limit, documented in code:** the solver clamps bitrate to a 2 Mbps floor ⇒ clips ≳70 s can't always reach 18 MB; output re-check catches those honestly. Caps themselves UNTOUCHED (20 MB / 180 s / nginx 21m), per the standing "no cap-nibbling" rule.
- Future option noted: `getVideoThumbnail()` from the same plugin could give native video posters (native probe deliberately has no ThumbHash — bubble poster is plain on Android, pre-existing and documented in `video_probe_io.dart`).

### Verified ON-DEVICE (Pixel emulator, throwaway accounts vtest_a/vtest_b = users 691/692, conv 201, against the RUNNING fireplace-0a docker backend on :3000 — NOT prod)
- **Integration test** `integration_test/video_transcode_device_test.dart` (same `/data/local/tmp/clip.mp4` fixture convention): real MediaCodec pipeline produces decodable, cap-sized output; whole `flutter test integration_test` run **13/13**.
- **Player, full Telegram behavior on the real app** (screenshots in gitignored `.planning/scr*.png`): tap bubble → fullscreen loads+decrypts+plays; center **pause/play glyph flips correctly**; seek bar + `0:06 / 0:07` timestamps advance; **chrome auto-hides after 3 s mid-play** and a stage tap **reveals it without touching playback**; clip end pins chrome with replay; close works. (Those runs were the SENDER viewing own bubbles.)
- **Seek slider verified on BOTH surfaces** (after the owner reported the original `VideoProgressIndicator` unscrubbable): **Android emulator** — drag back to 0:02, drag to start 0:00, paused forward drag to 0:06/0:07, forward drag mid-play seeks and plays out to end (`.planning/sl*.png`). **Web (Chrome via dev `web-server` build, fresh vtest_b session + key reset)** — fresh video sent through the web paperclip, fullscreen: forward drag 0:05/0:07, backward drag 0:01, play resumes from the seek point. Old pre-reset media correctly shows the load-failure surface (key reset, not a player bug). **Glide follow-up (advisory-caught):** the state's `_onControllerTick` gates rebuilds to whole seconds, which would step the thumb at 1 Hz — the bar is now the extracted public `VideoSeekBar` widget (same file) subscribing to the controller via `ValueListenableBuilder<VideoPlayerValue>` (the exact subscription `VideoProgressIndicator` had), with `onScrubStart`/`onScrubEnd` callbacks for the owner's chrome hide-timer. Deterministic coverage in `video_message_wire_test.dart` group "fullscreen seek bar": a never-initialized `VideoPlayerController` (plain ValueNotifier; `seekTo` self-guards) driven 1200 ms → 1700 ms (no second boundary) must move `Slider.value` — **mutation-verified**: removing the ValueListenableBuilder makes it fail; plus a mid-gesture drag test (thumb follows finger via `_dragMs`). Wire file now 12 tests. Incidental: the web-sent clip decrypted and played on Android (web→Android receive works for post-key-reset media).
- **RECEIVE SIDE VERIFIED TOO — closes the 08-31 retraction, for Android↔Android:** logged in as vtest_a (the recipient, separate login) on the emulator; both incoming bubbles rendered LEFT-aligned PORTRAIT with 0:08 chips (envelope geometry decrypted), and the TRANSCODED clip decrypted and PLAYED fullscreen (scr43/scr44). ⚠️ Same physical device for both accounts. **web→Android receive: now verified for post-key-reset media** (the web-sent 18:53 clip decrypted and played on Android during the slider session, line above). **Android→web receive remains unverified**, and the standing `[Decryption failed]` caveat still applies to media sent before a key reset.
- **Transcode E2E through the real UI:** forged a valid **26.75 MB** mp4 (0.5 MB clip + 25 MB `free` box — legal MP4 padding, decodes fine) in `/sdcard/Download`, picked via paperclip → sent. Server blob = **370,774 bytes** (vs 537,759 for the raw small clip) ⇒ transcode ran in-app (`c2.android.avc.encoder` in logcat), output encrypted+uploaded+emitted.
- Suite **1350+10sk green** (CLAUDE.md count line **1350**, confirmed by `verify-claude-frontend-test-counts.mjs` against a saved default-reporter log — the earlier "+1 convention" note was wrong; includes the 2 reconnect regressions below and the 2 seek-bar tests), analyze clean.


### ✅ FIXED (owner-approved shape: "fail the send cleanly") — reconnect-vs-in-flight-upload crash
- Observed live once (first video send, socket reconnect mid-attempt → `Video send failed: Null check operator`, before `SEND_START`); mechanism proven statically after an advisory correction: **`messaging_provider.dart:538` runs `_pendingSendContent.clear()` on EVERY `onConnect(isReconnect: true)`** ("retry was cancelled; orphaned entries serve no purpose") — but an upload IN FLIGHT across that reconnect is not orphaned, and every media path then indexed the map with `!` and crashed into its generic catch.
- **Fix:** new `_pendingAfterUpload(tempId)` guard in `messaging_provider.send.dart` applied to ALL SEVEN post-await write sites — post-upload in image/voice/video/gif/file, AND the two PRE-upload `addAll` sites (image after readAsBytes+preview-extract; gif after the Giphy download — advisory-caught follow-up): entry gone after an await → `_markMessageFailed(tempId, 'Connection was reset during send. Please retry.')`, no emit, no crash. Zero `!` derefs of `_pendingSendContent` remain in `lib/`. Chosen over re-inserting the entry because the reconnect also resets the exactly-once latch — emitting with reset state is the risky branch; a clean manual retry preserves existing semantics.
- **Regression tests:** `messaging_provider_media_send_test.dart` "reconnect during an in-flight media upload" — fake upload service fires `onConnect(true)` mid-upload; video + image sends return false, bubble `failed`, zero `sendMessage` emits. (Old code: throw.)
- Video catch also upgraded to `catch (e, st)` with stack printing (kept).
- ⚠️ Process note: an earlier draft of this entry claimed "nothing removes that entry pre-ack" — WRONG, the grep missed the parent `messaging_provider.dart` (only `providers/messaging/` was searched). Corrected before commit.



### Housekeeping
- Throwaway rows in the 0a dev DB: users 691/692, conversation 201, messages 1598/1599 + blobs. Harmless; delete if the 0a stream minds.
- `/data/local/tmp/clip.mp4` left on the emulator (fixture convention); bigclip/big.mp4 removed.
