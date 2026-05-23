# Session: Chat composer viewport (Android layout jump)

**Date:** 2026-05-23

## Accomplished

- Superpowers **design spec** and **implementation plan** for `ChatComposerViewport`.
- New `frontend/lib/widgets/input/chat_composer_viewport.dart`: Stack overlays composer; list bottom padding = measured composer height + keyboard inset.
- `ChatDetailScreen` (non-embedded): `Scaffold(resizeToAvoidBottomInset: false)`, `ChatComposerViewport` wraps messages + composer; keyboard auto-scroll moved to `didChangeMetrics`.
- Removed `showSoftKeyboardIfHidden` / `soft_keyboard.dart` (v0.0.7 workaround no longer needed).
- Widget tests: `test/widgets/input/chat_composer_viewport_test.dart`.
- Version **0.0.8** in `pubspec.yaml`; `CLAUDE.md` updated (viewport gotcha + Known Limitations split native vs web).
- `graphify update .` run.

## Key files

- `docs/superpowers/specs/2026-05-23-chat-composer-viewport-design.md`
- `docs/superpowers/plans/2026-05-23-chat-composer-viewport.md`
- `frontend/lib/widgets/input/chat_composer_viewport.dart`
- `frontend/lib/screens/chat_detail_screen.dart`
- `frontend/lib/widgets/input/chat_input_bar.dart`
- `frontend/test/widgets/input/chat_composer_viewport_test.dart`

## Status / next session

- **Manual QA** on Android emulator (`flutter run -d emulator-5554`): composer tap, reply preview, keyboard, send, rotation.
- **Web Android Chrome** layout jump still open (see CLAUDE §9).
- Optional: port viewport to embedded pane or mobile web if needed.
