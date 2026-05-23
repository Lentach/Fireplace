import 'package:fireplace/models/message_model.dart';
import 'package:fireplace/utils/scroll_to_message_helper.dart';
import 'package:flutter_test/flutter_test.dart';

MessageModel _m(int id) => MessageModel(
      id: id,
      content: 'msg$id',
      senderId: 1,
      senderUsername: 'alice',
      conversationId: 10,
      createdAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  test('listIndexForMessageId oldest-first in reverse ListView', () {
    expect(
      listIndexForMessageId(
        messageId: 2,
        messages: [
          _m(1),
          _m(2),
          _m(3),
        ],
      ),
      1,
    );
  });

  test('returns null when id not in list', () {
    expect(
      listIndexForMessageId(messageId: 99, messages: [_m(1)]),
      isNull,
    );
  });

  test('loadListIndexForMessageId paginates until message found', () async {
    var messages = List<MessageModel>.generate(50, (i) => _m(i + 1));
    var hasMore = true;
    var loadCount = 0;

    final listIndex = await loadListIndexForMessageId(
      messageId: 100,
      getMessages: () => messages,
      hasMoreMessages: () => hasMore,
      loadOlderPage: () async {
        loadCount++;
        messages = [_m(100), ...messages];
        hasMore = false;
      },
    );

    expect(listIndex, messages.length - 1);
    expect(loadCount, 1);
  });

  test('loadListIndexForMessageId returns null when not found', () async {
    final listIndex = await loadListIndexForMessageId(
      messageId: 999,
      getMessages: () => [_m(1)],
      hasMoreMessages: () => false,
      loadOlderPage: () async {},
    );
    expect(listIndex, isNull);
  });
}
