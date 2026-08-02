import 'package:fireplace/models/message_model.dart';
import 'package:fireplace/providers/conversations_provider.dart';
import 'package:fireplace/providers/encryption_provider.dart';
import 'package:fireplace/providers/messaging_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// The decrypt ledger's GATE, driven through the real MessagingProvider path.
///
/// The service-level suite proves the ledger stores the right ids. This proves
/// the thing that actually protects data: that a ledger hit stops the decrypt
/// before it reaches the ratchet.
///
/// Why it matters — a record whose plaintext was persisted once and is now gone
/// has a spent ratchet key. Re-decrypting it cannot succeed; it throws
/// DuplicateMessage and burns the row into a permanent "[Decryption failed]",
/// which reads to the user as corruption. The gate turns that into an honest
/// "no longer stored on this device", which a resend fixes.
///
/// The gate is also the only place in this feature that can destroy something
/// (`markRetired` is permanent), so the cases where it must NOT act are worth
/// more than the case where it must.
class _LedgerEncryption extends EncryptionProvider {
  _LedgerEncryption({
    required this.ledger,
    required this.exists,
    Map<int, Map<String, dynamic>>? persisted,
  }) : persisted = persisted ?? {};

  /// Ids the ledger claims were decrypted before.
  final Set<int> ledger;

  /// Tri-state answer for `recordExists`: true present, false definitely
  /// absent, null undetermined.
  final bool? exists;

  final Map<int, Map<String, dynamic>> persisted;

  int decryptCalls = 0;
  final List<int> retired = [];

  @override
  bool get isE2EReady => true;
  @override
  bool get hadIdentityReset => false;

  @override
  Future<void> ensureSession(int recipientId) async {}

  @override
  bool wasDecryptedBefore(int messageId) => ledger.contains(messageId);

  @override
  Future<bool?> recordExists(int messageId) async => exists;

  @override
  Future<void> retireLostMessage(int messageId) async {
    retired.add(messageId);
  }

  @override
  bool isRetired(int messageId) => retired.contains(messageId);

  @override
  Future<void> flushDecryptedLedger() async {}

  @override
  Future<String> decrypt(
    int senderId,
    String ciphertext, {
    int? messageId,
  }) async {
    decryptCalls++;
    // A real spent-key retry throws exactly this. If the gate lets anything
    // through, the row is destroyed and the test says so.
    throw Exception('DuplicateMessageException — ratchet key already consumed');
  }

  @override
  MessageModel? getCachedDecryption(int messageId) => null;
  @override
  void cacheDecryption(int messageId, MessageModel msg) {}

  @override
  Future<Map<String, dynamic>?> getDecryptedContent(int messageId) async =>
      persisted[messageId];

  @override
  Future<void> saveDecryptedContent(
    int messageId,
    Map<String, dynamic> data, {
    int? conversationId,
    DateTime? createdAt,
    DateTime? expiresAt,
    int? disappearAfterSeconds,
  }) async {
    persisted[messageId] = Map<String, dynamic>.from(data);
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

  const lostId = 18597;

  Future<({MessagingProvider provider, _LedgerEncryption encryption})> run({
    required Set<int> ledger,
    required bool? exists,
    Map<int, Map<String, dynamic>>? persisted,
  }) async {
    final encryption = _LedgerEncryption(
      ledger: ledger,
      exists: exists,
      persisted: persisted,
    );
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
      'messages': [_encryptedInboundJson(lostId)],
    });

    // The history pass runs async. Settle on the decrypt attempt rather than on
    // the label, because two of these cases deliberately leave the row alone.
    for (var i = 0; i < 200; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (encryption.decryptCalls > 0 || encryption.retired.isNotEmpty) break;
    }
    return (provider: provider, encryption: encryption);
  }

  MessageModel? rowOf(MessagingProvider p) =>
      p.messages.where((m) => m.id == lostId).firstOrNull;

  test('a definitely-lost record is retired instead of re-decrypted', () async {
    final r = await run(ledger: {lostId}, exists: false);

    expect(
      r.encryption.decryptCalls,
      0,
      reason: 'the ratchet must never be touched for a spent key — that is '
          'what turns a lost row into a permanent [Decryption failed]',
    );
    expect(r.encryption.retired, contains(lostId));
    expect(rowOf(r.provider)?.content, kRetiredMessageLabel);
  });

  test('an undetermined probe retires NOTHING and leaves the row alone', () async {
    // `recordExists` returns null for an unbound user or any caught exception.
    // Treating that as loss would let a transient storage error permanently
    // retire a message whose bytes are still on disk. The row must stay
    // untouched so a later pass can ask again.
    final r = await run(ledger: {lostId}, exists: null);

    expect(r.encryption.decryptCalls, 0);
    expect(r.encryption.retired, isEmpty);
    expect(rowOf(r.provider)?.content, isNot(kRetiredMessageLabel));
  });

  test('a record that is merely unhydrated is served, not retired', () async {
    final r = await run(
      ledger: {lostId},
      exists: true,
      persisted: {
        lostId: {'content': 'still here'},
      },
    );

    expect(r.encryption.decryptCalls, 0);
    expect(r.encryption.retired, isEmpty);
    expect(rowOf(r.provider)?.content, 'still here');
  });

  test('an id absent from the ledger still reaches the decrypt path', () async {
    // The gate must not become a blanket veto: a message genuinely never
    // decrypted has to be attempted, or nothing would ever decrypt at all.
    final r = await run(ledger: <int>{}, exists: false);

    expect(r.encryption.decryptCalls, greaterThan(0));
    expect(r.encryption.retired, isEmpty);
  });
}
