# Latest session summary

**Date:** 2026-06-08

**Topic:** Two voice follow-ups (brainstorm → spec → plan → inline TDD execution, 6 commits, v0.0.36). **Part A — audio coordination:** new `VoiceAudioCoordinator` singleton (`services/voice_audio_coordinator.dart`) → one-voice-at-a-time (`_PlaybackControllerState implements ManagedAudioPlayback`), pause-on-record (`RecordingController.startRecording`), stop-on-leave (`ChatDetailScreen.dispose`); pause-not-destroy; removed the temp `voice.*` diagnostics. **Part B — iOS mic re-prompt investigation (temp diagnostic):** `startRecording` logs `mic.start {loadNonce, permState}` to E2eDiagLog (web) — `kPageLoadNonce` (changes only on real reload) + Permissions-API `queryMicPermissionState()` — to learn whether the iOS PWA reloads on nav vs re-asks per getUserMedia. `flutter analyze` clean, full suite **296** green, `flutter build web --release` compiles. **Not yet pushed/deployed.** Next: deploy 0.0.36, capture the iOS `mic.start` log on-device, then pick the real mic fix + remove the diagnostic.

→ [2026-06-08-session-voice-audio-coordination.md](./2026-06-08-session-voice-audio-coordination.md)

**Previous:** 2026-06-07 — Fixed web voice playback in two stages. (1) `localhost` media URLs weren't rewritten on web → `rewriteLoopbackMediaUrl` now applies on all platforms (`api_service.dart`). (2) On-device diag showed the real blocker: the audio blob had no MIME type → mobile Safari/Chrome rejected it with MediaError 4. `audio_blob_url_web.dart` now stamps the type via `detectAudioMimeType` (`utils/audio_mime.dart`). v0.0.33→0.0.35; suite 290 green. → [2026-06-07-session-voice-web-playback-loopback-url.md](./2026-06-07-session-voice-web-playback-loopback-url.md)

**Earlier:** 2026-06-06 — Decomposed the 3009-line `messaging_provider.dart` into a thin core + five public-`extension` part-files + `IncomingMessageSoundService`. Public API + runtime behavior unchanged. Suite 275 green. → [2026-06-06-session.md](./2026-06-06-session.md)
