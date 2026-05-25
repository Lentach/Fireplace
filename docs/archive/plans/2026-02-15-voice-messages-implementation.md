# Voice Messages Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement full-featured voice messaging with hold-to-record, optimistic UI, Cloudinary storage with TTL auto-delete, and rich playback controls.

**Architecture:** Optimistic UI with background upload - messages appear instantly while audio uploads to Cloudinary in background. Backend validates and stores with TTL for auto-expiration. Frontend uses record package for cross-platform recording and just_audio for playback with waveform visualization.

**Tech Stack:** NestJS + TypeORM + Cloudinary (backend), Flutter + record + audio_waveforms + just_audio (frontend)

**Design Document:** `docs/plans/2026-02-15-voice-messages-design.md`

---

## Phase 1: Backend Foundation

### Task 1.1: Add VOICE to MessageType enum

**Files:**
- Modify: `backend/src/messages/message.entity.ts:19-24`

**Step 1: Add VOICE enum value**

```typescript
export enum MessageType {
  TEXT = 'TEXT',
  PING = 'PING',
  IMAGE = 'IMAGE',
  DRAWING = 'DRAWING',
  VOICE = 'VOICE',  // ← ADD
}
```

**Step 2: Verify TypeORM synchronization**

Run: `docker-compose up` (backend will auto-sync schema)
Expected: No migration errors, enum updated in PostgreSQL

**Step 3: Commit**

```bash
git add backend/src/messages/message.entity.ts
git commit -m "feat(backend): add VOICE to MessageType enum

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 1.2: Add mediaDuration column to Message entity

**Files:**
- Modify: `backend/src/messages/message.entity.ts:53-54`

**Step 1: Add mediaDuration column**

```typescript
@Column({ type: 'text', nullable: true })
mediaUrl: string | null;

@Column({ type: 'int', nullable: true })
mediaDuration: number | null;  // ← ADD: duration in seconds

@ManyToOne(() => User, { eager: true })
```

**Step 2: Verify TypeORM synchronization**

Run: `docker-compose up` (check logs for column addition)
Expected: `ALTER TABLE "messages" ADD "mediaDuration" integer`

**Step 3: Commit**

```bash
git add backend/src/messages/message.entity.ts
git commit -m "feat(backend): add mediaDuration column to Message entity

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 1.3: Add uploadVoiceMessage method to CloudinaryService

**Files:**
- Modify: `backend/src/cloudinary/cloudinary.service.ts:68-end`

**Step 1: Write the method signature and implementation**

Add after `deleteAvatar` method:

```typescript
  async uploadVoiceMessage(
    userId: number,
    buffer: Buffer,
    mimeType: string,
    expiresIn?: number,
  ): Promise<{ secureUrl: string; publicId: string; duration: number }> {
    const dataUri = `data:${mimeType};base64,${buffer.toString('base64')}`;

    const uploadOptions: any = {
      folder: 'voice-messages',
      public_id: `user-${userId}-${Date.now()}`,
      resource_type: 'video', // Cloudinary uses 'video' for audio files
      format: 'm4a',
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
      duration: result.duration || 0,
    };
  }
}
```

**Step 2: Update interface exports at top of file**

After line 13:

```typescript
export interface UploadImageResult {
  secureUrl: string;
  publicId: string;
}

export interface UploadVoiceResult {
  secureUrl: string;
  publicId: string;
  duration: number;
}
```

**Step 3: Test manually with Postman/Insomnia**

Later: Will test via `/messages/voice` endpoint

**Step 4: Commit**

```bash
git add backend/src/cloudinary/cloudinary.service.ts
git commit -m "feat(backend): add uploadVoiceMessage with TTL to CloudinaryService

- Uploads to voice-messages/ folder
- Sets Cloudinary expires_at based on disappearing timer
- Extracts audio duration from Cloudinary response
- Returns secureUrl, publicId, duration

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 1.4: Create POST /messages/voice endpoint

**Files:**
- Modify: `backend/src/messages/messages.controller.ts` (add method before closing brace)

**Step 1: Add imports at top of file**

```typescript
import {
  Controller,
  Post,
  UseGuards,
  Request,
  UseInterceptors,
  UploadedFile,
  BadRequestException,
  Body,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
```

**Step 2: Inject CloudinaryService in constructor**

Update constructor:

```typescript
constructor(
  private readonly messagesService: MessagesService,
  private readonly cloudinaryService: CloudinaryService,  // ← ADD
) {}
```

**Step 3: Add uploadVoiceMessage method**

Add before closing brace:

```typescript
  @Post('voice')
  @UseGuards(JwtAuthGuard)
  @UseInterceptors(
    FileInterceptor('audio', {
      limits: { fileSize: 10 * 1024 * 1024 }, // 10MB max
      fileFilter: (req, file, cb) => {
        const allowedMimes = [
          'audio/aac',
          'audio/mp4',
          'audio/m4a',
          'audio/mpeg',
          'audio/webm',
        ];
        if (!allowedMimes.includes(file.mimetype)) {
          return cb(
            new BadRequestException('Invalid audio format'),
            false,
          );
        }
        cb(null, true);
      },
    }),
  )
  async uploadVoiceMessage(
    @UploadedFile() file: Express.Multer.File,
    @Body('duration') duration: string,
    @Body('expiresIn') expiresIn?: string,
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
      duration: result.duration || durationNum,
    };
  }
```

**Step 4: Update MessagesModule imports**

Modify: `backend/src/messages/messages.module.ts`

```typescript
import { CloudinaryModule } from '../cloudinary/cloudinary.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([Message]),
    CloudinaryModule,  // ← ADD
  ],
  // ...
})
```

**Step 5: Test endpoint with curl**

```bash
# First login to get JWT
curl -X POST http://localhost:3000/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"Test1234"}'

# Upload voice (need actual audio file)
curl -X POST http://localhost:3000/messages/voice \
  -H "Authorization: Bearer <JWT>" \
  -F "audio=@test-audio.m4a" \
  -F "duration=5"
```

Expected: `{ "mediaUrl": "https://res.cloudinary.com/...", "publicId": "...", "duration": 5 }`

**Step 6: Commit**

```bash
git add backend/src/messages/messages.controller.ts backend/src/messages/messages.module.ts
git commit -m "feat(backend): add POST /messages/voice endpoint

- Accepts multipart audio file (AAC/M4A/WebM/MP3)
- Max 10MB file size
- Uploads to Cloudinary with optional TTL (expiresIn)
- Returns mediaUrl, publicId, duration

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 1.5: Update WebSocket sendMessage to support VOICE type

**Files:**
- Modify: `backend/src/chat/dto/chat.dto.ts:11-29`
- Modify: `backend/src/chat/services/chat-message.service.ts`

**Step 1: Update SendMessageDto to include optional media fields**

```typescript
export class SendMessageDto {
  @IsNumber()
  @IsPositive()
  recipientId: number;

  @IsString()
  @MinLength(1, { message: 'Message cannot be empty' })
  @MaxLength(5000, { message: 'Message cannot exceed 5000 characters' })
  content: string;

  @IsOptional()
  @IsNumber()
  @IsPositive()
  expiresIn?: number;

  @IsOptional()
  @IsString()
  tempId?: string;

  @IsOptional()
  @IsString()
  messageType?: string;  // ← ADD: 'TEXT', 'VOICE', 'PING', etc.

  @IsOptional()
  @IsString()
  mediaUrl?: string;  // ← ADD: Cloudinary URL for voice/image

  @IsOptional()
  @IsNumber()
  @IsPositive()
  mediaDuration?: number;  // ← ADD: duration in seconds
}
```

**Step 2: Update chat-message.service.ts handleSendMessage**

Modify: `backend/src/chat/services/chat-message.service.ts` (find handleSendMessage method)

Add to message creation:

```typescript
async handleSendMessage(client: Socket, dto: SendMessageDto) {
  const user = client.data.user;
  // ... existing code ...

  const message = await this.messagesService.create({
    senderId: user.id,
    recipientId: dto.recipientId,
    content: dto.content,
    messageType: dto.messageType || 'TEXT',  // ← ADD (default TEXT)
    mediaUrl: dto.mediaUrl || null,  // ← ADD
    mediaDuration: dto.mediaDuration || null,  // ← ADD
    expiresIn: dto.expiresIn,
  });

  // ... rest of existing code ...
}
```

**Step 3: Update messagesService.create to accept new fields**

Modify: `backend/src/messages/messages.service.ts` (create method)

```typescript
async create(data: {
  senderId: number;
  recipientId: number;
  content: string;
  messageType?: string;  // ← ADD
  mediaUrl?: string | null;  // ← ADD
  mediaDuration?: number | null;  // ← ADD
  expiresIn?: number;
}): Promise<Message> {
  // ... find or create conversation ...

  const message = this.messageRepository.create({
    content: data.content,
    sender: { id: data.senderId },
    conversation: { id: conversation.id },
    deliveryStatus: MessageDeliveryStatus.SENT,
    messageType: (data.messageType as MessageType) || MessageType.TEXT,  // ← ADD
    mediaUrl: data.mediaUrl || null,  // ← ADD
    mediaDuration: data.mediaDuration || null,  // ← ADD
    // ... existing expiresAt logic ...
  });

  return this.messageRepository.save(message);
}
```

**Step 4: Update WebSocket payload to include media fields**

In chat-message.service.ts, update the payload sent via socket:

```typescript
const messagePayload = {
  id: message.id,
  content: message.content,
  senderId: user.id,
  senderEmail: user.email,
  senderUsername: user.username,
  conversationId: message.conversation.id,
  createdAt: message.createdAt.toISOString(),
  deliveryStatus: message.deliveryStatus,
  expiresAt: message.expiresAt?.toISOString() || null,
  messageType: message.messageType,  // ← ADD
  mediaUrl: message.mediaUrl,  // ← ADD
  mediaDuration: message.mediaDuration,  // ← ADD
  tempId: dto.tempId,
};
```

**Step 5: Test WebSocket event manually**

Use Socket.IO client to emit:

```javascript
socket.emit('sendMessage', {
  recipientId: 2,
  content: '',
  messageType: 'VOICE',
  mediaUrl: 'https://res.cloudinary.com/test.m4a',
  mediaDuration: 10,
});
```

Expected: Receives `messageSent` and `newMessage` with all fields

**Step 6: Commit**

```bash
git add backend/src/chat/dto/chat.dto.ts backend/src/chat/services/chat-message.service.ts backend/src/messages/messages.service.ts
git commit -m "feat(backend): support VOICE messageType in WebSocket sendMessage

- Add messageType, mediaUrl, mediaDuration to SendMessageDto
- Update messagesService.create to accept and store media fields
- Include media fields in WebSocket payload (messageSent/newMessage)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Phase 2: Frontend Recording

### Task 2.1: Add dependencies to pubspec.yaml

**Files:**
- Modify: `frontend/pubspec.yaml:44-46`

**Step 1: Add new packages**

```yaml
  just_audio: ^0.9.36  # already exists
  path_provider: ^2.1.1  # already exists

  # NEW PACKAGES:
  record: ^5.0.0  # cross-platform audio recording
  audio_waveforms: ^1.0.5  # waveform visualization
  permission_handler: ^11.0.0  # mic permissions
```

**Step 2: Install packages**

Run: `cd frontend && flutter pub get`
Expected: All packages downloaded successfully

**Step 3: Commit**

```bash
git add frontend/pubspec.yaml frontend/pubspec.lock
git commit -m "feat(frontend): add audio recording dependencies

- record: cross-platform audio recording (web + mobile)
- audio_waveforms: waveform visualization
- permission_handler: microphone permissions

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 2.2: Add VOICE to MessageType enum (frontend)

**Files:**
- Modify: `frontend/lib/models/message_model.dart:8-13`

**Step 1: Add voice to enum**

```dart
enum MessageType {
  text,
  ping,
  image,
  drawing,
  voice,  // ← ADD
}
```

**Step 2: Update _parseMessageType method**

```dart
static MessageType _parseMessageType(String? type) {
  switch (type?.toUpperCase()) {
    case 'PING':
      return MessageType.ping;
    case 'IMAGE':
      return MessageType.image;
    case 'DRAWING':
      return MessageType.drawing;
    case 'VOICE':  // ← ADD
      return MessageType.voice;
    default:
      return MessageType.text;
  }
}
```

**Step 3: Commit**

```bash
git add frontend/lib/models/message_model.dart
git commit -m "feat(frontend): add VOICE to MessageType enum

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 2.3: Add mediaDuration field to MessageModel

**Files:**
- Modify: `frontend/lib/models/message_model.dart:15-42`
- Modify: `frontend/lib/models/message_model.dart:92-110`

**Step 1: Add mediaDuration field to class**

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
  final int? mediaDuration;  // ← ADD: duration in seconds
  final String? tempId;

  MessageModel({
    required this.id,
    required this.content,
    required this.senderId,
    required this.senderEmail,
    this.senderUsername,
    required this.conversationId,
    required this.createdAt,
    this.deliveryStatus = MessageDeliveryStatus.sent,
    this.expiresAt,
    this.messageType = MessageType.text,
    this.mediaUrl,
    this.mediaDuration,  // ← ADD
    this.tempId,
  });
```

**Step 2: Update fromJson to parse mediaDuration**

```dart
factory MessageModel.fromJson(Map<String, dynamic> json) {
  return MessageModel(
    // ... existing fields ...
    mediaUrl: json['mediaUrl'] as String?,
    mediaDuration: json['mediaDuration'] as int?,  // ← ADD
    tempId: json['tempId'] as String?,
  );
}
```

**Step 3: Update copyWith to include mediaDuration**

```dart
MessageModel copyWith({
  MessageDeliveryStatus? deliveryStatus,
  DateTime? expiresAt,
  String? mediaUrl,  // ← ADD parameter
  int? mediaDuration,  // ← ADD parameter
}) {
  return MessageModel(
    id: id,
    content: content,
    senderId: senderId,
    senderEmail: senderEmail,
    senderUsername: senderUsername,
    conversationId: conversationId,
    createdAt: createdAt,
    deliveryStatus: deliveryStatus ?? this.deliveryStatus,
    expiresAt: expiresAt ?? this.expiresAt,
    messageType: messageType,
    mediaUrl: mediaUrl ?? this.mediaUrl,  // ← ADD
    mediaDuration: mediaDuration ?? this.mediaDuration,  // ← ADD
    tempId: tempId,
  );
}
```

**Step 4: Commit**

```bash
git add frontend/lib/models/message_model.dart
git commit -m "feat(frontend): add mediaDuration field to MessageModel

- Add mediaDuration to class fields
- Parse from JSON
- Include in copyWith

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 2.4: Create VoiceRecordingOverlay widget

**Files:**
- Create: `frontend/lib/widgets/voice_recording_overlay.dart`

**Step 1: Create widget file with basic structure**

```dart
import 'package:flutter/material.dart';
import 'package:audio_waveforms/audio_waveforms.dart';
import '../theme/rpg_theme.dart';

class VoiceRecordingOverlay extends StatefulWidget {
  final Function(String audioPath, int duration) onSendVoice;
  final VoidCallback onCancel;

  const VoiceRecordingOverlay({
    super.key,
    required this.onSendVoice,
    required this.onCancel,
  });

  @override
  State<VoiceRecordingOverlay> createState() => _VoiceRecordingOverlayState();
}

class _VoiceRecordingOverlayState extends State<VoiceRecordingOverlay>
    with SingleTickerProviderStateMixin {
  int _recordingDuration = 0; // seconds
  double _cancelDragOffset = 0.0; // horizontal drag for cancel gesture
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes}:${secs.toString().padLeft(2, '0')}';
  }

  Color _getTimerColor() {
    if (_recordingDuration >= 118) return Colors.red; // 1:58+
    if (_recordingDuration >= 110) return Colors.yellow; // 1:50+
    return Colors.white;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _cancelDragOffset += details.delta.dx;
      if (_cancelDragOffset < -100) {
        // Trigger cancel
        widget.onCancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = RpgTheme.isDark(context);

    return GestureDetector(
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      child: Material(
        color: isDark ? Colors.black87 : Colors.white.withOpacity(0.95),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Timer display
              Text(
                _formatDuration(_recordingDuration),
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: _getTimerColor(),
                ),
              ),
              const SizedBox(height: 32),

              // Waveform placeholder (will add in next task)
              Container(
                height: 100,
                width: MediaQuery.of(context).size.width * 0.8,
                color: Colors.grey.withOpacity(0.2),
                child: const Center(child: Text('Waveform here')),
              ),

              const SizedBox(height: 48),

              // Pulsing mic icon
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: 1.0 + (_pulseController.value * 0.2),
                    child: Icon(
                      Icons.mic,
                      size: 80,
                      color: Colors.red.withOpacity(0.8 + (_pulseController.value * 0.2)),
                    ),
                  );
                },
              ),

              const SizedBox(height: 48),

              // Swipe to cancel instruction
              Opacity(
                opacity: _cancelDragOffset < 0 ? 1.0 - (_cancelDragOffset.abs() / 100) : 1.0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.arrow_back, color: Colors.red.withOpacity(0.7)),
                    const SizedBox(width: 8),
                    Text(
                      'Swipe left to cancel',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black54,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

**Step 2: Add timer update mechanism**

This widget receives duration updates from parent (ChatInputBar). Parent will call setState to update duration prop, or we'll use a Stream/callback.

**Step 3: Commit**

```bash
git add frontend/lib/widgets/voice_recording_overlay.dart
git commit -m "feat(frontend): create VoiceRecordingOverlay widget

- Timer display with color warnings (yellow at 1:50, red at 1:58)
- Pulsing mic icon animation
- Swipe-to-cancel gesture detection (drag left > 100px)
- Placeholder for waveform (will add in next task)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 2.5: Integrate recording in ChatInputBar

**Files:**
- Modify: `frontend/lib/widgets/chat_input_bar.dart`

**Step 1: Add imports at top**

```dart
import 'dart:async';
import 'dart:io';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'voice_recording_overlay.dart';
import 'top_snackbar.dart';
```

**Step 2: Add state variables to _ChatInputBarState**

```dart
class _ChatInputBarState extends State<ChatInputBar> {
  final TextEditingController _controller = TextEditingController();
  bool _hasText = false;

  // Voice recording state
  bool _isRecording = false;
  bool _isSendingVoice = false;
  AudioRecorder? _audioRecorder;
  String? _recordingPath;
  Timer? _recordingTimer;
  int _recordingDuration = 0; // seconds
  OverlayEntry? _recordingOverlay;

  // ... rest of existing code
```

**Step 3: Add recording methods**

```dart
Future<void> _checkMicPermission() async {
  if (Platform.isAndroid || Platform.isIOS) {
    final status = await Permission.microphone.request();
    if (status.isDenied || status.isPermanentlyDenied) {
      if (!mounted) return;
      showTopSnackBar(context, 'Microphone permission required');
      throw Exception('Permission denied');
    }
  }
  // Web: permission handled by browser automatically
}

Future<void> _startRecording() async {
  try {
    await _checkMicPermission();

    _audioRecorder = AudioRecorder();
    final tempDir = await getTemporaryDirectory();
    _recordingPath = '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

    final hasPermission = await _audioRecorder!.hasPermission();
    if (!hasPermission) {
      if (!mounted) return;
      showTopSnackBar(context, 'Microphone permission denied');
      return;
    }

    await _audioRecorder!.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc, // AAC/M4A format
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: _recordingPath!,
    );

    setState(() {
      _isRecording = true;
      _recordingDuration = 0;
    });

    // Show overlay
    _showRecordingOverlay();

    // Start timer (increment every second)
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _recordingDuration++;
        if (_recordingDuration >= 120) {
          // Auto-stop at 2 minutes
          _stopRecording();
        }
      });
    });
  } catch (e) {
    if (!mounted) return;
    showTopSnackBar(context, 'Failed to start recording');
    print('Recording error: $e');
  }
}

Future<void> _stopRecording() async {
  if (_audioRecorder == null || !_isRecording) return;

  _recordingTimer?.cancel();
  _recordingTimer = null;

  final path = await _audioRecorder!.stop();
  await _audioRecorder!.dispose();
  _audioRecorder = null;

  _hideRecordingOverlay();

  setState(() {
    _isRecording = false;
  });

  // Check duration
  if (_recordingDuration < 1) {
    // Too short, cancel
    if (path != null && File(path).existsSync()) {
      await File(path).delete();
    }
    if (!mounted) return;
    showTopSnackBar(context, 'Hold longer to record voice message');
    setState(() {
      _recordingDuration = 0;
      _recordingPath = null;
    });
    return;
  }

  // Send voice message
  if (path != null && File(path).existsSync()) {
    await _sendVoiceMessage(path, _recordingDuration);
  }

  setState(() {
    _recordingDuration = 0;
    _recordingPath = null;
  });
}

Future<void> _cancelRecording() async {
  if (_audioRecorder == null || !_isRecording) return;

  _recordingTimer?.cancel();
  _recordingTimer = null;

  await _audioRecorder!.stop();
  await _audioRecorder!.dispose();
  _audioRecorder = null;

  _hideRecordingOverlay();

  // Delete temp file
  if (_recordingPath != null && File(_recordingPath!).existsSync()) {
    await File(_recordingPath!).delete();
  }

  setState(() {
    _isRecording = false;
    _recordingDuration = 0;
    _recordingPath = null;
  });
}

Future<void> _sendVoiceMessage(String path, int duration) async {
  setState(() {
    _isSendingVoice = true;
  });

  try {
    final chat = Provider.of<ChatProvider>(context, listen: false);
    final conversationId = widget.conversationId;
    final recipientId = widget.recipientId;

    await chat.sendVoiceMessage(
      recipientId: recipientId,
      localAudioPath: path,
      duration: duration,
      conversationId: conversationId,
    );
  } catch (e) {
    if (!mounted) return;
    showTopSnackBar(context, 'Failed to send voice message');
    print('Send voice error: $e');
  } finally {
    if (mounted) {
      setState(() {
        _isSendingVoice = false;
      });
    }
  }
}

void _showRecordingOverlay() {
  _recordingOverlay = OverlayEntry(
    builder: (context) => VoiceRecordingOverlay(
      onSendVoice: (path, duration) {
        // Not used, we handle send in _stopRecording
      },
      onCancel: _cancelRecording,
    ),
  );
  Overlay.of(context).insert(_recordingOverlay!);
}

void _hideRecordingOverlay() {
  _recordingOverlay?.remove();
  _recordingOverlay = null;
}

@override
void dispose() {
  _controller.dispose();
  _recordingTimer?.cancel();
  _audioRecorder?.dispose();
  _recordingOverlay?.remove();
  super.dispose();
}
```

**Step 4: Update mic button with GestureDetector**

Find the mic IconButton in build() and replace with:

```dart
// Mic/Send button
_isSendingVoice
    ? const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      )
    : GestureDetector(
        onLongPressStart: (_) => _startRecording(),
        onLongPressEnd: (_) => _stopRecording(),
        child: Icon(
          _hasText ? Icons.send : (_isRecording ? Icons.mic : Icons.mic_none),
          color: _isRecording
              ? Colors.red
              : (isDark ? RpgTheme.accentDark : RpgTheme.primaryLight),
        ),
      ),
```

**Step 5: Update existing send button logic**

Keep existing text send logic, only add voice recording on long-press when `!_hasText`.

**Step 6: Test recording flow**

Run: `flutter run -d chrome` (or mobile device)
Actions:
1. Long-press mic → overlay appears, timer starts
2. Hold for 5s → release → message should send (will fail until ChatProvider.sendVoiceMessage exists)
3. Long-press, swipe left → recording cancels

**Step 7: Commit**

```bash
git add frontend/lib/widgets/chat_input_bar.dart
git commit -m "feat(frontend): integrate voice recording in ChatInputBar

- Long-press mic button to start recording (when text field empty)
- Show VoiceRecordingOverlay during recording
- Timer with auto-stop at 2 minutes
- Min 1 second duration, else auto-cancel
- Swipe left to cancel gesture
- Permission handling (mobile + web)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Phase 3: Frontend Upload & Optimistic UI

### Task 3.1: Add sendVoiceMessage to ChatProvider

**Files:**
- Modify: `frontend/lib/providers/chat_provider.dart`

**Step 1: Add import**

```dart
import 'dart:io';
```

**Step 2: Add sendVoiceMessage method**

Add after existing sendMessage method:

```dart
Future<void> sendVoiceMessage({
  required int recipientId,
  required String localAudioPath,
  required int duration,
  int? conversationId,
}) async {
  if (_currentUserId == null) return;

  // 1. Create optimistic message
  final tempId = DateTime.now().millisecondsSinceEpoch.toString();
  final expiresAt = _calculateExpiresAt(conversationId);

  final optimisticMessage = MessageModel(
    id: -1, // placeholder
    content: '',
    senderId: _currentUserId!,
    senderEmail: _currentUserEmail ?? '',
    conversationId: conversationId ?? -1,
    createdAt: DateTime.now(),
    deliveryStatus: MessageDeliveryStatus.sending,
    messageType: MessageType.voice,
    mediaUrl: localAudioPath, // local file path initially
    mediaDuration: duration,
    tempId: tempId,
    expiresAt: expiresAt,
  );

  // 2. Add to messages immediately (optimistic)
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

    // 6. Delete temp file after successful upload
    final file = File(localAudioPath);
    if (await file.exists()) {
      await file.delete();
    }
  } catch (e) {
    // 7. Mark as failed, keep local file for retry
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

DateTime? _calculateExpiresAt(int? conversationId) {
  if (conversationId == null) return null;

  final conversation = _conversations.firstWhere(
    (c) => c.id == conversationId,
    orElse: () => _conversations.first,
  );

  if (conversation.disappearingTimer == null || conversation.disappearingTimer == 0) {
    return null;
  }

  return DateTime.now().add(Duration(seconds: conversation.disappearingTimer!));
}

int? _getConversationDisappearingTimer(int? conversationId) {
  if (conversationId == null) return null;

  final conversation = _conversations.firstWhere(
    (c) => c.id == conversationId,
    orElse: () => _conversations.first,
  );

  return conversation.disappearingTimer;
}

void _updateLastMessage(int? conversationId, MessageModel message) {
  if (conversationId == null || conversationId == -1) return;
  _lastMessages[conversationId] = message;
}
```

**Step 3: Add failed status to MessageDeliveryStatus enum**

In `frontend/lib/models/message_model.dart`:

```dart
enum MessageDeliveryStatus {
  sending,
  sent,
  delivered,
  read,
  failed,  // ← ADD
}
```

Update parseDeliveryStatus:

```dart
static MessageDeliveryStatus parseDeliveryStatus(String? status) {
  switch (status?.toUpperCase()) {
    case 'SENDING':
      return MessageDeliveryStatus.sending;
    case 'SENT':
      return MessageDeliveryStatus.sent;
    case 'DELIVERED':
      return MessageDeliveryStatus.delivered;
    case 'READ':
      return MessageDeliveryStatus.read;
    case 'FAILED':  // ← ADD
      return MessageDeliveryStatus.failed;
    default:
      return MessageDeliveryStatus.sent;
  }
}
```

**Step 4: Commit**

```bash
git add frontend/lib/providers/chat_provider.dart frontend/lib/models/message_model.dart
git commit -m "feat(frontend): add sendVoiceMessage to ChatProvider

- Create optimistic message with SENDING status and local file path
- Upload to backend in background (non-blocking)
- Send via WebSocket after upload completes
- Update message with Cloudinary URL on success
- Mark as FAILED on error (keep local file for retry)
- Delete temp file after successful upload

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 3.2: Create uploadVoiceMessage in ApiService

**Files:**
- Modify: `frontend/lib/services/api_service.dart`

**Step 1: Add imports**

```dart
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
```

**Step 2: Add VoiceUploadResult class**

Add at end of file:

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

  factory VoiceUploadResult.fromJson(Map<String, dynamic> json) {
    return VoiceUploadResult(
      mediaUrl: json['mediaUrl'] as String,
      publicId: json['publicId'] as String,
      duration: json['duration'] as int,
    );
  }
}
```

**Step 3: Add uploadVoiceMessage method**

Add to ApiService class:

```dart
Future<VoiceUploadResult> uploadVoiceMessage({
  required String audioPath,
  required int duration,
  int? expiresIn,
}) async {
  final file = File(audioPath);
  if (!await file.exists()) {
    throw Exception('Audio file not found: $audioPath');
  }

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

  if (response.statusCode == 201 || response.statusCode == 200) {
    final json = jsonDecode(responseBody);
    return VoiceUploadResult.fromJson(json);
  } else {
    throw Exception('Failed to upload voice message: ${response.statusCode} - $responseBody');
  }
}
```

**Step 4: Test upload flow**

Run app, record voice, check logs for upload success/failure.

**Step 5: Commit**

```bash
git add frontend/lib/services/api_service.dart
git commit -m "feat(frontend): add uploadVoiceMessage to ApiService

- POST multipart upload to /messages/voice
- Include audio file, duration, expiresIn
- Return VoiceUploadResult with mediaUrl, publicId, duration

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 3.3: Update SocketService.sendMessage to support media fields

**Files:**
- Modify: `frontend/lib/services/socket_service.dart`

**Step 1: Update sendMessage method signature**

```dart
void sendMessage({
  required int recipientId,
  required String content,
  String? messageType,  // ← ADD
  String? mediaUrl,  // ← ADD
  int? mediaDuration,  // ← ADD
  int? expiresIn,
  String? tempId,
}) {
  socket?.emit('sendMessage', {
    'recipientId': recipientId,
    'content': content,
    'messageType': messageType ?? 'TEXT',  // ← ADD
    if (mediaUrl != null) 'mediaUrl': mediaUrl,  // ← ADD
    if (mediaDuration != null) 'mediaDuration': mediaDuration,  // ← ADD
    if (expiresIn != null) 'expiresIn': expiresIn,
    if (tempId != null) 'tempId': tempId,
  });
}
```

**Step 2: Update existing sendMessage calls in ChatProvider**

Find existing text message send and update:

```dart
_socketService.sendMessage(
  recipientId: recipientId,
  content: content,
  messageType: 'TEXT',  // ← ADD explicit type
  expiresIn: _getConversationDisappearingTimer(conversationId),
  tempId: tempId,
);
```

**Step 3: Commit**

```bash
git add frontend/lib/services/socket_service.dart frontend/lib/providers/chat_provider.dart
git commit -m "feat(frontend): update SocketService.sendMessage to support media fields

- Add messageType, mediaUrl, mediaDuration parameters
- Default messageType to TEXT for backward compatibility
- Update existing text message calls to be explicit

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Phase 4: Frontend Playback

### Task 4.1: Create VoiceMessageBubble widget

**Files:**
- Create: `frontend/lib/widgets/voice_message_bubble.dart`

**Step 1: Create widget file**

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../models/message_model.dart';
import '../theme/rpg_theme.dart';

class VoiceMessageBubble extends StatefulWidget {
  final MessageModel message;
  final bool isMine;

  const VoiceMessageBubble({
    super.key,
    required this.message,
    required this.isMine,
  });

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  bool _isLoading = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _playbackSpeed = 1.0;
  String? _cachedFilePath;

  @override
  void initState() {
    super.initState();
    _audioPlayer.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing;
        });
      }
    });

    _audioPlayer.positionStream.listen((position) {
      if (mounted) {
        setState(() {
          _position = position;
        });
      }
    });

    _audioPlayer.durationStream.listen((duration) {
      if (mounted && duration != null) {
        setState(() {
          _duration = duration;
        });
      }
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _togglePlayPause() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      // Check if audio is loaded
      if (_audioPlayer.duration == null) {
        await _loadAndPlayAudio();
      } else {
        await _audioPlayer.play();
      }
    }
  }

  Future<void> _loadAndPlayAudio() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Check if cached
      _cachedFilePath = await _getCachedFilePath();

      if (_cachedFilePath != null && File(_cachedFilePath!).existsSync()) {
        // Use cached file
        await _audioPlayer.setFilePath(_cachedFilePath!);
      } else {
        // Download and cache
        if (widget.message.mediaUrl == null) {
          throw Exception('No media URL');
        }

        _cachedFilePath = await _downloadAndCache(widget.message.mediaUrl!);
        await _audioPlayer.setFilePath(_cachedFilePath!);
      }

      await _audioPlayer.play();
    } catch (e) {
      print('Audio load error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load audio')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<String?> _getCachedFilePath() async {
    final dir = await getApplicationDocumentsDirectory();
    final cachePath = '${dir.path}/audio_cache';
    final file = File('$cachePath/${widget.message.id}.m4a');
    return file.existsSync() ? file.path : null;
  }

  Future<String> _downloadAndCache(String url) async {
    final dir = await getApplicationDocumentsDirectory();
    final cachePath = '${dir.path}/audio_cache';
    await Directory(cachePath).create(recursive: true);

    final file = File('$cachePath/${widget.message.id}.m4a');

    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      await file.writeAsBytes(response.bodyBytes);
      return file.path;
    } else {
      throw Exception('Failed to download audio: ${response.statusCode}');
    }
  }

  void _toggleSpeed() {
    setState(() {
      if (_playbackSpeed == 1.0) {
        _playbackSpeed = 1.5;
      } else if (_playbackSpeed == 1.5) {
        _playbackSpeed = 2.0;
      } else {
        _playbackSpeed = 1.0;
      }
      _audioPlayer.setSpeed(_playbackSpeed);
    });
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = RpgTheme.isDark(context);
    final bubbleColor = widget.isMine
        ? (isDark ? RpgTheme.mineMsgBg : RpgTheme.mineMsgBgLight)
        : (isDark ? RpgTheme.theirsMsgBg : RpgTheme.theirsMsgBgLight);
    final borderColor = widget.isMine
        ? (isDark ? RpgTheme.accentDark : RpgTheme.primaryLight)
        : (isDark ? RpgTheme.borderDark : RpgTheme.primaryLight);

    return Align(
      alignment: widget.isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: EdgeInsets.only(
          left: widget.isMine ? 48 : 0,
          right: widget.isMine ? 0 : 48,
          bottom: 4,
        ),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(16),
          border: Border(
            left: BorderSide(color: borderColor, width: 3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Playback controls row
            Row(
              children: [
                // Play/Pause button
                _isLoading
                    ? const SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                        onPressed: _togglePlayPause,
                        iconSize: 32,
                      ),

                const SizedBox(width: 8),

                // Waveform placeholder (will add in next task)
                Expanded(
                  child: Container(
                    height: 40,
                    color: Colors.grey.withOpacity(0.2),
                    child: const Center(child: Text('Waveform')),
                  ),
                ),

                const SizedBox(width: 8),

                // Speed toggle
                InkWell(
                  onTap: _toggleSpeed,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: borderColor),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_playbackSpeed}x',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Duration slider
            Row(
              children: [
                Text(
                  _formatDuration(_position),
                  style: const TextStyle(fontSize: 12),
                ),
                Expanded(
                  child: Slider(
                    value: _duration.inMilliseconds > 0
                        ? _position.inMilliseconds / _duration.inMilliseconds
                        : 0.0,
                    onChanged: (value) {
                      final newPosition = Duration(
                        milliseconds: (_duration.inMilliseconds * value).round(),
                      );
                      _audioPlayer.seek(newPosition);
                    },
                  ),
                ),
                Text(
                  _formatDuration(_duration),
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
```

**Step 2: Commit**

```bash
git add frontend/lib/widgets/voice_message_bubble.dart
git commit -m "feat(frontend): create VoiceMessageBubble widget

- Play/pause button with just_audio player
- Lazy download + local caching (audio_cache/ folder)
- Playback speed toggle (1x / 1.5x / 2x)
- Duration slider for scrubbing
- Placeholder for waveform (will add visualization next)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 4.2: Integrate VoiceMessageBubble in ChatMessageBubble

**Files:**
- Modify: `frontend/lib/widgets/chat_message_bubble.dart`

**Step 1: Add import**

```dart
import 'voice_message_bubble.dart';
```

**Step 2: Update build method to handle VOICE type**

In the build method, before the existing return statement:

```dart
@override
Widget build(BuildContext context) {
  // Handle voice messages with dedicated widget
  if (message.messageType == MessageType.voice) {
    return VoiceMessageBubble(
      message: message,
      isMine: isMine,
    );
  }

  // Handle ping messages
  if (message.messageType == MessageType.ping) {
    // ... existing ping handling
  }

  // Handle text messages (existing code)
  final isDark = RpgTheme.isDark(context);
  // ... rest of existing text message bubble
}
```

**Step 3: Test voice message display**

Run app, send voice message, verify VoiceMessageBubble appears with play button.

**Step 4: Commit**

```bash
git add frontend/lib/widgets/chat_message_bubble.dart
git commit -m "feat(frontend): integrate VoiceMessageBubble in ChatMessageBubble

- Route VOICE messageType to VoiceMessageBubble widget
- Keep existing text/ping message rendering

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 4.3: Add waveform visualization to VoiceMessageBubble

**Files:**
- Modify: `frontend/lib/widgets/voice_message_bubble.dart`

**Step 1: Add waveform visualization**

Replace the waveform placeholder in build():

```dart
// Waveform with progress
Expanded(
  child: _duration.inMilliseconds > 0
      ? CustomPaint(
          painter: _WaveformPainter(
            progress: _position.inMilliseconds / _duration.inMilliseconds,
            color: borderColor,
          ),
          size: const Size(double.infinity, 40),
        )
      : Container(
          height: 40,
          color: Colors.grey.withOpacity(0.1),
        ),
),
```

**Step 2: Add CustomPainter class at end of file**

```dart
class _WaveformPainter extends CustomPainter {
  final double progress;
  final Color color;

  _WaveformPainter({
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.3)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final paintFilled = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    // Generate random-looking waveform (in real impl, use actual audio data)
    final barCount = 50;
    final barWidth = size.width / barCount;

    for (int i = 0; i < barCount; i++) {
      // Pseudo-random height based on index (deterministic for same message)
      final heightFactor = ((i * 7) % 10) / 10.0;
      final barHeight = size.height * 0.2 + (size.height * 0.6 * heightFactor);

      final x = i * barWidth + barWidth / 2;
      final y1 = (size.height - barHeight) / 2;
      final y2 = y1 + barHeight;

      // Use filled paint if before progress, else unfilled
      final currentPaint = (i / barCount) <= progress ? paintFilled : paint;

      canvas.drawLine(Offset(x, y1), Offset(x, y2), currentPaint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
```

**Step 3: Test waveform animation**

Play voice message, verify waveform fills as audio plays.

**Step 4: Commit**

```bash
git add frontend/lib/widgets/voice_message_bubble.dart
git commit -m "feat(frontend): add waveform visualization to VoiceMessageBubble

- CustomPainter draws waveform bars
- Progress fills waveform as audio plays
- Deterministic pseudo-random heights (real audio data in future)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Phase 5: Error Handling & Polish

### Task 5.1: Add retry button for failed voice uploads

**Files:**
- Modify: `frontend/lib/providers/chat_provider.dart`
- Modify: `frontend/lib/widgets/chat_message_bubble.dart`

**Step 1: Add retryVoiceMessage to ChatProvider**

```dart
Future<void> retryVoiceMessage(String tempId) async {
  final message = _messages.firstWhere(
    (m) => m.tempId == tempId,
    orElse: () => throw Exception('Message not found'),
  );

  if (message.messageType != MessageType.voice) {
    throw Exception('Not a voice message');
  }

  if (message.deliveryStatus != MessageDeliveryStatus.failed) {
    return; // Already sent
  }

  // Get recipientId from conversation
  final conversation = _conversations.firstWhere(
    (c) => c.id == message.conversationId,
  );

  final recipientId = conversation.userOne.id == _currentUserId
      ? conversation.userTwo.id
      : conversation.userOne.id;

  // Update status to SENDING
  final index = _messages.indexWhere((m) => m.tempId == tempId);
  if (index != -1) {
    _messages[index] = _messages[index].copyWith(
      deliveryStatus: MessageDeliveryStatus.sending,
    );
    notifyListeners();
  }

  // Re-attempt upload using cached local file
  await sendVoiceMessage(
    recipientId: recipientId,
    localAudioPath: message.mediaUrl!, // Still has local path
    duration: message.mediaDuration ?? 0,
    conversationId: message.conversationId,
  );
}
```

**Step 2: Update ChatMessageBubble to show retry button**

In chat_message_bubble.dart, add after delivery icon logic:

```dart
Widget _buildDeliveryIcon() {
  if (!isMine) return const SizedBox.shrink();

  if (message.deliveryStatus == MessageDeliveryStatus.failed) {
    return const Icon(Icons.error, size: 12, color: Colors.red);
  }

  // ... existing delivery icon logic
}

Widget? _buildRetryButton(BuildContext context) {
  if (!isMine || message.deliveryStatus != MessageDeliveryStatus.failed) {
    return null;
  }

  return TextButton.icon(
    onPressed: () {
      final chat = Provider.of<ChatProvider>(context, listen: false);
      if (message.tempId != null) {
        chat.retryVoiceMessage(message.tempId!);
      }
    },
    icon: const Icon(Icons.refresh, size: 16),
    label: const Text('Retry'),
    style: TextButton.styleFrom(
      foregroundColor: Colors.red,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    ),
  );
}
```

**Step 3: Add retry button to column in build()**

Add after content text:

```dart
Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(displayContent, style: TextStyle(...)),
    if (_buildRetryButton(context) != null) ...[
      const SizedBox(height: 4),
      _buildRetryButton(context)!,
    ],
    // ... rest of existing code
  ],
)
```

**Step 4: Test retry flow**

Simulate network error (turn off wifi), send voice → should fail → tap retry → should succeed.

**Step 5: Commit**

```bash
git add frontend/lib/providers/chat_provider.dart frontend/lib/widgets/chat_message_bubble.dart
git commit -m "feat(frontend): add retry button for failed voice uploads

- Show red error icon on failed voice messages
- Add retry button below failed messages
- retryVoiceMessage re-uploads using cached local file

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 5.2: Handle expired voice messages

**Files:**
- Modify: `frontend/lib/widgets/voice_message_bubble.dart`

**Step 1: Add expiration check in _loadAndPlayAudio**

```dart
Future<void> _loadAndPlayAudio() async {
  // Check if message expired
  if (widget.message.expiresAt != null) {
    final now = DateTime.now();
    if (widget.message.expiresAt!.isBefore(now)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Audio no longer available')),
        );
      }
      return;
    }
  }

  setState(() {
    _isLoading = true;
  });

  // ... rest of existing code
}
```

**Step 2: Gray out play button for expired messages**

Update build method:

```dart
IconButton(
  icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
  onPressed: _isExpired() ? null : _togglePlayPause,  // ← disable if expired
  iconSize: 32,
  color: _isExpired() ? Colors.grey : null,
),
```

Add helper method:

```dart
bool _isExpired() {
  if (widget.message.expiresAt == null) return false;
  return widget.message.expiresAt!.isBefore(DateTime.now());
}
```

**Step 3: Commit**

```bash
git add frontend/lib/widgets/voice_message_bubble.dart
git commit -m "feat(frontend): handle expired voice messages

- Check expiration before loading audio
- Gray out play button for expired messages
- Show 'Audio no longer available' message

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 5.3: Add visual polish to VoiceRecordingOverlay

**Files:**
- Modify: `frontend/lib/widgets/voice_recording_overlay.dart`

**Step 1: Add waveform visualization during recording**

This requires audio_waveforms RecorderController. Update overlay to use it:

```dart
import 'package:audio_waveforms/audio_waveforms.dart';

class _VoiceRecordingOverlayState extends State<VoiceRecordingOverlay> {
  // ... existing fields
  RecorderController? _recorderController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(...);

    // Initialize waveform controller
    _recorderController = RecorderController();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _recorderController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ... existing code

    // Replace waveform placeholder:
    if (_recorderController != null)
      AudioWaveforms(
        size: Size(MediaQuery.of(context).size.width * 0.8, 100),
        recorderController: _recorderController!,
        waveStyle: WaveStyle(
          waveColor: Colors.white,
          showDurationLabel: false,
          spacing: 8.0,
          showBottom: false,
          extendWaveform: true,
          showMiddleLine: false,
        ),
      )
    else
      Container(
        height: 100,
        width: MediaQuery.of(context).size.width * 0.8,
        color: Colors.grey.withOpacity(0.2),
      ),
```

**Step 2: Pass recorderController from ChatInputBar**

This requires refactoring VoiceRecordingOverlay to receive controller as prop. Alternatively, keep overlay simple with placeholder.

**For MVP: Keep placeholder waveform**, real-time visualization can be added later.

**Step 3: Commit**

```bash
git add frontend/lib/widgets/voice_recording_overlay.dart
git commit -m "feat(frontend): improve VoiceRecordingOverlay visual polish

- Keep placeholder for real-time waveform (future enhancement)
- Existing timer, mic animation, swipe gesture working

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Phase 6: Testing & Documentation

### Task 6.1: Update CLAUDE.md with voice messages

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Add VOICE to MessageType in section 12**

Find "Chat Screen Redesign (2026-02-04)" and update MessageType list:

```markdown
- **Message Types:** TEXT, PING, IMAGE, DRAWING, VOICE
```

**Step 2: Add new section 15: Voice Messages Feature**

Add before "## 16. Recent Changes":

```markdown
---

## 15. Voice Messages (2026-02-15)

Full-featured voice messaging with Telegram-like UX.

### Recording
- **Hold mic button** (bottom right, when text field empty) to record
- **Max duration:** 2 minutes (auto-stop), **min duration:** 1 second (auto-cancel)
- **Visual feedback:** VoiceRecordingOverlay with timer, waveform, swipe-to-cancel
- **Audio format:** AAC/M4A (record package, ~50KB/min)
- **Permissions:** permission_handler (mobile), browser API (web)

### Upload & Storage
- **Optimistic UI:** Message appears instantly, upload in background
- **Backend endpoint:** POST /messages/voice (multipart, max 10MB)
- **Storage:** Cloudinary with TTL (disappearing timer + 1h buffer)
- **Auto-delete:** Cloudinary expires_at deletes file when message expires

### Playback
- **Player:** just_audio (cross-platform)
- **UI:** Play/pause, waveform with progress, scrub slider, speed toggle (1x/1.5x/2x)
- **Lazy download:** Audio downloaded on first play, cached locally (audio_cache/ folder)
- **Expired handling:** Gray out play button, show "Audio no longer available"

### Error Handling
- **Upload failure:** Show red error icon, retry button (keeps local file for retry)
- **Permission denied:** Top snackbar with instructions
- **Recording < 1s:** Auto-cancel, show "Hold longer to record"

### Backend Components
- **CloudinaryService.uploadVoiceMessage():** Upload with TTL, extract duration
- **POST /messages/voice:** Multipart upload, returns mediaUrl, publicId, duration
- **WebSocket:** Reuses sendMessage event with messageType: 'VOICE', mediaUrl, mediaDuration

### Frontend Components
- **VoiceRecordingOverlay:** Full-screen recording UI with timer, waveform, swipe-to-cancel
- **VoiceMessageBubble:** Playback UI with just_audio player, waveform visualization
- **ChatInputBar:** Long-press mic to record, permission handling
- **ChatProvider.sendVoiceMessage():** Optimistic upload, background sync, retry logic

### Files Modified
- Backend: cloudinary.service.ts, messages.controller.ts, messages.module.ts, chat.dto.ts, chat-message.service.ts, messages.service.ts, message.entity.ts
- Frontend: pubspec.yaml, message_model.dart, voice_recording_overlay.dart, voice_message_bubble.dart, chat_input_bar.dart, chat_message_bubble.dart, chat_provider.dart, api_service.dart, socket_service.dart

### Design & Implementation Docs
- Design: docs/plans/2026-02-15-voice-messages-design.md
- Implementation: docs/plans/2026-02-15-voice-messages-implementation.md
```

**Step 3: Update Recent Changes section**

Add at top of Recent Changes:

```markdown
**2026-02-15:**

- **Voice messages feature (2026-02-15):** Full Telegram-like voice messaging. Hold mic button to record (max 2min, min 1s), swipe left to cancel. Optimistic UI with background upload to Cloudinary (TTL auto-delete for disappearing messages). Rich playback UI with waveform, scrub slider, speed toggle (1x/1.5x/2x). Cross-platform (web + mobile). Files: see §15. Design doc: docs/plans/2026-02-15-voice-messages-design.md.
```

**Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with voice messages feature

- Add section 15: Voice Messages (2026-02-15)
- Document recording, upload, playback, error handling
- List all modified files
- Add to Recent Changes

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 6.2: Manual testing checklist

**Files:**
- Create: `docs/testing/voice-messages-manual-test.md`

**Step 1: Create testing document**

```markdown
# Voice Messages - Manual Testing Checklist

**Date:** 2026-02-15
**Tester:** ___________

## Mobile (Android)

### Recording
- [ ] Mic permission prompt appears on first use
- [ ] Long-press mic button starts recording
- [ ] Timer increments every second (0:00 → 0:05 → ...)
- [ ] Waveform animates during recording (or placeholder visible)
- [ ] Swipe left > 100px cancels recording
- [ ] Recording < 1s shows "Hold longer to record" toast
- [ ] Recording reaches 2:00 → auto-stops and sends
- [ ] Yellow timer at 1:50, red timer at 1:58

### Upload & Send
- [ ] Message appears immediately after release (optimistic)
- [ ] Delivery status shows clock icon (SENDING)
- [ ] Upload completes in background (UI responsive)
- [ ] Status updates to checkmark (SENT) after upload
- [ ] Cloudinary URL replaces local file path

### Playback
- [ ] Tap play button → downloads audio (loading spinner)
- [ ] Audio plays smoothly, no glitches
- [ ] Waveform fills as audio plays
- [ ] Scrub slider seeks to position
- [ ] Speed toggle cycles (1x → 1.5x → 2x → 1x)
- [ ] Pause/resume works correctly
- [ ] Second play uses cached file (instant, no download)

### Error Handling
- [ ] Turn off wifi → send voice → shows failed status (red icon)
- [ ] Tap retry button → re-uploads successfully
- [ ] Expired voice message → play button grayed out, "Audio no longer available"
- [ ] Deny mic permission → shows "Microphone permission required"

### Disappearing Messages
- [ ] Voice sent with 30s timer → expires after 30s
- [ ] Expired voice removed from UI (removeExpiredMessages)
- [ ] Check Cloudinary: file deleted after TTL (~31-32 min, 1h buffer)

---

## Mobile (iOS)

Repeat all Android tests.

---

## Web (Chrome)

### Recording
- [ ] Browser mic permission prompt appears
- [ ] Long-press mic button starts recording
- [ ] Timer increments correctly
- [ ] Swipe-to-cancel works with mouse drag
- [ ] Recording < 1s auto-cancels

### Upload & Send
- [ ] WebM/Opus audio uploads to backend
- [ ] Backend converts to M4A via Cloudinary
- [ ] Optimistic UI works (instant message display)

### Playback
- [ ] Play button works in browser
- [ ] just_audio web player handles M4A format
- [ ] Speed toggle works
- [ ] Scrubbing works

---

## Cross-Platform

- [ ] Send voice from mobile → receive on web → playback works
- [ ] Send voice from web → receive on mobile → playback works
- [ ] Voice appears in conversation preview (last message)
- [ ] Unread badge increments for voice messages
- [ ] Voice respects disappearing timer (same as text)

---

## Edge Cases

- [ ] Send 3 voices in quick succession → all upload in order (FIFO)
- [ ] Navigate away during recording → auto-cancel (no crash)
- [ ] Navigate away during upload → upload completes in background
- [ ] Delete conversation while voice uploading → upload canceled, no orphaned message

---

## Notes

_Add any bugs or observations here_
```

**Step 2: Commit**

```bash
git add docs/testing/voice-messages-manual-test.md
git commit -m "docs: add manual testing checklist for voice messages

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 6.3: Write README for voice messages

**Files:**
- Create: `docs/features/voice-messages.md`

**Step 1: Create feature README**

```markdown
# Voice Messages Feature

## Overview

Full-featured voice messaging with Telegram-like UX: hold mic to record, swipe to cancel, instant message display, background upload to Cloudinary with auto-delete TTL, and rich playback controls.

## User Flow

### Sending a Voice Message

1. **Start Recording**
   - Ensure text field is empty
   - Long-press mic button (bottom right)
   - Mic permission prompt appears (first time only)
   - VoiceRecordingOverlay shows with timer

2. **While Recording**
   - Timer counts up (0:00 → 2:00 max)
   - Waveform animates in real-time
   - Yellow timer at 1:50 (approaching limit)
   - Red timer at 1:58 (almost at limit)
   - Swipe left > 100px to cancel

3. **Finish Recording**
   - Release button when done
   - If < 1 second: auto-cancel, toast "Hold longer to record"
   - If >= 1 second: message sent

4. **Sending**
   - Message appears instantly in chat (optimistic UI)
   - Clock icon shows SENDING status
   - Upload happens in background (non-blocking)
   - Checkmark shows SENT after upload completes

### Receiving & Playing a Voice Message

1. **Receive Message**
   - Voice bubble appears in chat
   - Play button + waveform + duration visible
   - Audio NOT downloaded yet (lazy load)

2. **Play Audio**
   - Tap play button
   - Loading spinner while downloading
   - Audio cached locally for repeat plays
   - Waveform fills as audio plays

3. **Playback Controls**
   - **Play/Pause:** Toggle playback
   - **Scrub Slider:** Seek to position
   - **Speed Toggle:** 1x / 1.5x / 2x
   - **Progress:** Shows current time / total duration

## Technical Details

### Audio Format
- **Recording:** AAC/M4A (record package)
- **Bitrate:** 128kbps
- **Sample Rate:** 44.1kHz
- **Avg Size:** ~50KB/min (1MB for 2min max)

### Storage & Expiration
- **Upload:** POST /messages/voice (multipart, max 10MB)
- **Storage:** Cloudinary (voice-messages/ folder)
- **TTL:** Disappearing timer + 1h buffer (auto-delete)
- **Cache:** Local audio_cache/ folder for repeat playback

### Permissions
- **Mobile:** permission_handler (request on first use)
- **Web:** Browser API (automatic prompt)

## Error Handling

### Upload Failures
- **Network error:** Message shows red error icon + retry button
- **Retry:** Re-uploads using cached local file
- **Max retries:** User can retry indefinitely

### Playback Failures
- **Download error:** Shows "Failed to load audio"
- **Expired message:** Play button grayed out, "Audio no longer available"
- **Codec unsupported:** Cloudinary can transcode on-the-fly

### Edge Cases
- **Recording < 1s:** Auto-cancel, show toast
- **Recording = 2min:** Auto-stop and send
- **Permission denied:** Show instructions
- **Navigate away:** Auto-cancel recording

## Development

### Backend Endpoints
- `POST /messages/voice` - Upload voice message

### WebSocket Events
- `sendMessage` (with messageType: 'VOICE')
- `messageSent` / `newMessage` (includes mediaUrl, mediaDuration)

### Frontend Components
- `VoiceRecordingOverlay` - Recording UI
- `VoiceMessageBubble` - Playback UI
- `ChatInputBar` - Mic button with long-press
- `ChatProvider.sendVoiceMessage()` - Upload logic

### Dependencies
```yaml
record: ^5.0.0  # Recording
audio_waveforms: ^1.0.5  # Visualization
permission_handler: ^11.0.0  # Permissions
just_audio: ^0.9.36  # Playback
```

## Testing

See `docs/testing/voice-messages-manual-test.md` for full checklist.

Quick smoke test:
1. Long-press mic → record 5s → release → message appears
2. Tap play on received voice → audio plays with waveform
3. Toggle speed 1x → 1.5x → 2x → sounds faster
4. Swipe left during recording → cancels, no message sent

## Future Enhancements

- Real-time waveform during recording (audio_waveforms RecorderController)
- Audio transcription (speech-to-text API)
- Noise reduction / echo cancellation
- Draft management (save interrupted recordings)
- Voice message forwarding

## Related Docs

- Design: `docs/plans/2026-02-15-voice-messages-design.md`
- Implementation: `docs/plans/2026-02-15-voice-messages-implementation.md`
- Testing: `docs/testing/voice-messages-manual-test.md`
```

**Step 2: Commit**

```bash
git add docs/features/voice-messages.md
git commit -m "docs: add voice messages feature README

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Execution Summary

**Total Tasks:** 18 (6 phases)
- Phase 1: Backend Foundation (5 tasks)
- Phase 2: Frontend Recording (5 tasks)
- Phase 3: Frontend Upload & Optimistic UI (3 tasks)
- Phase 4: Frontend Playback (3 tasks)
- Phase 5: Error Handling & Polish (3 tasks)
- Phase 6: Testing & Documentation (3 tasks)

**Estimated Time:** 4-6 hours (assuming 15-20 min per task)

**Testing Strategy:**
- Incremental testing after each phase
- Manual testing checklist (mobile + web + cross-platform)
- Focus on edge cases (permissions, errors, expiration)

**Success Criteria:**
- ✅ Record voice by holding mic (max 2min, min 1s)
- ✅ Swipe left to cancel
- ✅ Optimistic UI (instant message display)
- ✅ Background upload (non-blocking)
- ✅ Playback with waveform + speed toggle
- ✅ Cloudinary TTL auto-delete for disappearing messages
- ✅ Cross-platform (web + mobile)
- ✅ Retry on upload failure

---

**Next Steps:** Choose execution approach (subagent-driven or parallel session).
