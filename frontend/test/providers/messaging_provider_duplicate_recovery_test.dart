
import 'package:fireplace/models/message_model.dart';
import 'package:fireplace/providers/conversations_provider.dart';
import 'package:fireplace/providers/encryption_provider.dart';
import 'package:fireplace/providers/messaging_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression for the "message breaks mid-conversation" bug (2026-07-11, the
/// `kind:duplicate` `[Decryption failed]` entries, e.g. bob210 / msg 15284).
///
/// Mechanism: on a history re-decrypt the client re-runs `decrypt` on a message
/// whose ratchet key was already consumed → `DuplicateMessageException`. The OLD
/// policy PERSISTED `[Decryption failed]`, poisoning the durable decrypted-content
/// cache so the message could never come back — a permanent break. The fix marks
/// `duplicate` failed IN MEMORY only (no durable write), so a later launch can
/// still restore the plaintext if its row survives.
///
/// This drives the REAL MessagingProvider decrypt path (not the policy in
/// isolation) and asserts the durable-write behavior, with a `badMac` contrast so
/// the test fails if the duplicate/badMac distinction ever regresses.
class _ThrowingEncryption extends EncryptionProvider {
  _ThrowingEncryption(this._error);
  final Object _error;

  /// Every (messageId, payload) written to the DURABLE cache.
  final List<MapEntry<int, Map<String, dynamic>>> durableWrites = [];

  @override
  bool get isE2EReady => true;
  @override
  bool get hadIdentityReset => false;

  @override
  Future<void> ensureSession(int recipientId) async {}

  @override
  Future<String> decrypt(int senderId, String ciphertext) async =>
      throw _error;

  @override
  MessageModel? getCachedDecryption(int messageId) => null;
  @override
  void cacheDecryption(int messageId, MessageModel msg) {}

  @override
  Future<Map<String, dynamic>?> getDecryptedContent(int messageId) async =>
      null; // plaintext absent locally — forces the live-decrypt branch

  @override
  Future<void> saveDecryptedContent(
      int messageId, Map<String, dynamic> data) async {
    durableWrites.add(MapEntry(messageId, data));
  }
}

Map<String, dynamic> _convJson() => {
      'id': 10,
      'userOne': {'id': 1, 'username': 'alice', 'tag': '0001'},
      'userTwo': {'id': 2, 'username': 'bob', 'tag': '0002'},
      'createdAt': '2026-01-01T00:00:00.000Z',
      'unreadCount': 0,
      'lastMessage': null,
    };

Map<String, dynamic> _encryptedInboundJson(int id) => {
      'id': id,
      'content': '[encrypted]',
      'encryptedContent': '2:ciphertext-$id',
      'senderId': 2,
      'senderUsername': 'bob',
      'conversationId': 10,
      'deliveryStatus': 'DELIVERED',
      'messageType': 'TEXT',
      'createdAt': '2026-01-01T00:00:00.000Z',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const failedLabel = '[Decryption failed]';

  Future<_ThrowingEncryption> runHistoryDecrypt(Object error) async {
    final encryption = _ThrowingEncryption(error);
    final conversations = ConversationsProvider();
    conversations.setCurrentUserId(1);
    conversations.onConversationsList([_convJson()]);
    conversations.openConversation(10);

    final provider = MessagingProvider();
    provider.setConversationsProvider(conversations);
    provider.setEncryptionProvider(encryption);
    provider.setCurrentUserId(1);
    provider.setToken('tok');
    provider.setIncomingMessageSoundEnabledForTest(false);
    provider.onConnect(false);
    provider.setEmitCallback((_, _) {});
    provider.setActiveConversationIdForTest(10);

    provider.onMessageHistory({
      'conversationId': 10,
      'messages': [_encryptedInboundJson(5001)],
    });

    // History decrypt runs async (whenComplete). Poll until the row settles to
    // the terminal failure label.
    for (var i = 0; i < 200; i++) {
      final m = provider.messages.where((m) => m.id == 5001).firstOrNull;
      if (m != null && m.content == failedLabel) break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return encryption;
  }

  group('mid-conversation duplicate does not permanently break the message', () {
    test(
      'DuplicateMessage on re-decrypt marks failed IN MEMORY but does NOT '
      'persist [Decryption failed] (durable cache stays un-poisoned → recoverable)',
      () async {
        final enc =
            await runHistoryDecrypt(Exception('DuplicateMessageException 42'));

        // The message shows failed in memory this session (no [encrypted] loop)...
        // (we don't assert the in-memory label strictly — the load-bearing claim
        // is the durable cache is not poisoned).
        // ...but nothing was written to the durable cache as [Decryption failed].
        final poisoned = enc.durableWrites
            .where((w) => w.value['content'] == failedLabel)
            .toList();
        expect(poisoned, isEmpty,
            reason: 'duplicate must NOT persist [Decryption failed] — that is '
                'what permanently broke bob210\'s message');
      },
    );

    test(
      'CONTRAST: badMac still persists [Decryption failed] (proves the test '
      'distinguishes duplicate from badMac; guards against a policy regression)',
      () async {
        final enc = await runHistoryDecrypt(Exception('Bad Mac!'));

        final poisoned = enc.durableWrites
            .where((w) => w.value['content'] == failedLabel)
            .toList();
        expect(poisoned, isNotEmpty,
            reason: 'badMac is terminal + persisted by policy; if this is empty '
                'the decrypt path never ran or the policy changed');
      },
    );
  });
}
