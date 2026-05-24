# Session: Context menu visual gap & alignment fix

**Date:** 2026-05-24

## Accomplished

- Root-caused why prior 10dp gap math did not match on-screen layout: **248dp emoji bar width estimate** (actual ~216dp) shifted sent-message pill left; **anchor RenderBox includes 10dp bottom margin** not in highlight replica (`bubbleRectForContextMenuLayout`); emoji row lacked fixed height / vertical centering.
- Increased overlay gap to **12dp** (`kMessageContextMenuOverlayGap`).
- Emoji bar: edge-aligned via `Positioned` `left`/`right` to bubble (no width estimate); 44dp pill with centered 36×36 emoji cells.
- Layout uses `bubbleRectForContextMenuLayout` + `bubbleHighlightVisualBottom` for scale-aware gaps.
- Added pixel-gap widget test; **13/13** overlay tests pass.

## Key files

- `frontend/lib/widgets/message/message_context_menu_overlay.dart`
- `frontend/lib/widgets/message/context_menu_bubble_anchor.dart`
- `frontend/lib/widgets/message/chat_message_bubble.dart`
- `frontend/lib/widgets/message/voice_message_content.dart`
- `frontend/test/widgets/message/message_context_menu_overlay_test.dart`
- `CLAUDE.md`

## Notes for next session

- Manual QA on device/PWA: long-press sent/received near composer; confirm Telegram-like breathing room.
