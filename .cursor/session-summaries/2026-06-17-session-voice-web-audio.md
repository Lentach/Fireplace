# Voice playback via Web Audio — no iOS media-control card (0.0.60)

**Date:** 2026-06-17

## What was done

Follow-up to the ping fix (same branch `fix/ios-ping-media-session`): voice-message
**playback** on web also showed an iOS media-control card, because `PlaybackController`
played through `just_audio`'s `AudioPlayer` → HTML `<audio>` element → MediaSession.
User explicitly requested removing it for voice too.

**Fix:** introduced a `VoicePlayer` abstraction and moved `PlaybackController` onto it.
- `widgets/audio/voice_player.dart` — interface (`VoicePlayerState{playing,completed}` +
  streams + play/pause/stop/seek/setSpeed/setFilePath/setUrl/setAudioBytes/dispose) and a
  `createVoicePlayer()` facade (conditional import: native, else web).
- `voice_player_native.dart` — thin 1:1 just_audio wrapper. **Behaviour identical** to before
  (keeps Android OS media controls). `setAudioBytes` throws `UnsupportedError`.
- `voice_player_web.dart` — Web Audio engine on a **shared** `AudioContext`
  (`AudioBufferSourceNode` ⇒ no MediaSession ⇒ no iOS card). One-shot source, so:
  play/pause = stop + restart-at-offset; seek = new source at offset; speed = `playbackRate`
  (pitch-shifts, same as just_audio-web today); position = ticker off `ctx.currentTime`;
  completion = active source's `onended` (identity-guarded so deliberate stops don't fire it).
  iOS gesture-unlock: `resume()` on every window gesture (installed in ctor) — first playback
  resumes post-await (after fetch+decode), which iOS may reject. `setFilePath`/`setUrl` throw.
- `PlaybackController` — rewritten to drive `VoicePlayer` (was `AudioPlayer`). Public API
  (builder signature, `message`, `clearAudioCache`) unchanged. Added `playerFactory` test seam.
  **Web load is now bytes, not a blob URL:** `_loadAndPlayAudio` web branch `fetchMediaBytes`
  → decrypt (when keyed) → `setAudioBytes`; the legacy unencrypted/Cloudinary case also fetches
  bytes (avoids the CORS wall a bare `fetch`+`decodeAudioData` would hit). `utils/audio_blob_url_*`
  are now unused — **left in place** (safe to delete in a follow-up; `audio_mime.dart` kept, has its
  own test). `audio_mime` is now referenced only by its test.
- Version `0.0.59 → 0.0.60`.

**TDD:** `playback_controller_test.dart` written first (RED: no `playerFactory` param). Drives a
fake `VoicePlayer`: play→play()+isPlaying, second tap→pause(), speed cycle 1→1.5→2→1 calls
setSpeed, waveform-seek maps tap fraction to duration, and a two-controller coordinator test
(starting B pauses A). The Web Audio engine itself is DOM-only → invisible to `flutter test`
(device QA), same as the ping.

## Key files
- `frontend/lib/widgets/audio/voice_player.dart` (new — interface + facade)
- `frontend/lib/widgets/audio/voice_player_native.dart` (new — just_audio wrapper)
- `frontend/lib/widgets/audio/voice_player_web.dart` (new — Web Audio engine)
- `frontend/lib/widgets/audio/playback_controller.dart` (rewritten onto `VoicePlayer`)
- `frontend/test/widgets/audio/playback_controller_test.dart` (new)
- `frontend/pubspec.yaml` (0.0.60); `CLAUDE.md` (voice gotcha + conditional-import list + limitation)

## Verification (commands + results)
- `flutter analyze` (5 voice files incl. web engine) → **No issues found**.
- `flutter build web --no-wasm-dry-run` → **Built** (Web Audio engine + js_interop compiles).
- `flutter test test/widgets/audio/playback_controller_test.dart` → 5 passed.
- `flutter test` (full) → **384 passed** (was 379 after ping; +5).

## Notes for next session
- **UNVERIFIED ON DEVICE = NOT DONE.** Real-iPhone PWA matrix owed for voice: play a voice note →
  audio plays, waveform progresses, **NO** media-control card in Control Center / lock screen;
  pause/resume; tap-to-seek; 1×/1.5×/2× speed; one-at-a-time (starting another stops the first);
  pause-on-record + stop-on-leave. Regression: native (Android) voice unchanged; first-play-after-load
  isn't silent (gesture-unlock); a phone-call interruption mid-play then resume still works.
- Both fixes (ping + voice) ride branch `fix/ios-ping-media-session` → one `.\deploy-web.ps1` tests
  both. Frontend-only; does NOT auto-deploy; live only after merge to `master`.
- Orphaned `utils/audio_blob_url_{stub,web}.dart` (+ now `audio_mime` only used by its test) — candidate
  cleanup, deferred to keep this diff focused.
