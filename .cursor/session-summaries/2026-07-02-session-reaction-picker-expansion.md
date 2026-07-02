# Reaction picker in-place expansion

**Date:** 2026-07-02

## What was done

- Implemented the approved Telegram-style context-menu reaction expansion plan on `feat/emoji-reactions`.
- Added `computeExpandedReactionPickerLayout` with width, margin, keyboard, above/below, and clamped-preview geometry coverage.
- Replaced the trailing quick-reaction plus button with a chevron affordance (`context-menu-expand-reactions`).
- Replaced the full-width bottom sheet with an in-overlay `FireplaceEmojiPicker` panel anchored by the pure layout function.
- Hid the quick reaction row and action panel while expanded; kept the bubble highlight and blur scrim visible.
- Added outside-tap, picker-selection, and collapsed/expanded system-back dismissal coverage.
- Registered a `PopEntry` on the caller `ModalRoute` so system back closes the overlay instead of popping the chat route.
- Updated `frontend/CLAUDE.md` reaction memory.

## Key files

- `frontend/lib/widgets/message/message_context_menu_overlay.dart`
- `frontend/test/widgets/message/message_context_menu_overlay_test.dart`
- `frontend/CLAUDE.md`
- `graphify-out/GRAPH_REPORT.md`

## Verification

- `flutter test test/widgets/message/message_context_menu_overlay_test.dart` — passed during Task 1 after adding layout tests: 41 tests.
- `flutter test test/widgets/message/message_context_menu_overlay_test.dart` — passed during Task 2 after chevron change: 41 tests.
- `flutter test test/widgets/message/message_context_menu_overlay_test.dart` — passed during Task 3 after in-place panel change: 42 tests.
- `flutter test test/widgets/message/message_context_menu_overlay_test.dart` — passed during Task 4 after PopEntry change: 44 tests.
- `dart format lib/widgets/message/message_context_menu_overlay.dart test/widgets/message/message_context_menu_overlay_test.dart` — formatted 2 files, 1 changed.
- `flutter analyze --no-fatal-infos` — no issues found.
- `flutter test test/widgets/message/message_context_menu_overlay_test.dart test/widgets/input/chat_input_bar_send_test.dart` — all 51 targeted tests passed.
- `graphify update .` — graph rebuilt: 4547 nodes, 5737 edges, 374 communities.
- Review subagents approved Task 1, Task 2, Task 3, and Task 4.

## Notes for next session

- Branch is ready for push/on-device VM verification; do not merge to `master` without explicit user OK.
- The selection widget test uses visible suggested-row emoji `🔥` instead of offscreen `🧙`; this avoids the compact horizontal suggested row's lazy-build trap while still testing `emoji-picker-option-<emoji>` reaction toggle semantics.
