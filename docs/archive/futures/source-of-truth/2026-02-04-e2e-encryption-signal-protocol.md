# End-to-End Encryption Architecture — Signal Protocol

**Document Version:** 1.0
**Created:** 2026-02-04
**Status:** PLANNED (Not Implemented)
**Author:** Architecture Research Session

---

## Executive Summary

This document describes the complete architecture for implementing end-to-end encryption (E2E) in the MVP Chat App using the **Signal Protocol**. This is the definitive source of truth for future implementation.

### Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Encryption Protocol** | Full Signal Protocol (libsignal) | Battle-tested, audited, industry standard |
| **Multi-Device Support** | Simultaneous devices (like WhatsApp) | Better UX, multiple devices logged in at once |
| **History Sync** | Only new messages | Simpler implementation, reduces complexity |
| **Metadata Protection** | Basic (content + attachments) | Server knows "who-to-whom", not "what" |
| **Recovery Mechanism** | No recovery (like Signal) | Maximum security, lost device = lost access |
| **Platform Target** | Flutter mobile (Android/iOS) | Secure storage available (Keychain/KeyStore) |
| **Deployment** | Render.com (managed PostgreSQL + backend) | Free tier, easy setup, scalable |
| **Migration Strategy** | Backward compatible (gradual rollout) | Supports plaintext during transition |

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Key Management & Device Registration](#2-key-management--device-registration)
3. [Message Flow (Encryption & Decryption)](#3-message-flow-encryption--decryption)
4. [Multi-Device Support](#4-multi-device-support)
5. [Database Schema](#5-database-schema)
6. [Libraries & Dependencies](#6-libraries--dependencies)
7. [Migration Strategy](#7-migration-strategy)
8. [Deployment (Render.com)](#8-deployment-rendercom)
9. [Testing & Verification](#9-testing--verification)
10. [Implementation Timeline](#10-implementation-timeline)
11. [Security Considerations](#11-security-considerations)
12. [Future Enhancements](#12-future-enhancements)

---

## 1. Architecture Overview

### 1.1 System Components

```
┌─────────────────────────────────────────────────────────────┐
│                    Flutter Mobile App                        │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ libsignal_client (Rust FFI)                           │  │
│  │ - X3DH Key Exchange                                   │  │
│  │ - Double Ratchet                                      │  │
│  │ - Encrypt/Decrypt Operations                          │  │
│  └───────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ flutter_secure_storage                                │  │
│  │ - Identity Keys (iOS Keychain / Android KeyStore)    │  │
│  │ - Session State                                       │  │
│  │ - Private Keys (NEVER leaves device)                 │  │
│  └───────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ Crypto Manager Service                                │  │
│  │ - Key Generation & Rotation                           │  │
│  │ - Session Management                                  │  │
│  │ - Device Registration                                 │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                            │ WebSocket (Socket.IO)
                            │ REST API
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                    NestJS Backend                            │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ @noble/ed25519 (signature verification only)          │  │
│  │ - Verify Signed PreKey; no full libsignal on server   │  │
│  │ - PreKey Storage & Routing                            │  │
│  └───────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ PreKey Store                                          │  │
│  │ - Public Keys Storage (Identity, Signed, One-Time)   │  │
│  │ - Key Distribution                                    │  │
│  └───────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ Device Registry                                       │  │
│  │ - Multi-Device Management                             │  │
│  │ - Device Sessions                                     │  │
│  └───────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ Encrypted Message Queue                               │  │
│  │ - Offline Device Buffering                            │  │
│  │ - Message Routing                                     │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                    PostgreSQL Database                       │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ users                  (unchanged)                    │  │
│  │ devices                (NEW - device registry)        │  │
│  │ pre_keys               (NEW - public keys)            │  │
│  │ messages               (MODIFIED - encrypted content) │  │
│  │ conversations          (unchanged)                    │  │
│  │ friend_requests        (unchanged)                    │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 Security Properties

**End-to-End Encryption:**
- Only sender and recipient can decrypt messages
- Server cannot read message content
- Database breach does not expose plaintext

**Perfect Forward Secrecy:**
- Compromised session key does not expose past messages
- Each message encrypted with unique ephemeral keys
- Double Ratchet rotates keys on every message

**Deniability:**
- MAC-based authentication (not digital signatures)
- Participants can plausibly deny messages
- No long-term cryptographic proof of authorship

**Future Secrecy:**
- Compromised key does not expose future messages
- Ratchet continues forward even after compromise

---

## 2. Key Management & Device Registration

### 2.1 Signal Protocol Key Types

#### Identity Key Pair (Long-term)
```
Private: 32 bytes Curve25519 scalar
Public:  33 bytes Curve25519 point (compressed)

Purpose:
- Signs other keys (Signed PreKey)
- Verifies device identity
- Never rotated (tied to device lifetime)

Storage:
- Private → Secure Storage (NEVER sent to server)
- Public  → Server (distributed to contacts)
```

#### Signed PreKey Pair (Medium-term)
```
Private: 32 bytes Curve25519 scalar
Public:  33 bytes Curve25519 point + 64 bytes signature

Purpose:
- Used for X3DH when One-Time PreKeys exhausted
- Signed by Identity Key (proves authenticity)
- Rotated every 7 days

Storage:
- Private → Secure Storage
- Public + Signature → Server
```

#### One-Time PreKeys (Short-term)
```
Generated in batches of 100
Each: 32 bytes private, 33 bytes public

Purpose:
- Consumed once per session initiation
- Provides Perfect Forward Secrecy
- Server deletes after use

Storage:
- Private → Secure Storage (indexed by keyId)
- Public  → Server (until used)
```

#### Ratchet Keys (Ephemeral)
```
Generated dynamically during conversation
Rotated with every message exchange

Purpose:
- Double Ratchet algorithm
- Message-level key derivation
- Forward/backward secrecy

Storage:
- Session state in Secure Storage
- NEVER sent in plaintext
```

### 2.2 Device Registration Flow

```dart
// Flutter: First login or new device setup

// Step 0: Check if device already registered
String deviceId = await secureStorage.read(key: 'device_id');
if (deviceId == null) {
  // First time setup - generate new device_id
  deviceId = Uuid().v4();
  await secureStorage.write(key: 'device_id', value: deviceId);
  // CRITICAL: device_id is PERMANENT, tied to identity key
  // App reinstall WITHOUT backup = NEW device_id + NEW keys
}

// Step 1: Generate all keys locally (only if new device)
final identityKeyPair = await generateIdentityKeyPair();
final signedPreKey = await generateSignedPreKey(
  identityKeyPair: identityKeyPair,
  signedPreKeyId: 1,
);
final oneTimePreKeys = await generateOneTimePreKeys(
  start: 1,
  count: 100,
);

// Step 2: Store private keys in Secure Storage
await secureStorage.write(
  key: 'identity_private_key',
  value: base64Encode(identityKeyPair.privateKey),
);
await secureStorage.write(
  key: 'signed_prekey_private_1',
  value: base64Encode(signedPreKey.privateKey),
);
for (var preKey in oneTimePreKeys) {
  await secureStorage.write(
    key: 'one_time_prekey_private_${preKey.id}',
    value: base64Encode(preKey.privateKey),
  );
}

// Step 3: Send public keys to server (use deviceId from Step 0!)
final registrationId = generateRegistrationId(); // random 14-bit int

await api.post('/devices/register', body: {
  'deviceId': deviceId,  // From secure storage (Step 0), NOT a new UUID
  'deviceName': await getDeviceName(), // "iPhone 13", "Galaxy S23"
  'registrationId': registrationId,
  'identityKey': base64Encode(identityKeyPair.publicKey),
  'signedPreKey': {
    'keyId': signedPreKey.id,
    'publicKey': base64Encode(signedPreKey.publicKey),
    'signature': base64Encode(signedPreKey.signature),
  },
  'preKeys': oneTimePreKeys.map((pk) => {
    'keyId': pk.id,
    'publicKey': base64Encode(pk.publicKey),
  }).toList(),
});
```

```typescript
// Backend: /devices/register endpoint

@Post('register')
@UseGuards(JwtAuthGuard)
async registerDevice(
  @Req() req,
  @Body() dto: RegisterDeviceDto,
) {
  const userId = req.user.id;

  // Verify signature on Signed PreKey (using @noble/ed25519)
  import { ed25519 } from '@noble/curves/ed25519';

  const isValid = await ed25519.verify(
    dto.signedPreKey.signature,  // 64 bytes
    dto.signedPreKey.publicKey,  // 32 bytes (message)
    dto.identityKey,             // 32 bytes (public key)
  );
  // Note: Backend doesn't need full libsignal - just signature verification!

  if (!isValid) {
    throw new BadRequestException('Invalid signature on Signed PreKey');
  }

  // Save device
  const device = await this.deviceRepo.save({
    userId,
    deviceId: dto.deviceId,
    deviceName: dto.deviceName,
    registrationId: dto.registrationId,
    identityKey: dto.identityKey,
    createdAt: new Date(),
    lastSeen: new Date(),
  });

  // Save Signed PreKey
  await this.preKeyRepo.save({
    deviceId: dto.deviceId,
    keyId: dto.signedPreKey.keyId,
    publicKey: dto.signedPreKey.publicKey,
    isSigned: true,
    signature: dto.signedPreKey.signature,
  });

  // Save One-Time PreKeys
  await this.preKeyRepo.save(
    dto.preKeys.map(pk => ({
      deviceId: dto.deviceId,
      keyId: pk.keyId,
      publicKey: pk.publicKey,
      isSigned: false,
    })),
  );

  return { success: true, deviceId: device.deviceId };
}
```

### 2.3 PreKey Rotation

**Signed PreKey Rotation (every 7 days):**
```dart
// Flutter: Background task
Future<void> rotateSignedPreKey() async {
  final identityKeyPair = await loadIdentityKeyPair();
  final newSignedPreKeyId = await getNextSignedPreKeyId();

  final newSignedPreKey = await generateSignedPreKey(
    identityKeyPair: identityKeyPair,
    signedPreKeyId: newSignedPreKeyId,
  );

  // Store new private key
  await secureStorage.write(
    key: 'signed_prekey_private_$newSignedPreKeyId',
    value: base64Encode(newSignedPreKey.privateKey),
  );

  // Upload new public key
  await api.post('/devices/rotate-signed-prekey', body: {
    'deviceId': await getDeviceId(),
    'signedPreKey': {
      'keyId': newSignedPreKey.id,
      'publicKey': base64Encode(newSignedPreKey.publicKey),
      'signature': base64Encode(newSignedPreKey.signature),
    },
  });

  // Keep old key for 30 more days (grace period for offline users)
  // 7 days is too short - users on vacation/without internet would lose session
  Future.delayed(Duration(days: 30), () async {
    await secureStorage.delete(
      key: 'signed_prekey_private_${newSignedPreKeyId - 1}',
    );
  });
}
```

**One-Time PreKey Replenishment:**
```dart
// Flutter: When PreKey count drops below threshold
Future<void> replenishPreKeys() async {
  final currentCount = await api.get('/devices/prekey-count');

  if (currentCount < 20) {
    final startId = await getNextPreKeyId();
    final newPreKeys = await generateOneTimePreKeys(
      start: startId,
      count: 100,
    );

    // Store privately
    for (var pk in newPreKeys) {
      await secureStorage.write(
        key: 'one_time_prekey_private_${pk.id}',
        value: base64Encode(pk.privateKey),
      );
    }

    // Upload publicly
    await api.post('/devices/upload-prekeys', body: {
      'deviceId': await getDeviceId(),
      'preKeys': newPreKeys.map((pk) => {
        'keyId': pk.id,
        'publicKey': base64Encode(pk.publicKey),
      }).toList(),
    });
  }
}
```

---

## 3. Message Flow (Encryption & Decryption)

### 3.1 First Message: X3DH Key Agreement

**Alice sends first message to Bob:**

```dart
// STEP 1: Alice fetches Bob's public keys
final bobKeysResponse = await api.get('/devices/prekeys?userId=${bobId}');
// Response contains Bob's devices and their public keys

final bobDevice = bobKeysResponse.devices.first;
final bobBundle = PreKeyBundle(
  registrationId: bobDevice.registrationId,
  deviceId: bobDevice.deviceId,
  identityKey: bobDevice.identityKey,
  signedPreKeyId: bobDevice.signedPreKey.keyId,
  signedPreKeyPublic: bobDevice.signedPreKey.publicKey,
  signedPreKeySignature: bobDevice.signedPreKey.signature,
  preKeyId: bobDevice.oneTimePreKey?.keyId, // may be null
  preKeyPublic: bobDevice.oneTimePreKey?.publicKey,
);

// STEP 2: Process bundle and create session
final aliceStore = await SignalProtocolStore.load();
final sessionBuilder = SessionBuilder(
  store: aliceStore,
  remoteAddress: ProtocolAddress(bobId, bobDevice.deviceId),
);

await sessionBuilder.processPreKeyBundle(bobBundle);
// This performs X3DH internally:
// - 4 ECDH operations
// - Derives shared secret
// - Initializes Double Ratchet

// STEP 3: Encrypt message
final sessionCipher = SessionCipher(
  store: aliceStore,
  remoteAddress: ProtocolAddress(bobId, bobDevice.deviceId),
);

final plaintext = 'Hello Bob! 👋';
final paddedPlaintext = padMessage(plaintext);
final ciphertext = await sessionCipher.encrypt(paddedPlaintext);

// Padding function (PKCS#7):
Uint8List padMessage(String plaintext) {
  final bytes = utf8.encode(plaintext);

  // Pad to size ranges: 0-159→160, 160-319→320, 320-479→480, etc.
  // Hides exact message length
  final blockSize = 160;
  final targetSize = ((bytes.length ~/ blockSize) + 1) * blockSize;
  final paddingLength = targetSize - bytes.length;

  // PKCS#7: fill with padding length byte
  final padded = Uint8List(targetSize);
  padded.setRange(0, bytes.length, bytes);
  padded.fillRange(bytes.length, targetSize, paddingLength);

  return padded;
  // Example: "Hi" (2 bytes) → pad to 160 bytes, last 158 bytes = 0x9E (158)
}

// Unpadding:
String unpadMessage(Uint8List padded) {
  final paddingLength = padded.last; // PKCS#7: last byte = padding length
  final plaintextLength = padded.length - paddingLength;
  return utf8.decode(padded.sublist(0, plaintextLength));
}

// ciphertext is a PreKeySignalMessage containing:
// - type: 3 (PreKeyMessage)
// - registrationId
// - preKeyId (if One-Time PreKey was used)
// - signedPreKeyId
// - baseKey (Alice's ephemeral key)
// - identityKey (Alice's identity key)
// - message (encrypted with derived key)

// STEP 4: Send via WebSocket
socket.emit('sendMessage', {
  recipientId: bobId,
  recipientDeviceId: bobDevice.deviceId,
  encryptedContent: {
    type: ciphertext.getType(), // 3
    body: base64Encode(ciphertext.serialize()),
    registrationId: aliceRegistrationId,
  },
  conversationId: conversationId,
});
```

**Backend routes encrypted message:**

```typescript
// Backend CANNOT decrypt - just routes
@SubscribeMessage('sendMessage')
async handleSendMessage(
  @ConnectedSocket() client: Socket,
  @MessageBody() dto: SendEncryptedMessageDto,
) {
  const sender = client.data.user;

  // Save encrypted blob to database
  const message = await this.messageRepo.save({
    conversation: { id: dto.conversationId },
    sender: { id: sender.id },
    senderDeviceId: client.data.deviceId,
    contentType: 'signal_encrypted',
    encryptedPayloads: [{
      deviceId: dto.recipientDeviceId,
      content: dto.encryptedContent,
      timestamp: new Date(),
    }],
  });

  // Route to recipient device
  const recipientSocket = this.getDeviceSocket(dto.recipientDeviceId);
  if (recipientSocket) {
    recipientSocket.emit('newMessage', {
      messageId: message.id,
      senderId: sender.id,
      senderDeviceId: client.data.deviceId,
      conversationId: dto.conversationId,
      encryptedContent: dto.encryptedContent,
      timestamp: message.createdAt,
    });
  } else {
    // Recipient offline - queue message
    await this.offlineQueue.add({
      deviceId: dto.recipientDeviceId,
      message: message,
    });
  }

  // Acknowledge to sender
  client.emit('messageSent', {
    tempId: dto.tempId,
    messageId: message.id,
    timestamp: message.createdAt,
  });
}
```

**Bob receives and decrypts:**

```dart
// STEP 5: Bob's device receives encrypted message
socket.on('newMessage', (data) async {
  final encryptedContent = data['encryptedContent'];

  // Determine message type
  if (encryptedContent['type'] == 3) {
    // PreKeySignalMessage - first message from sender
    final preKeyMessage = PreKeySignalMessage.deserialize(
      base64Decode(encryptedContent['body']),
    );

    // Extract sender info
    final senderAddress = ProtocolAddress(
      data['senderId'],
      data['senderDeviceId'],
    );

    // Load Bob's store
    final bobStore = await SignalProtocolStore.load();

    // Create session from PreKey message
    final sessionCipher = SessionCipher(
      store: bobStore,
      remoteAddress: senderAddress,
    );

    // Decrypt (also establishes session for future messages)
    final paddedPlaintext = await sessionCipher.decrypt(preKeyMessage);
    final plaintext = unpadMessage(paddedPlaintext);

    // Delete used One-Time PreKey locally
    final usedPreKeyId = preKeyMessage.getPreKeyId();
    if (usedPreKeyId != null) {
      await secureStorage.delete(
        key: 'one_time_prekey_private_$usedPreKeyId',
      );
      // Notify server to delete public key
      api.delete('/devices/prekeys/$usedPreKeyId');
    }

    // Display message
    print('Decrypted: $plaintext'); // "Hello Bob! 👋"

  } else {
    // Regular SignalMessage - session already established
    final message = SignalMessage.deserialize(
      base64Decode(encryptedContent['body']),
    );

    final sessionCipher = SessionCipher(...);
    final plaintext = await sessionCipher.decrypt(message);

    print('Decrypted: ${unpadMessage(plaintext)}');
  }
});
```

### 3.2 Subsequent Messages: Double Ratchet

**After first message, session is established. Double Ratchet updates keys:**

```
Alice → Bob: Message 1 (PreKeyMessage, establishes session)
              Session state:
                Root Key: RK_0
                Sending Chain Key: CK_send_0
                Receiving Chain Key: (not yet)

Bob → Alice: Message 2 (SignalMessage, response)
             Bob performs DH ratchet:
               - Generates new ephemeral key pair
               - Derives new Root Key: RK_1
               - Derives new Sending Chain: CK_send_Bob_0

             Alice receives, performs DH ratchet:
               - Derives new Root Key: RK_1 (same as Bob)
               - Derives new Receiving Chain: CK_recv_Alice_0

Alice → Bob: Message 3 (SignalMessage)
             Alice performs DH ratchet:
               - Generates new ephemeral key
               - Derives RK_2, CK_send_Alice_1

             ... and so on, keys ratchet forward with each turn
```

**Key Derivation (simplified):**
```
Message Key = HMAC-SHA256(Chain Key, 0x01)
Next Chain Key = HMAC-SHA256(Chain Key, 0x02)

Each message:
1. Derive message key from current chain key
2. Encrypt with AES-256-CBC using message key
3. Compute MAC with HMAC-SHA256
4. Ratchet chain key forward
5. Delete old message key (forward secrecy)
```

---

## 4. Multi-Device Support

### 4.1 Sender Keys Approach

**Problem:** Bob has 2 devices (phone + tablet). When Alice sends a message, both must receive it.

**Solution:** Alice encrypts message separately for each device.

```dart
// Alice sends to Bob (who has 2 devices)

// Fetch all Bob's devices
final bobDevicesResponse = await api.get('/devices/prekeys?userId=${bobId}');
// Returns: [bobPhone, bobTablet]

// Encrypt for each device
List<EncryptedPayload> payloads = [];

for (var device in bobDevicesResponse.devices) {
  final sessionCipher = SessionCipher(
    store: aliceStore,
    remoteAddress: ProtocolAddress(bobId, device.deviceId),
  );

  final ciphertext = await sessionCipher.encrypt(plaintext);

  payloads.add(EncryptedPayload(
    deviceId: device.deviceId,
    content: {
      'type': ciphertext.getType(),
      'body': base64Encode(ciphertext.serialize()),
    },
  ));
}

// Send all payloads
socket.emit('sendMessage', {
  recipientId: bobId,
  encryptedPayloads: payloads.map((p) => p.toJson()).toList(),
  conversationId: conversationId,
});
```

**Backend routes to each device:**

```typescript
@SubscribeMessage('sendMessage')
async handleSendMessage(
  @ConnectedSocket() client: Socket,
  @MessageBody() dto: SendMultiDeviceMessageDto,
) {
  // Save message once with multiple payloads
  const message = await this.messageRepo.save({
    conversation: { id: dto.conversationId },
    sender: client.data.user,
    senderDeviceId: client.data.deviceId,
    contentType: 'signal_encrypted',
    encryptedPayloads: dto.encryptedPayloads, // Array of {deviceId, content}
  });

  // Route to each device
  for (const payload of dto.encryptedPayloads) {
    const targetSocket = this.getDeviceSocket(payload.deviceId);

    if (targetSocket) {
      // Device online - send immediately
      targetSocket.emit('newMessage', {
        messageId: message.id,
        senderId: client.data.user.id,
        senderDeviceId: client.data.deviceId,
        conversationId: dto.conversationId,
        encryptedContent: payload.content, // Only this device's payload
        timestamp: message.createdAt,
      });
    } else {
      // Device offline - queue for later delivery
      await this.offlineQueue.add(payload.deviceId, {
        messageId: message.id,
        payload: payload.content,
      });
    }
  }

  // Acknowledge to sender
  client.emit('messageSent', {
    tempId: dto.tempId,
    messageId: message.id,
  });
}
```

### 4.2 Device Synchronization

**New Device Login:**
1. User logs in on new device (e.g., new tablet)
2. Device generates keys and registers with server
3. Server now knows user has 3 devices: [phone, old_tablet, new_tablet]
4. Future messages encrypted for all 3 devices

**History:** Only new messages (per requirements)
- New device starts with empty message history
- Receives only messages sent AFTER registration
- Old messages remain on original devices only

**Device Removal:**
```dart
// User removes old device
await api.delete('/devices/${oldDeviceId}');

// Server:
// - Deletes device from registry
// - Deletes associated PreKeys
// - Future messages NOT encrypted for removed device
```

**Device List UI:**
```dart
// Settings screen: "Linked Devices"
class LinkedDevicesScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Device>>(
      future: api.get('/devices/mine'),
      builder: (context, snapshot) {
        final devices = snapshot.data ?? [];
        return ListView.builder(
          itemCount: devices.length,
          itemBuilder: (context, index) {
            final device = devices[index];
            return ListTile(
              leading: Icon(device.isCurrentDevice
                ? Icons.phone_android
                : Icons.tablet),
              title: Text(device.name), // "iPhone 13"
              subtitle: Text('Last seen: ${device.lastSeen}'),
              trailing: device.isCurrentDevice
                ? Text('This device')
                : IconButton(
                    icon: Icon(Icons.delete),
                    onPressed: () => removeDevice(device.id),
                  ),
            );
          },
        );
      },
    );
  }
}
```

---

## 5. Database Schema

### 5.1 New Tables

```sql
-- Device registry
CREATE TABLE devices (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id VARCHAR(255) UNIQUE NOT NULL,  -- CRITICAL: Persistent UUID tied to identity_key
                                            -- App reinstall = NEW device_id + NEW keys
                                            -- Stored in Secure Storage alongside private keys
  device_name VARCHAR(100),  -- "iPhone 13 Pro", "Galaxy Tab S8"
  registration_id INT NOT NULL,
  identity_key TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  last_seen TIMESTAMP DEFAULT NOW(),
  is_active BOOLEAN DEFAULT TRUE,

  INDEX idx_user_devices (user_id, is_active),
  INDEX idx_device_lookup (device_id)
);

-- PreKeys storage
CREATE TABLE pre_keys (
  id SERIAL PRIMARY KEY,
  device_id VARCHAR(255) NOT NULL REFERENCES devices(device_id) ON DELETE CASCADE,
  key_id INT NOT NULL,
  public_key TEXT NOT NULL,
  is_signed BOOLEAN DEFAULT FALSE,
  signature TEXT,  -- Only for Signed PreKeys
  created_at TIMESTAMP DEFAULT NOW(),
  used_at TIMESTAMP,  -- When One-Time PreKey was consumed

  UNIQUE(device_id, key_id),
  INDEX idx_device_prekeys (device_id),
  INDEX idx_unused_prekeys (device_id, is_signed, used_at)
    WHERE used_at IS NULL AND is_signed = FALSE
);

-- REMOVED: signal_sessions table
-- Contradiction with "no recovery" policy
-- Sessions stored ONLY in local Secure Storage
-- If device lost → sessions lost (by design, maximum security)
--
-- FUTURE (Phase 3): Optional encrypted session backup
-- Would require user to set recovery passphrase
-- NOT part of MVP
```

### 5.2 Modified Tables

```sql
-- Messages: Add encryption support
ALTER TABLE messages
  ADD COLUMN content_type VARCHAR(50) DEFAULT 'plaintext',
  ADD COLUMN sender_device_id VARCHAR(255) REFERENCES devices(device_id),
  ADD COLUMN encrypted_payloads JSONB;

-- Update constraint: either content OR encrypted_payloads must be present
ALTER TABLE messages
  ADD CONSTRAINT chk_message_content
  CHECK (
    (content_type = 'plaintext' AND content IS NOT NULL) OR
    (content_type = 'signal_encrypted' AND encrypted_payloads IS NOT NULL)
  );

-- Migrate existing messages
UPDATE messages
SET content_type = 'plaintext'
WHERE content_type IS NULL;

-- encrypted_payloads structure:
-- [
--   {
--     "deviceId": "uuid-of-device",
--     "content": {
--       "type": 3,
--       "body": "base64_encrypted_blob",
--       "registrationId": 12345
--     },
--     "timestamp": "2026-02-04T10:30:00Z"
--   }
-- ]
```

### 5.3 Indexes for Performance

```sql
-- Fast PreKey lookup
CREATE INDEX idx_prekeys_available
  ON pre_keys(device_id, key_id)
  WHERE used_at IS NULL AND is_signed = FALSE;

-- Fast device lookup
CREATE INDEX idx_active_devices
  ON devices(user_id, last_seen DESC)
  WHERE is_active = TRUE;

-- Fast message retrieval
CREATE INDEX idx_messages_encrypted
  ON messages(conversation_id, created_at DESC)
  WHERE content_type = 'signal_encrypted';

-- JSONB index for device payload lookup
CREATE INDEX idx_encrypted_payloads_device
  ON messages USING gin(encrypted_payloads jsonb_path_ops);
```

---

## 6. Libraries & Dependencies

### 6.1 Flutter (Mobile App)

```yaml
# pubspec.yaml
dependencies:
  # Signal Protocol
  libsignal_client: ^0.2.0  # Rust FFI wrapper
  # Alternative if FFI issues: libsignal_protocol_dart: ^0.7.0

  # Secure Storage
  flutter_secure_storage: ^9.0.0

  # Cryptography utilities
  cryptography: ^2.7.0
  pointycastle: ^3.7.4  # For additional crypto operations

  # Existing dependencies
  socket_io_client: ^2.0.3+1
  provider: ^6.1.1
  shared_preferences: ^2.2.2
  http: ^1.2.0

  # Utilities
  uuid: ^4.3.3
  convert: ^3.1.1

dev_dependencies:
  flutter_test:
    sdk: flutter
  mockito: ^5.4.4
  integration_test:
    sdk: flutter
```

**Platform-specific requirements:**

```yaml
# android/app/build.gradle
android {
  compileSdkVersion 34

  defaultConfig {
    minSdkVersion 23  # Required for libsignal FFI
  }

  ndkVersion "25.2.9519653"  # Required for Rust FFI
}

# ios/Podfile
platform :ios, '13.0'  # Required for libsignal
```

### 6.2 Backend (NestJS)

```json
{
  "dependencies": {
    // Cryptography - MINIMAL dependencies for security
    "@noble/ed25519": "^2.0.0",  // Ed25519 signature verification (Signed PreKey)
    "@noble/curves": "^1.3.0",   // Curve25519 operations (if needed)
    // Alternative: "tweetnacl": "^1.0.3" (also good, slightly larger)

    // NOTE: We do NOT use full @signalapp/libsignal-client on backend
    // Backend only verifies signatures, doesn't decrypt messages
    // Smaller attack surface, fewer dependencies

    "@nestjs/core": "^10.3.0",
    "@nestjs/common": "^10.3.0",
    "@nestjs/typeorm": "^10.0.1",
    "@nestjs/websockets": "^10.3.0",
    "@nestjs/platform-socket.io": "^10.3.0",

    "typeorm": "^0.3.19",
    "pg": "^8.11.3",

    "socket.io": "^4.6.1",
    "class-validator": "^0.14.1",
    "class-transformer": "^0.5.1",

    "@nestjs/bull": "^10.1.0",
    "bull": "^4.12.0",
    "ioredis": "^5.3.2"
  },
  "devDependencies": {
    "@nestjs/testing": "^10.3.0",
    "jest": "^29.7.0",
    "supertest": "^6.3.4"
  }
}
```

### 6.3 Infrastructure

**Redis (Message Queue for Offline Devices):**
- Option 1: Upstash Redis (free tier: 10k commands/day)
- Option 2: Railway Redis ($1/month)
- Option 3: In-memory queue (MVP only, not persistent)

**PostgreSQL:**
- Render.com Managed PostgreSQL (free 90 days, then $7/month)
- Requires PostgreSQL 14+ for JSONB features

---

## 7. Migration Strategy

### 7.1 Backward Compatibility

**Phase 1: Deploy E2E Support (Week 1)**
- Backend supports both plaintext AND encrypted messages
- New `content_type` field distinguishes message types
- Existing clients continue to work (send/receive plaintext)

```typescript
// Backend handles both
async handleSendMessage(client: Socket, dto: SendMessageDto) {
  // Check if sender has E2E enabled
  const senderDevice = await this.deviceRepo.findOne({
    where: { userId: client.data.user.id },
  });

  if (senderDevice && dto.encryptedPayloads) {
    // NEW: E2E encrypted path
    return this.handleEncryptedMessage(client, dto);
  } else {
    // OLD: Plaintext path (legacy support)
    return this.handlePlaintextMessage(client, dto);
  }
}
```

**Phase 2: Client App Update (Week 2-4)**
- Release new Flutter app with libsignal
- On first launch: prompt user to enable E2E
- User can choose "Enable Now" or "Later"

```dart
// First launch of updated app
Future<void> checkE2EStatus() async {
  final hasKeys = await secureStorage.read(key: 'identity_private_key');

  if (hasKeys == null) {
    // User hasn't enabled E2E yet
    final shouldEnable = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Enable End-to-End Encryption'),
        content: Text(
          'Secure your messages with end-to-end encryption. '
          'Only you and your contacts can read your messages.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Later'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Enable Now'),
          ),
        ],
      ),
    );

    if (shouldEnable == true) {
      await initializeE2E();
    }
  }
}

Future<void> initializeE2E() async {
  showLoadingDialog('Generating encryption keys...');

  // Generate keys
  final identityKeyPair = await generateIdentityKeyPair();
  final signedPreKey = await generateSignedPreKey(identityKeyPair);
  final oneTimePreKeys = await generateOneTimePreKeys(count: 100);

  // Store locally
  await storeKeys(identityKeyPair, signedPreKey, oneTimePreKeys);

  // Register with server
  await registerDevice();

  hideLoadingDialog();
  showSuccessDialog('Encryption enabled! Your messages are now secure.');
}
```

**Phase 3: Gradual Rollout (Week 5-8)**
- Monitor E2E adoption rate
- Users with E2E enabled can message each other securely
- Mixed conversations (E2E ↔ plaintext) still work

**Phase 4: Enforce E2E (Month 6+)**
- After majority adoption (>80%), enforce E2E
- Block plaintext messages
- Show in-app notification: "Update required"

```typescript
// Backend enforces E2E
if (!dto.encryptedPayloads) {
  throw new BadRequestException(
    'End-to-end encryption is now required. Please update your app to continue.',
  );
}
```

### 7.2 Data Migration

**Old Messages (Plaintext):**

Option A: **Keep plaintext** (Recommended for MVP)
```dart
// Frontend displays both types
Widget buildMessageBubble(Message message) {
  if (message.contentType == 'plaintext') {
    return MessageBubble(
      text: message.content,
      isEncrypted: false,
    );
  } else {
    // Decrypt
    final decrypted = await decryptMessage(message.encryptedPayloads);
    return MessageBubble(
      text: decrypted,
      isEncrypted: true,
      lockIcon: Icons.lock,
    );
  }
}
```

Option B: **Local encryption** (More secure, but complex)
- When enabling E2E, download plaintext history
- Encrypt locally with new keys
- Store in local database (SQLite)
- Delete from server
- Problem: Other party can't decrypt (they don't have your keys)

**Recommendation:** Option A - keep old messages as plaintext, new messages encrypted. Clear UX with lock icon 🔒 for encrypted messages.

---

## 8. Deployment (Render.com)

### 8.1 Infrastructure Setup

```yaml
# render.yaml
services:
  # Backend Service
  - type: web
    name: mvp-chat-backend
    runtime: docker
    dockerfilePath: ./backend/Dockerfile
    dockerContext: ./backend
    region: frankfurt  # Choose closest to your users
    plan: free  # Free tier to start, upgrade to Starter ($7/mo) later

    healthCheckPath: /health

    envVars:
      - key: NODE_ENV
        value: production

      - key: PORT
        value: 3000

      - key: DATABASE_URL
        fromDatabase:
          name: mvp-chat-db
          property: connectionString

      - key: JWT_SECRET
        generateValue: true

      - key: CLOUDINARY_CLOUD_NAME
        sync: false  # Manually add in Render UI

      - key: CLOUDINARY_API_KEY
        sync: false

      - key: CLOUDINARY_API_SECRET
        sync: false

      - key: REDIS_URL
        fromService:
          type: redis
          name: mvp-chat-redis
          property: connectionString

    autoDeploy: true  # Auto-deploy on git push

databases:
  - name: mvp-chat-db
    databaseName: chatdb
    user: postgres
    region: frankfurt
    plan: free  # 90 days free, then $7/month

redis:
  - name: mvp-chat-redis
    plan: free  # If Render offers it, or use Upstash
    region: frankfurt
    maxmemoryPolicy: allkeys-lru
```

### 8.2 Dockerfile Optimizations

```dockerfile
# backend/Dockerfile
FROM node:20-alpine AS builder

WORKDIR /app

# Install dependencies first (cached layer)
COPY package*.json ./
RUN npm ci --only=production

# Copy source and build
COPY . .
RUN npm run build

# Production image
FROM node:20-alpine

WORKDIR /app

# Copy built artifacts
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/package*.json ./

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s \
  CMD node -e "require('http').get('http://localhost:3000/health', (r) => {process.exit(r.statusCode === 200 ? 0 : 1)})"

EXPOSE 3000

CMD ["node", "dist/main"]
```

### 8.3 Deployment Commands

```bash
# 1. Connect GitHub repo to Render
git remote add origin https://github.com/yourusername/mvp-chat-app.git
git push -u origin master

# 2. Create Render account and link repo
# Go to https://dashboard.render.com/select-repo

# 3. Render auto-detects render.yaml and sets up services

# 4. Add secrets via Render UI:
# Settings → Environment → Add Environment Variable:
#   CLOUDINARY_CLOUD_NAME = your_cloud_name
#   CLOUDINARY_API_KEY = your_api_key
#   CLOUDINARY_API_SECRET = your_api_secret

# 5. Trigger deploy
git commit -m "Deploy E2E encryption"
git push origin master

# Render automatically:
# - Builds Docker images
# - Runs migrations
# - Deploys to production
# - Provides URLs: https://mvp-chat-backend.onrender.com
```

### 8.4 Database Migrations

```typescript
// backend/src/migrations/1707048000000-AddE2ESupport.ts
import { MigrationInterface, QueryRunner, Table, TableColumn } from 'typeorm';

export class AddE2ESupport1707048000000 implements MigrationInterface {
  public async up(queryRunner: QueryRunner): Promise<void> {
    // Create devices table
    await queryRunner.createTable(new Table({
      name: 'devices',
      columns: [
        { name: 'id', type: 'serial', isPrimary: true },
        { name: 'user_id', type: 'int', isNullable: false },
        { name: 'device_id', type: 'varchar', length: '255', isUnique: true },
        { name: 'device_name', type: 'varchar', length: '100', isNullable: true },
        { name: 'registration_id', type: 'int', isNullable: false },
        { name: 'identity_key', type: 'text', isNullable: false },
        { name: 'created_at', type: 'timestamp', default: 'NOW()' },
        { name: 'last_seen', type: 'timestamp', default: 'NOW()' },
        { name: 'is_active', type: 'boolean', default: true },
      ],
      foreignKeys: [
        {
          columnNames: ['user_id'],
          referencedTableName: 'users',
          referencedColumnNames: ['id'],
          onDelete: 'CASCADE',
        },
      ],
      indices: [
        { columnNames: ['user_id', 'is_active'] },
        { columnNames: ['device_id'] },
      ],
    }), true);

    // Create pre_keys table
    await queryRunner.createTable(new Table({
      name: 'pre_keys',
      columns: [
        { name: 'id', type: 'serial', isPrimary: true },
        { name: 'device_id', type: 'varchar', length: '255', isNullable: false },
        { name: 'key_id', type: 'int', isNullable: false },
        { name: 'public_key', type: 'text', isNullable: false },
        { name: 'is_signed', type: 'boolean', default: false },
        { name: 'signature', type: 'text', isNullable: true },
        { name: 'created_at', type: 'timestamp', default: 'NOW()' },
        { name: 'used_at', type: 'timestamp', isNullable: true },
      ],
      foreignKeys: [
        {
          columnNames: ['device_id'],
          referencedTableName: 'devices',
          referencedColumnNames: ['device_id'],
          onDelete: 'CASCADE',
        },
      ],
      indices: [
        { columnNames: ['device_id', 'key_id'], isUnique: true },
        { columnNames: ['device_id', 'is_signed', 'used_at'], where: 'used_at IS NULL AND is_signed = FALSE' },
      ],
    }), true);

    // Modify messages table
    await queryRunner.addColumns('messages', [
      new TableColumn({
        name: 'content_type',
        type: 'varchar',
        length: '50',
        default: "'plaintext'",
      }),
      new TableColumn({
        name: 'sender_device_id',
        type: 'varchar',
        length: '255',
        isNullable: true,
      }),
      new TableColumn({
        name: 'encrypted_payloads',
        type: 'jsonb',
        isNullable: true,
      }),
    ]);

    // Update existing messages
    await queryRunner.query(`
      UPDATE messages
      SET content_type = 'plaintext'
      WHERE content_type IS NULL
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.dropTable('pre_keys');
    await queryRunner.dropTable('devices');
    await queryRunner.dropColumns('messages', [
      'content_type',
      'sender_device_id',
      'encrypted_payloads',
    ]);
  }
}
```

---

## 9. Testing & Verification

### 9.1 Unit Tests

```dart
// Flutter: test/crypto_manager_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mvp_chat_app/services/crypto_manager.dart';

void main() {
  group('CryptoManager', () {
    late CryptoManager cryptoManager;

    setUp(() {
      cryptoManager = CryptoManager();
    });

    test('should generate valid identity key pair', () async {
      final keyPair = await cryptoManager.generateIdentityKeyPair();

      expect(keyPair.privateKey.length, 32);
      expect(keyPair.publicKey.length, 33);
      expect(keyPair.publicKey[0], 0x05); // Curve25519 public key prefix
    });

    test('should generate and sign PreKeys', () async {
      final identityKeyPair = await cryptoManager.generateIdentityKeyPair();
      final signedPreKey = await cryptoManager.generateSignedPreKey(
        identityKeyPair: identityKeyPair,
        signedPreKeyId: 1,
      );

      expect(signedPreKey.signature.length, 64);

      // Verify signature
      final isValid = await cryptoManager.verifySignature(
        identityKeyPair.publicKey,
        signedPreKey.publicKey,
        signedPreKey.signature,
      );
      expect(isValid, true);
    });

    test('should encrypt and decrypt message', () async {
      // Alice setup
      final aliceStore = await SignalProtocolStore.createInMemory();
      final aliceAddress = ProtocolAddress('alice', 1);

      // Bob setup
      final bobStore = await SignalProtocolStore.createInMemory();
      final bobAddress = ProtocolAddress('bob', 1);
      final bobIdentity = await bobStore.getIdentityKeyPair();
      final bobPreKey = await bobStore.getSignedPreKey(1);

      // Alice initiates session
      final bobBundle = PreKeyBundle(
        registrationId: 1,
        deviceId: 1,
        identityKey: bobIdentity.publicKey,
        signedPreKeyId: 1,
        signedPreKeyPublic: bobPreKey.publicKey,
        signedPreKeySignature: bobPreKey.signature,
      );

      final aliceSessionBuilder = SessionBuilder(
        store: aliceStore,
        remoteAddress: bobAddress,
      );
      await aliceSessionBuilder.processPreKeyBundle(bobBundle);

      // Alice encrypts
      final aliceSessionCipher = SessionCipher(
        store: aliceStore,
        remoteAddress: bobAddress,
      );
      final plaintext = 'Hello Bob! 👋';
      final ciphertext = await aliceSessionCipher.encrypt(utf8.encode(plaintext));

      // Bob decrypts
      final bobSessionCipher = SessionCipher(
        store: bobStore,
        remoteAddress: aliceAddress,
      );
      final decryptedBytes = await bobSessionCipher.decrypt(ciphertext);
      final decrypted = utf8.decode(decryptedBytes);

      expect(decrypted, plaintext);
    });

    test('should ratchet forward on multiple messages', () async {
      // Setup session...

      // Send 10 messages
      for (int i = 0; i < 10; i++) {
        final ciphertext = await aliceCipher.encrypt(
          utf8.encode('Message $i'),
        );
        final plaintext = await bobCipher.decrypt(ciphertext);
        expect(utf8.decode(plaintext), 'Message $i');
      }

      // Verify keys rotated (check session state)
      final aliceSession = await aliceStore.loadSession(bobAddress);
      expect(aliceSession.sendingChainKey.index, 10);
    });
  });
}
```

```typescript
// Backend: test/signal-protocol.service.spec.ts
import { Test } from '@nestjs/testing';
import { SignalProtocolService } from './signal-protocol.service';
import { getRepositoryToken } from '@nestjs/typeorm';
import { Device } from './device.entity';
import { PreKey } from './pre-key.entity';

describe('SignalProtocolService', () => {
  let service: SignalProtocolService;
  let deviceRepo: any;
  let preKeyRepo: any;

  beforeEach(async () => {
    const module = await Test.createTestingModule({
      providers: [
        SignalProtocolService,
        {
          provide: getRepositoryToken(Device),
          useValue: mockDeviceRepo,
        },
        {
          provide: getRepositoryToken(PreKey),
          useValue: mockPreKeyRepo,
        },
      ],
    }).compile();

    service = module.get(SignalProtocolService);
    deviceRepo = module.get(getRepositoryToken(Device));
    preKeyRepo = module.get(getRepositoryToken(PreKey));
  });

  it('should store PreKeys', async () => {
    const deviceId = 'test-device-123';
    const preKeys = [
      { keyId: 1, publicKey: 'pk1' },
      { keyId: 2, publicKey: 'pk2' },
    ];

    await service.storePreKeys(deviceId, preKeys);

    expect(preKeyRepo.save).toHaveBeenCalledWith(
      expect.arrayContaining([
        expect.objectContaining({ deviceId, keyId: 1 }),
        expect.objectContaining({ deviceId, keyId: 2 }),
      ]),
    );
  });

  it('should retrieve and mark One-Time PreKey as used', async () => {
    const deviceId = 'test-device-123';
    preKeyRepo.findOne.mockResolvedValue({
      id: 1,
      deviceId,
      keyId: 42,
      publicKey: 'pk42',
      isSigned: false,
      usedAt: null,
    });

    const preKey = await service.consumeOneTimePreKey(deviceId);

    expect(preKey.keyId).toBe(42);
    expect(preKeyRepo.update).toHaveBeenCalledWith(
      1,
      { usedAt: expect.any(Date) },
    );
  });

  it('should rotate Signed PreKey', async () => {
    const deviceId = 'test-device-123';
    const newSignedPreKey = {
      keyId: 2,
      publicKey: 'new_pk',
      signature: 'new_sig',
    };

    preKeyRepo.findOne.mockResolvedValue({
      id: 1,
      keyId: 1,
      publicKey: 'old_pk',
    });

    await service.rotateSignedPreKey(deviceId, newSignedPreKey);

    expect(preKeyRepo.save).toHaveBeenCalledWith(
      expect.objectContaining({
        deviceId,
        keyId: 2,
        isSigned: true,
      }),
    );
  });
});
```

### 9.2 Integration Tests

```typescript
// test/e2e/encrypted-messaging.e2e-spec.ts
import { io, Socket } from 'socket.io-client';
import { SignalProtocolStore } from '@privacyresearch/libsignal-client';

describe('Encrypted Messaging E2E', () => {
  let aliceSocket: Socket;
  let bobSocket: Socket;
  let aliceStore: SignalProtocolStore;
  let bobStore: SignalProtocolStore;

  beforeAll(async () => {
    // Setup Alice
    aliceSocket = io('http://localhost:3000', {
      auth: { token: aliceJWT },
    });
    aliceStore = await SignalProtocolStore.createInMemory();
    await registerDevice(aliceSocket, aliceStore);

    // Setup Bob
    bobSocket = io('http://localhost:3000', {
      auth: { token: bobJWT },
    });
    bobStore = await SignalProtocolStore.createInMemory();
    await registerDevice(bobSocket, bobStore);
  });

  afterAll(() => {
    aliceSocket.disconnect();
    bobSocket.disconnect();
  });

  it('should send encrypted message from Alice to Bob', async () => {
    // Alice fetches Bob's PreKeys
    const bobKeys = await fetchPreKeys(aliceSocket, bobUserId);
    expect(bobKeys.devices).toHaveLength(1);

    // Alice establishes session
    const sessionBuilder = new SessionBuilder(
      aliceStore,
      new ProtocolAddress(bobUserId, bobKeys.devices[0].deviceId),
    );
    await sessionBuilder.processPreKeyBundle(bobKeys.devices[0]);

    // Alice sends encrypted message
    const plaintext = 'Hello Bob!';
    const sessionCipher = new SessionCipher(
      aliceStore,
      new ProtocolAddress(bobUserId, bobKeys.devices[0].deviceId),
    );
    const ciphertext = await sessionCipher.encrypt(
      Buffer.from(plaintext, 'utf8'),
    );

    // Send via WebSocket
    aliceSocket.emit('sendMessage', {
      recipientId: bobUserId,
      recipientDeviceId: bobKeys.devices[0].deviceId,
      encryptedContent: {
        type: ciphertext.type(),
        body: ciphertext.serialize().toString('base64'),
      },
    });

    // Bob receives
    const received = await new Promise((resolve) => {
      bobSocket.once('newMessage', resolve);
    });

    // Bob decrypts
    const bobSessionCipher = new SessionCipher(
      bobStore,
      new ProtocolAddress(aliceUserId, received.senderDeviceId),
    );
    const decrypted = await bobSessionCipher.decrypt(
      received.encryptedContent,
    );

    expect(decrypted.toString('utf8')).toBe(plaintext);
  });

  it('should verify server never sees plaintext', async () => {
    // Send message
    const plaintext = 'Secret message';
    await sendEncryptedMessage(aliceSocket, bobUserId, plaintext);

    // Query database directly
    const messageInDB = await queryDatabase(
      'SELECT content, encrypted_payloads FROM messages ORDER BY id DESC LIMIT 1',
    );

    // Verify plaintext NOT in database
    expect(messageInDB.content).toBeNull();
    expect(messageInDB.encrypted_payloads).toBeDefined();

    // Verify encrypted blob doesn't contain plaintext substring
    const encryptedBlob = JSON.stringify(messageInDB.encrypted_payloads);
    expect(encryptedBlob).not.toContain(plaintext);
  });

  it('should support multi-device (send to 2 devices)', async () => {
    // Bob registers second device
    const bobTablet = io('http://localhost:3000', {
      auth: { token: bobJWT },
    });
    const bobTabletStore = await SignalProtocolStore.createInMemory();
    await registerDevice(bobTablet, bobTabletStore);

    // Alice sends to Bob
    const plaintext = 'Multi-device test';
    await sendEncryptedMessage(aliceSocket, bobUserId, plaintext);

    // Both Bob's devices receive
    const phoneReceived = new Promise((resolve) =>
      bobSocket.once('newMessage', resolve),
    );
    const tabletReceived = new Promise((resolve) =>
      bobTablet.once('newMessage', resolve),
    );

    const [phoneMsg, tabletMsg] = await Promise.all([
      phoneReceived,
      tabletReceived,
    ]);

    // Both decrypt successfully
    const phoneDecrypted = await decryptMessage(bobStore, phoneMsg);
    const tabletDecrypted = await decryptMessage(bobTabletStore, tabletMsg);

    expect(phoneDecrypted).toBe(plaintext);
    expect(tabletDecrypted).toBe(plaintext);
  });
});
```

### 9.3 Manual Testing Checklist

**Basic Flow:**
- [ ] New user registration generates keys automatically
- [ ] Keys stored in Secure Storage (check with device tools)
- [ ] First message to contact uses PreKeyMessage (type 3)
- [ ] Subsequent messages use SignalMessage (type 2)
- [ ] Recipient successfully decrypts message
- [ ] Message displays with lock icon 🔒

**Multi-Device:**
- [ ] Log in on 2 devices simultaneously
- [ ] Send message from device A
- [ ] Both devices B1 and B2 receive message
- [ ] Both can decrypt independently
- [ ] Logout from B1, only B2 receives new messages

**Edge Cases:**
- [ ] Send message when recipient offline → queued
- [ ] Recipient comes online → receives queued messages
- [ ] One-Time PreKeys exhausted → fallback to Signed PreKey
- [ ] Signed PreKey rotation (after 7 days)
- [ ] Out-of-order messages (network delay)

**Negative / Invalid Input (no crash, no plaintext in logs):**
- [ ] Invalid or truncated ciphertext → decryption fails gracefully
- [ ] Tampered payload (bit flip in blob) → rejected, no plaintext leaked
- [ ] Wrong message type / malformed base64 → safe error handling

**Security Verification:**
- [ ] Server logs: no plaintext appears
- [ ] Database inspection: only encrypted blobs
- [ ] Network capture (Wireshark): payload encrypted
- [ ] Compromised old key: cannot decrypt new messages
- [ ] Man-in-the-middle: signature verification fails

**Performance:**
- [ ] Encryption adds <100ms latency
- [ ] Key generation <2 seconds
- [ ] App size increase <5MB
- [ ] Battery impact minimal (<5% increase)

---

## 10. Implementation Timeline

### Week 1-2: Foundation
**Goal:** Setup libraries, database, key generation

- [ ] Add libsignal_client to Flutter (FFI setup)
- [ ] Add @signalapp/libsignal-client to backend
- [ ] Create database migrations (devices, pre_keys, modify messages)
- [ ] Implement CryptoManager service (Flutter)
  - [ ] generateIdentityKeyPair()
  - [ ] generateSignedPreKey()
  - [ ] generateOneTimePreKeys()
  - [ ] Store in flutter_secure_storage
- [ ] Implement SignalProtocolService (backend)
  - [ ] Device registration endpoint
  - [ ] PreKey storage/retrieval
- [ ] Unit tests for crypto operations

### Week 3-4: Core E2E
**Goal:** Message encryption/decryption working

- [ ] Implement X3DH key exchange (Flutter)
  - [ ] Fetch PreKeys from server
  - [ ] Process PreKeyBundle
  - [ ] Establish session
- [ ] Implement encryption (Flutter)
  - [ ] SessionCipher.encrypt()
  - [ ] Padding
  - [ ] Serialization
- [ ] Implement decryption (Flutter)
  - [ ] SessionCipher.decrypt()
  - [ ] Handle PreKeyMessage vs SignalMessage
  - [ ] Unpadding
- [ ] Modify WebSocket handlers (backend)
  - [ ] Accept encrypted payloads
  - [ ] Route without decrypting
  - [ ] Backward compatibility (plaintext)
- [ ] Double Ratchet verification
- [ ] Integration tests (Alice → Bob flow)

### Week 5: Multi-Device
**Goal:** Multiple devices can receive messages

- [ ] Implement multi-device registration
  - [ ] Track user's devices
  - [ ] Fetch all device PreKeys
- [ ] Encrypt for each device (Flutter)
  - [ ] Loop through recipient devices
  - [ ] Separate payloads per device
- [ ] Backend routing to multiple devices
  - [ ] Send to all online devices
  - [ ] Queue for offline devices
- [ ] Device management UI
  - [ ] List linked devices
  - [ ] Remove device
- [ ] Test with 2-3 devices

### Week 6: Polish & Deploy
**Goal:** Production-ready

- [ ] UI indicators
  - [ ] Lock icon for encrypted messages
  - [ ] "Encryption enabled" banner
  - [ ] Device fingerprint verification screen
- [ ] Migration handling
  - [ ] Backward compatibility tested
  - [ ] Plaintext → Encrypted transition
- [ ] Performance optimization
  - [ ] Cache sessions
  - [ ] Batch PreKey uploads
  - [ ] IndexedDB for web (if supporting)
- [ ] Deploy to Render.com
  - [ ] Setup render.yaml
  - [ ] Database migrations
  - [ ] Environment variables
- [ ] E2E testing in production
- [ ] Monitoring & logging setup

**Total: 6 weeks** (single full-time developer)

**Milestones:**
- End of Week 2: Keys generated, stored, registered ✅
- End of Week 4: First encrypted message sent & decrypted ✅
- End of Week 5: Multi-device working ✅
- End of Week 6: Deployed to production ✅

---

## 11. Security Considerations

### 11.1 Threat Model

**Protected Against:**
- ✅ **Passive Server Compromise:** Server cannot read messages (E2E)
- ✅ **Database Breach:** Only encrypted blobs exposed
- ✅ **Network Eavesdropping:** TLS + E2E double layer
- ✅ **Compromised Past Keys:** Forward secrecy via ratchet
- ✅ **Man-in-the-Middle:** Identity key verification
- ✅ **Replay Attacks:** Message counters in ratchet state

**NOT Protected Against:**
- ❌ **Compromised Client:** If device hacked, keys can be stolen
- ❌ **Malicious App Update:** If we push backdoored version
- ❌ **OS-Level Keylogger:** Can capture messages before encryption
- ❌ **Quantum Computers:** Curve25519 vulnerable to Shor's algorithm (future risk)
- ❌ **Metadata Analysis:** Server knows who talks to whom, when
- ❌ **Supply Chain Attacks:** Compromised dependencies (npm/pub packages)
- ❌ **Memory Dumps:** Keys in RAM can be extracted (OS/hardware attack)
- ❌ **Logging Leaks:** Accidental plaintext in logs/crash reports

### 11.2 Security Best Practices

**Key Storage:**
```dart
// GOOD: Use Secure Storage
await FlutterSecureStorage().write(
  key: 'identity_private_key',
  value: privateKey,
  // iOS: Keychain with kSecAttrAccessibleWhenUnlockedThisDeviceOnly
  // Android: EncryptedSharedPreferences with AES-256
);

// BAD: SharedPreferences (plaintext)
await SharedPreferences.getInstance().setString('key', privateKey); // ❌
```

**Random Number Generation:**
```dart
// GOOD: Cryptographically secure
import 'dart:math' show Random;
import 'package:cryptography/cryptography.dart';

final secureRandom = SecureRandom.instance;
final randomBytes = secureRandom.nextBytes(32);

// BAD: Math.random()
final badRandom = Random().nextInt(1000000); // ❌ NOT cryptographically secure
```

**Padding:**
```dart
// GOOD: Pad to fixed block size (hides message length)
String padMessage(String plaintext, int blockSize) {
  final length = plaintext.length;
  final paddedLength = ((length ~/ blockSize) + 1) * blockSize;
  final padding = List.filled(paddedLength - length, '\x00').join();
  return plaintext + padding;
}

// BAD: No padding (leaks message length)
final encrypted = encrypt(plaintext); // ❌ Length visible
```

**Signature Verification:**
```typescript
// GOOD: Always verify signatures
import { ed25519 } from '@noble/curves/ed25519';

const isValid = await ed25519.verify(
  signature,      // 64 bytes
  signedPreKey,   // message
  identityKey,    // public key
);
if (!isValid) {
  throw new Error('Invalid signature - possible MITM');
}

// BAD: Trust without verification
await storePreKey(signedPreKey); // ❌ No signature check
```

**Memory Security (Zeroing Sensitive Buffers):**
```dart
// GOOD: Zero sensitive data after use
Future<String> decryptMessage(Uint8List encryptedData) async {
  Uint8List plaintextBytes;
  try {
    plaintextBytes = await sessionCipher.decrypt(encryptedData);
    final plaintext = utf8.decode(plaintextBytes);
    return plaintext;
  } finally {
    // CRITICAL: Zero the buffer before GC collects it
    if (plaintextBytes != null) {
      plaintextBytes.fillRange(0, plaintextBytes.length, 0);
    }
  }
}

// GOOD: Zero private keys when deleting
Future<void> deleteOldPreKey(int keyId) async {
  // Read key
  final keyString = await secureStorage.read(key: 'prekey_$keyId');
  if (keyString != null) {
    final keyBytes = base64Decode(keyString);

    // Zero the bytes before deleting
    keyBytes.fillRange(0, keyBytes.length, 0);

    // Delete from storage
    await secureStorage.delete(key: 'prekey_$keyId');
  }
}

// BAD: Leave sensitive data in memory
final plaintext = await decrypt(ciphertext);
// ❌ plaintextBytes still in heap, can be dumped
return plaintext;
```

**Logging Safety:**
```dart
// GOOD: Never log sensitive data
logger.info('Message sent', {
  'messageId': message.id,
  'recipientId': recipient.id,
  // NO plaintext, NO keys, NO session data
});

// BAD: Logging plaintext
logger.debug('Sending message: $plaintext'); // ❌ NEVER!
logger.error('Decryption failed for key: $privateKey'); // ❌ NEVER!

// GOOD: Filter in error tracking (Sentry)
Sentry.init((options) {
  options.beforeSend = (event, hint) {
    // Remove sensitive fields
    event.extra?.remove('privateKey');
    event.extra?.remove('sessionState');
    event.message = event.message?.replaceAll(RegExp(r'\b[A-Za-z0-9+/]{40,}\b'), '[REDACTED]');
    return event;
  };
});
```

### 11.3 Supply Chain Security

**Dependency Management:**

```json
// package.json - Pin EXACT versions (no ^ or ~)
{
  "dependencies": {
    "@noble/ed25519": "2.0.0",  // ✅ Exact version
    "libsignal_client": "^0.2.0"  // ❌ Can auto-update to 0.3.0!
  }
}

// Use package-lock.json (npm) or pubspec.lock (Flutter)
// Commit these files to git
```

**CVE Monitoring:**

```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: "npm"
    directory: "/backend"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 10

  - package-ecosystem: "pub"
    directory: "/frontend"
    schedule:
      interval: "weekly"
```

**Verify Package Integrity:**

```bash
# Before deploying to production
npm audit  # Check for known vulnerabilities
npm audit fix  # Auto-fix if safe

# Verify checksums (optional but recommended)
npm install --ignore-scripts  # Prevent postinstall scripts
```

**Critical Dependencies to Monitor:**
- `libsignal_client` - Core crypto library
- `@noble/ed25519` - Signature verification
- `flutter_secure_storage` - Key storage
- `socket.io` - Transport layer

**Red Flags:**
- ❌ Dependency suddenly requires new permissions
- ❌ Maintainer changed (check npm/pub)
- ❌ Major version bump without changelog
- ❌ Unusual file sizes or binary blobs in package

### 11.4 Audit & Compliance

**Self-Audit Checklist:**

**Cryptography:**
- [ ] Private keys never logged (not even in debug mode)
- [ ] Private keys never sent over network
- [ ] All crypto operations use libsignal (no custom crypto)
- [ ] Secure random number generation (crypto-grade RNG)
- [ ] Signature verification on all received keys
- [ ] Session state securely stored (Secure Storage only)
- [ ] Old keys deleted after rotation
- [ ] TLS 1.3 enforced for transport

**Memory Security:**
- [ ] Sensitive buffers (keys, plaintext) zeroed after use
- [ ] No keys/plaintext in heap dumps
- [ ] Secure Storage uses hardware-backed encryption when available
- [ ] No sensitive data in app screenshots (iOS/Android)

**Supply Chain:**
- [ ] Dependencies pinned to exact versions (package-lock.json)
- [ ] Dependabot enabled for CVE monitoring
- [ ] Regularly update libsignal (security patches)
- [ ] Verify package integrity (checksums, signatures)
- [ ] No third-party analytics with access to messages

**Logging & Monitoring:**
- [ ] No plaintext in application logs
- [ ] No keys in error logs
- [ ] Sentry/Crashlytics: filter sensitive fields
- [ ] Backend logs: only encrypted payloads (base64 blobs)
- [ ] No message content in push notifications (only "New message")

**Code Security:**
- [ ] No `console.log(message.content)` in production
- [ ] No `print(privateKey)` anywhere
- [ ] Code obfuscation for Flutter release builds
- [ ] Certificate pinning for API calls (optional but recommended)

**Future Professional Audit:**
When app reaches production scale, consider:
- Cure53 (German security firm) - €10-20k
- Trail of Bits (US) - $30-50k
- NCC Group - $20-40k

---

## 12. Future Enhancements

### 12.1 Phase 2 Features

**Encrypted Attachments:**
```dart
// Encrypt file before upload
Future<String> uploadEncryptedFile(File file) async {
  // 1. Generate random 32-byte key
  final fileKey = generateRandomBytes(32);

  // 2. Encrypt file with AES-256-GCM
  final encryptedBytes = await encryptAES(
    plaintext: await file.readAsBytes(),
    key: fileKey,
  );

  // 3. Upload encrypted file to Cloudinary
  final url = await cloudinary.upload(encryptedBytes);

  // 4. Include fileKey in message payload (encrypted with Signal Protocol)
  final messagePayload = {
    'type': 'attachment',
    'url': url,
    'fileKey': base64Encode(fileKey),
    'mimeType': 'image/jpeg',
    'size': file.lengthSync(),
  };

  // 5. Encrypt payload with Signal Protocol
  final encrypted = await sessionCipher.encrypt(
    jsonEncode(messagePayload),
  );

  return encrypted;
}

// Recipient decrypts
Future<File> downloadAndDecrypt(String url, String encryptedFileKey) async {
  final fileKey = base64Decode(encryptedFileKey);
  final encryptedFile = await http.get(Uri.parse(url));
  final decryptedBytes = await decryptAES(encryptedFile.bodyBytes, fileKey);
  return File('path/to/save').writeAsBytes(decryptedBytes);
}
```

**Safety Numbers (Fingerprint Verification):**
```dart
// Display safety number for user verification
String generateSafetyNumber(String aliceIdentityKey, String bobIdentityKey) {
  final combined = sortLexicographically([aliceIdentityKey, bobIdentityKey]);
  final hash = sha256.convert(utf8.encode(combined.join()));
  final number = hash.bytes.take(30).join();

  // Format: 12345 67890 12345 67890 12345 67890
  return number.replaceAllMapped(
    RegExp(r'.{5}'),
    (m) => '${m.group(0)} ',
  ).trim();
}

// UI: QR code or 30-digit number
// Users can verify out-of-band (phone call, in person)
```

**Disappearing Messages:**
```dart
// Message with TTL
final message = {
  'content': 'This will self-destruct',
  'expiresAt': DateTime.now().add(Duration(hours: 24)).toIso8601String(),
};

// Recipient sets timer
Timer(Duration(hours: 24), () {
  deleteMessage(messageId);
});
```

### 12.2 Phase 3: Advanced Features

**Group Chats with Sender Keys:**
- Implement Sender Keys protocol (efficient group encryption)
- Each participant encrypts once, all decrypt
- Admin management (add/remove members)

**Desktop App (Flutter Desktop):**
- Linked device via QR code scan
- Sync message history from mobile
- Push notifications

**Encrypted Voice/Video Calls:**
- WebRTC with SRTP (Secure RTP)
- DTLS for key exchange
- Use same Signal Protocol for call setup

**Sealed Sender (Metadata Protection):**
- Hide sender identity from server
- Server only knows recipient
- More complex routing

---

## 13. Resources & Documentation

### 13.1 Signal Protocol Documentation
- [Signal Protocol Specification](https://signal.org/docs/)
- [libsignal Repository](https://github.com/signalapp/libsignal)
- [X3DH Key Agreement](https://signal.org/docs/specifications/x3dh/)
- [Double Ratchet Algorithm](https://signal.org/docs/specifications/doubleratchet/)

### 13.2 Implementation Guides
- [Building a Secure Messenger](https://www.youtube.com/watch?v=DXv1boalsDI) - Moxie Marlinspike talk
- [Signal Protocol Deep Dive](https://medium.com/@justinomora/demystifying-the-signal-protocol-for-end-to-end-encryption-e2ee-ad6a567e6cb4)
- [Flutter Secure Storage Best Practices](https://pub.dev/packages/flutter_secure_storage)

### 13.3 Security Research
- [Breaking Signal Protocol's Anonymity](https://eprint.iacr.org/2019/1320.pdf)
- [Formal Verification of Signal](https://eprint.iacr.org/2016/1013.pdf)
- [Post-Quantum Signal](https://signal.org/blog/pqxdh/)

---

## 14. Glossary

| Term | Definition |
|------|------------|
| **E2E Encryption** | End-to-End Encryption - only sender and recipient can decrypt |
| **Perfect Forward Secrecy** | Compromised key doesn't expose past messages |
| **Double Ratchet** | Key rotation algorithm used by Signal |
| **X3DH** | Extended Triple Diffie-Hellman - key agreement protocol |
| **PreKey** | Public key uploaded to server for asynchronous key exchange |
| **One-Time PreKey** | PreKey used once, then deleted (provides PFS) |
| **Signed PreKey** | PreKey signed by Identity Key (proves authenticity) |
| **Identity Key** | Long-term key tied to device identity |
| **Session** | Established encrypted channel between two devices |
| **Ratchet State** | Current key state in Double Ratchet algorithm |
| **Safety Number** | Fingerprint for verifying identity keys out-of-band |
| **Sealed Sender** | Hides sender identity from server (metadata protection) |

---

## Document Change Log

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-02-04 | Initial architecture design |
| 1.1 | 2026-02-04 | Security review improvements:<br/>- Backend: Replaced libsignal with @noble/ed25519 (minimal deps)<br/>- Padding: Specified PKCS#7 format, variable-length ranges<br/>- Rotation: Grace period 7d → 30d (offline users)<br/>- Database: Removed signal_sessions table (contradicted "no recovery")<br/>- device_id: Added persistence notes (tied to identity key)<br/>- Threat model: Added supply chain, memory zeroing, logging<br/>- Security: Expanded checklist with memory/logging/supply chain |

---

**Next Steps:**
1. ~~Review and approve this architecture~~ ✓ Approved
2. ~~Create implementation plan (use superpowers:writing-plans)~~ ✓ See `docs/plans/2026-02-04-e2e-encryption-signal-protocol.md`
3. Set up git worktree (use superpowers:using-git-worktrees)
4. Begin Phase 1 implementation

**Questions? Concerns?**
Discuss with team before beginning implementation.

---

*This document is the single source of truth for E2E encryption implementation.*
