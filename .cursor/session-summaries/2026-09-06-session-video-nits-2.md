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
