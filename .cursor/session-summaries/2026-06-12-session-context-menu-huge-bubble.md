# Context-menu fix: huge messages made Copy unreachable

**Date:** 2026-06-12

## What was done
Post-deploy clipboard QA found: long-press on a very tall message (taller than ~the screen minus panel+emoji+gaps) rendered the context menu off-screen — Copy/Reply/Delete untappable. Root cause in `computeMessageContextMenuLayout`'s final fallback: it pins the bubble's BOTTOM to the composer clearance and stacks panel+emoji ABOVE the bubble top → for a 2000dp bubble the panel's Y goes deeply negative (only the emoji row was clamped to `minTop`). Fix (option A from brainstorm, user-approved): the pure function now returns `previewHeight` and, when `bubbleRect.height > (maxContentBottom − minTop − emoji − panel − 2·gap)/1.02`, clamps the preview and **centers** the emoji→preview→panel stack vertically (equal-gap geometry preserved for the clamped height). The overlay crops the replica top-aligned via `ClipRect` + `OverflowBox(minHeight/maxHeight: full bubble height)` (so text doesn't re-wrap) with a `ShaderMask` dstIn fade over the bottom 15% of the cut edge; normal-sized bubbles take the unchanged legacy path (`previewHeight == bubbleRect.height`). Matches iOS-context-menu/Telegram behavior (preview is decorative; full message stays visible under the blur scrim). Version bumped 0.0.51 → 0.0.52.

## Key files
- `frontend/lib/widgets/message/message_context_menu_overlay.dart` (clamp branch + `previewHeight` in the return record; crop/fade rendering)
- `frontend/test/widgets/message/message_context_menu_overlay_test.dart` (+4)
- `frontend/pubspec.yaml` (0.0.52), `CLAUDE.md` §7 context-menu bullet

## Verification
- New pure tests: 2000dp bubble (incl. anchored at y=−400, i.e. scrolled past top) → emoji ≥ minTop, panel bottom ≤ maxContentBottom, equal-gap geometry on clamped height; 5-row (Copy) panel variant also fits; normal bubble keeps `previewHeight == height` (legacy path untouched).
- New widget test: 2000dp bubble in 600px viewport → long-press → panel + emoji bar within screen bounds, `Copy` tap fires callback and dismisses.
- Full suite **364 green**; `flutter analyze` **zero issues**.

## Notes for next session
- Redeploy 0.0.52 and re-test the exact message that failed (long-press the huge one → menu should appear centered with a cropped, fading preview).
- Clipboard QA status from user so far: Copy ✓, photo paste works both directions ✓. Remaining from the matrix: Safari `.items` leg explicitly, Android Gboard chip, mixed text+image paste.
