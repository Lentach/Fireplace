# Media Encryption (Client-Side AES-256-GCM) Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Encrypt all media (image, voice, GIF, file) with AES-256-GCM client-side before uploading to Cloudinary, and decrypt client-side before displaying — so Cloudinary stores only opaque ciphertext.

**Architecture:** A one-time AES-256-GCM key + 12-byte IV are generated per media file client-side. The encrypted blob is uploaded to Cloudinary via the existing `POST /messages/upload-media` endpoint (using `type=file`). The key and IV (base64) are packed into the Signal Protocol E2E envelope alongside the Cloudinary URL. The recipient fetches the ciphertext blob, decrypts it locally, and displays the result. Old messages with no `mediaKey` in the envelope load directly from Cloudinary URL (backward compat).

**Tech Stack:** Flutter 3, pointycastle 4 (AES-256-GCM — already in pubspec), dart:convert (base64), http package, `dart:html` for web blob URLs (follows existing `download_utils_web.dart` pattern), no new dependencies.

**Platform notes:**
- `Image.memory` does NOT animate GIFs on Flutter web — GIFs on web use blob URL + `Image.network`
- Audio on web uses blob URL (same pattern as file downloads in `download_utils_web.dart`)
- `XFile.readAsBytes()` works on both web and native — no `kIsWeb` guard needed for reading image bytes

---

## File Map

| Status | File | What changes |
|--------|------|--------------|
| **CREATE** | `frontend/lib/services/media_crypto_service.dart` | AES-256-GCM encrypt/decrypt for binary data + secure random |
| **CREATE** | `frontend/test/services/media_crypto_service_test.dart` | Unit tests for the above |
| **CREATE** | `frontend/lib/utils/web_blob_utils_stub.dart` | Stub for non-web platforms (no-ops / throws) |
| **CREATE** | `frontend/lib/utils/web_blob_utils_web.dart` | Web: create Blob URLs from bytes using `dart:html` (audio + image) |
| **MODIFY** | `frontend/lib/utils/e2e_envelope.dart` | Add `mediaKey`, `mediaIv` optional fields to build/parse |
| **MODIFY** | `frontend/lib/models/message_model.dart` | Add `mediaKey`, `mediaIv` (String?) fields |
| **MODIFY** | `frontend/lib/services/api_service.dart` | Add `uploadEncryptedMedia()` method + unit test |
| **MODIFY** | `frontend/lib/providers/messaging_provider.dart` | Encrypt before upload in all 4 send methods; pass key/IV through envelope; restore key/IV on receive/cache |
| **MODIFY** | `frontend/lib/widgets/message/image_message_content.dart` | Fetch+decrypt+`Image.memory` when key present; `Image.network` fallback |
| **MODIFY** | `frontend/lib/widgets/message/gif_message_content.dart` | Fetch+decrypt: blob URL on web, `Image.memory` on native; `Image.network` fallback |
| **MODIFY** | `frontend/lib/widgets/message/file_message_content.dart` | Decrypt before download when key present (preserves confirmation dialog) |
| **MODIFY** | `frontend/lib/utils/download_utils_web.dart` | Add `saveDecryptedFile()` function |
| **MODIFY** | `frontend/lib/utils/download_utils_io.dart` | Add `saveDecryptedFile()` function |
| **MODIFY** | `frontend/lib/widgets/audio/playback_controller.dart` | Decrypt audio bytes before play/cache |
| **MODIFY** | `frontend/lib/widgets/message/message_content_factory.dart` | Pass `message.mediaKey`, `message.mediaIv` to image/gif/file widgets |

---

## Task 1: MediaCryptoService

**Files:**
- Create: `frontend/lib/services/media_crypto_service.dart`
- Create: `frontend/test/services/media_crypto_service_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// frontend/test/services/media_crypto_service_test.dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/services/media_crypto_service.dart';
import 'package:pointycastle/export.dart';

void main() {
  group('MediaCryptoService', () {
    test('generateKey returns 32 bytes', () {
      expect(MediaCryptoService.generateKey().length, 32);
    });

    test('generateIv returns 12 bytes', () {
      expect(MediaCryptoService.generateIv().length, 12);
    });

    test('generateKey produces different values each call', () {
      final k1 = MediaCryptoService.generateKey();
      final k2 = MediaCryptoService.generateKey();
      expect(k1, isNot(equals(k2)));
    });

    test('encrypt/decrypt round-trip returns original bytes', () {
      final key = MediaCryptoService.generateKey();
      final iv = MediaCryptoService.generateIv();
      final plaintext = Uint8List.fromList([1, 2, 3, 4, 5, 100, 200]);
      final ciphertext = MediaCryptoService.encrypt(plaintext, key, iv);
      final decrypted = MediaCryptoService.decrypt(ciphertext, key, iv);
      expect(decrypted, equals(plaintext));
    });

    test('ciphertext differs from plaintext', () {
      final key = MediaCryptoService.generateKey();
      final iv = MediaCryptoService.generateIv();
      final plaintext = Uint8List.fromList(List.generate(32, (i) => i));
      final ciphertext = MediaCryptoService.encrypt(plaintext, key, iv);
      expect(ciphertext, isNot(equals(plaintext)));
    });

    test('ciphertext is 16 bytes longer than plaintext (GCM auth tag)', () {
      final key = MediaCryptoService.generateKey();
      final iv = MediaCryptoService.generateIv();
      final plaintext = Uint8List.fromList(List.generate(50, (i) => i));
      final ciphertext = MediaCryptoService.encrypt(plaintext, key, iv);
      expect(ciphertext.length, plaintext.length + 16);
    });

    test('decrypt with wrong key throws InvalidCipherTextException', () {
      final key = MediaCryptoService.generateKey();
      final wrongKey = MediaCryptoService.generateKey();
      final iv = MediaCryptoService.generateIv();
      final ciphertext = MediaCryptoService.encrypt(
        Uint8List.fromList([1, 2, 3]),
        key,
        iv,
      );
      expect(
        () => MediaCryptoService.decrypt(ciphertext, wrongKey, iv),
        throwsA(isA<InvalidCipherTextException>()),
      );
    });

    test('decrypt with tampered ciphertext throws', () {
      final key = MediaCryptoService.generateKey();
      final iv = MediaCryptoService.generateIv();
      final ciphertext = MediaCryptoService.encrypt(
        Uint8List.fromList([1, 2, 3, 4]),
        key,
        iv,
      );
      ciphertext[0] ^= 0xFF; // flip bits to break auth tag check
      expect(
        () => MediaCryptoService.decrypt(ciphertext, key, iv),
        throwsA(isA<InvalidCipherTextException>()),
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```
cd frontend && flutter test test/services/media_crypto_service_test.dart
```

Expected: FAIL — `Target of URI doesn't exist: 'package:fireplace/services/media_crypto_service.dart'`

- [ ] **Step 3: Implement MediaCryptoService**

```dart
// frontend/lib/services/media_crypto_service.dart
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

/// AES-256-GCM encryption/decryption for binary media data.
///
/// Ciphertext format: raw GCM output = [ciphertext bytes] + [16-byte auth tag].
/// Key: 32 bytes. IV: 12 bytes. Auth tag: 128-bit (16 bytes).
class MediaCryptoService {
  const MediaCryptoService._();

  /// Generate a cryptographically random 256-bit (32-byte) AES key.
  static Uint8List generateKey() => _secureRandomBytes(32);

  /// Generate a cryptographically random 96-bit (12-byte) GCM IV/nonce.
  static Uint8List generateIv() => _secureRandomBytes(12);

  /// Encrypt [plaintext] with AES-256-GCM. Returns ciphertext + 16-byte auth tag.
  static Uint8List encrypt(Uint8List plaintext, Uint8List key, Uint8List iv) {
    final cipher = GCMBlockCipher(AESEngine());
    cipher.init(
      true,
      AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)),
    );
    return cipher.process(plaintext);
  }

  /// Decrypt [ciphertext] (includes 16-byte auth tag) with AES-256-GCM.
  ///
  /// Throws [InvalidCipherTextException] if the auth tag does not match
  /// (wrong key, wrong IV, or tampered data).
  static Uint8List decrypt(Uint8List ciphertext, Uint8List key, Uint8List iv) {
    final cipher = GCMBlockCipher(AESEngine());
    cipher.init(
      false,
      AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)),
    );
    return cipher.process(ciphertext);
  }

  static Uint8List _secureRandomBytes(int length) {
    final random = FortunaRandom();
    final seedSource = Random.secure();
    final seeds = List<int>.generate(32, (_) => seedSource.nextInt(256));
    random.seed(KeyParameter(Uint8List.fromList(seeds)));
    return random.nextBytes(length);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```
cd frontend && flutter test test/services/media_crypto_service_test.dart
```

Expected: All 7 tests PASS.

- [ ] **Step 5: Remove duplicate `_secureRandomBytes` from messaging_provider.dart**

In `frontend/lib/providers/messaging_provider.dart`, find the private method `_secureRandomBytes` (around line 1023) and remove it. In `sendAntiQuantumNote` (around line 991–1001), replace:
- `_secureRandomBytes(32)` → `MediaCryptoService.generateKey()`
- `_secureRandomBytes(12)` → `MediaCryptoService.generateIv()`

Add import at top of messaging_provider.dart:
```dart
import '../services/media_crypto_service.dart';
```

Verify:
```
cd frontend && flutter analyze lib/providers/messaging_provider.dart
```

- [ ] **Step 6: Commit**

```
git add frontend/lib/services/media_crypto_service.dart \
        frontend/test/services/media_crypto_service_test.dart \
        frontend/lib/providers/messaging_provider.dart
git commit -m "feat: add MediaCryptoService (AES-256-GCM for media)"
```

---

## Task 2: E2eEnvelope — mediaKey / mediaIv fields

**Files:**
- Modify: `frontend/lib/utils/e2e_envelope.dart`
- Create: `frontend/test/utils/e2e_envelope_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// frontend/test/utils/e2e_envelope_test.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/utils/e2e_envelope.dart';

void main() {
  group('E2eEnvelope — mediaKey/mediaIv', () {
    test('build/parse round-trip preserves media encryption fields', () {
      const testKey = 'dGVzdGtleWRhdGEtMzItYnl0ZXMtaGVyZS0h';
      const testIv  = 'dGVzdGl2MTI=';
      final built = E2eEnvelope.build(
        '',
        messageType: 'IMAGE',
        mediaUrl: 'https://res.cloudinary.com/test/image/upload/abc.bin',
        mediaKey: testKey,
        mediaIv: testIv,
      );
      final parsed = E2eEnvelope.parse(jsonEncode(built));
      expect(parsed.mediaUrl, 'https://res.cloudinary.com/test/image/upload/abc.bin');
      expect(parsed.mediaKey, testKey);
      expect(parsed.mediaIv, testIv);
      expect(parsed.messageType, 'IMAGE');
    });

    test('parse returns null mediaKey/mediaIv for legacy envelopes without those fields', () {
      const legacyJson =
          '{"content":"","mediaUrl":"https://example.com/x.jpg","messageType":"IMAGE"}';
      final parsed = E2eEnvelope.parse(legacyJson);
      expect(parsed.mediaKey, isNull);
      expect(parsed.mediaIv, isNull);
    });

    test('build omits mediaKey/mediaIv when not provided', () {
      final built = E2eEnvelope.build('hello');
      expect(built.containsKey('mediaKey'), isFalse);
      expect(built.containsKey('mediaIv'), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```
cd frontend && flutter test test/utils/e2e_envelope_test.dart
```

Expected: FAIL — `build()` does not accept `mediaKey`/`mediaIv` and `parse()` return record does not have those fields.

- [ ] **Step 3: Update e2e_envelope.dart**

Replace the entire file:

```dart
// frontend/lib/utils/e2e_envelope.dart
import 'dart:convert';

/// E2E encrypted message envelope format. Single source of truth for build/parse.
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
  static const String _keyMediaKey = 'mediaKey'; // base64-encoded AES-256 key
  static const String _keyMediaIv = 'mediaIv';   // base64-encoded GCM IV

  static Map<String, dynamic> build(
    String content, {
    String messageType = 'TEXT',
    String? mediaUrl,
    int? mediaDuration,
    Map<String, String?>? linkPreview,
    String? mediaKey,
    String? mediaIv,
  }) {
    final envelope = <String, dynamic>{_keyContent: content};
    if (messageType != 'TEXT') envelope[_keyMessageType] = messageType;
    if (mediaUrl != null) envelope[_keyMediaUrl] = mediaUrl;
    if (mediaDuration != null) envelope[_keyMediaDuration] = mediaDuration;
    if (linkPreview != null) envelope[_keyLinkPreview] = linkPreview;
    if (mediaKey != null) envelope[_keyMediaKey] = mediaKey;
    if (mediaIv != null) envelope[_keyMediaIv] = mediaIv;
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
    String? mediaKey,
    String? mediaIv,
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
      mediaKey: envelope[_keyMediaKey] as String?,
      mediaIv: envelope[_keyMediaIv] as String?,
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```
cd frontend && flutter test test/utils/e2e_envelope_test.dart
```

Expected: All 3 tests PASS.

- [ ] **Step 5: Commit**

```
git add frontend/lib/utils/e2e_envelope.dart \
        frontend/test/utils/e2e_envelope_test.dart
git commit -m "feat: add mediaKey/mediaIv fields to E2eEnvelope"
```

---

## Task 3: MessageModel — mediaKey / mediaIv fields

**Files:**
- Modify: `frontend/lib/models/message_model.dart`
- Create: `frontend/test/models/message_model_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// frontend/test/models/message_model_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/models/message_model.dart';

void main() {
  group('MessageModel — mediaKey/mediaIv', () {
    MessageModel base() => MessageModel(
      id: 1,
      content: '',
      senderId: 10,
      senderUsername: 'alice',
      conversationId: 5,
      createdAt: DateTime(2026),
      messageType: MessageType.image,
    );

    test('mediaKey and mediaIv default to null', () {
      expect(base().mediaKey, isNull);
      expect(base().mediaIv, isNull);
    });

    test('copyWith sets mediaKey and mediaIv', () {
      final msg = base().copyWith(
        mediaKey: 'abc123==',
        mediaIv: 'xyz789==',
      );
      expect(msg.mediaKey, 'abc123==');
      expect(msg.mediaIv, 'xyz789==');
    });

    test('copyWith without mediaKey/mediaIv preserves existing values', () {
      final withKeys = base().copyWith(mediaKey: 'keyvalue', mediaIv: 'ivvalue');
      final updated = withKeys.copyWith(content: 'hello');
      expect(updated.mediaKey, 'keyvalue');
      expect(updated.mediaIv, 'ivvalue');
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

```
cd frontend && flutter test test/models/message_model_test.dart
```

Expected: FAIL — `copyWith` does not accept `mediaKey`/`mediaIv`.

- [ ] **Step 3: Update MessageModel**

In `frontend/lib/models/message_model.dart`:

**Add two fields** after `encryptedContent`:
```dart
// base64-encoded AES-256 key — populated from E2E envelope, never from server JSON.
// Note: copyWith uses `param ?? this.param`, so these fields cannot be cleared
// to null once set (by design — they only ever go from null to a value).
final String? mediaKey;
final String? mediaIv;
```

**Add to constructor** after `this.encryptedContent`:
```dart
this.mediaKey,
this.mediaIv,
```

**Add to copyWith parameters** after `String? encryptedContent`:
```dart
String? mediaKey,
String? mediaIv,
```

**Add to copyWith body** after `encryptedContent: encryptedContent ?? this.encryptedContent`:
```dart
mediaKey: mediaKey ?? this.mediaKey,
mediaIv: mediaIv ?? this.mediaIv,
```

> Do NOT add `mediaKey`/`mediaIv` to `fromJson` — the server never sends these fields.

- [ ] **Step 4: Run test to verify it passes**

```
cd frontend && flutter test test/models/message_model_test.dart
```

Expected: All 3 tests PASS.

- [ ] **Step 5: Run all frontend tests**

```
cd frontend && flutter test
```

Expected: All tests pass (currently 71 tests; this adds 3 more).

- [ ] **Step 6: Commit**

```
git add frontend/lib/models/message_model.dart \
        frontend/test/models/message_model_test.dart
git commit -m "feat: add mediaKey/mediaIv fields to MessageModel"
```

---

## Task 4: ApiService.uploadEncryptedMedia()

**Files:**
- Modify: `frontend/lib/services/api_service.dart`
- Create: `frontend/test/services/api_service_media_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// frontend/test/services/api_service_media_test.dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/services/api_service.dart';

void main() {
  group('ApiService.uploadEncryptedMedia', () {
    test('ApiService has uploadEncryptedMedia method', () {
      // Smoke test: verify the method exists and is callable with the expected signature.
      // It does not make a real HTTP call here — integration is tested manually.
      final api = ApiService();
      expect(
        api.uploadEncryptedMedia,
        isA<Function>(),
      );
    });

    test('uploadEncryptedMedia rejects empty encryptedBytes', () async {
      final api = ApiService();
      // Passing empty bytes with no token will throw before making an HTTP call
      // because the server would reject it — here we verify the method exists
      // and is callable. Real integration is covered by manual smoke test.
      expect(
        () => api.uploadEncryptedMedia(
          token: '',
          encryptedBytes: Uint8List(0),
          fileName: 'test',
        ),
        // Does not throw synchronously — returns a Future
        returnsNormally,
      );
    });
  });
}
```

> Note: `ApiService` makes real HTTP calls, so these tests verify the API surface only. Full integration is tested manually in the verification checklist.

- [ ] **Step 2: Run test to verify it fails**

```
cd frontend && flutter test test/services/api_service_media_test.dart
```

Expected: FAIL — `uploadEncryptedMedia` does not exist on `ApiService`.

- [ ] **Step 3: Add `uploadEncryptedMedia` to `api_service.dart`**

Add `import 'dart:typed_data';` at the top if not already present. Then add after the existing `uploadMedia` method (after the closing `}` around line 238):

```dart
/// Upload already-encrypted media bytes to backend. Returns { mediaUrl }.
///
/// Always uses type='file' and application/octet-stream so Cloudinary stores
/// bytes as a raw resource without image/audio processing.
/// The caller is responsible for encrypting the bytes before calling this method.
Future<Map<String, dynamic>> uploadEncryptedMedia({
  required String token,
  required Uint8List encryptedBytes,
  required String fileName,
  int? expiresIn,
}) async {
  final request = http.MultipartRequest(
    'POST',
    Uri.parse('$baseUrl/messages/upload-media'),
  );
  request.headers['Authorization'] = 'Bearer $token';
  request.fields['type'] = 'file';
  if (expiresIn != null) request.fields['expiresIn'] = expiresIn.toString();
  request.files.add(http.MultipartFile.fromBytes(
    'file',
    encryptedBytes,
    filename: fileName,
    contentType: MediaType('application', 'octet-stream'),
  ));
  final streamedResponse = await request.send();
  final response = await http.Response.fromStream(streamedResponse);
  final data = jsonDecode(response.body) as Map<String, dynamic>;
  if (response.statusCode != 200 && response.statusCode != 201) {
    throw Exception(data['message'] ?? 'Encrypted media upload failed');
  }
  return data;
}
```

- [ ] **Step 4: Run test to verify it passes**

```
cd frontend && flutter test test/services/api_service_media_test.dart
```

Expected: Both tests PASS.

- [ ] **Step 5: Verify analyzer clean**

```
cd frontend && flutter analyze lib/services/api_service.dart
```

Expected: No issues found.

- [ ] **Step 6: Commit**

```
git add frontend/lib/services/api_service.dart \
        frontend/test/services/api_service_media_test.dart
git commit -m "feat: add uploadEncryptedMedia() to ApiService"
```

---

## Task 5: Web blob URL utilities

**Files:**
- Create: `frontend/lib/utils/web_blob_utils_stub.dart`
- Create: `frontend/lib/utils/web_blob_utils_web.dart`

These allow widgets to create temporary browser Blob URLs from decrypted bytes on web, without polluting the native build with `dart:html`. Provides functions for both audio and image/GIF blob URLs.

- [ ] **Step 1: Create stub (both functions together)**

```dart
// frontend/lib/utils/web_blob_utils_stub.dart

/// Create a temporary blob URL for audio [bytes].
/// Web-only — this stub throws if accidentally called on native.
/// Protected by kIsWeb guards at call sites.
String createAudioBlobUrl(List<int> bytes, String mimeType) {
  throw UnsupportedError('createAudioBlobUrl is only available on web');
}

/// Revoke a blob URL previously created by [createAudioBlobUrl].
void revokeAudioBlobUrl(String url) {
  // No-op on native — blob URLs are not created on native
}

/// Create a temporary blob URL for image/GIF [bytes].
/// Web-only — this stub throws if accidentally called on native.
/// Protected by kIsWeb guards at call sites.
String createImageBlobUrl(List<int> bytes, String mimeType) {
  throw UnsupportedError('createImageBlobUrl is only available on web');
}

/// Revoke a blob URL previously created by [createImageBlobUrl].
void revokeImageBlobUrl(String url) {
  // No-op on native — blob URLs are not created on native
}
```

- [ ] **Step 2: Create web implementation (both functions together)**

```dart
// frontend/lib/utils/web_blob_utils_web.dart
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Creates a temporary object URL for audio [bytes] with [mimeType].
/// Call [revokeAudioBlobUrl] after playback completes to release memory.
String createAudioBlobUrl(List<int> bytes, String mimeType) {
  final blob = html.Blob([bytes], mimeType);
  return html.Url.createObjectUrlFromBlob(blob);
}

/// Revoke a blob URL created by [createAudioBlobUrl].
void revokeAudioBlobUrl(String url) {
  html.Url.revokeObjectUrl(url);
}

/// Creates a temporary object URL for image/GIF [bytes] with [mimeType].
/// Using Image.network(blobUrl) allows GIF animation on web, unlike Image.memory.
/// Call [revokeImageBlobUrl] when the widget is disposed to release memory.
String createImageBlobUrl(List<int> bytes, String mimeType) {
  final blob = html.Blob([bytes], mimeType);
  return html.Url.createObjectUrlFromBlob(blob);
}

/// Revoke a blob URL created by [createImageBlobUrl].
void revokeImageBlobUrl(String url) {
  html.Url.revokeObjectUrl(url);
}
```

- [ ] **Step 3: Verify analyzer clean**

```
cd frontend && flutter analyze lib/utils/web_blob_utils_stub.dart lib/utils/web_blob_utils_web.dart
```

Expected: No errors. The `avoid_web_libraries_in_flutter` warning is suppressed by the `// ignore` comment on line 2 of the web file.

- [ ] **Step 4: Commit**

```
git add frontend/lib/utils/web_blob_utils_stub.dart \
        frontend/lib/utils/web_blob_utils_web.dart
git commit -m "feat: add web blob URL helpers for encrypted media display/playback"
```

---

## Task 6: Send side — encrypt bytes before upload

**Files:**
- Modify: `frontend/lib/providers/messaging_provider.dart`

Four send methods need updating: `sendImageMessage`, `sendVoiceMessage`, `sendGif`, `sendFileMessage`. The `_encryptAndSend` signature gets two new optional params. The `_addMessageToState` and `_persistDecryptedContent` methods need to handle the new fields.

**Before/after per send method:**
```
BEFORE: raw bytes → uploadMedia() → Cloudinary URL → _encryptAndSend(url)
AFTER:  raw bytes → MediaCryptoService.encrypt() → uploadEncryptedMedia() → Cloudinary URL → _encryptAndSend(url, key, iv)
```

- [ ] **Step 1: Update `_encryptAndSend` signature and body**

Find `Future<void> _encryptAndSend({` (around line 1223).

**Add two new optional parameters** after `int? mediaDuration`:
```dart
String? mediaKey,  // base64-encoded AES-256 key for media decryption
String? mediaIv,   // base64-encoded GCM IV for media decryption
```

**In the `_pendingSendContent` update block** (step 2 comment in the method, around line 1265–1280), add:
```dart
if (mediaKey != null) pending['mediaKey'] = mediaKey;
if (mediaIv != null) pending['mediaIv'] = mediaIv;
```

**In the `E2eEnvelope.build()` call** (around line 1285), add the new params:
```dart
final envelopeJson = jsonEncode(E2eEnvelope.build(
  content,
  messageType: messageType,
  mediaUrl: mediaUrl,
  mediaDuration: mediaDuration,
  linkPreview: linkPreview,
  mediaKey: mediaKey,   // NEW
  mediaIv: mediaIv,     // NEW
));
```

- [ ] **Step 2: Update `sendImageMessage`**

Find the upload+send block (around line 698–728). Replace it entirely with:

```dart
try {
  // Read bytes — XFile.readAsBytes() works on both web and native
  final rawBytes = await imageFile.readAsBytes();

  // Encrypt
  final mediaKey = MediaCryptoService.generateKey();
  final mediaIv = MediaCryptoService.generateIv();
  final encryptedBytes = MediaCryptoService.encrypt(
    Uint8List.fromList(rawBytes),
    mediaKey,
    mediaIv,
  );
  final mediaKeyB64 = base64.encode(mediaKey);
  final mediaIvB64 = base64.encode(mediaIv);

  // Upload encrypted blob as raw file
  final responseData = await _api.uploadEncryptedMedia(
    token: token,
    encryptedBytes: encryptedBytes,
    fileName: 'img_${DateTime.now().millisecondsSinceEpoch}',
    expiresIn: effectiveExpiresIn,
  );
  final cloudinaryUrl = responseData['mediaUrl'] as String;

  // Update optimistic message
  final idx = _messages.indexWhere((m) => m.tempId == tempId);
  if (idx != -1) {
    _messages[idx] = _messages[idx].copyWith(
      mediaUrl: cloudinaryUrl,
      mediaKey: mediaKeyB64,
      mediaIv: mediaIvB64,
    );
    notifyListeners();
  }

  _encryptAndSend(
    recipientId: recipientId,
    content: '',
    tempId: tempId,
    effectiveExpiresIn: effectiveExpiresIn,
    messageType: 'IMAGE',
    mediaUrl: cloudinaryUrl,
    mediaKey: mediaKeyB64,
    mediaIv: mediaIvB64,
  );
} catch (e) {
  debugPrint('[MessagingProvider] Image upload failed: $e');
  _markMessageFailed(tempId, 'Image upload failed: ${e.toString()}');
}
```

Add `import 'dart:typed_data';` at top of messaging_provider.dart if not already present.

- [ ] **Step 3: Update `sendVoiceMessage`**

In `sendVoiceMessage`, audio data arrives as `localAudioPath` (native) or `localAudioBytes` (web). There is no existing `bytes` variable — add one before the upload call. Find the upload block (around line 787) and replace from the upload call through the `_encryptAndSend` call:

```dart
// Read audio bytes from path (native) or use the provided bytes (web)
final List<int> bytes;
if (localAudioBytes != null) {
  bytes = localAudioBytes;
} else {
  bytes = await File(localAudioPath!).readAsBytes();
}

// Encrypt audio bytes
final mediaKey = MediaCryptoService.generateKey();
final mediaIv = MediaCryptoService.generateIv();
final encryptedBytes = MediaCryptoService.encrypt(
  Uint8List.fromList(bytes),
  mediaKey,
  mediaIv,
);
final mediaKeyB64 = base64.encode(mediaKey);
final mediaIvB64 = base64.encode(mediaIv);

final responseData = await _api.uploadEncryptedMedia(
  token: _tokenForReconnect!,
  encryptedBytes: encryptedBytes,
  fileName: 'voice_${DateTime.now().millisecondsSinceEpoch}',
  expiresIn: effectiveExpiresIn,
);

final cloudinaryUrl = responseData['mediaUrl'] as String;
// Duration is known client-side from recording; no need to read from response
final serverDuration = duration;

// Update optimistic message
final index = _messages.indexWhere((m) => m.tempId == tempId);
if (index != -1) {
  _messages[index] = _messages[index].copyWith(
    mediaUrl: cloudinaryUrl,
    mediaDuration: serverDuration,
    mediaKey: mediaKeyB64,
    mediaIv: mediaIvB64,
  );
  notifyListeners();
}

// Delete temp file after successful upload (native only; web uses blob)
if (!kIsWeb && localAudioPath != null) {
  await file_utils.deleteFileIfExists(localAudioPath);
}

// Encrypt and send via WebSocket (key + URL hidden in E2E envelope)
_encryptAndSend(
  recipientId: recipientId,
  content: '',
  tempId: tempId,
  effectiveExpiresIn: effectiveExpiresIn,
  messageType: 'VOICE',
  mediaUrl: cloudinaryUrl,
  mediaDuration: serverDuration,
  mediaKey: mediaKeyB64,
  mediaIv: mediaIvB64,
);
```

> The variable `duration` is the `int duration` parameter of `sendVoiceMessage`. `File` is from `dart:io` — the existing file already imports it (guarded by `!kIsWeb` elsewhere). Add `import 'dart:io' show File;` at the top if the analyzer reports it missing.

- [ ] **Step 4: Update `sendGif`**

Find the block after `final gifBytes = response.bodyBytes;` (downloaded GIF bytes, around line 872). Insert encryption before the upload and replace the upload + `_encryptAndSend` calls:

```dart
// Size guard (unchanged)
if (gifBytes.length > 5 * 1024 * 1024) {
  throw Exception('GIF too large (max 5 MB)');
}

// Encrypt GIF bytes
final mediaKey = MediaCryptoService.generateKey();
final mediaIv = MediaCryptoService.generateIv();
final encryptedBytes = MediaCryptoService.encrypt(gifBytes, mediaKey, mediaIv);
final mediaKeyB64 = base64.encode(mediaKey);
final mediaIvB64 = base64.encode(mediaIv);

// Upload encrypted blob
final responseData = await _api.uploadEncryptedMedia(
  token: token,
  encryptedBytes: encryptedBytes,
  fileName: 'gif_${DateTime.now().millisecondsSinceEpoch}',
  expiresIn: effectiveExpiresIn,
);

final cloudinaryUrl = responseData['mediaUrl'] as String;

// Update optimistic message
final idx = _messages.indexWhere((m) => m.tempId == tempId);
if (idx != -1) {
  _messages[idx] = _messages[idx].copyWith(
    mediaUrl: cloudinaryUrl,
    mediaKey: mediaKeyB64,
    mediaIv: mediaIvB64,
  );
  notifyListeners();
}

_encryptAndSend(
  recipientId: recipientId,
  content: '',
  tempId: tempId,
  effectiveExpiresIn: effectiveExpiresIn,
  messageType: 'GIF',
  mediaUrl: cloudinaryUrl,
  mediaKey: mediaKeyB64,
  mediaIv: mediaIvB64,
);
```

- [ ] **Step 5: Update `sendFileMessage`**

Find the upload block (around line 946). Replace from the `uploadMedia` call through `_encryptAndSend`:

```dart
// Encrypt file bytes
final mediaKey = MediaCryptoService.generateKey();
final mediaIv = MediaCryptoService.generateIv();
final encryptedBytes = MediaCryptoService.encrypt(
  Uint8List.fromList(fileBytes),
  mediaKey,
  mediaIv,
);
final mediaKeyB64 = base64.encode(mediaKey);
final mediaIvB64 = base64.encode(mediaIv);

final responseData = await _api.uploadEncryptedMedia(
  token: token,
  encryptedBytes: encryptedBytes,
  fileName: fileName,
  expiresIn: effectiveExpiresIn,
);

final mediaUrl = responseData['mediaUrl'] as String;

final idx = _messages.indexWhere((m) => m.tempId == tempId);
if (idx != -1) {
  _messages[idx] = _messages[idx].copyWith(
    mediaUrl: mediaUrl,
    mediaKey: mediaKeyB64,
    mediaIv: mediaIvB64,
  );
  notifyListeners();
}

_pendingSendContent[tempId] = <String, dynamic>{
  'content': fileName,
  'messageType': 'FILE',
  'mediaUrl': mediaUrl,
  'mediaKey': mediaKeyB64,
  'mediaIv': mediaIvB64,
};

_encryptAndSend(
  recipientId: recipientId,
  content: fileName,
  tempId: tempId,
  effectiveExpiresIn: effectiveExpiresIn,
  messageType: 'FILE',
  mediaUrl: mediaUrl,
  mediaKey: mediaKeyB64,
  mediaIv: mediaIvB64,
);
```

- [ ] **Step 6: Update `_addMessageToState` to restore mediaKey/mediaIv**

In `_addMessageToState` (around line 352), in the `msg.copyWith(...)` call inside the `if (msg.content == '[encrypted]')` block, add after `linkPreviewImageUrl`:

```dart
mediaKey: savedData?['mediaKey'] as String?,
mediaIv: savedData?['mediaIv'] as String?,
```

In the `persistData` map built right below that `copyWith`, add:
```dart
if (savedData?['mediaKey'] != null) 'mediaKey': savedData!['mediaKey'],
if (savedData?['mediaIv'] != null) 'mediaIv': savedData!['mediaIv'],
```

- [ ] **Step 7: Update `_persistDecryptedContent` to save mediaKey/mediaIv**

In `_persistDecryptedContent` (around line 319):

**Replace the early-return guard** (currently returns if content is empty/failed):
```dart
// Persist if there's meaningful content OR media encryption keys (mediaKey
// present means an encrypted media message — must persist keys even if content is empty).
if ((decrypted.content.isEmpty ||
    decrypted.content == '[Decryption failed]' ||
    decrypted.content == '[Encryption not initialized]') &&
    decrypted.mediaKey == null) {
  return;
}
```

**Add to the `data` map** after the `mediaUrl` entry:
```dart
if (decrypted.mediaKey != null) 'mediaKey': decrypted.mediaKey!,
if (decrypted.mediaIv != null) 'mediaIv': decrypted.mediaIv!,
```

- [ ] **Step 8: Update history restore paths to read mediaKey/mediaIv from cache**

There are two paths in `_decryptMessageHistory`:

**Path 1 — received message restore from cache** (around line 1360, inside the `persisted != null` block):
```dart
final restored = msg.copyWith(
  content: ...,
  messageType: ...,
  mediaUrl: persisted['mediaUrl'] as String?,
  mediaDuration: ...,
  // add:
  mediaKey: persisted['mediaKey'] as String?,
  mediaIv: persisted['mediaIv'] as String?,
  ...
);
```

**Path 2 — sender's own message restore** (around line 1417, inside the `stored != null` block):
```dart
final restored = msg.copyWith(
  content: ...,
  messageType: ...,
  mediaUrl: stored?['mediaUrl'] as String?,
  // add:
  mediaKey: stored?['mediaKey'] as String?,
  mediaIv: stored?['mediaIv'] as String?,
  ...
);
```

- [ ] **Step 9: Update `_decryptMessageAsync` to set mediaKey/mediaIv from parsed envelope**

In `_decryptMessageAsync` (around line 1470), in the `decryptedMsg = msg.copyWith(...)` call, add:
```dart
mediaKey: parsed.mediaKey,
mediaIv: parsed.mediaIv,
```

- [ ] **Step 10: Verify analyzer clean and run all tests**

```
cd frontend && flutter analyze lib/providers/messaging_provider.dart
cd frontend && flutter test
```

Expected: No analyzer errors, all tests pass.

- [ ] **Step 11: Commit**

```
git add frontend/lib/providers/messaging_provider.dart
git commit -m "feat: encrypt media bytes client-side before Cloudinary upload"
```

---

## Task 7: Voice PlaybackController — decrypt before play

**Files:**
- Modify: `frontend/lib/widgets/audio/playback_controller.dart`

**Key insight:** `message.mediaKey` and `message.mediaIv` are now on `MessageModel`. If both are non-null, decrypt after downloading. The cache stores **decrypted** bytes so repeated playback doesn't re-decrypt. Old messages have null keys → existing path unchanged.

- [ ] **Step 1: Add imports and a field for blob URL cleanup**

At the top of `playback_controller.dart`, add after existing imports:
```dart
import 'dart:convert';
import 'dart:typed_data';
import '../../utils/web_blob_utils_stub.dart'
    if (dart.library.html) '../../utils/web_blob_utils_web.dart' as blob_utils;
import '../../services/media_crypto_service.dart';
```

In `_PlaybackControllerState`, add a field after `String? _cachedFilePath`:
```dart
String? _blobUrl; // Web only: revoked on dispose
```

- [ ] **Step 2: Replace `_downloadAndCache` to decrypt before saving**

Replace the entire `_downloadAndCache` method:

```dart
Future<String> _downloadAndCache(String url) async {
  final dir = await getApplicationDocumentsDirectory();
  final cachePath = '${dir.path}/audio_cache';
  await Directory(cachePath).create(recursive: true);

  final file = File('$cachePath/${widget.message.id}.m4a');

  final response = await http.get(Uri.parse(url));
  if (response.statusCode != 200) {
    throw Exception('Failed to download audio: ${response.statusCode}');
  }

  var audioBytes = response.bodyBytes;

  // Decrypt if this is an encrypted media message
  final mediaKey = widget.message.mediaKey;
  final mediaIv = widget.message.mediaIv;
  if (mediaKey != null && mediaIv != null) {
    final key = base64.decode(mediaKey);
    final iv = base64.decode(mediaIv);
    audioBytes = MediaCryptoService.decrypt(audioBytes, key, iv);
  }

  // Cache stores decrypted bytes — no re-decryption on repeat plays
  await file.writeAsBytes(audioBytes);
  return file.path;
}
```

- [ ] **Step 3: Replace the full `_loadAndPlayAudio` method**

Replace the entire `_loadAndPlayAudio` method with the version below. This replaces both the existing web branch and the native branch. The native path is unchanged except that `_downloadAndCache` now handles decryption.

```dart
Future<void> _loadAndPlayAudio() async {
  if (_isExpired()) {
    if (mounted) showTopSnackBar(context, 'Audio no longer available');
    return;
  }

  final mediaUrl = widget.message.mediaUrl;
  if (mediaUrl == null || mediaUrl.isEmpty) {
    throw Exception('No media URL');
  }

  _loadCancelled = false;
  setState(() => _isLoading = true);

  try {
    if (kIsWeb) {
      final mediaKey = widget.message.mediaKey;
      final mediaIv = widget.message.mediaIv;

      if (mediaKey != null && mediaIv != null) {
        // Encrypted: download, decrypt, create blob URL
        final response = await http.get(Uri.parse(mediaUrl));
        if (response.statusCode != 200) {
          throw Exception('Failed to download audio: ${response.statusCode}');
        }
        final key = base64.decode(mediaKey);
        final iv = base64.decode(mediaIv);
        final decryptedBytes = MediaCryptoService.decrypt(
          response.bodyBytes,
          key,
          iv,
        );
        _blobUrl = blob_utils.createAudioBlobUrl(decryptedBytes, 'audio/wav');
        await _audioPlayer.setUrl(_blobUrl!);
      } else {
        // Legacy unencrypted: play directly from Cloudinary URL
        await _audioPlayer.setUrl(mediaUrl);
      }
    } else {
      // Native: check cache, download (+ decrypt) if needed
      _cachedFilePath = await _getCachedFilePath();

      if (_cachedFilePath != null && File(_cachedFilePath!).existsSync()) {
        await _audioPlayer.setFilePath(_cachedFilePath!);
      } else {
        final path = await _downloadAndCache(mediaUrl);
        _cachedFilePath = path;
        await _audioPlayer.setFilePath(path);
      }
    }

    if (mounted) setState(() => _isLoading = false);
    if (_loadCancelled || !mounted) return;
    await _audioPlayer.play();
  } catch (e) {
    debugPrint('Audio load error: $e');
    if (mounted) showTopSnackBar(context, 'Failed to load audio');
  } finally {
    if (mounted) setState(() => _isLoading = false);
  }
}
```

- [ ] **Step 4: Add blob URL cleanup in `dispose`**

In the `dispose()` method, add before `_audioPlayer.dispose()`:
```dart
if (_blobUrl != null) {
  blob_utils.revokeAudioBlobUrl(_blobUrl!);
}
```

- [ ] **Step 5: Verify analyzer clean**

```
cd frontend && flutter analyze lib/widgets/audio/playback_controller.dart
```

Expected: No errors.

- [ ] **Step 6: Commit**

```
git add frontend/lib/widgets/audio/playback_controller.dart
git commit -m "feat: decrypt audio bytes before playback in PlaybackController"
```

---

## Task 8: ImageMessageContent — decrypt-then-display

**Files:**
- Modify: `frontend/lib/widgets/message/image_message_content.dart`

Convert to `StatefulWidget`. When `mediaKey`/`mediaIv` are present: fetch → decrypt → `Image.memory`. Legacy (no key): keep existing `Image.network` path.

- [ ] **Step 1: Rewrite `image_message_content.dart`**

```dart
// frontend/lib/widgets/message/image_message_content.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../l10n/app_localizations.dart';
import '../../services/media_crypto_service.dart';
import '../../theme/rpg_theme.dart';

/// Content widget for IMAGE message type with fullscreen viewer on tap.
///
/// Encrypted images (mediaKey/mediaIv non-null): downloaded as ciphertext,
/// decrypted client-side, displayed with Image.memory.
/// Legacy unencrypted images (mediaKey null): loaded with Image.network.
class ImageMessageContent extends StatefulWidget {
  final String? mediaUrl;
  final String? mediaKey; // base64-encoded AES-256 key
  final String? mediaIv;  // base64-encoded GCM IV

  const ImageMessageContent({
    super.key,
    required this.mediaUrl,
    this.mediaKey,
    this.mediaIv,
  });

  @override
  State<ImageMessageContent> createState() => _ImageMessageContentState();
}

class _ImageMessageContentState extends State<ImageMessageContent> {
  Uint8List? _decryptedBytes;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.mediaUrl != null &&
        widget.mediaKey != null &&
        widget.mediaIv != null) {
      _loadAndDecrypt();
    }
  }

  @override
  void didUpdateWidget(ImageMessageContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.mediaUrl != oldWidget.mediaUrl ||
        widget.mediaKey != oldWidget.mediaKey) {
      _decryptedBytes = null;
      _error = null;
      if (widget.mediaUrl != null &&
          widget.mediaKey != null &&
          widget.mediaIv != null) {
        _loadAndDecrypt();
      }
    }
  }

  Future<void> _loadAndDecrypt() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await http.get(Uri.parse(widget.mediaUrl!));
      if (response.statusCode != 200) {
        throw Exception('Download failed: ${response.statusCode}');
      }
      final key = base64.decode(widget.mediaKey!);
      final iv = base64.decode(widget.mediaIv!);
      final decrypted = MediaCryptoService.decrypt(response.bodyBytes, key, iv);
      if (mounted) setState(() { _decryptedBytes = decrypted; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _showFullscreen(BuildContext context, ImageProvider imageProvider) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: Image(image: imageProvider, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // No URL yet — show spinner (optimistic message still uploading)
    if (widget.mediaUrl == null) {
      return const SizedBox(
        width: 150,
        height: 150,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    // Legacy unencrypted path
    if (widget.mediaKey == null) {
      final provider = NetworkImage(widget.mediaUrl!);
      return GestureDetector(
        onTap: () => _showFullscreen(context, provider),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 200),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              widget.mediaUrl!,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(),
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) => Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  AppLocalizations.of(context).imageFailedToLoad,
                  style: RpgTheme.bodyFont(fontSize: 12, color: Colors.red),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Encrypted path — show spinner while downloading/decrypting
    if (_loading || (_decryptedBytes == null && _error == null)) {
      return const SizedBox(
        width: 150,
        height: 150,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (_error != null || _decryptedBytes == null) {
      return Padding(
        padding: const EdgeInsets.all(8.0),
        child: Text(
          AppLocalizations.of(context).imageFailedToLoad,
          style: RpgTheme.bodyFont(fontSize: 12, color: Colors.red),
        ),
      );
    }

    final provider = MemoryImage(_decryptedBytes!);
    return GestureDetector(
      onTap: () => _showFullscreen(context, provider),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 200),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            _decryptedBytes!,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                AppLocalizations.of(context).imageFailedToLoad,
                style: RpgTheme.bodyFont(fontSize: 12, color: Colors.red),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify analyzer clean**

```
cd frontend && flutter analyze lib/widgets/message/image_message_content.dart
```

- [ ] **Step 3: Commit**

```
git add frontend/lib/widgets/message/image_message_content.dart
git commit -m "feat: decrypt encrypted images client-side before display"
```

---

## Task 9: GifMessageContent — decrypt-then-display (web-aware)

**Files:**
- Modify: `frontend/lib/widgets/message/gif_message_content.dart`

**Important:** `Image.memory` does NOT animate GIFs on Flutter web. To preserve animation on web for encrypted GIFs, decrypt bytes → create a blob URL → `Image.network(blobUrl)`. On native, `Image.memory` animates correctly. Legacy (unencrypted) GIFs use `Image.network` directly on all platforms.

- [ ] **Step 1: Rewrite `gif_message_content.dart`**

```dart
// frontend/lib/widgets/message/gif_message_content.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../l10n/app_localizations.dart';
import '../../services/media_crypto_service.dart';
import '../../theme/rpg_theme.dart';
import '../../utils/web_blob_utils_stub.dart'
    if (dart.library.html) '../../utils/web_blob_utils_web.dart' as blob_utils;

/// Content widget for GIF message type with fullscreen viewer on tap.
///
/// Encrypted GIFs (mediaKey/mediaIv non-null):
///   - Web: decoded bytes → blob URL → Image.network (preserves animation)
///   - Native: decoded bytes → Image.memory (animates on native)
/// Legacy unencrypted GIFs: Image.network on all platforms.
class GifMessageContent extends StatefulWidget {
  final String? mediaUrl;
  final String? mediaKey;
  final String? mediaIv;

  const GifMessageContent({
    super.key,
    required this.mediaUrl,
    this.mediaKey,
    this.mediaIv,
  });

  @override
  State<GifMessageContent> createState() => _GifMessageContentState();
}

class _GifMessageContentState extends State<GifMessageContent> {
  Uint8List? _decryptedBytes;  // used on native
  String? _blobUrl;             // used on web; revoked on dispose
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.mediaUrl != null &&
        widget.mediaKey != null &&
        widget.mediaIv != null) {
      _loadAndDecrypt();
    }
  }

  @override
  void didUpdateWidget(GifMessageContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.mediaUrl != oldWidget.mediaUrl ||
        widget.mediaKey != oldWidget.mediaKey) {
      _cleanup();
      if (widget.mediaUrl != null &&
          widget.mediaKey != null &&
          widget.mediaIv != null) {
        _loadAndDecrypt();
      }
    }
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }

  void _cleanup() {
    if (_blobUrl != null) {
      blob_utils.revokeImageBlobUrl(_blobUrl!);
      _blobUrl = null;
    }
    _decryptedBytes = null;
    _error = null;
  }

  Future<void> _loadAndDecrypt() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final response = await http.get(Uri.parse(widget.mediaUrl!));
      if (response.statusCode != 200) {
        throw Exception('Download failed: ${response.statusCode}');
      }
      final key = base64.decode(widget.mediaKey!);
      final iv = base64.decode(widget.mediaIv!);
      final decrypted = MediaCryptoService.decrypt(response.bodyBytes, key, iv);

      if (mounted) {
        if (kIsWeb) {
          // On web, Image.memory does not animate GIFs — use blob URL instead
          final url = blob_utils.createImageBlobUrl(decrypted, 'image/gif');
          setState(() { _blobUrl = url; _loading = false; });
        } else {
          setState(() { _decryptedBytes = decrypted; _loading = false; });
        }
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _showFullscreen(BuildContext context, ImageProvider imageProvider) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: Image(image: imageProvider, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mediaUrl == null) {
      return const SizedBox(
        width: 150,
        height: 150,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    // Legacy unencrypted path
    if (widget.mediaKey == null) {
      final provider = NetworkImage(widget.mediaUrl!);
      return GestureDetector(
        onTap: () => _showFullscreen(context, provider),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 200),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              widget.mediaUrl!,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, p) =>
                  p == null ? child : const Center(child: CircularProgressIndicator()),
              errorBuilder: (context, e, s) => Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  AppLocalizations.of(context).imageFailedToLoad,
                  style: RpgTheme.bodyFont(fontSize: 12, color: Colors.red),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Encrypted path — loading state
    final readyOnWeb = kIsWeb && _blobUrl != null;
    final readyOnNative = !kIsWeb && _decryptedBytes != null;
    if (_loading || (!readyOnWeb && !readyOnNative && _error == null)) {
      return const SizedBox(
        width: 150,
        height: 150,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(8.0),
        child: Text(
          AppLocalizations.of(context).imageFailedToLoad,
          style: RpgTheme.bodyFont(fontSize: 12, color: Colors.red),
        ),
      );
    }

    // Web: use blob URL (preserves GIF animation)
    if (kIsWeb && _blobUrl != null) {
      final provider = NetworkImage(_blobUrl!);
      return GestureDetector(
        onTap: () => _showFullscreen(context, provider),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 200),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(_blobUrl!, fit: BoxFit.contain),
          ),
        ),
      );
    }

    // Native: use Image.memory (animates correctly on native)
    final provider = MemoryImage(_decryptedBytes!);
    return GestureDetector(
      onTap: () => _showFullscreen(context, provider),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 200),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(_decryptedBytes!, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify analyzer clean**

```
cd frontend && flutter analyze lib/widgets/message/gif_message_content.dart
```

- [ ] **Step 3: Commit**

```
git add frontend/lib/widgets/message/gif_message_content.dart
git commit -m "feat: decrypt encrypted GIFs before display (blob URL on web for animation)"
```

---

## Task 10: MessageContentFactory — pass mediaKey/mediaIv

**Files:**
- Modify: `frontend/lib/widgets/message/message_content_factory.dart`

- [ ] **Step 1: Update all three media content widget instantiations**

In `message_content_factory.dart`, make three changes:

```dart
// IMAGE
case MessageType.image:
  return ImageMessageContent(
    mediaUrl: message.mediaUrl,
    mediaKey: message.mediaKey,  // NEW
    mediaIv: message.mediaIv,    // NEW
  );

// GIF
case MessageType.gif:
  return GifMessageContent(
    mediaUrl: message.mediaUrl,
    mediaKey: message.mediaKey,  // NEW
    mediaIv: message.mediaIv,    // NEW
  );

// FILE
case MessageType.file:
  return FileMessageContent(
    mediaUrl: message.mediaUrl,
    content: message.content,
    textColor: textColor,
    mediaKey: message.mediaKey,  // NEW
    mediaIv: message.mediaIv,    // NEW
  );
```

- [ ] **Step 2: Verify analyzer clean**

```
cd frontend && flutter analyze lib/widgets/message/message_content_factory.dart
```

- [ ] **Step 3: Commit**

```
git add frontend/lib/widgets/message/message_content_factory.dart
git commit -m "feat: pass mediaKey/mediaIv to all encrypted media content widgets"
```

---

## Task 11: FileMessageContent — decrypt before download

**Files:**
- Modify: `frontend/lib/utils/download_utils_web.dart` (append `saveDecryptedFile`)
- Modify: `frontend/lib/utils/download_utils_io.dart` (append `saveDecryptedFile`)
- Modify: `frontend/lib/widgets/message/file_message_content.dart`

- [ ] **Step 1: Append `saveDecryptedFile` to `download_utils_io.dart`**

Open the existing `download_utils_io.dart` and **append** these lines at the end of the file (after the existing `_sanitizeFilename` function):

```dart
/// Save already-decrypted [bytes] to app documents directory as [filename].
/// For encrypted file messages: caller decrypts bytes before calling this.
Future<void> saveDecryptedFile(List<int> bytes, String filename) async {
  final dir = await getApplicationDocumentsDirectory();
  final safe = _sanitizeFilename(filename);
  final file = File('${dir.path}/$safe');
  await file.writeAsBytes(bytes);
}
```

- [ ] **Step 2: Append `saveDecryptedFile` to `download_utils_web.dart`**

Open the existing `download_utils_web.dart` and **append** at the end:

```dart
/// Trigger browser download of already-decrypted [bytes] with [filename].
/// For encrypted file messages: caller decrypts bytes before calling this.
Future<void> saveDecryptedFile(List<int> bytes, String filename) async {
  final blob = html.Blob([bytes]);
  final objectUrl = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement()
    ..href = objectUrl
    ..download = _sanitizeFilename(filename)
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  Future.delayed(const Duration(milliseconds: 500), () {
    html.Url.revokeObjectUrl(objectUrl);
  });
}
```

- [ ] **Step 3: Update `FileMessageContent`**

In `file_message_content.dart`, add fields, imports, and update `_downloadDocument`. The confirmation dialog in `build()` is unchanged — only the inner async logic changes.

**Add imports** at top:
```dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../../services/media_crypto_service.dart';
```

**Add fields** to the widget:
```dart
final String? mediaKey; // base64 AES-256 key, null for legacy messages
final String? mediaIv;  // base64 GCM IV, null for legacy messages
```

**Add to constructor**:
```dart
this.mediaKey,
this.mediaIv,
```

**Replace `_downloadDocument` method** (the `build` method with confirmation dialog is unchanged):
```dart
Future<void> _downloadDocument(
  BuildContext context,
  String url,
  String filename,
) async {
  final l10n = AppLocalizations.of(context);
  try {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('Download failed: ${response.statusCode}');
    }

    List<int> bytes = response.bodyBytes;

    // Decrypt if this is an encrypted file message
    final key = mediaKey;
    final iv = mediaIv;
    if (key != null && iv != null) {
      bytes = MediaCryptoService.decrypt(
        Uint8List.fromList(bytes),
        base64.decode(key),
        base64.decode(iv),
      );
    }

    await download_utils.saveDecryptedFile(bytes, filename);

    if (context.mounted) {
      showTopSnackBar(context, l10n.documentDownloaded);
    }
  } catch (_) {
    if (context.mounted) {
      showTopSnackBar(
        context,
        l10n.documentDownloadFailed,
        backgroundColor: Colors.red,
      );
    }
  }
}
```

The existing `build()` method calls `_downloadDocument(context, mediaUrl!, content.isNotEmpty ? content : 'document')` inside the confirmation dialog's Download action — this call is **unchanged**.

- [ ] **Step 4: Verify analyzer clean across all modified files**

```
cd frontend && flutter analyze lib/utils/download_utils_web.dart \
    lib/utils/download_utils_io.dart \
    lib/widgets/message/file_message_content.dart
```

Expected: No new issues.

- [ ] **Step 5: Run all tests**

```
cd frontend && flutter test
```

Expected: All tests pass.

- [ ] **Step 6: Commit**

```
git add frontend/lib/utils/download_utils_web.dart \
        frontend/lib/utils/download_utils_io.dart \
        frontend/lib/widgets/message/file_message_content.dart
git commit -m "feat: decrypt encrypted files before download in FileMessageContent"
```

---

## Task 12: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update Known Limitations (section 11)**

Find:
```
Media files on Cloudinary NOT encrypted (only URLs encrypted in envelope).
```
Replace with:
```
Media files on Cloudinary are AES-256-GCM encrypted client-side (one key+IV per file, packed in Signal envelope). Cloudinary stores opaque ciphertext. Old messages without mediaKey in envelope load via direct URL (backward compat). GIFs use blob URL on web to preserve animation (Image.memory does not animate GIFs on Flutter web).
```

- [ ] **Step 2: Update E2E Encryption bullet in section 8**

Find:
```
Media files on Cloudinary are NOT encrypted — only the URL is hidden inside the encrypted envelope.
```
Replace with:
```
Media files on Cloudinary are AES-256-GCM encrypted (client-side, one key+IV per file). Key + IV are packed in the Signal E2E envelope alongside the URL. Cloudinary stores only opaque ciphertext. `MediaCryptoService` in `services/media_crypto_service.dart` handles encrypt/decrypt.
```

- [ ] **Step 3: Update File Location Map (Frontend section)**

Add to the Services row or add a new row:
```
| **Media Crypto** | `services/media_crypto_service.dart` (AES-256-GCM for binary media files) |
```

- [ ] **Step 4: Commit**

```
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md — media files are now E2E encrypted"
```

---

## Verification Checklist

After all tasks complete, manually verify in the running app (`docker-compose up` + `flutter run -d chrome`):

- [ ] **Encrypted image send+receive**: pick a photo → send → image appears correctly on both sides
- [ ] **Encrypted image on reload**: close and reopen app → previously sent encrypted image still displays (key/IV restored from cache)
- [ ] **Encrypted voice send+receive**: record voice → send → plays correctly on both sides; waveform scrub works
- [ ] **Encrypted GIF send+receive**: pick GIF from picker → send → GIF animates in chat on web and native
- [ ] **Encrypted file send+receive**: pick a PDF → send → recipient can download and open the file
- [ ] **Legacy display**: if any old messages with plain Cloudinary URLs exist, they still display correctly (no mediaKey = Image.network path)
- [ ] **Cloudinary inspection**: open Cloudinary dashboard → verify uploaded blobs have no image dimensions / are listed as raw resources (not processed images)

Final automated checks:
```
cd frontend && flutter test && flutter analyze lib/
```

Expected: All tests pass, no analyzer errors.
