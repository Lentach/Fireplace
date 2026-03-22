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
- Avatars stored on VM, **publicly accessible by URL** (no JWT required — profile pictures are not private message content; same model as Signal/WhatsApp)
- Nginx serves files directly via X-Accel-Redirect — Node.js not involved in file I/O for downloads
- Cloudinary dependency fully removed

---

## Architecture

```
Flutter Client
  SEND:  rawBytes → compute(encrypt) → {ciphertext, key, iv}
         POST /media/upload (JWT, binary blob) → {mediaUrl}
         key+IV → Signal E2E envelope → sendMessage (server never sees key)

  RECV:  GET /media/msgs/:id (public URL, no auth needed for msgs)
         → compute(decrypt, blob, key, iv from Signal envelope)
         → display

  AVATAR FETCH: Image.network(avatarUrl) — no JWT header needed (public)

Nginx
  POST /media/upload  → proxy → NestJS :3000 (JWT checked in NestJS)
  GET  /media/msgs/:filename  → proxy → NestJS → X-Accel-Redirect (no auth, file is ciphertext)
  GET  /media/avatars/:filename → served directly as public static (or X-Accel-Redirect, no auth)
  location /internal/media/ { internal; alias /app/media/; }

NestJS :3000
  MediaController: POST /media/upload, GET /media/msgs/:filename, GET /media/avatars/:filename
  LocalStorageService (replaces CloudinaryService, identical method signatures)
  MediaCleanupService: on-demand + cron daily at 03:00

Docker Volume: media_storage → /app/media (both containers, NestJS rw / Nginx ro)
  ├── avatars/   (unencrypted JPEG/PNG, publicly accessible)
  └── msgs/      (AES-256-GCM encrypted blobs, also publicly accessible — useless without key)
```

### Why message media can be public URLs

Encrypted blobs are opaque ciphertext. Without the AES key (which lives only inside the Signal E2E envelope), the blob is unreadable. JWT on the GET endpoint adds no real security — it only prevents unauthenticated listing, but each blob has a UUID filename that cannot be guessed. This matches the threat model of Signal's attachment CDN.

---

## Backend Design

### LocalStorageService (`backend/src/media/local-storage.service.ts`)

Replaces `CloudinaryService` with **identical method signatures** so call sites require minimal changes.

| Method | Behaviour |
|---|---|
| `uploadAvatar(userId, buffer, mimeType)` | Saves to `/app/media/avatars/{uuid}.{ext}`, returns `{secureUrl, publicId}` |
| `uploadImage(userId, buffer, mimeType)` | Saves to `/app/media/msgs/{uuid}.bin`, returns `{secureUrl, publicId}` |
| `uploadVoiceMessage(userId, buffer, mimeType, duration, expiresIn?)` | Saves to `/app/media/msgs/{uuid}.bin`, returns `{secureUrl, publicId, duration}`. **Duration comes from client** — server cannot compute duration from opaque ciphertext. |
| `uploadRawFile(userId, buffer, mimeType, filename?)` | Saves to `/app/media/msgs/{uuid}.bin`, returns `{secureUrl, publicId}` |
| `deleteAvatar(publicId)` | Deletes `/app/media/{publicId}` from disk |
| `deleteFile(publicId)` | Deletes `/app/media/{publicId}` from disk. **Uses `publicId` (relative path), not full URL**, to avoid fragile URL parsing and survive `MEDIA_BASE_URL` changes. |

- Avatar files retain original extension (`.jpg`, `.png`) for browser display
- Message media files use `.bin` — opaque encrypted blobs
- `publicId` = relative path within `/app/media/` (e.g. `msgs/abc123.bin`, `avatars/uuid.jpg`)
- Base URL from `MEDIA_BASE_URL` env var (e.g. `https://fireplace.ignorelist.com`)

### Voice Duration

Cloudinary previously computed audio duration server-side. After migration, the backend stores opaque ciphertext and **cannot compute duration**. The Flutter client **must measure duration before encryption** and pass it as the `duration` field in the upload request. `LocalStorageService.uploadVoiceMessage` returns the client-provided duration unchanged.

### MediaController (`backend/src/media/media.controller.ts`)

**Route order matters** — more specific routes must be registered before wildcard routes in NestJS:

```
POST /media/upload                  JWT required, accepts binary blob
                                    + body fields: mediaType, duration?, expiresIn? (seconds, matches existing /messages/upload-media API)
                                    Returns { mediaUrl, mediaDuration? } or { mediaUrl, fileName }
                                    Rate limit: 20 req/min (same as existing media endpoints)

GET  /media/avatars/:filename       No auth — public static
                                    → X-Accel-Redirect: /internal/media/avatars/:filename

GET  /media/msgs/:filename          No auth — ciphertext is useless without key
                                    → X-Accel-Redirect: /internal/media/msgs/:filename
                                    Rate limit: 60 req/min per IP (protect disk I/O)
```

**IMPORTANT — Route ordering:** `GET /media/avatars/:filename` MUST be declared before `GET /media/msgs/:filename` in the NestJS controller to prevent the `:filename` wildcard from matching `avatars/...` paths.

### DTO Validation — CLOUDINARY_URL_REGEX

`SendMessageDto` in `chat/dto/chat.dto.ts` currently enforces `@Matches(CLOUDINARY_URL_REGEX)` on `mediaUrl`. For E2E messages, `mediaUrl` is **inside the Signal envelope** — the server only receives `encryptedContent` in `sendMessage`, so `mediaUrl` is `null` on the DTO and the regex is never triggered. However, to be safe and future-proof, the regex must be updated to also accept self-hosted URLs:

```typescript
// Replace CLOUDINARY_URL_REGEX with:
const MEDIA_URL_REGEX = /^https:\/\/(res\.cloudinary\.com\/|fireplace\.ignorelist\.com\/media\/)/;
```

This also allows legacy Cloudinary URLs (for backward compat with unencrypted historical messages).

### Module changes

- `cloudinary.module.ts` → replaced by `media.module.ts` (exports `LocalStorageService`, `MediaCleanupService`)
- `app.module.ts`: swap `CloudinaryModule` → `MediaModule`, add `ScheduleModule.forRoot()`
- `users.controller.ts`: inject `LocalStorageService` instead of `CloudinaryService`
- `messages.controller.ts`: MIME validation removed for upload (client pre-validates); backend accepts any binary blob. `duration` field passed through from client for voice.

### MediaCleanupService (`backend/src/media/media-cleanup.service.ts`)

Uses `publicId` (relative path, stored in message `mediaUrl` after stripping base URL — or stored as a separate column) for all deletion. **Recommendation:** store `publicId` as a separate DB column, or extract it consistently via `url.replace(MEDIA_BASE_URL + '/media/', '')`.

**publicId extraction:** `publicId` is derived from `mediaUrl` by stripping the base URL prefix: `mediaUrl.replace(MEDIA_BASE_URL + '/media/', '')`. No new DB column needed — `mediaUrl` is the single source of truth.

**On-demand triggers:**

| Event | Action |
|---|---|
| `deleteMessage` (for_everyone) | `deleteFile(extractPublicId(message.mediaUrl))` |
| `clearChatHistory` | `deleteFile(extractPublicId(msg.mediaUrl))` for all messages in conversation with non-null `mediaUrl` |
| `deleteConversationOnly` | Same as clearChatHistory |
| `unfriend` | Same as clearChatHistory for the removed conversation |
| `deleteAccount` | All messages where `senderId = userId`, delete each non-null `mediaUrl` |

**Cron safety net (`@Cron('0 3 * * *')`):**
1. Scan `/app/media/msgs/` for all filenames on disk
2. Query DB for all currently valid media references:
   ```sql
   SELECT "mediaUrl" FROM messages
   WHERE "mediaUrl" IS NOT NULL
     AND ("expiresAt" IS NULL OR "expiresAt" > NOW())
   ```
3. Delete files on disk whose filename is NOT in the valid references set (orphaned)
4. Separately: delete files whose `expiresAt` has passed (cross-check via DB)

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

  /// Encrypts in background isolate via compute().
  /// Generates fresh random 256-bit key + 96-bit IV per call.
  /// Throws ArgumentError if bytes.length > 20MB.
  Future<EncryptedMedia> encrypt(Uint8List bytes);

  /// Decrypts in background isolate via compute().
  Future<Uint8List> decrypt(Uint8List ciphertext, String keyB64, String ivB64);
}
```

- Uses `pointycastle` package (already available in project) for AES-256-GCM
- `compute()` wraps both operations — UI thread never blocked
- Keys are in-memory only during send/receive — never logged, never stored server-side

### Progress UX

| Phase | File size | UX |
|---|---|---|
| Encrypting | < 500 KB | No indicator — imperceptible |
| Encrypting | ≥ 500 KB | Indeterminate spinner on message bubble |
| Uploading | Any | Determinate progress bar (%) via `StreamedRequest` |
| Decrypting | Any | Indeterminate spinner while `compute()` runs |

### Send Flow

```
sendImage() / sendVoice() / sendGif() / sendFile()
  1. Create optimistic message (SENDING) → notifyListeners()
  2. [voice only] measure duration from audio BEFORE encrypting
  3. compute(encrypt, rawBytes) → EncryptedMedia{ciphertext, key, iv}
  4. _pendingSendContent[tempId] = <String,dynamic>{
       'content': content, 'messageType': type,
       'mediaKey': key, 'mediaIv': iv
     }
     ← MUST be written before _encryptAndSend() await
  5. POST /media/upload (encrypted blob, JWT) with StreamedRequest → {mediaUrl}
  6. _pendingSendContent[tempId]['mediaUrl'] = mediaUrl
  7. _encryptAndSend(content, messageType, mediaUrl, mediaKey: key, mediaIv: iv)
     └─ Signal envelope: {content, messageType, mediaUrl, mediaKey, mediaIv}
```

### Receive Flow

```
onNewMessage() → Signal decrypt → E2eEnvelope.parse()
  if envelope.mediaKey != null:
    1. GET /media/msgs/:filename (no auth header needed — public URL)
    2. compute(decrypt, responseBytes, mediaKey, mediaIv)
    3. render decrypted bytes
       - image: MemoryImage(bytes)
       - voice: write to temp file → audio player
       - GIF (web): Uint8List → blob URL via js interop (Image.memory does not animate GIFs on Flutter web)
       - GIF (native): Image.memory(bytes)
       - file: write to temp file → open with url_launcher
  else (legacy — no mediaKey in envelope):
    load mediaUrl directly (Cloudinary URL — backward compat)
```

### GIF on Flutter Web

`Image.memory` does not animate GIFs on Flutter web. After decryption, on web:
```dart
// Use existing blob URL pattern from the codebase (already present for GIF fetching)
if (kIsWeb) {
  final blob = html.Blob([decryptedBytes], 'image/gif');
  final url = html.Url.createObjectUrlFromBlob(blob);
  // Image.network(url) — animates correctly
}
```
This is the same pattern already used in `gif_message_content.dart` for Giphy downloads.

### Avatars

Avatars are now public URLs — **no JWT header required**:
```dart
// AvatarCircle: no change needed to Image.network() calls
// avatarUrl already stored in AuthProvider / UserModel
// Flutter web Image.network works without Authorization header
```
No changes needed in `AvatarCircle` — removing the JWT requirement is the simplest solution and matches how Signal/WhatsApp handle profile pictures.

### E2eEnvelope Changes

The existing `E2eEnvelope` is implemented as a static-method utility class (not a Dart record). Add two nullable fields to `build()` and `parse()`:

**`build()` — add optional named params:**
```dart
static String build(
  String content, {
  String? messageType,
  String? mediaUrl,
  int? mediaDuration,
  String? mediaKey,    // NEW
  String? mediaIv,     // NEW
  Map<String, dynamic>? linkPreview,
}) {
  return jsonEncode({
    'content': content,
    if (messageType != null) 'messageType': messageType,
    if (mediaUrl != null) 'mediaUrl': mediaUrl,
    if (mediaDuration != null) 'mediaDuration': mediaDuration,
    if (mediaKey != null) 'mediaKey': mediaKey,   // NEW
    if (mediaIv != null) 'mediaIv': mediaIv,      // NEW
    if (linkPreview != null) 'linkPreview': linkPreview,
  });
}
```

**`parse()` — extract new fields, null if absent:**
```dart
// existing parsed fields unchanged
final mediaKey = map['mediaKey'] as String?;   // NEW
final mediaIv = map['mediaIv'] as String?;     // NEW
```

Callers of `parse()` that destructure the result must be updated to include `mediaKey` / `mediaIv`. All existing callers continue to work — old envelopes simply have `mediaKey = null`.

---

## Nginx Configuration

```nginx
# In the server block (nginx.conf or site config)

# Internal location — ONLY reachable via X-Accel-Redirect from NestJS
location /internal/media/ {
    internal;
    alias /app/media/;
    # File permissions: NestJS writes as node user (UID varies).
    # Set volume dir permissions: chmod 755 /app/media, chmod 644 on files.
    # Both containers must agree on UID or use chmod a+r on write.
}

# Upload goes through NestJS (JWT checked there)
location /media/upload {
    proxy_pass http://backend:3000;
    proxy_set_header Authorization $http_authorization;
    client_max_body_size 11m;
}

# All other /media/ requests → NestJS for auth/redirect
location /media/ {
    proxy_pass http://backend:3000;
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
    # Ensure files are world-readable for Nginx:
    # entrypoint sets umask 022 or chmod on /app/media at startup

  nginx:
    volumes:
      - media_storage:/app/media:ro  # read-only — Nginx only serves, never writes
```

**File permissions note:** Files written by the NestJS (`node`) user must be readable by the Nginx user. Two options:
1. Set `umask 022` in the NestJS container entrypoint so written files are world-readable
2. Add a startup script: `chmod -R 755 /app/media` before NestJS starts

---

## Backward Compatibility

| Scenario | Behaviour |
|---|---|
| Old message — Cloudinary URL, no `mediaKey` in envelope | `envelope.mediaKey == null` → load directly from Cloudinary URL (works until Cloudinary decommissioned) |
| Old avatar on Cloudinary | Displayed from Cloudinary URL until user updates avatar |
| New message with `mediaKey` | Fetch blob from VM, decrypt client-side |
| New avatar | Fetched from VM as public URL |

`MEDIA_URL_REGEX` in `SendMessageDto` updated to accept both Cloudinary and self-hosted URLs.

Cloudinary can be decommissioned when: no active user has a Cloudinary avatar AND all Cloudinary-hosted message media has expired or been deleted.

---

## Security Properties

| Property | Status after implementation |
|---|---|
| Message media encrypted at rest | ✅ AES-256-GCM, key never reaches server unencrypted |
| Media upload requires auth | ✅ JWT required on POST /media/upload |
| Media download requires auth | ❌ Public by design — blobs are ciphertext, useless without key |
| Server is blind to plaintext media | ✅ Never sees plaintext — only opaque AES-256-GCM ciphertext |
| Key stored server-side | ✅ Never — key lives only in Signal E2E envelope |
| Avatar encrypted at rest | ❌ Not encrypted (deliberate — profile pictures are not private) |
| Avatar access requires auth | ❌ Public (deliberate — same model as Signal/WhatsApp; no Flutter web JWT issue) |

---

## Out of Scope

- Multi-device key sharing
- Thumbnail generation
- CDN / geographic distribution
- Resumable uploads
- Encryption of avatars
- Migration script for existing Cloudinary media (users keep old messages as-is)
- Rate limiting beyond what is specified (GET /media/msgs: 60/min per IP)
