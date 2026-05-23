# Session summary — 2026-05-18 (web keyboard host scroll)

## Accomplished

- Added minimal complementary fix for intermittent Android Chrome web chat layout jump (composer high, theme void below).
- Layer 1 (existing): `resizeToAvoidBottomInset: !kIsWeb` + `effectiveChatKeyboardInset()` cap at 45%.
- Layer 2 (new): `interactive-widget=overlays-content` + `html,body { overflow:hidden }` in `frontend/web/index.html`; `resetWebDocumentScroll()` on composer focus via `utils/web_viewport_scroll.dart` (no UA sniffing, no visualViewport listeners).
- Tests: `web_viewport_scroll_test.dart`, `index_html_viewport_test.dart`.
- Commit `21d98d7` pushed to `origin/master`.

## Key files

- `frontend/web/index.html`
- `frontend/lib/utils/web_viewport_scroll*.dart`
- `frontend/lib/widgets/input/chat_input_bar.dart`
- `CLAUDE.md`

## Notes for next session

- Manual QA on Android Chrome: open chat, tap composer repeatedly; confirm no upward shift / void; keyboard still usable; dismiss keyboard and re-open.
- If bug persists, consider single visualViewport scroll listener (not full fa73526 stack).
