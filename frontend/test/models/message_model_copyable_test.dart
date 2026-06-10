import 'package:fireplace/models/message_model.dart';
import 'package:flutter_test/flutter_test.dart';

MessageModel _msg({
  MessageType messageType = MessageType.text,
  String content = 'hello',
}) =>
    MessageModel(
      id: 1,
      content: content,
      senderId: 1,
      senderUsername: 'alice',
      conversationId: 1,
      createdAt: DateTime(2026, 6, 10),
      messageType: messageType,
    );

void main() {
  group('MessageModel.hasCopyablePlaintext', () {
    test('true for TEXT message with real plaintext', () {
      expect(_msg().hasCopyablePlaintext, isTrue);
    });

    test('false for empty content', () {
      expect(_msg(content: '').hasCopyablePlaintext, isFalse);
    });

    test('false for E2E placeholder and terminal labels', () {
      expect(_msg(content: '[encrypted]').hasCopyablePlaintext, isFalse);
      expect(
        _msg(content: '[Decryption failed]').hasCopyablePlaintext,
        isFalse,
      );
      expect(
        _msg(content: '[Encryption not initialized]').hasCopyablePlaintext,
        isFalse,
      );
    });

    test('false for every non-TEXT message type', () {
      for (final type in [
        MessageType.ping,
        MessageType.image,
        MessageType.voice,
        MessageType.gif,
        MessageType.file,
      ]) {
        expect(
          _msg(messageType: type).hasCopyablePlaintext,
          isFalse,
          reason: 'type $type must not be copyable',
        );
      }
    });
  });
}
