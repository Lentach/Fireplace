# iOS keyboard focus guard + viewport debounce

**Date:** 2026-05-29

## What was done

### Housekeeping
- Removed all `.kiro/` files from git tracking (`git rm -r .kiro/`) — they were tracked and deploying to prod
- Confirmed `docs/superpowers/` was also tracked (same issue) — user to run `git rm -r --cached docs/superpowers/` separately
- Verified two prior E2E test commits (44919f2, 383fbba) were genuine fixes, not papering — traced Signal library source to confirm `InvalidMessageException('Bad Mac!')` detection is correct

### iOS PWA keyboard bounce — 6 iterations (v0.0.19 → v0.0.24)
Bug: **iOS Safari PWA only**. Android Chrome PWA never exhibited this. iPhone 14, tested physically.

| Version | Approach | Result |
|---------|----------|--------|
| v0.0.19 | Focus guard infra + touchstart preventDefault only | Keyboard closed, stayed closed |
| v0.0.20 | touchend `.focus()` (user-gesture context) | Keyboard bounced back ✅, but visible down→up animation |
| v0.0.21 | touchend `preventDefault()` + `.focus()` | Same bounce, `preventDefault` on touchend doesn't prevent iOS blur |
| v0.0.22 | Replaced touchend with `blur` event listener on textarea | **Regression** — keyboard closed, stayed closed. `_isEditable(document.activeElement)` returned false (Flutter's text element wasn't matching), guard never activated, no fallback |
| v0.0.23 | Reverted to v21 touchend approach + `ChatComposerViewport` 450ms inset debounce | Keyboard bounces back ✅, black screen flash eliminated ✅ |
| v0.0.24 | FocusNode listener fires microtask restore the moment Flutter sees focus loss | **Not yet confirmed on device** |

### Root cause analysis (confirmed)
- iOS Safari fires `resignFirstResponder` on the native UITextField (Flutter's text input) whenever any non-input DOM element is tapped — this is OS-level, not preventable from JS or Flutter web APIs
- Keyboard returns because Flutter's `SystemChannels.textInput.invokeMethod('TextInput.show')` goes through UIKit native channel — works outside user-gesture context
- `_savedElement = document.activeElement` in JS guard was working for touchend approach but not for blur listener (Flutter's textarea element may not always match `_isEditable` during tap)

### What v0.0.24 does differently
- `_onFocusLostAfterSend` FocusNode listener: when `_sendJustFired` flag is true and focus is lost, fires `Future.microtask` to call `requestFocus()` + `TextInput.show` — much faster than postFrameCallback
- `_sendJustFired` armed in `_send()`, auto-disarmed after 500ms so intentional blur post-send is respected
- `showSoftKeyboardIfHidden` no longer checks `viewInsets.bottom > 0` — fires even mid-dismiss-animation

### ChatComposerViewport debounce (v0.0.23, permanent)
- `viewInsets.bottom` drops `336→0→336` during the keyboard bounce → caused two full Flutter re-renders → black screen flash + layout jump
- Fix: `_keyboardInset` field in `_ChatComposerViewportState` grows immediately, shrinks only after 450ms timer
- Layout stays stable during the entire bounce animation

## Key files
- `frontend/lib/utils/web_focus_guard_web.dart` — JS touchstart/touchend guard, saves `_savedElement`, restores in touchend
- `frontend/lib/utils/web_focus_guard.dart` — conditional import facade
- `frontend/lib/utils/web_focus_guard_stub.dart` — no-op stub for non-web
- `frontend/lib/widgets/input/focus_guard_area.dart` — Flutter widget that registers rect with guard
- `frontend/lib/widgets/input/chat_input_bar.dart` — `_onFocusLostAfterSend`, `_sendJustFired`, `_send()`
- `frontend/lib/utils/soft_keyboard_web.dart` — `showSoftKeyboardIfHidden` (removed viewInsets guard)
- `frontend/lib/widgets/input/chat_composer_viewport.dart` — 450ms keyboard inset debounce

## Verification
- `flutter analyze` passes on all changed files
- Physical device: iPhone 14 iOS Safari PWA (user testing), Huawei Android Chrome PWA
- Android: no keyboard issues (confirmed)
- iOS v0.0.24: not yet confirmed on device

## Notes for next session
- **Deploy pending**: v0.0.24 pushed but user hasn't deployed + confirmed yet
- **If v0.0.24 still bounces visibly**: the bounce is the iOS keyboard animation itself starting before Flutter receives the blur event — it is an iOS PWA limitation, not fixable from web layer. Document in CLAUDE.md Known Limitations and stop iterating. The layout no longer jumps (v0.0.23 debounce), which is the worst artifact.
- **If bounce is still unacceptable**: only solution is a native iOS Flutter app build (not PWA)
- **docs/superpowers git tracking**: still needs `git rm -r --cached docs/superpowers/` + commit to stop it deploying to prod
- **Known Limitation to add to CLAUDE.md**: "iOS Safari PWA: keyboard briefly dips after send-button tap (OS-level `resignFirstResponder` cannot be prevented from web). Layout is stable (ChatComposerViewport debounce). Android unaffected."
- Version is `0.0.24`
