# Session note — 2026-05-11 (bottom safe area audit)

## What was done

- Read-only audit: how Fireplace handles **bottom system insets** (gesture nav / home indicator) vs **chat input** and **main tab bar**.

## Findings

- **Chat composer:** `ChatInputBar` uses `SafeArea(top: false)`; `ChatDetailScreen` also wraps the main `Column` in `SafeArea` — bottom inset is already applied on the chat path (possibly redundant double `SafeArea`).
- **Main shell:** `Scaffold` + raw `BottomNavigationBar` with **no** explicit `SafeArea`; relies on Flutter/Material layout — if mis-taps happen on **tabs**, wrapping the bar in `SafeArea(top: false)` is the usual fix.
- **Padding vs inset:** Prefer **system-driven** inset (`SafeArea`, or `MediaQuery.viewPaddingOf(context).bottom` when `padding.bottom` is consumed, e.g. keyboard), not a fixed dp-only padding.

## Code changes

- None.
