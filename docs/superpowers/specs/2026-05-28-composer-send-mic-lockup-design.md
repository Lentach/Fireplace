# Chat Composer — Send/Mic Toggle, Voice Lock-Up & iOS Viewport Fix

**Date:** 2026-05-28  
**Status:** Approved for implementation  
**App version at spec time:** `0.0.17`  
**Supersedes / merges:** `2026-05-24-trailing-send-button-spec.md` (Phase 0), `2026-05-24-voice-lock-up-spec.md` (Phase 1)  
**Related:** `2026-05-23-chat-composer-viewport-design.md`

---

## 1. Goals

| # | Goal |
|---|------|
| G1 | **Telegram-style send/mic toggle** — trailing 48×48 slot shows mic when text field is empty; animated send button when user types. |
| G2 | **Keyboard stays open on send** — in-app send button must never steal focus from `TextField`. |
| G3 | **iOS Safari black-screen fix** — when keyboard opens on an already-focused field, Safari scrolls the WebView; `resetWebDocumentScroll()` must fire at that moment. |
| G4 | **Voice lock-up** — while holding mic, slide up ≥ 72 px to lock recording; finger may release; recording continues until explicit Send or Cancel. |
| G5 | **Fix stuck-recording bug** — long recording + gesture event lost = recording stuck forever; V4 locked mode + defensive try-finally in `_stopRecording()` eliminates this. |
| G6 | **CLAUDE.md constraints preserved** — single `GestureDetector`, `RecordingController` always mounted, `ExcludeFocus` on trailing slot, all existing guards kept. |

---

## 2. Composer state table

| ID | State | Text field area | Trailing 48×48 | Send paths |
|----|--------|-----------------|----------------|------------|
| V0 | **Idle, empty** | `TextField` | Mic (hold) | — |
| V1 | **Has draft text** | `TextField` | Text Send (primary) + mic underlay | Tap send / IME / Ctrl+Enter |
| V3 | **Recording unlocked** | Recording bar | Mic red, draggable H+V | Release → auto-send; slide left → cancel |
| V4 | **Recording locked** | Recording bar (locked) | Voice Send (purple) | Tap Send button |
| V5 | **Sending voice** | `TextField` | Spinner | — |

**Precedence:** V5 > V4 > V3 > V1 > V0.

**Text Send hidden while `_isRecording`** — even if draft text exists.  
**Voice Send hidden when not locked.**

---

## 3. File changes

### 3.1 `chat_composer_viewport.dart` — iOS scroll watchdog

**New field:**
```dart
double _prevKeyboardInset = 0;
```

**In `build()`, before existing stack:**
```dart
if (kIsWeb && keyboardInset > 0 && _prevKeyboardInset == 0) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) resetWebDocumentScroll();
  });
}
_prevKeyboardInset = keyboardInset;
```

Import `web_viewport_scroll.dart` and `web_ios_webkit.dart`.

**Why:** The existing `resetWebDocumentScroll()` in `ChatInputBar` only fires on `_focusNode` changes. When the field already has focus and the keyboard opens (user taps after keyboard was dismissed), no focus event fires → Safari scrolls the WebView → black screen. This watchdog catches every `0 → > 0` keyboard inset transition.

---

### 3.2 `chat_input_bar.dart` — state driver

**New fields:**
```dart
bool _hasText = false;
bool _isLocked = false;
```

**Extend `_controller.addListener`** (only `setState` when empty/non-empty status changes — no extra rebuilds on every keystroke):
```dart
final hasText = _controller.text.trim().isNotEmpty;
if (hasText != _hasText) setState(() => _hasText = hasText);
```

**`RecordingController` props (final):**
```dart
RecordingController(
  key: _recordingKey,
  onVoiceSent: _handleVoiceSent,
  onRecordingStateChanged: _onRecordingStateChanged,
  isSendingVoice: _isSendingVoice,
  showTextSend: _hasText && !_isRecording,
  onTextSend: _send,
  onRecordingLockChanged: (locked) => setState(() => _isLocked = locked),
)
```

`RecordingController.build()` owns the entire trailing slot stack — both text Send and voice Send layers are rendered there. `ChatInputBar` only mirrors `_isLocked` from the callback to route the recording bar between locked and unlocked variants.

**Recording bar routing in the `Expanded` child:**
```dart
_isRecording
  ? (_isLocked
      ? (_recordingKey.currentState?.buildRecordingBarLocked(context) ?? const SizedBox.shrink())
      : (_recordingKey.currentState?.buildRecordingBar(context) ?? const SizedBox.shrink()))
  : /* TextField */
```

---

### 3.3 `recording_controller.dart` — trailing stack + lock-up

#### New props

```dart
final bool showTextSend;
final VoidCallback? onTextSend;
final void Function(bool isLocked)? onRecordingLockChanged;
```

#### New state fields

```dart
bool _isLocked = false;
double _dragStartY = 0.0;
double _lockDragOffset = 0.0;

static const double _lockUpThresholdPx = 72.0;
static const double _lockUpHintShowPx = 36.0;
```

#### Gesture changes

**`onLongPressStart`:** also capture `details.globalPosition.dy → _dragStartY`.

**`onLongPressMoveUpdate`:** compute vertical delta `= _dragStartY - details.globalPosition.dy` (positive = upward). When `_isRecording && !_isLocked && verticalDelta >= _lockUpThresholdPx`: call `_enterLockedMode()`. Continue tracking horizontal delta as before (unlocked cancel drag unaffected until lock triggers).

**`_enterLockedMode()`:**
```dart
void _enterLockedMode() {
  _isLocked = true;
  _cancelDragOffset = 0;
  _showTrashIcon = false;
  setState(() {});
  widget.onRecordingLockChanged?.call(true);
  if (!kIsWeb) HapticFeedback.mediumImpact();
}
```

**`_finishRecordingGesture()` / `_onLongPressFinished()`:** add guard at top:
```dart
if (_isLocked) return;  // locked mode: explicit Send/Cancel required
```

**`_onPointerRelease()`:** same guard:
```dart
void _onPointerRelease() {
  if (!_isRecording && !_isStartingRecording) return;
  if (_isLocked) return;
  _finishRecordingGesture();
}
```

**`_stopRecording()` and `_cancelRecording()`:** both reset lock state in their finally/cleanup:
```dart
_isLocked = false;
widget.onRecordingLockChanged?.call(false);
```

#### Public methods for locked mode

```dart
void sendLockedRecording() {
  if (_isRecording && _isLocked && !_isStopping) _stopRecording();
}

void cancelLockedRecording() {
  if (_isRecording && _isLocked) _cancelRecording();
}
```

#### `build()` — trailing slot stack

```
SizedBox(48×48)
└── ExcludeFocus
    └── Stack(alignment: center)
        ├── [Base] IgnorePointer(ignoring: showTextSend || _isLocked) +
        │         Opacity(opacity: 0 when covered) → micHitTarget (GestureDetector ALWAYS mounted)
        ├── [Voice Send] AnimatedOpacity/Scale → when _isRecording && _isLocked
        │                 Focus(canRequestFocus:false) → IconButton(Icons.send_rounded, purple)
        ├── [Text Send]  AnimatedOpacity/Scale → when showTextSend && !_isRecording
        │                 Focus(canRequestFocus:false) → IconButton(Icons.send, primaryColor)
        └── [Spinner]    when isSendingVoice → CircularProgressIndicator (existing)
```

Animation: `AnimatedOpacity` + `AnimatedScale` 150ms `Curves.easeOut` for both Send layers. Scale: `0.7 → 1.0` on appear.

`Focus(canRequestFocus: false)` on **both** send buttons — neither can steal focus → keyboard stays open.

#### `buildRecordingBarLocked(BuildContext context)` — new method

```
Container(height:48, decoration: rounded border same as buildRecordingBar)
└── Row
    ├── GestureDetector(onTap: cancelLockedRecording)
    │     Icon(Icons.close, red, size:22) — min 44×44 hit target
    ├── SizedBox(width:12)
    ├── Icon(Icons.lock, size:14, color:purple)
    ├── SizedBox(width:8)
    ├── AnimatedBuilder(animation:_pulseController) → red dot + M:SS timer
    ├── SizedBox(width:8)
    └── Flexible → Text(l10n.voiceRecordingLocked, ellipsis, color:purple)
```

#### `buildRecordingBar()` additions (unlocked)

When `_lockDragOffset > _lockUpHintShowPx`, fade in upward hint text (`voiceRecordingSlideUpToLock`) in the right area, opacity proportional to `(_lockDragOffset - _lockUpHintShowPx) / (_lockUpThresholdPx - _lockUpHintShowPx)`.

---

### 3.4 Defensive `_stopRecording()` fix

Wrap the **entire body** in try-finally:

```dart
Future<void> _stopRecording() async {
  if (_audioRecorder == null || !_isRecording || _isStopping) return;
  _isStopping = true;
  try {
    // ... all existing code ...
  } catch (e) {
    debugPrint('Stop recording error: $e');
  } finally {
    _isStopping = false;
    _isLocked = false;
    widget.onRecordingLockChanged?.call(false);
  }
}
```

**Also fix `dispose()`** — call `_releaseRecorderSilently()` if still recording:
```dart
@override
void dispose() {
  _pulseController.dispose();
  _recordingTimer?.cancel();
  if (_isRecording || _isStartingRecording) {
    _isLocked = false;
    _isRecording = false;
    _isStopping = false;
    _releaseRecorderSilently();
  } else {
    _audioRecorder?.dispose();
  }
  super.dispose();
}
```

---

### 3.5 ARB strings

**`app_en.arb`:**
```json
"voiceRecordingSlideUpToLock": "↑ Slide up to lock",
"voiceRecordingLocked": "Locked · tap Send when done",
"voiceRecordingCancelLocked": "Cancel recording"
```

**`app_pl.arb`:**
```json
"voiceRecordingSlideUpToLock": "↑ Przesuń w górę, aby zablokować",
"voiceRecordingLocked": "Zablokowano · dotknij Wyślij",
"voiceRecordingCancelLocked": "Anuluj nagrywanie"
```

Run `flutter gen-l10n` after adding keys.

---

## 4. Invariants & constraints

| ID | Rule |
|----|------|
| C1 | `RecordingController` GestureDetector **always mounted** — never conditional in Row |
| C2 | Single `GestureDetector` for entire press/move/release lifecycle |
| C3 | `Listener` (onPointerUp/Cancel) kept for PWA release fallback |
| C4 | `_isStartingRecording` / `_pendingStopAfterStart` / `_abortInFlightStart` guards **unchanged** |
| C5 | `_gestureFinishHandled` dedupe extended: locked release sets it without calling stop |
| C6 | `Focus(canRequestFocus:false)` on **all** in-app buttons in composer row |
| C7 | `_isStopping = false` **always** reached via finally — no deadlock possible |
| C8 | Text field not focused/unfocused during recording start/lock/stop |
| C9 | Draft text (`_controller`) **not cleared** by any recording action |

---

## 5. Edge cases

| Case | Expected |
|------|----------|
| Lock then release under 500 ms | `snackbarHoldLongerForVoiceMessage` |
| Lock then Send at 120 s cap | Auto-stop already fired; normal send |
| Lock then Cancel | Clip discarded; `recordingVoice: false` emitted |
| Draft text + record + cancel | Field shows draft again |
| Draft text + record + send | Voice sends; draft still present |
| `isSendingVoice` during locked | Spinner shown; no new recording |
| Navigate away while locked | `dispose()` calls `_releaseRecorderSilently()`; audio cleaned up |
| Slide up but under threshold | `_lockUpHintShowPx` hint fades in; release still auto-sends |
| Slide left while recording (cancel) | Works only while unlocked; locked mode ignores horizontal drag |
| `showTextSend` true + long-press mic | Mic underlay receives gesture (IgnorePointer on text Send only, not mic); voice starts, recording bar replaces field, text Send disappears |
| `_stopRecording()` throws | `finally` always resets `_isStopping`; `_isLocked` reset; parent notified |

---

## 6. Testing

### New widget tests — `recording_controller_lock_test.dart`

| Test | Assertion |
|------|-----------|
| Lock threshold | Vertical drag ≥ 72 px → `isLocked == true` |
| Locked release no auto-send | Pointer up while locked → `onVoiceSent` not called |
| Locked Send | `sendLockedRecording()` → stop/send path |
| Locked Cancel | `cancelLockedRecording()` → discards |
| Hint appears | Drag 40 px up → hint visible; drag 80 px → lock |
| Single GestureDetector | Widget tree count stable across all state transitions |
| `_isStopping` never deadlocks | Mock recorder throws on `stop()` → `_isStopping` is false after |
| Dispose while locked | No exception; audio released |

### Extend — `chat_input_bar_trailing_send_test.dart` (or new file)

| Test | Assertion |
|------|-----------|
| Text send appears on type | Empty → type → text send visible |
| Text send hidden while recording | `_isRecording=true` → text send hidden even with draft |
| Voice send visible when locked | `isLocked=true` → voice send visible |
| `Focus(canRequestFocus:false)` | Neither send button can focus in test tree |
| Viewport scroll watchdog | `keyboardInset 0 → 300` on iOS → `resetWebDocumentScroll` called |

### CI commands

```bash
cd frontend && flutter analyze
cd frontend && flutter test test/widgets/input/recording_controller_lock_test.dart
cd frontend && flutter test test/widgets/input/
```

### Manual QA matrix

| Platform | Scenario | Pass |
|----------|----------|------|
| iPhone PWA | Type → send → keyboard stays | ✓ |
| iPhone PWA | Send → tap field (already focused) → no black screen | ✓ |
| iPhone PWA | Hold → slide up → lock → Send | ✓ |
| iPhone PWA | Hold → slide up → lock → Cancel | ✓ |
| iPhone PWA | Hold → release (no lock) | ✓ |
| iPhone PWA | Hold → slide left → cancel | ✓ |
| Android native | Hold → lock → Send | ✓ |
| Android native | Short hold < 500 ms | ✓ |
| All | Draft text + voice send → draft remains | ✓ |
| All | Text send (V1) → works after voice cancel | ✓ |

---

## 7. Version

Ship as `0.0.18` (PATCH). All changes are in 3 Flutter files + 2 ARB files.
