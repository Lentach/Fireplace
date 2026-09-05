# 2026-09-06 — Video nits round 2: dead tap on the playing clip, Telegram chrome, swipe-down, resume fix

Branch `feat/video-nits` (worktree `Desktop/fireplace-video`), head `4aa4f84`, PR #163. Branch test on prod:
`test/video-nits-0.2.3` (worktree `Desktop/fireplace-prodtest`) = live `5d669ce` + cherry-picks; builds 0.2.7 → **0.2.11
(`d4cbc27`) LIVE**, smoke passed on every build. Backend untouched `0.2.0 / 5ffef19b`. Rollback = redeploy `5d669ce`.

## Owner reports this round

1. From 0.2.8 on, inline autoplay WORKS on both phones (the earlier "blurred with play button" is closed — the size
   guard or the diag-build cache bust; no log arrived, so the exact 0.2.5–0.2.7 cause is unrecorded).
2. Tapping the (playing) bubble does not open fullscreen, Android and iOS.
3. Mute button sat bottom-right where the bubble's time/ticks live — move to top-left like Telegram, one pill with the
   remaining time.
4. Fullscreen like Telegram's paused view (screenshot): back chevron, sender + day header pill, big play/pause,
   `elapsed — slider — remaining` pill; swipe-down to dismiss; loop at the end.
5. "You can test it — you have a browser and an emulator, see why it doesn't work." Correct; done below.

## Emulator reproduction (Pixel_7 AVD, Chrome 113, CDP `Input.dispatchTouchEvent` = a real finger in the DOM)

Capture-phase DOM listeners on `pointerdown`/`click` record the target of each touch:

| build | tap on | DOM target | result |
|---|---|---|---|
| 0.2.8 | playing bubble | `VIDEO[flt-platform-view]` | nothing |
| 0.2.8 | paused poster (control) | `FLUTTER-VIEW` | fullscreen opens |
| 0.2.9 (`PointerInterceptor` as a sibling, ancestor `GestureDetector`) | playing bubble | `DIV[flt-platform-view]` | nothing |
| 0.2.10 (gesture target = the interceptor's CHILD) | playing bubble | `DIV[flt-platform-view]` | **fullscreen opens** (one `<video>` 412×733, playing, resumed) |

**Cause 1:** on Flutter web `video_player_web` mounts the `<video>` as an `HtmlElementView`; the engine does not deliver
pointer events whose DOM target sits inside a platform view, so the bubble's `GestureDetector` never fired on a playing
clip. Every earlier "fullscreen works" check tapped BEFORE playback started (canvas poster) — a blind spot in the
harness, not a flake.

**Cause 2:** `pointer_interceptor` (flutter/packages) fixes cause 1 with an `isVisible: false` div the engine forwards —
but that div is itself a platform view, and `PlatformViewRenderBox`'s recognizer is the innermost hit-test entry, so
the arena sweep hands it the pointer and an ANCESTOR detector loses. The package is designed for its *child* to be the
target. Rule: **the tap/drag handler is the interceptor's child**, in the bubble and in the fullscreen stage
(`_stageGestures` is used twice there: around the whole surface for the letterbox bars, and as the interceptor's child).

**Third finding, measured while verifying:** fullscreen at 27.4 s, dismiss → inline restarted at 21.7 s = the handoff.
`showDialog`'s future resolves at pop; the view's `dispose` (which reported the position) runs after the exit
transition, so `lastPosition` was always null. Reported from `PopScope.onPopInvokedWithResult` now (every route: chevron,
system back, swipe). 0.2.11 measurements: swipe at 10.0 s → inline 11.5 s after 2.5 s; chevron at 7.0 s → 8.2 s.
Not unit-testable without session injection into `_VideoFullscreenView` — on-device proof only.

## Built

- `video_message_content.dart`: `PointerInterceptor(child: GestureDetector(onTap: _openFullscreen))` over the playing
  stage; `_RemainingMutePill` top-left (`0:12 🔇`, whole pill toggles mute, key `video_inline_mute_toggle`);
  `_DurationChip` moved top-left; `_OverlayPill` takes an optional trailing icon. Bottom corners belong to the bubble.
- `video_fullscreen_view.dart`: back chevron top-left (key `video_fullscreen_close` kept), header pill `Ty` /
  `senderUsername` + `MessageDateSeparator.dayLabel · HH:mm` (`dayLabel` lifted to a public static), seek bar in a scrim
  pill with the right label counting DOWN (`video_remaining_label`), swipe-down dismiss (`_dragDy`; dismiss at 22 % of
  height or a >700 px/s fling; backdrop alpha and stage scale follow the finger; chrome hidden while dragging; the dialog
  barrier is transparent so the view paints its own backdrop), `setLooping(true)`, `PopScope` position report.
- ARB: `videoSenderYou` (`Ty`/`You`). New dep `pointer_interceptor ^0.10.1+2`.
- Tests: `video_message_wire_test.dart` + long-swipe dismisses / short-swipe snaps back. `test/widgets/message` 140 green,
  analyze clean. (Also this round, earlier: diag keyed on `step:reason`; `maxCiphertextBytes` = maxBytes + 16 with the
  +16/+17 boundary test.)

## Device verification on 0.2.11 (prod, emulator)

Tap on playing → fullscreen; screenshot shows chevron, `Ty` / `Dziś · 04:52`, pause glyph, `0:08 ▬▬ 0:33` pill; swipe-down
returns to the inline bubble playing at a continuous position; chevron closes (chrome must be visible — auto-hide is
3 s); fullscreen looped (28.7 → 7.0 on a 41 s clip); inline pill `0:41 🔇` top-left, `04:52 ✓✓` bottom-right, bottom-left
empty; paused bubble shows `0:22` top-left.

## Traps

- Emulator Vulkan backend died mid-session (`VK_ERROR_DEVICE_LOST`, `adb devices` empty): `hub restart emu-video`; Chrome
  and the PWA session survived.
- A stray `data:` noise tab makes `/json/list` hang the whole JS kernel (30 s kill) — close it via `/json/close/<id>`.
- `screenrecord` cannot produce a dense clip off a static or noise screen (<0.6 MB at 20 Mbps); the >8 MB / HEVC cases
  remain untested here. Cap edge covered by the unit test instead.

## Open

- iOS: not verified here (no device). The interceptor path is the same DOM mechanism on Safari; owner to confirm.
- Longer videos plan (WebCodecs transcode first, chunked streaming later) — after owner accepts this round.
- Merge path unchanged: master's red e2e first, PR #163, PATCH bump on master, backend deploy before web.

## Second half of the day: the 429, the arbiter, the animated dismiss

**Owner after 0.2.11:** "videos send with lag, plays once after send then blurred; tapping → failed to load; reopen chat → plays once → broken; a second clip to someone else blurred too." Desktop pair (`vnitdesk2`→`vnitdesk3`, 8 MB) on 0.2.11: send 3.4 s, both ends autoplay, fullscreen, no errors — so the phone was hitting something the desktop never did. **0.2.12** put `stage · bytes · error` under "Nie udało się załadować wideo" (`VideoPlaybackSession.failureDetail`, key `video_failure_detail`); the owner's screenshot read **`fetch_decrypt 0B Exception Media fetch failed 429`**.

**Cause:** `GET /media/msgs/:filename` (every image AND video blob) had `@Throttle 60/min` per client IP (`HttpThrottlerGuard` keys on `X-Real-IP`) and no cache header, so every load hit the origin. Inline autoplay multiplied loads (scroll-in, fullscreen open, fullscreen close — the dialog releases the inline session by design — and the sender's optimistic→real State replacement), the chat's images share the bucket, and both phones share the WiFi IP. After the 60th blob in a minute every load was 429 until the window reset → "plays once, then broken".

**Fix (backend, `media.controller.ts`):** 600/min and `Cache-Control: private, max-age=31536000, immutable` (UUID-named ciphertext, never rewritten; nginx passes Cache-Control through the X-Accel response — verified on a live blob: `X-RateLimit-Limit: 600`, header present). Spec pins both (`THROTTLER:TTLdefault` / `THROTTLER:LIMITdefault` metadata keys — the throttler suffixes the name). Deployed by the agent on the owner's "deploy it as you always do": VM `git checkout test/video-nits-0.2.3 && ./deploy-backend.sh` → `/version` `0.2.12 / 0df8dd82`, healthy in 10 s. There was NO backend delta between live `5ffef19b` and `5d669ce`, so this shipped exactly one change.

**Arbiter (owner: last video blurred, previous one playing on chat open):** `request(owner, onRevoke, {required int priority})` → bool, priority = `createdAt.millisecondsSinceEpoch`. Higher revokes, lower is denied; the bubble sets `_deniedByNewer` and the arbiter's next release re-evaluates it (post-frame, outside the notifier). **First cut looped:** every bubble reacted to every release, so a bubble whose own load failed re-requested every frame (`pumpAndSettle` timeouts caught it) — exactly the pattern that would have hammered the throttle. Only a denied bubble reacts now. Tests: arbiter unit (priority, denial, equal-priority, release-notifies-once), widget (newer first in tree, older denied, older granted after the newer's failed load, newer never retries).

**Swipe-down:** `_slide` AnimationController; release → easeIn to the bottom (80–220 ms by fling speed) then pop, or easeOutCubic back in 220 ms; `MediaQuery.disableAnimationsOf` → 0 ms; `_dismissing` latch. Measured in the desktop pair: y 236 → 296 → 344 → 402 → 468 → 590 → 673 → 764 → off in ~230 ms, stage width 336 → 270, inline resumes underneath.

**Re-entry proof (sender's chat, two clips):** back → re-enter ×3, the bottom (newest) clip plays every time.

**Not app bugs:** Android gallery "Gotowe" greyed with nothing picked = Android's photo picker (browser `<input type=file>`); back cancels. Heavy video lag on the PWA = whole-file decrypt in RAM + blob URL + no streaming; native app is the right home for long/heavy clips (owner's call, agreed).

**Harness notes:** registration is 10/h per IP — the desktop pair burned it (`vnitdesk2..5`; `vnitdesk4` never registered); fresh incognito contexts are KEYLESS for existing accounts under the live 0.2.3 gate, so use a freshly registered account as the sender. The emulator did not boot under `-gpu swiftshader_indirect` within 10 min (adb never listed it) — stopped; the desktop pair carried the proof. Suite **1768 / 10 skipped**.
