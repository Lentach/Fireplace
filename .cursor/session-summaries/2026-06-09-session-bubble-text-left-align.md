# Session: Message-bubble text left-alignment fix

**Date:** 2026-06-09

## What was done
Fixed sent-message text rendering with a ragged left edge ("not in line"). The
sender's own text bubbles were drawn with `textAlign: TextAlign.right`, so every
multi-line outgoing message wrapped with right-aligned lines — non-standard and
visually jarring.

- Changed `TextMessageContent._buildTextWithLinks` to always use
  `TextAlign.left` (was `isMine ? TextAlign.right : TextAlign.left`).
- The *bubble position* is unchanged: sent bubbles still sit on the right via the
  `Align(centerRight)` in `ChatMessageBubble`. Only the wrapped text lines now
  read left-to-right for both sides — matching WhatsApp / iMessage / Telegram /
  Signal (confirmed via web search; the bubble goes right, the text reads left).
- Side benefit: the long-press `MessageContextMenuBubbleHighlight` replica uses a
  plain `Text` (defaults to start/left), so the old right-align made the live
  bubble desync from its own preview. Now consistent.

One-line behavioral change; no API/model/test changes required.

## Key files
- `frontend/lib/widgets/message/text_message_content.dart` (line ~63) — the fix
- `CLAUDE.md` §7 "Chat bubbles" — documented the invariant ("do NOT reintroduce
  `isMine ? TextAlign.right`")

## Verification
- `flutter analyze lib/widgets/message/text_message_content.dart` → No issues found
- `flutter test test/` → **All tests passed!** (315)

## Notes for next session
- No version bump applied (cosmetic, not yet deployed). Bump PATCH + deploy when
  bundling with other changes, per `.cursor/rules/version-bump.mdc`.
- Manual QA worth a glance: a long multi-line *sent* message in light/teal/dark
  themes to confirm the left edge is flush and the bottom-right time overlay is
  still correctly placed.
