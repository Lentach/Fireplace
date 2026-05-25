# GIF Support Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add GIF search (Giphy API) and sending with E2E encryption to Fireplace.

**Architecture:** GIF picker (bottom sheet with trending/search) → download from Giphy → upload to Cloudinary → Cloudinary URL encrypted in E2E envelope → sent via existing `sendMessage` WebSocket event. Same pattern as IMAGE messages.

**Tech Stack:** Giphy API, Cloudinary, Flutter `Image.network` (native GIF support), existing E2E encryption pipeline.

**Spec:** `docs/superpowers/specs/2026-03-16-gif-support-design.md`

---

## File Structure

**Create:**
- `frontend/lib/services/gif_service.dart` — Giphy API client (trending + search)
- `frontend/lib/widgets/gif_picker_sheet.dart` — bottom sheet with GIF grid
- `frontend/test/services/gif_service_test.dart` — unit tests for GIF service

**Modify:**
- `backend/src/messages/message.entity.ts` — add `GIF` to `MessageType` enum
- `backend/src/messages/dto/upload-media.dto.ts` — add `'gif'` to allowed types
- `backend/src/messages/messages.controller.ts` — add GIF MIME branch
- `backend/src/messages/message.mapper.ts` — add GIF reply-to preview
- `backend/src/messages/message.mapper.spec.ts` — add GIF test cases
- `backend/src/chat/services/chat-message.service.spec.ts` — add E2E encrypted GIF test
- `frontend/lib/models/message_model.dart` — add `gif` to enum + parser
- `frontend/lib/config/app_config.dart` — add `giphyApiKey` getter
- `frontend/lib/services/api_service.dart` — add GIF upload branch
- `frontend/lib/providers/chat_provider.dart` — add `sendGif()` method
- `frontend/lib/widgets/chat_action_tiles.dart` — wire GIF picker
- `frontend/lib/widgets/chat_message_bubble.dart` — render GIF bubbles
- `frontend/lib/l10n/app_pl.arb` — add GIF L10n strings
- `frontend/lib/l10n/app_en.arb` — add GIF L10n strings
- `CLAUDE.md` — update per checklist in spec

---

## Chunk 1: Backend — MessageType + Upload + Mapper

### Task 1: Add GIF to MessageType enum

**Files:**
- Modify: `backend/src/messages/message.entity.ts:19-24`

- [ ] **Step 1: Add GIF to enum**

```typescript
export enum MessageType {
  TEXT = 'TEXT',
  PING = 'PING',
  IMAGE = 'IMAGE',
  VOICE = 'VOICE',
  GIF = 'GIF',
}
```

- [ ] **Step 2: Run existing tests to verify no breakage**

Run: `cd backend && npm test -- --testPathPattern=message`
Expected: All existing tests pass.

- [ ] **Step 3: Commit**

```bash
git add backend/src/messages/message.entity.ts
git commit -m "feat(backend): add GIF to MessageType enum"
```

---

### Task 2: Add GIF to upload-media DTO

**Files:**
- Modify: `backend/src/messages/dto/upload-media.dto.ts`

- [ ] **Step 1: Add 'gif' to @IsIn validator**

Change:
```typescript
@IsIn(['image', 'voice'])
type: 'image' | 'voice';
```
To:
```typescript
@IsIn(['image', 'voice', 'gif'])
type: 'image' | 'voice' | 'gif';
```

- [ ] **Step 2: Run tests**

Run: `cd backend && npm test -- --testPathPattern=message`
Expected: Pass.

- [ ] **Step 3: Commit**

```bash
git add backend/src/messages/dto/upload-media.dto.ts
git commit -m "feat(backend): add gif type to upload-media DTO"
```

---

### Task 3: Add GIF branch to upload-media controller

**Files:**
- Modify: `backend/src/messages/messages.controller.ts:43-57`

- [ ] **Step 1: Add GIF MIME handling**

Replace the image branch (lines 43-57):
```typescript
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
```

With:
```typescript
    if (dto.type === 'image' || dto.type === 'gif') {
      const allowedMimeTypes = dto.type === 'gif'
        ? ['image/gif']
        : ['image/jpeg', 'image/jpg', 'image/png'];
      const label = dto.type === 'gif' ? 'GIF' : 'JPEG/PNG';
      if (!allowedMimeTypes.includes(file.mimetype)) {
        throw new BadRequestException(`Only ${label} images are allowed`);
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
```

- [ ] **Step 2: Run tests**

Run: `cd backend && npm test -- --testPathPattern=message`
Expected: Pass.

- [ ] **Step 3: Commit**

```bash
git add backend/src/messages/messages.controller.ts
git commit -m "feat(backend): accept image/gif MIME type in upload-media"
```

---

### Task 4: Add GIF to MessageMapper reply-to preview

**Files:**
- Modify: `backend/src/messages/message.mapper.ts`

- [ ] **Step 1: Write the failing test**

Add to `backend/src/messages/message.mapper.spec.ts` in the `toPayload` describe block, in the `cases` array for unencrypted type labels:

```typescript
{ messageType: MessageType.GIF, expected: 'GIF' },
```

And add a test for GIF in the `replyTo` describe block:

```typescript
it('should show GIF label for GIF replyTo', () => {
  const msg = {
    ...baseMock,
    messageType: MessageType.GIF,
    mediaUrl: 'https://res.cloudinary.com/demo/image/upload/v1/gif.gif',
    replyTo: {
      ...baseMock,
      id: 50,
      messageType: MessageType.GIF,
      mediaUrl: 'https://res.cloudinary.com/demo/image/upload/v1/gif2.gif',
    },
  };
  const payload = MessageMapper.toPayload(msg as any);
  expect(payload.replyTo.content).toBe('GIF');
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && npm test -- --testPathPattern=message.mapper`
Expected: FAIL — GIF messageType falls through to default.

- [ ] **Step 3: Add GIF case to mapper**

In `message.mapper.ts`, in the reply-to ternary chain, after the IMAGE check add GIF:

Find:
```typescript
: rt.messageType === 'IMAGE'
  ? 'Image'
  : rt.messageType === 'PING'
```

Replace with:
```typescript
: rt.messageType === 'IMAGE'
  ? 'Image'
  : rt.messageType === 'GIF'
    ? 'GIF'
    : rt.messageType === 'PING'
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd backend && npm test -- --testPathPattern=message.mapper`
Expected: All PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/src/messages/message.mapper.ts backend/src/messages/message.mapper.spec.ts
git commit -m "feat(backend): add GIF to message mapper reply-to preview"
```

---

### Task 5: Add E2E encrypted GIF test

**Files:**
- Modify: `backend/src/chat/services/chat-message.service.spec.ts`

- [ ] **Step 1: Write the test**

Add in the `E2E encrypted message types` describe block, following the IMAGE pattern:

```typescript
it('should store [encrypted] for encrypted GIF (no mediaUrl in payload)', async () => {
  chatValidationService.validateCanMessage.mockResolvedValue({ valid: true });
  usersService.findById
    .mockResolvedValueOnce(mockSender as User)
    .mockResolvedValueOnce(mockRecipient as User);
  conversationsService.findById.mockResolvedValue(mockConversation as Conversation);
  messagesService.create.mockResolvedValue(mockMessage);
  onlineUsers.set(2, 'sock2');

  const data = {
    recipientId: 2,
    content: '[encrypted]',
    encryptedContent: '3:base64encryptedGifData',
  };

  await service.handleSendMessage(
    mockClient as Socket,
    mockServer as Server,
    onlineUsers,
    data,
  );

  const opts = messagesService.create.mock.calls[0][2];
  expect(opts.messageType).toBeUndefined();
  expect(opts.mediaUrl).toBeUndefined();
});
```

- [ ] **Step 2: Run test**

Run: `cd backend && npm test -- --testPathPattern=chat-message.service`
Expected: PASS (encrypted GIF is indistinguishable from encrypted TEXT on the server).

- [ ] **Step 3: Commit**

```bash
git add backend/src/chat/services/chat-message.service.spec.ts
git commit -m "test(backend): add E2E encrypted GIF test"
```

---

## Chunk 2: Frontend — Model + Config + API Service

### Task 6: Add GIF to frontend MessageType

**Files:**
- Modify: `frontend/lib/models/message_model.dart`

- [ ] **Step 1: Add `gif` to MessageType enum**

Find:
```dart
enum MessageType {
  text,
  ping,
  image,
  voice,
}
```

Replace with:
```dart
enum MessageType {
  text,
  ping,
  image,
  voice,
  gif,
}
```

- [ ] **Step 2: Add GIF case to `_parseMessageType`**

Find:
```dart
case 'VOICE': return MessageType.voice;
```

Add after it:
```dart
case 'GIF': return MessageType.gif;
```

- [ ] **Step 3: Run frontend tests**

Run: `cd frontend && flutter test`
Expected: All 48 tests pass.

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/models/message_model.dart
git commit -m "feat(frontend): add gif to MessageType enum"
```

---

### Task 7: Add Giphy API key to AppConfig

**Files:**
- Modify: `frontend/lib/config/app_config.dart`

- [ ] **Step 1: Add giphyApiKey getter**

Add to the `AppConfig` class:

```dart
static String get giphyApiKey {
  const key = String.fromEnvironment('GIPHY_API_KEY', defaultValue: '');
  if (key.isNotEmpty) return key;
  // Beta key for development only
  return 'dc6zaTOxFJmzC';
}
```

- [ ] **Step 2: Commit**

```bash
git add frontend/lib/config/app_config.dart
git commit -m "feat(frontend): add Giphy API key to AppConfig"
```

---

### Task 8: Add GIF upload branch to ApiService

**Files:**
- Modify: `frontend/lib/services/api_service.dart:160-210`

- [ ] **Step 1: Add gifBytes parameter and gif branch**

Update the `uploadMedia` method signature — add `List<int>? gifBytes`:

```dart
Future<Map<String, dynamic>> uploadMedia({
  required String token,
  required String type, // 'image', 'voice', or 'gif'
  int? duration,
  int? expiresIn,
  XFile? imageFile,
  String? audioPath,
  List<int>? audioBytes,
  List<int>? gifBytes,
}) async {
```

After the voice branch (`} else if (type == 'voice') { ... }`), before the final send, add:

```dart
} else if (type == 'gif' && gifBytes != null) {
  request.files.add(http.MultipartFile.fromBytes(
    'file', gifBytes,
    filename: 'gif_${DateTime.now().millisecondsSinceEpoch}.gif',
    contentType: MediaType('image', 'gif'),
  ));
}
```

- [ ] **Step 2: Run frontend tests**

Run: `cd frontend && flutter test`
Expected: Pass.

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/services/api_service.dart
git commit -m "feat(frontend): add gif upload branch to ApiService"
```

---

## Chunk 3: Frontend — L10n + GifService + GifPickerSheet

### Task 9: Add L10n strings

**Files:**
- Modify: `frontend/lib/l10n/app_pl.arb`
- Modify: `frontend/lib/l10n/app_en.arb`

> **Note:** L10n strings must exist BEFORE creating GifPickerSheet (Task 11), which references them.

- [ ] **Step 1: Add Polish strings**

Add to `app_pl.arb` (before the closing `}`):
```json
"gifNoResults": "Nie znaleziono GIFów",
"gifSearchHint": "Szukaj GIFów...",
"gifLoadError": "Nie udało się załadować GIFów"
```

- [ ] **Step 2: Add English strings**

Add to `app_en.arb` (before the closing `}`):
```json
"gifNoResults": "No GIFs found",
"gifSearchHint": "Search GIFs...",
"gifLoadError": "Could not load GIFs"
```

- [ ] **Step 3: Regenerate localizations**

Run: `cd frontend && flutter gen-l10n`
Expected: Generated files updated.

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/l10n/
git commit -m "feat(frontend): add GIF localization strings (pl + en)"
```

---

### Task 10: Create GifService

**Files:**
- Create: `frontend/lib/services/gif_service.dart`

- [ ] **Step 1: Write the test**

Create `frontend/test/services/gif_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/services/gif_service.dart';

void main() {
  group('GifModel', () {
    test('fromJson parses Giphy API response', () {
      final json = {
        'id': 'abc123',
        'images': {
          'fixed_height_small': {'url': 'https://media.giphy.com/small.gif'},
          'fixed_height': {'url': 'https://media.giphy.com/full.gif'},
        },
      };
      final gif = GifModel.fromJson(json);
      expect(gif.id, 'abc123');
      expect(gif.previewUrl, 'https://media.giphy.com/small.gif');
      expect(gif.fullUrl, 'https://media.giphy.com/full.gif');
    });

    test('fromJson handles missing fields gracefully', () {
      final json = {
        'id': 'xyz',
        'images': {
          'fixed_height_small': {'url': ''},
          'fixed_height': {'url': ''},
        },
      };
      final gif = GifModel.fromJson(json);
      expect(gif.id, 'xyz');
      expect(gif.previewUrl, '');
      expect(gif.fullUrl, '');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd frontend && flutter test test/services/gif_service_test.dart`
Expected: FAIL — cannot find `gif_service.dart`.

- [ ] **Step 3: Implement GifService**

Create `frontend/lib/services/gif_service.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class GifModel {
  final String id;
  final String previewUrl;
  final String fullUrl;

  const GifModel({
    required this.id,
    required this.previewUrl,
    required this.fullUrl,
  });

  factory GifModel.fromJson(Map<String, dynamic> json) {
    final images = json['images'] as Map<String, dynamic>? ?? {};
    final small = images['fixed_height_small'] as Map<String, dynamic>? ?? {};
    final full = images['fixed_height'] as Map<String, dynamic>? ?? {};
    return GifModel(
      id: json['id'] as String? ?? '',
      previewUrl: small['url'] as String? ?? '',
      fullUrl: full['url'] as String? ?? '',
    );
  }
}

class GifService {
  static const _baseUrl = 'https://api.giphy.com/v1/gifs';
  http.Client? _client;

  void dispose() {
    _client?.close();
    _client = null;
  }

  Future<List<GifModel>> fetchTrending({int limit = 25, int offset = 0}) async {
    return _fetch('$_baseUrl/trending', limit: limit, offset: offset);
  }

  Future<List<GifModel>> search(String query, {int limit = 25, int offset = 0}) async {
    return _fetch('$_baseUrl/search', query: query, limit: limit, offset: offset);
  }

  Future<List<GifModel>> _fetch(String url, {String? query, int limit = 25, int offset = 0}) async {
    _client?.close();
    _client = http.Client();
    final params = {
      'api_key': AppConfig.giphyApiKey,
      'limit': '$limit',
      'offset': '$offset',
      'rating': 'pg-13',
      if (query != null) 'q': query,
    };
    final uri = Uri.parse(url).replace(queryParameters: params);
    try {
      final response = await _client!.get(uri);
      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final list = data['data'] as List<dynamic>? ?? [];
      return list.map((e) => GifModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd frontend && flutter test test/services/gif_service_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/services/gif_service.dart frontend/test/services/gif_service_test.dart
git commit -m "feat(frontend): create GifService with Giphy API client"
```

---

### Task 11: Create GifPickerSheet widget

**Files:**
- Create: `frontend/lib/widgets/gif_picker_sheet.dart`

- [ ] **Step 1: Create the widget**

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../services/gif_service.dart';
import '../l10n/app_localizations.dart';

class GifPickerSheet extends StatefulWidget {
  final void Function(String gifFullUrl) onGifSelected;

  const GifPickerSheet({super.key, required this.onGifSelected});

  @override
  State<GifPickerSheet> createState() => _GifPickerSheetState();

  static Future<void> show(BuildContext context, {required void Function(String) onGifSelected}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: GifPickerSheet(onGifSelected: onGifSelected),
      ),
    );
  }
}

class _GifPickerSheetState extends State<GifPickerSheet> {
  final _gifService = GifService();
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  List<GifModel> _gifs = [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  Timer? _debounce;
  int _offset = 0;
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    _loadTrending();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    _gifService.dispose();
    super.dispose();
  }

  Future<void> _loadTrending() async {
    setState(() { _loading = true; _error = null; _offset = 0; _lastQuery = ''; });
    final results = await _gifService.fetchTrending();
    if (!mounted) return;
    setState(() {
      _gifs = results;
      _loading = false;
      _error = results.isEmpty ? 'no_results' : null;
    });
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      _loadTrending();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () => _doSearch(query.trim()));
  }

  Future<void> _doSearch(String query) async {
    setState(() { _loading = true; _error = null; _offset = 0; _lastQuery = query; });
    final results = await _gifService.search(query);
    if (!mounted) return;
    setState(() {
      _gifs = results;
      _loading = false;
      _error = results.isEmpty ? 'no_results' : null;
    });
  }

  void _onScroll() {
    if (_loadingMore) return;
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    _offset += 25;
    final results = _lastQuery.isEmpty
        ? await _gifService.fetchTrending(offset: _offset)
        : await _gifService.search(_lastQuery, offset: _offset);
    if (!mounted) return;
    setState(() {
      _gifs.addAll(results);
      _loadingMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Column(
      children: [
        const SizedBox(height: 8),
        Container(
          width: 40, height: 4,
          decoration: BoxDecoration(
            color: theme.dividerColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: l10n.actionTileGif,
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              isDense: true,
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error == 'no_results'
                  ? Center(child: Text(l10n.gifNoResults, style: theme.textTheme.bodyMedium))
                  : GridView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 6,
                        mainAxisSpacing: 6,
                      ),
                      itemCount: _gifs.length + (_loadingMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _gifs.length) {
                          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                        }
                        final gif = _gifs[index];
                        return GestureDetector(
                          onTap: () {
                            Navigator.pop(context);
                            widget.onGifSelected(gif.fullUrl);
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              gif.previewUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: theme.colorScheme.surfaceContainerHighest,
                                child: const Icon(Icons.broken_image, size: 32),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('Powered by GIPHY', style: theme.textTheme.bodySmall),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Verify no compile errors**

Run: `cd frontend && flutter analyze lib/widgets/gif_picker_sheet.dart`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/widgets/gif_picker_sheet.dart
git commit -m "feat(frontend): create GifPickerSheet widget"
```

---

## Chunk 4: Frontend — ChatProvider + Wire-up + Bubble

### Task 12: Add sendGif to ChatProvider

**Files:**
- Modify: `frontend/lib/providers/chat_provider.dart`

- [ ] **Step 1: Add the `sendGif` method**

Add after the `sendImageMessage` method (around line 1320). Follow the exact same pattern:

```dart
/// Send a GIF message. Downloads from Giphy, uploads to Cloudinary, encrypts URL.
Future<void> sendGif(
  String token,
  String gifUrl,
  int recipientId,
) async {
  if (_activeConversationId == null || _currentUserId == null) return;

  final effectiveExpiresIn = conversationDisappearingTimer;
  final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}_$_currentUserId';

  // 1. Optimistic message
  final tempMessage = MessageModel(
    id: -(++ChatProvider._tempIdSeq),
    content: '',
    senderId: _currentUserId!,
    senderUsername: '',
    conversationId: _activeConversationId!,
    createdAt: DateTime.now(),
    deliveryStatus: MessageDeliveryStatus.sending,
    messageType: MessageType.gif,
    expiresAt: effectiveExpiresIn != null
        ? DateTime.now().add(Duration(seconds: effectiveExpiresIn))
        : null,
    tempId: tempId,
  );

  _messages.add(tempMessage);
  _pendingSendContent[tempId] = <String, dynamic>{'content': '', 'messageType': 'GIF'};
  notifyListeners();

  try {
    // 2. Download GIF bytes from Giphy
    final response = await http.get(Uri.parse(gifUrl));
    if (response.statusCode != 200) {
      throw Exception('Failed to download GIF');
    }
    final gifBytes = response.bodyBytes;

    // 3. Size guard
    if (gifBytes.length > 5 * 1024 * 1024) {
      throw Exception('GIF too large (max 5 MB)');
    }

    // 4. Upload to Cloudinary
    final responseData = await _api.uploadMedia(
      token: token,
      type: 'gif',
      gifBytes: gifBytes,
      expiresIn: effectiveExpiresIn,
    );

    final cloudinaryUrl = responseData['mediaUrl'] as String;

    // 5. Update optimistic message with URL
    final idx = _messages.indexWhere((m) => m.tempId == tempId);
    if (idx != -1) {
      _messages[idx] = _messages[idx].copyWith(mediaUrl: cloudinaryUrl);
      notifyListeners();
    }

    // 6. Encrypt and send
    _encryptAndSend(
      recipientId: recipientId,
      content: '',
      tempId: tempId,
      effectiveExpiresIn: effectiveExpiresIn,
      messageType: 'GIF',
      mediaUrl: cloudinaryUrl,
    );
  } catch (e) {
    debugPrint('[ChatProvider] GIF send failed: $e');
    _markMessageFailed(tempId, 'GIF send failed: ${e.toString()}');
  }
}
```

- [ ] **Step 2: Add `http` import**

Add `import 'package:http/http.dart' as http;` at the top of `chat_provider.dart` (it does NOT currently have this import — `api_service.dart` has it but not `chat_provider.dart`).

> **CORS note:** Giphy CDN (`media*.giphy.com`) serves CORS headers, so `http.get` works on both web and native. No backend proxy needed for the download step.

- [ ] **Step 3: Run frontend tests**

Run: `cd frontend && flutter test`
Expected: Pass.

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/providers/chat_provider.dart
git commit -m "feat(frontend): add sendGif method to ChatProvider"
```

---

### Task 13: Wire GIF picker to action tiles

**Files:**
- Modify: `frontend/lib/widgets/chat_action_tiles.dart:67-70`

> **Important:** `ChatActionTiles` is a `StatelessWidget`. It has a `_requireActiveConversation(context)` helper that returns `(ConversationModel, int)?` — use this pattern (same as `_pickAttachment`, `_sendPing`).

- [ ] **Step 1: Replace _showComingSoon with GIF picker**

Find:
```dart
onTap: () => _showComingSoon(context, l10n.actionTileGif),
```

Replace with:
```dart
onTap: () => _openGifPicker(context),
```

- [ ] **Step 2: Add _openGifPicker method**

Add to the `ChatActionTiles` class (it is a StatelessWidget, not stateful), following the `_pickAttachment` pattern:

```dart
void _openGifPicker(BuildContext context) {
  final result = _requireActiveConversation(context);
  if (result == null) return;

  final chat = context.read<ChatProvider>();
  final auth = context.read<AuthProvider>();

  GifPickerSheet.show(
    context,
    onGifSelected: (gifUrl) {
      chat.sendGif(auth.token!, gifUrl, result.$2);
    },
  );
}
```

- [ ] **Step 3: Add import**

Add at top of file:
```dart
import 'gif_picker_sheet.dart';
```

- [ ] **Step 4: Remove `_showComingSoon` if now unused**

Check if any other tile uses `_showComingSoon`. If not, delete the method (line 180-182). Run `flutter analyze` to confirm.

- [ ] **Step 5: Verify no compile errors**

Run: `cd frontend && flutter analyze lib/widgets/chat_action_tiles.dart`
Expected: No errors.

- [ ] **Step 6: Commit**

```bash
git add frontend/lib/widgets/chat_action_tiles.dart
git commit -m "feat(frontend): wire GIF picker to action tiles"
```

---

### Task 14: Render GIF in ChatMessageBubble

**Files:**
- Modify: `frontend/lib/widgets/chat_message_bubble.dart`

- [ ] **Step 1: Add GIF rendering**

Find the IMAGE rendering block (the `else if` for `MessageType.image`). Add a similar block for GIF right after it:

```dart
else if (message.messageType == MessageType.gif && message.mediaUrl != null)
  GestureDetector(
    onTap: () => _showGifDialog(context, message.mediaUrl!),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 200),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          message.mediaUrl!,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return const SizedBox(
              width: 150, height: 150,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          },
          errorBuilder: (context, error, stackTrace) => Container(
            width: 150, height: 150,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Icon(Icons.broken_image, size: 48),
          ),
        ),
      ),
    ),
  )
```

- [ ] **Step 2: Add _showGifDialog helper**

Add a helper method (can be a static or free function in the file):

```dart
void _showGifDialog(BuildContext context, String url) {
  showDialog(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      child: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Image.network(url, fit: BoxFit.contain),
      ),
    ),
  );
}
```

- [ ] **Step 3: Verify no compile errors**

Run: `cd frontend && flutter analyze lib/widgets/chat_message_bubble.dart`
Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/widgets/chat_message_bubble.dart
git commit -m "feat(frontend): render GIF messages in chat bubble with tap-to-expand"
```

---

> **Note on E2eEnvelope:** The spec mentions adding 'GIF' to `E2eEnvelope.parse()`, but the parser treats `messageType` as a generic string — no enum validation. GIF already works without changes. No task needed.

## Chunk 5: Integration + CLAUDE.md

### Task 15: Manual integration test

- [ ] **Step 1: Start backend**

Run: `docker-compose up`

- [ ] **Step 2: Start frontend**

Run: `cd frontend && flutter run -d chrome`

- [ ] **Step 3: Test GIF flow**

1. Open a conversation with a friend
2. Tap action tiles → tap GIF icon
3. Verify: bottom sheet opens with trending GIFs
4. Search for "cat" → verify results update
5. Tap a GIF → verify: sheet closes, optimistic message appears
6. Verify: GIF uploads and sends (status changes from SENDING to SENT)
7. Check the other user receives the GIF with animation
8. Verify: reply-to shows "GIF" label (if reply feature used)
9. Verify: disappearing timer works on GIF messages

- [ ] **Step 4: Run all tests**

Run: `cd backend && npm test` (expect 128+ tests pass)
Run: `cd frontend && flutter test` (expect 50+ tests pass)

---

### Task 16: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update MessageType in DB schema**

Find: `enum messageType "TEXT|PING|IMAGE|VOICE"`
Replace with: `enum messageType "TEXT|PING|IMAGE|VOICE|GIF"`

- [ ] **Step 2: Update E2E Encryption section**

Find: `**All message types encrypted** (text, ping, voice, image)`
Replace with: `**All message types encrypted** (text, ping, voice, image, gif)`

Find: `**E2E Envelope:** \`{ content, messageType?, mediaUrl?, mediaDuration?, linkPreview? }\` — \`messageType\` defaults to \`TEXT\` when absent (backward compat).`
Add after that line: `GIF uses \`messageType: 'GIF'\` with \`mediaUrl\` pointing to Cloudinary.`

- [ ] **Step 3: Update File Location Map**

In the Frontend table, Services row, add `gif_service` to the list.
In the Widgets row, add `gif_picker_sheet` to the list.

- [ ] **Step 4: Update Environment & Config table**

Add row: `| \`GIPHY_API_KEY\` | No | Frontend dart define for Giphy API (defaults to beta key in dev) |`

- [ ] **Step 5: Update Known Limitations**

Find: `E2E: all types encrypted (text, ping, voice, image).`
Replace with: `E2E: all types encrypted (text, ping, voice, image, gif).`

- [ ] **Step 6: Update REST API table**

Update the upload-media row: change `'image'\|'voice'` to `'image'\|'voice'\|'gif'`.

- [ ] **Step 7: Update test counts**

Update backend and frontend test counts in Quick Start section.

- [ ] **Step 8: Add GIF to Other Features section**

Add:
```
- **GIF messages:** GIF picker (Giphy API) in action tiles. Trending + search with 500ms debounce. Download from Giphy → upload to Cloudinary → Cloudinary URL encrypted in E2E envelope. `Image.network` for native GIF animation. Tap to expand. API key via `--dart-define=GIPHY_API_KEY=...` (beta key in dev).
```

- [ ] **Step 9: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for GIF support"
```

---

### Task 17: Final commit (if needed)

- [ ] **Step 1: Run all tests one final time**

Run: `cd backend && npm test`
Run: `cd frontend && flutter test`

- [ ] **Step 2: Verify git status is clean**

Run: `git status`
Expected: Nothing to commit, working tree clean.
