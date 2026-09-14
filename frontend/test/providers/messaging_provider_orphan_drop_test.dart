import 'package:fireplace/providers/conversations_provider.dart';
import 'package:fireplace/providers/encryption_provider.dart';
import 'package:fireplace/providers/messaging_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// A session that was RUNNING but disconnected when a message was deleted
/// never sees the live `messageDeleted`, and `_mergeHistorySnapshot`
/// deliberately never prunes rows a server snapshot omits. The
/// server-authoritative reconcile destroys the stored plaintext for such a
/// row, but the row itself was left in memory still showing content the model
/// decrypted earlier. These pin the handoff that removes it.
class _Enc extends EncryptionProvider {
  @override
  bool get isE2EReady => true;
}

Map<String, dynamic> _conv() => {
  'id': 10,
  'userOne': {'id': 1, 'username': 'alice', 'tag': '0001'},
  'userTwo': {'id': 2, 'username': 'bob', 'tag': '0002'},
  'createdAt': '2026-01-01T00:00:00.000Z',
  'unreadCount': 0,
  'lastMessage': null,
};

Map<String, dynamic> _row(int id) => {
  'id': id,
  'content': 'hello there',
  'senderId': 2,
  'senderUsername': 'bob',
  'conversationId': 10,
  'deliveryStatus': 'DELIVERED',
  'messageType': 'TEXT',
  'createdAt': '2026-01-01T00:00:00.000Z',
};

void main() {
  late MessagingProvider provider;
  late ConversationsProvider conversations;

  setUp(() {
    provider = MessagingProvider();
    conversations = ConversationsProvider()
      ..setCurrentUserId(1)
      ..onConversationsList([_conv()])
      ..openConversation(10);
    provider
      ..setConversationsProvider(conversations)
      ..setEncryptionProvider(_Enc())
      ..setCurrentUserId(1)
      ..setToken('tok')
      ..setIncomingMessageSoundEnabledForTest(false)
      ..onConnect(false)
      ..setActiveConversationIdForTest(10);
  });

  test('an orphaned row leaves the list while the others stay', () {
    provider
      ..onNewMessage(_row(500))
      ..onNewMessage(_row(501));
    expect(provider.messages.map((m) => m.id), containsAll([500, 501]));

    provider.onStoredPlaintextOrphaned({500});

    expect(
      provider.messages.map((m) => m.id),
      isNot(contains(500)),
      reason: 'the server says it no longer serves this row',
    );
    expect(provider.messages.map((m) => m.id), contains(501));
  });

  test('a history response in flight cannot resurrect an orphaned row', () async {
    provider
      ..onNewMessage(_row(500))
      ..onStoredPlaintextOrphaned({500});

    // The reply was already on the wire when the reconcile landed. Without the
    // same guard the live delete path sets, this would re-add a row whose only
    // plaintext copy has just been destroyed.
    await provider.onMessageHistory({
      'conversationId': 10,
      'messages': [_row(500)],
    });

    expect(provider.messages.map((m) => m.id), isNot(contains(500)));
  });

  test('an empty orphan set changes nothing', () {
    provider
      ..onNewMessage(_row(500))
      ..onStoredPlaintextOrphaned(<int>{});

    expect(provider.messages.map((m) => m.id), contains(500));
  });
}
