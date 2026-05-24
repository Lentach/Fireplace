# Session: Context menu overlay spacing & alignment

**Date:** 2026-05-24

## Accomplished

- Refactored `computeMessageContextMenuLayout` to use a unified stack anchor (`standardStack` / `invertedStack`) so emoji, bubble highlight, and action panel always share equal vertical gaps.
- Increased overlay gap to **10dp** (`kMessageContextMenuOverlayGap`); exported `kMessageContextMenuEmojiRowHeight`.
- Accounted for **1.02 scale overflow** on bubble highlight when computing gaps (fixes panel appearing flush to tall media bubbles).
- Fixed inverted-layout bottom clip: no longer places bubble above panel when compressing near composer.
- **Horizontal alignment:** emoji bar now trailing/leading aligned with bubble (same as panel) via `isMine` in `computeEmojiBarLeft`.
- Added tests for exact gap math, inverted layout, and emoji bar edge alignment.
- All 11 overlay tests pass.

## Key files

- `frontend/lib/widgets/message/message_context_menu_overlay.dart`
- `frontend/test/widgets/message/message_context_menu_overlay_test.dart`
- `CLAUDE.md`

## Notes for next session

- Manual QA on device/PWA: long-press sent vs received bubbles near top/bottom of chat; verify Telegram-like breathing room between emoji pill, bubble, and action panel.
