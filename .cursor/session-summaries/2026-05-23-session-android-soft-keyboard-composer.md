# Session summary — 2026-05-23 — Android soft keyboard / composer

## What was accomplished

- Fixed native Android issue where the soft keyboard hid while the text field kept focus (user saw the floating IME menu with "Show on-screen keyboard"; typing still worked via emulator hardware keyboard).
- Reduced `ChatInputBar` rebuilds: `context.select` for reply target, disappearing timer, theme; removed `ReplyPreviewBar` watching full `MessagingProvider`.
- Added `utils/soft_keyboard.dart` — `showSoftKeyboardIfHidden()` calls `TextInput.show` when focus is held but `viewInsets.bottom == 0`.
- Reply flow re-shows keyboard and refocuses after quote is set.
- Version bumped to **0.0.7**.

## Key files modified

- `frontend/lib/widgets/input/chat_input_bar.dart`
- `frontend/lib/widgets/input/reply_preview_bar.dart`
- `frontend/lib/utils/soft_keyboard.dart` (new)
- `frontend/test/utils/soft_keyboard_test.dart` (new)
- `frontend/pubspec.yaml`
- `CLAUDE.md`

## Notes for next session

- User should **full restart** (`R` or stop/start `flutter run`) to see 0.0.7 in Settings.
- On emulator, if IME menu persists: AVD extended controls → disable physical keyboard, or tap **Show on-screen keyboard** once.
- Verify on real device + emulator: type in composer, swipe-reply while typing, confirm soft keyboard stays visible.
