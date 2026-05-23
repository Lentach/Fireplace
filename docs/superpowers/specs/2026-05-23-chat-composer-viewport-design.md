# Chat Composer Viewport — Design Spec

**Date:** 2026-05-23  
**Status:** Approved (parent task — implement ChatComposerViewport for native Android chat)

---

## Problem Statement

On **Android native** (and sometimes other mobile targets), tapping the chat composer—especially when **reply preview** appears—causes a large layout jump: the whole screen shifts up, a band of theme background (white/black) fills the lower half, and the composer may sit under the header while the keyboard still works.

**Root cause (compound):**

1. `Scaffold(resizeToAvoidBottomInset: true)` resizes the body when the IME opens.
2. `Column` with `Expanded(ListView)` + `ChatInputBar` at the bottom: when the composer grows (reply bar, action panel, disappearing banner), `Expanded` **shrinks** the message list in the same frame as keyboard inset changes.
3. `ChatInputBar` toggles `bottomInteractivePadding` (0 when keyboard visible, 16+ when hidden), adding a second height change when focus/IME state updates.
4. `ChatDetailScreen.build()` schedules keyboard open auto-scroll and compares `_lastKeyboardHeight` on every rebuild—side effects during layout.
5. `showSoftKeyboardIfHidden` (`TextInput.show`) was added in v0.0.7 as a workaround; it can fight the framework when layout is unstable.

**Out of scope / do not repeat:** Web-only `visualViewport` caps, `interactive-widget=overlays-content` in `index.html`, and `resizeToAvoidBottomInset: !kIsWeb` hacks (reverted May 2026). This change targets **structural** layout ownership, not browser UA sniffing.

---

## Goal

- Tapping composer or enabling reply preview **does not** jump the full screen or leave a large empty gap.
- Keyboard open: messages stay readable; newest message remains near the composer (existing auto-scroll behavior, moved out of `build()`).
- Preserve: IME-only send, stable mic widget tree, `context.select` in `ChatInputBar`, horizontal safe-area on list only, web mobile bottom inset fallback inside composer.

---

## Product Decisions (Locked)

| Decision | Choice |
|----------|--------|
| Primary fix target | Native **non-embedded** `ChatDetailScreen` (`isEmbedded == false`) |
| Scaffold inset | `resizeToAvoidBottomInset: false` on that path |
| Composer position | `Stack` + `Positioned` bottom, lifted by `viewInsets.bottom` |
| List clearance | `ListView` bottom padding = measured composer height + keyboard inset |
| Reply preview | Stays inside `ChatInputBar`; viewport measures total composer height (no `Expanded` shrink) |
| Embedded desktop sidebar | Keep existing `Column` for this slice (lower risk; follow-up if needed) |
| `showSoftKeyboardIfHidden` | Remove calls from `ChatInputBar`; delete `soft_keyboard.dart` if unused |
| Version | Bump PATCH to **0.0.8** (production-worthy layout fix) |

---

## Approaches Considered

### 1. Tune `resizeToAvoidBottomInset` + padding only (rejected)

- Tweak Scaffold flag per platform, cap insets, keep Column.
- **Pros:** Small diff.
- **Cons:** Does not fix reply-bar shrinking `Expanded`; same class of bug as reverted web patches.

### 2. `ChatComposerViewport` — Stack + measured composer (chosen)

| Piece | Behavior |
|-------|----------|
| Messages | Full-height scrollable; bottom padding from composer measurement + `viewInsets.bottom` |
| Composer | `Positioned(left: 0, right: 0, bottom: viewInsets.bottom)` |
| Height | `GlobalKey` + post-frame measure; rebuild list padding when height changes |
| Keyboard scroll | `WidgetsBindingObserver.didChangeMetrics` in screen (not `build()`) |

**Pros:** Decouples list height from composer height; matches Telegram/WhatsApp pattern.  
**Cons:** New widget + measure pass; must keep padding in sync with reply/action panel.

### 3. Separate overlay route for composer (rejected)

- **Pros:** Maximum isolation.
- **Cons:** Breaks provider/context wiring, overkill for this bug.

---

## Architecture

### New: `chat_composer_viewport.dart`

- **Inputs:** `messageListBuilder(double listBottomPadding)`, `composer` widget.
- **Outputs:** None (pure layout).
- **Measure:** After layout, read composer `RenderBox.size.height`; update state if changed.
- **Stack:** List fills stack; composer overlaid at bottom with keyboard inset.

### `ChatDetailScreen` (non-embedded)

- `Scaffold(resizeToAvoidBottomInset: false)`.
- Body: `Column(pinnedBanner?, Expanded(ChatComposerViewport(...)))`.
- `ListView` padding: `bottom: 8 + listBottomPadding` (existing 8 preserved).
- Remove `_lastKeyboardHeight` logic from `build()`; use `didChangeMetrics` for one-shot scroll-to-bottom when keyboard opens.

### `ChatInputBar`

- Remove `showSoftKeyboardIfHidden` import and all call sites.
- Keep `context.select`, reply focus `requestFocus`, IME send path unchanged.
- `bottomInteractivePadding` remains inside composer (viewport measures it).

### Testing

- Widget test: when composer height notifier/padding increases, list receives larger bottom padding without being wrapped in shrinking `Expanded` sibling (structural test on `ChatComposerViewport`).
- Existing chat tests must pass; run `flutter analyze` on touched files.

---

## Success Criteria (Manual QA — Android emulator)

1. Open chat → tap composer → no full-screen white/black gap; composer stays at bottom above keyboard.
2. Swipe-reply → reply bar appears → no list “jump” to top; only bottom padding adjusts smoothly.
3. Dismiss reply → layout stable.
4. Send message → keyboard stays (IME refocus behavior unchanged).
5. Rotate portrait↔landscape (if allowed) → recovers without stuck gap.

---

## Follow-ups (not this slice)

- Apply `ChatComposerViewport` to **embedded** desktop detail pane if mobile web PWA reports same bug.
- Investigate whether web Android Chrome still needs separate work (Known Limitation in CLAUDE.md).
