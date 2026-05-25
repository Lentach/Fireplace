# E2E Encryption for All Message Types + Drawing Removal — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Encrypt ping, voice, and image messages with Signal Protocol (same as text), remove drawing feature entirely.

**Architecture:** All message types go through a unified E2E envelope encrypted via Signal Protocol. Server becomes blind to message type, media URLs, and metadata. New `POST /messages/upload-media` endpoint replaces separate image/voice endpoints (upload-only, no DB message creation). Ping loses its dedicated WebSocket event and goes through `sendMessage`.

**Tech Stack:** NestJS 11, Flutter 3.x, Signal Protocol (libsignal_protocol_dart), Cloudinary, Socket.IO 4

**Spec:** `docs/superpowers/specs/2026-03-15-e2e-all-message-types-design.md`

---

## Chunk 1: Drawing Removal + Envelope Extension + Model Changes

### Task 1: Remove Drawing from backend

**Files:**
- Modify: `backend/src/messages/message.entity.ts:19-25` — remove DRAWING from enum
- Modify: `backend/src/messages/message.mapper.ts:44` — remove DRAWING check
- Test: `backend/src/messages/message.mapper.spec.ts`

- [ ] **Step 1: Remove `DRAWING` from `MessageType` enum**

In `backend/src/messages/message.entity.ts`, remove the `DRAWING = 'DRAWING',` line from the enum (line 23).

- [ ] **Step 2: Remove DRAWING reference from MessageMapper**

In `backend/src/messages/message.mapper.ts:44`, change:
```typescript
: rt.messageType === 'IMAGE' || rt.messageType === 'DRAWING'
```
to:
```typescript
: rt.messageType === 'IMAGE'
```

- [ ] **Step 3: Run backend tests**

Run: `cd backend && npm test`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add backend/src/messages/message.entity.ts backend/src/messages/message.mapper.ts
git commit -m "refactor: remove DRAWING from backend MessageType enum"
```

---

### Task 2: Remove Drawing from frontend

**Files:**
- Delete: `frontend/lib/screens/drawing_canvas_screen.dart`
- Modify: `frontend/lib/models/message_model.dart:9-15` — remove drawing from enum
- Modify: `frontend/lib/models/message_model.dart:154-167` — remove DRAWING fromJson case
- Modify: `frontend/lib/widgets/chat_action_tiles.dart:9,66-71` — remove Draw tile + import
- Modify: `frontend/lib/widgets/chat_message_bubble.dart:82,108,152-153` — remove drawing checks
- Modify: `frontend/lib/widgets/voice_message_bubble.dart:280` — remove drawing check
- Modify: `frontend/lib/widgets/chat_input_bar.dart:407-409` — remove drawing check
- Modify: `frontend/lib/l10n/app_pl.arb` — remove "drawings" references if any
- Modify: `frontend/lib/l10n/app_en.arb` — remove "drawings" references if any

- [ ] **Step 1: Delete `drawing_canvas_screen.dart`**

Delete the file `frontend/lib/screens/drawing_canvas_screen.dart`.

- [ ] **Step 2: Remove `drawing` from frontend `MessageType` enum**

In `frontend/lib/models/message_model.dart`, remove `drawing,` from the enum (line 13) and remove the `case 'DRAWING': return MessageType.drawing;` case from `_parseMessageType`.

- [ ] **Step 3: Remove Draw tile from `chat_action_tiles.dart`**

Remove the import `import '../screens/drawing_canvas_screen.dart';` (line 9) and the Draw `_ActionTile` block (lines 66-71). Also remove the `_openDrawing` method if it exists.

- [ ] **Step 4: Remove `MessageType.drawing` from widget files**

In `chat_message_bubble.dart`: remove `MessageType.drawing` from all conditions (lines 82, 108, 152-153) — keep only `MessageType.image`.

In `voice_message_bubble.dart`: remove `MessageType.drawing` from condition (line 280) — keep only `MessageType.image`.

In `chat_input_bar.dart`: remove `MessageType.drawing` from condition (lines 407-409) — keep only `MessageType.image`.

- [ ] **Step 5: Update l10n files if "drawings" text exists**

Check `app_pl.arb` and `app_en.arb` for any text mentioning "drawings" or "rysunki" and remove those references.

- [ ] **Step 6: Run flutter analyze + tests**

Run: `cd frontend && flutter analyze && flutter test`
Expected: No new errors, all tests pass.

- [ ] **Step 7: Commit**

```bash
git add -A frontend/lib/screens/drawing_canvas_screen.dart frontend/lib/models/ frontend/lib/widgets/ frontend/lib/l10n/
git commit -m "refactor: remove drawing feature entirely (enum, screen, tiles, references)"
```

---

### Task 3: Extend E2E Envelope with messageType, mediaUrl, mediaDuration

**Files:**
- Modify: `frontend/lib/utils/e2e_envelope.dart`
- Test: `frontend/test/utils/e2e_envelope_test.dart`

- [ ] **Step 1: Update existing envelope tests + add new ones**

In `frontend/test/utils/e2e_envelope_test.dart`, add tests:

```dart
test('build includes messageType when provided', () {
  final envelope = E2eEnvelope.build('', messageType: 'PING');
  expect(envelope['messageType'], 'PING');
});

test('build includes mediaUrl and mediaDuration', () {
  final envelope = E2eEnvelope.build('', messageType: 'VOICE', mediaUrl: 'https://example.com/audio.m4a', mediaDuration: 5);
  expect(envelope['messageType'], 'VOICE');
  expect(envelope['mediaUrl'], 'https://example.com/audio.m4a');
  expect(envelope['mediaDuration'], 5);
});

test('parse returns messageType TEXT when absent (backward compat)', () {
  final json = '{"content":"hello"}';
  final parsed = E2eEnvelope.parse(json);
  expect(parsed.messageType, 'TEXT');
});

test('parse extracts messageType, mediaUrl, mediaDuration', () {
  final json = '{"content":"","messageType":"VOICE","mediaUrl":"https://example.com/a.m4a","mediaDuration":10}';
  final parsed = E2eEnvelope.parse(json);
  expect(parsed.messageType, 'VOICE');
  expect(parsed.mediaUrl, 'https://example.com/a.m4a');
  expect(parsed.mediaDuration, 10);
});

test('build then parse round-trip with all fields', () {
  final envelope = E2eEnvelope.build('hello', messageType: 'IMAGE', mediaUrl: 'https://img.com/1.jpg');
  final json = jsonEncode(envelope);
  final parsed = E2eEnvelope.parse(json);
  expect(parsed.content, 'hello');
  expect(parsed.messageType, 'IMAGE');
  expect(parsed.mediaUrl, 'https://img.com/1.jpg');
  expect(parsed.mediaDuration, isNull);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd frontend && flutter test test/utils/e2e_envelope_test.dart`
Expected: New tests FAIL (build/parse don't support new fields yet).

- [ ] **Step 3: Extend `E2eEnvelope.build()` and `parse()`**

In `frontend/lib/utils/e2e_envelope.dart`:

```dart
class E2eEnvelope {
  E2eEnvelope._();

  static const String _keyContent = 'content';
  static const String _keyMessageType = 'messageType';
  static const String _keyMediaUrl = 'mediaUrl';
  static const String _keyMediaDuration = 'mediaDuration';
  static const String _keyLinkPreview = 'linkPreview';
  static const String _keyUrl = 'url';
  static const String _keyTitle = 'title';
  static const String _keyImageUrl = 'imageUrl';

  static Map<String, dynamic> build(
    String content, {
    String messageType = 'TEXT',
    String? mediaUrl,
    int? mediaDuration,
    Map<String, String?>? linkPreview,
  }) {
    final envelope = <String, dynamic>{_keyContent: content};
    if (messageType != 'TEXT') envelope[_keyMessageType] = messageType;
    if (mediaUrl != null) envelope[_keyMediaUrl] = mediaUrl;
    if (mediaDuration != null) envelope[_keyMediaDuration] = mediaDuration;
    if (linkPreview != null) envelope[_keyLinkPreview] = linkPreview;
    return envelope;
  }

  static ({
    String content,
    String messageType,
    String? mediaUrl,
    int? mediaDuration,
    String? linkPreviewUrl,
    String? linkPreviewTitle,
    String? linkPreviewImageUrl,
  }) parse(String jsonStr) {
    final envelope = jsonDecode(jsonStr) as Map<String, dynamic>;
    final content = envelope[_keyContent] as String? ?? '';
    final messageType = envelope[_keyMessageType] as String? ?? 'TEXT';
    final mediaUrl = envelope[_keyMediaUrl] as String?;
    final mediaDuration = envelope[_keyMediaDuration] as int?;
    final lp = envelope[_keyLinkPreview] as Map<String, dynamic>?;
    return (
      content: content,
      messageType: messageType,
      mediaUrl: mediaUrl,
      mediaDuration: mediaDuration,
      linkPreviewUrl: lp?[_keyUrl] as String?,
      linkPreviewTitle: lp?[_keyTitle] as String?,
      linkPreviewImageUrl: lp?[_keyImageUrl] as String?,
    );
  }
}
```

Note: `build()` signature changes from positional `linkPreview` parameter to named. All call sites must be updated.

- [ ] **Step 4: Update all `E2eEnvelope.build()` call sites**

In `frontend/lib/providers/chat_provider.dart`, find the call to `E2eEnvelope.build(content, linkPreview)` and change to `E2eEnvelope.build(content, linkPreview: linkPreview)`.

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd frontend && flutter test test/utils/e2e_envelope_test.dart`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add frontend/lib/utils/e2e_envelope.dart frontend/test/utils/e2e_envelope_test.dart frontend/lib/providers/chat_provider.dart
git commit -m "feat: extend E2eEnvelope with messageType, mediaUrl, mediaDuration"
```

---

### Task 4: Add `messageType` to `MessageModel.copyWith()`

**Files:**
- Modify: `frontend/lib/models/message_model.dart:169-204` — add messageType param

- [ ] **Step 1: Add `messageType` parameter to `copyWith`**

In `frontend/lib/models/message_model.dart`, add `MessageType? messageType,` to the `copyWith` method parameters and use it:

```dart
MessageModel copyWith({
  MessageType? messageType,  // ← ADD THIS
  String? content,
  // ... existing params ...
}) {
  return MessageModel(
    // ... existing fields ...
    messageType: messageType ?? this.messageType,  // ← CHANGE from this.messageType
    // ...
  );
}
```

- [ ] **Step 2: Run tests**

Run: `cd frontend && flutter test`
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/models/message_model.dart
git commit -m "feat: add messageType to MessageModel.copyWith()"
```

---

## Chunk 2: Backend Changes (upload-media endpoint, remove sendPing, remove old endpoints)

### Task 5: Create `POST /messages/upload-media` endpoint

**Files:**
- Create: `backend/src/messages/dto/upload-media.dto.ts`
- Modify: `backend/src/messages/messages.controller.ts` — add upload-media, remove image/voice
- Modify: `backend/src/messages/messages.module.ts` — update if needed
- Delete: `backend/src/messages/dto/upload-image.dto.ts`
- Delete: `backend/src/messages/dto/upload-voice.dto.ts`

- [ ] **Step 1: Create `upload-media.dto.ts`**

Create `backend/src/messages/dto/upload-media.dto.ts`:

```typescript
import { IsIn, IsNumber, IsOptional, IsPositive } from 'class-validator';
import { Transform } from 'class-transformer';

export class UploadMediaDto {
  @Transform(({ value }) => typeof value === 'string' ? value : String(value))
  @IsIn(['image', 'voice'])
  type: 'image' | 'voice';

  @Transform(({ value }) => (value != null ? parseInt(value, 10) : undefined))
  @IsOptional()
  @IsNumber()
  @IsPositive()
  duration?: number;

  @Transform(({ value }) => (value != null ? parseInt(value, 10) : undefined))
  @IsOptional()
  @IsNumber()
  @IsPositive()
  expiresIn?: number;
}
```

- [ ] **Step 2: Replace image/voice endpoints with upload-media**

In `backend/src/messages/messages.controller.ts`:

Remove the `uploadImageMessage` and `uploadVoiceMessage` methods entirely. Add:

```typescript
@Post('upload-media')
@UseGuards(JwtAuthGuard)
@Throttle({ default: { limit: 10, ttl: 60000 } })
@UseInterceptors(FileInterceptor('file', {
  limits: { fileSize: 10 * 1024 * 1024 }, // 10MB max (covers both image and voice)
}))
async uploadMedia(
  @UploadedFile() file: Express.Multer.File,
  @Body() body: Record<string, unknown>,
  @Request() req,
) {
  if (!file) {
    throw new BadRequestException('No file uploaded');
  }

  const dto = validateDto(UploadMediaDto, body);

  if (dto.type === 'image') {
    const allowedMimeTypes = ['image/jpeg', 'image/jpg', 'image/png'];
    if (!allowedMimeTypes.includes(file.mimetype)) {
      throw new BadRequestException('Only JPEG/PNG images are allowed');
    }
    if (file.size > 5 * 1024 * 1024) {
      throw new BadRequestException('Image size must not exceed 5 MB');
    }
    const result = await this.cloudinaryService.uploadImage(
      req.user.id,
      file.buffer,
      file.mimetype,
    );
    return { mediaUrl: result.secureUrl };
  }

  // voice
  const allowedAudioMimes = [
    'audio/aac', 'audio/mp4', 'audio/m4a', 'audio/mpeg',
    'audio/webm', 'audio/wav', 'audio/wave', 'audio/x-wav',
  ];
  if (!allowedAudioMimes.includes(file.mimetype)) {
    throw new BadRequestException('Invalid audio format');
  }
  const result = await this.cloudinaryService.uploadVoiceMessage(
    req.user.id,
    file.buffer,
    file.mimetype,
    dto.expiresIn,
  );
  return {
    mediaUrl: result.secureUrl,
    mediaDuration: result.duration || dto.duration,
  };
}
```

Also update imports: replace `UploadImageDto` and `UploadVoiceDto` with `UploadMediaDto`. Remove unused imports (`ConversationsService`, `UsersService`, `ChatValidationService`, `MessageType`, `MessageMapper` — if no longer used by any remaining method). Keep `LinkPreviewService` import for the link-preview endpoint.

Remove `conversationsService`, `usersService`, `chatValidationService` from the constructor if no remaining method uses them. Update `messages.module.ts` imports accordingly (remove `ConversationsModule`, `UsersModule`, `ChatValidationModule` if no longer needed).

- [ ] **Step 3: Delete old DTOs**

Delete `backend/src/messages/dto/upload-image.dto.ts` and `backend/src/messages/dto/upload-voice.dto.ts`.

- [ ] **Step 4: Run backend tests**

Run: `cd backend && npm test`
Expected: All pass (existing controller tests may need updating if they test image/voice endpoints).

- [ ] **Step 5: Commit**

```bash
git add backend/src/messages/
git commit -m "feat: replace image/voice endpoints with unified upload-media"
```

---

### Task 6: Remove sendPing from backend

**Files:**
- Modify: `backend/src/chat/chat.gateway.ts:139-151` — remove sendPing handler
- Modify: `backend/src/chat/services/chat-message.service.ts:213-282` — remove handleSendPing
- Delete: `backend/src/chat/dto/send-ping.dto.ts`
- Test: `backend/src/chat/services/chat-message.service.spec.ts`

- [ ] **Step 1: Remove `@SubscribeMessage('sendPing')` handler from gateway**

In `backend/src/chat/chat.gateway.ts`, remove the entire `handleSendPing` method (lines 139-151).

- [ ] **Step 2: Remove `handleSendPing` from `ChatMessageService`**

In `backend/src/chat/services/chat-message.service.ts`, remove the entire `handleSendPing` method (lines 213-282).

- [ ] **Step 3: Delete `send-ping.dto.ts`**

Delete `backend/src/chat/dto/send-ping.dto.ts`.

- [ ] **Step 4: Remove sendPing imports**

Remove `SendPingDto` import from `chat-message.service.ts` if present. Remove any unused imports from the gateway.

- [ ] **Step 5: Update tests**

In `backend/src/chat/services/chat-message.service.spec.ts`, remove any tests for `handleSendPing`.

- [ ] **Step 6: Run backend tests**

Run: `cd backend && npm test`
Expected: All pass.

- [ ] **Step 7: Commit**

```bash
git add backend/src/chat/
git commit -m "refactor: remove sendPing WebSocket event (ping now goes through sendMessage)"
```

---

## Chunk 3: Frontend — Remove ping socket events, update ApiService

### Task 7: Remove ping events from SocketService and ChatProvider

**Files:**
- Modify: `frontend/lib/services/socket_service.dart:33-34,87-88,169-173` — remove ping callbacks and sendPing
- Modify: `frontend/lib/providers/chat_provider.dart:620-621,1288-1315` — remove ping handler and callback wiring

- [ ] **Step 1: Remove ping from `SocketService`**

In `frontend/lib/services/socket_service.dart`:

1. Remove `required void Function(dynamic) onPingReceived,` (line 33) and `required void Function(dynamic) onPingSent,` (line 34) from `connect()` parameters.
2. Remove `_socket!.on('newPing', onPingReceived);` (line 87) and `_socket!.on('pingSent', onPingSent);` (line 88).
3. Remove the `sendPing` method (lines 169-173).

- [ ] **Step 2: Remove ping wiring from `ChatProvider.connect()`**

In `frontend/lib/providers/chat_provider.dart`:

1. Remove `onPingReceived: _handlePingReceived,` (line 620) and `onPingSent: _handlePingReceived,` (line 621) from the `_socketService.connect()` call.
2. Remove the entire `_handlePingReceived` method (lines 1288-1315).

- [ ] **Step 3: Run flutter analyze + tests**

Run: `cd frontend && flutter analyze && flutter test`
Expected: No errors, all tests pass.

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/services/socket_service.dart frontend/lib/providers/chat_provider.dart
git commit -m "refactor: remove ping-specific socket events from frontend"
```

---

### Task 8: Replace uploadImageMessage/uploadVoiceMessage with uploadMedia in ApiService

**Files:**
- Modify: `frontend/lib/services/api_service.dart` — replace two methods with one

- [ ] **Step 1: Replace both upload methods with `uploadMedia`**

In `frontend/lib/services/api_service.dart`, remove `uploadImageMessage` (lines 160-208) and `uploadVoiceMessage` (lines 249-end). Replace with:

```dart
/// Upload media (image or voice) to backend. Returns {mediaUrl, mediaDuration?}.
Future<Map<String, dynamic>> uploadMedia({
  required String token,
  required String type, // 'image' or 'voice'
  int? duration,
  int? expiresIn,
  XFile? imageFile,
  String? audioPath,
  List<int>? audioBytes,
}) async {
  final request = http.MultipartRequest(
    'POST',
    Uri.parse('$baseUrl/messages/upload-media'),
  );
  request.headers['Authorization'] = 'Bearer $token';
  request.fields['type'] = type;
  if (duration != null) request.fields['duration'] = duration.toString();
  if (expiresIn != null) request.fields['expiresIn'] = expiresIn.toString();

  if (type == 'image' && imageFile != null) {
    if (kIsWeb) {
      final bytes = await imageFile.readAsBytes();
      final extension = imageFile.name.toLowerCase().split('.').last;
      final mimeType = extension == 'png' ? 'image/png' : 'image/jpeg';
      request.files.add(http.MultipartFile.fromBytes(
        'file', bytes,
        filename: imageFile.name,
        contentType: MediaType.parse(mimeType),
      ));
    } else {
      request.files.add(await http.MultipartFile.fromPath('file', imageFile.path));
    }
  } else if (type == 'voice') {
    List<int> bytes;
    if (audioBytes != null) {
      bytes = audioBytes;
    } else if (audioPath != null) {
      final file = File(audioPath);
      if (!await file.exists()) throw Exception('Audio file not found: $audioPath');
      bytes = await file.readAsBytes();
    } else {
      throw Exception('Either audioPath or audioBytes required for voice upload');
    }
    final isWeb = audioBytes != null;
    final ext = isWeb ? 'wav' : 'm4a';
    final mime = isWeb ? 'wav' : 'm4a';
    request.files.add(http.MultipartFile.fromBytes(
      'file', bytes,
      filename: 'voice_${DateTime.now().millisecondsSinceEpoch}.$ext',
      contentType: MediaType('audio', mime),
    ));
  }

  final streamedResponse = await request.send();
  final response = await http.Response.fromStream(streamedResponse);
  final data = jsonDecode(response.body) as Map<String, dynamic>;
  if (response.statusCode != 200 && response.statusCode != 201) {
    throw Exception(data['message'] ?? 'Upload failed');
  }
  return data;
}
```

Also remove the `VoiceUploadResult` class (no longer needed — `uploadMedia` returns raw map).

**Important:** Keep the old `uploadImageMessage` and `uploadVoiceMessage` methods temporarily (mark with `@Deprecated`) until Tasks 11 and 12 update the call sites. Remove them after those tasks.

- [ ] **Step 2: Run flutter analyze**

Run: `cd frontend && flutter analyze`
Expected: No new errors (old methods still exist as deprecated).

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/services/api_service.dart
git commit -m "feat: add unified uploadMedia method to ApiService"
```

---

## Chunk 4: Frontend — Encrypt all message types

### Task 9: Refactor `_encryptAndSend` to support all types

**Files:**
- Modify: `frontend/lib/providers/chat_provider.dart` — extend _encryptAndSend signature and _pendingSendContent type

- [ ] **Step 1: Change `_pendingSendContent` type to `Map<String, dynamic>`**

In `frontend/lib/providers/chat_provider.dart`, change the `_pendingSendContent` declaration:

```dart
final Map<String, Map<String, dynamic>> _pendingSendContent = {};
```

Also update the existing `sendMessage()` method (line 775) map literal to match:
```dart
_pendingSendContent[tempId] = <String, dynamic>{'content': content};
```

- [ ] **Step 2: Extend `_encryptAndSend` signature**

Add new parameters to `_encryptAndSend`:

```dart
Future<void> _encryptAndSend({
  required int recipientId,
  required String content,
  required String tempId,
  int? effectiveExpiresIn,
  int? effectiveReplyToId,
  String messageType = 'TEXT',   // ← NEW
  String? mediaUrl,              // ← NEW
  int? mediaDuration,            // ← NEW
}) async {
```

- [ ] **Step 3: Update `_encryptAndSend` body**

1. Only fetch link preview for TEXT type:
```dart
Map<String, String?>? linkPreview;
if (messageType == 'TEXT') {
  try {
    if (kIsWeb && _reconnect.tokenForReconnect != null) {
      linkPreview = await _api.fetchLinkPreview(_reconnect.tokenForReconnect!, content);
    } else {
      linkPreview = await LinkPreviewService.fetchPreview(content);
    }
  } catch (e) {
    debugPrint('[E2E] Link preview fetch failed (non-fatal): $e');
  }
}
```

2. Store all fields in `_pendingSendContent`:
```dart
final pending = _pendingSendContent[tempId];
if (pending != null) {
  pending['messageType'] = messageType;
  if (mediaUrl != null) pending['mediaUrl'] = mediaUrl;
  if (mediaDuration != null) pending['mediaDuration'] = mediaDuration;
  if (linkPreview != null) {
    if (linkPreview['url'] != null) pending['linkPreviewUrl'] = linkPreview['url'];
    if (linkPreview['title'] != null) pending['linkPreviewTitle'] = linkPreview['title'];
    if (linkPreview['imageUrl'] != null) pending['linkPreviewImageUrl'] = linkPreview['imageUrl'];
  }
}
```

3. Build envelope with all fields:
```dart
final envelopeJson = jsonEncode(E2eEnvelope.build(
  content,
  messageType: messageType,
  mediaUrl: mediaUrl,
  mediaDuration: mediaDuration,
  linkPreview: linkPreview,
));
```

- [ ] **Step 4: Update `_addMessageToState` to restore all fields**

Extend the existing block that restores content + link preview to also restore `messageType`, `mediaUrl`, `mediaDuration`:

```dart
if (msg.content == '[encrypted]' && plaintextContent.isNotEmpty) {
  final restoredType = savedData?['messageType'] as String?;
  msg = msg.copyWith(
    content: plaintextContent,
    messageType: restoredType != null ? _parseMessageTypeString(restoredType) : null,
    mediaUrl: savedData?['mediaUrl'] as String?,
    mediaDuration: savedData?['mediaDuration'] as int?,
    linkPreviewUrl: savedData?['linkPreviewUrl'] as String?,
    linkPreviewTitle: savedData?['linkPreviewTitle'] as String?,
    linkPreviewImageUrl: savedData?['linkPreviewImageUrl'] as String?,
  );
```

Add a helper method:
```dart
MessageType? _parseMessageTypeString(String? type) {
  switch (type) {
    case 'TEXT': return MessageType.text;
    case 'PING': return MessageType.ping;
    case 'VOICE': return MessageType.voice;
    case 'IMAGE': return MessageType.image;
    default: return null;
  }
}
```

Also update `_persistDecryptedContent` to include `messageType`, `mediaUrl`, `mediaDuration`.

- [ ] **Step 5: Update `_decryptMessageAsync` to restore messageType + media**

In the decrypt success path, after `E2eEnvelope.parse(plaintext)`:

```dart
final parsedType = _parseMessageTypeString(parsed.messageType);
final decryptedMsg = msg.copyWith(
  content: parsed.content,
  messageType: parsedType,
  mediaUrl: parsed.mediaUrl,
  mediaDuration: parsed.mediaDuration,
  linkPreviewUrl: parsed.linkPreviewUrl,
  // ... existing link preview fields
);
```

Also update the persisted cache restore path and own-message recovery path in `_decryptMessageHistory` to restore `messageType`, `mediaUrl`, `mediaDuration`.

- [ ] **Step 5b: Set ping effect for recipient after decryption**

In `_decryptMessageAsync`, after successfully decrypting a message, check if the decrypted type is PING and set `_showPingEffect = true`. Since decryption is async, this must happen inside the decrypt success path:

```dart
if (parsedType == MessageType.ping && msg.senderId != _currentUserId) {
  _showPingEffect = true;
}
```

This replaces the old `_handlePingReceived` which set `_showPingEffect = true` synchronously. Without this, the recipient would not see the ping animation.

- [ ] **Step 6: Run flutter analyze**

Run: `cd frontend && flutter analyze`
Expected: No new errors (some call-site errors expected until Tasks 10-12 are done).

- [ ] **Step 7: Commit**

```bash
git add frontend/lib/providers/chat_provider.dart
git commit -m "feat: extend _encryptAndSend and restore paths for all message types"
```

---

### Task 10: Encrypt ping messages

**Files:**
- Modify: `frontend/lib/providers/chat_provider.dart` — rewrite sendPing

- [ ] **Step 1: Rewrite `sendPing`**

Replace the current `sendPing` method (lines 975-977) with:

```dart
void sendPing(int recipientId) {
  if (_activeConversationId == null || _currentUserId == null) return;

  final effectiveExpiresIn = conversationDisappearingTimer;
  final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}_$_currentUserId';

  final tempMessage = MessageModel(
    id: -(++ChatProvider._tempIdSeq),
    content: '',
    senderId: _currentUserId!,
    senderUsername: '',
    conversationId: _activeConversationId!,
    createdAt: DateTime.now(),
    deliveryStatus: MessageDeliveryStatus.sending,
    messageType: MessageType.ping,
    expiresAt: effectiveExpiresIn != null
        ? DateTime.now().add(Duration(seconds: effectiveExpiresIn))
        : null,
    tempId: tempId,
  );

  _messages.add(tempMessage);
  _pendingSendContent[tempId] = <String, dynamic>{'content': '', 'messageType': 'PING'};
  _showPingEffect = true;
  notifyListeners();

  _encryptAndSend(
    recipientId: recipientId,
    content: '',
    tempId: tempId,
    effectiveExpiresIn: effectiveExpiresIn,
    messageType: 'PING',
  );
}
```

- [ ] **Step 2: Run flutter analyze + tests**

Run: `cd frontend && flutter analyze && flutter test`
Expected: Pass.

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/providers/chat_provider.dart
git commit -m "feat: encrypt ping messages through unified sendMessage flow"
```

---

### Task 11: Encrypt voice messages

**Files:**
- Modify: `frontend/lib/providers/chat_provider.dart` — rewrite sendVoiceMessage + retryVoiceMessage

- [ ] **Step 1: Rewrite `sendVoiceMessage` to use uploadMedia + _encryptAndSend**

The method keeps the same optimistic message creation, but after getting the Cloudinary URL, calls `_encryptAndSend` instead of direct socket emit.

**Behavioral change:** Voice messages will stay at `SENDING` status until the server confirms `messageSent` (consistent with text messages). Previously, status was set to `SENT` immediately after socket emit.

Full changes:
1. Replace `_api.uploadVoiceMessage(...)` with `_api.uploadMedia(token: ..., type: 'voice', duration: ..., audioPath: ..., audioBytes: ..., expiresIn: ...)`
2. Remove the direct `_socketService.sendMessage(...)` call (lines 1057-1065)
3. Remove the premature `deliveryStatus: MessageDeliveryStatus.sent` update
4. Add `_pendingSendContent[tempId] = <String, dynamic>{'content': '', 'messageType': 'VOICE'};` after creating optimistic message
5. After upload success, call `_encryptAndSend` with mediaUrl + mediaDuration

Key changes in the upload success handler:
```dart
// After successful upload:
final mediaUrl = responseData['mediaUrl'] as String;
final mediaDuration = (responseData['mediaDuration'] as num?)?.toInt() ?? duration;

// Update optimistic message with Cloudinary URL
final idx = _messages.indexWhere((m) => m.tempId == tempId);
if (idx != -1) {
  _messages[idx] = _messages[idx].copyWith(mediaUrl: mediaUrl, mediaDuration: mediaDuration);
  notifyListeners();
}

// Encrypt and send via WebSocket (URL hidden in envelope)
_encryptAndSend(
  recipientId: recipientId,
  content: '',
  tempId: tempId,
  effectiveExpiresIn: effectiveExpiresIn,
  messageType: 'VOICE',
  mediaUrl: mediaUrl,
  mediaDuration: mediaDuration,
);
```

Replace `_api.uploadVoiceMessage(...)` with `_api.uploadMedia(token: ..., type: 'voice', ...)`.

- [ ] **Step 2: Update `retryVoiceMessage` to use uploadMedia + _encryptAndSend**

Same pattern: if mediaUrl is already a Cloudinary URL, skip re-upload and just call `_encryptAndSend`. Otherwise re-upload first.

- [ ] **Step 3: Run flutter analyze + tests**

Run: `cd frontend && flutter analyze && flutter test`
Expected: Pass.

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/providers/chat_provider.dart
git commit -m "feat: encrypt voice messages (URL in E2E envelope)"
```

---

### Task 12: Encrypt image messages

**Files:**
- Modify: `frontend/lib/providers/chat_provider.dart` — rewrite sendImageMessage
- Modify: `frontend/lib/widgets/chat_action_tiles.dart` — update image send call

- [ ] **Step 1: Rewrite `sendImageMessage`**

Replace the current `sendImageMessage` (lines 1170-1201) with optimistic message + upload + _encryptAndSend:

```dart
Future<void> sendImageMessage(
  String token,
  XFile imageFile,
  int recipientId,
) async {
  if (_activeConversationId == null || _currentUserId == null) return;

  final effectiveExpiresIn = conversationDisappearingTimer;
  final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}_$_currentUserId';

  // Create optimistic message
  final tempMessage = MessageModel(
    id: -(++ChatProvider._tempIdSeq),
    content: '',
    senderId: _currentUserId!,
    senderUsername: '',
    conversationId: _activeConversationId!,
    createdAt: DateTime.now(),
    deliveryStatus: MessageDeliveryStatus.sending,
    messageType: MessageType.image,
    expiresAt: effectiveExpiresIn != null
        ? DateTime.now().add(Duration(seconds: effectiveExpiresIn))
        : null,
    tempId: tempId,
  );

  _messages.add(tempMessage);
  _pendingSendContent[tempId] = <String, dynamic>{'content': '', 'messageType': 'IMAGE'};
  notifyListeners();

  try {
    // Upload to Cloudinary (no message created in DB)
    final responseData = await _api.uploadMedia(
      token: token,
      type: 'image',
      imageFile: imageFile,
      expiresIn: effectiveExpiresIn,
    );

    final mediaUrl = responseData['mediaUrl'] as String;

    // Update optimistic message with URL
    final idx = _messages.indexWhere((m) => m.tempId == tempId);
    if (idx != -1) {
      _messages[idx] = _messages[idx].copyWith(mediaUrl: mediaUrl);
      notifyListeners();
    }

    // Encrypt and send
    _encryptAndSend(
      recipientId: recipientId,
      content: '',
      tempId: tempId,
      effectiveExpiresIn: effectiveExpiresIn,
      messageType: 'IMAGE',
      mediaUrl: mediaUrl,
    );
  } catch (e) {
    debugPrint('[ChatProvider] Image upload failed: $e');
    _markMessageFailed(tempId, 'Image upload failed: ${e.toString()}');
  }
}
```

- [ ] **Step 2: Update `chat_action_tiles.dart` call site if needed**

Check how `sendImageMessage` is called from action tiles and ensure the call matches the new signature.

- [ ] **Step 3: Update `retryFailedMessage` for image and ping**

Extend `retryFailedMessage` to handle `MessageType.image` and `MessageType.ping`:

```dart
if (message.messageType == MessageType.ping) {
  _messages[index] = _messages[index].copyWith(
    deliveryStatus: MessageDeliveryStatus.sending,
  );
  notifyListeners();
  final conv = _conversations.firstWhere((c) => c.id == message.conversationId);
  final recipientId = conv_helpers.getOtherUserId(conv, _currentUserId);
  _encryptAndSend(
    recipientId: recipientId,
    content: '',
    tempId: tempId,
    messageType: 'PING',
  );
  return;
}
if (message.messageType == MessageType.image) {
  // If mediaUrl is already a Cloudinary URL, just re-encrypt and send
  if (message.mediaUrl != null && message.mediaUrl!.contains('cloudinary')) {
    _messages[index] = _messages[index].copyWith(
      deliveryStatus: MessageDeliveryStatus.sending,
    );
    notifyListeners();
    final conv = _conversations.firstWhere((c) => c.id == message.conversationId);
    final recipientId = conv_helpers.getOtherUserId(conv, _currentUserId);
    _encryptAndSend(
      recipientId: recipientId,
      content: '',
      tempId: tempId,
      messageType: 'IMAGE',
      mediaUrl: message.mediaUrl,
    );
  }
  return;
}
```

- [ ] **Step 4: Delete deprecated methods from ApiService**

Remove `uploadImageMessage`, `uploadVoiceMessage`, and `VoiceUploadResult` class from `frontend/lib/services/api_service.dart` (marked `@Deprecated` in Task 8). All call sites now use `uploadMedia`.

- [ ] **Step 5: Run flutter analyze + tests**

Run: `cd frontend && flutter analyze && flutter test`
Expected: Pass.

- [ ] **Step 6: Commit**

```bash
git add frontend/lib/providers/chat_provider.dart frontend/lib/widgets/chat_action_tiles.dart frontend/lib/services/api_service.dart
git commit -m "feat: encrypt image messages (URL in E2E envelope)"
```

---

## Chunk 5: Final integration, persist/restore, tests, docs

### Task 13: Complete persist/restore paths for all types

**Files:**
- Modify: `frontend/lib/providers/chat_provider.dart` — _persistDecryptedContent, _decryptMessageHistory own-message path

- [ ] **Step 1: Update `_persistDecryptedContent` to save messageType + media fields**

Ensure the persist map includes:
```dart
final data = <String, dynamic>{
  'content': decrypted.content,
  if (decrypted.messageType != MessageType.text) 'messageType': decrypted.messageType.name.toUpperCase(),
  if (decrypted.mediaUrl != null) 'mediaUrl': decrypted.mediaUrl!,
  if (decrypted.mediaDuration != null) 'mediaDuration': decrypted.mediaDuration!,
  if (decrypted.linkPreviewUrl != null) 'linkPreviewUrl': decrypted.linkPreviewUrl!,
  // ... existing link preview fields
};
```

- [ ] **Step 2: Update own-message recovery in `_decryptMessageHistory`**

The block at ~line 1683 (`msg.senderId == _currentUserId && msg.content == '[encrypted]'`) must restore `messageType`, `mediaUrl`, `mediaDuration` from persisted cache:

```dart
final restoredType = _parseMessageTypeString(stored?['messageType'] as String?);
final restored = msg.copyWith(
  content: storedContent,
  messageType: restoredType,
  mediaUrl: stored?['mediaUrl'] as String?,
  mediaDuration: stored?['mediaDuration'] as int?,
  linkPreviewUrl: stored?['linkPreviewUrl'] as String?,
  linkPreviewTitle: stored?['linkPreviewTitle'] as String?,
  linkPreviewImageUrl: safeImageUrl,
);
```

- [ ] **Step 3: Run flutter analyze + tests**

Run: `cd frontend && flutter analyze && flutter test`
Expected: Pass.

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/providers/chat_provider.dart
git commit -m "feat: persist and restore messageType + media fields for E2E messages"
```

---

### Task 14: Run full test suites and fix any issues

**Files:**
- Test: `backend/` — all tests
- Test: `frontend/` — all tests

- [ ] **Step 1: Run backend tests**

Run: `cd backend && npm test`
Expected: All pass. Fix any failures.

- [ ] **Step 2: Run frontend tests**

Run: `cd frontend && flutter test`
Expected: All pass. Fix any failures.

- [ ] **Step 3: Run flutter analyze**

Run: `cd frontend && flutter analyze`
Expected: Only pre-existing info-level warnings.

- [ ] **Step 4: Manual smoke test**

Start backend + frontend:
```bash
# Terminal 1
docker-compose up
# Terminal 2
cd frontend && flutter run -d chrome
```

Test:
1. Send text message → encrypted, shows with link preview if URL
2. Send ping → encrypted, shows PING! bubble
3. Send voice → upload then encrypt, plays correctly for recipient
4. Send image → upload then encrypt, displays correctly for recipient
5. Re-login → all messages restore correctly (type, media, content)

- [ ] **Step 5: Commit any fixes**

```bash
git add -A
git commit -m "fix: address test and integration issues for E2E all-types"
```

---

### Task 15: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update all relevant sections**

Key changes:
1. **Section 1 (Critical Rules)**: Update E2E section — all types encrypted, remove drawing references
2. **Section 4 (Database)**: Note that messageType is TEXT for all encrypted messages
3. **Section 6 (WebSocket API)**: Remove sendPing/pingSent/newPing from table. Note ping goes through sendMessage
4. **Section 7 (REST API)**: Replace image/voice endpoints with upload-media. Update rate limits
5. **Section 8 (E2E Encryption)**: Update to reflect all types encrypted, envelope format, send flows
6. **Section 9 (Widgets)**: Remove DrawingCanvasScreen, update ChatActionTiles description
7. **Section 11 (Known Limitations)**: Update "E2E: text only" → "E2E: all types (text, ping, voice, image). Media files on Cloudinary are not encrypted, only URLs"
8. **File Location Map**: Remove drawing_canvas_screen, update DTO references

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for E2E all message types + drawing removal"
```
