# E2E Diagnostic Log — Design Spec

**Date:** 2026-05-28  
**Status:** Approved

---

## Problem

When `[Decryption failed]` appears in production on iOS PWA, there is no way to see what happened. All `[E2E-FLOW]` log events are gated on `kDebugMode` and only print to the console — invisible on a user's device. Diagnosis requires reproducing the issue locally or guessing from symptoms.

---

## Goal

A hidden developer panel inside Privacy & Safety that shows the last 30 E2E flow events from the current session. Accessible via long-press on the shield icon — invisible to normal users. Lets the user copy the log and share it for diagnosis.

---

## Architecture

### New file: `lib/utils/e2e_diag_log.dart`

A static utility class. No `ChangeNotifier`, no DI — just a module-level ring buffer.

```
E2eDiagLog
  static const int kMaxEntries = 30
  static final List<String> _entries = []                    // oldest-first, capped
  static void add(String step, Map<String, dynamic> data)   // appends formatted entry; prunes if over cap
  static List<String> get entries                            // unmodifiable snapshot (List.unmodifiable)
  static void clear()                                        // empties the buffer
```

Each entry is formatted as `"HH:mm:ss STEP | {data}"` using the device's local time. No DateTime objects stored — string-only to keep memory minimal.

`add()` is always called unconditionally (no `kDebugMode` guard). This is required so it captures events in release/profile builds on production PWA.

`_e2eFlowLog` in both providers passes `data ?? {}` to `E2eDiagLog.add` to satisfy the non-nullable `Map<String, dynamic>` parameter.

### Changes to existing providers

`EncryptionProvider._e2eFlowLog` and `MessagingProvider._e2eFlowLog` are currently identical private static methods:
```dart
static void _e2eFlowLog(String step, [Map<String, dynamic>? data]) {
  if (kDebugMode) debugPrint('[E2E-FLOW] $step | ${data ?? {}}');
}
```

Both get an additional line — `E2eDiagLog.add(step, data ?? {})` — placed **before** the `kDebugMode` guard so it always fires. The `debugPrint` stays as-is for local development.

No other changes to provider logic. Call sites are untouched.

### UI: `PrivacySafetyScreen`

**Unlock gesture:** Long-press on the existing `Icons.verified_user` shield icon at the top of the screen. Sets `_diagLogUnlocked = true` in local `setState`. There is no way to re-lock within the session — it stays visible until the screen is closed.

**Log panel** (shown only when `_diagLogUnlocked == true`):

- Inserted between the fingerprint section and the bottom of the scroll view.
- A `Container` with the same surface styling as the existing info cards (`surfaceContainerHighest`, `borderRadius: 12`).
- Header row: small `Icons.terminal` icon + label `"E2E Diagnostic Log"`, right-aligned row with two `TextButton`s: `"Copy"` and `"Clear"`.
- Body: `ConstrainedBox(maxHeight: 220)` wrapping a `ListView.builder` over `E2eDiagLog.entries.reversed.toList()` (newest first — `.toList()` required because `Iterable.reversed` has no `length` and `itemCount` must be an `int`). Each row is a `SelectableText` in monospace, font size 11, muted color.
- `"Clear"` calls `E2eDiagLog.clear()` then `setState`.
- `"Copy"` calls `Clipboard.setData(ClipboardData(text: entries.join('\n')))` then shows `showTopSnackBar(context, 'Log copied to clipboard')`.
- If `entries` is empty: a single centered `Text('No events recorded')` in muted style.

**Strings:** Hardcoded English. This panel is a developer/debugging tool hidden behind a gesture — ARB localization is not warranted.

---

## Data flow

```
E2eDiagLog.add()  ←  EncryptionProvider._e2eFlowLog()
                  ←  MessagingProvider._e2eFlowLog()

PrivacySafetyScreen  →  reads E2eDiagLog.entries on each setState
```

No `ChangeNotifier` subscription. The screen rebuilds the panel only when the user taps "Clear" or navigates back and returns. This is intentional — a live-updating log would be distracting and the user's workflow is: reproduce issue → open Privacy & Safety → copy log.

---

## Version bump

`frontend/pubspec.yaml`:
- Fix `0.0.15` → `0.0.16` (the cascade-fix commit named 0.0.16 but never updated pubspec)
- Then `0.0.16` → `0.0.17` for this feature

---

## Tests

`frontend/test/utils/e2e_diag_log_test.dart` — unit tests for the static ring buffer:

1. **Cap enforcement** — add 31 entries; assert `entries.length == 30` and the first entry is the 2nd one added (oldest dropped).
2. **`clear()` empties the list** — add entries, call `clear()`, assert `entries.isEmpty`.
3. **`entries` is a snapshot** — capture `entries`, add another entry, assert the captured list is unchanged (immutable snapshot).

---

## What is NOT in scope

- Persistence across restarts (in-memory only; enough for a live session)
- Automatic log sending / crash reporting
- Per-conversation or per-peer filtering
- Any ARB localization strings
- Backend changes

---

## Files changed

| File | Change |
|---|---|
| `lib/utils/e2e_diag_log.dart` | New — static ring buffer |
| `test/utils/e2e_diag_log_test.dart` | New — ring buffer unit tests |
| `lib/providers/encryption_provider.dart` | `_e2eFlowLog` also calls `E2eDiagLog.add` |
| `lib/providers/messaging_provider.dart` | `_e2eFlowLog` also calls `E2eDiagLog.add` |
| `lib/screens/privacy_safety_screen.dart` | Long-press unlock + log panel |
| `frontend/pubspec.yaml` | `0.0.15` → `0.0.17` |
| `CLAUDE.md` | Note new utility + updated version |
