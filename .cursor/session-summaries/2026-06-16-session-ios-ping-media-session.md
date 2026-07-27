# iOS ping media-control card — route ping through Web Audio (no MediaSession) (0.0.59)

**Date:** 2026-06-16

## What was done

**Bug (iOS Safari PWA only):** receiving a PING created an unwanted, un-startable
media-control card ("now playing") in Control Center / the lock screen — a stale
media session left behind by the short ping sound.

**Root cause (verified from source):** `PingEffectOverlay._playPingSound` played
`assets/sounds/ping_alert.mp3` through `just_audio`'s `AudioPlayer`, which on web
(`just_audio_web` 0.4.16) plays via an **HTML `<audio>` media element**. Playing
through a media element registers a **MediaSession**, and iOS WebKit then shows
media controls. For a one-shot ping that leaves a stale card the user can't start.
Confirmed the ping is the *only* web sound on this path: the incoming-pop
(`IncomingMessageSoundService`) is gated `if (kIsWeb || !_enabled) return;`, so it
never plays on web and creates no session. Voice playback intentionally left alone
(out of scope; a media card for long-form audio is acceptable/expected).

**Fix:** new conditional-import facade `utils/ping_sound.dart`
(`if (dart.library.html) ping_sound_web.dart` else `ping_sound_stub.dart`):
- **Web** (`ping_sound_web.dart`): decode the asset once (`rootBundle.load` →
  `AudioContext.decodeAudioData`) and play via a transient `AudioBufferSourceNode`
  (`package:web` Web Audio API). An `AudioBufferSourceNode` registers **no
  MediaSession** → no iOS card. Also `primePingSound()` installs a one-shot
  `pointerdown/touchend/mousedown/keydown` window listener that `resume()`s the
  (iOS-`suspended`) `AudioContext` on the first user gesture, so a ping that lands
  outside a gesture can still produce sound.
- **Native/VM** (`ping_sound_stub.dart`): unchanged just_audio playback (the
  original overlay logic verbatim); `primePingSound()` is a no-op.
- `PingEffectOverlay` now calls `playPingSound().ignore()` fire-and-forget and owns
  no `AudioPlayer` — visual/animation/timing untouched.
- `ChatDetailScreen.initState` calls `primePingSound()` (web gesture-unlock; no-op
  native).
- Version bump `0.0.58 → 0.0.59`.

**TDD:** `test/utils/ping_sound_test.dart` written first (RED: facade file missing →
import fails; verified). The Web Audio path is DOM-only and invisible to
`flutter test`; constructing a just_audio `AudioPlayer` in the VM leaks
`MissingPluginException` (internal `init`/`disposeAllPlayers`) into the zone, so the
only VM-safe surface is `primePingSound()`'s no-op (the new production call site in
`ChatDetailScreen.initState`) — that's what the test pins. `playPingSound()` stays
exercised by the existing `ping_effect_overlay_test.dart` (fire-and-forget).

## Key files
- `frontend/lib/utils/ping_sound.dart` (new — facade)
- `frontend/lib/utils/ping_sound_stub.dart` (new — native/VM, just_audio)
- `frontend/lib/utils/ping_sound_web.dart` (new — Web Audio API)
- `frontend/lib/widgets/ping_effect_overlay.dart` (use facade; drop just_audio + `_audioPlayer`)
- `frontend/lib/screens/chat_detail_screen.dart` (`primePingSound()` in initState + import)
- `frontend/test/utils/ping_sound_test.dart` (new)
- `frontend/pubspec.yaml` (0.0.59)
- `CLAUDE.md` (Frontend sound gotcha updated/added)

## Verification (commands + results)
- `flutter analyze` (6 changed items incl. web file) → **No issues found**.
- `flutter build web --no-wasm-dry-run` → **Built build\web** (proves the
  js_interop / Web Audio path compiles via dart2js — the file that matters most and
  is otherwise untestable in the VM).
- `flutter test test/utils/ping_sound_test.dart test/widgets/ping_effect_overlay_test.dart`
  → 3 passed.
- `flutter test` (full) → **379 passed** (was 377; +2 from `ping_sound_test.dart`).
- `flutter test .../settings_screen_version_footer_test.dart` → green after bump.

## Notes for next session
- **UNVERIFIED ON DEVICE = NOT DONE.** Real-iPhone PWA matrix still owed (I can't
  drive an iPhone): receive a ping → (1) sound plays audibly, (2) `PingEffectOverlay`
  visual still fires, (3) **NO** media-control card appears in Control Center / lock
  screen, and (4) none lingers afterward. Regression check: incoming-pop sound, voice
  playback, native (Android) builds unchanged.
- On a feature branch `fix/ios-ping-media-session` + PR — does **NOT** auto-deploy;
  goes live only **after merge to `master`** (VM pulls master). Frontend deploys via
  local `.\deploy-web.ps1` (never build web on the 2 GB VM).
- If the first ping after load is ever silent on iOS: the `AudioContext` hadn't been
  unlocked yet — `primePingSound()` resumes it on the next gesture; an actively
  chatting user almost always has one before a ping. This matches the pre-existing
  iOS audio-unlock constraint (HTML audio had the same gate).
