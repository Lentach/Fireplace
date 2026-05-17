# Session summary — 2026-05-18 (web keyboard revert + simpler fix)

## Accomplished

- Reverted `fa73526` (layered Android Chrome keyboard fix) via `50afc0e`.
- Implemented simpler Dart-only strategy in `d4fc67b`: `resizeToAvoidBottomInset: !kIsWeb` + capped composer lift via `utils/web_keyboard_inset.dart`.
- Pushed to `origin/master`.

## Key files

- `frontend/lib/utils/web_keyboard_inset.dart`
- `frontend/lib/screens/chat_detail_screen.dart`
- `frontend/lib/widgets/input/chat_input_bar.dart`
- `frontend/test/utils/web_keyboard_inset_test.dart`
- `CLAUDE.md`

## Manual verify

Android Chrome tab + PWA: open chat, tap composer repeatedly — UI should stay anchored; no full-screen void with composer at top.
