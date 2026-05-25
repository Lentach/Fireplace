import 'package:fireplace/models/message_model.dart';
import 'package:fireplace/providers/encryption_provider.dart';
import 'package:fireplace/providers/messaging_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MessagingProvider reply quote enrichment', () {
    test('incoming message enriches encrypted reply quote from decrypt cache', () {
      final provider = MessagingProvider()
        ..setIncomingMessageSoundEnabledForTest(false);
      final encryption = EncryptionProvider();
      provider.setEncryptionProvider(encryption);
      provider.setCurrentUserId(1);
      provider.onConnect(false);
      provider.setActiveConversationIdForTest(10);

      encryption.cacheDecryption(
        99,
        MessageModel(
          id: 99,
          content: 'secret reply body',
          senderId: 2,
          senderUsername: 'bob',
          conversationId: 10,
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      );

      provider.onNewMessage({
        'id': 100,
        'content': 'hello',
        'senderId': 2,
        'senderUsername': 'bob',
        'conversationId': 10,
        'deliveryStatus': 'DELIVERED',
        'messageType': 'TEXT',
        'createdAt': '2026-01-01T00:00:00.000Z',
        'replyTo': {
          'id': 99,
          'content': 'Encrypted message',
          'senderUsername': 'bob',
          'messageType': 'TEXT',
        },
      });

      final stored = provider.messages.single;
      expect(stored.replyTo?.content, 'secret reply body');
    });
  });
}
