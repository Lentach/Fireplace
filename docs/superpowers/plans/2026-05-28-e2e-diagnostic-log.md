# E2E Diagnostic Log Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a hidden E2E diagnostic log (circular buffer, 30 entries) accessible by long-pressing the shield icon in Privacy & Safety, so production PWA issues can be diagnosed without DevTools.

**Architecture:** A static `E2eDiagLog` utility class holds an in-memory ring buffer. Both `EncryptionProvider` and `MessagingProvider` call it unconditionally (no `kDebugMode` gate) alongside their existing `debugPrint`. The Privacy & Safety screen reveals a log panel after a long-press unlock gesture.

**Tech Stack:** Flutter/Dart, `package:flutter_test`, `package:flutter/services` (Clipboard).

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `frontend/lib/utils/e2e_diag_log.dart` | Static ring buffer — add, entries, clear |
| Create | `frontend/test/utils/e2e_diag_log_test.dart` | Unit tests for ring buffer behaviour |
| Modify | `frontend/lib/providers/encryption_provider.dart:11-13` | `_e2eFlowLog` also calls `E2eDiagLog.add` |
| Modify | `frontend/lib/providers/messaging_provider.dart:30-32` | `_e2eFlowLog` also calls `E2eDiagLog.add` |
| Modify | `frontend/lib/screens/privacy_safety_screen.dart` | Long-press unlock + log panel UI |
| Modify | `frontend/pubspec.yaml:9` | `version: 0.0.15` → `version: 0.0.17` |

---

## Task 1: Ring buffer — tests first

**Files:**
- Create: `frontend/test/utils/e2e_diag_log_test.dart`
- Create: `frontend/lib/utils/e2e_diag_log.dart` (stub only — enough for tests to compile and fail)

- [ ] **Step 1.1: Create the stub**

Create `frontend/lib/utils/e2e_diag_log.dart`:

```dart
class E2eDiagLog {
  static const int kMaxEntries = 30;
  static final List<String> _entries = [];

  static void add(String step, Map<String, dynamic> data) {}

  static List<String> get entries => List.unmodifiable(_entries);

  static void clear() {}
}
```

- [ ] **Step 1.2: Write the failing tests**

Create `frontend/test/utils/e2e_diag_log_test.dart`:

```dart
import 'package:fireplace/utils/e2e_diag_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => E2eDiagLog.clear());

  group('E2eDiagLog', () {
    test('add() appends an entry', () {
      E2eDiagLog.add('STEP_A', {'key': 'val'});
      expect(E2eDiagLog.entries.length, 1);
      expect(E2eDiagLog.entries.first, contains('STEP_A'));
    });

    test('cap enforcement: 31st entry drops the oldest', () {
      for (var i = 0; i < 31; i++) {
        E2eDiagLog.add('STEP_$i', {});
      }
      expect(E2eDiagLog.entries.length, 30);
      expect(E2eDiagLog.entries.first, contains('STEP_1'));
      expect(E2eDiagLog.entries.last, contains('STEP_30'));
    });

    test('clear() empties the list', () {
      E2eDiagLog.add('STEP_A', {});
      E2eDiagLog.add('STEP_B', {});
      E2eDiagLog.clear();
      expect(E2eDiagLog.entries, isEmpty);
    });

    test('entries is an immutable snapshot — mutation after read does not affect it', () {
      E2eDiagLog.add('STEP_A', {});
      final snapshot = E2eDiagLog.entries;
      E2eDiagLog.add('STEP_B', {});
      expect(snapshot.length, 1);           // snapshot not affected
      expect(E2eDiagLog.entries.length, 2); // live list has 2
    });

    test('entry format contains timestamp, step, and data', () {
      E2eDiagLog.add('DECRYPT_OK', {'msgId': 42});
      final entry = E2eDiagLog.entries.first;
      // Format: "HH:mm:ss STEP | {data}"
      expect(entry, matches(RegExp(r'\d{2}:\d{2}:\d{2}')));
      expect(entry, contains('DECRYPT_OK'));
      expect(entry, contains('msgId'));
    });
  });
}
```

- [ ] **Step 1.3: Run — confirm all fail**

```
cd frontend && flutter test test/utils/e2e_diag_log_test.dart --reporter=compact
```

Expected: `0/5 passed` — tests compile but fail because `add()` is a no-op.

---

## Task 2: Ring buffer — implementation

**Files:**
- Modify: `frontend/lib/utils/e2e_diag_log.dart`

- [ ] **Step 2.1: Implement `add()`, `entries`, `clear()`**

Replace the entire file content:

```dart
import 'package:flutter/foundation.dart';

class E2eDiagLog {
  static const int kMaxEntries = 30;
  static final List<String> _entries = [];

  static void add(String step, Map<String, dynamic> data) {
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');
    _entries.add('$hh:$mm:$ss $step | $data');
    if (_entries.length > kMaxEntries) {
      _entries.removeAt(0);
    }
  }

  static List<String> get entries => List.unmodifiable(_entries);

  static void clear() => _entries.clear();
}
```

Note: `flutter/foundation.dart` is imported for potential future `kDebugMode` use; it costs nothing. If the analyzer flags an unused import, remove it.

- [ ] **Step 2.2: Run — confirm all pass**

```
cd frontend && flutter test test/utils/e2e_diag_log_test.dart --reporter=compact
```

Expected: `5/5 passed`.

- [ ] **Step 2.3: Commit**

```
git add frontend/lib/utils/e2e_diag_log.dart frontend/test/utils/e2e_diag_log_test.dart
git commit -m "feat(e2e): add E2eDiagLog static ring buffer with tests"
```

---

## Task 3: Wire `E2eDiagLog` into both providers

**Files:**
- Modify: `frontend/lib/providers/encryption_provider.dart` (lines 1–13)
- Modify: `frontend/lib/providers/messaging_provider.dart` (lines 1–32)

Both files have an identical private static `_e2eFlowLog` method. The change is the same in each.

- [ ] **Step 3.1: Update `EncryptionProvider._e2eFlowLog`**

In `frontend/lib/providers/encryption_provider.dart`, add the import and update the method.

Current imports (top of file):
```dart
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/message_model.dart';
import '../services/encryption_service.dart';
```

New imports (add one line):
```dart
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/message_model.dart';
import '../services/encryption_service.dart';
import '../utils/e2e_diag_log.dart';
```

Current method (lines 11–13):
```dart
  static void _e2eFlowLog(String step, [Map<String, dynamic>? data]) {
    if (kDebugMode) debugPrint('[E2E-FLOW] $step | ${data ?? {}}');
  }
```

New method:
```dart
  static void _e2eFlowLog(String step, [Map<String, dynamic>? data]) {
    E2eDiagLog.add(step, data ?? {});
    if (kDebugMode) debugPrint('[E2E-FLOW] $step | ${data ?? {}}');
  }
```

- [ ] **Step 3.2: Update `MessagingProvider._e2eFlowLog`**

In `frontend/lib/providers/messaging_provider.dart`, find the existing imports block (top of file) and add:
```dart
import '../utils/e2e_diag_log.dart';
```

Then find the method (around line 30):
```dart
  static void _e2eFlowLog(String step, [Map<String, dynamic>? data]) {
    if (kDebugMode) debugPrint('[E2E-FLOW] $step | ${data ?? {}}');
  }
```

Replace with:
```dart
  static void _e2eFlowLog(String step, [Map<String, dynamic>? data]) {
    E2eDiagLog.add(step, data ?? {});
    if (kDebugMode) debugPrint('[E2E-FLOW] $step | ${data ?? {}}');
  }
```

- [ ] **Step 3.3: Run full test suite — confirm no regressions**

```
cd frontend && flutter test --reporter=compact 2>&1 | tail -3
```

Expected: `All tests passed!` (249+ tests).

- [ ] **Step 3.4: Commit**

```
git add frontend/lib/providers/encryption_provider.dart frontend/lib/providers/messaging_provider.dart
git commit -m "feat(e2e): wire E2eDiagLog into both providers (unconditional capture)"
```

---

## Task 4: Privacy & Safety screen — long-press unlock + log panel

**Files:**
- Modify: `frontend/lib/screens/privacy_safety_screen.dart`

- [ ] **Step 4.1: Add `_diagLogUnlocked` state and import**

In `privacy_safety_screen.dart`, add the import at the top (after existing imports):
```dart
import 'package:flutter/services.dart';
import '../utils/e2e_diag_log.dart';
```

In `_PrivacySafetyScreenState`, add the field alongside the existing `_fingerprint` and `_loading`:
```dart
  bool _diagLogUnlocked = false;
```

- [ ] **Step 4.2: Wrap the shield icon in a `GestureDetector`**

Current shield icon block (around line 59–67 in the `build` method):
```dart
            // Shield icon
            Center(
              child: Icon(
                Icons.verified_user,
                size: 64,
                color: theme.colorScheme.primary,
              ),
            ),
```

Replace with:
```dart
            // Shield icon — long-press unlocks E2E diagnostic log
            Center(
              child: GestureDetector(
                onLongPress: () => setState(() => _diagLogUnlocked = true),
                child: Icon(
                  Icons.verified_user,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
```

- [ ] **Step 4.3: Add the log panel at the bottom of the scroll column**

In the `build` method, find the last item in the `children` list inside `SingleChildScrollView`. Currently the list ends with the loading indicator:

```dart
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              ),
```

After that block (still inside `children`), add:
```dart
            if (_diagLogUnlocked) ...[
              const SizedBox(height: 24),
              _buildDiagLogPanel(context),
            ],
```

- [ ] **Step 4.4: Add `_buildDiagLogPanel` method**

Add this method to `_PrivacySafetyScreenState` (after `_clearLocalMessageCache`):

```dart
  Widget _buildDiagLogPanel(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = RpgTheme.isDark(context);
    final mutedColor = isDark ? RpgTheme.mutedDark : RpgTheme.textSecondaryLight;
    final entries = E2eDiagLog.entries.reversed.toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.terminal, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'E2E Diagnostic Log',
                  style: RpgTheme.bodyFont(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              TextButton(
                onPressed: () async {
                  final all = E2eDiagLog.entries.join('\n');
                  await Clipboard.setData(ClipboardData(text: all));
                  if (!mounted) return;
                  showTopSnackBar(context, 'Log copied to clipboard');
                },
                child: const Text('Copy'),
              ),
              TextButton(
                onPressed: () {
                  E2eDiagLog.clear();
                  setState(() {});
                },
                child: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: entries.isEmpty
                ? Text(
                    'No events recorded',
                    style: RpgTheme.bodyFont(fontSize: 12, color: mutedColor),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: entries.length,
                    itemBuilder: (context, index) => SelectableText(
                      entries[index],
                      style: TextStyle(
                        fontSize: 11,
                        color: mutedColor,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
```

- [ ] **Step 4.5: Run the full test suite — confirm no regressions**

```
cd frontend && flutter test --reporter=compact 2>&1 | tail -3
```

Expected: `All tests passed!`.

- [ ] **Step 4.6: Commit**

```
git add frontend/lib/screens/privacy_safety_screen.dart
git commit -m "feat(e2e): add diagnostic log panel to Privacy & Safety (long-press unlock)"
```

---

## Task 5: Version bump + CLAUDE.md

**Files:**
- Modify: `frontend/pubspec.yaml`
- Modify: `CLAUDE.md`

- [ ] **Step 5.1: Bump version in pubspec**

In `frontend/pubspec.yaml`, line 9:
```yaml
version: 0.0.15
```
→
```yaml
version: 0.0.17
```

(Skipping 0.0.16 — that version was named in a commit message but the pubspec was never updated. Going straight to 0.0.17 for this feature.)

- [ ] **Step 5.2: Update CLAUDE.md**

In the **E2E Encryption** section of `CLAUDE.md`, add a note about the diagnostic log after the cache-first history decrypt bullet:

Find:
```
- **Cache-first history decrypt:** check persisted cache before live decrypt. `EncryptionProvider` owns cache via `saveDecryptedContent()`/`getDecryptedContent()`. Cap: 2000 entries per user. "Clear local message cache" in `PrivacySafetyScreen` — clears plaintext cache + audio only, NOT Signal keys.
```

Add after it:
```
- **E2E diagnostic log:** `utils/e2e_diag_log.dart` — static ring buffer, 30 entries, always writes (no `kDebugMode` gate). Both `EncryptionProvider` and `MessagingProvider` call `E2eDiagLog.add(step, data ?? {})` in `_e2eFlowLog`. Viewable in Privacy & Safety screen via long-press on shield icon. Copy + Clear buttons. In-memory only — resets on restart.
```

- [ ] **Step 5.3: Final full test run**

```
cd frontend && flutter test --reporter=compact 2>&1 | tail -3
```

Expected: `All tests passed!`.

- [ ] **Step 5.4: Commit**

```
git add frontend/pubspec.yaml CLAUDE.md
git commit -m "chore: bump version 0.0.15 → 0.0.17, document E2eDiagLog in CLAUDE.md"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Task |
|---|---|
| `E2eDiagLog` static class, `add(String, Map<String, dynamic>)`, cap 30, `entries`, `clear()` | Task 1–2 |
| `_e2eFlowLog` in both providers calls `E2eDiagLog.add(step, data ?? {})` unconditionally | Task 3 |
| Long-press shield icon → `_diagLogUnlocked` | Task 4.2 |
| Log panel: `ConstrainedBox(maxHeight:220)`, `ListView.builder` over `.reversed.toList()`, `SelectableText` monospace | Task 4.4 |
| Copy button → `Clipboard.setData` + snackbar | Task 4.4 |
| Clear button → `E2eDiagLog.clear()` + `setState` | Task 4.4 |
| "No events recorded" when empty | Task 4.4 |
| Tests: cap enforcement, clear, snapshot immutability | Task 1–2 |
| pubspec 0.0.15 → 0.0.17 | Task 5.1 |
| CLAUDE.md update | Task 5.2 |

All requirements covered. No gaps.

**Placeholder scan:** No TBD, TODO, or vague steps. All code blocks are complete.

**Type consistency:** `E2eDiagLog.add(String, Map<String, dynamic>)` defined in Task 1 and used identically in Tasks 3 and 4. `E2eDiagLog.entries` returns `List<String>` — used as `List<String>` everywhere. `E2eDiagLog.clear()` used in Tasks 2 (tests) and 4 (UI). Consistent throughout.
