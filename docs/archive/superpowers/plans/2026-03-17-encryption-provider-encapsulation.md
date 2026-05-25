# EncryptionProvider Encapsulation — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the public `encryptionService` getter from `EncryptionProvider` by delegating `saveDecryptedContent` and `getDecryptedContent` directly through the provider, so `MessagingProvider` never touches `EncryptionService` directly.

**Architecture:** Add two thin delegation methods to `EncryptionProvider` that wrap `_encryptionService.saveDecryptedContent` / `getDecryptedContent`. Replace all 5 call sites in `MessagingProvider` with the new provider methods. Remove the `encryptionService` getter. No behavior changes — pure refactor.

**Tech Stack:** Flutter 3.x, Dart, `ChangeNotifier` providers, `shared_preferences` (used inside `EncryptionService` for persistence)

---

## Context for the implementer

### Why this matters

`MessagingProvider` currently reaches into `EncryptionProvider` to call `EncryptionService` methods directly:

```dart
// Current — leaks internal service:
_encryptionProvider!.encryptionService.saveDecryptedContent(msg.id, data);
_encryptionProvider!.encryptionService.getDecryptedContent(msg.id);
```

This breaks encapsulation. If `EncryptionService` changes its method signatures or internal storage mechanism, `MessagingProvider` also breaks. The fix is to add delegation methods on `EncryptionProvider` (as already done for `encrypt()`, `decrypt()`, `ensureSession()`, etc.).

### The 5 call sites in MessagingProvider

| Line (approx) | Method | Context |
|------|--------|---------|
| ~348 | `saveDecryptedContent` | After decrypting received message with link preview |
| ~391 | `saveDecryptedContent` | After restoring own message from `messageSent` (sender persistence) |
| ~1362 | `getDecryptedContent` | History decrypt: cache-first path for received messages |
| ~1401 | `getDecryptedContent` | History decrypt: cache-first path for own sent messages |
| ~1498 | `getDecryptedContent` | Error recovery: `DuplicateMessageException` fallback |

### What the EncryptionService methods do

- `saveDecryptedContent(int id, Map<String, dynamic> data)` — stores decrypted message fields to `SharedPreferences` using key `e2e_{userId}_decrypted_{id}`. Silent on failure (try/catch). No-op if userId is null.
- `getDecryptedContent(int id)` — reads from `SharedPreferences`, falls back to `flutter_secure_storage` (legacy). Returns `null` if not found. Silent on failure.

### Pre-existing issue (carry forward, do not fix in this task)

At call site 5 (~line 1498), `MessagingProvider` uses `_encryptionProvider!` (force-unwrap). This is a pre-existing inconsistency with line 1496 (`_encryptionProvider?.getCachedDecryption`). This refactor reproduces the existing behavior — do not change the null-assertion pattern here.

### Files to touch

| File | Change |
|------|--------|
| `frontend/lib/providers/encryption_provider.dart` | Add 2 delegation methods, remove `encryptionService` getter |
| `frontend/lib/providers/messaging_provider.dart` | Replace 5 call sites with new provider methods |

No other files are affected.

### Test setup pattern (copy from existing tests)

`initializeE2E(userId)` calls `_encryptionService.initialize(userId)` which uses both `FlutterSecureStorage` and `SharedPreferences`. Both must be mocked. The emit callback is nullable (`_emit?`) — socket events are silently ignored when no callback is set, so tests can safely call `initializeE2E` without a socket.

```dart
setUp(() async {
  FlutterSecureStorage.setMockInitialValues({});
  SharedPreferences.setMockInitialValues({});
});
```

Reference: `frontend/test/services/encryption_service_content_cache_test.dart` — same pattern.

### Test file location

```
frontend/test/providers/encryption_provider_test.dart   ← create
```

Run tests: `cd frontend && flutter test test/providers/encryption_provider_test.dart --no-pub`
Run all tests: `cd frontend && flutter test --no-pub`
Run analyze: `cd frontend && flutter analyze --no-pub`

---

## Task 1: Add delegation methods to EncryptionProvider + tests

**Files:**
- Modify: `frontend/lib/providers/encryption_provider.dart`
- Create: `frontend/test/providers/encryption_provider_test.dart`

### Step 1.1: Write the failing tests
- [ ] Create `frontend/test/providers/encryption_provider_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fireplace/providers/encryption_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EncryptionProvider — decrypted content delegation', () {
    late EncryptionProvider provider;

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      provider = EncryptionProvider();
      // initializeE2E loads keys from storage; emit callback is nullable so
      // socket events are silently ignored in tests.
      await provider.initializeE2E(42);
    });

    test('saveDecryptedContent + getDecryptedContent round-trip', () async {
      await provider.saveDecryptedContent(1001, {'content': 'Hello world'});
      final result = await provider.getDecryptedContent(1001);
      expect(result, isNotNull);
      expect(result!['content'], 'Hello world');
    });

    test('getDecryptedContent returns null for unknown id', () async {
      final result = await provider.getDecryptedContent(9999);
      expect(result, isNull);
    });

    test('saveDecryptedContent persists all envelope fields', () async {
      await provider.saveDecryptedContent(1002, {
        'content': 'Check this',
        'messageType': 'TEXT',
        'linkPreviewUrl': 'https://example.com',
        'linkPreviewTitle': 'Example',
      });
      final result = await provider.getDecryptedContent(1002);
      expect(result!['content'], 'Check this');
      expect(result['linkPreviewUrl'], 'https://example.com');
      expect(result['linkPreviewTitle'], 'Example');
    });
  });
}
```

### Step 1.2: Run tests to verify they fail
- [ ] Run: `cd frontend && flutter test test/providers/encryption_provider_test.dart --no-pub`
- [ ] Expected: FAIL — `saveDecryptedContent` and `getDecryptedContent` not found on `EncryptionProvider`

### Step 1.3: Add delegation methods to EncryptionProvider

In `frontend/lib/providers/encryption_provider.dart`, in the **`// ---------- Public Interface ----------`** section (after `cacheDecryption` on ~line 153), add:

```dart
/// Persist decrypted message content to local cache.
/// Delegates to [EncryptionService.saveDecryptedContent].
/// Silent on failure (matches service behavior).
Future<void> saveDecryptedContent(
    int messageId, Map<String, dynamic> data) async {
  await _encryptionService.saveDecryptedContent(messageId, data);
}

/// Retrieve persisted decrypted message content, or null if not cached.
/// Delegates to [EncryptionService.getDecryptedContent].
Future<Map<String, dynamic>?> getDecryptedContent(int messageId) async {
  return _encryptionService.getDecryptedContent(messageId);
}
```

### Step 1.4: Run tests to verify they pass
- [ ] Run: `cd frontend && flutter test test/providers/encryption_provider_test.dart --no-pub`
- [ ] Expected: PASS (3 tests)

### Step 1.5: Commit
- [ ] Run:
```bash
cd C:/Users/Lentach/Desktop/Fireplace
git add frontend/lib/providers/encryption_provider.dart frontend/test/providers/encryption_provider_test.dart
git commit -m "feat(encryption): add saveDecryptedContent + getDecryptedContent delegation on EncryptionProvider"
```

---

## Task 2: Update MessagingProvider call sites

**Files:**
- Modify: `frontend/lib/providers/messaging_provider.dart`

Replace all 5 call sites. Find each by context (line numbers may shift after Task 1 commit):

### Step 2.1: Replace call site 1 — save after received message decrypt

Find:
```dart
await _encryptionProvider?.encryptionService
    .saveDecryptedContent(decrypted.id, data);
```

Replace with:
```dart
await _encryptionProvider?.saveDecryptedContent(decrypted.id, data);
```

### Step 2.2: Replace call site 2 — save after own message (`messageSent`)

Find (inside `_addMessageToState`):
```dart
_encryptionProvider?.encryptionService
    .saveDecryptedContent(msg.id, persistData)
    .catchError((_) {});
```

Replace with:
```dart
_encryptionProvider?.saveDecryptedContent(msg.id, persistData)
    .catchError((_) {});
```

### Step 2.3: Replace call site 3 — get in history decrypt (received messages)

Find (inside `_decryptMessageHistory` — received path):
```dart
final persisted = await _encryptionProvider!.encryptionService
    .getDecryptedContent(msg.id);
```

Replace with:
```dart
final persisted = await _encryptionProvider!.getDecryptedContent(msg.id);
```

### Step 2.4: Replace call site 4 — get in history decrypt (own sent messages)

Find (inside `_decryptMessageHistory` — own message path with `msg.senderId == _currentUserId`):
```dart
final stored = await _encryptionProvider!.encryptionService
    .getDecryptedContent(msg.id);
```

Replace with:
```dart
final stored = await _encryptionProvider!.getDecryptedContent(msg.id);
```

### Step 2.5: Replace call site 5 — get in `_decryptMessageAsync` error recovery

Find (inside `catch` block after `DuplicateMessageException` comment):
```dart
final persisted = await _encryptionProvider!.encryptionService
    .getDecryptedContent(msg.id);
```

Replace with:
```dart
final persisted = await _encryptionProvider!.getDecryptedContent(msg.id);
```

Note: `_encryptionProvider!` (force-unwrap) is intentionally preserved — this is a pre-existing pattern in the file; fixing it is out of scope for this refactor.

### Step 2.6: Verify zero remaining references
- [ ] Run: `grep -n "encryptionService" frontend/lib/providers/messaging_provider.dart`
- [ ] Expected: no output

### Step 2.7: Run analyze
- [ ] Run: `cd frontend && flutter analyze --no-pub 2>&1 | grep -E "error|messaging_provider|encryption_provider"`
- [ ] Expected: no errors in these files

### Step 2.8: Run all tests
- [ ] Run: `cd frontend && flutter test --no-pub`
- [ ] Expected: all pass

### Step 2.9: Commit
- [ ] Run:
```bash
cd C:/Users/Lentach/Desktop/Fireplace
git add frontend/lib/providers/messaging_provider.dart
git commit -m "refactor(messaging): replace encryptionService getter calls with EncryptionProvider delegation methods"
```

---

## Task 3: Remove the encryptionService getter

**Files:**
- Modify: `frontend/lib/providers/encryption_provider.dart`

### Step 3.1: Verify no remaining external usages
- [ ] Run: `grep -rn "\.encryptionService" frontend/lib/ --include="*.dart"`
- [ ] Expected: no output

### Step 3.2: Remove the getter

In `frontend/lib/providers/encryption_provider.dart`, delete these 3 lines:
```dart
  /// Direct access to the underlying EncryptionService for internals that
  /// haven't been fully extracted yet.
  EncryptionService get encryptionService => _encryptionService;
```

### Step 3.3: Run analyze
- [ ] Run: `cd frontend && flutter analyze --no-pub 2>&1 | grep -E "error"`
- [ ] Expected: no new errors
- [ ] Static analysis confirms no remaining references to the removed getter.

### Step 3.4: Run all tests
- [ ] Run: `cd frontend && flutter test --no-pub`
- [ ] Expected: all pass

### Step 3.5: Commit
- [ ] Run:
```bash
cd C:/Users/Lentach/Desktop/Fireplace
git add frontend/lib/providers/encryption_provider.dart
git commit -m "refactor(encryption): remove public encryptionService getter — encapsulation complete"
```

---

## Done

`EncryptionProvider` is now the single point of access for all encryption operations. `MessagingProvider` has no direct dependency on `EncryptionService`. Future changes to storage format or method signatures in `EncryptionService` only require updating `EncryptionProvider`.
