# In-Place Expanding Reaction Picker (Telegram-style) — Design

**Date:** 2026-07-02 · **Branch:** `feat/emoji-reactions` · **Status:** approved by user (chat), implementation pending

## Problem

The message context menu shows a quick-reaction pill (👍 ❤️ 😂 😮 😢 🔥). The branch currently ends that pill with a "+" (`Icons.add_reaction_outlined`) that opens a **full-width bottom sheet** containing `FireplaceEmojiPicker`. The user wants Telegram behavior instead: a **chevron-down arrow** at the end of the pill that expands the picker **in place**, anchored near the row, without a bottom sheet.

## Decisions (user-approved)

1. **Expansion style:** in-place (Telegram). The bottom-sheet path is deleted.
2. **Panel content:** the full `FireplaceEmojiPicker` (search, categories, all emojis), compact; `showSuggestedRow: true` — since the quick pill unmounts while expanded, the suggested row is the panel's "frequent reactions" header, not a duplicate (Telegram's expanded view also leads with frequently-used). *Amended from the chat-approved `false`: an empirical probe showed `emoji_picker_flutter`'s grid renders nothing under the widget-test binding (async init never completes), so the suggested row is also the only tappable selection path for widget tests.* No backspace.
3. **While expanded:** the quick-reaction row and the action panel (Reply/Copy/Edit/Pin/Delete) unmount; the highlighted bubble preview stays visible. The expanded panel must never cover the bubble.
4. **Dismissal:** outside tap and system back both close the **whole overlay** (no collapse-first step). Picking an emoji reacts (toggle if already reacted) and closes everything.

## Design

### Collapsed row

`_ContextMenuReactionEmojiBar`: the trailing IconButton becomes `Icons.keyboard_arrow_down`, key `context-menu-expand-reactions`, callback renamed `onExpand`. Semantics/tooltip reuse the existing `messageReactionMoreEmoji` ARB key ("More emoji reactions" / "Więcej reakcji emoji") — no new l10n keys.

### Expanded panel geometry (pure, testable)

New `computeExpandedReactionPickerLayout(...)` in `message_context_menu_overlay.dart`, following the file's existing pure-layout-function pattern:

- Width = `min(viewWidth − 32, 360)`; aligned to the bubble's side (right edge for own messages, left edge for received), clamped to a 16px screen margin.
- Vertical: compute free space **above** the scaled bubble highlight (down to `viewPadding.top + 8`) and **below** it (up to `viewSize.height − max(keyboardBottom, viewPadding.bottom) − 16`), each minus the standard `kMessageContextMenuOverlayGap`. Place the panel in the **larger** region; height = `min(420, region)`.
- Uses the existing `bubbleHighlightVisualTop/Bottom` helpers with the (possibly clamped) `previewHeight` from `computeMessageContextMenuLayout`, so huge-message previews are respected.
- Returns `(left, top, width, height, below)`; `below` also picks the entrance-animation anchor corner.

Because the action panel is hidden while expanded, the below-bubble region is usually large; messages near the screen bottom get the above-bubble placement.

### Overlay state

The existing `StatefulBuilder` flag `pickerOpen` becomes `pickerExpanded`. When true: the emoji-bar and action-panel `Positioned`s are not built; the expanded panel `Positioned` is built from the layout function, wrapping `FireplaceEmojiPicker` in a rounded (radius 20), elevated surface `Material` with a 150ms fade + 0.95→1.0 scale entrance (`TweenAnimationBuilder`; alignment corner from `below` × `isMine`).

### System back

The overlay is an `OverlayEntry`, not a route — today Android back pops the chat **under** an open context menu (pre-existing bug). Fix: a `WidgetsBindingObserver` (`didPopRoute` → dismiss overlay, return `true` to consume) registered when the overlay is inserted and removed on dismiss. This covers both collapsed and expanded states, satisfying decision 4.

### Deletions

- The `pickerOpen` bottom-sheet block (`Positioned(left:0,right:0,bottom:viewInsets…)` + sheet `Material`).
- Its widget test ("reaction emoji picker sheet is lifted above the keyboard inset") — superseded by layout-function tests that include `keyboardBottom`.

## Error handling

No new failure modes: reaction toggling reuses the existing `onReaction(emoji, alreadyReacted)` path; layout is pure math clamped to the viewport; degenerate tiny viewports produce a short panel rather than an overflow.

## Testing

- **Layout unit tests:** below preferred when roomier; above when bubble near screen bottom; 420 height cap; width cap + 16px margin clamps; own vs received horizontal alignment; keyboard inset shrinks the below region; huge-message `previewHeight` respected.
- **Widget tests:** arrow expands (panel appears, emoji row + action panel gone, bubble highlight still present); emoji selection via the panel's suggested row invokes `onReaction` (toggle semantics preserved) and dismisses; outside tap dismisses while expanded; `tester.binding.handlePopRoute()` dismisses (collapsed and expanded) without popping the chat route. The package grid itself is untestable (probe-verified) — grid selection shares `selectPickerEmoji` with the suggested row, so the contract is covered.

## Out of scope

- Composer emoji panel (previous task, already shipped on this branch).
- Reaction wire contract / backend — unchanged.
- Skin-tone or custom-reaction sets.
