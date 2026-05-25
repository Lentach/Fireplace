# Voice Messages Feature - Design Document

**Date:** 2026-02-15
**Status:** Approved
**Approach:** Optimistic UI + Background Upload

---

## Overview

Add voice messaging capability to MVP Chat App with full Telegram-like UX: hold mic button to record, swipe to cancel, instant message display, background upload to Cloudinary with auto-delete TTL, and rich playback UI with waveform visualization and speed control.

---

## Requirements

### Functional Requirements
- ✅ Hold mic button (bottom right, when text field empty) to record audio
- ✅ Max recording duration: 2 minutes
- ✅ Min recording duration: 1 second (< 1s = auto-cancel)
- ✅ Visual feedback: timer + waveform + swipe-to-cancel gesture
- ✅ Audio format: AAC/M4A (optimal compression, ~50KB/min)
- ✅ Optimistic UI: message appears instantly, upload in background
- ✅ Playback UI: play/pause, waveform with progress, scrub slider, speed toggle (1x/1.5x/2x)
- ✅ Platform support: Web + Mobile (Android/iOS)
- ✅ Disappearing messages: voice messages respect conversation timer
- ✅ Cloudinary auto-delete: TTL synchronized with disappearing timer (+1h buffer)
- ✅ Error handling: retry on upload failure, permission prompts, edge cases

### Non-Functional Requirements
- ✅ Instant feedback (< 100ms message display after recording)
- ✅ Background upload (non-blocking UI)
- ✅ Retry logic for failed uploads
- ✅ Cross-platform compatibility (web MediaRecorder API, mobile native recording)
- ✅ Audio caching (download once, cache locally for repeat playback)

---

## Architecture Overview

### High-Level Flow

```
User (hold mic)
    ↓
Frontend Recording (record package, AAC/M4A, temp file)
    ↓
Optimistic UI (show message bubble immediately, status: SENDING)
    ↓
Background Upload (POST /messages/voice → Cloudinary with TTL)
    ↓
WebSocket Send (emit sendMessage with VOICE type + Cloudinary URL)
    ↓
Recipient (receive newMessage, download & play on demand)
```

### Key Principles
- **Optimistic updates**: Message appears instantly (consistent with text messages)
- **Background upload**: Non-blocking, user can continue chatting
- **Cloudinary TTL**: Auto-delete files when message expires
- **Retry on failure**: Upload failures show retry button, local file cached
- **Min 1s recording**: Prevents accidental ultra-short taps

---

## Backend Components

### 1. Database Changes

**message.entity.ts:**
```typescript
export enum MessageType {
  TEXT = 'TEXT',
  PING = 'PING',
  IMAGE = 'IMAGE',
  DRAWING = 'DRAWING',
  VOICE = 'VOICE',  // ← NEW
}

// NEW FIELD:
@Column({ type: 'int', nullable: true })
mediaDuration: number | null;  // seconds, for playback UI
```

Existing fields used:
- `messageType: MessageType` - set to VOICE
- `mediaUrl: string | null` - Cloudinary URL
- `deliveryStatus: MessageDeliveryStatus` - SENDING → SENT → DELIVERED → READ
- `expiresAt: Date | null` - expiration timestamp (if disappearing timer active)

### 2. Cloudinary Service Enhancement

**cloudinary.service.ts - new method:**
```typescript
async uploadVoiceMessage(
  userId: number,
  buffer: Buffer,
  mimeType: string,
  expiresIn?: number,  // seconds until expiration (from disappearing timer)
): Promise<{ secureUrl: string; publicId: string; duration: number }> {
  const dataUri = `data:${mimeType};base64,${buffer.toString('base64')}`;

  const uploadOptions: any = {
    folder: 'voice-messages',
    public_id: `user-${userId}-${Date.now()}`,
    resource_type: 'video',  // Cloudinary uses 'video' for audio files
    format: 'm4a',  // force M4A/AAC format
  };

  // Set TTL if disappearing timer is active
  if (expiresIn) {
    // Add 1 hour buffer to allow for delivery/playback
    const ttlSeconds = expiresIn + 3600;
    uploadOptions.expires_at = Math.floor(Date.now() / 1000) + ttlSeconds;
  }

  const result = await cloudinary.uploader.upload(dataUri, uploadOptions);

  return {
    secureUrl: result.secure_url,
    publicId: result.public_id,
    duration: result.duration || 0,  // Cloudinary extracts audio duration
  };
}
```

**Future enhancement:** Generic `uploadMediaWithTTL()` method for all media types (voice, image, drawing) to avoid code duplication.

### 3. New REST Endpoint

**messages.controller.ts:**
```typescript
@Post('voice')
@UseGuards(JwtAuthGuard)
@UseInterceptors(FileInterceptor('audio', {
  limits: { fileSize: 10 * 1024 * 1024 },  // 10MB max (2min AAC ~1-2MB)
  fileFilter: (req, file, cb) => {
    const allowedMimes = [
      'audio/aac',
      'audio/mp4',
      'audio/m4a',
      'audio/mpeg',
      'audio/webm',  // web MediaRecorder format
    ];
    if (!allowedMimes.includes(file.mimetype)) {
      return cb(new BadRequestException('Invalid audio format'), false);
    }
    cb(null, true);
  },
}))
async uploadVoiceMessage(
  @UploadedFile() file: Express.Multer.File,
  @Body('duration') duration: string,  // client-measured duration (seconds)
  @Body('expiresIn') expiresIn?: string,  // optional disappearing timer
  @Request() req,
) {
  const userId = req.user.id;
  const durationNum = parseInt(duration, 10);
  const expiresInNum = expiresIn ? parseInt(expiresIn, 10) : undefined;

  const result = await this.cloudinaryService.uploadVoiceMessage(
    userId,
    file.buffer,
    file.mimetype,
    expiresInNum,
  );

  return {
    mediaUrl: result.secureUrl,
    publicId: result.publicId,
    duration: result.duration || durationNum,  // prefer Cloudinary's extracted duration
  };
}
```

### 4. WebSocket Integration

**Option A (Recommended):** Reuse existing `sendMessage` event with `messageType: 'VOICE'` parameter.

**Option B:** Create new `sendVoiceMessage` event (similar to `sendPing`).

**Recommendation:** Use Option A to avoid event proliferation. The existing `sendMessage` handler in `chat-message.service.ts` already supports `messageType` field.

**No backend changes needed** - existing WebSocket flow works:
1. Frontend emits `sendMessage` with `{ messageType: 'VOICE', mediaUrl, mediaDuration, ... }`
2. Backend creates Message entity with VOICE type
3. Backend emits `messageSent` (to sender) + `newMessage` (to recipient)

---

## Frontend Components

### 1. New Dependencies

**pubspec.yaml:**
```yaml
dependencies:
  just_audio: ^0.9.36  # already exists - playback
  path_provider: ^2.1.1  # already exists - temp storage

  # NEW PACKAGES:
  record: ^5.0.0  # cross-platform audio recording (web + mobile)
  audio_waveforms: ^1.0.5  # waveform visualization
  permission_handler: ^11.0.0  # mic permissions (mobile)
```

### 2. Recording UI - Voice Recording Overlay

**New widget:** `lib/widgets/voice_recording_overlay.dart`

**Purpose:** Full-screen overlay displayed during recording with timer, waveform, and swipe-to-cancel gesture.

**Components:**
- Timer display (0:00 → 2:00)
- Waveform visualization (real-time, using audio_waveforms package)
- Swipe-to-cancel zone (red icon on left, drag left > 100px = cancel)
- Mic icon with pulsing animation
- Visual feedback when approaching 2min limit:
  - Yellow timer at 1:50
  - Red timer at 1:58
  - Auto-stop at 2:00

**Gesture handling:**
- `GestureDetector` with `onHorizontalDragUpdate`
- Drag left > 100px: trigger cancel animation + `onCancel()`
- Release: call `onSendVoice(audioPath, duration)` if duration >= 1s

**Signature:**
```dart
class VoiceRecordingOverlay extends StatefulWidget {
  final Function(String audioPath, int duration) onSendVoice;
  final VoidCallback onCancel;

  const VoiceRecordingOverlay({
    required this.onSendVoice,
    required this.onCancel,
  });
}
```

### 3. Message Bubble - Voice Playback UI

**Enhanced:** `lib/widgets/chat_message_bubble.dart` (add voice mode)

**Alternative:** New widget `lib/widgets/voice_message_bubble.dart` (cleaner separation)

**Components:**
- Play/Pause button (`IconButton` with `Icons.play_arrow` / `Icons.pause`)
- Waveform with progress (audio_waveforms, fills as playing)
- Duration label (e.g., "0:12 / 0:45")
- Playback speed toggle (1.0x / 1.5x / 2.0x) - circular button in top-right
- Slider for scrubbing (`Slider` widget)
- Delivery status icon (only for `isMine`, same as text messages)
- Timer countdown if `expiresAt` set (same as text messages)

**State management:**
- `AudioPlayer` from just_audio package (singleton per conversation or per message?)
- `PlayerState` (playing, paused, stopped, loading)
- Current position / total duration (Stream from AudioPlayer)
- Current playback speed (1.0, 1.5, 2.0)
- Download state (not_downloaded, downloading, cached)

**Lazy loading:**
- Audio NOT downloaded on message receive
- Download starts on first play button tap
- Cache locally using `path_provider.getApplicationDocumentsDirectory()/audio_cache/`
- Reuse cached file for subsequent plays

### 4. Chat Input Bar Enhancement

**Modified:** `lib/widgets/chat_input_bar.dart`

**Mic button behavior:**
```dart
// Replace existing mic IconButton with GestureDetector
GestureDetector(
  onLongPressStart: (_) => _startRecording(),
  onLongPressEnd: (_) => _stopRecording(),
  onLongPressMoveUpdate: (details) => _checkCancelGesture(details),
  child: Icon(
    _isRecording ? Icons.mic : Icons.mic_none,
    color: _isRecording ? Colors.red : iconColor,
  ),
)

// Only active when text field is empty (existing logic)
// Visual states:
// - Normal: grey mic icon
// - Recording: red mic icon with pulsing animation
// - Sending: spinner icon
```

**New state variables:**
```dart
bool _isRecording = false;
bool _isSendingVoice = false;
String? _recordingPath;
Timer? _recordingTimer;
int _recordingDuration = 0;  // seconds
RecordController? _recordController;  // from audio_waveforms package
```

**New methods:**
```dart
Future<void> _startRecording() async {
  // 1. Check permission
  // 2. Initialize recorder (record package)
  // 3. Start recording to temp file
  // 4. Show VoiceRecordingOverlay
  // 5. Start timer (increment _recordingDuration every 1s)
  // 6. Auto-stop at 120s
}

Future<void> _stopRecording() async {
  // 1. Stop recorder
  // 2. Get file path + duration
  // 3. Hide overlay
  // 4. If duration < 1s: delete file, show toast
  // 5. Else: call _sendVoiceMessage()
}

Future<void> _cancelRecording() async {
  // 1. Stop recorder
  // 2. Delete temp file
  // 3. Hide overlay
  // 4. Reset state
}

Future<void> _sendVoiceMessage(String path, int duration) async {
  // 1. Set _isSendingVoice = true
  // 2. Call ChatProvider.sendVoiceMessage()
  // 3. Delete temp file after upload completes
  // 4. Reset state
}

void _checkCancelGesture(LongPressMoveUpdateDetails details) {
  // Track horizontal drag
  // If drag.dx < -100: trigger cancel animation
}
```

### 5. ChatProvider Enhancements

**Modified:** `lib/providers/chat_provider.dart`

**New method:**
```dart
Future<void> sendVoiceMessage({
  required int recipientId,
  required String localAudioPath,
  required int duration,
  int? conversationId,
}) async {
  // 1. Create optimistic message
  final tempId = DateTime.now().millisecondsSinceEpoch.toString();
  final expiresAt = _calculateExpiresAt(conversationId);

  final optimisticMessage = MessageModel(
    id: -1,  // placeholder, will be replaced by backend ID
    content: '',
    senderId: _currentUserId,
    senderEmail: _currentUserEmail,
    conversationId: conversationId ?? -1,
    createdAt: DateTime.now(),
    deliveryStatus: MessageDeliveryStatus.sending,
    messageType: MessageType.voice,
    mediaUrl: localAudioPath,  // local file path initially
    mediaDuration: duration,
    tempId: tempId,
    expiresAt: expiresAt,
  );

  // 2. Add to _messages immediately (optimistic)
  _messages.add(optimisticMessage);
  _updateLastMessage(conversationId, optimisticMessage);
  notifyListeners();

  // 3. Upload to backend in background
  try {
    final result = await _apiService.uploadVoiceMessage(
      audioPath: localAudioPath,
      duration: duration,
      expiresIn: _getConversationDisappearingTimer(conversationId),
    );

    // 4. Send via WebSocket with Cloudinary URL
    _socketService.sendMessage(
      recipientId: recipientId,
      content: '',
      messageType: 'VOICE',
      mediaUrl: result.mediaUrl,
      mediaDuration: result.duration,
      expiresIn: _getConversationDisappearingTimer(conversationId),
      tempId: tempId,
    );

    // 5. Update local message with Cloudinary URL
    final index = _messages.indexWhere((m) => m.tempId == tempId);
    if (index != -1) {
      _messages[index] = _messages[index].copyWith(
        mediaUrl: result.mediaUrl,
        mediaDuration: result.duration,
        deliveryStatus: MessageDeliveryStatus.sent,
      );
      notifyListeners();
    }

  } catch (e) {
    // 6. Mark as failed, keep local file for retry
    final index = _messages.indexWhere((m) => m.tempId == tempId);
    if (index != -1) {
      _messages[index] = _messages[index].copyWith(
        deliveryStatus: MessageDeliveryStatus.failed,
      );
      notifyListeners();
    }

    _errorMessage = 'Failed to send voice message';
    print('Voice upload error: $e');
  }
}

// Retry failed voice upload
Future<void> retryVoiceMessage(String tempId) async {
  final message = _messages.firstWhere((m) => m.tempId == tempId);
  if (message.messageType != MessageType.voice) return;

  // Re-upload using local file (still in mediaUrl if failed)
  await sendVoiceMessage(
    recipientId: /* extract from conversation */,
    localAudioPath: message.mediaUrl!,  // local path
    duration: message.mediaDuration ?? 0,
    conversationId: message.conversationId,
  );
}
```

**New enum value:**
```dart
enum MessageDeliveryStatus {
  sending,
  sent,
  delivered,
  read,
  failed,  // ← NEW: for upload failures
}
```

### 6. API Service Enhancement

**Modified:** `lib/services/api_service.dart`

**New method:**
```dart
Future<VoiceUploadResult> uploadVoiceMessage({
  required String audioPath,
  required int duration,
  int? expiresIn,
}) async {
  final file = File(audioPath);
  final bytes = await file.readAsBytes();

  final request = http.MultipartRequest(
    'POST',
    Uri.parse('$baseUrl/messages/voice'),
  );

  request.headers['Authorization'] = 'Bearer $_token';
  request.files.add(http.MultipartFile.fromBytes(
    'audio',
    bytes,
    filename: 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
    contentType: MediaType('audio', 'm4a'),
  ));

  request.fields['duration'] = duration.toString();
  if (expiresIn != null) {
    request.fields['expiresIn'] = expiresIn.toString();
  }

  final response = await request.send();
  final responseBody = await response.stream.bytesToString();

  if (response.statusCode == 201) {
    final json = jsonDecode(responseBody);
    return VoiceUploadResult(
      mediaUrl: json['mediaUrl'],
      publicId: json['publicId'],
      duration: json['duration'],
    );
  } else {
    throw Exception('Failed to upload voice message: ${response.statusCode}');
  }
}
```

**New model:**
```dart
class VoiceUploadResult {
  final String mediaUrl;
  final String publicId;
  final int duration;

  VoiceUploadResult({
    required this.mediaUrl,
    required this.publicId,
    required this.duration,
  });
}
```

### 7. Socket Service Enhancement

**Modified:** `lib/services/socket_service.dart`

**Update `sendMessage()` signature:**
```dart
void sendMessage({
  required int recipientId,
  required String content,
  String? messageType,  // ← NEW: 'TEXT' (default), 'VOICE', 'PING', etc.
  String? mediaUrl,  // ← NEW: Cloudinary URL for voice/image
  int? mediaDuration,  // ← NEW: duration in seconds
  int? expiresIn,
  String? tempId,
}) {
  socket?.emit('sendMessage', {
    'recipientId': recipientId,
    'content': content,
    'messageType': messageType ?? 'TEXT',
    if (mediaUrl != null) 'mediaUrl': mediaUrl,
    if (mediaDuration != null) 'mediaDuration': mediaDuration,
    if (expiresIn != null) 'expiresIn': expiresIn,
    if (tempId != null) 'tempId': tempId,
  });
}
```

### 8. Message Model Enhancement

**Modified:** `lib/models/message_model.dart`

**Add VOICE to enum:**
```dart
enum MessageType {
  text,
  ping,
  image,
  drawing,
  voice,  // ← NEW
}
```

**Update parsing:**
```dart
static MessageType _parseMessageType(String? type) {
  switch (type?.toUpperCase()) {
    case 'PING':
      return MessageType.ping;
    case 'IMAGE':
      return MessageType.image;
    case 'DRAWING':
      return MessageType.drawing;
    case 'VOICE':  // ← NEW
      return MessageType.voice;
    default:
      return MessageType.text;
  }
}
```

**Add mediaDuration field:**
```dart
class MessageModel {
  final int id;
  final String content;
  final int senderId;
  final String senderEmail;
  final String? senderUsername;
  final int conversationId;
  final DateTime createdAt;
  final MessageDeliveryStatus deliveryStatus;
  final DateTime? expiresAt;
  final MessageType messageType;
  final String? mediaUrl;
  final int? mediaDuration;  // ← NEW: duration in seconds
  final String? tempId;

  // Constructor, fromJson, copyWith updated accordingly
}
```

**Update `copyWith()` to include mediaDuration.**

---

## Data Flow (Step-by-Step)

### Recording Flow
1. User long-presses mic button (text field empty)
2. Frontend checks mic permission:
   - Mobile: `permission_handler.request(Permission.microphone)`
   - Web: browser prompts automatically on `record.start()`
3. If denied: show top snackbar, abort
4. If granted: start recording (record package, AAC/M4A format)
5. Show `VoiceRecordingOverlay`:
   - Timer starts (0:00 → 2:00)
   - Waveform animates in real-time (audio_waveforms)
   - User can swipe left to cancel
6. If recording reaches 2:00: auto-stop + proceed to send
7. If user releases button:
   - Duration < 1s: auto-cancel, delete file, show "Hold longer to record"
   - Duration >= 1s: proceed to send

### Sending Flow (Optimistic UI)
8. Save recording to temp file:
   - Path: `path_provider.getTemporaryDirectory()/voice_{timestamp}.m4a`
9. Create optimistic message:
   - `messageType: MessageType.voice`
   - `deliveryStatus: MessageDeliveryStatus.sending`
   - `mediaUrl: <local file path>`
   - `mediaDuration: <measured seconds>`
   - `tempId: <uuid>`
   - `expiresAt: <calculated from conversation timer>`
10. Add to `ChatProvider._messages` → UI shows message bubble immediately
11. **Background upload** (non-blocking):
    - POST `/messages/voice` with audio file (multipart)
    - Backend uploads to Cloudinary with TTL (if disappearing timer active)
    - Returns `{ mediaUrl, publicId, duration }`
12. Send via WebSocket:
    - `emit('sendMessage', { messageType: 'VOICE', mediaUrl: <cloudinary url>, mediaDuration, ... })`
13. Update optimistic message:
    - Replace local `mediaUrl` with Cloudinary URL
    - Update `deliveryStatus: MessageDeliveryStatus.sent`
14. Backend emits `messageSent` (to sender) + `newMessage` (to recipient)
15. ChatProvider updates message with real ID from backend (via `tempId` matching)

### Receiving Flow
16. Recipient's `SocketService` receives `newMessage` event
17. ChatProvider adds to `_messages`, updates conversation preview
18. UI renders `VoiceMessageBubble`:
    - Show play button + static waveform + duration label
    - Audio NOT downloaded yet (lazy load)
19. User taps play button:
    - Check if cached: `audio_cache/{messageId}.m4a`
    - If not cached: download from Cloudinary URL, save to cache
    - Initialize `AudioPlayer` from just_audio
    - Load audio file: `audioPlayer.setFilePath(cachedPath)`
    - Start playback: `audioPlayer.play()`
    - Animate waveform progress (sync with `audioPlayer.positionStream`)
20. User can:
    - Scrub timeline: update `audioPlayer.seek(position)`
    - Change playback speed: `audioPlayer.setSpeed(1.0 / 1.5 / 2.0)`
    - Pause/resume: `audioPlayer.pause() / play()`

### Expiration Flow
21. If message has `expiresAt`:
    - Frontend: `ChatProvider.removeExpiredMessages()` called every 1s removes from UI when expired
    - Backend cron: deletes message from DB after expiration (existing logic)
    - Cloudinary: auto-deletes file when TTL expires (no manual cleanup needed)
22. Expired voice messages:
    - Removed from chat UI
    - Audio file deleted from Cloudinary (automatic)
    - Local cache can be purged (future enhancement: cache cleanup job)

---

## Error Handling

### 1. Permission Denied
**Scenario:** User denies microphone permission

**Handling:**
- Mobile: Show top snackbar "Microphone permission required"
- Web: Show top snackbar "Please allow microphone access"
- Mic button disabled/grayed out until permission granted
- (Optional) Add "Open Settings" button on mobile to navigate to app settings

### 2. Recording Errors
**Scenario:** Recording fails to start (mic in use by another app, hardware error)

**Handling:**
- Show top snackbar "Failed to start recording. Please try again."
- Log error to console for debugging
- Button returns to normal state
- User can retry

**Scenario:** Recording fails mid-way (app interrupted, OS kills mic access)

**Handling:**
- Stop recording gracefully
- Save current recording as draft (future enhancement)
- Show top snackbar "Recording interrupted"
- Option to resume or discard draft

### 3. Upload Failures
**Scenario:** Upload to backend fails (network error, 500 server error, timeout)

**Handling:**
- Keep message in chat with `deliveryStatus: MessageDeliveryStatus.failed`
- Show red exclamation icon instead of delivery checkmark
- Audio file kept in temp storage for retry
- Tap message bubble → show action sheet with "Retry" option
- User taps retry → re-attempt upload with same file
- After 3 consecutive failed retries: show "Upload failed - please check your connection"

**Visual indicator:**
- Failed messages: red exclamation mark (⚠️) in bubble
- Retry button in message options

### 4. Playback Errors
**Scenario:** Download from Cloudinary fails (network error, file deleted)

**Handling:**
- Show loading spinner → then "Failed to load audio"
- Retry button in message bubble
- If file expired (`expiresAt` passed): show "Audio no longer available" (grayed out play button)

**Scenario:** Audio file corrupted or codec not supported

**Handling:**
- Show "Audio format not supported"
- Fallback: attempt to play alternate format (Cloudinary can transcode on-the-fly)
- Last resort: show permanent error message

### 5. Edge Cases

**Max duration exceeded (2 minutes):**
- Visual warning at 1:50 (timer turns yellow)
- Visual warning at 1:58 (timer turns red)
- Auto-stop at 2:00, proceed to send seamlessly (no "recording stopped" toast)

**Recording < 1 second (accidental tap):**
- Cancel automatically, delete temp file
- Show brief toast: "Hold longer to record voice message"
- No message created

**User navigates away during recording:**
- Auto-save draft (future enhancement)
- OR auto-cancel if duration < 1s

**Multiple recordings in quick succession:**
- Queue uploads (process one at a time, FIFO)
- All shown optimistically in chat
- Upload order maintained

**Disappearing timer changed after voice sent:**
- Voice message uploaded with original TTL
- Backend recalculates `expiresAt` on delivery (same as text messages)
- Cloudinary TTL remains unchanged (slight buffer is OK, file auto-deletes anyway)

**User deletes conversation while voice uploading:**
- Cancel pending upload
- Delete temp file
- Remove optimistic message from UI

---

## Testing Strategy

### Unit Tests

**Backend:**
- `CloudinaryService.uploadVoiceMessage()`: TTL calculation, format validation, upload success/failure
- `MessagesService.create()`: VOICE type message creation with `mediaDuration`
- `MessagesController.uploadVoiceMessage()`: file validation, multipart handling

**Frontend:**
- `ChatProvider.sendVoiceMessage()`: optimistic message creation, upload queue, error handling
- `MessageModel`: VOICE type parsing, `copyWith` with new fields, JSON serialization
- `VoiceRecordingOverlay`: timer logic, swipe-to-cancel gesture detection, auto-stop at 2min
- `VoiceMessageBubble`: playback state transitions, speed toggle, scrub slider

### Integration Tests

**Recording flow:**
1. Long-press mic → recording starts → overlay appears → timer increments
2. Swipe left > 100px → cancel animation triggers → recording deleted, overlay hidden
3. Release at 5s → message sent → appears in chat optimistically → upload completes

**Upload flow:**
1. Record 10s voice → release → upload starts in background → `mediaUrl` updates from local to Cloudinary
2. Simulate network error → message shows failed status → tap retry → re-uploads successfully
3. Record 3 voices in quick succession → all queued → upload in order (FIFO)

**Playback flow:**
1. Receive voice message → tap play → downloads → caches → plays
2. Scrub slider to 50% → audio seeks to 50% position
3. Change speed 1x → 1.5x → 2x → playback rate updates
4. Pause → resume → continues from correct position

**Expiration flow:**
1. Send voice with 30s timer → delivered → countdown starts → expires at 0 → message vanishes from UI
2. Verify Cloudinary: file auto-deleted after TTL (manual check via Cloudinary dashboard)

### Manual Testing Checklist

**Mobile (Android + iOS):**
- [ ] Mic permission prompt appears on first use
- [ ] Recording works (AAC/M4A format saved to temp file)
- [ ] Waveform animates smoothly during recording
- [ ] Swipe-to-cancel gesture is responsive (< 100px threshold)
- [ ] Upload completes in background (UI remains responsive)
- [ ] Playback smooth, no audio glitches or stuttering
- [ ] Speed toggle works (1x, 1.5x, 2x audible difference)
- [ ] Disappearing timer synchronized (voice expires at correct time)
- [ ] Retry works after simulated network failure

**Web (Chrome, Firefox, Edge):**
- [ ] Browser mic permission prompt appears
- [ ] MediaRecorder API records (WebM/Opus format)
- [ ] Backend accepts WebM, converts to M4A via Cloudinary
- [ ] Upload works from web client
- [ ] Playback in web player (just_audio web support confirmed)
- [ ] All UI components render correctly (waveform, slider, buttons)
- [ ] Speed toggle works in browser

**Cross-platform:**
- [ ] Send from mobile → receive on web → playback works
- [ ] Send from web → receive on mobile → playback works
- [ ] Cloudinary TTL auto-deletes files after expiration (verify in dashboard)
- [ ] Retry button appears and works after network failure
- [ ] Local cache prevents re-downloading same audio

---

## Implementation Phases

### Phase 1: Backend Foundation
1. Add `VOICE` to `MessageType` enum, add `mediaDuration` column
2. Implement `CloudinaryService.uploadVoiceMessage()` with TTL
3. Create `/messages/voice` REST endpoint
4. Test upload + TTL via Postman/Insomnia

### Phase 2: Frontend Recording
1. Add dependencies (record, audio_waveforms, permission_handler)
2. Implement `VoiceRecordingOverlay` widget
3. Modify `ChatInputBar` with long-press gesture detection
4. Implement recording logic (start, stop, cancel, save to temp file)
5. Test recording on mobile + web

### Phase 3: Frontend Upload & Optimistic UI
1. Enhance `ChatProvider.sendVoiceMessage()` with optimistic updates
2. Implement `ApiService.uploadVoiceMessage()` with multipart upload
3. Update `MessageModel` and `SocketService` to support VOICE type
4. Test end-to-end: record → optimistic display → upload → WebSocket send

### Phase 4: Frontend Playback
1. Implement `VoiceMessageBubble` widget with just_audio
2. Add lazy download + local caching logic
3. Implement waveform progress animation
4. Add playback controls (play/pause, scrub, speed toggle)
5. Test playback on mobile + web

### Phase 5: Error Handling & Polish
1. Implement retry logic for failed uploads
2. Add permission handling (prompts, error messages)
3. Handle edge cases (< 1s recording, 2min auto-stop, etc.)
4. Add visual polish (animations, loading states, error icons)

### Phase 6: Testing & Refinement
1. Write unit tests (backend + frontend)
2. Write integration tests (recording, upload, playback, expiration)
3. Manual testing checklist (mobile, web, cross-platform)
4. Performance optimization (audio caching, upload queue)
5. Documentation updates (CLAUDE.md, API docs)

---

## Future Enhancements

- **Audio effects:** Noise reduction, echo cancellation
- **Waveform customization:** Color themes, amplitude normalization
- **Draft management:** Save interrupted recordings, resume later
- **Push notifications:** "New voice message from X"
- **Voice message forwarding:** Send received voice to another user
- **Transcription:** Auto-generate text captions (speech-to-text API)
- **Compression options:** User-selectable quality (low/medium/high bitrate)
- **Multiple playback speeds:** 0.5x, 0.75x, 1.25x, 1.75x (not just 1x/1.5x/2x)

---

## Success Metrics

- ✅ Recording latency < 200ms (tap to start recording)
- ✅ Message display latency < 100ms (optimistic UI)
- ✅ Upload completion rate > 95% (retry logic handles failures)
- ✅ Playback start latency < 1s (first play, includes download)
- ✅ Cached playback latency < 100ms (subsequent plays)
- ✅ TTL accuracy: Cloudinary deletes files within 1 hour of message expiration
- ✅ Cross-platform compatibility: works on web + mobile without degradation

---

## Risks & Mitigations

**Risk:** Cloudinary TTL not working as expected (files not auto-deleted)

**Mitigation:** Test TTL in staging environment, verify deletion via Cloudinary dashboard. Fallback: manual cleanup cron job.

---

**Risk:** Audio codec incompatibility (web WebM vs mobile M4A)

**Mitigation:** Backend converts all uploads to M4A via Cloudinary. just_audio supports both formats on all platforms.

---

**Risk:** Poor UX on slow networks (upload takes too long)

**Mitigation:** Optimistic UI ensures instant feedback. Show upload progress indicator (optional). Retry logic for failures.

---

**Risk:** Permission handling inconsistencies across platforms

**Mitigation:** Use permission_handler for mobile, rely on browser API for web. Clear error messages + instructions for users.

---

## Conclusion

This design provides a comprehensive, Telegram-like voice messaging experience with:
- ✅ Intuitive UX (hold to record, swipe to cancel)
- ✅ Instant feedback (optimistic UI)
- ✅ Robust error handling (retry, permissions, edge cases)
- ✅ Cross-platform support (web + mobile)
- ✅ Automatic cleanup (Cloudinary TTL for disappearing messages)

Next step: Create implementation plan with detailed tasks.
