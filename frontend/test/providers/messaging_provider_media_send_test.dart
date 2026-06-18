import 'dart:typed_data';

import 'package:fireplace/models/message_model.dart';
import 'package:fireplace/providers/conversations_provider.dart';
import 'package:fireplace/providers/encryption_provider.dart';
import 'package:fireplace/providers/messaging_provider.dart';
import 'package:fireplace/services/api_service.dart';
import 'package:fireplace/services/encrypted_media_upload_service.dart';
import 'package:fireplace/utils/e2e_diag_log.dart';
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

/// E2E-ready fake so _encryptAndSend reaches the socket emit (send path only).
class _SendReadyEncryption extends EncryptionProvider {
  @override
  bool get isE2EReady => true;

  @override
  bool get hadIdentityReset => false;

  @override
  Future<void> ensureSession(int recipientId) async {}

  @override
  Future<String> encrypt(int recipientId, String plaintext) async => '1:abc';

  @override
  Future<Map<String, dynamic>?> getDecryptedContent(int messageId) async =>
      null;
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

  group('MessagingProvider media send — voice', () {
    test('routes through the upload service with duration', () async {
      final provider = _newProvider();
      final fake = _FakeMediaUpload();
      provider.setMediaUploadServiceForTest(fake);

      await provider.sendVoiceMessage(
        recipientId: 2,
        duration: 5,
        conversationId: 10,
        localAudioBytes: Uint8List.fromList([1, 2, 3]),
      );

      final msg = provider.messages.last;
      expect(msg.mediaUrl, 'http://test/media/msgs/x.bin');
      expect(msg.mediaDuration, 5); // serverDuration = upload.mediaDuration ?? duration
      expect(msg.mediaKey, 'K');
      expect(fake.calls.single['mediaType'], 'voice');
      expect(fake.calls.single['duration'], 5);
    });

    test('marks the message failed when upload throws', () async {
      final provider = _newProvider();
      provider.setMediaUploadServiceForTest(
        _FakeMediaUpload(throwOnUpload: Exception('boom')),
      );

      await provider.sendVoiceMessage(
        recipientId: 2,
        duration: 5,
        conversationId: 10,
        localAudioBytes: Uint8List.fromList([1, 2, 3]),
      );

      expect(provider.messages.last.deliveryStatus, MessageDeliveryStatus.failed);
    });
  });

  group('MessagingProvider media send — file', () {
    test('routes through the upload service with fileName and no expiresIn', () async {
      final provider = _newProvider();
      final fake = _FakeMediaUpload();
      provider.setMediaUploadServiceForTest(fake);

      await provider.sendFileMessage(
        'tok',
        Uint8List.fromList([1, 2, 3]),
        'doc.pdf',
        'application/pdf',
        2,
      );

      final msg = provider.messages.last;
      expect(msg.mediaUrl, 'http://test/media/msgs/x.bin');
      expect(msg.content, 'doc.pdf');
      expect(fake.calls.single['mediaType'], 'file');
      expect(fake.calls.single['fileName'], 'doc.pdf');
      expect(fake.calls.single['expiresIn'], isNull);
    });

    test('marks the message failed (no mediaUrl) when upload throws', () async {
      final provider = _newProvider();
      provider.setMediaUploadServiceForTest(
        _FakeMediaUpload(throwOnUpload: Exception('boom')),
      );

      await provider.sendFileMessage(
        'tok',
        Uint8List.fromList([1, 2, 3]),
        'doc.pdf',
        'application/pdf',
        2,
      );

      final msg = provider.messages.last;
      expect(msg.deliveryStatus, MessageDeliveryStatus.failed);
      expect(msg.mediaUrl, isNull);
    });
  });

  group('sendImageMessage ordering contract (Clipboard Phase 2)', () {
    test('completes only after the IMAGE emit and returns true', () async {
      final provider = _newProvider();
      provider.setMediaUploadServiceForTest(_FakeMediaUpload());
      provider.setEncryptionProvider(_SendReadyEncryption());
      final emitted = <String>[];
      provider.setEmitCallback((event, data) {
        if (event == 'sendMessage') {
          emitted.add((data as Map)['messageType'] as String? ?? 'TEXT');
        }
      });

      final ok = await provider.sendImageMessage(
        'tok',
        XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'a.jpg'),
        2,
      );

      expect(ok, isTrue);
      // THE contract: when the Future completes, the emit already happened.
      expect(emitted, ['IMAGE']);

      provider.sendMessage('caption');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(emitted, ['IMAGE', 'TEXT']); // caption strictly after image
    });

    test('returns false when upload throws', () async {
      final provider = _newProvider();
      provider.setMediaUploadServiceForTest(
        _FakeMediaUpload(throwOnUpload: Exception('boom')),
      );
      provider.setEncryptionProvider(_SendReadyEncryption());

      final ok = await provider.sendImageMessage(
        'tok',
        XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'a.jpg'),
        2,
      );

      expect(ok, isFalse);
    });

    test('returns false when E2E is not ready', () async {
      final provider = _newProvider(); // no EncryptionProvider set
      provider.setMediaUploadServiceForTest(_FakeMediaUpload());

      final ok = await provider.sendImageMessage(
        'tok',
        XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'a.jpg'),
        2,
      );

      expect(ok, isFalse);
    });
  });

  group('MEDIA_ORPHAN_LIKELY diagnostic (I1 observability)', () {
    test('logged when a media send fails AFTER a successful upload', () async {
      // Upload succeeds (fake returns a mediaUrl) but no EncryptionProvider is
      // set, so _encryptAndSend fails on the !e2eReady path → the blob is
      // uploaded yet never referenced by an emitted message = orphan-likely.
      final provider = _newProvider();
      provider.setMediaUploadServiceForTest(_FakeMediaUpload());
      E2eDiagLog.clear();

      final ok = await provider.sendImageMessage(
        'tok',
        XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'a.jpg'),
        2,
      );

      expect(ok, isFalse);
      final orphanEvents = E2eDiagLog.entries
          .where((e) => e.contains('MEDIA_ORPHAN_LIKELY'))
          .toList();
      expect(orphanEvents, hasLength(1));
      expect(orphanEvents.single, contains('tempId'));
    });

    test('NOT logged for a text send failure (nothing was uploaded)', () async {
      final provider = _newProvider(); // no EncryptionProvider → E2E not ready
      E2eDiagLog.clear();

      provider.sendMessage('hello');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        E2eDiagLog.entries.where((e) => e.contains('MEDIA_ORPHAN_LIKELY')),
        isEmpty,
      );
    });
  });
}
