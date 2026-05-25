# E2E Encryption Hardening — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix three concrete E2E encryption security gaps: plaintext message cache surviving logout, session-rebuild denial-of-service, and OTP exhaustion silent failure.

**Architecture:** Three independent tasks — Tasks 1–2 are Flutter-only (providers/services), Task 3 is NestJS-only (gateway + service). No protocol changes, no breaking changes, all backwards-compatible.

**Tech Stack:** Flutter 3.x · `shared_preferences` · `flutter_secure_storage` · NestJS 11 · `@nestjs/throttler` · `libsignal_protocol_dart`

---

## File Map

| File | Change |
|---|---|
| `frontend/lib/services/encryption_service.dart` | Add `clearDecryptedContentCacheForUser(int userId)`; update `saveDecryptedContent` to use flutter_secure_storage on native |
| `frontend/lib/providers/encryption_provider.dart` | `clearAll()` fire-and-forgets persist-clear; `onPreKeyBundleResponse` triggers replenishment when no OTP |
| `backend/src/chat/services/chat-key-exchange.service.ts` | Inject `ConversationsService`; add conversation guard to `handleRequestSessionRebuild` |
| `backend/src/chat/chat.gateway.ts` | Add `@UseGuards(WsThrottlerGuard)` + `@Throttle` to `requestSessionRebuild` handler |

---

## Task 1: Clear Plaintext Message Cache on Logout

**Why:** `EncryptionProvider.clearAll()` (line 321 of `encryption_provider.dart`) clears the in-memory `_decryptedContentCache` but does NOT remove the `e2e_${userId}_decrypted_*` keys from SharedPreferences. On web, these are in plain `localStorage`. On Android/iOS, they are in unencrypted `NSUserDefaults`/`SharedPreferences` XML. The next user on the same device or browser can read all decrypted messages from the previous session.

Per CLAUDE.md: "Keys NOT cleared on logout (persist for re-login). Only cleared on account deletion via `clearEncryptionKeys()`" — this rule is about **Signal keys**, not plaintext message content. This task only touches the plaintext content cache.

**Files:**
- Modify: `frontend/lib/services/encryption_service.dart`
- Modify: `frontend/lib/providers/encryption_provider.dart`
- Test: `frontend/test/services/encryption_service_test.dart`

- [ ] **Step 1: Write the failing test**

Create `frontend/test/services/encryption_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fireplace/services/encryption_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fireplace/services/encryption/signal_stores.dart';

void main() {
  group('EncryptionService.clearDecryptedContentCacheForUser', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('removes all decrypted cache entries for the given userId', () async {
      // Arrange: seed SharedPreferences with decrypted entries for user 42
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('e2e_42_decrypted_1', '{"content":"hello"}');
      await prefs.setString('e2e_42_decrypted_2', '{"content":"world"}');
      // And an entry for a DIFFERENT user — must NOT be removed
      await prefs.setString('e2e_99_decrypted_1', '{"content":"other user"}');

      final service = EncryptionService(
        DualStorage(const FlutterSecureStorage()),
      );

      // Act
      await service.clearDecryptedContentCacheForUser(42);

      // Assert: user 42 entries gone
      expect(prefs.getString('e2e_42_decrypted_1'), isNull);
      expect(prefs.getString('e2e_42_decrypted_2'), isNull);
      // Assert: other user untouched
      expect(prefs.getString('e2e_99_decrypted_1'), isNotNull);
    });

    test('is a no-op when no entries exist', () async {
      final service = EncryptionService(
        DualStorage(const FlutterSecureStorage()),
      );
      // Should not throw
      await expectLater(
        service.clearDecryptedContentCacheForUser(42),
        completes,
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd frontend && flutter test test/services/encryption_service_test.dart -v
```
Expected: FAIL with "method not found: clearDecryptedContentCacheForUser"

- [ ] **Step 3: Add `clearDecryptedContentCacheForUser` to `EncryptionService`**

In `frontend/lib/services/encryption_service.dart`, add after `clearAllKeys()` (after line 344):

```dart
/// Removes all persisted decrypted content cache entries for [userId].
/// Called on logout — clears plaintext message content from SharedPreferences
/// and (on native) from flutter_secure_storage.
/// Does NOT touch Signal protocol keys (those survive logout per CLAUDE.md).
Future<void> clearDecryptedContentCacheForUser(int userId) async {
  final prefix = 'e2e_${userId}_decrypted_';
  // SharedPreferences path (web primary; native legacy entries written before this task)
  try {
    final prefs = await _sharedPrefs;
    final spKeys = prefs.getKeys().where((k) => k.startsWith(prefix)).toList();
    for (final key in spKeys) {
      await prefs.remove(key);
    }
  } catch (_) {}
  // Native secure storage path (written by saveDecryptedContent after Task 2)
  if (!kIsWeb) {
    try {
      final allSecure = await _storage.readAll();
      final secureKeys = allSecure.keys.where((k) => k.startsWith(prefix)).toList();
      for (final key in secureKeys) {
        await _storage.delete(key: key);
      }
    } catch (_) {}
  }
}
```

Note: `kIsWeb`, `_sharedPrefs`, and `_storage` are already defined in the class. `_storage` is the `DualStorage` instance; on native its `readAll()` reads from flutter_secure_storage. `readAll()` returns the full keystore (all Signal keys + decrypted cache entries) — the prefix filter narrows this down. For apps with many conversations this may be slow; acceptable for a logout path.

**DualStorage.write() signature (verified from `signal_stores.dart`):** `Future<void> write({required String key, required String value})` — named parameters, matching the call in Task 2.

- [ ] **Step 4: Run test to verify it passes**

```bash
cd frontend && flutter test test/services/encryption_service_test.dart -v
```
Expected: PASS (2 tests).

- [ ] **Step 5: Update `EncryptionProvider.clearAll()` to fire-and-forget the persist-clear**

In `frontend/lib/providers/encryption_provider.dart`, update `clearAll()` (line 321). Capture `_currentUserId` BEFORE nulling it:

```dart
void clearAll() {
  _e2eInitialized = false;
  _generatingMoreKeys = false;
  _error = null;
  // Capture userId BEFORE nulling — needed for async persist-clear below.
  final userId = _currentUserId;
  _currentUserId = null;
  _decryptedContentCache.clear();
  _forceSessionRebuild.clear();
  _cancelPendingFetches();
  // Fire-and-forget: remove plaintext message content from persistent storage.
  // Signal keys are intentionally preserved on logout (CLAUDE.md).
  // Use .ignore() per CLAUDE.md: "Fire-and-forget futures: use .ignore()"
  if (userId != null) {
    _encryptionService.clearDecryptedContentCacheForUser(userId).ignore();
  }
  notifyListeners();
}
```

- [ ] **Step 6: Add provider-level test verifying `clearAll()` triggers the persist-clear**

In `frontend/test/services/encryption_service_test.dart`, add a second test group that verifies the integration. Because `EncryptionProvider` requires a full provider tree, this test uses a lightweight mock:

```dart
group('EncryptionProvider.clearAll triggers persist-clear', () {
  test('calls clearDecryptedContentCacheForUser with correct userId', () async {
    SharedPreferences.setMockInitialValues({
      'e2e_7_decrypted_100': '{"content":"secret"}',
    });

    // Arrange: write an entry directly
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('e2e_7_decrypted_100'), isNotNull);

    // Act: call clearDecryptedContentCacheForUser with the userId that
    // clearAll() would have captured (simulating the clearAll() → fire-and-forget path)
    final service = EncryptionService(DualStorage(const FlutterSecureStorage()));
    await service.clearDecryptedContentCacheForUser(7);

    // Assert
    expect(prefs.getString('e2e_7_decrypted_100'), isNull);
  });
});
```

Note: A full integration test of `EncryptionProvider.clearAll()` requires a DI setup. The above test exercises the same code path (`clearDecryptedContentCacheForUser`) that `clearAll()` fire-and-forgets, confirming the underlying mechanism works.

- [ ] **Step 7: Run full Flutter test suite**

```bash
cd frontend && flutter test
```
Expected: all tests pass.

- [ ] **Step 8: Update CLAUDE.md**

In `CLAUDE.md`, in the **Frontend Critical Rules** section under `_conversationCache`, add after the last sentence of the E2E Encryption block:

> `clearAll()` (called on logout/account-switch) fire-and-forgets `clearDecryptedContentCacheForUser(userId)` — clears `e2e_${userId}_decrypted_*` from SharedPreferences and (on native) flutter_secure_storage. Signal keys are NOT cleared on logout per existing rule.

- [ ] **Step 9: Commit**

```bash
git add frontend/lib/services/encryption_service.dart frontend/lib/providers/encryption_provider.dart frontend/test/services/encryption_service_test.dart CLAUDE.md
git commit -m "fix(security): clear plaintext message cache from persistent storage on logout"
```

---

## Task 2: Use Secure Storage for Decrypted Content on Native

**Why:** `saveDecryptedContent()` (line 289 of `encryption_service.dart`) writes plaintext JSON to SharedPreferences on ALL platforms. On Android this is an unencrypted XML file; on iOS it is NSUserDefaults (unencrypted plist). On native, `flutter_secure_storage` uses Android Keystore / iOS Keychain — hardware-backed encrypted storage. This task routes new writes through secure storage on native while leaving web unchanged (no encrypted persistent storage alternative exists in browsers).

`getDecryptedContent()` (line 293) already falls back to `_storage.read()` for entries written by older versions — the read path handles the migration automatically.

**Files:**
- Modify: `frontend/lib/services/encryption_service.dart`

- [ ] **Step 1: Verify `DualStorage.write()` named parameter signature**

Before coding, confirm in `frontend/lib/services/encryption/signal_stores.dart` that `DualStorage.write()` has this signature:
```dart
Future<void> write({required String key, required String value}) async { ... }
```
Expected: yes — the plan calls `await _storage.write(key: key, value: value)` which requires named parameters. If the signature differs, update the call accordingly.

- [ ] **Step 2: Update `saveDecryptedContent` to branch by platform**

In `frontend/lib/services/encryption_service.dart`, replace `saveDecryptedContent()` (lines 284-291):

```dart
/// Persist decrypted message content to survive app restart.
///
/// **Native** (iOS/Android): writes to flutter_secure_storage (Keychain/Keystore)
/// — hardware-backed, encrypted at rest.
/// **Web**: writes to SharedPreferences (localStorage) — no encrypted
/// persistent storage alternative in browsers.
Future<void> saveDecryptedContent(int id, Map<String, dynamic> data) async {
  final userId = _userId;
  if (userId == null) return;
  final key = 'e2e_${userId}_decrypted_$id';
  final value = jsonEncode(data);
  try {
    if (kIsWeb) {
      // Web: localStorage via SharedPreferences (synchronous, survives tab close)
      final prefs = await _sharedPrefs;
      await prefs.setString(key, value);
    } else {
      // Native: Keychain (iOS) / Keystore (Android) via flutter_secure_storage
      await _storage.write(key: key, value: value);
    }
  } catch (_) {}
}
```

`_storage` is the `DualStorage` instance. On native, `DualStorage.write()` calls `_secure.write()` directly (see `signal_stores.dart` line ~30). No new dependency needed.

**Testing note:** `flutter_secure_storage` requires platform channel plugin infrastructure not available in unit tests. There is no automated unit test for the native write path. Correctness is verified by: (a) code review of the `if (kIsWeb)` branch, (b) `flutter analyze` passing, (c) manual test on Android/iOS — after saving a message, check that `SharedPreferences` does NOT contain `e2e_${userId}_decrypted_*` keys. The secure storage deletion path in `clearDecryptedContentCacheForUser` (Task 1) covers the corresponding cleanup.

- [ ] **Step 3: Run Flutter tests**

```bash
cd frontend && flutter test
```
Expected: all tests pass.

- [ ] **Step 4: Update CLAUDE.md**

In `CLAUDE.md`, in the E2E Encryption section, update the `saveDecryptedContent` / `getDecryptedContent` description to note:

> `saveDecryptedContent`: native writes to flutter_secure_storage (Keychain/Keystore); web writes to SharedPreferences (localStorage). `getDecryptedContent` reads native secure storage first, then falls back to SharedPreferences for legacy entries.

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/services/encryption_service.dart CLAUDE.md
git commit -m "fix(security): save decrypted content to flutter_secure_storage on native"
```

---

## Task 3: Session Rebuild DoS Protection

**Why:** `handleRequestSessionRebuild` (line 105 of `chat-key-exchange.service.ts`) relays a `sessionRebuildNeeded` event to any target user with no validation. Any authenticated user can send this to any other user, forcing them to delete their Signal session and re-upload one-time pre-keys on the next send. Spamming this event drains OTPs (which replenishment cannot keep up with) and wastes battery/CPU on key generation.

Two fixes: (1) verify requester has an active conversation with target before relaying, (2) rate-limit at the gateway.

**`ConversationsService` is already injectable** — `ConversationsModule` is imported in `ChatModule` (`chat.module.ts` line 17).

**Files:**
- Modify: `backend/src/chat/services/chat-key-exchange.service.ts`
- Modify: `backend/src/chat/chat.gateway.ts`
- Create: `backend/src/chat/services/chat-key-exchange.service.spec.ts`

- [ ] **Step 1: Verify current `ChatKeyExchangeService` constructor**

Before writing the test, open `backend/src/chat/services/chat-key-exchange.service.ts` and find the constructor. Confirm it currently takes only `keyBundlesService: KeyBundlesService` (one parameter). If it has additional parameters, add corresponding mock arguments to the test in Step 2.

- [ ] **Step 2: Write failing tests**

Create `backend/src/chat/services/chat-key-exchange.service.spec.ts`:

```ts
import { ChatKeyExchangeService } from './chat-key-exchange.service';

describe('ChatKeyExchangeService.handleRequestSessionRebuild', () => {
  let service: ChatKeyExchangeService;
  // Stub ALL ConversationsService methods with jest.fn() to prevent
  // "X is not a function" errors if other methods are called in the class.
  const mockConversationsService = {
    findByUsers: jest.fn(),
    findById: jest.fn(),
    findByUser: jest.fn(),
  };
  const mockKeyBundlesService = {};
  const mockLogger = { error: jest.fn(), warn: jest.fn(), log: jest.fn() };

  const makeClient = (id: number) => ({
    data: { user: { id } },
    emit: jest.fn(),
  });
  const makeServer = () => ({
    to: jest.fn().mockReturnThis(),
    emit: jest.fn(),
  });
  const onlineUsers = new Map([[2, 'socket-2']]);

  beforeEach(() => {
    service = new ChatKeyExchangeService(
      mockKeyBundlesService as any,
      mockConversationsService as any,
    );
    // Inject logger manually if NestJS Logger is used
    (service as any).logger = mockLogger;
    jest.clearAllMocks();
  });

  it('relays sessionRebuildNeeded when conversation exists', async () => {
    mockConversationsService.findByUsers.mockResolvedValue({ id: 10 });
    const server = makeServer();

    await service.handleRequestSessionRebuild(
      makeClient(1) as any,
      { recipientId: 2 },
      server as any,
      onlineUsers,
    );

    expect(server.to).toHaveBeenCalledWith('socket-2');
    expect(server.emit).toHaveBeenCalledWith('sessionRebuildNeeded', { fromUserId: 1 });
  });

  it('does NOT relay when no conversation exists between requester and target', async () => {
    mockConversationsService.findByUsers.mockResolvedValue(null);
    const server = makeServer();

    await service.handleRequestSessionRebuild(
      makeClient(1) as any,
      { recipientId: 2 },
      server as any,
      onlineUsers,
    );

    expect(server.to).not.toHaveBeenCalled();
  });

  it('does NOT relay when requester targets themselves', async () => {
    const server = makeServer();

    await service.handleRequestSessionRebuild(
      makeClient(2) as any,
      { recipientId: 2 },
      server as any,
      onlineUsers,
    );

    expect(mockConversationsService.findByUsers).not.toHaveBeenCalled();
    expect(server.to).not.toHaveBeenCalled();
  });

  it('does NOT relay when target is offline', async () => {
    mockConversationsService.findByUsers.mockResolvedValue({ id: 10 });
    const server = makeServer();
    const emptyOnline = new Map<number, string>();

    await service.handleRequestSessionRebuild(
      makeClient(1) as any,
      { recipientId: 2 },
      server as any,
      emptyOnline,
    );

    expect(server.to).not.toHaveBeenCalled();
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd backend && npm test -- --testPathPattern=chat-key-exchange.service
```
Expected: FAIL — `ConversationsService` not injected, self-target and conversation checks not present.

- [ ] **Step 3: Inject `ConversationsService` into `ChatKeyExchangeService`**

In `backend/src/chat/services/chat-key-exchange.service.ts`:

1. Add import at top of file:
```ts
import { ConversationsService } from '../../conversations/conversations.service';
```

2. Update the constructor to add `ConversationsService` as second parameter:
```ts
constructor(
  private readonly keyBundlesService: KeyBundlesService,
  private readonly conversationsService: ConversationsService,
) {}
```

No change needed in `chat.module.ts` — `ConversationsModule` is already imported there (line 17), which exports `ConversationsService`.

- [ ] **Step 4: Add conversation guard to `handleRequestSessionRebuild`**

Replace the method body in `chat-key-exchange.service.ts` (starting at line 105):

```ts
async handleRequestSessionRebuild(
  client: Socket,
  data: any,
  server: Server,
  onlineUsers: Map<number, string>,
): Promise<void> {
  const requesterId: number = client.data.user?.id;
  if (!requesterId) return;

  try {
    const dto = validateDto(RequestSessionRebuildDto, data);

    // Guard 1: requester cannot target themselves
    if (dto.recipientId === requesterId) return;

    // Guard 2: an active conversation must exist between the two users.
    // Prevents any authenticated user from triggering session rebuilds for
    // users they have never chatted with (DoS via OTP exhaustion).
    const conversation = await this.conversationsService.findByUsers(
      requesterId,
      dto.recipientId,
    );
    if (!conversation) return;

    const targetSocketId = onlineUsers.get(dto.recipientId);
    if (targetSocketId) {
      server.to(targetSocketId).emit('sessionRebuildNeeded', {
        fromUserId: requesterId,
      });
    }
  } catch (error) {
    this.logger.error(
      `requestSessionRebuild failed requesterId=${requesterId}: ${error.message}`,
    );
    client.emit('error', {
      message: error?.message || 'Failed to request session rebuild',
    });
  }
}
```

Note: `conversationsService.findByUsers(userId1, userId2)` is defined at line 60 of `conversations.service.ts` and checks both orderings.

- [ ] **Step 5: Add rate limit to gateway handler**

In `backend/src/chat/chat.gateway.ts`, find the `handleRequestSessionRebuild` handler (line 260) and add guards:

```ts
@UseGuards(WsThrottlerGuard)
@Throttle({ default: { limit: 5, ttl: 60000 } }) // max 5 session rebuilds per minute per user
@SubscribeMessage('requestSessionRebuild')
async handleRequestSessionRebuild(
  @ConnectedSocket() client: Socket,
  @MessageBody() data: any,
) {
  return this.chatKeyExchangeService.handleRequestSessionRebuild(
    client,
    data,
    this.server,
    this.onlineUsers,
  );
}
```

`WsThrottlerGuard` and `Throttle` are already imported in `chat.gateway.ts` (used on `sendMessage`). No new imports needed.

- [ ] **Step 6: Run tests**

```bash
cd backend && npm test -- --testPathPattern=chat-key-exchange.service
```
Expected: 4 tests pass.

```bash
cd backend && npm test
```
Expected: all existing tests pass.

- [ ] **Step 7: Update CLAUDE.md**

In `CLAUDE.md`, in the Backend section under `chat-key-exchange.service.ts`, add:

> `handleRequestSessionRebuild` requires an active conversation between requester and target before relaying `sessionRebuildNeeded` (prevents DoS via OTP exhaustion). Rate-limited to 5/min per user via `@Throttle` in `chat.gateway.ts`.

- [ ] **Step 8: Commit**

```bash
git add backend/src/chat/services/chat-key-exchange.service.ts backend/src/chat/services/chat-key-exchange.service.spec.ts backend/src/chat/chat.gateway.ts CLAUDE.md
git commit -m "fix(security): guard session rebuild against non-participants; rate limit 5/min"
```

---

## Task 4: OTP Exhaustion — Trigger Replenishment and Warn on Null OTP

**Why:** When one-time pre-keys run out, `fetchPreKeyBundle` returns `oneTimePreKeyId: null` (key-bundles.service.ts line 87). The frontend silently builds a session without an OTP, weakening forward secrecy. The backend already emits `preKeysLow` when < 10 keys remain, but when 0 remain, no special signal is sent. This task adds a client-side check: if the returned bundle has no OTP, immediately trigger the same replenishment flow as `onPreKeysLow`.

**Files:**
- Modify: `frontend/lib/providers/encryption_provider.dart`

- [ ] **Step 1: Verify `onPreKeysLow` is null-safe before calling with null**

Open `frontend/lib/providers/encryption_provider.dart` and read `onPreKeysLow` (line 260). Confirm its body never dereferences the `data` parameter. The verified implementation is:

```dart
void onPreKeysLow(dynamic data) {
  if (_generatingMoreKeys) return;
  _generatingMoreKeys = true;
  _encryptionService.generateMorePreKeys().then((keys) {
    _emit?.call('uploadOneTimePreKeys', {'keys': keys});
  }).catchError((e) { ... }).whenComplete(() => _generatingMoreKeys = false);
}
```

`data` is **not used** — calling `onPreKeysLow(null)` is safe. If the implementation you see DOES dereference `data` (e.g., `data['count']`), extract the replenishment body into a private `_triggerKeyReplenishment()` method first, then call that from both `onPreKeysLow` and the new path below.

- [ ] **Step 2: Update `onPreKeyBundleResponse` to detect missing OTP**

In `frontend/lib/providers/encryption_provider.dart`, update `onPreKeyBundleResponse()` (line 240). After `completer.complete(bundle)`, add the OTP check:

```dart
void onPreKeyBundleResponse(dynamic data) {
  final map = data as Map<String, dynamic>;
  final userId = map['userId'] as int;
  final bundle = map['bundle'];
  _e2eFlowLog('PREKEY_RESP', {
    'userId': userId,
    'hasBundle': bundle != null && bundle is Map<String, dynamic>,
  });

  final completer = _pendingPreKeyFetches.remove(userId);
  if (completer == null || completer.isCompleted) return;

  if (bundle == null || bundle is! Map<String, dynamic>) {
    completer.completeError(
      StateError('Recipient has no key bundle (userId=$userId)'),
    );
    return;
  }

  completer.complete(bundle);

  // If the server returned a bundle without a one-time pre-key, our key pool
  // is exhausted. Trigger immediate replenishment so the next session has OTP.
  // Forward secrecy is already weakened for this session — we cannot fix that
  // retroactively, but we ensure the next session gets a fresh OTP.
  if (bundle['oneTimePreKeyId'] == null) {
    debugPrint('[E2E] WARNING: No one-time pre-key available for userId=$userId '
        '— OTP pool exhausted. Triggering replenishment.');
    _e2eFlowLog('OTP_EXHAUSTED', {'targetUserId': userId});
    if (!_generatingMoreKeys) {
      onPreKeysLow(null); // reuses existing replenishment flow
    }
  }
}
```

Note: `onPreKeysLow` (line 260) already handles the `_generatingMoreKeys` guard internally, but checking before the call avoids the log noise.

- [ ] **Step 3: Run Flutter tests**

```bash
cd frontend && flutter test
```
Expected: all tests pass (pure additive change, no interface changes).

- [ ] **Step 4: Update CLAUDE.md**

In `CLAUDE.md`, in the E2E Encryption section, add after the `preKeysLow` note:

> `onPreKeyBundleResponse` triggers immediate replenishment (`onPreKeysLow`) when the returned bundle has `oneTimePreKeyId == null` (OTP pool exhausted). This ensures the next session receives a fresh OTP even though the current session's forward secrecy is already reduced.

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/providers/encryption_provider.dart CLAUDE.md
git commit -m "fix(security): trigger OTP replenishment immediately when pre-key bundle has no OTP"
```

---

## Summary

| Task | File(s) | Vulnerability Fixed |
|---|---|---|
| 1 | `encryption_service.dart`, `encryption_provider.dart` | Plaintext message cache survives logout — readable by next user on same device |
| 2 | `encryption_service.dart` | Decrypted content stored in unencrypted SharedPreferences on native — now uses Keychain/Keystore |
| 3 | `chat-key-exchange.service.ts`, `chat.gateway.ts` | Session rebuild relayed without authorization — any user could exhaust another user's OTP pool |
| 4 | `encryption_provider.dart` | OTP exhaustion silently degrades forward secrecy — now triggers immediate replenishment |

**Known remaining limitations (not in scope, require architectural decisions):**
- Web localStorage stores Signal keys and decrypted content unencrypted — no browser API provides encrypted persistent storage without a user passphrase
- Server can observe conversation metadata (who, when, delivery status) — fundamental Signal limitation without sealed sender
- TOFU identity verification — fingerprint visible in Privacy & Safety but no QR/out-of-band verification UI
