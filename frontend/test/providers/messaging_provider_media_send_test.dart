import 'dart:typed_data';

import 'package:fireplace/models/message_model.dart';
import 'package:fireplace/providers/conversations_provider.dart';
import 'package:fireplace/providers/messaging_provider.dart';
import 'package:fireplace/services/api_service.dart';
import 'package:fireplace/services/encrypted_media_upload_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

/// Fake upload service: records call args, fires onEncrypted (so the provider
/// writes pending content), then either returns a canned result or throws.
class _FakeMediaUpload extends EncryptedMediaUploadService {
  _FakeMediaUpload({this.throwOnUpload})
      : super(api: ApiService(baseUrl: 'http://test'));

  final Object? throwOnUpload;
  final List<Map<String, Object?>> calls = [];
  String? capturedKey;

  @override
  Future<EncryptedMediaUpload> encryptAndUpload({
    required Uint8List bytes,
    required String token,
    required String mediaType,
    int? duration,
    int? expiresIn,
    String? fileName,
    void Function(String keyBase64, String ivBase64)? onEncrypted,
  }) async {
    calls.add({
      'mediaType': mediaType,
      'token': token,
      'duration': duration,
      'expiresIn': expiresIn,
      'fileName': fileName,
      'bytesLen': bytes.length,
    });
    onEncrypted?.call('K', 'IV');
    capturedKey = 'K';
    if (throwOnUpload != null) throw throwOnUpload!;
    return EncryptedMediaUpload(
      mediaUrl: 'http://test/media/msgs/x.bin',
      keyBase64: 'K',
      ivBase64: 'IV',
      mediaDuration: duration,
    );
  }
}

MessagingProvider _newProvider() {
  final provider = MessagingProvider();
  final conversations = ConversationsProvider();
  conversations.onConversationsList([
    {
      'id': 10,
      'userOne': {'id': 1, 'username': 'alice', 'tag': '0001'},
      'userTwo': {'id': 2, 'username': 'bob', 'tag': '0002'},
      'createdAt': '2026-01-01T00:00:00.000Z',
      'unreadCount': 0,
      'lastMessage': null,
    },
  ]);
  provider.setConversationsProvider(conversations);
  provider.setCurrentUserId(1);
  provider.setToken('tok'); // also sets _tokenForReconnect (voice path)
  provider.onConnect(false);
  conversations.openConversation(10);
  return provider;
}

void main() {
  group('MessagingProvider media send — image', () {
    test('routes through the upload service and patches the message', () async {
      final provider = _newProvider();
      final fake = _FakeMediaUpload();
      provider.setMediaUploadServiceForTest(fake);

      await provider.sendImageMessage(
        'tok',
        XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'a.jpg'),
        2,
      );

      final msg = provider.messages.last;
      // mediaUrl/key/iv are patched BEFORE _encryptAndSend, so they survive even
      // though deliveryStatus ends 'failed' here (no EncryptionProvider in test).
      expect(msg.mediaUrl, 'http://test/media/msgs/x.bin');
      expect(msg.mediaKey, 'K');
      expect(msg.mediaIv, 'IV');
      expect(fake.calls.single['mediaType'], 'image');
      expect(fake.capturedKey, 'K');
    });

    test('marks the message failed (no mediaUrl) when upload throws', () async {
      final provider = _newProvider();
      provider.setMediaUploadServiceForTest(
        _FakeMediaUpload(throwOnUpload: Exception('boom')),
      );

      await provider.sendImageMessage(
        'tok',
        XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'a.jpg'),
        2,
      );

      final msg = provider.messages.last;
      expect(msg.deliveryStatus, MessageDeliveryStatus.failed);
      expect(msg.mediaUrl, isNull); // never patched — upload threw before the patch
    });
  });
}
