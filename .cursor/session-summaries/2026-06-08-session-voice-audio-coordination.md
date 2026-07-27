# Voice audio coordination + iOS mic re-prompt investigation (0.0.36)

**Date:** 2026-06-08

## What was done

Two follow-ups after the web voice-playback fixes. Brainstormed → spec → plan → executed inline (6 tasks, TDD, one commit each).

### Part A — audio coordination (feature)
New `VoiceAudioCoordinator` singleton (`services/voice_audio_coordinator.dart`, pure Dart) tracks the single active `ManagedAudioPlayback`:
- **One voice at a time:** `_PlaybackControllerState implements ManagedAudioPlayback`; its `playerStateStream` listener calls `onStartedPlaying(this)` on play (pauses the previous), `onStoppedPlaying(this)` on completed + in `dispose()` (before `_audioPlayer.dispose()`).
- **Pause on record:** `RecordingController.startRecording` calls `pauseActive()` right after the `_isStarting` guard (captures `context.read<MessagingProvider>()` before the new `await`, per use_build_context_synchronously).
- **Stop on leave:** `ChatDetailScreen.dispose` calls `pauseActive()`.
- Semantics: pause (resumable), `_audioPlayer.pause().ignore()`. Voice messages only.
- Also removed the temporary `voice.*` E2eDiagLog diagnostics from `playback_controller.dart` (kept the fetch/decrypt/setUrl load logic).

### Part B — iOS mic re-prompt investigation (diagnostic, temp)
On web, `startRecording` logs `mic.start {loadNonce, permState}` to `E2eDiagLog`:
- `kPageLoadNonce` (`utils/page_load_nonce.dart`) — changes only on a real page reload → tells us if the iOS PWA reloads on nav vs re-asks per getUserMedia.
- `queryMicPermissionState()` (`utils/mic_permission_state_{stub,web}.dart`, Permissions API via `dart:js_interop_unsafe` JSObject `{name:'microphone'}`) → `granted|prompt|denied|unsupported` (iOS Safari typically `unsupported`).
- No change to the recording path yet — pending on-device data.

## Key files
- New: `frontend/lib/services/voice_audio_coordinator.dart` (+ `test/services/voice_audio_coordinator_test.dart`, 4 tests).
- New: `frontend/lib/utils/page_load_nonce.dart`, `mic_permission_state_stub.dart`, `mic_permission_state_web.dart` (+ `test/utils/page_load_nonce_test.dart`, 2 tests).
- Edit: `playback_controller.dart`, `recording_controller.dart`, `chat_detail_screen.dart`, `pubspec.yaml` (0.0.36), `CLAUDE.md`.
- Spec/plan (gitignored): `docs/superpowers/specs/2026-06-08-voice-audio-coordination-design.md`, `docs/superpowers/plans/2026-06-08-voice-audio-coordination.md`.

## Verification
- `flutter analyze` → No issues found.
- `flutter test` → **All tests passed (296)** (was 290; +6 new).
- `flutter build web --release` → `√ Built build\web`.
- 6 commits on master: `90521bd` coordinator core → `3a22507` version+docs. Not yet pushed/deployed at time of writing.

## Notes for next session
- **Deploy 0.0.36** (VM: `git pull && ./deploy.sh && cp -a frontend/build/web/. frontend-build/`).
- **Then gather the iOS mic data:** on the phone PWA, record → leave chat → return → record; read `mic.start` in Privacy & Safety → long-press shield. Compare `loadNonce` across the two records (changed = PWA reloaded; same = iOS re-asks per getUserMedia) + note `permState`. That decides the real mic fix (or confirms it's unavoidable iOS relaunch behavior), after which the temp `mic.start` diagnostic should be removed.
- **Manual QA:** one-voice-at-a-time, pause-on-record, stop-on-leave (web + native). Desktop/`IndexedStack` edge: confirm leaving the chat on the ≥600px sidebar+detail layout still stops audio (no automated integration test covers the wiring).
