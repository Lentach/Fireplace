# Requirements Document

## Introduction

This document specifies the requirements for a complete rebuild of the voice recording feature in Fireplace. The rebuild replaces the existing long-press-hold-slide interaction model with a simple three-state flow (Idle → Recording → Preview), introduces a persistent AudioRecorder to fix PWA permission re-prompts, adds preview-before-send with waveform playback, and switches web encoding from WAV to Opus/WebM. The scope is frontend-only — backend upload and socket events remain unchanged.

## Glossary

- **RecordingController**: The StatefulWidget that owns the recording state machine, AudioRecorder lifecycle, and delegates to sub-widgets for each state's UI
- **RecordingPhase**: An enum representing the three mutually exclusive states of the recording flow: idle, recording, preview
- **AudioRecorder**: The persistent instance from the `record` package that captures microphone audio
- **PreviewPanel**: The widget that renders waveform playback, discard, and send controls after recording stops
- **AudioSource**: A sealed class representing recorded audio data — either a file path (native) or raw bytes (web)
- **ChatInputBar**: The parent widget that hosts the RecordingController and adapts its layout based on the current RecordingPhase
- **MessagingProvider**: The provider responsible for encrypting and uploading voice messages to the backend
- **SocketService**: The service that emits `recordingVoice` events to notify the recipient of recording activity

## Requirements

### Requirement 1: State Machine Transitions

**User Story:** As a user, I want the recording flow to follow a clear three-state model, so that the interaction is predictable and free of gesture ambiguity.

#### Acceptance Criteria

1. THE RecordingController SHALL maintain exactly one active state from the set {idle, recording, preview} at any point in time
2. WHEN the user taps the microphone icon while in idle state, THE RecordingController SHALL transition to recording state
3. WHEN the user taps the stop button while in recording state AND the recording duration is at least 500 milliseconds, THE RecordingController SHALL transition to preview state
4. WHEN the user taps the stop button while in recording state AND the recording duration is less than 500 milliseconds, THE RecordingController SHALL transition to idle state and display a "Hold longer" snackbar
5. WHEN the user taps the cancel button while in recording state, THE RecordingController SHALL transition to idle state and display a "Recording canceled" snackbar
6. WHEN the user taps the send button while in preview state, THE RecordingController SHALL transition to idle state and invoke the voice send callback
7. WHEN the user taps the discard button while in preview state, THE RecordingController SHALL transition to idle state and delete the recorded audio data
8. WHEN a recording reaches 120 seconds, THE RecordingController SHALL automatically stop the recording and transition to preview state

### Requirement 2: Persistent AudioRecorder

**User Story:** As a PWA user, I want the microphone permission to be requested only once per session, so that I am not repeatedly interrupted by browser permission prompts.

#### Acceptance Criteria

1. THE RecordingController SHALL create the AudioRecorder instance on first use and reuse the same instance for all subsequent recordings within the widget lifecycle
2. WHEN a recording stops or is canceled, THE RecordingController SHALL NOT dispose the AudioRecorder instance
3. WHEN the RecordingController widget is disposed, THE RecordingController SHALL dispose the AudioRecorder instance and release all associated resources
4. WHEN the AudioRecorder instance already exists and a new recording is requested, THE RecordingController SHALL reuse the existing instance without creating a new one

### Requirement 3: Microphone Permission Handling

**User Story:** As a user, I want clear feedback when microphone access is denied, so that I understand why recording cannot start.

#### Acceptance Criteria

1. WHEN the user taps the microphone icon on a native platform, THE RecordingController SHALL request microphone permission via the platform permission API
2. WHEN microphone permission is denied or permanently denied, THE RecordingController SHALL display a "Microphone permission required" snackbar and remain in idle state
3. WHEN the application is running in a non-secure web context (not HTTPS and not localhost), THE RecordingController SHALL display a "Voice recording requires secure context" snackbar and remain in idle state
4. WHEN the AudioRecorder reports no permission via its own API, THE RecordingController SHALL display a "Microphone permission denied" snackbar and remain in idle state

### Requirement 4: Recording Audio Format

**User Story:** As a developer, I want voice recordings to use efficient codecs appropriate to each platform, so that file sizes are small and upload times are fast.

#### Acceptance Criteria

1. WHILE running on web, THE RecordingController SHALL configure the AudioRecorder to use the Opus encoder with a WebM container
2. WHILE running on a native platform, THE RecordingController SHALL configure the AudioRecorder to use the AAC-LC encoder with an M4A container
3. THE RecordingController SHALL configure all recordings as mono (single channel) at 128 kbps bitrate
4. WHILE running on web, THE RecordingController SHALL use a 48000 Hz sample rate
5. WHILE running on a native platform, THE RecordingController SHALL use a 44100 Hz sample rate

### Requirement 5: Preview Playback

**User Story:** As a user, I want to listen to my recording before sending it, so that I can verify the audio quality and content.

#### Acceptance Criteria

1. WHEN the RecordingController transitions to preview state, THE PreviewPanel SHALL display a waveform visualization, a play/pause toggle, a discard button, and a send button
2. WHEN the user taps the play button in preview state, THE PreviewPanel SHALL begin audio playback from the recorded data
3. WHEN the user taps the pause button during playback, THE PreviewPanel SHALL pause audio playback
4. WHEN the user taps the send button during active playback, THE RecordingController SHALL stop playback before initiating the send operation
5. THE PreviewPanel SHALL display the recording duration as a label

### Requirement 6: Socket Event Symmetry

**User Story:** As a recipient, I want to see a "recording voice" indicator only while the sender is actually recording, so that the indicator is never stuck in an active state.

#### Acceptance Criteria

1. WHEN a recording starts successfully, THE RecordingController SHALL emit a `recordingVoice(true)` socket event to the recipient
2. WHEN a recording stops, is canceled, or the widget is disposed during recording, THE RecordingController SHALL emit a `recordingVoice(false)` socket event to the recipient
3. FOR ALL recording sessions, the count of `recordingVoice(true)` emissions SHALL equal the count of `recordingVoice(false)` emissions after the RecordingController returns to idle state

### Requirement 7: Resource Cleanup

**User Story:** As a user, I want the app to clean up temporary audio files and timers, so that storage is not wasted and no background processes leak.

#### Acceptance Criteria

1. WHEN the RecordingController transitions to idle state from any other state, THE RecordingController SHALL delete any temporary audio files created during the session
2. WHEN the RecordingController transitions to idle state, THE RecordingController SHALL cancel any active recording timer
3. WHEN the RecordingController transitions to idle state from preview state, THE RecordingController SHALL stop any active preview playback
4. WHEN the RecordingController widget is disposed while in recording state, THE RecordingController SHALL stop the recording, emit `recordingVoice(false)`, cancel the timer, and delete the temporary audio file
5. WHEN running on web and audio data is discarded, THE RecordingController SHALL revoke any blob URLs associated with the recording

### Requirement 8: Double-Tap Guard

**User Story:** As a user, I want rapid taps on the microphone icon to be ignored while a recording is starting, so that the app does not enter an inconsistent state.

#### Acceptance Criteria

1. WHILE a recording start operation is in progress, THE RecordingController SHALL ignore additional taps on the microphone icon
2. WHILE the RecordingController is in recording or preview state, THE RecordingController SHALL ignore taps on the microphone icon

### Requirement 9: Preview Data Integrity

**User Story:** As a user, I want the preview state to always contain valid audio data, so that playback and send operations never fail due to missing data.

#### Acceptance Criteria

1. WHILE in preview state, THE RecordingController SHALL hold a non-null AudioSource reference with valid audio data
2. WHILE in preview state, THE RecordingController SHALL hold a duration value of at least 500 milliseconds
3. WHILE in idle state, THE RecordingController SHALL hold no references to recorded audio data or recording timestamps

### Requirement 10: Widget Tree Persistence

**User Story:** As a developer, I want the RecordingController to remain mounted in the widget tree throughout the chat screen lifecycle, so that gesture events are never lost due to widget unmounting.

#### Acceptance Criteria

1. THE ChatInputBar SHALL keep the RecordingController in the widget tree at all times regardless of the current RecordingPhase
2. WHEN the RecordingPhase changes, THE ChatInputBar SHALL adapt its layout without unmounting or recreating the RecordingController widget

### Requirement 11: Interaction Model

**User Story:** As a user, I want to start and stop recording with simple taps, so that I do not need to hold, drag, or perform complex gestures.

#### Acceptance Criteria

1. THE RecordingController SHALL use tap-to-start interaction for initiating recordings (not long-press, not hold)
2. THE RecordingController SHALL use tap-to-stop interaction for ending recordings (not finger-release, not slide)
3. THE RecordingController SHALL NOT implement slide-to-cancel gesture
4. THE RecordingController SHALL NOT implement slide-up-to-lock gesture
5. THE RecordingController SHALL NOT implement hold-to-record gesture

### Requirement 12: Send Operation

**User Story:** As a user, I want my voice message to be encrypted and uploaded when I tap send, so that my message is delivered securely.

#### Acceptance Criteria

1. WHEN the user taps send in preview state, THE RecordingController SHALL invoke the onVoiceSent callback with the audio data and duration
2. WHEN running on web, THE RecordingController SHALL pass audio bytes to the send callback
3. WHEN running on a native platform, THE RecordingController SHALL pass the local audio file path to the send callback
4. WHEN the send operation is in progress, THE RecordingController SHALL display a loading indicator in place of the microphone icon

### Requirement 13: Error Recovery

**User Story:** As a user, I want the recording flow to recover gracefully from errors, so that I can always try again without restarting the app.

#### Acceptance Criteria

1. IF the AudioRecorder fails to start, THEN THE RecordingController SHALL display a "Failed to start recording" snackbar and remain in idle state
2. IF the AudioRecorder.stop() returns null, THEN THE RecordingController SHALL display a "Failed to read recording" snackbar and transition to idle state
3. IF the web blob fetch fails during preview preparation, THEN THE RecordingController SHALL display a "Failed to read recording" snackbar and transition to idle state
4. IF any error occurs during recording start, THEN THE RecordingController SHALL preserve the AudioRecorder instance for future retry attempts
