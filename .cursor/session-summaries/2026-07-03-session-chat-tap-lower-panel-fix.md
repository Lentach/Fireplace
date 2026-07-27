# Chat tap lower-panel, stacked panels, solo emoji size, and CI test fixes

**Date:** 2026-07-03

## What was done
- Fixed the lower-panel tap loop introduced by `dd6abcc` / `0.0.82` in worktree `.worktrees/feat-emoji-reactions` on branch `fix-chat-ui-bugs`.
- Chat-surface taps dismiss the composer emoji picker and keyboard when only emoji is open.
- Chat-surface taps do **not** close, lower, unfocus, or otherwise disturb the lower action panel when only that panel is open.
- Enabled independent stacked panels per user choice: lower action panel and emoji picker can be visible together.
- With both panels open, chat-surface tap closes emoji and keeps the lower action panel visible/stable.
- Preserved plain outside-tap behavior: a non-chat outside tap still closes the action panel and unfocuses the composer.
- Changed solo emoji-only message size to match the 2-emoji tier: `1–2→84`, `3→64`, `4→52`, `5+→44`.
- Repaired stale jumbo widget tests that were asserting old/impossible `40`/`22` values even though the widgets render `jumboEmojiFontSize` directly.
- Fixed the CI failure in `message_context_menu_overlay_test.dart`: the length-based inline-time gate was already removed intentionally, so long text without newline stays inline; explicit newline still stacks.
- Bumped frontend semver to `0.0.85`.

## Key files
- `.worktrees/feat-emoji-reactions/frontend/lib/widgets/input/chat_input_bar.dart`
- `.worktrees/feat-emoji-reactions/frontend/test/widgets/input/chat_input_bar_send_test.dart`
- `.worktrees/feat-emoji-reactions/frontend/lib/utils/jumbo_emoji.dart`
- `.worktrees/feat-emoji-reactions/frontend/test/utils/jumbo_emoji_test.dart`
- `.worktrees/feat-emoji-reactions/frontend/test/widgets/message/text_message_content_jumbo_test.dart`
- `.worktrees/feat-emoji-reactions/frontend/test/widgets/message/message_context_menu_overlay_test.dart`
- `.worktrees/feat-emoji-reactions/frontend/lib/widgets/message/message_bubble_inline_time.dart`
- `.worktrees/feat-emoji-reactions/frontend/lib/widgets/message/chat_message_bubble.dart`
- `.worktrees/feat-emoji-reactions/frontend/CLAUDE.md`
- `.worktrees/feat-emoji-reactions/frontend/pubspec.yaml`

## Verification
- `cd .worktrees/feat-emoji-reactions/frontend && flutter test test/widgets/input/chat_input_bar_send_test.dart` — 16 tests passed.
- `cd .worktrees/feat-emoji-reactions/frontend && flutter test test/utils/jumbo_emoji_test.dart test/widgets/message/bubble_redesign_test.dart test/widgets/message/text_message_content_jumbo_test.dart` — 42 tests passed.
- `cd .worktrees/feat-emoji-reactions/frontend && flutter test test/widgets/message/message_context_menu_overlay_test.dart --name "messageBubbleUsesInlineTime"` — 4 tests passed.
- `cd .worktrees/feat-emoji-reactions/frontend && flutter test` — 503 tests passed.
- `cd .worktrees/feat-emoji-reactions/frontend && flutter analyze --no-fatal-infos` — No issues found.
- `cd .worktrees/feat-emoji-reactions && graphify update .` — graph rebuilt: 4595 nodes, 5822 edges, 366 communities.

## Notes for next session
- PR #25 is open for `fix-chat-ui-bugs`.
- Branch `fix-chat-ui-bugs` is intended for PR review/merge, not direct deploy from stale root.
- Deploy/test from `.worktrees/feat-emoji-reactions` / branch `fix-chat-ui-bugs` if doing branch device QA.
- Verify actual device Settings footer `gitCommit`; `/version.json` does not include the commit.
- Installed iOS PWA cache can stay stale. Fully close/reopen or test Safari/incognito; do not uninstall or clear site data because that wipes E2E keys.
