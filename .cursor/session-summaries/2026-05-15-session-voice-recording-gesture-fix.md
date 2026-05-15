# Session 2026-05-15 — Voice recording release / send reliability

## Accomplished

- Traced hold-to-record flow in `RecordingController` + `ChatInputBar`.
- Identified root causes for “release does not send”: (1) **two different `GestureDetector` widgets** for idle vs recording — when `_isRecording` became true the recognizer from the idle detector was torn down mid-gesture; (2) **async gap** in `_startRecording` — `onLongPressEnd` could run before `_isRecording` was true so `_stopRecording` was skipped while recording still started.
- Implemented: **single persistent `GestureDetector`** (visuals only change); **`_isStartingRecording` / `_pendingStopAfterStart`** so a release during mic startup still triggers stop once recording is active.
- Ran `flutter analyze` on `recording_controller.dart` (clean). Ran `graphify update .`.
- Updated `CLAUDE.md` Frontend gotchas with the new recording-gesture notes.

## Key files

- `frontend/lib/widgets/input/recording_controller.dart`
- `CLAUDE.md`

## Notes for next session

- Optional: localize hardcoded `⬅ Slide to cancel` in `buildRecordingBar` (ARB keys).
- Optional: abort in-flight `_startRecording` on `onLongPressCancel` during startup (flag + cleanup) if scroll races remain noisy.
