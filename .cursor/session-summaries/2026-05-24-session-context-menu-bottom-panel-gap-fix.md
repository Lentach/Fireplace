# Session: Context menu bottom panel gap fix

**Date:** 2026-05-24

## Accomplished

- Root-caused flush bottom action menu: **`MessageContextMenuBubbleHighlight` always stacked time below text**, while **`ChatMessageBubble` uses inline time for short messages** (≤25 chars). Highlight was taller than `bubbleRectForContextMenuLayout` height, so `panelTop` math left the menu visually flush.
- Highlight now mirrors `_isShortMessage` (inline `Row` for short text/ping).
- Overlay highlight uses `SizedBox(height: layoutRect.height)` so scale/gap helpers match painted footprint.
- Added `bubbleHighlightVisualTop` / `messageContextMenuPanelTop`; layout uses shared visual helpers.
- Regression: `ChatMessageBubble short text has equal top and bottom gaps` + top==bottom in pixel gap test.
- **14/14** overlay tests pass.

## Key files

- `frontend/lib/widgets/message/message_context_menu_bubble_highlight.dart`
- `frontend/lib/widgets/message/message_context_menu_overlay.dart`
- `frontend/test/widgets/message/message_context_menu_overlay_test.dart`
- `CLAUDE.md`

## Notes for next session

- Manual QA: long messages, voice/media bubbles, inverted layout near top safe area.
