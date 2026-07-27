# iOS action panel keyboard bug

**Date:** 2026-05-29

## What was done

### Housekeeping (same session, earlier)
- Untracked `docs/superpowers/` from git (44 files, was deploying to prod; already in `.gitignore`)
- Updated CLAUDE.md Known Limitations: iOS PWA keyboard bounce confirmed as OS-level ceiling (Safari + Chrome both affected)

### Bug: keyboard appeared when opening action panel (iOS PWA)

**Root cause:** The FocusGuard (`web_focus_guard_web.dart`) only fires `preventDefault` on `touchstart` when an editable element IS already focused. When keyboard is hidden (no active editable), the guard does nothing. iOS WebKit then auto-focuses the Flutter `<textarea>` on any canvas tap near it, causing the keyboard to appear unexpectedly.

**Secondary effect:** iOS may also scroll the visual viewport / layout viewport (`window.scrollY`) to bring the textarea into view. If `resetWebDocumentScroll()` doesn't fire at the right time, the Flutter canvas appears scrolled — messages visible at the top but composer + action panel hidden under or off-screen.

**Fix:** `_toggleActionPanel` in `chat_input_bar.dart` now handles two iOS paths:
1. `hadComposerFocus = true` (keyboard was open): keep keyboard open + call `resetWebDocumentScroll()` after the frame.
2. `hadComposerFocus = false && _showActionPanel` (opening from hidden state): in postFrameCallback, call `_focusNode.unfocus()` to dismiss the auto-focused textarea + `resetWebDocumentScroll()` to undo any viewport scroll.

**Keyboard bounce** (send button): confirmed iOS PWA ceiling — affects Safari and Chrome equally. Documented in CLAUDE.md Known Limitations. Do not iterate further.

## Key files
- `frontend/lib/widgets/input/chat_input_bar.dart` — `_toggleActionPanel()` (iOS WebKit branch added for `!hadComposerFocus && _showActionPanel`)
- `frontend/pubspec.yaml` — bumped `0.0.24 → 0.0.25`
- `CLAUDE.md` — added iOS action panel toggle note + updated Known Limitations

## Verification
- `flutter analyze lib/widgets/input/chat_input_bar.dart` → No issues found
- Physical iPhone 14 testing pending (deploy v0.0.25 to prod)

## Notes for next session
- **Deploy pending:** v0.0.25 pushed, needs deployment + iPhone 14 confirmation
- **Test scenarios on iPhone:**
  1. Open action panel while keyboard hidden → keyboard should NOT appear, action panel visible at bottom
  2. Open action panel while keyboard visible → keyboard stays open, action panel visible above keyboard
  3. Close action panel → composer returns to normal state
  4. Send message → keyboard bounce still happens (known limitation), no black screen flash
- **If unfocus causes flash (keyboard briefly appears then hides):** consider calling `unfocus()` synchronously before `setState` in `_toggleActionPanel` — the postFrameCallback approach should be fine but may show 1–2 frames of keyboard
- Version is `0.0.25`
