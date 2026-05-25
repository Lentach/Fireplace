# Media Self-Hosting + AES-256-GCM Encryption Design

**Date:** 2026-03-22
**Status:** Approved (v3 — post user review)
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
- CLAUDE.md updated to reflect actual `MediaCryptoService` implementation

---

## Architecture

```
Flutter Client
  SEND:  rawBytes → compute(encrypt) → {ciphertext, key, iv}
         POST /media/upload (JWT, binary blob) → {mediaUrl}
         key+IV → Signal E2E envelope → sendMessage (server never sees key)

  RECV:  GET /media/msgs/:id (public URL — ciphertext only, key not here)
         → compute(decrypt, blob, key, iv from Signal envelope)
         → display

  AVATAR FETCH: Image.network(avatarUrl) — no JWT header (public)

Nginx
  POST /media/upload           → proxy → NestJS :3000 (JWT checked in NestJS)
  GET  /media/msgs/:filename   → NestJS → X-Accel-Redirect → disk (no auth)
  GET  /media/avatars/:filename → NestJS → X-Accel-Redirect → disk (no auth)
  location /internal/media/ { internal; alias /app/media/; }

NestJS :3000
  MediaController: POST /media/upload, GET /media/msgs/:filename, GET /media/avatars/:filename
  LocalStorageService (replaces CloudinaryService, identical method signatures)
  MediaCleanupService: on-demand + cron daily at 03:00

Docker Volume: media_storage → /app/media (NestJS rw / Nginx ro)
  ├── avatars/   (unencrypted JPEG/PNG, publicly accessible)
  └── msgs/      (AES-256-GCM encrypted blobs, publicly accessible — useless without key)
```

### Why message media can be public URLs

Encrypted blobs are opaque ciphertext. Without the AES key (which lives only inside the Signal E2E envelope), the blob is unreadable. JWT on the GET endpoint adds no real security — each blob has a UUID filename that cannot be guessed. This matches the threat model of Signal's attachment CDN.

**Known limitations (conscious trade-offs):**
- URL leak (logs, referrer headers, shared link) exposes the ciphertext blob — not the plaintext
- Traffic analysis: an observer can see who downloads which UUID and when — not the content
- Retention after deletion: if a URL was leaked before deletion, the file may have already been fetched — same as any CDN model
- These are acceptable given the threat model (ciphertext without key = no data exposure)

---

## Backend Design

### Endpoint Strategy: POST /messages/upload-media → POST /media/upload

The existing `POST /messages/upload-media` endpoint is **replaced** by `POST /media/upload`. No dual-endpoint period — the Flutter client is updated in the same deploy. Old Cloudinary URLs remain valid for backward compat (legacy messages still load from Cloudinary until they expire).

### LocalStorageService (`backend/src/media/local-storage.service.ts`)

Replaces `CloudinaryService` with **identical method signatures** so call sites require minimal changes.

| Method | Behaviour |
|---|---|
| `uploadAvatar(userId, buffer, mimeType)` | Saves to `/app/media/avatars/{uuid}.{ext}`, returns `{secureUrl, publicId}` |
| `uploadImage(userId, buffer, mimeType)` | Saves to `/app/media/msgs/{uuid}.bin`, returns `{secureUrl, publicId}` |
| `uploadVoiceMessage(userId, buffer, mimeType, duration, expiresIn?)` | Saves to `/app/media/msgs/{uuid}.bin`, returns `{secureUrl, publicId, duration}`. Duration comes from client — server cannot compute from opaque ciphertext. |
| `uploadRawFile(userId, buffer, mimeType, filename?)` | Saves to `/app/media/msgs/{uuid}.bin`, returns `{secureUrl, publicId}` |
| `deleteAvatar(publicId)` | Deletes `/app/media/{publicId}` from disk |
| `deleteFile(publicId)` | Deletes `/app/media/{publicId}` from disk using relative path |

- Avatar files retain original extension (`.jpg`, `.png`) for browser display
- Message media files use `.bin` — opaque encrypted blobs
- `publicId` = relative path within `/app/media/` (e.g. `msgs/abc123.bin`, `avatars/uuid.jpg`)
- Base URL from `MEDIA_BASE_URL` env var

### publicId Extraction

`publicId` is derived from `mediaUrl` by stripping the base URL prefix:
```typescript
function extractPublicId(mediaUrl: string, baseUrl: string): string {
  return mediaUrl.replace(`${baseUrl}/media/`, '');
}
```
`MEDIA_BASE_URL` is the single source of truth — no new DB column needed. The cron job uses the same function to match disk filenames against DB references.

### Voice Duration

Cloudinary previously computed audio duration server-side. After migration, the backend stores opaque ciphertext and **cannot compute duration**. The Flutter client **must measure duration before encryption** and pass it as the `duration` field in the upload request. `LocalStorageService.uploadVoiceMessage` returns the client-provided duration unchanged.

### MediaController (`backend/src/media/media.controller.ts`)

```
POST /media/upload                  JWT required, accepts binary blob (application/octet-stream)
                                    + body fields: mediaType ('image'|'voice'|'gif'|'file'|'avatar'),
                                      duration? (seconds, client-measured for voice),
                                      expiresIn? (seconds — consistent with existing /messages/upload-media)
                                    Returns { mediaUrl, mediaDuration? } or { mediaUrl, fileName }
                                    NestJS body size limit: 11 MB (matches Nginx client_max_body_size)
                                    Rate limit: 20 req/min (matches existing media endpoints)

GET  /media/avatars/:filename       No auth — public static
                                    → X-Accel-Redirect: /internal/media/avatars/:filename

GET  /media/msgs/:filename          No auth — ciphertext is useless without key
                                    → X-Accel-Redirect: /internal/media/msgs/:filename
                                    Rate limit: 60 req/min per IP (protect disk I/O)
```

**Note on route ordering:** Routes `GET /media/avatars/:filename` and `GET /media/msgs/:filename` use literal path segments (`avatars`, `msgs`) — there is no wildcard collision between them. NestJS resolves these correctly without special ordering. The `POST /media/upload` literal route takes priority over any dynamic routes automatically.

### DTO Validation — mediaUrl regex

`SendMessageDto` in `chat/dto/chat.dto.ts` enforces `@Matches(CLOUDINARY_URL_REGEX)` on `mediaUrl`. For E2E messages, `mediaUrl` is inside the Signal envelope — the server receives only `encryptedContent` in `sendMessage`, so `mediaUrl` is `null` on the DTO and the regex is never triggered.

However, the regex must be updated to:
1. Accept self-hosted URLs (for any future non-E2E path)
2. Correctly cover all Cloudinary path types used by the app (image upload, video/audio upload, **and raw/upload for FILE type documents**)

```typescript
// MEDIA_BASE_URL read from ConfigService — no hardcoded hostname
// Validated at startup in MediaModule to ensure env var is set

export function buildMediaUrlValidator(mediaBaseUrl: string) {
  const escapedBase = mediaBaseUrl.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return new RegExp(
    `^https://(res\\.cloudinary\\.com/.+/(image|video|raw)/upload/|${escapedBase}/media/)`,
  );
}
```

This approach:
- Covers Cloudinary `image/upload/`, `video/upload/` (voice), and `raw/upload/` (FILE documents)
- Covers self-hosted `${MEDIA_BASE_URL}/media/` URLs
- Does not hardcode `fireplace.ignorelist.com` — works on staging, local Docker, domain changes

### Module changes

- `cloudinary.module.ts` → replaced by `media.module.ts` (exports `LocalStorageService`, `MediaCleanupService`)
- `app.module.ts`: swap `CloudinaryModule` → `MediaModule`, add `ScheduleModule.forRoot()`
- `users.controller.ts`: inject `LocalStorageService` instead of `CloudinaryService`
- `messages.controller.ts`: route `POST /messages/upload-media` removed — replaced by `POST /media/upload`

### MediaCleanupService (`backend/src/media/media-cleanup.service.ts`)

**On-demand triggers:**

| Event | Action |
|---|---|
| `deleteMessage` (for_everyone) | `deleteFile(extractPublicId(message.mediaUrl))` |
| `clearChatHistory` | `deleteFile` for all non-null `mediaUrl` values in conversation |
| `deleteConversationOnly` | Same as clearChatHistory |
| `unfriend` | Same as clearChatHistory for the removed conversation |
| `deleteAccount` | All messages where `senderId = userId`, delete each non-null `mediaUrl` |

Only deletes files whose URL starts with `MEDIA_BASE_URL` (i.e. self-hosted). Legacy Cloudinary URLs are skipped — Cloudinary account handles their lifecycle.

**Cron safety net (`@Cron('0 3 * * *')`):**
1. Scan `/app/media/msgs/` for all filenames on disk (e.g. `abc123.bin`)
2. Query DB for all currently valid self-hosted media references:
   ```sql
   SELECT "mediaUrl" FROM messages
   WHERE "mediaUrl" IS NOT NULL
     AND "mediaUrl" LIKE $1  -- $1 = MEDIA_BASE_URL + '/media/%'
     AND ("expiresAt" IS NULL OR "expiresAt" > NOW())
   ```
3. Extract `publicId` from each valid URL via `extractPublicId()`
4. Delete disk files whose `publicId` is NOT in the valid set (orphaned or expired)

---

## Frontend Design

### MediaCryptoService (`frontend/lib/services/media_crypto_service.dart`)

**AES-256-GCM blob format:** `blob = ciphertext || authTag` where `authTag` is 128 bits (16 bytes), appended by PointyCastle's GCM implementation. Key is 256 bits (32 bytes), IV is 96 bits (12 bytes). This format must be consistent across any future clients.

```dart
class EncryptedMedia {
  final Uint8List ciphertext; // encrypted bytes + 16-byte GCM auth tag appended
  final String keyBase64;     // 32-byte AES-256 key, base64url-encoded
  final String ivBase64;      // 12-byte GCM IV, base64url-encoded
}

class MediaCryptoService {
  static const int _maxBytes = 20 * 1024 * 1024; // 20 MB hard cap

  /// Encrypts in background isolate via compute().
  /// Generates fresh random key + IV per call.
  /// Throws ArgumentError if bytes.length > 20MB.
  Future<EncryptedMedia> encrypt(Uint8List bytes);

  /// Decrypts in background isolate via compute().
  Future<Uint8List> decrypt(Uint8List ciphertext, String keyB64, String ivB64);
}
```

- Uses `pointycastle` (^4.0.0, already in pubspec.yaml) for AES-256-GCM
- `compute()` wraps both operations — UI thread never blocked
- Must be tested on both Flutter web (PointyCastle is pure Dart — no platform channels, works on web) and native
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
     ← MUST be written BEFORE _encryptAndSend() await (see CLAUDE.md rule)
  5. POST /media/upload (encrypted blob, JWT) with StreamedRequest → {mediaUrl}
  6. _pendingSendContent[tempId]['mediaUrl'] = mediaUrl
     ← mediaUrl added BEFORE calling _encryptAndSend()
  7. _encryptAndSend(content, messageType, mediaUrl, mediaKey: key, mediaIv: iv)
     └─ Signal envelope: {content, messageType, mediaUrl, mediaKey, mediaIv}
```

### Receive Flow

```
onNewMessage() → Signal decrypt → E2eEnvelope.parse()
  if envelope.mediaKey != null:
    1. GET /media/msgs/:filename (no auth — public URL)
    2. compute(decrypt, responseBytes, mediaKey, mediaIv)
    3. render decrypted bytes:
       - image: MemoryImage(bytes)
       - voice: write to temp file → audio player
       - GIF (web): blob URL via dart:js interop — Image.memory does not animate on Flutter web
       - GIF (native): Image.memory(bytes)
       - file: write to temp file → open with url_launcher
  else (legacy — no mediaKey):
    load mediaUrl directly (Cloudinary URL — backward compat)
```

### GIF on Flutter Web

`Image.memory` does not animate GIFs on Flutter web. After decryption, on web:
```dart
if (kIsWeb) {
  final blob = html.Blob([decryptedBytes], 'image/gif');
  final url = html.Url.createObjectUrlFromBlob(blob);
  // Image.network(url) — animates correctly
}
```
Same pattern already used in `gif_message_content.dart` for Giphy downloads — reuse existing code.

### Avatars

Avatars are now public URLs — **no JWT header required**. `AvatarCircle` requires no changes — `Image.network(url)` without headers works on Flutter web and native.

### E2eEnvelope Changes (`encryption_service.dart`)

Add two nullable fields. The class uses static methods (`build()`/`parse()`) — this is an additive change, not a structural refactor.

**`build()` — add optional named params:**
```dart
static String build(String content, {
  String? messageType, String? mediaUrl, int? mediaDuration,
  String? mediaKey,   // NEW — null for text messages
  String? mediaIv,    // NEW — null for text messages
  Map<String, dynamic>? linkPreview,
}) {
  return jsonEncode({
    'content': content,
    if (messageType != null) 'messageType': messageType,
    if (mediaUrl != null) 'mediaUrl': mediaUrl,
    if (mediaDuration != null) 'mediaDuration': mediaDuration,
    if (mediaKey != null) 'mediaKey': mediaKey,
    if (mediaIv != null) 'mediaIv': mediaIv,
    if (linkPreview != null) 'linkPreview': linkPreview,
  });
}
```

**`parse()` — extract new fields, null if absent:**
```dart
final mediaKey = map['mediaKey'] as String?;  // NEW
final mediaIv  = map['mediaIv']  as String?;  // NEW
```

All existing callers work unchanged — old envelopes have `mediaKey = null`.

---

## Nginx Configuration

```nginx
# Internal location — ONLY reachable via X-Accel-Redirect
location /internal/media/ {
    internal;
    alias /app/media/;
    # Permissions: files written by NestJS must be world-readable.
    # NestJS entrypoint sets umask 022 so written files are 644 by default.
}

# Upload proxied to NestJS (JWT checked there)
location = /media/upload {
    proxy_pass http://backend:3000;
    proxy_set_header Authorization $http_authorization;
    client_max_body_size 11m;  # 10MB file + multipart overhead
}

# All other /media/ requests → NestJS for X-Accel-Redirect
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
    # NestJS Dockerfile entrypoint: set umask 022 so files are world-readable by Nginx

  nginx:
    volumes:
      - media_storage:/app/media:ro  # read-only — Nginx only serves via X-Accel-Redirect
```

---

## Implementation Risks

| Area | Risk | Mitigation |
|---|---|---|
| AES-GCM blob format | Flutter ↔ other clients diverge on ciphertext+tag layout | Spec defines format explicitly: `blob = ciphertext \|\| 16-byte GCM tag` (PointyCastle default) |
| compute() on web | PointyCastle is pure Dart — should work on web without platform channels | Add integration tests: encrypt on web, decrypt on native and vice versa |
| GET 60/min/IP rate limit | Fast scroll in media-heavy chat hits limit | Monitor in production; increase to 120/min or add client-side LRU cache if needed |
| Endpoint cutover | No dual-endpoint period — Flutter and backend deploy together | Single coordinated deploy; old Cloudinary URLs remain valid for legacy messages |
| Cron + extractPublicId | URL format change breaks orphan detection | `extractPublicId` function is shared between on-demand and cron — single implementation |
| NestJS body size | NestJS default body parser rejects >100KB raw bodies | Set `rawBody: true` and `bodyParser: false` in NestJS bootstrap, use raw body middleware for `/media/upload` |

---

## Backward Compatibility

| Scenario | Behaviour |
|---|---|
| Old message — Cloudinary URL, no `mediaKey` in envelope | `envelope.mediaKey == null` → load directly from Cloudinary URL |
| Old avatar on Cloudinary | Displayed from Cloudinary URL until user updates avatar |
| New message with `mediaKey` | Fetch blob from VM, decrypt client-side |
| New avatar | Fetched from VM as public URL |

`MEDIA_URL_REGEX` in `SendMessageDto` updated to accept both Cloudinary paths (`image/upload/`, `video/upload/`, `raw/upload/`) and self-hosted URLs — built dynamically from `MEDIA_BASE_URL` env var.

Cloudinary can be decommissioned when: no active user has a Cloudinary avatar AND all Cloudinary-hosted message media has expired or been deleted.

---

## Security Properties

| Property | Status |
|---|---|
| Message media encrypted at rest | ✅ AES-256-GCM client-side — key never reaches server |
| Media upload requires auth | ✅ JWT required on POST /media/upload |
| Media download requires auth | ❌ Public by design — ciphertext without key = no data exposure |
| Server is blind to plaintext | ✅ Server stores only opaque AES-256-GCM ciphertext |
| Encryption key stored server-side | ❌ Never — key lives only in Signal E2E envelope |
| Avatar encrypted at rest | ❌ Deliberate — profile pictures are not private message content |
| Avatar download requires auth | ❌ Public — same model as Signal/WhatsApp |

---

## Out of Scope

- Multi-device key sharing
- Thumbnail generation
- CDN / geographic distribution
- Resumable uploads
- Encryption of avatars
- Migration script for existing Cloudinary media (legacy messages load from Cloudinary as-is)
