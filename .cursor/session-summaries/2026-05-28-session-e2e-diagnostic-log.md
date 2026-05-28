# E2E Diagnostic Log — v0.0.17

**Date:** 2026-05-28

## What was done

Added a hidden developer diagnostic panel to Privacy & Safety screen. Long-press the shield icon → panel unlocks showing last 30 E2E flow events with Copy and Clear buttons.

### New: `lib/utils/e2e_diag_log.dart`
Static ring buffer, cap=30, no `kDebugMode` gate. `add(step, data)` always writes — captures events in production release builds. `entries` returns unmodifiable snapshot (oldest→newest). `clear()` empties buffer.

### Provider wiring
Both `EncryptionProvider._e2eFlowLog` and `MessagingProvider._e2eFlowLog` now call `E2eDiagLog.add(step, data ?? {})` before the existing `debugPrint`. All E2E flow events captured unconditionally.

### UI
`PrivacySafetyScreen`: long-press `Icons.verified_user` → `_diagLogUnlocked = true`. Panel shows reversed entries (newest first) in `ConstrainedBox(maxHeight: 220)` with monospace `SelectableText` rows. Copy button copies all to clipboard. Clear button empties buffer and rebuilds. "No events recorded" when empty. Hardcoded English — developer-facing, not user-visible.

### Version bump
`pubspec.yaml`: `0.0.15` → `0.0.17` (0.0.16 was named in a previous commit message but pubspec was never updated).

## Key files

- `frontend/lib/utils/e2e_diag_log.dart` — new utility
- `frontend/test/utils/e2e_diag_log_test.dart` — 6 unit tests (cap, clear, snapshot, unmodifiable)
- `frontend/lib/providers/encryption_provider.dart` — `_e2eFlowLog` wired to `E2eDiagLog`
- `frontend/lib/providers/messaging_provider.dart` — same
- `frontend/lib/screens/privacy_safety_screen.dart` — log panel UI

## Verification

- `flutter test` — 255/255 passed
- `flutter analyze lib/screens/privacy_safety_screen.dart` — no issues

## Notes for next session

- Version is 0.0.17. Next user-visible feature → 0.0.18.
- To diagnose a production incident: open Privacy & Safety, long-press shield, Copy log, paste to developer.
- `E2eDiagLog` is in-memory only — resets on hot restart and on full app restart. It captures from the moment the app launches, not from before.
- Static state means it's shared across all tests — `setUp(() => E2eDiagLog.clear())` pattern is required in any future tests that call providers.
