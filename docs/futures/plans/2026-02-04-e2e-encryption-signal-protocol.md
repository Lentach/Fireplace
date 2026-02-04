# E2E Encryption (Signal Protocol) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement end-to-end encryption using the Signal Protocol (libsignal) so that only sender and recipient can decrypt messages. Server stores encrypted blobs only. Supports multi-device and backward-compatible plaintext during migration.

**Architecture:** Flutter app uses libsignal_client (Rust FFI) for X3DH + Double Ratchet. Keys stored in flutter_secure_storage. Backend uses @noble/ed25519 only for Signed PreKey verification. New entities: devices, pre_keys. Messages gain content_type, sender_device_id, encrypted_payloads. Backward compatible: plaintext and encrypted coexist.

**Tech Stack:** Flutter + libsignal_client + flutter_secure_storage; NestJS + TypeORM + @noble/ed25519; PostgreSQL.

**Reference:** `docs/futures/2026-02-04-e2e-encryption-signal-protocol.md` — single source of truth.

---

## Phase 1: Foundation (Backend + DB)

### Task 1: Add backend dependencies

**Files:**
- Modify: `backend/package.json`

**Step 1:** Add @noble/ed25519 (exact version per architecture doc)

```bash
cd backend && npm install @noble/ed25519@2.0.0 --save
```

**Step 2:** Verify install

```bash
npm ls @noble/ed25519
```

Expected: @noble/ed25519@2.0.0

**Step 3:** Commit

```bash
git add package.json package-lock.json
git commit -m "deps(backend): add @noble/ed25519 for PreKey signature verification"
```

---

### Task 2: Create Device entity

**Files:**
- Create: `backend/src/devices/device.entity.ts`
- Create: `backend/src/devices/devices.module.ts`
- Modify: `backend/src/app.module.ts`

**Step 1:** Create device.entity.ts

```typescript
import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn, ManyToOne, JoinColumn, Index } from 'typeorm';
import { User } from '../users/user.entity';

@Entity('devices')
@Index(['userId', 'isActive'])
@Index(['deviceId'])
export class Device {
  @PrimaryGeneratedColumn()
  id: number;

  @Column({ name: 'user_id' })
  userId: number;

  @ManyToOne(() => User, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'user_id' })
  user: User;

  @Column({ name: 'device_id', type: 'varchar', length: 255, unique: true })
  deviceId: string;

  @Column({ name: 'device_name', type: 'varchar', length: 100, nullable: true })
  deviceName: string | null;

  @Column({ name: 'registration_id', type: 'int' })
  registrationId: number;

  @Column({ name: 'identity_key', type: 'text' })
  identityKey: string;

  @CreateDateColumn({ name: 'created_at' })
  createdAt: Date;

  @Column({ name: 'last_seen', type: 'timestamp', default: () => 'CURRENT_TIMESTAMP' })
  lastSeen: Date;

  @Column({ name: 'is_active', type: 'boolean', default: true })
  isActive: boolean;
}
```

**Step 2:** Create devices.module.ts (export TypeOrmModule.forFeature([Device]))

**Step 3:** Import DevicesModule in app.module.ts

**Step 4:** Commit

```bash
git add backend/src/devices/ backend/src/app.module.ts
git commit -m "feat(backend): add Device entity and module"
```

---

### Task 3: Create PreKey entity

**Files:**
- Create: `backend/src/devices/pre-key.entity.ts`
- Modify: `backend/src/devices/devices.module.ts`

**Step 1:** Create pre-key.entity.ts (deviceId FK, keyId, publicKey, isSigned, signature nullable, usedAt nullable, unique(deviceId, keyId))

**Step 2:** Add PreKey to DevicesModule

**Step 3:** Commit

```bash
git commit -m "feat(backend): add PreKey entity"
```

---

### Task 4: Create database migration for E2E

**Files:**
- Create: `backend/src/migrations/TIMESTAMP-AddE2ESupport.ts` (use actual timestamp)
- Modify: `backend/package.json` or tsconfig if migrations path needed

**Step 1:** Create migration that:
- Creates devices table (columns per schema in architecture doc §5.1)
- Creates pre_keys table
- Adds to messages: content_type (default 'plaintext'), sender_device_id, encrypted_payloads (jsonb)
- Updates existing messages SET content_type = 'plaintext'

**Step 2:** Run migration (if using TypeORM migrations)

```bash
cd backend && npm run typeorm migration:run
```

**Step 3:** Commit

```bash
git add backend/src/migrations/
git commit -m "feat(backend): add E2E migration (devices, pre_keys, messages)"
```

---

### Task 5: Create device registration DTOs

**Files:**
- Create: `backend/src/devices/dto/register-device.dto.ts`

**Step 1:** Create RegisterDeviceDto with: deviceId, deviceName, registrationId, identityKey, signedPreKey { keyId, publicKey, signature }, preKeys [{ keyId, publicKey }]. Use class-validator decorators.

**Step 2:** Commit

```bash
git add backend/src/devices/dto/
git commit -m "feat(backend): add RegisterDeviceDto"
```

---

### Task 6: Implement device registration endpoint with signature verification

**Files:**
- Create: `backend/src/devices/devices.service.ts`
- Create: `backend/src/devices/devices.controller.ts`
- Modify: `backend/src/devices/devices.module.ts`

**Step 1:** Write unit test for DevicesService.registerDevice — verify ed25519.verify called with correct args when valid signature.

**Step 2:** Run test — expect fail (service not implemented).

**Step 3:** Implement DevicesService.registerDevice:
- Verify signature using @noble/ed25519 (ed25519.verify(signature, signedPreKey.publicKey, identityKey))
- Throw BadRequestException if invalid
- Save Device, Signed PreKey, One-Time PreKeys

**Step 4:** Run test — expect pass.

**Step 5:** Add POST /devices/register endpoint (JwtAuthGuard). Wire socket.data.deviceId on connect from query/header.

**Step 6:** Commit

```bash
git add backend/src/devices/
git commit -m "feat(backend): device registration with Signed PreKey verification"
```

---

### Task 7: Implement PreKey retrieval endpoint

**Files:**
- Modify: `backend/src/devices/devices.service.ts`
- Modify: `backend/src/devices/devices.controller.ts`

**Step 1:** Add GET /devices/prekeys?userId=X — returns user's devices with identity key, signed prekey, one unused one-time prekey (or null).

**Step 2:** Add GET /devices/prekey-count — for replenishment logic (count unused one-time prekeys for current device).

**Step 3:** Commit

```bash
git commit -m "feat(backend): PreKey retrieval and count endpoints"
```

---

### Task 8: Wire deviceId into WebSocket connection

**Files:**
- Modify: `backend/src/chat/chat.gateway.ts`
- Modify: `backend/src/auth/strategies/jwt.strategy.ts` (if needed for handshake)

**Step 1:** On socket connection, read deviceId from auth handshake (e.g. auth.token + extra.deviceId or query ?deviceId=). Store in client.data.deviceId.

**Step 2:** If no deviceId and user has E2E enabled, disconnect or require deviceId. For Phase 1, allow optional deviceId (backward compat).

**Step 3:** Commit

```bash
git commit -m "feat(backend): wire deviceId into socket connection"
```

---

## Phase 2: Foundation (Flutter)

### Task 9: Add Flutter dependencies

**Files:**
- Modify: `frontend/pubspec.yaml`
- Modify: `frontend/android/app/build.gradle.kts` (minSdkVersion 23, ndkVersion if needed)
- Modify: `frontend/ios/Podfile` (platform :ios, '13.0')

**Step 1:** Add to pubspec.yaml:
- libsignal_client: ^0.2.0 (or libsignal_protocol_dart if FFI issues)
- flutter_secure_storage: ^9.0.0
- uuid: ^4.3.3

**Step 2:** Run flutter pub get

**Step 3:** Commit

```bash
git add frontend/pubspec.yaml frontend/pubspec.lock frontend/android/ frontend/ios/
git commit -m "deps(frontend): add libsignal_client, flutter_secure_storage, uuid"
```

---

### Task 10: Create CryptoManager service skeleton

**Files:**
- Create: `frontend/lib/services/crypto_manager.dart`
- Create: `frontend/test/services/crypto_manager_test.dart`

**Step 1:** Write failing test: CryptoManager generates identity key pair with private 32 bytes, public 33 bytes, public[0] == 0x05.

**Step 2:** Run test — fail.

**Step 3:** Implement CryptoManager with generateIdentityKeyPair() using libsignal (or mock for now if libsignal API differs). Use flutter_secure_storage for persistence.

**Step 4:** Run test — pass.

**Step 5:** Commit

```bash
git add frontend/lib/services/crypto_manager.dart frontend/test/
git commit -m "feat(frontend): CryptoManager identity key generation"
```

---

### Task 11: Implement Signed PreKey and One-Time PreKey generation

**Files:**
- Modify: `frontend/lib/services/crypto_manager.dart`
- Modify: `frontend/test/services/crypto_manager_test.dart`

**Step 1:** Add tests: generateSignedPreKey returns signature length 64; verifySignature validates correctly.

**Step 2:** Implement generateSignedPreKey, generateOneTimePreKeys, store/load from secure storage.

**Step 3:** Run tests — pass.

**Step 4:** Commit

```bash
git commit -m "feat(frontend): Signed PreKey and One-Time PreKey generation"
```

---

### Task 12: Implement device registration flow (Flutter)

**Files:**
- Modify: `frontend/lib/services/crypto_manager.dart`
- Modify: `frontend/lib/services/api_service.dart`
- Modify: `frontend/lib/providers/auth_provider.dart` or create E2E provider

**Step 1:** Add ApiService.post('/devices/register', body) and get('/devices/prekeys?userId=...').

**Step 2:** In CryptoManager: registerDevice() — check secure storage for device_id; if null, generate UUID and store; generate keys; call POST /devices/register.

**Step 3:** Call registerDevice after login when E2E enabled (or in ChatProvider.connect). For MVP, add flag E2E_ENABLED in settings; if true, run registerDevice on connect.

**Step 4:** Manual test: login → check backend devices table has new row.

**Step 5:** Commit

```bash
git commit -m "feat(frontend): device registration flow"
```

---

## Phase 3: Core E2E Message Flow

### Task 13: Add SendEncryptedMessageDto and extend chat DTOs

**Files:**
- Modify: `backend/src/chat/dto/chat.dto.ts`
- Modify: `backend/src/messages/message.entity.ts`

**Step 1:** Add SendEncryptedMessageDto: recipientId, recipientDeviceId (optional for multi-device), conversationId, encryptedContent { type, body, registrationId }, tempId.

**Step 2:** Ensure Message entity has content_type, sender_device_id, encrypted_payloads (nullable). Make content nullable when content_type = 'signal_encrypted'.

**Step 3:** Commit

```bash
git commit -m "feat(backend): SendEncryptedMessageDto and Message entity E2E fields"
```

---

### Task 14: Modify handleSendMessage for encrypted path

**Files:**
- Modify: `backend/src/chat/services/chat-message.service.ts`
- Modify: `backend/src/chat/chat.gateway.ts`
- Modify: `backend/src/chat/dto/chat.dto.ts`

**Step 1:** In handleSendMessage: if dto has encryptedPayloads (or encryptedContent), use encrypted path — save message with content_type='signal_encrypted', encrypted_payloads; do NOT decrypt. Route to recipient device(s). Emit messageSent with messageId.

**Step 2:** If dto has content (plaintext), use existing plaintext path (backward compat).

**Step 3:** Add validation: either (content) or (encryptedPayloads/encryptedContent) must be present.

**Step 4:** Run existing E2E script (if any) — plaintext still works.

**Step 5:** Commit

```bash
git commit -m "feat(backend): handle encrypted messages in chat gateway"
```

---

### Task 15: Implement X3DH and first-message encryption (Flutter)

**Files:**
- Modify: `frontend/lib/services/crypto_manager.dart`
- Create: `frontend/lib/services/signal_session_service.dart` (or extend CryptoManager)

**Step 1:** Implement fetchPreKeys(userId), processPreKeyBundle(bundle), establishSession(remoteUserId, remoteDeviceId). Use libsignal SessionBuilder, SessionCipher.

**Step 2:** Implement encryptMessage(remoteUserId, remoteDeviceId, plaintext) — pad with PKCS#7 (block 160), encrypt, return { type, body, registrationId }.

**Step 3:** Unit test: Alice encrypts, Bob decrypts (in-memory stores).

**Step 4:** Commit

```bash
git commit -m "feat(frontend): X3DH and first-message encryption"
```

---

### Task 16: Implement sendMessage with encryption in ChatProvider

**Files:**
- Modify: `frontend/lib/providers/chat_provider.dart`
- Modify: `frontend/lib/services/socket_service.dart`
- Modify: `frontend/lib/screens/chat_detail_screen.dart`

**Step 1:** In ChatProvider.sendMessage: if E2E enabled for conversation, fetch recipient prekeys, establish session if needed, encrypt, emit sendMessage with encryptedContent + recipientDeviceId.

**Step 2:** SocketService: add emit overload or handle encrypted payload shape.

**Step 3:** Backend must receive and route. Verify messageSent returns; UI updates.

**Step 4:** Manual test: two users, both E2E enabled; send message; DB has encrypted_payloads, no plaintext.

**Step 5:** Commit

```bash
git commit -m "feat(frontend): sendMessage with E2E encryption"
```

---

### Task 17: Implement decryption on receive (Flutter)

**Files:**
- Modify: `frontend/lib/providers/chat_provider.dart`
- Modify: `frontend/lib/models/message_model.dart`
- Modify: `frontend/lib/widgets/chat_message_bubble.dart`

**Step 1:** In _handleIncomingMessage: if message.contentType == 'signal_encrypted', decrypt using SessionCipher.decrypt(PreKeySignalMessage or SignalMessage). Unpad. Set message.content to decrypted text for display.

**Step 2:** Add contentType to MessageModel. Widget shows lock icon when encrypted.

**Step 3:** Handle PreKeyMessage: consume one-time prekey locally, notify backend to delete (optional for MVP).

**Step 4:** Manual test: Bob receives Alice's encrypted message, sees plaintext, lock icon.

**Step 5:** Commit

```bash
git commit -m "feat(frontend): decrypt received E2E messages"
```

---

### Task 18: Padding and unpadding (PKCS#7)

**Files:**
- Modify: `frontend/lib/services/crypto_manager.dart` or signal_session_service

**Step 1:** Implement padMessage(plaintext, blockSize=160) and unpadMessage(padded) per architecture doc §3.1.

**Step 2:** Unit test: pad then unpad returns original.

**Step 3:** Commit

```bash
git commit -m "feat(frontend): PKCS#7 padding for message length hiding"
```

---

## Phase 4: Multi-Device

### Task 19: Encrypt for all recipient devices

**Files:**
- Modify: `frontend/lib/providers/chat_provider.dart`
- Modify: `backend/src/chat/services/chat-message.service.ts`
- Modify: `backend/src/chat/dto/chat.dto.ts`

**Step 1:** SendEncryptedMessageDto accepts encryptedPayloads: Array<{ deviceId, content }>.

**Step 2:** Flutter: fetch all recipient devices from /devices/prekeys; encrypt separately for each; send encryptedPayloads array.

**Step 3:** Backend: save message with encryptedPayloads; route to each device (online emit, offline queue).

**Step 4:** Manual test: Bob has 2 devices; Alice sends; both receive and decrypt.

**Step 5:** Commit

```bash
git commit -m "feat: multi-device encrypted messaging"
```

---

### Task 20: Offline message queue (backend)

**Files:**
- Create: `backend/src/chat/services/offline-queue.service.ts`
- Modify: `backend/src/chat/chat.gateway.ts`

**Step 1:** When recipient device offline, store message in queue (Redis or in-memory map keyed by deviceId). On device connect, flush queue to that device.

**Step 2:** For MVP, in-memory Map is acceptable; document Redis for production.

**Step 3:** Commit

```bash
git commit -m "feat(backend): offline message queue for E2E"
```

---

### Task 21: Linked Devices UI (Flutter)

**Files:**
- Create: `frontend/lib/screens/linked_devices_screen.dart`
- Modify: `frontend/lib/screens/settings_screen.dart`

**Step 1:** LinkedDevicesScreen: fetch GET /devices/mine, list devices with name, lastSeen. Current device marked. Remove device button for others.

**Step 2:** Add "Linked Devices" tile in SettingsScreen; push LinkedDevicesScreen.

**Step 3:** Implement remove device (DELETE /devices/:deviceId).

**Step 4:** Commit

```bash
git commit -m "feat(frontend): Linked Devices settings screen"
```

---

## Phase 5: Polish & Migration

### Task 22: E2E enablement prompt and migration UX

**Files:**
- Modify: `frontend/lib/main.dart` or auth flow
- Create: `frontend/lib/widgets/dialogs/e2e_enable_dialog.dart`

**Step 1:** On first launch after E2E support, if no identity_private_key in secure storage, show dialog "Enable End-to-End Encryption" — Enable Now / Later.

**Step 2:** If Enable Now: generate keys, register device, show success.

**Step 3:** If Later: continue with plaintext. Next launch, optional reminder (don't nag).

**Step 4:** Commit

```bash
git commit -m "feat(frontend): E2E enablement prompt"
```

---

### Task 23: Lock icon and encryption indicators

**Files:**
- Modify: `frontend/lib/widgets/chat_message_bubble.dart`
- Modify: `frontend/lib/screens/chat_detail_screen.dart`

**Step 1:** Encrypted messages show lock icon (e.g. Icons.lock, small, next to timestamp).

**Step 2:** Optional: "Encryption enabled" banner in chat header when E2E active.

**Step 3:** Plaintext messages: no lock (backward compat).

**Step 4:** Commit

```bash
git commit -m "feat(frontend): lock icon for encrypted messages"
```

---

### Task 24: PreKey rotation and replenishment (background)

**Files:**
- Modify: `frontend/lib/services/crypto_manager.dart`
- Modify: `frontend/lib/providers/chat_provider.dart`

**Step 1:** Signed PreKey rotation: timer every 7 days (or on app start if >7 days since last), generate new signed prekey, upload, keep old 30 days then delete.

**Step 2:** One-Time PreKey replenishment: when prekey-count < 20, generate 100 more, upload.

**Step 3:** Call replenishment check on connect and periodically (e.g. daily).

**Step 4:** Commit

```bash
git commit -m "feat(frontend): PreKey rotation and replenishment"
```

---

### Task 25: Security checklist and logging audit

**Files:**
- Audit: all backend and frontend files for logs containing message.content, privateKey, sessionState.
- Modify: Add redaction in Sentry/error handlers if used.

**Step 1:** Grep for print(.*content|.*key|.*plaintext). Remove or redact.

**Step 2:** Ensure no console.log(plaintext) in backend.

**Step 3:** Document in CLAUDE.md: E2E security checklist.

**Step 4:** Commit

```bash
git commit -m "chore: E2E logging audit and redaction"
```

---

### Task 26: Update CLAUDE.md and docs

**Files:**
- Modify: `CLAUDE.md`
- Modify: `docs/futures/2026-02-04-e2e-encryption-signal-protocol.md` (Next Steps)

**Step 1:** Add §E2E Encryption: architecture summary, new entities, WebSocket event changes, migration phases.

**Step 2:** Update WebSocket Event Map with sendMessage encrypted path, new DTOs.

**Step 3:** Add File Map entries for devices, crypto_manager, signal_session_service.

**Step 4:** Mark "Next Steps" item 2 as done in architecture doc.

**Step 5:** Commit

```bash
git commit -m "docs: CLAUDE.md and E2E architecture updates"
```

---

## Task Order Summary

1. Backend deps → Device entity → PreKey entity → Migration → DTOs → Registration endpoint → PreKey retrieval → deviceId in socket  
2. Flutter deps → CryptoManager skeleton → PreKeys → Device registration flow  
3. SendEncryptedMessageDto → handleSendMessage encrypted path → X3DH/encrypt → sendMessage in ChatProvider → decrypt on receive → Padding  
4. Multi-device encrypt → Offline queue → Linked Devices UI  
5. E2E prompt → Lock icon → PreKey rotation → Logging audit → CLAUDE.md  

---

## Notes

- **libsignal_client:** If Rust FFI fails on Flutter, use `libsignal_protocol_dart` or `signal_protocol_dart` (verify package names on pub.dev).
- **Backend:** NEVER add full libsignal. Only @noble/ed25519 for signature verification.
- **TDD:** Apply where practical (crypto, padding, DTO validation). Integration tests manual until E2E script updated.
- **Deployment:** Render.com setup (render.yaml, Redis) is separate; can be Plan Phase 2.
- **Verification:** Use manual testing checklist from architecture doc §9.3 before marking complete.
