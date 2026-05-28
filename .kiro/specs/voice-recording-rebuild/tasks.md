# Implementation Plan: Voice Recording Rebuild

## Overview

Replace the existing hold-to-record gesture system with a tap-to-toggle three-state recording model (Idle → Recording → Preview), persistent AudioRecorder singleton, Opus/WebM encoding on web, and preview-before-send with real waveform playback. The implementation rewrites `RecordingController` and modifies `ChatInputBar` while keeping the backend/socket interface unchanged.

## Tasks

- [ ] 1. Define state model and recording configuration
  - [ ] 1.1 Create `VoiceRecordingPhase` enum and `VoiceRecordingState` class
    - Create `frontend/lib/widgets/input/voice_recording_state.dart`
    - Define `VoiceRecordingPhase { idle, recording, preview, sending }` enum
    - Define `VoiceRecordingState` immutable class with fields: phase, elapsed, amplitudes, audioPath, audioBytes, previewPosition, previewDuration, isPreviewPlaying
    - Add named constructors: `VoiceRecordingState.idle()`, factory methods for each phase
    - _Requirements: 1.1, 9.1, 9.2, 9.3_

  - [ ] 1.2 Create `RecordingConfig` platform-aware configuration
    - Create `frontend/lib/widgets/input/recording_config.dart`
    - Web: Opus encoder, WebM container, 48000 Hz, mono, 64 kbps
    - Native: AAC-LC encoder, M4A container, 44100 Hz, mono, 128 kbps
    - Static getter `platformConfig` that returns the correct `RecordConfig`
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5_

  - [ ]* 1.3 Write unit tests for VoiceRecordingState and RecordingConfig
    - Test that `VoiceRecordingState.idle()` has null audio references and null timestamps
    - Test that preview state factory requires non-null audio and duration >= 500ms
    - Test platform config returns correct encoder/bitrate/sampleRate per platform
    - _Requirements: 9.1, 9.2, 9.3, 4.1, 4.2, 4.3, 4.4, 4.5_

- [ ] 2. Rewrite RecordingController with new state machine
  - [ ] 2.1 Implement core state machine and idle/recording transitions
    - Rewrite `frontend/lib/widgets/input/recording_controller.dart`
    - Remove all long-press, drag-to-cancel, slide-up-to-lock logic
    - Remove `onRecordingLockChanged`, `onRecordingBarChanged` callbacks
    - Implement persistent AudioRecorder (created on first use, reused across recordings, disposed only on widget dispose)
    - Implement `_startRecording()`: permission check → secure context check → start recorder with `RecordingConfig.platformConfig` → emit socket event → start amplitude timer (100ms) → start duration timer (1s)
    - Implement double-tap guard: ignore mic taps while in recording/preview/starting states
    - Implement 120s auto-stop via duration timer
    - _Requirements: 1.1, 1.2, 2.1, 2.2, 2.3, 2.4, 3.1, 3.2, 3.3, 3.4, 6.1, 8.1, 8.2, 11.1, 11.2, 11.3, 11.4, 11.5_

  - [ ] 2.2 Implement recording → preview and recording → idle transitions
    - Implement `_stopRecording()`: stop recorder → check min duration (500ms) → read web blob if needed → transition to preview or idle
    - Implement `_cancelRecording()`: stop recorder → delete temp file → emit socket false → show snackbar → transition to idle
    - Implement minimum duration enforcement: < 500ms → idle + "Hold longer" snackbar
    - Implement amplitude normalization: dBFS (-60..0) → 0.0..1.0
    - _Requirements: 1.3, 1.4, 1.5, 1.8, 6.2, 7.1, 7.2_

  - [ ]* 2.3 Write property test for state exclusivity
    - **Property 1: State Exclusivity**
    - Generate random sequences of VoiceRecordingEvents, apply to state machine, assert exactly one phase is active after each transition
    - **Validates: Requirement 1.1**

  - [ ]* 2.4 Write property test for duration threshold branching
    - **Property 2: Duration Threshold Branching**
    - For random durations, assert: >= 500ms → preview, < 500ms → idle with data discarded
    - **Validates: Requirements 1.3, 1.4**

  - [ ]* 2.5 Write property test for AudioRecorder persistence
    - **Property 3: AudioRecorder Persistence**
    - For random sequences of start/stop/cancel cycles, assert recorder instance identity is preserved and never disposed mid-lifecycle
    - **Validates: Requirements 2.1, 2.2, 2.4, 13.4**

- [ ] 3. Implement preview state and playback
  - [ ] 3.1 Implement preview playback with AudioPlayer
    - Add preview `AudioPlayer` (from `just_audio`) lifecycle to RecordingController
    - Implement `_togglePreviewPlayback()`: load source on first play, toggle play/pause
    - Implement `_sendRecording()`: stop playback if active → invoke onVoiceSent callback → transition to idle
    - Implement `_discardPreview()`: stop playback → delete audio file → transition to idle
    - Stop playback before send if currently playing
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 1.6, 1.7, 12.1, 12.2, 12.3_

  - [ ] 3.2 Build preview panel UI (PreviewPanel)
    - Create preview UI within RecordingController's build method for preview phase
    - Render: waveform (from amplitude data), play/pause toggle, duration label, discard button, send button
    - Show loading indicator during send operation (sending phase)
    - _Requirements: 5.1, 5.5, 12.4_

  - [ ]* 3.3 Write property test for socket event symmetry
    - **Property 4: Socket Event Symmetry**
    - For random action sequences that begin and end in idle, assert count of `recordingVoice(true)` == count of `recordingVoice(false)`
    - **Validates: Requirements 6.1, 6.2, 6.3**

  - [ ]* 3.4 Write property test for resource cleanup on idle transition
    - **Property 5: Resource Cleanup on Idle Transition**
    - For any transition path leading to idle (cancel, discard, send, too-short, dispose), assert: no temp files remain, timer cancelled, playback stopped
    - **Validates: Requirements 7.1, 7.2, 7.3, 7.4**

- [ ] 4. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 5. Implement resource cleanup and error recovery
  - [ ] 5.1 Implement full resource cleanup and dispose logic
    - On transition to idle from any state: delete temp audio files, cancel timers, stop preview playback
    - On widget dispose during recording: stop recorder, emit `recordingVoice(false)`, cancel timer, delete temp file
    - On web: revoke blob URLs when audio data is discarded
    - Preserve AudioRecorder instance on start failure (for retry)
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 13.4_

  - [ ] 5.2 Implement error handling for all failure scenarios
    - AudioRecorder fails to start → snackbar + remain idle + preserve recorder instance
    - AudioRecorder.stop() returns null → snackbar + transition to idle
    - Web blob fetch fails → snackbar + transition to idle
    - Permission denied (native) → snackbar + remain idle
    - Permission denied (recorder API) → snackbar + remain idle
    - Insecure web context → snackbar + remain idle
    - _Requirements: 13.1, 13.2, 13.3, 13.4, 3.1, 3.2, 3.3, 3.4_

  - [ ]* 5.3 Write property test for start guard
    - **Property 6: Start Guard**
    - For taps on mic while in recording/preview/starting states, assert no state change occurs
    - **Validates: Requirements 8.1, 8.2**

  - [ ]* 5.4 Write property test for state-data consistency invariants
    - **Property 7: State-Data Consistency Invariants**
    - For any reachable state: preview → audioData non-null and duration >= 500ms; idle → audioData null and startTime null; recording → startTime non-null
    - **Validates: Requirements 9.1, 9.2, 9.3**

- [ ] 6. Update ChatInputBar and build recording/preview UI
  - [ ] 6.1 Modify ChatInputBar to support new RecordingController interface
    - Remove `onRecordingLockChanged` and `onRecordingBarChanged` callbacks
    - Remove `_recordingKey` GlobalKey pattern and `buildRecordingBar()` calls
    - RecordingController now renders its own full-width UI in recording/preview states
    - ChatInputBar conditionally shows text field OR RecordingController's expanded UI based on recording phase
    - Keep RecordingController always mounted in widget tree
    - _Requirements: 10.1, 10.2_

  - [ ] 6.2 Build recording state UI within RecordingController
    - Idle state: mic icon (tap to start)
    - Recording state: cancel button, pulsing red dot, timer, live waveform, stop button
    - Preview state: discard button, play/pause, waveform with progress, duration label, send button
    - Sending state: loading indicator
    - Use real amplitude data for waveform (not seed-based sine wave)
    - _Requirements: 5.1, 11.1, 11.2, 12.4_

  - [ ]* 6.3 Write widget tests for RecordingController UI states
    - Test tap mic → recording UI appears (cancel, stop, timer visible)
    - Test tap stop → preview UI appears (play, discard, send, waveform visible)
    - Test tap send → onVoiceSent called, returns to idle
    - Test tap cancel → returns to idle with snackbar
    - Test tap discard → returns to idle
    - _Requirements: 1.2, 1.3, 1.5, 1.6, 1.7, 5.1_

- [ ] 7. Enhance WaveformDisplay for real amplitude data
  - [ ] 7.1 Update WaveformDisplay to accept real amplitude data
    - Add `amplitudeData` parameter (List<double>?) to WaveformDisplay
    - When `amplitudeData` is provided: render bars from actual amplitude values
    - When `amplitudeData` is null: use existing seed-based sine-wave (backward compatible for message playback)
    - Support seek-by-tap/drag in preview state via `onSeek` callback
    - Animate progress fill during playback
    - _Requirements: 5.1_

  - [ ]* 7.2 Write unit tests for WaveformDisplay amplitude rendering
    - Test that amplitude data renders correct number of bars
    - Test that null amplitude data falls back to seed-based generation
    - Test seek callback fires with correct position
    - _Requirements: 5.1_

- [ ] 8. Delete obsolete code and tests
  - [ ] 8.1 Remove old gesture-based recording code and tests
    - Delete `test/widgets/input/recording_controller_lock_test.dart`
    - Remove any tests referencing slide-to-cancel, drag gestures, or `onLongPress*`
    - Remove `buildRecordingBar()`, `buildRecordingBarLocked()` methods from old controller
    - Remove lock-related state variables and methods
    - Clean up unused imports
    - _Requirements: 11.3, 11.4, 11.5_

- [ ] 9. Final checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties from the design document
- Unit tests validate specific examples and edge cases
- The `record` package, `just_audio`, `permission_handler`, and `path_provider` are already in the project — no new dependencies needed
- The existing `WaveformDisplay` widget is extended (not replaced) to maintain backward compatibility with message playback
- Backend upload and socket events (`recordingVoice`, `sendVoiceMessage`) remain unchanged

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "1.2"] },
    { "id": 1, "tasks": ["1.3", "2.1"] },
    { "id": 2, "tasks": ["2.2", "7.1"] },
    { "id": 3, "tasks": ["2.3", "2.4", "2.5", "3.1"] },
    { "id": 4, "tasks": ["3.2", "3.3", "3.4", "5.1"] },
    { "id": 5, "tasks": ["5.2", "5.3", "5.4"] },
    { "id": 6, "tasks": ["6.1"] },
    { "id": 7, "tasks": ["6.2", "6.3", "7.2"] },
    { "id": 8, "tasks": ["8.1"] }
  ]
}
```
