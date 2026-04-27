import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:fireplace/providers/conversations_provider.dart';
import 'package:fireplace/providers/encryption_provider.dart';
import 'package:fireplace/providers/messaging_provider.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeEncryptionProvider extends EncryptionProvider {
  bool failEnsureSession = true;
  int ensureSessionCalls = 0;

  @override
  bool get isE2EReady => true;

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
  });
}
