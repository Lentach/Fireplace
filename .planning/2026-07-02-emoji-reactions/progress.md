# Emoji reactions progress

**Date:** 2026-07-02

## Log
- Created isolated worktree `.worktrees/feat-emoji-reactions` on branch `feat/emoji-reactions` from `origin/master`.
- Re-read root and frontend CLAUDE files plus latest session summary inside the worktree.
- Researched Unicode/CLDR, Dart grapheme handling, Signal/Telegram behavior, Flutter overlay/sheet/semantics APIs, and `emoji_picker_flutter`.
- Added failing TDD coverage for context-menu more reactions, selected quick reaction semantics, picker selection callback, and grapheme-safe composer editing.
- Implemented `FireplaceEmojiPicker`, in-overlay expanded reaction picker, composer inline emoji picker, and grapheme-safe insert/backspace helpers.
- Added `emoji_picker_flutter` and direct `characters` dependency; bumped frontend version to `0.0.77`.
- Verification passed: `flutter analyze --no-fatal-infos`, targeted widget/helper tests, full `flutter test` (428 tests), and `graphify update .`.
- User supplied a Telegram-like emoji keyboard screenshot; adjusted picker order to match it better: search on top, emoji grid middle, category/backspace row at bottom, no separate bottom action bar.
- Post-adjustment verification passed: analyzer no issues, targeted emoji/composer/context-menu tests passed (38 tests), final full `flutter test` passed (428 tests), graphify update completed.
- Review found the expanded picker used stale `MediaQuery` values captured before `OverlayEntry` build and could return a sub-52dp picker height under constrained viewport/keyboard geometry.
- Fixed expanded picker geometry to read live overlay `MediaQuery` values, added a 52dp minimum layout height, and made `FireplaceEmojiPicker` hide its suggested row when too short instead of squeezing the grid into garbage.
- Final verification passed: `flutter analyze --no-fatal-infos`, targeted overlay/input/composer tests (56 tests), full `flutter test` (446 tests), and `graphify update .`.
