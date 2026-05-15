# Session 2026-05-15 — Composer horizontal safe area

## Accomplished

- Fixed large dead strip (Scaffold background) to the right of the chat composer on mobile PWA / notched layouts by **not** applying horizontal `SafeArea` to the whole chat body column.
- Wrapped horizontal `SafeArea` only around the **scrollable message area** in `ChatDetailScreen`; `ChatInputBar` stays full width with `surface` edge-to-edge.
- `ChatInputBar`: row `Container` uses `EdgeInsets.fromLTRB(8 + padding.left, 8, 4 + padding.right, 8)` so cutouts stay respected; slightly tighter trailing inner padding when `padding.right` is 0; `SizedBox` between field and mic 4→2.

## Files modified

- `frontend/lib/screens/chat_detail_screen.dart`
- `frontend/lib/widgets/input/chat_input_bar.dart`
- `CLAUDE.md` (composer horizontal note)
- `graphify-out/` (via `graphify update .`)

## Tests

- `cd frontend && flutter test` — **115** passed.

## Notes for next session

- `MainShell` did not add extra horizontal padding around chat; root cause was `SafeArea` shrinking the entire `Column` including the composer.
