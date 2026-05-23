// reverse:true → visual bottom = offset 0 = newest.
// msgIndex (oldest-first) → listIndex = messages.length - 1 - msgIndex.
// This file does NOT call Scrollable.ensureVisible — caller owns GlobalKey lifecycle.

import '../models/message_model.dart';

/// With [ListView.reverse: true], builder index 0 = newest (last in oldest-first list).
int? listIndexForMessageId({
  required int messageId,
  required List<MessageModel> messages,
}) {
  final msgIndex = messages.indexWhere((m) => m.id == messageId);
  if (msgIndex < 0) return null;
  return messages.length - 1 - msgIndex;
}

/// Paginate older pages until [messageId] appears in the loaded list, or give up.
/// Returns reverse-ListView builder index, or null if not found / no more pages.
/// Caller must assign [GlobalKey] to that index, rebuild, then call ensureVisible.
Future<int?> loadListIndexForMessageId({
  required int messageId,
  required List<MessageModel> Function() getMessages,
  required bool Function() hasMoreMessages,
  required Future<void> Function() loadOlderPage,
}) async {
  const maxPages = 40;
  for (var attempt = 0; attempt < maxPages; attempt++) {
    final listIndex = listIndexForMessageId(
      messageId: messageId,
      messages: getMessages(),
    );
    if (listIndex != null) return listIndex;
    if (!hasMoreMessages()) break;
    await loadOlderPage();
  }
  return null;
}
