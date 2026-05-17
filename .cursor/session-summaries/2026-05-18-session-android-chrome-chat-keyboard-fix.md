# Session summary — 2026-05-18

## Accomplished

- Fixed Android Chrome (tab + PWA) chat layout jump when focusing the composer TextField.
- Layered fix: viewport meta `interactive-widget=overlays-content`, `html/body` overflow lock, Android Chrome Web detection + visualViewport keyboard height, `resizeToAvoidBottomInset: false` on chat scaffold, composer lift via clamped inset math.
- Added `test/utils/keyboard_inset_math_test.dart`; existing `chat_input_bar_disappearing_banner_test.dart` still passes.

## Key files

- `frontend/web/index.html`
- `frontend/lib/utils/android_chrome_web.dart` (+ stub/web)
- `frontend/lib/utils/keyboard_inset_math.dart`
- `frontend/lib/main.dart`
- `frontend/lib/screens/chat_detail_screen.dart`
- `frontend/lib/widgets/input/chat_input_bar.dart`
- `CLAUDE.md`
- `frontend/test/utils/keyboard_inset_math_test.dart`

## Manual verify

On Android Chrome (URL + installed PWA): open chat, tap message field repeatedly — UI should stay anchored (composer above keyboard, no full-screen void). Tap message list to dismiss keyboard; safe-area padding when keyboard hidden unchanged.

## Notes

- `flutter analyze` clean on touched files; pre-existing warnings elsewhere unchanged.
- `graphify update .` run after code changes.
