# Chat Composer — Send/Mic Toggle, Voice Lock-Up & iOS Fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Telegram-style send/mic toggle, voice lock-up mode, iOS Safari black-screen fix, and defensive recording cleanup — fixing the stuck-recording bug and the post-send keyboard jump.

**Architecture:** Three Flutter files change (ChatComposerViewport adds a 5-line iOS scroll watchdog; ChatInputBar tracks `_hasText`/`_isLocked` and routes recording bars; RecordingController owns the full trailing 48×48 Stack with mic + text Send + voice Send layers). ARB strings added for lock-up UI. All new state is local to those three files — no provider changes, no new files beyond tests.

**Tech Stack:** Flutter 3.x, `record` package (AudioRecorder), `flutter_test` widget tests, `AppLocalizations` (gen-l10n), `RpgTheme`

**Spec:** `docs/superpowers/specs/2026-05-28-composer-send-mic-lockup-design.md`

---

## File map

| File | Role |
|------|------|
| `frontend/lib/l10n/app_en.arb` | Add 3 lock-up ARB keys |
| `frontend/lib/l10n/app_pl.arb` | Same, Polish |
| `frontend/lib/widgets/input/chat_composer_viewport.dart` | iOS keyboard scroll watchdog |
| `frontend/lib/widgets/input/recording_controller.dart` | Defensive fixes, lock-up gesture + UI, trailing Stack |
| `frontend/lib/widgets/input/chat_input_bar.dart` | `_hasText`/`_isLocked` state, bar routing |
| `frontend/test/widgets/input/recording_controller_lock_test.dart` | New: lock-up gesture tests |
| `frontend/test/widgets/input/chat_input_bar_trailing_send_test.dart` | New: send toggle + locked bar routing tests |

---

## Task 1 — ARB strings

**Files:**
- Modify: `frontend/lib/l10n/app_en.arb`
- Modify: `frontend/lib/l10n/app_pl.arb`

- [ ] **Step 1: Add 3 new keys to `app_en.arb` after `voiceRecordingSlideToCancel`**

Find `"voiceRecordingSlideToCancel"` (around line 230) and insert the three keys immediately after it:

```json
  "voiceRecordingSlideToCancel": "← Slide to cancel",
  "voiceRecordingSlideUpToLock": "↑ Slide up to lock",
  "voiceRecordingLocked": "Locked · tap Send when done",
  "voiceRecordingCancelLocked": "Cancel recording",
  "voiceRecordingSemanticsLabel": "Recording voice message, {time}. Swipe left to cancel.",
```

- [ ] **Step 2: Add the same 3 keys to `app_pl.arb` after `voiceRecordingSlideToCancel`**

Find `"voiceRecordingSlideToCancel"` (around line 218) and insert:

```json
  "voiceRecordingSlideToCancel": "← Przesuń, aby anulować",
  "voiceRecordingSlideUpToLock": "↑ Przesuń w górę, aby zablokować",
  "voiceRecordingLocked": "Zablokowano · dotknij Wyślij",
  "voiceRecordingCancelLocked": "Anuluj nagrywanie",
  "voiceRecordingSemanticsLabel": "Nagrywanie wiadomości głosowej, {time}. Przesuń w lewo, aby anulować.",
```

- [ ] **Step 3: Generate localizations**

```bash
cd frontend && flutter gen-l10n
```

Expected: exits 0, no errors. Three new method names now available on `AppLocalizations`: `voiceRecordingSlideUpToLock`, `voiceRecordingLocked`, `voiceRecordingCancelLocked`.

- [ ] **Step 4: Verify compilation**

```bash
cd frontend && flutter analyze
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/l10n/app_en.arb frontend/lib/l10n/app_pl.arb
git add frontend/lib/l10n/
git commit -m "feat(i18n): add voice lock-up ARB strings (en + pl)"
```

---

## Task 2 — Defensive `_stopRecording()` + `dispose()` fix

**Files:**
- Modify: `frontend/lib/widgets/input/recording_controller.dart`

**Why:** `_isStopping = true` is set before the `try {}` block in `_stopRecording()`. If `_audioRecorder!.stop()` throws (large file, encoding error, iOS interruption), `_isStopping` is permanently stuck — every subsequent call to `_stopRecording()` returns early. Recording is frozen. The only fix is closing the app. Also, `dispose()` doesn't clean up an in-progress recording.

- [ ] **Step 1: Wrap `_stopRecording()` entire body in try-catch-finally**

Open `frontend/lib/widgets/input/recording_controller.dart`.

The current `_stopRecording()` has `_isStopping = true` set at the top, then a `try {}` block only around the send-logic at the bottom. Replace the entire method body so every code path resets `_isStopping`. The wrapping structure is:

```dart
  Future<void> _stopRecording() async {
    if (_audioRecorder == null || !_isRecording || _isStopping) return;
    _isStopping = true;
    try {
      final l10n = AppLocalizations.of(context);
      final messaging = context.read<MessagingProvider>();
      messaging.setIsRecordingVoice(false);
      _emitRecordingVoiceToRecipient(false);
      _recordingTimer?.cancel();
      _recordingTimer = null;

      final path = await _audioRecorder!.stop();
      await _audioRecorder!.dispose();
      _audioRecorder = null;

      setState(() {
        _isRecording = false;
        _cancelDragOffset = 0.0;
        _showTrashIcon = false;
      });
      widget.onRecordingStateChanged(false);

      final durationMs = _recordingStartTime != null
          ? DateTime.now().difference(_recordingStartTime!).inMilliseconds
          : 0;
      final durationSeconds = (durationMs + 999) ~/ 1000;
      _recordingStartTime = null;

      if (durationMs < kMinVoiceRecordingMs) {
        if (!kIsWeb && path != null) {
          try {
            final file = File(path);
            if (await file.exists()) await file.delete();
          } catch (_) {}
        }
        _showNotSentSnackBar(l10n.snackbarHoldLongerForVoiceMessage);
        setState(() => _recordingPath = null);
        return;
      }

      if (path == null) {
        _showNotSentSnackBar(l10n.snackbarFailedToReadRecording);
        setState(() => _recordingPath = null);
        return;
      }

      if (kIsWeb) {
        try {
          final response = await http.get(Uri.parse(path));
          if (response.statusCode == 200) {
            await widget.onVoiceSent(
              duration: durationSeconds,
              audioBytes: response.bodyBytes,
            );
          } else {
            _showNotSentSnackBar(l10n.snackbarFailedToReadRecording);
          }
        } catch (e) {
          _showNotSentSnackBar(l10n.snackbarFailedToReadRecording);
          debugPrint('Read voice blob error: $e');
        }
      } else {
        final file = File(path);
        if (await file.exists()) {
          await widget.onVoiceSent(
            duration: durationSeconds,
            localAudioPath: path,
          );
        } else {
          _showNotSentSnackBar(l10n.snackbarFailedToReadRecording);
        }
      }

      setState(() => _recordingPath = null);
    } catch (e) {
      debugPrint('Stop recording error: $e');
      if (mounted) {
        setState(() {
          _isRecording = false;
          _recordingPath = null;
        });
      }
      widget.onRecordingStateChanged(false);
    } finally {
      _isStopping = false;
    }
  }
```

Note: the `_isLocked` reset will be added in Task 5 when that field is introduced.

- [ ] **Step 2: Fix `dispose()` to clean up in-progress recording**

Replace the existing `dispose()`:

```dart
  @override
  void dispose() {
    _pulseController.dispose();
    _recordingTimer?.cancel();
    if (_isRecording || _isStartingRecording) {
      // Force-reset all flags — widget is being torn down, no callbacks needed.
      _isRecording = false;
      _isStopping = false;
      _releaseRecorderSilently();  // existing method: stops recorder, deletes temp file, no send/cancel callbacks
    } else {
      _audioRecorder?.dispose();
    }
    super.dispose();
  }
```

`_releaseRecorderSilently()` already exists in the file — it stops the audio recorder and deletes the temp file without triggering `onVoiceSent` or `onRecordingStateChanged`.

- [ ] **Step 3: Analyze**

```bash
cd frontend && flutter analyze
```

Expected: no errors.

- [ ] **Step 4: Run existing recording tests**

```bash
cd frontend && flutter test test/widgets/input/recording_controller_test.dart
```

Expected: PASS (the existing 2 tests are about constants and exception types — unchanged).

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/widgets/input/recording_controller.dart
git commit -m "fix(voice): wrap _stopRecording in try-finally; fix dispose while recording"
```

---

## Task 3 — iOS viewport scroll watchdog

**Files:**
- Modify: `frontend/lib/widgets/input/chat_composer_viewport.dart`

**Why:** When keyboard opens on an already-focused field, iOS Safari natively scrolls the document to bring the element into view. The existing `resetWebDocumentScroll()` in `ChatInputBar` only fires on `_focusNode` changes. No focus change = no reset = black screen. This watchdog fires on every `keyboardInset 0 → > 0` transition.

Coverage note: `isIOSWebKit()` returns false in the test VM, so the watchdog is a no-op in automated tests. Verified via manual QA matrix in spec §6.

- [ ] **Step 1: Add imports to `chat_composer_viewport.dart`**

Open `frontend/lib/widgets/input/chat_composer_viewport.dart`. At the top, add:

```dart
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../utils/web_viewport_scroll.dart';
import '../../utils/web_ios_webkit.dart';
```

- [ ] **Step 2: Add two tracking fields to `_ChatComposerViewportState`**

```dart
  double _prevKeyboardInset = 0;       // tracking field, no setState — intentional
  bool _scrollResetScheduled = false;  // guard: prevents duplicate postFrameCallback
```

- [ ] **Step 3: Insert watchdog at top of `build()` before the `return Stack(...)`**

After the existing `final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;` line and before `return Stack(`:

```dart
    // iOS Safari: when keyboard opens on an already-focused field, Safari scrolls
    // the document without a focus event. Reset on every 0 → >0 transition.
    if (kIsWeb && isIOSWebKit() && keyboardInset > 0 && _prevKeyboardInset == 0 && !_scrollResetScheduled) {
      _scrollResetScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollResetScheduled = false;
        if (mounted) resetWebDocumentScroll();
      });
    }
    _prevKeyboardInset = keyboardInset; // tracking field, no setState — intentional
```

- [ ] **Step 4: Analyze + run existing viewport tests**

```bash
cd frontend && flutter analyze
cd frontend && flutter test test/widgets/input/chat_composer_viewport_test.dart
```

Expected: no errors, all existing tests pass.

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/widgets/input/chat_composer_viewport.dart
git commit -m "fix(ios): reset viewport scroll when keyboard opens on already-focused field"
```

---

## Task 4 — Text send toggle (Phase 0)

**Files:**
- Modify: `frontend/lib/widgets/input/recording_controller.dart`
- Modify: `frontend/lib/widgets/input/chat_input_bar.dart`
- Create: `frontend/test/widgets/input/chat_input_bar_trailing_send_test.dart`

**What this builds:** Mic and Send share the exact same 48×48 slot. When the text field is empty → mic shows. When user types → Send fades/scales in, mic is hidden but its GestureDetector stays mounted (CLAUDE.md constraint). Both send buttons use `Focus(canRequestFocus: false)` — tapping never steals focus from the TextField, keyboard stays open.

- [ ] **Step 1: Write failing tests**

Create `frontend/test/widgets/input/chat_input_bar_trailing_send_test.dart`:

```dart
import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/providers/conversations_provider.dart';
import 'package:fireplace/providers/messaging_provider.dart';
import 'package:fireplace/providers/settings_provider.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/input/chat_input_bar.dart';
import 'package:fireplace/widgets/input/recording_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Widget _buildBar({int? disappearingTimer}) {
  final convs = ConversationsProvider();
  // No conversations needed — we just need the widget to mount.
  return MaterialApp(
    theme: RpgTheme.themeDataLight,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(
      body: MultiProvider(
        providers: [
          ChangeNotifierProvider<ConversationsProvider>.value(value: convs),
          ChangeNotifierProvider(create: (_) => MessagingProvider()),
          ChangeNotifierProvider(
            create: (_) => SettingsProvider(initialThemePreference: 'light'),
          ),
        ],
        child: const ChatInputBar(),
      ),
    ),
  );
}

void main() {
  group('Text send toggle', () {
    testWidgets('mic icon visible when field is empty', (tester) async {
      await tester.pumpWidget(_buildBar());
      await tester.pump();

      expect(find.byIcon(Icons.mic_none), findsOneWidget);
      expect(find.byIcon(Icons.send), findsNothing);
    });

    testWidgets('send icon appears after typing, mic visually hidden', (tester) async {
      await tester.pumpWidget(_buildBar());
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();

      expect(find.byIcon(Icons.send), findsOneWidget);
    });

    testWidgets('send icon disappears when text cleared', (tester) async {
      await tester.pumpWidget(_buildBar());
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();
      expect(find.byIcon(Icons.send), findsOneWidget);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      expect(find.byIcon(Icons.send), findsNothing);
    });

    testWidgets('send button wrapped in Focus(canRequestFocus: false)', (tester) async {
      await tester.pumpWidget(_buildBar());
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();

      // Find all Focus widgets that wrap the send icon area
      bool foundNonFocusableSend = false;
      tester.widgetList<Focus>(find.byType(Focus)).forEach((f) {
        if (!f.canRequestFocus) foundNonFocusableSend = true;
      });
      expect(foundNonFocusableSend, true,
          reason: 'Send button must be wrapped in Focus(canRequestFocus:false)');
    });

    testWidgets('mic GestureDetector stays in tree when send shown', (tester) async {
      await tester.pumpWidget(_buildBar());
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();

      // RecordingController must still be in the widget tree
      expect(find.byType(RecordingController), findsOneWidget);
    });

    testWidgets('send icon hidden while recording even with draft text', (tester) async {
      await tester.pumpWidget(_buildBar());
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'draft text');
      await tester.pump();
      expect(find.byIcon(Icons.send), findsOneWidget);

      // Simulate recording start via test seam
      final rcState = tester.state<RecordingControllerState>(
        find.byType(RecordingController),
      );
      rcState.simulateRecordingStartedForTest();
      await tester.pump();

      // Send must be hidden during recording
      expect(find.byIcon(Icons.send), findsNothing);
    });
  });
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd frontend && flutter test test/widgets/input/chat_input_bar_trailing_send_test.dart
```

Expected: FAIL — `showTextSend` prop not found on `RecordingController`, `simulateRecordingStartedForTest` not found.

- [ ] **Step 3: Add new props to `RecordingController` widget class**

In `recording_controller.dart`, add three fields to the `RecordingController` class:

```dart
  final bool showTextSend;
  final VoidCallback? onTextSend;
  final void Function(bool isLocked)? onRecordingLockChanged;
```

Update the constructor to include them with defaults:

```dart
  const RecordingController({
    super.key,
    required this.onVoiceSent,
    required this.onRecordingStateChanged,
    required this.isSendingVoice,
    this.showTextSend = false,
    this.onTextSend,
    this.onRecordingLockChanged,
  });
```

- [ ] **Step 4: Replace `build()` return in `RecordingControllerState` with trailing Stack**

Find the final `return ExcludeFocus(...)` at the end of `build()` and replace it:

```dart
    final showSendLayer = widget.showTextSend && !_isRecording && !widget.isSendingVoice;

    return ExcludeFocus(
      child: SizedBox(
        width: 48,
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Mic — always mounted (CLAUDE.md: GestureDetector must never unmount)
            IgnorePointer(
              ignoring: showSendLayer,
              child: Opacity(
                opacity: showSendLayer ? 0.0 : 1.0,
                child: micHitTarget,
              ),
            ),

            // Text send — fades/scales in when user has typed text
            AnimatedOpacity(
              opacity: showSendLayer ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              child: AnimatedScale(
                scale: showSendLayer ? 1.0 : 0.7,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                child: Focus(
                  canRequestFocus: false,
                  child: IconButton(
                    icon: Icon(
                      Icons.send,
                      size: 22,
                      color: RpgTheme.primaryColor(context),
                    ),
                    onPressed: showSendLayer ? widget.onTextSend : null,
                    padding: EdgeInsets.zero,
                    splashRadius: 20,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
```

- [ ] **Step 5: Add `simulateRecordingStartedForTest()` test seam to `RecordingControllerState`**

Add at the bottom of `RecordingControllerState`, before the closing `}`:

```dart
  // ── test seams ────────────────────────────────────────────────────────────

  @visibleForTesting
  void simulateRecordingStartedForTest() {
    _isRecording = true;
    _isStartingRecording = false;
    _recordingStartTime = DateTime.now();
    widget.onRecordingStateChanged(true);
    setState(() {});
  }
```

Add `import 'package:flutter/foundation.dart' show visibleForTesting;` at the top if not already present.

- [ ] **Step 6: Add `_hasText` + `_isLocked` to `ChatInputBar` and wire up new props**

In `chat_input_bar.dart`, add two fields to `_ChatInputBarState`:

```dart
  bool _hasText = false;
  bool _isLocked = false;
```

In `initState()`, extend the existing `_controller.addListener` block. Find:

```dart
    _controller.addListener(() {
      if (_controller.text.trim().isEmpty) return;
      _typingDebounceTimer?.cancel();
```

Replace with:

```dart
    _controller.addListener(() {
      final hasText = _controller.text.trim().isNotEmpty;
      if (hasText != _hasText) setState(() => _hasText = hasText);
      if (_controller.text.trim().isEmpty) return;
      _typingDebounceTimer?.cancel();
```

Find the existing `RecordingController(...)` instantiation in `build()` and update it:

```dart
                RecordingController(
                  key: _recordingKey,
                  onVoiceSent: _handleVoiceSent,
                  onRecordingStateChanged: _onRecordingStateChanged,
                  isSendingVoice: _isSendingVoice,
                  showTextSend: _hasText && !_isRecording,
                  onTextSend: _send,
                  onRecordingLockChanged: (locked) =>
                      setState(() => _isLocked = locked),
                ),
```

- [ ] **Step 7: Run tests**

```bash
cd frontend && flutter gen-l10n
cd frontend && flutter test test/widgets/input/chat_input_bar_trailing_send_test.dart
```

Expected: PASS

- [ ] **Step 8: Run full widget suite to check for regressions**

```bash
cd frontend && flutter test test/widgets/input/
```

Expected: all existing tests pass.

- [ ] **Step 9: Analyze**

```bash
cd frontend && flutter analyze
```

- [ ] **Step 10: Commit**

```bash
git add frontend/lib/widgets/input/recording_controller.dart \
        frontend/lib/widgets/input/chat_input_bar.dart \
        frontend/test/widgets/input/chat_input_bar_trailing_send_test.dart
git commit -m "feat(composer): Telegram-style send/mic toggle — Phase 0"
```

---

## Task 5 — Voice lock-up gesture

**Files:**
- Modify: `frontend/lib/widgets/input/recording_controller.dart`
- Create: `frontend/test/widgets/input/recording_controller_lock_test.dart`

**What this builds:** While holding mic, sliding up ≥ 72 px locks the recording. The locked-release guard (`_isLocked`) prevents `_finishRecordingGesture` from auto-sending. The public `sendLockedRecording()` / `cancelLockedRecording()` methods are the only exit from locked mode. This eliminates the stuck-recording bug — even if gesture events are swallowed by the scroll list on long holds, the user has an explicit Stop button (added in Task 6).

- [ ] **Step 1: Write failing tests**

Create `frontend/test/widgets/input/recording_controller_lock_test.dart`:

```dart
import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/providers/conversations_provider.dart';
import 'package:fireplace/providers/messaging_provider.dart';
import 'package:fireplace/providers/settings_provider.dart';
import 'package:fireplace/widgets/input/recording_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Future<GlobalKey<RecordingControllerState>> _build(WidgetTester tester, {
  void Function(bool)? onLockChanged,
}) async {
  final key = GlobalKey<RecordingControllerState>();
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: MultiProvider(
          providers: [
            ChangeNotifierProvider<ConversationsProvider>(
              create: (_) => ConversationsProvider(),
            ),
            ChangeNotifierProvider(create: (_) => MessagingProvider()),
            ChangeNotifierProvider(
              create: (_) => SettingsProvider(initialThemePreference: 'light'),
            ),
          ],
          child: RecordingController(
            key: key,
            onVoiceSent: ({required duration, localAudioPath, audioBytes}) async {},
            onRecordingStateChanged: (_) {},
            isSendingVoice: false,
            showTextSend: false,
            onTextSend: null,
            onRecordingLockChanged: onLockChanged,
          ),
        ),
      ),
    ),
  );
  return key;
}

void main() {
  group('Voice lock-up gesture', () {
    testWidgets('vertical drag >= 72px while recording triggers lock', (tester) async {
      final key = await _build(tester);
      final state = key.currentState!;

      state.simulateRecordingStartedForTest();
      await tester.pump();
      expect(state.isRecording, true);
      expect(state.isLocked, false);

      state.simulateVerticalDragForTest(80.0);
      await tester.pump();

      expect(state.isLocked, true);
    });

    testWidgets('vertical drag < 72px does not lock', (tester) async {
      final key = await _build(tester);
      final state = key.currentState!;

      state.simulateRecordingStartedForTest();
      state.simulateVerticalDragForTest(40.0);
      await tester.pump();

      expect(state.isLocked, false);
    });

    testWidgets('locked pointer release does not auto-send', (tester) async {
      bool sent = false;
      final key = GlobalKey<RecordingControllerState>();
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: MultiProvider(
            providers: [
              ChangeNotifierProvider<ConversationsProvider>(create: (_) => ConversationsProvider()),
              ChangeNotifierProvider(create: (_) => MessagingProvider()),
              ChangeNotifierProvider(create: (_) => SettingsProvider(initialThemePreference: 'light')),
            ],
            child: RecordingController(
              key: key,
              onVoiceSent: ({required duration, localAudioPath, audioBytes}) async {
                sent = true;
              },
              onRecordingStateChanged: (_) {},
              isSendingVoice: false,
              showTextSend: false,
              onTextSend: null,
              onRecordingLockChanged: null,
            ),
          ),
        ),
      ));
      final state = key.currentState!;

      state.simulateRecordingStartedForTest();
      state.simulateLockForTest();
      await tester.pump();

      state.simulatePointerReleaseForTest();
      await tester.pump();

      expect(sent, false);
      expect(state.isRecording, true); // still recording
    });

    testWidgets('sendLockedRecording stops recording', (tester) async {
      final key = await _build(tester);
      final state = key.currentState!;

      state.simulateRecordingStartedForTest();
      state.simulateLockForTest();
      await tester.pump();

      state.sendLockedRecording();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(state.isLocked, false);
    });

    testWidgets('cancelLockedRecording cancels and unlocks', (tester) async {
      final key = await _build(tester);
      final state = key.currentState!;

      state.simulateRecordingStartedForTest();
      state.simulateLockForTest();
      await tester.pump();

      state.cancelLockedRecording();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(state.isLocked, false);
      expect(state.isRecording, false);
    });

    testWidgets('onRecordingLockChanged fires true on lock, false on cancel', (tester) async {
      final events = <bool>[];
      final key = await _build(tester, onLockChanged: events.add);
      final state = key.currentState!;

      state.simulateRecordingStartedForTest();
      state.simulateLockForTest();
      await tester.pump();
      expect(events, [true]);

      state.cancelLockedRecording();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(events, [true, false]);
    });

    testWidgets('onRecordingLockChanged NOT fired on normal (unlocked) stop', (tester) async {
      final events = <bool>[];
      final key = await _build(tester, onLockChanged: events.add);
      final state = key.currentState!;

      state.simulateRecordingStartedForTest();
      await tester.pump();
      // Stop while not locked — onRecordingLockChanged must not fire
      state.sendLockedRecording(); // guard: isLocked=false → no-op
      await tester.pump();

      expect(events, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd frontend && flutter test test/widgets/input/recording_controller_lock_test.dart
```

Expected: FAIL — `isLocked`, `simulateVerticalDragForTest`, `simulateLockForTest`, `simulatePointerReleaseForTest` not defined.

- [ ] **Step 3: Fix `_emitRecordingVoiceToRecipient()` provider read order**

The current method reads `ConnectionProvider` before checking `convId`. This causes `ProviderNotFoundException` in tests that don't provide `ConnectionProvider`. Reorder to guard early:

```dart
  void _emitRecordingVoiceToRecipient(bool isRecording) {
    final convs = context.read<ConversationsProvider>();
    final convId = convs.activeConversationId;
    if (convId == null) return; // guard before reading ConnectionProvider
    final conv = convs.getConversationById(convId);
    if (conv == null) return;
    final conn = context.read<ConnectionProvider>();
    final recipientId = convs.getOtherUserId(conv);
    conn.socketService.emitRecordingVoice(recipientId, convId, isRecording);
  }
```

- [ ] **Step 4: Add lock-up state fields and constants to `RecordingControllerState`**

In the `// ── recording state ──` section of `RecordingControllerState`, add:

```dart
  // ── lock-up state ─────────────────────────────────────────────────────────
  bool _isLocked = false;
  double _dragStartY = 0.0;
  double _lockDragOffset = 0.0;

  static const double _lockUpThresholdPx = 72.0;
  static const double _lockUpHintShowPx = 36.0;
```

- [ ] **Step 5: Add `isLocked` getter and `sendLockedRecording()` / `cancelLockedRecording()` public methods**

After the existing `isRecording` and `cancelDragOffset` getters:

```dart
  bool get isLocked => _isLocked;

  void sendLockedRecording() {
    if (_isRecording && _isLocked && !_isStopping) _stopRecording();
  }

  void cancelLockedRecording() {
    if (_isRecording && _isLocked) _cancelRecording();
  }
```

- [ ] **Step 6: Add `_enterLockedMode()`**

Add after `_emitRecordingVoiceToRecipient()`:

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

- [ ] **Step 7: Update `_startRecording()` to capture Y position**

Change the signature to accept `startY` and capture it:

```dart
  Future<void> _startRecording(double startX, double startY) async {
    _gestureFinishHandled = false;
    _isStartingRecording = true;
    _pendingStopAfterStart = false;
    _dragStartX = startX;
    _dragStartY = startY;
    _lockDragOffset = 0.0;
    _cancelDragOffset = 0.0;
    // ... rest of method body unchanged ...
```

Update the `onLongPressStart` call site in `build()`:

```dart
          onLongPressStart: (details) {
            _abortInFlightStart = false;
            _startRecording(details.globalPosition.dx, details.globalPosition.dy);
          },
```

- [ ] **Step 8: Update `_onRecordingDragUpdate()` for vertical + lock trigger**

Replace the existing method:

```dart
  void _onRecordingDragUpdate(double currentX, double currentY) {
    if (!_isRecording) return;
    final verticalDelta = _dragStartY - currentY; // positive = upward
    _lockDragOffset = verticalDelta.clamp(0.0, _lockUpThresholdPx);
    setState(() {
      _cancelDragOffset = currentX - _dragStartX;
      _showTrashIcon = _cancelDragOffset < -20;
    });
    if (!_isLocked && verticalDelta >= _lockUpThresholdPx) {
      _enterLockedMode();
    }
  }
```

Update its call site in `build()`:

```dart
          onLongPressMoveUpdate: (details) => _onRecordingDragUpdate(
              details.globalPosition.dx, details.globalPosition.dy),
```

- [ ] **Step 9: Update `_finishRecordingGesture()` with locked guard**

Replace:

```dart
  void _finishRecordingGesture() {
    if (_gestureFinishHandled) return;
    _gestureFinishHandled = true;
    _onLongPressFinished();
  }
```

With:

```dart
  void _finishRecordingGesture() {
    if (_isLocked) {
      _gestureFinishHandled = true; // consume — C5: no auto-send in locked mode
      return;
    }
    if (_gestureFinishHandled) return;
    _gestureFinishHandled = true;
    _onLongPressFinished();
  }
```

- [ ] **Step 10: Update `_onPointerRelease()` with locked guard**

Replace:

```dart
  void _onPointerRelease() {
    if (!_isRecording && !_isStartingRecording) return;
    _finishRecordingGesture();
  }
```

With:

```dart
  void _onPointerRelease() {
    if (!_isRecording && !_isStartingRecording) return;
    if (_isLocked) return;
    _finishRecordingGesture();
  }
```

- [ ] **Step 11: Update `_stopRecording()` finally block to include `_isLocked` reset**

In the `_stopRecording()` method from Task 2, the `finally` block currently only has `_isStopping = false`. Update it:

```dart
    } finally {
      final wasLocked = _isLocked; // capture before reset
      _isStopping = false;
      _isLocked = false;
      if (wasLocked) widget.onRecordingLockChanged?.call(false);
    }
```

Wait — `wasLocked` needs to be captured before the try block. Move it:

```dart
  Future<void> _stopRecording() async {
    if (_audioRecorder == null || !_isRecording || _isStopping) return;
    _isStopping = true;
    final wasLocked = _isLocked;
    try {
      // ... body unchanged from Task 2 ...
    } catch (e) {
      debugPrint('Stop recording error: $e');
      if (mounted) setState(() { _isRecording = false; _recordingPath = null; });
      widget.onRecordingStateChanged(false);
    } finally {
      _isStopping = false;
      _isLocked = false;
      if (wasLocked) widget.onRecordingLockChanged?.call(false);
    }
  }
```

- [ ] **Step 12: Update `_cancelRecording()` to reset `_isLocked`**

In `_cancelRecording()`, capture `wasLocked` at the top and reset at the end:

```dart
  Future<void> _cancelRecording() async {
    if (_audioRecorder == null || !_isRecording) return;

    final l10n = AppLocalizations.of(context);
    final canceledMessage = l10n.snackbarVoiceRecordingCanceled;
    final messaging = context.read<MessagingProvider>();
    final wasLocked = _isLocked;
    messaging.setIsRecordingVoice(false);
    _emitRecordingVoiceToRecipient(false);
    _canceledBySlide = true;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _recordingStartTime = null;

    await _audioRecorder!.stop();
    await _audioRecorder!.dispose();
    _audioRecorder = null;

    if (!kIsWeb && _recordingPath != null) {
      try {
        final file = File(_recordingPath!);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }

    setState(() {
      _isRecording = false;
      _isLocked = false;
      _recordingPath = null;
      _cancelDragOffset = 0.0;
      _showTrashIcon = false;
    });
    widget.onRecordingStateChanged(false);
    if (wasLocked) widget.onRecordingLockChanged?.call(false);
    _showNotSentSnackBar(canceledMessage);
  }
```

- [ ] **Step 13: Also update `dispose()` from Task 2 to reset `_isLocked`**

In `dispose()`, add `_isLocked = false;` alongside the existing resets:

```dart
    if (_isRecording || _isStartingRecording) {
      _isLocked = false;
      _isRecording = false;
      _isStopping = false;
      _releaseRecorderSilently();
    }
```

- [ ] **Step 14: Add test seams for lock gesture**

In the `// ── test seams ──` section, add:

```dart
  @visibleForTesting
  void simulateLockForTest() {
    if (!_isRecording) return;
    _enterLockedMode();
  }

  @visibleForTesting
  void simulateVerticalDragForTest(double upwardPx) {
    if (!_isRecording) return;
    // _dragStartY is 0 (default); currentY = 0 - upwardPx = negative
    _onRecordingDragUpdate(_dragStartX, _dragStartY - upwardPx);
  }

  @visibleForTesting
  void simulatePointerReleaseForTest() {
    _onPointerRelease();
  }
```

- [ ] **Step 15: Run tests**

```bash
cd frontend && flutter test test/widgets/input/recording_controller_lock_test.dart
```

Expected: PASS

- [ ] **Step 16: Run full suite + analyze**

```bash
cd frontend && flutter gen-l10n
cd frontend && flutter test test/widgets/input/
cd frontend && flutter analyze
```

- [ ] **Step 17: Commit**

```bash
git add frontend/lib/widgets/input/recording_controller.dart \
        frontend/test/widgets/input/recording_controller_lock_test.dart
git commit -m "feat(voice): slide-up lock-up gesture (72px threshold, explicit Send/Cancel)"
```

---

## Task 6 — Lock-up UI

**Files:**
- Modify: `frontend/lib/widgets/input/recording_controller.dart`
- Modify: `frontend/lib/widgets/input/chat_input_bar.dart`

**What this builds:** V4 locked state shows the locked recording bar (cancel icon + lock icon + pulsing timer + hint) in the field area, and a purple voice Send button in the trailing slot. Unlocked bar gains a slide-up hint that fades in as the user approaches the lock threshold.

- [ ] **Step 1: Add tests for lock-up UI to existing test files**

Add to `frontend/test/widgets/input/recording_controller_lock_test.dart` (inside `main()`):

```dart
  group('Lock-up UI', () {
    testWidgets('voice send icon (Icons.send_rounded) visible when locked', (tester) async {
      final key = await _build(tester);
      final state = key.currentState!;

      expect(find.byIcon(Icons.send_rounded), findsNothing);

      state.simulateRecordingStartedForTest();
      state.simulateLockForTest();
      await tester.pump();

      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
    });

    testWidgets('voice send icon hidden after cancel', (tester) async {
      final key = await _build(tester);
      final state = key.currentState!;

      state.simulateRecordingStartedForTest();
      state.simulateLockForTest();
      await tester.pump();

      state.cancelLockedRecording();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byIcon(Icons.send_rounded), findsNothing);
    });
  });
```

Add to `frontend/test/widgets/input/chat_input_bar_trailing_send_test.dart` (inside `main()`):

```dart
  group('Locked recording bar routing', () {
    testWidgets('Icons.close appears when recording locked', (tester) async {
      await tester.pumpWidget(_buildBar());
      await tester.pump();

      final rcState = tester.state<RecordingControllerState>(
        find.byType(RecordingController),
      );

      rcState.simulateRecordingStartedForTest();
      await tester.pump();
      expect(find.byIcon(Icons.close), findsNothing);

      rcState.simulateLockForTest();
      await tester.pump();
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.byIcon(Icons.lock), findsOneWidget);
    });

    testWidgets('text send hidden while locked even with draft', (tester) async {
      await tester.pumpWidget(_buildBar());
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'draft');
      await tester.pump();
      expect(find.byIcon(Icons.send), findsOneWidget);

      final rcState = tester.state<RecordingControllerState>(
        find.byType(RecordingController),
      );
      rcState.simulateRecordingStartedForTest();
      rcState.simulateLockForTest();
      await tester.pump();

      // Text send hidden (recording + locked)
      expect(find.byIcon(Icons.send), findsNothing);
    });
  });
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd frontend && flutter test test/widgets/input/recording_controller_lock_test.dart
cd frontend && flutter test test/widgets/input/chat_input_bar_trailing_send_test.dart
```

Expected: FAIL — `Icons.send_rounded`, `Icons.close`, `Icons.lock` not found.

- [ ] **Step 3: Add voice Send layer to the trailing Stack in `RecordingController.build()`**

In the `build()` Stack from Task 4, add the voice Send layer. The complete Stack should now be:

```dart
    final showVoiceSend = _isRecording && _isLocked && !widget.isSendingVoice;
    final showTextSendLayer = widget.showTextSend && !_isRecording && !widget.isSendingVoice;

    return ExcludeFocus(
      child: SizedBox(
        width: 48,
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Base: mic — always mounted (CLAUDE.md constraint)
            IgnorePointer(
              ignoring: showTextSendLayer || showVoiceSend,
              child: Opacity(
                opacity: (showTextSendLayer || showVoiceSend) ? 0.0 : 1.0,
                child: micHitTarget,
              ),
            ),

            // Text send (V1) — typing, not recording
            AnimatedOpacity(
              opacity: (showTextSendLayer && !showVoiceSend) ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              child: AnimatedScale(
                scale: (showTextSendLayer && !showVoiceSend) ? 1.0 : 0.7,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                child: Focus(
                  canRequestFocus: false,
                  child: IconButton(
                    icon: Icon(Icons.send, size: 22,
                        color: RpgTheme.primaryColor(context)),
                    onPressed: (showTextSendLayer && !showVoiceSend)
                        ? widget.onTextSend
                        : null,
                    padding: EdgeInsets.zero,
                    splashRadius: 20,
                  ),
                ),
              ),
            ),

            // Voice send (V4) — locked recording
            AnimatedOpacity(
              opacity: showVoiceSend ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              child: AnimatedScale(
                scale: showVoiceSend ? 1.0 : 0.7,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                child: Focus(
                  canRequestFocus: false,
                  child: IconButton(
                    icon: const Icon(Icons.send_rounded, size: 22,
                        color: Colors.deepPurple),
                    onPressed: showVoiceSend ? sendLockedRecording : null,
                    padding: EdgeInsets.zero,
                    splashRadius: 20,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
```

- [ ] **Step 4: Add `buildRecordingBarLocked()` to `RecordingControllerState`**

Add this new method alongside the existing `buildRecordingBar()`:

```dart
  Widget buildRecordingBarLocked(BuildContext context) {
    final isDark = RpgTheme.isDark(context);
    final fc = FireplaceColors.of(context);
    final l10n = AppLocalizations.of(context);

    return Semantics(
      label: () {
        final sec = _recordingStartTime != null
            ? DateTime.now().difference(_recordingStartTime!).inSeconds
            : 0;
        return l10n.voiceRecordingSemanticsLabel(_formatRecordingDuration(sec));
      }(),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: fc.tabBorder),
          color: fc.inputBg,
        ),
        child: Row(
          children: [
            Semantics(
              label: l10n.voiceRecordingCancelLocked,
              child: GestureDetector(
                onTap: cancelLockedRecording,
                child: const SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(
                    child: Icon(Icons.close, color: Colors.red, size: 22),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.lock, size: 14, color: Colors.deepPurple),
            const SizedBox(width: 6),
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, _) {
                final sec = _recordingStartTime != null
                    ? DateTime.now().difference(_recordingStartTime!).inSeconds
                    : 0;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.red.withValues(
                          alpha: 0.7 + (_pulseController.value * 0.3),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatRecordingDuration(sec),
                      style: RpgTheme.bodyFont(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                l10n.voiceRecordingLocked,
                overflow: TextOverflow.ellipsis,
                style: RpgTheme.bodyFont(
                  fontSize: 12,
                  color: Colors.deepPurple,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
```

- [ ] **Step 5: Add slide-up hint to `buildRecordingBar()` (unlocked)**

In `buildRecordingBar()`, find the existing `Expanded` child at the right side of the Row:

```dart
            Expanded(
              child: Opacity(
                opacity: _showTrashIcon ? 0.0 : 1.0,
                child: Text(
                  l10n.voiceRecordingSlideToCancel,
```

Replace with:

```dart
            Expanded(
              child: Opacity(
                opacity: _showTrashIcon ? 0.0 : 1.0,
                child: _lockDragOffset > _lockUpHintShowPx
                    ? Opacity(
                        opacity: (_lockDragOffset - _lockUpHintShowPx) /
                            (_lockUpThresholdPx - _lockUpHintShowPx),
                        child: Text(
                          l10n.voiceRecordingSlideUpToLock,
                          style: RpgTheme.bodyFont(
                            fontSize: 13,
                            color: Colors.deepPurple,
                          ),
                        ),
                      )
                    : Text(
                        l10n.voiceRecordingSlideToCancel,
                        style: RpgTheme.bodyFont(
                          fontSize: 14,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
              ),
            ),
```

- [ ] **Step 6: Update `ChatInputBar.build()` to route locked recording bar**

In `chat_input_bar.dart`, find the recording bar routing in the `Expanded` child inside the Row. Currently:

```dart
                  child: _isRecording
                      ? (_recordingKey.currentState
                              ?.buildRecordingBar(context) ??
                          const SizedBox.shrink())
```

Replace with:

```dart
                  child: _isRecording
                      ? (_isLocked
                          ? (_recordingKey.currentState
                                  ?.buildRecordingBarLocked(context) ??
                              const SizedBox.shrink())
                          : (_recordingKey.currentState
                                  ?.buildRecordingBar(context) ??
                              const SizedBox.shrink()))
```

- [ ] **Step 7: Run all tests**

```bash
cd frontend && flutter gen-l10n
cd frontend && flutter test test/widgets/input/recording_controller_lock_test.dart
cd frontend && flutter test test/widgets/input/chat_input_bar_trailing_send_test.dart
cd frontend && flutter test test/widgets/input/
```

Expected: all pass.

- [ ] **Step 8: Analyze**

```bash
cd frontend && flutter analyze
```

- [ ] **Step 9: Commit**

```bash
git add frontend/lib/widgets/input/recording_controller.dart \
        frontend/lib/widgets/input/chat_input_bar.dart
git commit -m "feat(voice): lock-up UI — locked recording bar + voice send button (Phase 1)"
```

---

## Task 7 — Version bump + final verification

**Files:**
- Modify: `frontend/pubspec.yaml`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Bump version in `frontend/pubspec.yaml`**

Change `version: 0.0.17+17` to `version: 0.0.18+18`.

- [ ] **Step 2: Run full frontend test suite**

```bash
cd frontend && flutter gen-l10n && flutter analyze && flutter test
```

Expected: all pass, no errors.

- [ ] **Step 3: Run backend tests (regression check)**

```bash
cd backend && npm test
```

Expected: 281 tests pass (verify count with `node scripts/verify-claude-backend-test-counts.mjs`).

- [ ] **Step 4: Manual QA on iPhone PWA**

- [ ] Type text → send button fades in (mic disappears)
- [ ] Tap Send → keyboard stays open, text clears, ready for next message
- [ ] Send message → tap text field (already focused, keyboard hidden) → keyboard opens → **no black screen**
- [ ] Hold mic → slide up 72+ px → feel haptic → locked bar appears with Cancel + purple Send
- [ ] In locked mode → tap voice Send → voice message sends
- [ ] In locked mode → tap Cancel (×) → snackbar "Voice recording canceled"
- [ ] Hold mic → release normally (no slide up) → voice auto-sends
- [ ] Hold mic → slide left → cancel → snackbar

- [ ] **Step 5: Manual QA on Android native**

- [ ] Hold mic → slide up → lock → Send → sends
- [ ] Short hold (<500ms) → "Hold longer" snackbar
- [ ] Draft text → hold mic → record → cancel → draft still present

- [ ] **Step 6: Update CLAUDE.md §1 Frontend — hold-to-record bullet**

Replace the existing hold-to-record bullet (search for `**Hold-to-record (voice):**`) with:

```
- **Hold-to-record (voice):** Use **one** `GestureDetector` for idle + recording. Wrap mic in `Listener` (`onPointerUp`/`onPointerCancel`) for PWA release. `_finishRecordingGesture()` + `_gestureFinishHandled` dedupes pointer vs `onLongPressEnd`. `_pendingStopAfterStart` if user releases during async start. `_abortInFlightStart` on `onLongPressCancel` while starting. Minimum clip: `kMinVoiceRecordingMs` (500ms) from `_recordingStartTime`. `HapticFeedback.lightImpact()` on start (native only). **Lock-up:** `_lockUpThresholdPx=72`, `_lockUpHintShowPx=36`; slide up → `_enterLockedMode()` (medium haptic); locked release is a no-op (`_finishRecordingGesture` returns early + sets `_gestureFinishHandled=true`); explicit `sendLockedRecording()` or `cancelLockedRecording()` required. Spec: `docs/superpowers/specs/2026-05-28-composer-send-mic-lockup-design.md`. Regression: `recording_controller_lock_test.dart`, `chat_input_bar_trailing_send_test.dart`. **iOS scroll fix:** `ChatComposerViewport` resets Safari scroll on `keyboardInset 0→>0` via `_prevKeyboardInset` + `_scrollResetScheduled` watchdog. **Trailing slot:** 48×48 Stack — mic always mounted; text Send (`Focus(canRequestFocus:false)`, primary color) when `_hasText && !_isRecording`; voice Send (`Focus(canRequestFocus:false)`, `Colors.deepPurple`) when locked; spinner when `isSendingVoice`. **Defensive:** `_stopRecording()` wrapped in try-catch-finally — `_isStopping` always reset; `dispose()` calls `_releaseRecorderSilently()` when recording.
```

- [ ] **Step 7: Commit**

```bash
git add frontend/pubspec.yaml CLAUDE.md
git commit -m "chore: bump version 0.0.17 → 0.0.18; update CLAUDE.md for composer overhaul"
```
