# Chat Screen Redesign - Telegram/Wire Inspired UI

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Redesign chat screen with Telegram/Wire-inspired UI including delivery indicators, disappearing messages, rich input controls, and action tiles (ping, camera, drawing, GIF).

**Architecture:** Extend MessageModel with deliveryStatus and expiresAt fields, create new widgets for action tiles and input controls, add WebSocket events for delivery tracking and ping, integrate audio playback for ping sound, implement canvas drawing with basic paint tools.

**Tech Stack:** Flutter, Socket.IO, NestJS, TypeORM, PostgreSQL, just_audio (audio), flutter_colorpicker (optional), Cloudinary (image upload)

---

## ⚠️ IMPORTANT IMPLEMENTATION NOTES (Code Review Fixes)

**These corrections must be applied during implementation based on code review findings:**

1. **Optimistic Message ID (Task 2.2, Step 6-7):**
   - Don't match by `content` (fails for duplicate texts)
   - Add `tempId` field to payload: `sendMessage` emits `{ recipientId, content, tempId: DateTime.now().millisecondsSinceEpoch }`
   - Backend echoes `tempId` in `messageSent` payload
   - Replace optimistic message by matching `tempId` instead of `content`

2. **SocketService Methods (Task 2.2):**
   - Add `void emitMessageDelivered(int messageId)` method
   - Update `sendMessage(recipientId, content, {int? expiresIn})` signature (add optional `expiresIn`)
   - Add `void sendPing(int recipientId)` method
   - In `connect()` signature: add named params `required Function(Map) onMessageDelivered, required Function(Map) onPingReceived`

3. **ChatProvider Token Storage (Task 2.2, Task 5.2):**
   - In `connect(token, userId)` save: `_token = token` (not just `_tokenForReconnect`)
   - Use `_token` in `sendImageMessage` for API calls

4. **ApiService Constructor (Task 5.2):**
   - Don't call `ApiService()` without args
   - Use: `ApiService(baseUrl: AppConfig.baseUrl).uploadImageMessage(_token, ...)`
   - Or inject ApiService in ChatProvider constructor

5. **CloudinaryService.uploadImage (Task 5.1):**
   - Add new method: `async uploadImage(buffer: Buffer, mimeType: string, options?: { folder?: string }): Promise<{ url: string, publicId: string }>`
   - Use folder `'messages/'` for message images (vs `'avatars/'` for profiles)

6. **MessagesService Dependencies (Task 5.1):**
   - In `MessagesModule.imports`: add `FriendsModule`, `ConversationsModule`, `UsersModule`
   - Inject in `MessagesService` constructor: `FriendsService`, `ConversationsService`, `UsersService`
   - Or keep friend/conversation logic in `ChatMessageService` and call simple `MessagesService.create(...)`

7. **Multer Memory Storage (Task 5.1):**
   - Configure `MulterModule.register({ storage: memoryStorage() })` in `MessagesModule` or `AppModule`
   - Check `if (!file?.buffer)` before passing to Cloudinary

8. **Action Tiles Guard (Task 3.3):**
   - At start of `_sendPing`, `_openCamera`, `_openDrawing`:
   ```dart
   if (chat.activeConversationId == null) {
     ScaffoldMessenger.of(context).showSnackBar(
       const SnackBar(content: Text('Open a conversation first')),
     );
     return;
   }
   ```

9. **Drawing Canvas Capture (Task 5.2):**
   - Wrap `toImage()` call in `WidgetsBinding.instance.addPostFrameCallback((_) { ... })` to ensure layout is ready

10. **EmojiPicker Config (Task 3.2):**
    - Check `emoji_picker_flutter` version on pub.dev
    - API may use `EmojiPickerConfig` instead of `Config` in newer versions
    - Adjust code snippet if needed

11. **messageHistory Payload (Task 1.1):**
    - In `handleGetMessages` (backend), extend mapowanie to include new fields:
    ```typescript
    messages.map(m => ({
      ...existing fields...,
      deliveryStatus: m.deliveryStatus || 'SENT',
      expiresAt: m.expiresAt,
      messageType: m.messageType || 'TEXT',
      mediaUrl: m.mediaUrl,
    }))
    ```

12. **PingEffectOverlay mounted check (Task 3.5):**
    - In `_controller.forward().then((_) { ... })`: add `if (mounted) widget.onComplete();`

13. **CLAUDE.md Path (Task 7.1):**
    - File is `CLAUDE.md` in root, not `docs/CLAUDE.md`
    - Edit: `C:\Users\Lentach\desktop\mvp-chat-app\CLAUDE.md`

14. **Message Entity Import Paths:**
    - All fixed: use `backend/src/messages/message.entity.ts` (not `entities/message.entity.ts`)
    - Import User: `../users/user.entity`, Conversation: `../conversations/conversation.entity`

**Apply these during implementation or Phase 1-2 setup. Marked with ⚠️ in relevant task steps.**

---

## Current State Analysis

**Existing:**
- Basic chat screen with AppBar (back, avatar+username, menu)
- ChatInputBar with TextField + send button
- ChatMessageBubble with content + timestamp
- MessageModel: id, content, senderId, conversationId, createdAt
- Socket.IO: sendMessage, getMessages events
- Image upload: ApiService.uploadProfilePicture (multipart, Cloudinary)
- Theme: RpgTheme with dark/light colors

**Missing:**
- Delivery status tracking (clock/✓/✓✓)
- Disappearing messages (timer display + auto-delete)
- Emoji picker
- Mic/Send toggle
- Action tiles (timer, ping, camera, drawing, GIF)
- Ping feature (visual effect + sound)
- Drawing canvas
- Audio playback

---

## Phase 1: Backend - Message Model Extensions

### Task 1.1: Add Message Delivery Status & Expiration

**Files:**
- Modify: `backend/src/messages/message.entity.ts`
- Modify: `backend/src/messages/messages.service.ts`
- Modify: `backend/src/chat/services/chat-message.service.ts`
- Modify: `backend/src/chat/dto/chat.dto.ts`

**Step 1: Extend Message entity with delivery status and expiration**

File: `backend/src/messages/message.entity.ts`

```typescript
import { Entity, PrimaryGeneratedColumn, Column, ManyToOne, JoinColumn, CreateDateColumn } from 'typeorm';
import { User } from '../users/user.entity';
import { Conversation } from '../conversations/conversation.entity';

export enum MessageDeliveryStatus {
  SENDING = 'SENDING',
  SENT = 'SENT',
  DELIVERED = 'DELIVERED',
}

@Entity('messages')
export class Message {
  @PrimaryGeneratedColumn()
  id: number;

  @Column({ type: 'text' })
  content: string;

  @Column({
    type: 'enum',
    enum: MessageDeliveryStatus,
    default: MessageDeliveryStatus.SENT,
  })
  deliveryStatus: MessageDeliveryStatus;

  @Column({ type: 'timestamp', nullable: true })
  expiresAt: Date | null;

  @ManyToOne(() => User)
  @JoinColumn({ name: 'sender_id' })
  sender: User;

  @ManyToOne(() => Conversation)
  @JoinColumn({ name: 'conversation_id' })
  conversation: Conversation;

  @CreateDateColumn()
  createdAt: Date;
}
```

**Step 2: Update ChatMessageService to include new fields**

File: `backend/src/chat/services/chat-message.service.ts`

Find `handleSendMessage` method, update message creation:

```typescript
async handleSendMessage(
  client: Socket,
  data: SendMessageDto,
  server: Server,
  onlineUsers: Map<number, string>,
) {
  const user = client.data.user;
  const { recipientId, content, expiresIn } = data; // Add expiresIn (seconds)

  // ... existing friend check and conversation logic ...

  const expiresAt = expiresIn
    ? new Date(Date.now() + expiresIn * 1000)
    : null;

  const message = this.messagesRepo.create({
    content,
    sender: { id: user.id },
    conversation: { id: conversation.id },
    deliveryStatus: MessageDeliveryStatus.SENT,
    expiresAt,
  });
  await this.messagesRepo.save(message);

  const payload = {
    id: message.id,
    content: message.content,
    senderId: user.id,
    senderEmail: user.email,
    senderUsername: user.username,
    conversationId: conversation.id,
    createdAt: message.createdAt,
    deliveryStatus: message.deliveryStatus,
    expiresAt: message.expiresAt,
  };

  client.emit('messageSent', payload);

  const recipientSocketId = onlineUsers.get(recipientId);
  if (recipientSocketId) {
    server.to(recipientSocketId).emit('newMessage', payload);
  }
}
```

**Step 3: Update SendMessageDto with expiresIn field**

File: `backend/src/chat/dto/chat.dto.ts`

```typescript
export class SendMessageDto {
  @IsInt()
  recipientId: number;

  @IsString()
  @IsNotEmpty()
  content: string;

  @IsInt()
  @IsOptional()
  expiresIn?: number; // Seconds until expiration
}
```

**Step 4: Add messageDelivered event handler**

File: `backend/src/chat/services/chat-message.service.ts`

Add new method:

```typescript
async handleMessageDelivered(
  client: Socket,
  data: { messageId: number },
  server: Server,
  onlineUsers: Map<number, string>,
) {
  const user = client.data.user;
  const message = await this.messagesRepo.findOne({
    where: { id: data.messageId },
    relations: ['sender', 'conversation'],
  });

  if (!message) {
    client.emit('error', { message: 'Message not found' });
    return;
  }

  // Update status to DELIVERED
  message.deliveryStatus = MessageDeliveryStatus.DELIVERED;
  await this.messagesRepo.save(message);

  // Notify sender that message was delivered
  const senderSocketId = onlineUsers.get(message.sender.id);
  if (senderSocketId) {
    server.to(senderSocketId).emit('messageDelivered', {
      messageId: message.id,
      deliveryStatus: MessageDeliveryStatus.DELIVERED,
    });
  }
}
```

**Step 5: Register messageDelivered event in gateway**

File: `backend/src/chat/chat.gateway.ts`

Add in `handleMessage` method:

```typescript
@SubscribeMessage('messageDelivered')
handleMessageDelivered(
  @ConnectedSocket() client: Socket,
  @MessageBody() data: { messageId: number },
) {
  return this.messageService.handleMessageDelivered(
    client,
    data,
    this.server,
    this.onlineUsers,
  );
}
```

**Step 6: Database migration**

Run:
```bash
# Backend will auto-sync with TypeORM synchronize:true
# In production, generate migration:
# npm run migration:generate -- -n AddDeliveryStatusAndExpiration
```

**Step 7: Test backend changes**

Manual test via Socket.IO client:
```javascript
// Send message with expiration
socket.emit('sendMessage', {
  recipientId: 2,
  content: 'Test message',
  expiresIn: 3600 // 1 hour
});

// Listen for delivery
socket.on('messageDelivered', (data) => {
  console.log('Delivered:', data.messageId, data.deliveryStatus);
});
```

Expected: Message created with expiresAt timestamp, deliveryStatus = SENT

**Step 8: Commit backend changes**

```bash
git add backend/src/messages/entities/message.entity.ts
git add backend/src/chat/services/chat-message.service.ts
git add backend/src/chat/dto/chat.dto.ts
git add backend/src/chat/chat.gateway.ts
git commit -m "feat(backend): add message delivery status and expiration fields

- Add MessageDeliveryStatus enum (SENDING, SENT, DELIVERED)
- Add expiresAt nullable timestamp to Message entity
- Update SendMessageDto with optional expiresIn field
- Add messageDelivered WebSocket event handler
- Include deliveryStatus and expiresAt in message payloads"
```

---

### Task 1.2: Add Ping Message Type

**Files:**
- Modify: `backend/src/messages/entities/message.entity.ts`
- Modify: `backend/src/chat/services/chat-message.service.ts`
- Create: `backend/src/chat/dto/send-ping.dto.ts`

**Step 1: Add messageType column to Message entity**

File: `backend/src/messages/entities/message.entity.ts`

```typescript
export enum MessageType {
  TEXT = 'TEXT',
  PING = 'PING',
  IMAGE = 'IMAGE',
  DRAWING = 'DRAWING',
  // Future: VOICE, VIDEO, etc.
}

@Entity('messages')
export class Message {
  // ... existing fields ...

  @Column({
    type: 'enum',
    enum: MessageType,
    default: MessageType.TEXT,
  })
  messageType: MessageType;

  @Column({ type: 'text', nullable: true })
  mediaUrl: string | null;

  // ... rest of entity ...
}
```

**Step 2: Create SendPingDto**

File: `backend/src/chat/dto/send-ping.dto.ts`

```typescript
import { IsInt } from 'class-validator';

export class SendPingDto {
  @IsInt()
  recipientId: number;
}
```

**Step 3: Add handleSendPing method**

File: `backend/src/chat/services/chat-message.service.ts`

```typescript
async handleSendPing(
  client: Socket,
  data: SendPingDto,
  server: Server,
  onlineUsers: Map<number, string>,
) {
  const user = client.data.user;
  const { recipientId } = data;

  // Check if friends (reuse existing logic)
  const areFriends = await this.friendsService.areFriends(user.id, recipientId);
  if (!areFriends) {
    client.emit('error', { message: 'You can only ping friends' });
    return;
  }

  // Get sender and recipient User entities
  const sender = await this.usersService.findById(user.id);
  const recipient = await this.usersService.findById(recipientId);
  if (!sender || !recipient) {
    client.emit('error', { message: 'User not found' });
    return;
  }

  // Find or create conversation
  const conversation = await this.conversationsService.findOrCreate(sender, recipient);

  // Create ping message
  const message = this.messagesRepo.create({
    content: '', // Empty content for ping
    sender: { id: user.id },
    conversation: { id: conversation.id },
    messageType: MessageType.PING,
    deliveryStatus: MessageDeliveryStatus.SENT,
    expiresAt: null, // Pings don't expire
  });
  await this.messagesRepo.save(message);

  const payload = {
    id: message.id,
    content: '',
    senderId: user.id,
    senderEmail: user.email,
    senderUsername: user.username,
    conversationId: conversation.id,
    createdAt: message.createdAt,
    messageType: MessageType.PING,
    deliveryStatus: message.deliveryStatus,
    expiresAt: null,
  };

  client.emit('pingSent', payload);

  const recipientSocketId = onlineUsers.get(recipientId);
  if (recipientSocketId) {
    server.to(recipientSocketId).emit('newPing', payload);
  }
}
```

**Step 4: Register sendPing event in gateway**

File: `backend/src/chat/chat.gateway.ts`

```typescript
import { SendPingDto } from './dto/send-ping.dto';

@SubscribeMessage('sendPing')
handleSendPing(
  @ConnectedSocket() client: Socket,
  @MessageBody() data: SendPingDto,
) {
  return this.messageService.handleSendPing(
    client,
    data,
    this.server,
    this.onlineUsers,
  );
}
```

**Step 5: Test ping event**

Manual test:
```javascript
socket.emit('sendPing', { recipientId: 2 });
socket.on('pingSent', (data) => console.log('Ping sent:', data));
socket.on('newPing', (data) => console.log('Ping received:', data));
```

Expected: Ping message created with messageType=PING, empty content

**Step 6: Commit ping changes**

```bash
git add backend/src/messages/entities/message.entity.ts
git add backend/src/chat/services/chat-message.service.ts
git add backend/src/chat/dto/send-ping.dto.ts
git add backend/src/chat/chat.gateway.ts
git commit -m "feat(backend): add ping message type

- Add MessageType enum (TEXT, PING, IMAGE, DRAWING)
- Add mediaUrl nullable field to Message entity
- Create SendPingDto and handleSendPing service method
- Register sendPing WebSocket event
- Emit pingSent to sender, newPing to recipient"
```

---

## Phase 2: Frontend - Message Model & Provider Updates

### Task 2.1: Extend MessageModel with New Fields

**Files:**
- Modify: `frontend/lib/models/message_model.dart`

**Step 1: Add deliveryStatus, expiresAt, messageType, mediaUrl fields**

File: `frontend/lib/models/message_model.dart`

```dart
enum MessageDeliveryStatus {
  sending,
  sent,
  delivered,
}

enum MessageType {
  text,
  ping,
  image,
  drawing,
}

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
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    return MessageModel(
      id: json['id'] as int,
      content: json['content'] as String? ?? '',
      senderId: json['senderId'] as int,
      senderEmail: json['senderEmail'] as String,
      senderUsername: json['senderUsername'] as String?,
      conversationId: json['conversationId'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
      deliveryStatus: _parseDeliveryStatus(json['deliveryStatus'] as String?),
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'] as String)
          : null,
      messageType: _parseMessageType(json['messageType'] as String?),
      mediaUrl: json['mediaUrl'] as String?,
    );
  }

  // Public method for parsing delivery status from other files
  static MessageDeliveryStatus parseDeliveryStatus(String? status) {
    switch (status?.toUpperCase()) {
      case 'SENDING':
        return MessageDeliveryStatus.sending;
      case 'SENT':
        return MessageDeliveryStatus.sent;
      case 'DELIVERED':
        return MessageDeliveryStatus.delivered;
      default:
        return MessageDeliveryStatus.sent;
    }
  }

  static MessageType _parseMessageType(String? type) {
    switch (type?.toUpperCase()) {
      case 'PING':
        return MessageType.ping;
      case 'IMAGE':
        return MessageType.image;
      case 'DRAWING':
        return MessageType.drawing;
      default:
        return MessageType.text;
    }
  }

  MessageModel copyWith({
    MessageDeliveryStatus? deliveryStatus,
    DateTime? expiresAt,
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
      mediaUrl: mediaUrl,
    );
  }
}
```

**Step 2: Run Flutter tests to ensure model parsing works**

Run:
```bash
cd frontend
flutter test test/models/message_model_test.dart
```

Expected: All tests pass (or create test if missing)

**Step 3: Commit MessageModel changes**

```bash
git add frontend/lib/models/message_model.dart
git commit -m "feat(frontend): extend MessageModel with delivery status, expiration, type, media

- Add MessageDeliveryStatus enum (sending, sent, delivered)
- Add MessageType enum (text, ping, image, drawing)
- Add expiresAt nullable DateTime field
- Add mediaUrl nullable String field
- Add fromJson parsing for new fields with fallback defaults
- Add copyWith method for delivery status updates"
```

---

### Task 2.2: Update ChatProvider with Delivery Tracking & Ping

**Files:**
- Modify: `frontend/lib/providers/chat_provider.dart`
- Modify: `frontend/lib/services/socket_service.dart`

**Step 1: Add messageDelivered listener in SocketService**

File: `frontend/lib/services/socket_service.dart`

Find `connect()` method, add listener:

```dart
void connect(
  String token,
  Function(Map<String, dynamic>) onMessageReceived,
  Function(List<dynamic>) onMessageHistory,
  Function(List<dynamic>) onConversationsList,
  Function(Map<String, dynamic>) onConversationCreated,
  // ... existing callbacks ...
  Function(Map<String, dynamic>) onMessageDelivered, // NEW
  Function(Map<String, dynamic>) onPingReceived, // NEW
) {
  // ... existing connection logic ...

  _socket!.on('messageDelivered', (data) {
    onMessageDelivered(data as Map<String, dynamic>);
  });

  _socket!.on('newPing', (data) {
    onPingReceived(data as Map<String, dynamic>);
  });

  // ... rest of listeners ...
}
```

**Step 2: Update ChatProvider connect() to handle delivery and ping**

File: `frontend/lib/providers/chat_provider.dart`

Find `connect()` method, update SocketService call:

```dart
void connect(String token, int userId) {
  // ... existing setup ...

  _socket = SocketService();
  _socket!.connect(
    token,
    _handleIncomingMessage,
    _handleMessageHistory,
    _handleConversationsList,
    _handleConversationCreated,
    // ... existing callbacks ...
    _handleMessageDelivered, // NEW
    _handlePingReceived, // NEW
  );

  // ... rest of method ...
}
```

**Step 3: Add _handleMessageDelivered method**

File: `frontend/lib/providers/chat_provider.dart`

Add new method:

```dart
void _handleMessageDelivered(Map<String, dynamic> data) {
  final messageId = data['messageId'] as int;
  final status = data['deliveryStatus'] as String;

  // Update message in _messages list
  final index = _messages.indexWhere((m) => m.id == messageId);
  if (index != -1) {
    _messages[index] = _messages[index].copyWith(
      deliveryStatus: MessageModel.parseDeliveryStatus(status),
    );
    notifyListeners();
  }
}
```

**Step 4: Add sendPing method**

File: `frontend/lib/providers/chat_provider.dart`

Add new method:

```dart
void sendPing(int recipientId) {
  if (_socket == null) return;
  _socket!.emit('sendPing', {'recipientId': recipientId});
}
```

**Step 5: Add _handlePingReceived method**

File: `frontend/lib/providers/chat_provider.dart`

Add new method:

```dart
void _handlePingReceived(Map<String, dynamic> data) {
  final message = MessageModel.fromJson(data);

  // Add to messages if active conversation matches
  if (_activeConversationId == message.conversationId) {
    _messages.add(message);
  }

  // Update last message
  _lastMessages[message.conversationId] = message;

  notifyListeners();
}
```

**Step 6: Update sendMessage to mark as SENDING initially**

File: `frontend/lib/providers/chat_provider.dart`

Find `sendMessage()` method, update:

```dart
void sendMessage(String content, {int? expiresIn}) {
  if (_socket == null || _activeConversationId == null) return;

  final conv = conversations.firstWhere((c) => c.id == _activeConversationId);
  final recipientId = getOtherUserId(conv);

  // Create optimistic message with SENDING status
  final tempMessage = MessageModel(
    id: -DateTime.now().millisecondsSinceEpoch, // Temporary negative ID
    content: content,
    senderId: _currentUserId,
    senderEmail: '', // Will be replaced when server confirms
    conversationId: _activeConversationId!,
    createdAt: DateTime.now(),
    deliveryStatus: MessageDeliveryStatus.sending,
    expiresAt: expiresIn != null
        ? DateTime.now().add(Duration(seconds: expiresIn))
        : null,
  );

  _messages.add(tempMessage);
  notifyListeners();

  _socket!.emit('sendMessage', {
    'recipientId': recipientId,
    'content': content,
    if (expiresIn != null) 'expiresIn': expiresIn,
  });
}
```

**Step 7: Update _handleIncomingMessage to replace temp message**

File: `frontend/lib/providers/chat_provider.dart`

Find `_handleIncomingMessage()`, update to handle messageSent:

```dart
void _handleIncomingMessage(Map<String, dynamic> data) {
  final message = MessageModel.fromJson(data);

  // If this is our own message (messageSent), replace temp optimistic message
  if (message.senderId == _currentUserId) {
    final tempIndex = _messages.indexWhere((m) => m.id < 0 && m.content == message.content);
    if (tempIndex != -1) {
      _messages.removeAt(tempIndex);
    }
  }

  // Add confirmed message
  if (_activeConversationId == message.conversationId) {
    _messages.add(message);
  }

  _lastMessages[message.conversationId] = message;
  notifyListeners();

  // Emit messageDelivered if this is incoming from other user
  if (message.senderId != _currentUserId && _socket != null) {
    _socket!.emit('messageDelivered', {'messageId': message.id});
  }
}
```

**Step 8: Test ChatProvider changes**

Manual test:
1. Send message → should appear with clock icon (SENDING)
2. Server confirms → clock changes to single ✓ (SENT)
3. Recipient opens chat → changes to ✓✓ (DELIVERED)

**Step 9: Commit ChatProvider changes**

```bash
git add frontend/lib/providers/chat_provider.dart
git add frontend/lib/services/socket_service.dart
git commit -m "feat(frontend): add delivery tracking and ping support in ChatProvider

- Add messageDelivered and newPing listeners in SocketService
- Implement _handleMessageDelivered to update message status
- Add sendPing method to emit ping events
- Add _handlePingReceived to handle incoming pings
- Update sendMessage with optimistic SENDING status
- Emit messageDelivered when receiving messages from others"
```

---

## Phase 3: Frontend - UI Components

### Task 3.1: Update ChatMessageBubble with Delivery Indicator & Timer

**Files:**
- Modify: `frontend/lib/widgets/chat_message_bubble.dart`

**Step 1: Add delivery status icon helper**

File: `frontend/lib/widgets/chat_message_bubble.dart`

Add helper method inside `ChatMessageBubble` class:

```dart
Widget _buildDeliveryIcon() {
  if (!isMine) return const SizedBox.shrink();

  IconData icon;
  Color color;

  switch (message.deliveryStatus) {
    case MessageDeliveryStatus.sending:
      icon = Icons.access_time;
      color = Colors.grey;
      break;
    case MessageDeliveryStatus.sent:
      icon = Icons.check;
      color = Colors.grey;
      break;
    case MessageDeliveryStatus.delivered:
      icon = Icons.done_all;
      color = Colors.blue;
      break;
  }

  return Icon(icon, size: 12, color: color);
}
```

**Step 2: Add timer countdown helper**

Add helper method:

```dart
String? _getTimerText() {
  if (message.expiresAt == null) return null;

  final now = DateTime.now();
  final remaining = message.expiresAt!.difference(now);

  if (remaining.isNegative) return 'Expired';

  if (remaining.inHours > 0) {
    return '${remaining.inHours}h';
  } else if (remaining.inMinutes > 0) {
    return '${remaining.inMinutes}m';
  } else {
    return '${remaining.inSeconds}s';
  }
}
```

**Step 3: Update build() to show delivery + timer**

Update the bottom row in `build()`:

```dart
@override
Widget build(BuildContext context) {
  // ... existing setup ...

  return Align(
    alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      // ... existing container setup ...
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Message content
          if (message.messageType == MessageType.text)
            Text(
              message.content,
              style: RpgTheme.bodyFont(fontSize: 14, color: textColor),
            )
          else if (message.messageType == MessageType.ping)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.campaign, size: 18, color: textColor),
                const SizedBox(width: 6),
                Text(
                  'PING!',
                  style: RpgTheme.bodyFont(
                    fontSize: 14,
                    color: textColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

          const SizedBox(height: 4),

          // Bottom row: time + delivery + timer
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _formatTime(message.createdAt),
                style: RpgTheme.bodyFont(fontSize: 10, color: timeColor),
              ),
              const SizedBox(width: 4),
              _buildDeliveryIcon(),
              if (_getTimerText() != null) ...[
                const SizedBox(width: 6),
                Icon(Icons.timer_outlined, size: 10, color: timeColor),
                const SizedBox(width: 2),
                Text(
                  _getTimerText()!,
                  style: RpgTheme.bodyFont(fontSize: 10, color: timeColor),
                ),
              ],
            ],
          ),
        ],
      ),
    ),
  );
}
```

**Step 4: Test message bubble with different states**

Manual test:
1. Send message → should show clock icon
2. Message delivered → should show ✓✓
3. Message with timer → should show countdown

**Step 5: Commit message bubble changes**

```bash
git add frontend/lib/widgets/chat_message_bubble.dart
git commit -m "feat(frontend): add delivery indicators and timer to message bubbles

- Add _buildDeliveryIcon helper (clock/✓/✓✓)
- Add _getTimerText helper for countdown display
- Update build to show delivery status for own messages
- Add ping message type display (icon + 'PING!' text)
- Show timer icon + countdown if expiresAt is set"
```

---

### Task 3.2: Redesign ChatInputBar with Telegram-style Controls

**Files:**
- Modify: `frontend/lib/widgets/chat_input_bar.dart`
- Add dependency: `emoji_picker_flutter: ^2.0.0` to `pubspec.yaml`

**Step 1: Add emoji_picker dependency**

File: `frontend/pubspec.yaml`

Add under dependencies:

```yaml
dependencies:
  # ... existing dependencies ...
  emoji_picker_flutter: ^2.0.0
```

Run:
```bash
cd frontend
flutter pub get
```

**Step 2: Rewrite ChatInputBar with attachment, emoji, mic/send toggle**

File: `frontend/lib/widgets/chat_input_bar.dart`

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import '../providers/chat_provider.dart';
import '../theme/rpg_theme.dart';

class ChatInputBar extends StatefulWidget {
  const ChatInputBar({super.key});

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final _controller = TextEditingController();
  final _imagePicker = ImagePicker();
  bool _hasText = false;
  bool _showEmojiPicker = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) {
        setState(() => _hasText = has);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final chat = context.read<ChatProvider>();

    // Check if conversation has disappearing timer set
    final expiresIn = chat.conversationDisappearingTimer;

    chat.sendMessage(text, expiresIn: expiresIn);
    _controller.clear();

    if (_showEmojiPicker) {
      setState(() => _showEmojiPicker = false);
    }
  }

  void _toggleEmojiPicker() {
    setState(() => _showEmojiPicker = !_showEmojiPicker);
  }

  Future<void> _pickImageFromGallery() async {
    final XFile? image = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      // TODO: Upload image and send as message (Phase 4)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image upload coming soon')),
      );
    }
  }

  void _recordVoice() {
    // TODO: Voice recording (future feature)
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Voice messages coming soon')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = RpgTheme.isDark(context);
    final colorScheme = Theme.of(context).colorScheme;
    final borderColor =
        isDark ? RpgTheme.convItemBorderDark : RpgTheme.convItemBorderLight;
    final inputBg = isDark ? RpgTheme.inputBg : RpgTheme.inputBgLight;

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Input row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(top: BorderSide(color: borderColor)),
            ),
            child: Row(
              children: [
                // Attachment button (gallery)
                IconButton(
                  icon: const Icon(Icons.attach_file),
                  iconSize: 24,
                  color: isDark ? RpgTheme.mutedDark : RpgTheme.textSecondaryLight,
                  onPressed: _pickImageFromGallery,
                ),

                // Text field
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: RpgTheme.bodyFont(
                      fontSize: 14,
                      color: colorScheme.onSurface,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(
                          color: isDark
                              ? RpgTheme.tabBorderDark
                              : RpgTheme.tabBorderLight,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(
                          color: isDark
                              ? RpgTheme.tabBorderDark
                              : RpgTheme.tabBorderLight,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(
                          color: RpgTheme.primaryColor(context),
                          width: 1.5,
                        ),
                      ),
                      filled: true,
                      fillColor: inputBg,
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                  ),
                ),

                const SizedBox(width: 4),

                // Emoji button
                IconButton(
                  icon: Icon(
                    _showEmojiPicker ? Icons.keyboard : Icons.emoji_emotions_outlined,
                  ),
                  iconSize: 24,
                  color: isDark ? RpgTheme.mutedDark : RpgTheme.textSecondaryLight,
                  onPressed: _toggleEmojiPicker,
                ),

                const SizedBox(width: 4),

                // Mic / Send toggle
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _hasText
                        ? RpgTheme.primaryColor(context)
                        : Colors.transparent,
                  ),
                  child: IconButton(
                    icon: Icon(
                      _hasText ? Icons.send_rounded : Icons.mic,
                      size: 22,
                    ),
                    color: _hasText
                        ? (isDark ? RpgTheme.accentDark : Colors.white)
                        : (isDark ? RpgTheme.mutedDark : RpgTheme.textSecondaryLight),
                    onPressed: _hasText ? _send : _recordVoice,
                  ),
                ),
              ],
            ),
          ),

          // Emoji picker
          if (_showEmojiPicker)
            SizedBox(
              height: 250,
              child: EmojiPicker(
                onEmojiSelected: (category, emoji) {
                  _controller.text += emoji.emoji;
                },
                config: Config(
                  columns: 7,
                  emojiSizeMax: 32,
                  verticalSpacing: 0,
                  horizontalSpacing: 0,
                  gridPadding: EdgeInsets.zero,
                  initCategory: Category.RECENT,
                  bgColor: colorScheme.surface,
                  indicatorColor: RpgTheme.primaryColor(context),
                  iconColor: isDark ? RpgTheme.mutedDark : RpgTheme.textSecondaryLight,
                  iconColorSelected: RpgTheme.primaryColor(context),
                  backspaceColor: RpgTheme.primaryColor(context),
                  skinToneDialogBgColor: colorScheme.surface,
                  skinToneIndicatorColor: RpgTheme.primaryColor(context),
                  enableSkinTones: true,
                  recentTabBehavior: RecentTabBehavior.RECENT,
                  recentsLimit: 28,
                  noRecents: const Text(
                    'No Recents',
                    style: TextStyle(fontSize: 20, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  loadingIndicator: const SizedBox.shrink(),
                  tabIndicatorAnimDuration: kTabScrollDuration,
                  categoryIcons: const CategoryIcons(),
                  buttonMode: ButtonMode.MATERIAL,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
```

**Step 3: Test new input bar**

Manual test:
1. Tap attachment → opens gallery
2. Type text → mic icon changes to send
3. Tap emoji → picker appears
4. Select emoji → adds to text field
5. Tap keyboard icon → picker closes

**Step 4: Commit input bar redesign**

```bash
git add frontend/lib/widgets/chat_input_bar.dart
git add frontend/pubspec.yaml
git commit -m "feat(frontend): redesign ChatInputBar with Telegram-style controls

- Add attachment button (opens gallery via image_picker)
- Add emoji picker toggle button (emoji_picker_flutter)
- Replace send button with mic/send toggle (mic when empty, send when text)
- Add emoji picker panel below input (250px height)
- Integrate with ChatProvider.sendMessage (expiresIn support)
- Theme-aware colors for all controls"
```

---

### Task 3.3: Create Action Tiles Row

**Files:**
- Create: `frontend/lib/widgets/chat_action_tiles.dart`

**Step 1: Create ChatActionTiles widget**

File: `frontend/lib/widgets/chat_action_tiles.dart`

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../theme/rpg_theme.dart';

class ChatActionTiles extends StatelessWidget {
  const ChatActionTiles({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = RpgTheme.isDark(context);
    final borderColor =
        isDark ? RpgTheme.convItemBorderDark : RpgTheme.convItemBorderLight;
    final tileColor =
        isDark ? RpgTheme.inputBg : RpgTheme.inputBgLight;
    final iconColor =
        isDark ? RpgTheme.accentDark : RpgTheme.primaryLight;

    return Container(
      height: 60,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: borderColor)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        children: [
          _ActionTile(
            icon: Icons.timer_outlined,
            label: 'Timer',
            color: iconColor,
            backgroundColor: tileColor,
            onTap: () => _showTimerDialog(context),
          ),
          const SizedBox(width: 8),
          _ActionTile(
            icon: Icons.campaign,
            label: 'Ping',
            color: iconColor,
            backgroundColor: tileColor,
            onTap: () => _sendPing(context),
          ),
          const SizedBox(width: 8),
          _ActionTile(
            icon: Icons.camera_alt,
            label: 'Camera',
            color: iconColor,
            backgroundColor: tileColor,
            onTap: () => _openCamera(context),
          ),
          const SizedBox(width: 8),
          _ActionTile(
            icon: Icons.brush,
            label: 'Draw',
            color: iconColor,
            backgroundColor: tileColor,
            onTap: () => _openDrawing(context),
          ),
          const SizedBox(width: 8),
          _ActionTile(
            icon: Icons.gif_box,
            label: 'GIF',
            color: iconColor,
            backgroundColor: tileColor,
            onTap: () => _showComingSoon(context, 'GIF picker'),
          ),
          const SizedBox(width: 8),
          _ActionTile(
            icon: Icons.more_horiz,
            label: 'More',
            color: iconColor,
            backgroundColor: tileColor,
            onTap: () => _showComingSoon(context, 'More options'),
          ),
        ],
      ),
    );
  }

  void _showTimerDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _TimerDialog(),
    );
  }

  void _sendPing(BuildContext context) {
    final chat = context.read<ChatProvider>();

    // Guard: Check if conversation is active
    if (chat.activeConversationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Open a conversation first')),
      );
      return;
    }

    final conv = chat.conversations
        .firstWhere((c) => c.id == chat.activeConversationId);
    final recipientId = chat.getOtherUserId(conv);

    chat.sendPing(recipientId);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ping sent!')),
    );
  }

  void _openCamera(BuildContext context) {
    final chat = context.read<ChatProvider>();

    // Guard: Check if conversation is active
    if (chat.activeConversationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Open a conversation first')),
      );
      return;
    }

    // TODO: Open camera (Phase 4)
    _showComingSoon(context, 'Camera');
  }

  void _openDrawing(BuildContext context) {
    final chat = context.read<ChatProvider>();

    // Guard: Check if conversation is active
    if (chat.activeConversationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Open a conversation first')),
      );
      return;
    }

    // TODO: Open drawing canvas (Task 3.5)
    _showComingSoon(context, 'Drawing');
  }

  void _showComingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature coming soon')),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color backgroundColor;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.backgroundColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 70,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: RpgTheme.bodyFont(
                fontSize: 10,
                color: color,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _TimerDialog extends StatefulWidget {
  @override
  State<_TimerDialog> createState() => _TimerDialogState();
}

class _TimerDialogState extends State<_TimerDialog> {
  int? _selectedSeconds;

  final _options = [
    {'label': '30 seconds', 'value': 30},
    {'label': '1 minute', 'value': 60},
    {'label': '5 minutes', 'value': 300},
    {'label': '1 hour', 'value': 3600},
    {'label': '1 day', 'value': 86400},
    {'label': 'Off', 'value': null},
  ];

  @override
  void initState() {
    super.initState();
    final chat = context.read<ChatProvider>();
    _selectedSeconds = chat.conversationDisappearingTimer;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Disappearing Messages'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: _options.map((opt) {
          return RadioListTile<int?>(
            title: Text(opt['label'] as String),
            value: opt['value'] as int?,
            groupValue: _selectedSeconds,
            onChanged: (val) {
              setState(() => _selectedSeconds = val);
            },
          );
        }).toList(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            final chat = context.read<ChatProvider>();
            chat.setConversationDisappearingTimer(_selectedSeconds);
            Navigator.pop(context);
          },
          child: const Text('Set'),
        ),
      ],
    );
  }
}
```

**Step 2: Add ChatActionTiles to ChatInputBar**

File: `frontend/lib/widgets/chat_input_bar.dart`

Update to import and include tiles above input row:

```dart
import 'chat_action_tiles.dart';

// In build() method, wrap in Column:
@override
Widget build(BuildContext context) {
  // ... existing variables ...

  return SafeArea(
    top: false,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const ChatActionTiles(), // ADD THIS

        // Input row
        Container(
          // ... existing input row ...
        ),

        // Emoji picker
        if (_showEmojiPicker) ...,
      ],
    ),
  );
}
```

**Step 3: Add conversationDisappearingTimer to ChatProvider**

File: `frontend/lib/providers/chat_provider.dart`

Add field and methods:

```dart
class ChatProvider extends ChangeNotifier {
  // ... existing fields ...

  final Map<int, int?> _conversationTimers = {}; // conversationId -> seconds

  int? get conversationDisappearingTimer {
    if (_activeConversationId == null) return null;
    return _conversationTimers[_activeConversationId];
  }

  void setConversationDisappearingTimer(int? seconds) {
    if (_activeConversationId == null) return;
    _conversationTimers[_activeConversationId!] = seconds;
    notifyListeners();
  }

  // ... rest of class ...
}
```

**Step 4: Test action tiles**

Manual test:
1. Tiles appear below input bar
2. Tap Timer → dialog opens with options
3. Select timer → sets conversation timer
4. Tap Ping → sends ping message
5. Other tiles → show "coming soon"

**Step 5: Commit action tiles**

```bash
git add frontend/lib/widgets/chat_action_tiles.dart
git add frontend/lib/widgets/chat_input_bar.dart
git add frontend/lib/providers/chat_provider.dart
git commit -m "feat(frontend): add action tiles row below input bar

- Create ChatActionTiles widget with horizontal scroll
- Add 6 tiles: Timer, Ping, Camera, Draw, GIF, More
- Implement Timer dialog with 6 duration options (30s to 1 day)
- Add conversationDisappearingTimer to ChatProvider
- Integrate sendPing with Ping tile
- Placeholder 'coming soon' for Camera, Draw, GIF, More"
```

---

### Task 3.4: Redesign AppBar (Top Bar)

**Files:**
- Modify: `frontend/lib/screens/chat_detail_screen.dart`

**Step 1: Update AppBar to match Telegram layout**

File: `frontend/lib/screens/chat_detail_screen.dart`

Find the `Scaffold` widget's `appBar`, replace with:

```dart
appBar: AppBar(
  leading: IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () {
      context.read<ChatProvider>().clearActiveConversation();
      Navigator.of(context).pop();
    },
  ),
  title: Text(
    contactName,
    style: RpgTheme.bodyFont(
      fontSize: 16,
      color: colorScheme.onSurface,
      fontWeight: FontWeight.w600,
    ),
    overflow: TextOverflow.ellipsis,
  ),
  actions: [
    // Avatar on the right
    Padding(
      padding: const EdgeInsets.only(right: 12),
      child: AvatarCircle(
        email: contactName,
        radius: 18,
        profilePictureUrl: otherUser?.profilePictureUrl,
      ),
    ),
    // Menu (three dots)
    PopupMenuButton<String>(
      onSelected: (value) {
        if (value == 'unfriend') {
          _unfriend();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'unfriend',
          child: Row(
            children: [
              Icon(Icons.person_remove, color: Colors.red),
              const SizedBox(width: 8),
              const Text('Unfriend'),
            ],
          ),
        ),
      ],
    ),
  ],
),
```

**Step 2: Test new AppBar**

Manual test:
1. Back button works
2. Username centered
3. Avatar appears on right side
4. Three-dot menu opens
5. Unfriend option works

**Step 3: Commit AppBar redesign**

```bash
git add frontend/lib/screens/chat_detail_screen.dart
git commit -m "feat(frontend): redesign AppBar to match Telegram layout

- Move avatar to right side of AppBar (actions)
- Keep username as title (centered)
- Remove avatar from title row
- Keep back button on left
- Keep three-dot menu on far right"
```

---

### Task 3.5: Add Ping Visual Effect & Sound

**Files:**
- Create: `frontend/lib/widgets/ping_effect_overlay.dart`
- Add dependency: `just_audio: ^0.9.36` to `pubspec.yaml`
- Create: `frontend/assets/sounds/ping.mp3` (placeholder)

**Step 1: Add just_audio dependency**

File: `frontend/pubspec.yaml`

```yaml
dependencies:
  # ... existing dependencies ...
  just_audio: ^0.9.36

flutter:
  assets:
    - assets/sounds/
```

Run:
```bash
cd frontend
flutter pub get
```

**Step 2: Create ping sound asset**

Create directory and placeholder:
```bash
mkdir -p frontend/assets/sounds
# Add a ping.mp3 file (download from freesound.org or use text-to-speech "ping")
# For now, create empty placeholder:
echo "" > frontend/assets/sounds/ping.mp3
```

**Step 3: Create PingEffectOverlay widget**

File: `frontend/lib/widgets/ping_effect_overlay.dart`

```dart
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

class PingEffectOverlay extends StatefulWidget {
  final VoidCallback onComplete;

  const PingEffectOverlay({super.key, required this.onComplete});

  @override
  State<PingEffectOverlay> createState() => _PingEffectOverlayState();
}

class _PingEffectOverlayState extends State<PingEffectOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  final _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _scaleAnimation = Tween<double>(begin: 0.5, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _opacityAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _playPingSound();
    _controller.forward().then((_) {
      if (mounted) {
        widget.onComplete();
      }
    });
  }

  Future<void> _playPingSound() async {
    try {
      await _audioPlayer.setAsset('assets/sounds/ping.mp3');
      await _audioPlayer.play();
    } catch (e) {
      debugPrint('Error playing ping sound: $e');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Center(
          child: Opacity(
            opacity: _opacityAnimation.value,
            child: Transform.scale(
              scale: _scaleAnimation.value,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.orange.withOpacity(0.5),
                  border: Border.all(
                    color: Colors.orange,
                    width: 3,
                  ),
                ),
                child: const Icon(
                  Icons.campaign,
                  size: 50,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
```

**Step 4: Show PingEffectOverlay when receiving ping**

File: `frontend/lib/providers/chat_provider.dart`

Update `_handlePingReceived`:

```dart
void _handlePingReceived(Map<String, dynamic> data) {
  final message = MessageModel.fromJson(data);

  // Add to messages
  if (_activeConversationId == message.conversationId) {
    _messages.add(message);
  }
  _lastMessages[message.conversationId] = message;

  // Set flag for showing ping effect
  _showPingEffect = true;

  notifyListeners();
}

// Add field
bool _showPingEffect = false;
bool get showPingEffect => _showPingEffect;

void clearPingEffect() {
  _showPingEffect = false;
  notifyListeners();
}
```

**Step 5: Add overlay to ChatDetailScreen**

File: `frontend/lib/screens/chat_detail_screen.dart`

Import and add overlay:

```dart
import '../widgets/ping_effect_overlay.dart';

// In build() method, wrap body in Stack:
@override
Widget build(BuildContext context) {
  final chat = context.watch<ChatProvider>();
  // ... existing variables ...

  final bodyWidget = Column(
    children: [
      Expanded(
        child: Container(
          // ... existing messages ListView ...
        ),
      ),
      const ChatInputBar(),
    ],
  );

  return Scaffold(
    appBar: /* ... existing AppBar ... */,
    body: Stack(
      children: [
        bodyWidget,

        // Ping effect overlay
        if (chat.showPingEffect)
          Positioned.fill(
            child: PingEffectOverlay(
              onComplete: () {
                chat.clearPingEffect();
              },
            ),
          ),
      ],
    ),
  );
}
```

**Step 6: Test ping effect**

Manual test:
1. Send ping from another user
2. Orange circle expands and fades
3. Ping sound plays
4. Overlay disappears after animation

**Step 7: Commit ping effect**

```bash
git add frontend/lib/widgets/ping_effect_overlay.dart
git add frontend/lib/providers/chat_provider.dart
git add frontend/lib/screens/chat_detail_screen.dart
git add frontend/pubspec.yaml
git add frontend/assets/sounds/ping.mp3
git commit -m "feat(frontend): add ping visual effect and sound

- Add just_audio dependency for audio playback
- Create PingEffectOverlay widget with scale + fade animation
- Play ping.mp3 sound when ping received
- Add showPingEffect flag to ChatProvider
- Show overlay in ChatDetailScreen Stack when ping arrives
- Orange circle icon expands from center (800ms duration)"
```

---

### Task 3.6: Create Drawing Canvas Screen (Basic)

**Files:**
- Create: `frontend/lib/screens/drawing_canvas_screen.dart`
- Modify: `frontend/lib/widgets/chat_action_tiles.dart`

**Step 1: Create DrawingCanvasScreen**

File: `frontend/lib/screens/drawing_canvas_screen.dart`

```dart
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../theme/rpg_theme.dart';

class DrawingCanvasScreen extends StatefulWidget {
  const DrawingCanvasScreen({super.key});

  @override
  State<DrawingCanvasScreen> createState() => _DrawingCanvasScreenState();
}

class _DrawingCanvasScreenState extends State<DrawingCanvasScreen> {
  final List<DrawnLine> _lines = [];
  DrawnLine? _currentLine;
  bool _isEraser = false;
  final GlobalKey _canvasKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final isDark = RpgTheme.isDark(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Draw'),
        actions: [
          // Eraser toggle
          IconButton(
            icon: Icon(_isEraser ? Icons.edit : Icons.auto_fix_high),
            onPressed: () {
              setState(() => _isEraser = !_isEraser);
            },
          ),
          // Clear all
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              setState(() => _lines.clear());
            },
          ),
          // Send
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _sendDrawing,
          ),
        ],
      ),
      body: Column(
        children: [
          // Canvas
          Expanded(
            child: Container(
              color: Colors.white,
              child: RepaintBoundary(
                key: _canvasKey,
                child: GestureDetector(
                  onPanStart: (details) {
                    setState(() {
                      _currentLine = DrawnLine(
                        points: [details.localPosition],
                        color: _isEraser ? Colors.white : Colors.black,
                        strokeWidth: _isEraser ? 20.0 : 3.0,
                      );
                    });
                  },
                  onPanUpdate: (details) {
                    setState(() {
                      _currentLine = _currentLine?.copyWith(
                        points: [..._currentLine!.points, details.localPosition],
                      );
                    });
                  },
                  onPanEnd: (details) {
                    setState(() {
                      if (_currentLine != null) {
                        _lines.add(_currentLine!);
                        _currentLine = null;
                      }
                    });
                  },
                  child: CustomPaint(
                    painter: DrawingPainter(
                      lines: [..._lines, if (_currentLine != null) _currentLine!],
                    ),
                    size: Size.infinite,
                  ),
                ),
              ),
            ),
          ),

          // Toolbar
          Container(
            padding: const EdgeInsets.all(16),
            color: isDark ? RpgTheme.inputBg : RpgTheme.inputBgLight,
            child: Row(
              children: [
                Text(
                  _isEraser ? 'Eraser mode' : 'Draw mode',
                  style: RpgTheme.bodyFont(fontSize: 14),
                ),
                const Spacer(),
                Text(
                  'Stroke: ${_isEraser ? '20px' : '3px'}',
                  style: RpgTheme.bodyFont(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendDrawing() async {
    if (_lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Canvas is empty')),
      );
      return;
    }

    // TODO: Convert canvas to image and upload (Phase 4)
    // For now, just pop with success message
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Drawing upload coming soon')),
    );
  }
}

class DrawnLine {
  final List<Offset> points;
  final Color color;
  final double strokeWidth;

  DrawnLine({
    required this.points,
    required this.color,
    required this.strokeWidth,
  });

  DrawnLine copyWith({
    List<Offset>? points,
    Color? color,
    double? strokeWidth,
  }) {
    return DrawnLine(
      points: points ?? this.points,
      color: color ?? this.color,
      strokeWidth: strokeWidth ?? this.strokeWidth,
    );
  }
}

class DrawingPainter extends CustomPainter {
  final List<DrawnLine> lines;

  DrawingPainter({required this.lines});

  @override
  void paint(Canvas canvas, Size size) {
    for (final line in lines) {
      final paint = Paint()
        ..color = line.color
        ..strokeWidth = line.strokeWidth
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      for (int i = 0; i < line.points.length - 1; i++) {
        canvas.drawLine(line.points[i], line.points[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(DrawingPainter oldDelegate) {
    return oldDelegate.lines != lines;
  }
}
```

**Step 2: Wire up Draw tile to open canvas**

File: `frontend/lib/widgets/chat_action_tiles.dart`

Update `_openDrawing`:

```dart
import '../screens/drawing_canvas_screen.dart';

void _openDrawing(BuildContext context) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => const DrawingCanvasScreen(),
    ),
  );
}
```

**Step 3: Test drawing canvas**

Manual test:
1. Tap Draw tile → canvas screen opens
2. Draw on white canvas → black strokes appear
3. Tap eraser → draw mode changes, white strokes erase
4. Tap clear → all strokes removed
5. Tap check → pops back (coming soon message)

**Step 4: Commit drawing canvas**

```bash
git add frontend/lib/screens/drawing_canvas_screen.dart
git add frontend/lib/widgets/chat_action_tiles.dart
git commit -m "feat(frontend): add basic drawing canvas screen

- Create DrawingCanvasScreen with white canvas
- Implement CustomPainter for stroke rendering
- Add draw/eraser mode toggle (black 3px / white 20px)
- Add clear button to reset canvas
- Add send button (upload coming in Phase 4)
- Wire up Draw tile to open canvas screen"
```

---

## Phase 4: Message Expiration & Cleanup (Auto-delete)

### Task 4.1: Implement Message Expiration Background Job

**Files:**
- Create: `backend/src/messages/message-cleanup.service.ts`
- Modify: `backend/src/messages/messages.module.ts`
- Modify: `backend/src/app.module.ts`
- Add dependency: `@nestjs/schedule` to `package.json`

**Step 1: Add @nestjs/schedule dependency**

File: `backend/package.json`

```json
"dependencies": {
  "@nestjs/schedule": "^4.0.0",
  // ... existing dependencies ...
}
```

Run:
```bash
cd backend
npm install
```

**Step 2: Create MessageCleanupService**

File: `backend/src/messages/message-cleanup.service.ts`

```typescript
import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, LessThan } from 'typeorm';
import { Message } from './entities/message.entity';

@Injectable()
export class MessageCleanupService {
  private readonly logger = new Logger(MessageCleanupService.name);

  constructor(
    @InjectRepository(Message)
    private messagesRepo: Repository<Message>,
  ) {}

  @Cron(CronExpression.EVERY_MINUTE)
  async deleteExpiredMessages() {
    const now = new Date();

    const expiredMessages = await this.messagesRepo.find({
      where: {
        expiresAt: LessThan(now),
      },
    });

    if (expiredMessages.length > 0) {
      await this.messagesRepo.remove(expiredMessages);
      this.logger.log(`Deleted ${expiredMessages.length} expired messages`);
    }
  }
}
```

**Step 3: Register MessageCleanupService in MessagesModule**

File: `backend/src/messages/messages.module.ts`

```typescript
import { MessageCleanupService } from './message-cleanup.service';

@Module({
  imports: [TypeOrmModule.forFeature([Message])],
  providers: [MessagesService, MessageCleanupService],
  exports: [MessagesService],
})
export class MessagesModule {}
```

**Step 4: Enable ScheduleModule in AppModule**

File: `backend/src/app.module.ts`

```typescript
import { ScheduleModule } from '@nestjs/schedule';

@Module({
  imports: [
    ScheduleModule.forRoot(),
    // ... existing imports ...
  ],
  // ...
})
export class AppModule {}
```

**Step 5: Test message expiration**

Manual test:
1. Send message with `expiresIn: 60` (1 minute)
2. Wait 61 seconds
3. Check database → message should be deleted
4. Check backend logs → "Deleted 1 expired messages"

**Step 6: Commit message cleanup**

```bash
git add backend/src/messages/message-cleanup.service.ts
git add backend/src/messages/messages.module.ts
git add backend/src/app.module.ts
git add backend/package.json
git commit -m "feat(backend): add message expiration background job

- Add @nestjs/schedule dependency
- Create MessageCleanupService with cron job (every minute)
- Delete messages where expiresAt < now
- Enable ScheduleModule in AppModule
- Log number of deleted messages"
```

---

### Task 4.2: Frontend Timer Countdown Live Update

**Files:**
- Modify: `frontend/lib/widgets/chat_message_bubble.dart`
- Modify: `frontend/lib/screens/chat_detail_screen.dart`

**Step 1: Add periodic rebuild for countdown**

File: `frontend/lib/screens/chat_detail_screen.dart`

Add timer in state:

```dart
class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final _scrollController = ScrollController();
  Timer? _timerCountdownRefresh;

  @override
  void initState() {
    super.initState();

    // ... existing initState code ...

    // Refresh every second to update countdown
    _timerCountdownRefresh = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _timerCountdownRefresh?.cancel();
    super.dispose();
  }

  // ... rest of class ...
}
```

**Step 2: Update ChatMessageBubble to rebuild every second**

File: `frontend/lib/widgets/chat_message_bubble.dart`

The countdown already uses `_getTimerText()` which recalculates on every build, so periodic setState in parent will update it.

**Step 3: Test live countdown**

Manual test:
1. Send message with timer (e.g., 5 minutes)
2. Watch bubble → countdown updates every second
3. When expired → shows "Expired" (will be deleted by backend cron)

**Step 4: Commit countdown update**

```bash
git add frontend/lib/screens/chat_detail_screen.dart
git commit -m "feat(frontend): add live countdown update for disappearing messages

- Add Timer.periodic in ChatDetailScreen (1 second interval)
- setState to rebuild message bubbles every second
- Countdown automatically recalculates via _getTimerText()
- Cancel timer in dispose to prevent leaks"
```

---

## Phase 5: Image Upload for Messages (Camera & Drawing)

### Task 5.1: Backend - Image Message Upload Endpoint

**Files:**
- Modify: `backend/src/messages/messages.service.ts`
- Create: `backend/src/messages/messages.controller.ts`
- Modify: `backend/src/messages/messages.module.ts`

**Step 1: Create MessagesController with image upload endpoint**

File: `backend/src/messages/messages.controller.ts`

```typescript
import {
  Controller,
  Post,
  UseGuards,
  UseInterceptors,
  UploadedFile,
  Body,
  Request,
  HttpException,
  HttpStatus,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { MessagesService } from './messages.service';
import { CloudinaryService } from '../cloudinary/cloudinary.service';

@Controller('messages')
export class MessagesController {
  constructor(
    private messagesService: MessagesService,
    private cloudinaryService: CloudinaryService,
  ) {}

  @Post('image')
  @UseGuards(JwtAuthGuard)
  @UseInterceptors(FileInterceptor('file'))
  async uploadImageMessage(
    @UploadedFile() file: Express.Multer.File,
    @Body('recipientId') recipientId: string,
    @Body('expiresIn') expiresIn: string,
    @Request() req,
  ) {
    if (!file) {
      throw new HttpException('No file uploaded', HttpStatus.BAD_REQUEST);
    }

    // Validate MIME type
    const allowedTypes = ['image/jpeg', 'image/png', 'image/jpg'];
    if (!allowedTypes.includes(file.mimetype)) {
      throw new HttpException(
        'Invalid file type. Only JPEG and PNG allowed.',
        HttpStatus.BAD_REQUEST,
      );
    }

    // Upload to Cloudinary
    const uploadResult = await this.cloudinaryService.uploadImage(file.buffer);

    // Create message
    const message = await this.messagesService.createImageMessage({
      senderId: req.user.id,
      recipientId: parseInt(recipientId, 10),
      mediaUrl: uploadResult.url,
      expiresIn: expiresIn ? parseInt(expiresIn, 10) : null,
    });

    return {
      message: 'Image uploaded successfully',
      imageUrl: uploadResult.url,
      messageId: message.id,
    };
  }
}
```

**Step 2: Add createImageMessage method to MessagesService**

File: `backend/src/messages/messages.service.ts`

```typescript
async createImageMessage(data: {
  senderId: number;
  recipientId: number;
  mediaUrl: string;
  expiresIn: number | null;
}) {
  const { senderId, recipientId, mediaUrl, expiresIn } = data;

  // Check if friends
  const areFriends = await this.friendsService.areFriends(
    senderId,
    recipientId,
  );
  if (!areFriends) {
    throw new HttpException(
      'You can only send images to friends',
      HttpStatus.FORBIDDEN,
    );
  }

  // Find or create conversation
  let conversation = await this.conversationsService.findBetweenUsers(
    senderId,
    recipientId,
  );
  if (!conversation) {
    conversation = await this.conversationsService.createConversation(
      senderId,
      recipientId,
    );
  }

  // Create message
  const expiresAt = expiresIn
    ? new Date(Date.now() + expiresIn * 1000)
    : null;

  const message = this.messagesRepo.create({
    content: '', // Empty for image messages
    sender: { id: senderId },
    conversation: { id: conversation.id },
    messageType: MessageType.IMAGE,
    mediaUrl,
    deliveryStatus: MessageDeliveryStatus.SENT,
    expiresAt,
  });

  await this.messagesRepo.save(message);
  return message;
}
```

**Step 3: Register MessagesController in MessagesModule**

File: `backend/src/messages/messages.module.ts`

```typescript
import { MessagesController } from './messages.controller';
import { CloudinaryModule } from '../cloudinary/cloudinary.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([Message]),
    CloudinaryModule, // Import for image upload
  ],
  controllers: [MessagesController],
  providers: [MessagesService, MessageCleanupService],
  exports: [MessagesService],
})
export class MessagesModule {}
```

**Step 4: Test image upload**

Manual test:
```bash
curl -X POST http://localhost:3000/messages/image \
  -H "Authorization: Bearer YOUR_JWT" \
  -F "file=@test-image.jpg" \
  -F "recipientId=2" \
  -F "expiresIn=3600"
```

Expected: 200 OK with `{ message: '...', imageUrl: 'https://cloudinary...', messageId: 123 }`

**Step 5: Commit image message upload**

```bash
git add backend/src/messages/messages.controller.ts
git add backend/src/messages/messages.service.ts
git add backend/src/messages/messages.module.ts
git commit -m "feat(backend): add image message upload endpoint

- Create MessagesController with POST /messages/image
- Add createImageMessage method to MessagesService
- Upload image to Cloudinary via multipart form
- Validate MIME type (JPEG/PNG only)
- Create message with messageType=IMAGE, mediaUrl, expiresAt
- Check friendship before creating image message"
```

---

### Task 5.2: Frontend - Camera & Drawing Upload

**Files:**
- Modify: `frontend/lib/widgets/chat_action_tiles.dart`
- Modify: `frontend/lib/screens/drawing_canvas_screen.dart`
- Modify: `frontend/lib/services/api_service.dart`
- Modify: `frontend/lib/providers/chat_provider.dart`

**Step 1: Add uploadImageMessage to ApiService**

File: `frontend/lib/services/api_service.dart`

```dart
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

Future<Map<String, dynamic>> uploadImageMessage(
  String token,
  XFile imageFile,
  int recipientId, {
  int? expiresIn,
}) async {
  final uri = Uri.parse('$baseUrl/messages/image');
  final request = http.MultipartRequest('POST', uri);

  request.headers['Authorization'] = 'Bearer $token';
  request.fields['recipientId'] = recipientId.toString();
  if (expiresIn != null) {
    request.fields['expiresIn'] = expiresIn.toString();
  }

  if (kIsWeb) {
    final bytes = await imageFile.readAsBytes();
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: imageFile.name,
    ));
  } else {
    request.files.add(await http.MultipartFile.fromPath(
      'file',
      imageFile.path,
    ));
  }

  final response = await request.send();
  final responseBody = await response.stream.bytesToString();

  if (response.statusCode == 201 || response.statusCode == 200) {
    return jsonDecode(responseBody) as Map<String, dynamic>;
  } else {
    throw Exception('Failed to upload image: $responseBody');
  }
}
```

**Step 2: Add sendImageMessage to ChatProvider**

File: `frontend/lib/providers/chat_provider.dart`

```dart
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';

Future<void> sendImageMessage(XFile imageFile, int recipientId) async {
  if (_socket == null) return;

  final token = /* get token from AuthProvider or stored */;
  final expiresIn = _conversationTimers[_activeConversationId];

  try {
    final result = await ApiService().uploadImageMessage(
      token,
      imageFile,
      recipientId,
      expiresIn: expiresIn,
    );

    // Emit socket event to notify recipient in real-time
    _socket!.emit('imageMessageSent', {
      'messageId': result['messageId'],
      'recipientId': recipientId,
    });

    // Message will arrive via normal newMessage event from backend
  } catch (e) {
    _errorMessage = 'Failed to upload image: $e';
    notifyListeners();
  }
}
```

**Step 3: Wire up Camera tile**

File: `frontend/lib/widgets/chat_action_tiles.dart`

```dart
import 'package:image_picker/image_picker.dart';

void _openCamera(BuildContext context) async {
  final chat = context.read<ChatProvider>();
  final conv = chat.conversations
      .firstWhere((c) => c.id == chat.activeConversationId);
  final recipientId = chat.getOtherUserId(conv);

  final picker = ImagePicker();
  final XFile? image = await picker.pickImage(source: ImageSource.camera);

  if (image != null) {
    await chat.sendImageMessage(image, recipientId);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Image sent')),
    );
  }
}
```

**Step 4: Wire up Drawing send**

File: `frontend/lib/screens/drawing_canvas_screen.dart`

Add method to capture canvas as image:

```dart
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

Future<void> _sendDrawing() async {
  if (_lines.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Canvas is empty')),
    );
    return;
  }

  try {
    // Capture canvas as image
    final boundary = _canvasKey.currentContext!.findRenderObject()
        as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();

    // Save to temp file
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/drawing_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(pngBytes);

    final xFile = XFile(file.path);

    // Send via ChatProvider
    final chat = context.read<ChatProvider>();
    final conv = chat.conversations
        .firstWhere((c) => c.id == chat.activeConversationId);
    final recipientId = chat.getOtherUserId(conv);

    await chat.sendImageMessage(xFile, recipientId);

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Drawing sent')),
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to send drawing: $e')),
    );
  }
}
```

Add dependency:

File: `frontend/pubspec.yaml`

```yaml
dependencies:
  path_provider: ^2.1.1
```

**Step 5: Update ChatMessageBubble to display images**

File: `frontend/lib/widgets/chat_message_bubble.dart`

```dart
// In build() method, update content section:
if (message.messageType == MessageType.text)
  Text(
    message.content,
    style: RpgTheme.bodyFont(fontSize: 14, color: textColor),
  )
else if (message.messageType == MessageType.ping)
  Row(
    // ... existing ping display ...
  )
else if (message.messageType == MessageType.image && message.mediaUrl != null)
  ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: Image.network(
      message.mediaUrl!,
      width: 200,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return const SizedBox(
          width: 200,
          height: 150,
          child: Center(child: CircularProgressIndicator()),
        );
      },
    ),
  ),
```

**Step 6: Test camera & drawing upload**

Manual test:
1. Tap Camera tile → camera opens
2. Take photo → uploads and appears in chat
3. Tap Draw tile → draw something → tap send
4. Drawing appears as image message in chat

**Step 7: Commit image upload frontend**

```bash
git add frontend/lib/services/api_service.dart
git add frontend/lib/providers/chat_provider.dart
git add frontend/lib/widgets/chat_action_tiles.dart
git add frontend/lib/screens/drawing_canvas_screen.dart
git add frontend/lib/widgets/chat_message_bubble.dart
git add frontend/pubspec.yaml
git commit -m "feat(frontend): add camera and drawing image upload

- Add uploadImageMessage to ApiService (multipart upload)
- Add sendImageMessage to ChatProvider
- Wire up Camera tile to pickImage(camera) and upload
- Capture drawing canvas as PNG and upload
- Add path_provider for temp file storage
- Display image messages in ChatMessageBubble (200px width)
- Show loading indicator while image loads"
```

---

## Verification & Testing

### Task 6.1: End-to-End Manual Testing

**Test Scenarios:**

1. **Delivery Indicators**
   - [ ] Send message → shows clock icon (SENDING)
   - [ ] Server confirms → changes to single ✓ (SENT)
   - [ ] Recipient receives → changes to ✓✓ (DELIVERED)

2. **Disappearing Messages**
   - [ ] Set timer to 1 minute via Timer tile dialog
   - [ ] Send message → countdown shows "1m" next to timestamp
   - [ ] Wait 1 minute → countdown updates every second
   - [ ] After expiration → message deleted from both sender/receiver

3. **Ping**
   - [ ] Tap Ping tile → sends ping message
   - [ ] Recipient sees orange circle animation + hears sound
   - [ ] Ping message appears in chat with campaign icon + "PING!" text

4. **Emoji Picker**
   - [ ] Tap emoji button → picker appears below input
   - [ ] Select emoji → adds to text field
   - [ ] Tap keyboard icon → picker closes

5. **Mic/Send Toggle**
   - [ ] Empty text field → shows mic icon
   - [ ] Type text → icon changes to send button
   - [ ] Clear text → reverts to mic icon

6. **Camera**
   - [ ] Tap Camera tile → opens camera
   - [ ] Take photo → uploads to Cloudinary
   - [ ] Image message appears in chat

7. **Drawing**
   - [ ] Tap Draw tile → canvas opens
   - [ ] Draw strokes → appear on canvas
   - [ ] Toggle eraser → erases strokes
   - [ ] Tap clear → all strokes removed
   - [ ] Tap send → converts to image and uploads

8. **AppBar**
   - [ ] Avatar appears on right side of AppBar
   - [ ] Username centered as title
   - [ ] Back button works
   - [ ] Three-dot menu opens with Unfriend option

**Run Test:**
```bash
# Start backend
cd backend
npm run start:dev

# Start frontend
cd frontend
flutter run

# Create two users
# Log in on two devices/browsers
# Test all scenarios above
```

**Step: Document test results**

Create file: `docs/testing/2026-02-04-chat-redesign-manual-tests.md`

```markdown
# Chat Redesign Manual Test Results

**Date:** 2026-02-04
**Tester:** [Your Name]

## Test Results

| Scenario | Status | Notes |
|----------|--------|-------|
| Delivery indicators | ✅/❌ | ... |
| Disappearing messages | ✅/❌ | ... |
| Ping | ✅/❌ | ... |
| Emoji picker | ✅/❌ | ... |
| Mic/Send toggle | ✅/❌ | ... |
| Camera | ✅/❌ | ... |
| Drawing | ✅/❌ | ... |
| AppBar | ✅/❌ | ... |

## Issues Found

[List any bugs or unexpected behavior]

## Screenshots

[Add screenshots of key features]
```

**Commit test results:**
```bash
git add docs/testing/2026-02-04-chat-redesign-manual-tests.md
git commit -m "docs: add manual test results for chat redesign"
```

---

## Final Commit & Documentation

### Task 7.1: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md` (root directory)

**Step: Add new features to CLAUDE.md**

File: `CLAUDE.md`

Add new section after "Recent Changes":

```markdown
## Chat Screen Redesign (2026-02-04)

### New Features

**Message Features:**
- Delivery indicators: SENDING (clock), SENT (✓), DELIVERED (✓✓)
- Disappearing messages: Global timer per conversation (30s to 1 day)
- Ping messages: One-shot visual effect + sound notification
- Image messages: Camera capture and drawing canvas upload

**UI Components:**
- Redesigned AppBar: Username (center), avatar (right), back button (left)
- ChatInputBar: Attachment, emoji picker, mic/send toggle
- Action tiles: Timer, Ping, Camera, Draw, GIF (coming soon), More (coming soon)
- PingEffectOverlay: Animated orange circle with fade + scale
- DrawingCanvasScreen: Basic white canvas with brush + eraser

**Backend:**
- MessageDeliveryStatus enum (SENDING, SENT, DELIVERED)
- MessageType enum (TEXT, PING, IMAGE, DRAWING)
- Message.expiresAt field with cron job cleanup (every minute)
- POST /messages/image endpoint for image upload (Cloudinary)

**Files Modified:**
- Backend: message.entity, chat-message.service, messages.controller, message-cleanup.service
- Frontend: MessageModel, ChatProvider, ChatInputBar, ChatMessageBubble, ChatActionTiles, DrawingCanvasScreen, PingEffectOverlay
- Dependencies: emoji_picker_flutter, just_audio, @nestjs/schedule

**WebSocket Events:**
- messageDelivered: Update delivery status when recipient receives
- sendPing: Send ping message
- newPing: Receive ping notification
```

**Commit CLAUDE.md update:**
```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with chat redesign features

- Add message delivery indicators section
- Document disappearing messages timer
- Document ping feature (visual + audio)
- List new UI components and backend changes
- Reference new WebSocket events"
```

---

## Summary

**Total Tasks:** 19 (across 7 phases)

**Key Deliverables:**
1. ✅ Backend: Message delivery status, expiration, ping, image upload
2. ✅ Frontend: Extended MessageModel, delivery tracking, emoji picker, action tiles
3. ✅ UI Components: Redesigned AppBar, ChatInputBar, ChatMessageBubble, ping overlay, drawing canvas
4. ✅ Background job: Message cleanup cron (every minute)
5. ✅ Audio: Ping sound playback with just_audio
6. ✅ Image handling: Camera capture + drawing canvas → Cloudinary upload

**Files Created:** 7
- Backend: message-cleanup.service.ts, messages.controller.ts, send-ping.dto.ts
- Frontend: chat_action_tiles.dart, ping_effect_overlay.dart, drawing_canvas_screen.dart
- Assets: ping.mp3

**Files Modified:** 15
- Backend: message.entity, messages.service, chat.gateway, chat-message.service, chat.dto, messages.module, app.module
- Frontend: message_model.dart, chat_provider.dart, socket_service.dart, chat_input_bar.dart, chat_message_bubble.dart, chat_detail_screen.dart, api_service.dart, pubspec.yaml

**Dependencies Added:** 4
- Backend: @nestjs/schedule
- Frontend: emoji_picker_flutter, just_audio, path_provider

---

## Plan Complete!

Plan saved to `docs/plans/2026-02-04-chat-screen-redesign.md`.

**Two execution options:**

**1. Subagent-Driven (this session)** - I dispatch fresh subagent per task, review between tasks, fast iteration

**2. Parallel Session (separate)** - Open new session with executing-plans, batch execution with checkpoints

**Which approach?**
