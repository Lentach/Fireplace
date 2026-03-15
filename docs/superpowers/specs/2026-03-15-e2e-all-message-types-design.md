# E2E Encryption for All Message Types + Drawing Removal

**Date:** 2026-03-15
**Status:** Approved

## Summary

Extend E2E encryption (Signal Protocol) to cover **all** message types: ping, voice, and image. Currently only text messages are encrypted. Also remove the drawing feature entirely.

After this change, the server will be blind to message type, media URLs, and media metadata — everything hidden inside the encrypted Signal envelope.

## Current State

| Type | Encrypted | Server sees |
|------|-----------|-------------|
| Text | Yes | `[encrypted]` + ciphertext |
| Ping | No | empty content, type=PING |
| Voice | No | Cloudinary URL in plaintext, type=VOICE |
| Image | No | Cloudinary URL in plaintext, type=IMAGE |
| Drawing | No | never used (uploaded as IMAGE) |

## Target State

| Type | Encrypted | Server sees |
|------|-----------|-------------|
| Text | Yes | `[encrypted]` + ciphertext, type=TEXT |
| Ping | Yes | `[encrypted]` + ciphertext, type=TEXT |
| Voice | Yes | `[encrypted]` + ciphertext, type=TEXT, mediaUrl=null |
| Image | Yes | `[encrypted]` + ciphertext, type=TEXT, mediaUrl=null |
| Drawing | Removed | — |

Server stores all encrypted messages identically: `content='[encrypted]'`, `encryptedContent=<ciphertext>`, `messageType=TEXT`, `mediaUrl=null`. It cannot distinguish between message types.

**Bonus:** Image messages now deliver in real-time via WebSocket (previously, `POST /messages/image` created the DB row but never emitted a WebSocket event to the recipient — they only saw images on next `getMessages`).

## Design

### 1. Extended E2E Envelope

**File:** `frontend/lib/utils/e2e_envelope.dart`

```json
{
  "content": "string",
  "messageType": "TEXT|PING|VOICE|IMAGE",
  "mediaUrl": "string | null",
  "mediaDuration": "int | null",
  "linkPreview": {
    "url": "string | null",
    "title": "string | null",
    "imageUrl": "string | null"
  }
}
```

Rules:
- `messageType` defaults to `TEXT` when absent (backward compatibility with old encrypted messages)
- `linkPreview` only for TEXT
- `mediaUrl` only for VOICE/IMAGE
- `mediaDuration` only for VOICE

Changes to `E2eEnvelope`:
- `build()` accepts optional `messageType`, `mediaUrl`, `mediaDuration`
- `parse()` returns a record with all fields, defaulting `messageType` to `TEXT`

### 2. New Backend Endpoint: `POST /messages/upload-media`

**File:** `backend/src/messages/messages.controller.ts`

```
Auth: JWT
Body: multipart
  - file: image (JPEG/PNG, max 5MB) or audio (AAC/MP4/WAV/WEBM/MPEG, max 10MB)
  - type: 'image' | 'voice'
  - duration?: number (voice only, seconds)
  - expiresIn?: number (seconds, forwarded to Cloudinary TTL for disappearing media)
Response: { mediaUrl: string, mediaDuration?: number }
Rate limit: 10/min
```

This endpoint **only** uploads to Cloudinary and returns the URL. It does **not** create a message in the database. Message creation happens via the WebSocket `sendMessage` handler.

No `recipientId` required — friendship validation happens in `handleSendMessage`. Abuse risk (free Cloudinary hosting) is mitigated by JWT auth + rate limiting (10/min). Accepted trade-off for cleaner separation.

### 3. Removed Backend Endpoints

- `POST /messages/image` — replaced by `upload-media`
- `POST /messages/voice` — replaced by `upload-media`
- Delete DTOs: `dto/upload-image.dto.ts`, `dto/upload-voice.dto.ts`
- New DTO: `dto/upload-media.dto.ts`

### 4. Removed WebSocket Events

- `sendPing` (client emit) — ping now goes through `sendMessage`
- `pingSent` (server emit to sender) — replaced by `messageSent`
- `newPing` (server emit to recipient) — replaced by `newMessage`

Backend: remove `handleSendPing()` from `ChatMessageService` and `@SubscribeMessage('sendPing')` from `ChatGateway`.

Frontend: remove `sendPing()` from `SocketService`, remove `onPingSent`/`onPingReceived` required callbacks from `SocketService.connect()` signature and all call sites.

### 5. Send Flows

#### Ping (new flow)

1. `ChatProvider.sendPing(recipientId)` creates optimistic message (`messageType: PING`, `content: ''`, `deliveryStatus: SENDING`)
2. Reads `conversationDisappearingTimer` and passes as `expiresIn` (same logic as current `handleSendPing` backend — moved to frontend)
3. Calls `_encryptAndSend(recipientId, content: '', messageType: 'PING', effectiveExpiresIn: expiresIn)`
4. Envelope `{ content: '', messageType: 'PING' }` encrypted via Signal
5. Socket emits `sendMessage` with `encryptedContent` only
6. Server stores as TEXT with ciphertext — blind to ping

#### Voice (new flow)

1. `sendVoiceMessage()` creates optimistic message (unchanged)
2. REST upload via `POST /messages/upload-media` with `type: 'voice'`, `duration`, optional `expiresIn` → returns `{ mediaUrl, mediaDuration }`
3. Updates optimistic message with Cloudinary URL
4. Calls `_encryptAndSend(recipientId, content: '', messageType: 'VOICE', mediaUrl: cloudinaryUrl, mediaDuration: duration)`
5. Envelope `{ content: '', messageType: 'VOICE', mediaUrl: '...', mediaDuration: 5 }` encrypted
6. Socket emits `sendMessage` with `encryptedContent` only (no plaintext mediaUrl)
7. Server stores as TEXT — blind to voice

#### Image (new flow)

1. `sendImageMessage()` creates optimistic message
2. REST upload via `POST /messages/upload-media` with `type: 'image'`, optional `expiresIn` → returns `{ mediaUrl }`
3. Calls `_encryptAndSend(recipientId, content: '', messageType: 'IMAGE', mediaUrl: cloudinaryUrl)`
4. Envelope encrypted, socket emits with `encryptedContent` only
5. Server stores as TEXT — blind to image

#### Text (unchanged)

Same as current: content + optional link preview in envelope, encrypted, sent via `sendMessage`.

### 6. Receive / Decrypt Flow

**Recipient receives `newMessage`:**

`_decryptMessageAsync()` → `E2eEnvelope.parse(plaintext)` → returns `{ content, messageType, mediaUrl, mediaDuration, linkPreviewUrl, ... }` → `msg.copyWith()` with all fields including `messageType`.

**Critical:** `MessageModel.copyWith()` must be extended to accept `messageType` parameter. Currently `copyWith` preserves the existing type — but for encrypted messages the server stores `TEXT`, so the real type from the envelope must override it. (CLAUDE.md gotcha: "`copyWith` must include ALL fields — missing field = data silently lost.")

**Sender receives `messageSent`:**

`_addMessageToState()` — `_pendingSendContent` type changes from `Map<String, Map<String, String?>>` to `Map<String, Map<String, dynamic>>` to accommodate `mediaDuration` (int) alongside string fields. Stores `messageType`, `mediaUrl`, `mediaDuration` alongside `content` and link preview. On confirmation, sender restores all fields via `copyWith`.

**Persisted cache:**

`_persistDecryptedContent()` and `getDecryptedContent()` — extended to include `messageType`, `mediaUrl`, `mediaDuration`. On re-login, both sender and recipient restore full data from localStorage/SharedPreferences.

**History decryption:**

`_decryptMessageHistory()` — both paths updated:
1. Recipient path (live decrypt): `_decryptMessageAsync()` returns message with all fields from envelope
2. Own-message recovery path (`msg.senderId == _currentUserId && msg.content == '[encrypted]'`): restores `messageType`, `mediaUrl`, `mediaDuration` from persisted cache alongside content and link preview

### 7. Backend `handleSendMessage` Changes

- For encrypted messages (`data.encryptedContent` present): `mediaUrl` will be null — existing DTO `@ValidateIf` on `mediaUrl` already handles this (only validates when non-null), so no DTO change needed
- Store `messageType = TEXT` regardless (server doesn't know real type)
- Skip server-side link preview fetch (already done for encrypted — no change)
- Push notifications: unchanged (silent payload, no content revealed)

### 8. `_encryptAndSend` Refactor

Current signature:
```dart
Future<void> _encryptAndSend({
  required int recipientId,
  required String content,
  required String tempId,
  int? effectiveExpiresIn,
  int? effectiveReplyToId,
})
```

New signature adds:
```dart
  String messageType = 'TEXT',
  String? mediaUrl,
  int? mediaDuration,
```

Flow:
1. If TEXT: fetch link preview (web: backend proxy, native: direct)
2. Build envelope with all fields
3. Encrypt via Signal
4. Store all fields in `_pendingSendContent[tempId]`
5. Socket emit `sendMessage` with `encryptedContent` only

### 9. `retryFailedMessage` Updates

Current `retryFailedMessage` handles TEXT and VOICE. Must be extended for PING and IMAGE:

- **PING retry:** simple — call `_encryptAndSend` with `messageType: 'PING'`
- **IMAGE retry:** if Cloudinary URL already obtained (upload succeeded, socket failed), reuse URL and call `_encryptAndSend`. If upload also failed, re-upload first
- **VOICE retry:** same as image — check if `mediaUrl` is a Cloudinary URL or local path to decide whether to re-upload

### 10. Drawing Removal

**Delete:**
- `frontend/lib/screens/drawing_canvas_screen.dart` — entire file

**Remove from enums:**
- `MessageType.drawing` from `frontend/lib/models/message_model.dart`
- `MessageType.DRAWING` from `backend/src/messages/message.entity.ts`

**Remove references:**
- `chat_action_tiles.dart` — Draw tile and import
- `chat_message_bubble.dart` — `MessageType.drawing` checks
- `voice_message_bubble.dart` — `MessageType.drawing` check
- `chat_input_bar.dart` — `MessageType.drawing` check
- `chat_provider.dart` — any drawing references
- `message_model.dart` — fromJson case for 'DRAWING'
- `app_pl.arb` / `app_en.arb` — "drawings" in privacy description
- `message.mapper.ts` — DRAWING check (backend)

**No DB migration needed** — drawings were stored as IMAGE type.

### 11. Backward Compatibility

- Old unencrypted messages in DB retain their `messageType` and `mediaUrl` fields — render correctly
- Old encrypted text messages without `messageType` in envelope → `parse()` defaults to `TEXT`
- New encrypted messages: server stores as TEXT with null mediaUrl — recipient decrypts to get real type
- Conversation list: all encrypted messages show "Encrypted message" (including voice/image/ping) — acceptable, consistent behavior
- Reply-to preview on server: `MessageMapper` already shows "Encrypted message" when `encryptedContent` is set (line 38), so reply previews for encrypted non-text messages work correctly

### 12. Testing

**Backend:**
- Update existing `chat-message.service.spec.ts` — remove sendPing tests, add encrypted message handling tests
- Add `upload-media` endpoint tests in `messages.controller.spec.ts`
- Update `link-preview.service.spec.ts` if needed

**Frontend:**
- Update `e2e_envelope_test.dart` — test new fields (messageType, mediaUrl, mediaDuration), backward compat (missing messageType defaults to TEXT)
- Update existing tests that reference drawing or sendPing

### 13. Files Changed

**Backend:**
- `messages/messages.controller.ts` — new `upload-media` endpoint, remove `image` and `voice` endpoints
- `messages/messages.module.ts` — update dependencies
- `messages/message.entity.ts` — remove DRAWING from enum
- `messages/message.mapper.ts` — remove DRAWING reference
- `messages/dto/upload-image.dto.ts` — delete
- `messages/dto/upload-voice.dto.ts` — delete
- `messages/dto/upload-media.dto.ts` — new file
- `chat/chat.gateway.ts` — remove `sendPing` handler
- `chat/services/chat-message.service.ts` — remove `handleSendPing()`, update `handleSendMessage()` for encrypted-only media

**Frontend:**
- `utils/e2e_envelope.dart` — extended build/parse
- `models/message_model.dart` — add `messageType` to `copyWith()`, remove `MessageType.drawing`
- `providers/chat_provider.dart` — refactored sendPing, sendVoiceMessage, sendImageMessage to use _encryptAndSend; extended _pendingSendContent type to `Map<String, Map<String, dynamic>>`; extended _addMessageToState, _persistDecryptedContent, _decryptMessageHistory restore paths; updated retryFailedMessage
- `services/socket_service.dart` — remove sendPing, onPingSent/onPingReceived callbacks from connect()
- `services/api_service.dart` — new uploadMedia method, remove uploadImageMessage and uploadVoiceMessage
- `screens/drawing_canvas_screen.dart` — delete
- `widgets/chat_action_tiles.dart` — remove Draw tile
- `widgets/chat_message_bubble.dart` — remove drawing references
- `widgets/voice_message_bubble.dart` — remove drawing reference
- `widgets/chat_input_bar.dart` — remove drawing reference
- `l10n/app_pl.arb`, `l10n/app_en.arb` — remove "drawings"
- `CLAUDE.md` — update documentation

## Non-Goals

- Encrypting the media file itself (only URL encrypted — Cloudinary stores plaintext file)
- Multi-device support
- Media key rotation
- Encrypting message metadata (who, when, delivery status)
