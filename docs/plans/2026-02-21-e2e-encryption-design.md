# E2E Encryption for Fireplace Messenger — Implementation Plan

**Date:** 2026-02-21
**Status:** Approved, ready for implementation

## Context

Fireplace stores messages as plaintext in PostgreSQL. The server can read all message content. This plan adds full E2E encryption (Signal Protocol) so the server never sees message content.

**User decisions:**
- Scope: text messages only (not media/voice)
- Link preview: moved to client-side (frontend fetches OG metadata before encrypting)
- Platform: mobile first, web secondary
- Key recovery: none (new device = new keys = no history, like Signal)
- Migration: clear ALL old messages when E2E is enabled
- UI: "Privacy & Safety" section in Settings (informational, no lock icons on messages)
- Library: `libsignal_protocol_dart` v0.7.4 (pure Dart, GPL-3.0, used by MixinNetwork)
- Key storage: `flutter_secure_storage` v10.0.0 (Keychain/Keystore on mobile, encrypted localStorage on web)

---

## Signal Protocol Overview (for this app)

### Key Concepts
1. **Identity Key Pair** — long-term Ed25519/Curve25519 key pair, generated once per device
2. **Signed Pre-Key** — medium-term key, signed by identity key
3. **One-Time Pre-Keys** — single-use keys, uploaded in batches of 100
4. **X3DH** — initial key agreement using identity + signed + one-time pre-key
5. **Double Ratchet** — derives unique key per message (forward secrecy)

### First Message Flow (X3DH)
```
Alice                          Server                         Bob
  │  Registration: upload       │  Registration: upload        │
  │  publicKeys ────────────────┤──────────────── publicKeys   │
  │                             │                              │
  │  fetchPreKeyBundle(bob) ────┤                              │
  │  ◄── bob's public keys ─────┤                              │
  │                             │                              │
  │  X3DH → shared secret      │                              │
  │  Double Ratchet init        │                              │
  │  encrypt("Cześć!")          │                              │
  │  sendMessage(ciphertext) ───┤── newMessage(ciphertext) ──► │
  │                             │                     X3DH     │
  │                             │                     decrypt  │
  │                             │                     → "Cześć!"│
```

### What Server Sees
```
BEFORE: { content: "Cześć Bob!" }
AFTER:  { encryptedContent: "3:a7f3b2c9e1d8...base64...", content: "[encrypted]" }
```

### Encrypted Envelope Format
```json
{
  "content": "Hello! Check out https://example.com",
  "linkPreview": {
    "url": "https://example.com",
    "title": "Example Site",
    "imageUrl": "https://example.com/og.png"
  }
}
```
This JSON is encrypted as a whole → base64 ciphertext → stored in `encryptedContent`.

### Ciphertext String Format
`"{type}:{base64_body}"` where type 3 = PreKeySignalMessage (first message), type 1 = SignalMessage (subsequent).

---

## Phase 1: Backend — Key Storage Infrastructure

**Goal:** Create DB tables and service for storing public key bundles. Purely additive — no existing functionality touched.

### New files:

**`backend/src/key-bundles/key-bundle.entity.ts`**
```typescript
@Entity('key_bundles')
export class KeyBundle {
  @PrimaryGeneratedColumn()
  id: number;

  @Column({ unique: true })
  userId: number;

  @Column()
  registrationId: number;

  @Column('text')
  identityPublicKey: string;  // base64

  @Column()
  signedPreKeyId: number;

  @Column('text')
  signedPreKeyPublic: string;  // base64

  @Column('text')
  signedPreKeySignature: string;  // base64

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
```

**`backend/src/key-bundles/one-time-pre-key.entity.ts`**
```typescript
@Entity('one_time_pre_keys')
@Index(['userId', 'used'])
export class OneTimePreKey {
  @PrimaryGeneratedColumn()
  id: number;

  @Column()
  userId: number;

  @Column()
  keyId: number;  // Signal protocol key ID

  @Column('text')
  publicKey: string;  // base64

  @Column({ default: false })
  used: boolean;

  @CreateDateColumn()
  createdAt: Date;
}
```

**`backend/src/key-bundles/key-bundles.service.ts`**

Methods:
- `upsertKeyBundle(userId, bundle)` — insert or update (ON CONFLICT userId)
- `uploadOneTimePreKeys(userId, keys[])` — bulk insert OTPs
- `fetchPreKeyBundle(userId)` — return key bundle + 1 unused OTP (mark as used). If no unused OTPs, return bundle without OTP (Signal allows this).
- `countUnusedPreKeys(userId)` — count where used=false
- `deleteByUserId(userId)` — for account deletion cascade

**`backend/src/key-bundles/key-bundles.module.ts`**
```typescript
@Module({
  imports: [TypeOrmModule.forFeature([KeyBundle, OneTimePreKey])],
  providers: [KeyBundlesService],
  exports: [KeyBundlesService],
})
export class KeyBundlesModule {}
```

### Modified files:

- **`backend/src/app.module.ts`** — import KeyBundle + OneTimePreKey entities, import KeyBundlesModule
- **`backend/src/users/users.service.ts`** — inject KeyBundlesService, call `deleteByUserId(userId)` in `deleteAccount()` cascade (after friend_requests, before user)
- **`backend/src/users/users.module.ts`** — import KeyBundlesModule

**Pattern:** follows `backend/src/fcm-tokens/` structure exactly.

---

## Phase 2: Backend — WebSocket Key Exchange Events

**Goal:** Add WebSocket events for uploading and fetching key bundles.

### New files:

**`backend/src/chat/dto/upload-key-bundle.dto.ts`**
```typescript
export class UploadKeyBundleDto {
  @IsNumber() @IsPositive() registrationId: number;
  @IsString() @MinLength(1) identityPublicKey: string;
  @IsNumber() @Min(0) signedPreKeyId: number;
  @IsString() @MinLength(1) signedPreKeyPublic: string;
  @IsString() @MinLength(1) signedPreKeySignature: string;
}
```

**`backend/src/chat/dto/upload-one-time-pre-keys.dto.ts`**
```typescript
export class OneTimePreKeyDto {
  @IsNumber() @Min(0) keyId: number;
  @IsString() @MinLength(1) publicKey: string;
}
export class UploadOneTimePreKeysDto {
  @ValidateNested({ each: true })
  @Type(() => OneTimePreKeyDto)
  keys: OneTimePreKeyDto[];
}
```

**`backend/src/chat/dto/fetch-pre-key-bundle.dto.ts`**
```typescript
export class FetchPreKeyBundleDto {
  @IsNumber() @IsPositive() userId: number;
}
```

**`backend/src/chat/services/chat-key-exchange.service.ts`**

Handlers:
- `handleUploadKeyBundle(client, data)` → validate DTO → `keyBundlesService.upsertKeyBundle()` → emit `keyBundleUploaded`
- `handleUploadOneTimePreKeys(client, data)` → validate DTO → `keyBundlesService.uploadOneTimePreKeys()` → emit `oneTimePreKeysUploaded`
- `handleFetchPreKeyBundle(client, data, server, onlineUsers)` → validate DTO → `keyBundlesService.fetchPreKeyBundle()` → emit `preKeyBundleResponse` → if remaining < 10, emit `preKeysLow` to target user

### Modified files:

- **`backend/src/chat/chat.gateway.ts`** — 3 new `@SubscribeMessage` handlers (uploadKeyBundle, uploadOneTimePreKeys, fetchPreKeyBundle), inject ChatKeyExchangeService
- **`backend/src/chat/chat.module.ts`** — import KeyBundlesModule, add ChatKeyExchangeService to providers

### WebSocket Event Table

| Client Emit | Server Emit (caller) | Server Emit (target) |
|---|---|---|
| `uploadKeyBundle` | `keyBundleUploaded` | — |
| `uploadOneTimePreKeys` | `oneTimePreKeysUploaded` | — |
| `fetchPreKeyBundle` | `preKeyBundleResponse` | `preKeysLow` (if < 10 OTPs) |

---

## Phase 3: Backend — Message Entity Changes

**Goal:** Add `encryptedContent` column, update mapper and send flow.

### Modified files:

**`backend/src/messages/message.entity.ts`** — add after `content` column:
```typescript
@Column({ type: 'text', nullable: true, default: null })
encryptedContent: string | null;
```

**`backend/src/messages/message.mapper.ts`** — add to payload:
```typescript
encryptedContent: message.encryptedContent ?? null,
```

**`backend/src/chat/dto/chat.dto.ts`** — add to SendMessageDto:
```typescript
@IsOptional() @IsString()
encryptedContent?: string;
```
Relax content validation when encryptedContent present:
```typescript
@ValidateIf((o) => !o.encryptedContent && !['VOICE', 'PING'].includes(o?.messageType))
```

**`backend/src/chat/services/chat-message.service.ts`** — in handleSendMessage:
1. Store `'[encrypted]'` as content when `encryptedContent` present
2. Pass `encryptedContent` to `messagesService.create()`
3. Skip server-side link preview when `encryptedContent` present

**`backend/src/messages/messages.service.ts`** — accept `encryptedContent` in create() options, pass to `msgRepo.create()`

---

## Phase 4: Frontend — EncryptionService + Signal Stores

**Goal:** Create the core encryption service wrapping `libsignal_protocol_dart`.

### New Flutter dependencies (`frontend/pubspec.yaml`):
```yaml
libsignal_protocol_dart: ^0.7.4
flutter_secure_storage: ^10.0.0
```

### New files:

**`frontend/lib/services/encryption/signal_stores.dart`**

4 persistent store implementations backed by `flutter_secure_storage`:
- `SecureIdentityKeyStore` implements `IdentityKeyStore`
- `SecurePreKeyStore` implements `PreKeyStore`
- `SecureSignedPreKeyStore` implements `SignedPreKeyStore`
- `SecureSessionStore` implements `SessionStore`

Each serializes key material as base64 strings under namespaced keys:
- `e2e_identity_key_pair`, `e2e_registration_id`
- `e2e_pre_key_{id}`, `e2e_signed_pre_key_{id}`
- `e2e_session_{address}_{deviceId}`

**`frontend/lib/services/encryption_service.dart`**

Main facade:
```dart
class EncryptionService {
  static const int PRE_KEY_BATCH_SIZE = 100;
  static const int PRE_KEY_THRESHOLD = 10;

  bool needsKeyUpload = false;

  Future<void> initialize();           // Load or generate keys
  Map<String, dynamic> getKeysForUpload();  // Public portions for server
  Future<bool> hasSession(int userId);
  Future<void> buildSession(int userId, Map<String, dynamic> preKeyBundle);  // X3DH
  Future<String> encrypt(int recipientId, String plaintext);  // → "{type}:{base64}"
  Future<String> decrypt(int senderId, String ciphertext);    // → plaintext
  Future<List<Map<String, dynamic>>?> generateMorePreKeysIfNeeded();
  Future<void> clearAllKeys();         // Logout cleanup
}
```

Key implementation details:
- DeviceId always `1` (single-device model)
- `encrypt()` returns `"{type}:{base64}"` — type 3 = PreKeySignalMessage, type 1 = SignalMessage
- `buildSession()` reconstructs `PreKeyBundle` from server data, uses `SessionBuilder.processPreKeyBundle()`
- First-launch detection: `flutter_secure_storage` flag `e2e_setup_complete`

**`frontend/lib/services/link_preview_service.dart`**

Client-side OG metadata fetch (moved from backend):
```dart
class LinkPreviewService {
  static Future<Map<String, String?>?> fetchPreview(String text);
}
```
- URL regex extraction, private IP blocking (SSRF protection), 5s timeout
- Parse `og:title` + `og:image` from HTML head (max 100KB read)
- Mirrors backend's `backend/src/chat/services/link-preview.service.ts` logic

---

## Phase 5: Frontend — ChatProvider Integration (most invasive)

**Goal:** Wire EncryptionService into the existing send/receive flow.

### Modified files:

**`frontend/lib/services/socket_service.dart`**

Add to `connect()` parameters:
```dart
void Function(dynamic)? onKeyBundleUploaded,
void Function(dynamic)? onOneTimePreKeysUploaded,
void Function(dynamic)? onPreKeyBundleResponse,
void Function(dynamic)? onPreKeysLow,
```

Add emit methods:
```dart
void uploadKeyBundle(Map<String, dynamic> bundle);
void uploadOneTimePreKeys(List<Map<String, dynamic>> keys);
void fetchPreKeyBundle(int userId);
```

**`frontend/lib/models/message_model.dart`**

Add `encryptedContent` field to constructor, `fromJson()`, and `copyWith()`. **CRITICAL: copyWith must include ALL fields per CLAUDE.md rules.**

**`frontend/lib/providers/chat_provider.dart`**

Major changes:

**a) E2E initialization on connect:**
```dart
final EncryptionService _encryptionService = EncryptionService();
bool _e2eInitialized = false;

// In onConnect, after existing fetches:
if (!_e2eInitialized) {
  await _encryptionService.initialize();
  if (_encryptionService.needsKeyUpload) {
    final keys = _encryptionService.getKeysForUpload();
    _socketService.uploadKeyBundle(keys['keyBundle']);
    _socketService.uploadOneTimePreKeys(keys['oneTimePreKeys']);
  }
  _e2eInitialized = true;
}
```

**b) Session establishment with Completer:**
```dart
final Map<int, Completer<Map<String, dynamic>>> _pendingPreKeyFetches = {};

Future<void> _ensureSession(int recipientId) async {
  if (await _encryptionService.hasSession(recipientId)) return;
  final completer = Completer<Map<String, dynamic>>();
  _pendingPreKeyFetches[recipientId] = completer;
  _socketService.fetchPreKeyBundle(recipientId);
  final bundle = await completer.future.timeout(Duration(seconds: 10));
  if (bundle == null) throw Exception('Recipient has no encryption keys');
  await _encryptionService.buildSession(recipientId, bundle);
}
```

**c) Modify sendMessage():**
```
1. LinkPreviewService.fetchPreview(content)  // client-side
2. envelope = jsonEncode({"content": content, "linkPreview": preview?})
3. await _ensureSession(recipientId)
4. ciphertext = await _encryptionService.encrypt(recipientId, envelope)
5. Optimistic message (content = plaintext for local display)
6. socket.emit('sendMessage', {content: '[encrypted]', encryptedContent: ciphertext, ...})
```

**d) Modify _handleIncomingMessage() + onMessageHistory:**
```
1. If msg.encryptedContent != null:
   - decrypted = _encryptionService.decrypt(senderId, encryptedContent)
   - envelope = jsonDecode(decrypted)
   - Build MessageModel with content=envelope['content'], linkPreview from envelope
2. On failure: content = "[Decryption failed]"
```

**e) Pre-key replenishment:**
```dart
onPreKeysLow: (data) async {
  final moreKeys = await _encryptionService.generateMorePreKeysIfNeeded();
  if (moreKeys != null) _socketService.uploadOneTimePreKeys(moreKeys);
}
```

**f) Logout:** call `_encryptionService.clearAllKeys()` before clearing JWT

---

## Phase 6: Frontend — UI (Privacy & Safety)

### New file:

**`frontend/lib/screens/privacy_safety_screen.dart`**

Informational screen:
- Shield/lock icon
- "End-to-end encryption is enabled"
- "Your messages are encrypted using the Signal Protocol. Only you and the person you're chatting with can read them — not even the server."
- "Your encryption keys are stored securely on this device."
- "If you switch devices or reinstall the app, your message history cannot be recovered."
- Identity key fingerprint display (for manual verification with contacts)

### Modified file:

**`frontend/lib/screens/settings_screen.dart`** — Privacy & Safety tile navigates to `PrivacySafetyScreen` instead of showing "Coming soon" snackbar

---

## Phase 7: Migration — Clear Old Messages

### New file:

**`backend/scripts/migrate-enable-e2e.ts`** — one-time script: `msgRepo.clear()` (delete all messages from DB)

### Frontend:

`EncryptionService.initialize()` checks `e2e_setup_complete` flag in secure storage. If absent (first launch with E2E), set `needsKeyUpload = true`.

---

## Phase 8: Tests

### New files:
- **`backend/src/key-bundles/key-bundles.service.spec.ts`** — upsert, fetch (with/without OTPs), count, mark-used, delete tests
- **`backend/src/chat/services/chat-key-exchange.service.spec.ts`** — handler tests with mocked service

### Modified files:
- **`backend/src/chat/services/chat-message.service.spec.ts`** — test encrypted message flow, verify link preview skipped when encryptedContent present
- **`backend/src/chat/utils/dto.validator.spec.ts`** — validation tests for 3 new DTOs

---

## Phase 9: CLAUDE.md Update

Update: Section 2 (schema — new tables), Section 3 (WebSocket events — key exchange), Section 5 (screens — Privacy & Safety), Section 6 (ChatProvider — E2E flow), Section 7 (architecture — new services), Section 8 (features — new section 8.6 E2E Encryption), Section 9 (file map — new files), Section 11 (gotchas — E2E-specific), Section 13 (recent changes), Section 14 (tech debt — media encryption as future work, update test count).

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Session corruption / key loss | Catch decrypt errors → "[Decryption failed]"; add "Reset encryption keys" button in Privacy & Safety |
| First message latency (async pre-key fetch) | Completer with 10s timeout; optionally pre-fetch bundles for all friends on connect |
| flutter_secure_storage on web (less secure) | Acceptable (web is secondary); note in Privacy & Safety |
| Reply-to preview leaks content to server | Show "Encrypted message" as reply preview |
| Link preview: client HTTP to arbitrary URLs | Private IP blocking (mirrors backend SSRF protection) |
| libsignal_protocol_dart v0.7.4 stability | Pin exact version; library used by MixinNetwork in production |

---

## Verification Checklist

1. `docker-compose up` → backend starts, new tables `key_bundles` + `one_time_pre_keys` created
2. `npm test` → all existing + new tests pass
3. `flutter run -d chrome` → login → keys generated + uploaded to server (check DB)
4. Open chat → send message → verify DB: `encryptedContent` has base64 blob, `content` = `"[encrypted]"`
5. Receive message on second account → verify decrypted correctly in UI
6. Kill and restart frontend → verify sessions persist (secure storage), old messages in current session still decrypt
7. Settings → Privacy & Safety → verify screen renders with encryption info
8. Test with two browser tabs (two users) → full E2E roundtrip
9. Test first-message flow (no existing session) → verify pre-key bundle fetch + session establishment
10. Verify link preview works (client-side OG fetch → encrypted in envelope → displayed after decrypt)

---

## Implementation Order

| Phase | Dependencies | New Files | Modified Files | Complexity |
|---|---|---|---|---|
| 1. Backend key storage | None | 4 | 3 | Medium |
| 2. Backend WebSocket events | Phase 1 | 4 | 2 | Medium |
| 3. Backend message changes | None (parallel with 1-2) | 0 | 5 | Medium |
| 4. Frontend EncryptionService | Phases 1-3 deployed | 3 | 1 (pubspec) | Large |
| 5. Frontend ChatProvider | Phase 4 | 0 | 3 | Large |
| 6. Frontend UI | Phase 5 | 1 | 1 | Small |
| 7. Migration | Phases 3, 4 | 1 | 0 | Small |
| 8. Tests | Phases 1-3 | 2 | 2 | Medium |
| 9. CLAUDE.md | All | 0 | 1 | Small |

**Total: ~15 new files, ~18 modified files**
