import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:fireplace/models/message_model.dart';
import 'package:fireplace/providers/conversations_provider.dart';
import 'package:fireplace/providers/encryption_provider.dart';
import 'package:fireplace/providers/messaging_provider.dart';
import 'package:fireplace/utils/e2e_envelope.dart';
import 'package:flutter_test/flutter_test.dart';

/// Encryption fake that succeeds immediately — happy send path.
class _WorkingEncryption extends EncryptionProvider {
  @override
  bool get isE2EReady => true;

  @override
  bool get hadIdentityReset => false;

  @override
  Future<void> ensureSession(int recipientId) async {}

  @override
  Future<String> encrypt(int recipientId, String plaintext) async =>
      'ciphertext';

  @override
  Future<String> decrypt(int senderId, String ciphertext) async =>
      jsonEncode(E2eEnvelope.build('decrypted'));

  @override
  Future<Map<String, dynamic>?> getDecryptedContent(int messageId) async =>
      null;

  @override
  Future<void> saveDecryptedContent(
          int messageId, Map<String, dynamic> data) async {}
}

/// Encryption fake whose ensureSession never completes — rows stay SENDING.
class _StuckEncryption extends _WorkingEncryption {
  final _never = Completer<void>();

  @override
  Future<void> ensureSession(int recipientId) => _never.future;
}

Map<String, dynamic> _convJson() => {
      'id': 10,
      'userOne': {'id': 1, 'username': 'alice', 'tag': '0001'},
      'userTwo': {'id': 2, 'username': 'bob', 'tag': '0002'},
      'createdAt': '2026-01-01T00:00:00.000Z',
      'unreadCount': 0,
      'lastMessage': null,
    };

Map<String, dynamic> _plainIncomingJson(int id) => {
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
  late List<Map<String, dynamic>> emitted;

  void wire(EncryptionProvider encryption) {
    provider = MessagingProvider();
    conversations = ConversationsProvider();
    emitted = <Map<String, dynamic>>[];

    conversations.setCurrentUserId(1);
    conversations.onConversationsList([_convJson()]);
    conversations.openConversation(10);

    provider.setConversationsProvider(conversations);
    provider.setEncryptionProvider(encryption);
    provider.setCurrentUserId(1);
    provider.setToken('tok');
    provider.setIncomingMessageSoundEnabledForTest(false);
    provider.onConnect(false);
    provider.setEmitCallback((event, data) {
      emitted.add({'event': event, 'data': data});
    });
    provider.setActiveConversationIdForTest(10);
  }

  group('onMessageSent temp -> real replacement', () {
    setUp(() => wire(_WorkingEncryption()));

    test(
        'replaces the optimistic temp row with the server row and restores '
        'plaintext from pending send content', () async {
      provider.sendMessage('secret plan');
      // Optimistic row is visible immediately.
      final temp = provider.messages.single;
      expect(temp.id, isNegative);
      expect(temp.deliveryStatus, MessageDeliveryStatus.sending);
      expect(temp.tempId, isNotNull);
      expect(temp.content, 'secret plan');

      // Let _encryptAndSend finish and capture the emitted tempId.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final sendEvent =
          emitted.singleWhere((e) => e['event'] == 'sendMessage');
      final tempId = (sendEvent['data'] as Map)['tempId'] as String;
      expect(tempId, temp.tempId);

      // Server confirms: real id, '[encrypted]' content, echoed tempId.
      provider.onMessageSent({
        'id': 555,
        'content': '[encrypted]',
        'encryptedContent': 'ciphertext',
        'senderId': 1,
        'senderUsername': 'alice',
        'conversationId': 10,
        'deliveryStatus': 'SENT',
        'messageType': 'TEXT',
        'createdAt': '2026-01-01T00:00:01.000Z',
        'tempId': tempId,
      });

      // Exactly one row: temp gone, real id in, plaintext restored.
      expect(provider.messages, hasLength(1));
      final real = provider.messages.single;
      expect(real.id, 555);
      expect(real.content, 'secret plan',
          reason: 'plaintext must be restored from _pendingSendContent, '
              'never shown as [encrypted]');
      expect(real.deliveryStatus, MessageDeliveryStatus.sent);
      expect(provider.messages.where((m) => m.id < 0), isEmpty);
    });

    test('messageSent with an unknown tempId does not corrupt existing rows',
        () async {
      provider.sendMessage('first');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final before = provider.messages.single;

      provider.onMessageSent({
        'id': 777,
        'content': '[encrypted]',
        'encryptedContent': 'ciphertext',
        'senderId': 1,
        'senderUsername': 'alice',
        'conversationId': 10,
        'deliveryStatus': 'SENT',
        'messageType': 'TEXT',
        'createdAt': '2026-01-01T00:00:02.000Z',
        'tempId': 'temp_unknown_999',
      });

      // The pending row for 'first' must still exist untouched.
      final firstRow =
          provider.messages.where((m) => m.tempId == before.tempId);
      expect(firstRow, hasLength(1));
      expect(firstRow.single.content, 'first');
      // No duplicate ids.
      final ids = provider.messages.map((m) => m.id).toList();
      expect(ids.toSet().length, ids.length);
    });
  });

  group('reactions', () {
    setUp(() => wire(_WorkingEncryption()));

    test('onReactionUpdated patches the target message reactions', () {
      provider.onMessageHistory({
        'conversationId': 10,
        'messages': [_plainIncomingJson(50)],
      });
      expect(provider.messages.single.reactions, isEmpty);

      provider.onReactionUpdated({
        'messageId': 50,
        'reactions': {
          '🔥': [2],
          '👍': [1, 2],
        },
      });

      final reactions = provider.messages.single.reactions;
      expect(reactions['🔥'], [2]);
      expect(reactions['👍'], [1, 2]);
    });

    test('onReactionUpdated for an unknown message id is a safe no-op', () {
      provider.onMessageHistory({
        'conversationId': 10,
        'messages': [_plainIncomingJson(50)],
      });

      expect(
        () => provider.onReactionUpdated({
          'messageId': 9999,
          'reactions': {
            '🔥': [2],
          },
        }),
        returnsNormally,
      );
      expect(provider.messages.single.reactions, isEmpty);
    });

    test('addReaction / removeReaction emit the wire payloads', () {
      provider.addReaction(50, '🔥');
      provider.removeReaction(50, '🔥');

      expect(emitted, [
        {
          'event': 'addReaction',
          'data': {'messageId': 50, 'emoji': '🔥'},
        },
        {
          'event': 'removeReaction',
          'data': {'messageId': 50, 'emoji': '🔥'},
        },
      ]);
    });
  });

  group('typing indicators', () {
    setUp(() => wire(_WorkingEncryption()));

    test('onPartnerTyping sets the flag and expires after the timer window',
        () {
      fakeAsync((async) {
        provider.onPartnerTyping({'conversationId': 10});
        expect(provider.isPartnerTyping(10), isTrue);

        async.elapse(const Duration(seconds: 2, milliseconds: 900));
        expect(provider.isPartnerTyping(10), isTrue,
            reason: 'flag must survive until the 3s window elapses');

        async.elapse(const Duration(milliseconds: 200));
        expect(provider.isPartnerTyping(10), isFalse);
      });
    });

    test('typing in another conversation does not leak into the active one',
        () {
      fakeAsync((async) {
        provider.onPartnerTyping({'conversationId': 99});
        expect(provider.isPartnerTyping(10), isFalse);
        expect(provider.isPartnerTyping(99), isTrue);
        async.elapse(const Duration(seconds: 4));
        expect(provider.isPartnerTyping(99), isFalse);
      });
    });

    test('an incoming message from the partner clears the typing flag', () {
      fakeAsync((async) {
        provider.onPartnerTyping({'conversationId': 10});
        expect(provider.isPartnerTyping(10), isTrue);

        provider.onNewMessage(_plainIncomingJson(60));
        expect(provider.isPartnerTyping(10), isFalse,
            reason: 'message arrival supersedes the typing indicator');
      });
    });
  });

  group('onLinkPreviewReady', () {
    setUp(() => wire(_WorkingEncryption()));

    test('patches preview fields onto the target message', () {
      provider.onMessageHistory({
        'conversationId': 10,
        'messages': [_plainIncomingJson(70)],
      });

      provider.onLinkPreviewReady({
        'messageId': 70,
        'linkPreviewUrl': 'https://example.com',
        'linkPreviewTitle': 'Example',
        'linkPreviewImageUrl': 'https://example.com/og.png',
      });

      final msg = provider.messages.single;
      expect(msg.linkPreviewUrl, 'https://example.com');
      expect(msg.linkPreviewTitle, 'Example');
      expect(msg.linkPreviewImageUrl, 'https://example.com/og.png');
    });

    test('unknown message id is a safe no-op', () {
      provider.onMessageHistory({
        'conversationId': 10,
        'messages': [_plainIncomingJson(70)],
      });

      expect(
        () => provider.onLinkPreviewReady({
          'messageId': 9999,
          'linkPreviewUrl': 'https://example.com',
        }),
        returnsNormally,
      );
      expect(provider.messages.single.linkPreviewUrl, isNull);
    });
  });

  group('markSendingMessagesFailed', () {
    test('flips SENDING rows to failed and leaves settled rows untouched',
        () async {
      wire(_StuckEncryption());

      // Settled row from the peer.
      provider.onMessageHistory({
        'conversationId': 10,
        'messages': [_plainIncomingJson(80)],
      });

      // Own send stuck in SENDING (ensureSession never resolves).
      provider.sendMessage('stuck one');
      await Future<void>.delayed(Duration.zero);
      expect(
        provider.messages
            .where((m) => m.deliveryStatus == MessageDeliveryStatus.sending),
        hasLength(1),
      );

      provider.markSendingMessagesFailed('socket error');

      final own = provider.messages.singleWhere((m) => m.tempId != null);
      expect(own.deliveryStatus, MessageDeliveryStatus.failed);
      final settled = provider.messages.singleWhere((m) => m.id == 80);
      expect(settled.deliveryStatus, MessageDeliveryStatus.delivered,
          reason: 'already-settled rows must not be touched');
    });

    test('failed rows become retryable: a retry emits sendMessage again',
        () async {
      wire(_WorkingEncryption());

      provider.sendMessage('retry me');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(
          emitted.where((e) => e['event'] == 'sendMessage'), hasLength(1));

      // Simulate socket error flipping the (already sent but unconfirmed) row.
      provider.markSendingMessagesFailed('socket error');

      final row = provider.messages.single;
      // Re-run the send path with the same tempId — the exactly-once latch
      // must have been released by the failure.
      await provider.encryptAndSendForTest(
        recipientId: 2,
        content: 'retry me',
        tempId: row.tempId!,
      );
      expect(
          emitted.where((e) => e['event'] == 'sendMessage'), hasLength(2));
    });
  });
}
