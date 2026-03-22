# Media Self-Hosting + AES-256-GCM Encryption Design

**Date:** 2026-03-22
**Status:** Approved
**Scope:** Replace Cloudinary with self-hosted VM storage + implement client-side AES-256-GCM media encryption

---

## Problem Statement

Current state:
- All media (images, voice, GIFs, files, avatars) uploaded **unencrypted** to Cloudinary
- `MediaCryptoService` referenced in CLAUDE.md does **not exist** — was never implemented
- Signal E2E encrypts only the Cloudinary URL in the envelope, not the file itself
- Anyone with a Cloudinary URL can access original media without authentication
- Third-party dependency (Cloudinary) holds all user media

Target state:
- All media stored on the production Linux VM (GCP e2-medium, Warszawa)
- Message media encrypted AES-256-GCM client-side before upload — backend sees only opaque ciphertext
- Avatars stored on VM, JWT-protected, not AES-encrypted (profile pictures are not private message content)
- Nginx serves files directly via X-Accel-Redirect — Node.js not involved in file I/O
- Cloudinary dependency fully removed

---

## Architecture

```
Flutter Client
  SEND:  file → compute(encrypt) → POST /media/upload (JWT) → {mediaUrl}
         key+IV → Signal E2E envelope → sendMessage
  RECV:  GET /media/:id (JWT header) → Nginx auth check → compute(decrypt) → display

Nginx
  POST /media/upload  → proxy → NestJS :3000
  GET  /media/:id     → proxy → NestJS (JWT verify) → X-Accel-Redirect
  location /internal/media/ { internal; alias /app/media/; }

NestJS :3000
  MediaController: POST /media/upload, GET /media/:filename
  LocalStorageService (replaces CloudinaryService)
  MediaCleanupService: on-demand + cron daily at 03:00

Docker Volume: media_storage → /app/media
  ├── avatars/   (unencrypted, JWT-protected)
  └── msgs/      (AES-256-GCM encrypted blobs)
```

---

## Backend Design

### LocalStorageService (`backend/src/media/local-storage.service.ts`)

Replaces `CloudinaryService` with identical method signatures so call sites require minimal changes.

| Method | Behaviour |
|---|---|
| `uploadAvatar(userId, buffer, mimeType)` | Saves to `/app/media/avatars/{uuid}.{ext}`, returns `{secureUrl, publicId}` |
| `uploadImage(userId, buffer, mimeType)` | Saves to `/app/media/msgs/{uuid}.bin`, returns `{secureUrl, publicId}` |
| `uploadVoiceMessage(userId, buffer, mimeType, expiresIn?)` | Saves to `/app/media/msgs/{uuid}.bin`, returns `{secureUrl, publicId, duration}` |
| `uploadRawFile(userId, buffer, mimeType, filename?)` | Saves to `/app/media/msgs/{uuid}.bin`, returns `{secureUrl, publicId}` |
| `deleteAvatar(publicId)` | Deletes file from disk |
| `deleteFile(url)` | Deletes media file from disk by URL |

- Avatar files use original extension (`.jpg`, `.png`) for browser display
- Message media files use `.bin` extension — opaque encrypted blobs
- `publicId` = relative path within `/app/media/` (used for deletion)
- Base URL: `https://fireplace.ignorelist.com`

### MediaController (`backend/src/media/media.controller.ts`)

```
POST /media/upload
  Auth: JWT required
  Body: multipart — field `file` (binary blob) + `mediaType` ('image'|'voice'|'gif'|'file'|'avatar')
        + optional `expiresAt` (ISO string), `duration` (seconds)
  Response: { mediaUrl } or { mediaUrl, fileName } for type=file
  Rate limits: inherit existing limits from MessagesController

GET /media/:filename
  Auth: JWT required
  Response: sets X-Accel-Redirect: /internal/media/msgs/:filename header, 200 empty body
  Error: 404 if file not found, 401 if no JWT

GET /media/avatars/:filename
  Auth: JWT required
  Response: sets X-Accel-Redirect: /internal/media/avatars/:filename header
```

### MediaCleanupService (`backend/src/media/media-cleanup.service.ts`)

**On-demand triggers (called from existing services):**

| Event | Files deleted |
|---|---|
| `deleteMessage` (for_everyone) | `deleteFile(message.mediaUrl)` |
| `clearChatHistory` | all `mediaUrl` values from cleared messages |
| `deleteConversationOnly` | all `mediaUrl` values from deleted messages |
| `unfriend` | all `mediaUrl` values from the removed conversation |
| `deleteAccount` | all files where `userId` matches (scan DB for user's messages) |

**Cron safety net (`@Cron('0 3 * * *')`):**
1. Scan `/app/media/msgs/` for all filenames
2. Query DB: `SELECT mediaUrl FROM messages WHERE expiresAt < NOW() OR mediaUrl IS NOT NULL`
3. Delete files where `expiresAt < now()`
4. Delete files not referenced by any message in DB (orphaned)

### Module changes

- `cloudinary.module.ts` → replaced by `media.module.ts`
- `app.module.ts`: swap `CloudinaryModule` → `MediaModule`, add `ScheduleModule.forRoot()`
- `users.controller.ts`: `CloudinaryService` → `LocalStorageService`
- `messages.controller.ts`: MIME validation stays for unencrypted path; encrypted uploads accepted as `application/octet-stream`

---

## Frontend Design

### MediaCryptoService (`frontend/lib/services/media_crypto_service.dart`)

```dart
class EncryptedMedia {
  final Uint8List ciphertext;
  final String keyBase64;  // 256-bit AES key, base64-encoded
  final String ivBase64;   // 96-bit GCM IV, base64-encoded
}

class MediaCryptoService {
  static const int _maxBytes = 20 * 1024 * 1024; // 20 MB hard cap

  /// Encrypts bytes in a background isolate (compute).
  /// Generates a fresh random 256-bit key and 96-bit IV per call.
  Future<EncryptedMedia> encrypt(Uint8List bytes);

  /// Decrypts bytes in a background isolate (compute).
  Future<Uint8List> decrypt(Uint8List ciphertext, String keyB64, String ivB64);
}
```

- Uses `dart:isolate` via `compute()` — UI thread never blocked
- Uses `pointycastle` or `webcrypto` package for AES-256-GCM
- Throws if `bytes.length > 20MB`
- Keys are in-memory only — never logged, never persisted server-side

### Progress UX

| Phase | UX |
|---|---|
| Encrypting (<500KB) | No indicator — fast enough |
| Encrypting (≥500KB) | Indeterminate spinner overlay on message bubble |
| Uploading | Determinate progress bar (%) via `StreamedRequest` |
| Decrypting | Indeterminate spinner while compute() runs |

### Send Flow

```
sendImage() / sendVoice() / sendGif() / sendFile()
  1. Create optimistic message (SENDING) → notifyListeners()
  2. compute(encrypt, rawBytes) → EncryptedMedia{ciphertext, key, iv}
  3. _pendingSendContent[tempId] = {content, messageType, mediaKey: key, mediaIv: iv}
  4. POST /media/upload (encrypted blob, JWT) with StreamedRequest → progress bar
  5. response: {mediaUrl}
  6. _pendingSendContent[tempId]['mediaUrl'] = mediaUrl
  7. _encryptAndSend(content, messageType, mediaUrl, mediaKey=key, mediaIv=iv)
     └─ Signal envelope: {content, messageType, mediaUrl, mediaKey, mediaIv}
```

**Critical:** `_pendingSendContent[tempId]` must be written with `mediaKey`+`mediaIv` BEFORE `_encryptAndSend()` await, so if `messageHistory` arrives during session-setup, `_addMessageToState` finds the keys already present.

### Receive Flow

```
onNewMessage() → Signal decrypt → E2eEnvelope.parse()
  if envelope.mediaKey != null:
    1. GET /media/:filename (with JWT Authorization header)
    2. compute(decrypt, blob, mediaKey, mediaIv) → Uint8List
    3. render decrypted bytes (MemoryImage / audio player / file)
  else (legacy message, no mediaKey):
    load mediaUrl directly (backward compat — Cloudinary URLs still work)
```

### Avatar Fetch

Avatars are not AES-encrypted. After migration:
- `Image.network(avatarUrl, headers: {'Authorization': 'Bearer $token'})`
- `AvatarCircle` widget updated to pass JWT header on all avatar image requests

### E2eEnvelope Changes (`encryption_service.dart`)

```dart
class E2eEnvelope {
  final String content;
  final MessageType? messageType;
  final String? mediaUrl;
  final int? mediaDuration;
  final String? mediaKey;    // NEW — null for legacy messages
  final String? mediaIv;     // NEW — null for legacy messages
  final LinkPreview? linkPreview;
}
```

- `build()`: includes `mediaKey`/`mediaIv` when non-null
- `parse()`: reads `mediaKey`/`mediaIv` if present, null otherwise
- Legacy messages (no `mediaKey` in JSON): parsed with `mediaKey = null` → backward compat

---

## Nginx Configuration

```nginx
# Added to existing server block in nginx.conf / docker-compose nginx config

# Internal location — only reachable via X-Accel-Redirect, not directly
location /internal/media/ {
    internal;
    alias /app/media/;
}

# Proxy to NestJS for auth + redirect
location /media/ {
    proxy_pass http://backend:3000;
    proxy_set_header Authorization $http_authorization;
    proxy_set_header Host $host;
}
```

---

## Docker Configuration

```yaml
volumes:
  media_storage:

services:
  backend:
    volumes:
      - media_storage:/app/media
    environment:
      - MEDIA_BASE_URL=https://fireplace.ignorelist.com

  nginx:
    volumes:
      - media_storage:/app/media:ro  # read-only for Nginx file serving
```

---

## Backward Compatibility

| Scenario | Behaviour |
|---|---|
| Old message with Cloudinary URL, no `mediaKey` | Loaded directly from Cloudinary URL — works until Cloudinary account closed |
| Old avatar on Cloudinary | Displayed from Cloudinary URL until user updates avatar |
| New message with `mediaKey` | Fetched from VM with JWT, decrypted client-side |
| New avatar | Fetched from VM with JWT header |

Cloudinary can be decommissioned when: no active user has a Cloudinary avatar AND all Cloudinary-hosted messages have expired or been deleted.

---

## Security Properties

| Property | Status after implementation |
|---|---|
| Media encrypted at rest | ✅ AES-256-GCM, key never leaves client unencrypted |
| Media access requires auth | ✅ JWT on every request |
| Server sees plaintext media | ✅ Never — server stores opaque ciphertext only |
| Key stored server-side | ✅ Never — key in Signal E2E envelope only |
| Avatar encrypted at rest | ❌ Not encrypted (profile pictures are not private message content) |
| Avatar access requires auth | ✅ JWT required |

---

## Out of Scope

- Multi-device key sharing
- Thumbnail generation
- CDN / geographic distribution
- Resumable uploads
- Encryption of avatars (deliberate — not private message content)
- Migration script for existing Cloudinary media (users keep old messages as-is)
