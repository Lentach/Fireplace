# Session 2026-05-18 — Revert web keyboard layout fixes

## What was done

- Reverted all 2026-05-18 chat keyboard layout fix commits: `21d98d7`, `da31e6a`, `d4fc67b` (kept earlier `50afc0e` revert of `fa73526` in history).
- Removed `web_keyboard_inset.dart`, `web_viewport_scroll*.dart`, related tests, `index.html` overlays-content / overflow lock.
- Restored default `resizeToAvoidBottomInset: true` and standard composer padding on web.
- Documented open bug in **CLAUDE.md §9 Known Limitations** (Android Chrome PWA layout jump on composer focus).

## Status

Bug unfixed — deferred until on-device DevTools / targeted refactor.

## Key files

- `CLAUDE.md` (Known Limitations entry)
- `frontend/lib/screens/chat_detail_screen.dart`, `chat_input_bar.dart`, `frontend/web/index.html` (reverted)
