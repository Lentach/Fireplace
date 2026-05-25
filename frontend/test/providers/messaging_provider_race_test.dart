import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:fireplace/providers/conversations_provider.dart';
import 'package:fireplace/providers/encryption_provider.dart';
import 'package:fireplace/models/message_model.dart';
import 'package:fireplace/providers/messaging_provider.dart';
import 'package:fireplace/utils/e2e_envelope.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeEncryptionProvider extends EncryptionProvider {
  bool failEnsureSession = true;
  int ensureSessionCalls = 0;

  @override
  bool get isE2EReady => true;

  @override
  Future<void> deleteSessionWithPeer(int peerUserId) async {}

  @override
  Future<void> ensureSession(int recipientId) async {
    ensureSessionCalls++;
    if (failEnsureSession) {
      failEnsureSession = false;
      throw TimeoutException('timed out');
    }
  }

  @override
  Future<String> encrypt(int recipientId, String plaintext) async {
    return 'ciphertext';
  }

  @override
  Future<String> decrypt(int senderId, String ciphertext) async {
    return jsonEncode(E2eEnvelope.build('decrypted'));
  }

  @override
  Future<Map<String, dynamic>?> getDecryptedContent(int messageId) async =>
      null;
}

/// Tracks decrypt calls — used to assert history does not re-decrypt plaintext rows.
class _DecryptCountingEncryption extends _FakeEncryptionProvider {
  int decryptCalls = 0;

  @override
  Future<String> decrypt(int senderId, String ciphertext) async {
    decryptCalls++;
    return jsonEncode(E2eEnvelope.build('plain-$decryptCalls'));
  }
}

/// Always fails decrypt (simulates cross-device ratchet mismatch).
class _AlwaysFailDecryptEncryption extends _FakeEncryptionProvider {
  @override
  Future<String> decrypt(int senderId, String ciphertext) async {
    throw Exception('Bad Mac');
  }
}

/// Simulates stale localStorage row: mediaUrl/type without AES keys (pre-re-enter bug).
class _PersistedGifWithoutKeysEncryption extends _FakeEncryptionProvider {
  int decryptCalls = 0;

  @override
  Future<Map<String, dynamic>?> getDecryptedContent(int messageId) async {
    return {
      'content': '',
      'messageType': 'GIF',
      'mediaUrl': 'http://localhost:3000/media/msgs/test.bin',
    };
  }

  @override
  Future<String> decrypt(int senderId, String ciphertext) async {
    decryptCalls++;
    return jsonEncode(
      E2eEnvelope.build(
        '',
        messageType: 'GIF',
        mediaUrl: 'http://localhost:3000/media/msgs/test.bin',
        mediaKey: 'keyBase64',
        mediaIv: 'ivBase64',
      ),
    );
  }
}

/// Second decrypt throws DuplicateMessageException (live decrypt already advanced ratchet).
class _DuplicateDecryptEncryption extends _FakeEncryptionProvider {
  int decryptCalls = 0;

  @override
  Future<String> decrypt(int senderId, String ciphertext) async {
    decryptCalls++;
    if (decryptCalls > 1) {
      throw Exception(
        'DuplicateMessageException - Received message with old counter',
      );
    }
    return jsonEncode(E2eEnvelope.build('', messageType: 'PING'));
  }
}

/// Fails the first live decrypt per history pass, then succeeds after session reset.
/// E2E becomes ready only after [markReady] (simulates iOS PWA init lag).
class _DelayedE2EReadyEncryption extends _FakeEncryptionProvider {
  bool _ready = false;

  @override
  bool get isE2EReady => _ready;

  void markReady() => _ready = true;
}

class _HistoryDecryptRetryEncryption extends _FakeEncryptionProvider {
  int decryptAttempts = 0;
  int deleteSessionCalls = 0;

  @override
  Future<void> deleteSessionWithPeer(int peerUserId) async {
    deleteSessionCalls++;
  }

  @override
  Future<String> decrypt(int senderId, String ciphertext) async {
    decryptAttempts++;
    if (decryptAttempts <= 1) {
      throw Exception('simulate ratchet mismatch');
    }
    return jsonEncode(E2eEnvelope.build('recovered-after-retry'));
  }
}

Map<String, dynamic> _convJson() => {
      'id': 10,
      'userOne': {
        'id': 1,
        'username': 'alice',
        'tag': '0001',
      },
      'userTwo': {
        'id': 2,
        'username': 'bob',
        'tag': '0002',
      },
      'createdAt': '2026-01-01T00:00:00.000Z',
      'disappearingTimer': 60,
      'unreadCount': 0,
      'lastMessage': null,
    };

void main() {
  group('MessagingProvider — race regressions', () {
    late MessagingProvider provider;
    late ConversationsProvider conversations;
    late _FakeEncryptionProvider encryption;
    late List<Map<String, dynamic>> emitted;

    setUp(() {
      provider = MessagingProvider();
      conversations = ConversationsProvider();
      encryption = _FakeEncryptionProvider();
      emitted = <Map<String, dynamic>>[];

      conversations.setCurrentUserId(1);
      conversations.onConversationsList([_convJson()]);
      conversations.openConversation(10);

      provider.setConversationsProvider(conversations);
      provider.setEncryptionProvider(encryption);
      provider.setCurrentUserId(1);
      provider.setIncomingMessageSoundEnabledForTest(false);
      provider.setToken('tok');
      provider.onConnect(false);
      provider.setEmitCallback((event, data) {
        emitted.add({'event': event, 'data': data});
      });
    });

    test('never emits plaintext sendMessage when session bootstrap fails', () async {
      provider.sendMessage('hello');
      await Future<void>.delayed(Duration.zero);

      final sendEvents = emitted.where((e) => e['event'] == 'sendMessage').toList();
      expect(sendEvents, isEmpty);
      expect(provider.messages.any((m) => m.content == 'hello'), isTrue);
      expect(
        provider.messages.any((m) => m.deliveryStatus.name == 'failed'),
        isTrue,
      );
    });

    test('reconnect cancels delayed retry timer (no second ensureSession)', () {
      fakeAsync((async) {
        provider.sendMessage('hello');
        async.flushMicrotasks();
        expect(encryption.ensureSessionCalls, 1);

        provider.onConnect(true);
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();

        expect(encryption.ensureSessionCalls, 1);
      });
    });

    Map<String, dynamic> incomingJson({
      required int id,
      required String createdAt,
      bool includeTtl = true,
      String messageType = 'TEXT',
    }) =>
        {
          'id': id,
          'content': '[encrypted]',
          'encryptedContent': 'cipher-$id',
          'senderId': 2,
          'senderUsername': 'bob',
          'conversationId': 10,
          'deliveryStatus': 'DELIVERED',
          'messageType': messageType,
          if (includeTtl) 'disappearAfterSeconds': 60,
          'createdAt': createdAt,
        };

    test(
      'recipient burst: stale messageHistory null TTL keeps disappearAfterSeconds from newMessage',
      () async {
        provider.setActiveConversationIdForTest(10);

        for (var id = 1; id <= 3; id++) {
          provider.onNewMessage(
            incomingJson(
              id: id,
              createdAt:
                  '2026-01-01T00:00:${id.toString().padLeft(2, '0')}.000Z',
            ),
          );
        }

        provider.onMessageHistory({
          'conversationId': 10,
          'messages': List.generate(
            3,
            (i) => incomingJson(
              id: i + 1,
              createdAt:
                  '2026-01-01T00:00:${(i + 1).toString().padLeft(2, '0')}.000Z',
              includeTtl: false,
            ),
          ),
        });

        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(provider.messages.length, 3);
        expect(
          provider.messages.every((m) => m.disappearAfterSeconds == 60),
          isTrue,
          reason: 'merge + decrypt must not let null history wipe TTL',
        );
      },
    );

    test(
      'defers live decrypt until the conversation is open (ordered history path)',
      () async {
        final counting = _DecryptCountingEncryption();
        provider.setEncryptionProvider(counting);
        conversations.closeConversation(notify: false);
        provider.clearMessages();

        provider.onNewMessage(
          incomingJson(
            id: 91,
            createdAt: '2026-01-01T00:00:91.000Z',
            includeTtl: false,
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(counting.decryptCalls, 0);

        provider.setActiveConversationIdForTest(10);
        provider.onMessageHistory({
          'conversationId': 10,
          'messages': [
            incomingJson(
              id: 91,
              createdAt: '2026-01-01T00:00:91.000Z',
              includeTtl: false,
            ),
          ],
        });
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(counting.decryptCalls, 1);
        expect(provider.messages.single.content, isNot('[encrypted]'));
      },
    );

    test(
      'history decrypt keeps [encrypted] until retry fails then marks failed',
      () async {
        final failEncryption = _AlwaysFailDecryptEncryption();
        provider.setEncryptionProvider(failEncryption);
        provider.setActiveConversationIdForTest(10);

        provider.onMessageHistory({
          'conversationId': 10,
          'messages': [
            incomingJson(
              id: 92,
              createdAt: DateTime.now().toUtc().toIso8601String(),
              includeTtl: false,
            ),
          ],
        });
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(provider.messages.single.content, '[Decryption failed]');
      },
    );

    test(
      'history decrypt ignores memory cache that still has [encrypted] placeholder',
      () async {
        final createdAt = DateTime.now().toUtc().toIso8601String();
        provider.setActiveConversationIdForTest(10);
        encryption.cacheDecryption(
          1,
          MessageModel.fromJson(
            incomingJson(
              id: 1,
              createdAt: createdAt,
              includeTtl: false,
            ),
          ),
        );

        provider.onMessageHistory({
          'conversationId': 10,
          'messages': [
            incomingJson(
              id: 1,
              createdAt: createdAt,
              includeTtl: false,
            ),
          ],
        });
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(provider.messages.single.content, 'decrypted');
        expect(
          provider.messages.single.displayAsEncryptedPlaceholder,
          isFalse,
        );
      },
    );

    test(
      'history decrypt from stale memory cache keeps disappearAfterSeconds on row',
      () {
        fakeAsync((async) {
          provider.setActiveConversationIdForTest(10);

          for (var id = 1; id <= 3; id++) {
            final createdAt =
                '2026-01-01T00:00:${id.toString().padLeft(2, '0')}.000Z';
            provider.onNewMessage(incomingJson(id: id, createdAt: createdAt));
            encryption.cacheDecryption(
              id,
              MessageModel.fromJson(
                incomingJson(
                  id: id,
                  createdAt: createdAt,
                  includeTtl: false,
                ),
              ).copyWith(content: 'cached-plain'),
            );
          }

          provider.onMessageHistory({
            'conversationId': 10,
            'messages': List.generate(
              3,
              (i) => incomingJson(
                id: i + 1,
                createdAt:
                    '2026-01-01T00:00:${(i + 1).toString().padLeft(2, '0')}.000Z',
                includeTtl: false,
              ),
            ),
          });

          async.flushMicrotasks();

          expect(
            provider.messages.every((m) => m.disappearAfterSeconds == 60),
            isTrue,
          );
        });
      },
    );

    test(
      'messageHistory keeps decrypted PING when duplicate decrypt would fire',
      () async {
        final dupEncryption = _DuplicateDecryptEncryption();
        provider.setEncryptionProvider(dupEncryption);
        provider.setActiveConversationIdForTest(10);

        provider.onNewMessage(incomingJson(
          id: 8,
          createdAt: '2026-01-01T00:00:08.000Z',
          messageType: 'PING',
          includeTtl: false,
        ));
        for (var i = 0; i < 30; i++) {
          await Future<void>.delayed(Duration.zero);
          if (provider.messages.any((m) => m.id == 8)) break;
        }
        expect(dupEncryption.decryptCalls, 1);
        expect(
          provider.messages.singleWhere((m) => m.id == 8).messageType,
          MessageType.ping,
        );

        provider.onMessageHistory({
          'conversationId': 10,
          'messages': [
            incomingJson(
              id: 8,
              createdAt: '2026-01-01T00:00:08.000Z',
              messageType: 'PING',
              includeTtl: false,
            ),
          ],
        });
        for (var i = 0; i < 30; i++) {
          await Future<void>.delayed(Duration.zero);
        }

        expect(dupEncryption.decryptCalls, 1);
        final row = provider.messages.singleWhere((m) => m.id == 8);
        expect(row.messageType, MessageType.ping);
        expect(row.content, isNot('[Decryption failed]'));
      },
    );

    test(
      'messageHistory does not re-decrypt rows already plaintext in _messages',
      () async {
        final counting = _DecryptCountingEncryption();
        provider.setEncryptionProvider(counting);
        provider.setActiveConversationIdForTest(10);
        provider.getMessages(10);

        provider.onNewMessage(incomingJson(
          id: 7,
          createdAt: '2026-01-01T00:00:07.000Z',
          includeTtl: false,
        ));
        for (var i = 0; i < 30; i++) {
          await Future<void>.delayed(Duration.zero);
          if (provider.messages.any((m) => m.id == 7 && m.content == 'plain-1')) {
            break;
          }
        }
        expect(counting.decryptCalls, 1);

        provider.onMessageHistory({
          'conversationId': 10,
          'messages': [
            incomingJson(
              id: 7,
              createdAt: '2026-01-01T00:00:07.000Z',
              includeTtl: false,
            ),
          ],
        });
        for (var i = 0; i < 30; i++) {
          await Future<void>.delayed(Duration.zero);
        }

        expect(counting.decryptCalls, 1);
        final row = provider.messages.where((m) => m.id == 7).toList();
        expect(row.length, 1);
        expect(row.first.content, 'plain-1');
      },
    );

    test(
      'retryDecryptActiveConversation decrypts after E2E becomes ready',
      () async {
        final delayed = _DelayedE2EReadyEncryption();
        provider.setEncryptionProvider(delayed);
        provider.setActiveConversationIdForTest(10);

        provider.onMessageHistory({
          'conversationId': 10,
          'messages': [
            incomingJson(
              id: 1,
              createdAt: DateTime.now().toUtc().toIso8601String(),
              includeTtl: false,
            ),
          ],
        });
        await Future<void>.delayed(Duration.zero);
        expect(
          provider.messages.single.displayAsEncryptedPlaceholder,
          isTrue,
        );

        delayed.markReady();
        await provider.retryDecryptActiveConversation();
        await Future<void>.delayed(Duration.zero);

        expect(provider.messages.single.content, isNot('[encrypted]'));
        expect(
          provider.messages.single.displayAsEncryptedPlaceholder,
          isFalse,
        );
      },
    );

    test(
      'history decrypt failure resets session and retries instead of permanent [Decryption failed]',
      () async {
        final retryEncryption = _HistoryDecryptRetryEncryption();
        provider.setEncryptionProvider(retryEncryption);
        provider.setActiveConversationIdForTest(10);

        provider.onMessageHistory({
          'conversationId': 10,
          'messages': [
            incomingJson(
              id: 1,
              createdAt: DateTime.now().toUtc().toIso8601String(),
              includeTtl: false,
            ),
          ],
        });
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(retryEncryption.deleteSessionCalls, 1);
        expect(
          emitted.any(
            (e) =>
                e['event'] == 'requestSessionRebuild' &&
                (e['data'] as Map)['recipientId'] == 2,
          ),
          isTrue,
        );
        expect(provider.messages.single.content, 'recovered-after-retry');
        expect(
          provider.messages.any((m) => m.content == '[Decryption failed]'),
          isFalse,
        );
      },
    );

    test('messageHistory after newMessage does not drop the live message', () {
      provider.setActiveConversationIdForTest(10);
      provider.getMessages(10);

      final serverPage = List.generate(
        3,
        (i) => {
          'id': i + 1,
          'content': 'history-$i',
          'senderId': 2,
          'senderUsername': 'bob',
          'conversationId': 10,
          'deliveryStatus': 'DELIVERED',
          'messageType': 'TEXT',
          'createdAt': '2026-01-01T00:00:00.000Z',
        },
      );

      provider.onNewMessage({
        'id': 99,
        'content': 'live',
        'senderId': 2,
        'senderUsername': 'bob',
        'conversationId': 10,
        'deliveryStatus': 'DELIVERED',
        'messageType': 'TEXT',
        'createdAt': '2026-01-02T00:00:00.000Z',
      });

      expect(provider.messages.any((m) => m.id == 99), isTrue);

      provider.onMessageHistory({
        'conversationId': 10,
        'messages': serverPage,
      });

      expect(provider.messages.any((m) => m.id == 99), isTrue);
      expect(provider.messages.length, 4);
    });

    test('messageDelivered updates cache when message not in _messages', () {
      final msg = {
        'id': 42,
        'content': 'cached',
        'senderId': 2,
        'senderUsername': 'bob',
        'conversationId': 10,
        'deliveryStatus': 'DELIVERED',
        'messageType': 'TEXT',
        'disappearAfterSeconds': 60,
        'createdAt': '2026-01-01T00:00:00.000Z',
      };
      provider.seedCacheForTest(
        10,
        [MessageModel.fromJson(msg)],
      );
      provider.setActiveConversationIdForTest(99);

      provider.onMessageDelivered({
        'messageId': 42,
        'conversationId': 10,
        'deliveryStatus': 'READ',
        'expiresAt': '2026-01-01T01:00:00.000Z',
      });

      final cached = provider.cacheMessageForTest(10, 42);
      expect(cached, isNotNull);
      expect(cached!.deliveryStatus, MessageDeliveryStatus.read);
      expect(cached.expiresAt, DateTime.parse('2026-01-01T01:00:00.000Z'));
    });

    test('deterministic interleaving: reconnect + messageHistory + retry keeps encrypted send path', () {
      fakeAsync((async) {
        provider.sendMessage('hello');
        async.flushMicrotasks();

        final failed = provider.messages.firstWhere(
          (m) => m.deliveryStatus.name == 'failed',
        );
        final failedTempId = failed.tempId!;

        provider.onConnect(true);
        provider.onMessageHistory({
          'conversationId': 10,
          'messages': [
            {
              'id': 7001,
              'content': 'hello',
              'senderId': 1,
              'senderUsername': 'alice',
              'conversationId': 10,
              'deliveryStatus': 'FAILED',
              'messageType': 'TEXT',
              'tempId': failedTempId,
              'createdAt': '2026-01-01T00:00:00.000Z',
            },
          ],
        });
        async.flushMicrotasks();

        provider.retryFailedMessage(failedTempId);
        async.flushMicrotasks();

        final sendEvents =
            emitted.where((e) => e['event'] == 'sendMessage').toList();
        expect(sendEvents.length, 1);
        final payload = sendEvents.first['data'] as Map<String, dynamic>;
        expect(payload['content'], '[encrypted]');
        expect(payload['encryptedContent'], 'ciphertext');
        expect(payload['content'], isNot('hello'));
      });
    });

    test(
      'encrypted sendMessage includes messageType and mediaUrl for IMAGE',
      () async {
        encryption.failEnsureSession = false;
        await provider.encryptAndSendForTest(
          recipientId: 2,
          content: '',
          tempId: 'temp_image_1',
          messageType: 'IMAGE',
          mediaUrl: 'http://localhost:3000/media/msgs/test-image.bin',
        );
        await Future<void>.delayed(Duration.zero);

        final sendEvents =
            emitted.where((e) => e['event'] == 'sendMessage').toList();
        expect(sendEvents.length, 1);
        final payload = sendEvents.first['data'] as Map<String, dynamic>;
        expect(payload['messageType'], 'IMAGE');
        expect(
          payload['mediaUrl'],
          'http://localhost:3000/media/msgs/test-image.bin',
        );
        expect(payload['encryptedContent'], isNotEmpty);
      },
    );

    test('encrypted sendMessage omits messageType for TEXT', () async {
      encryption.failEnsureSession = false;
      await provider.encryptAndSendForTest(
        recipientId: 2,
        content: 'hello',
        tempId: 'temp_text_1',
      );
      await Future<void>.delayed(Duration.zero);

      final payload = emitted
          .firstWhere((e) => e['event'] == 'sendMessage')['data']
          as Map<String, dynamic>;
      expect(payload.containsKey('messageType'), isFalse);
      expect(payload.containsKey('mediaUrl'), isFalse);
    });

    test(
      're-enter chat: GIF with mediaUrl but no keys still runs history decrypt',
      () async {
        final enc = _PersistedGifWithoutKeysEncryption();
        provider.setEncryptionProvider(enc);
        provider.setActiveConversationIdForTest(10);

        final row = {
          'id': 88,
          'content': '',
          'encryptedContent': 'cipher-gif',
          'senderId': 2,
          'senderUsername': 'bob',
          'conversationId': 10,
          'deliveryStatus': 'DELIVERED',
          'messageType': 'GIF',
          'mediaUrl': 'http://localhost:3000/media/msgs/test.bin',
          'createdAt': '2026-01-01T00:01:00.000Z',
        };

        provider.onMessageHistory({
          'conversationId': 10,
          'messages': [row],
        });
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(enc.decryptCalls, greaterThan(0));
        final m = provider.messages.single;
        expect(m.mediaKey, 'keyBase64');
        expect(m.mediaIv, 'ivBase64');
        expect(m.messageType, MessageType.gif);
      },
    );

    test(
      'messageHistory merge preserves [Decryption failed] over server [encrypted]',
      () async {
        final failEncryption = _AlwaysFailDecryptEncryption();
        provider.setEncryptionProvider(failEncryption);
        provider.setActiveConversationIdForTest(10);

        final row = incomingJson(
          id: 55,
          createdAt: DateTime.now().toUtc().toIso8601String(),
          includeTtl: false,
        );
        provider.seedCacheForTest(
          10,
          [
            MessageModel.fromJson(row)
                .copyWith(content: '[Decryption failed]'),
          ],
        );
        provider.loadCachedMessages(10);

        provider.onMessageHistory({
          'conversationId': 10,
          'messages': [row],
        });
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(const Duration(milliseconds: 900));

        expect(provider.messages.single.content, '[Decryption failed]');
        expect(
          provider.messages.single.displayAsEncryptedPlaceholder,
          isFalse,
        );
      },
    );

    test(
      'live decrypt fail debounces requestSessionRebuild until batched retry',
      () {
        fakeAsync((async) {
          final failEncryption = _AlwaysFailDecryptEncryption();
          provider.setEncryptionProvider(failEncryption);
          provider.setActiveConversationIdForTest(10);
          emitted.clear();

          provider.onNewMessage(
            incomingJson(
              id: 77,
              createdAt: '2026-01-01T00:00:77.000Z',
            ),
          );
          async.flushMicrotasks();

          expect(
            emitted.where((e) => e['event'] == 'requestSessionRebuild'),
            isEmpty,
          );
          expect(
            provider.messages.single.content,
            '[Decryption failed]',
          );

          async.elapse(const Duration(milliseconds: 800));
          async.flushMicrotasks();

          expect(
            emitted.where((e) => e['event'] == 'requestSessionRebuild'),
            isNotEmpty,
          );
        });
      },
    );
  });
}
