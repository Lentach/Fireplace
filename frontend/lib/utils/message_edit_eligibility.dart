import '../models/message_model.dart';

/// Client-side edit window. Mirrors the server's `EDIT_WINDOW_MS` (15 min); the
/// server is the authoritative enforcer, this only decides whether to show the
/// Edit affordance.
const Duration kMessageEditWindow = Duration(minutes: 15);

/// True when [message] may be edited by the current user from the context menu:
/// own + TEXT + real plaintext + a confirmed server id (positive) + a delivered
/// state (never an optimistic/failed row) + within the edit window. The client
/// gate is never the sole enforcer — the server re-checks sender + window.
bool messageEditEligible(
  MessageModel message, {
  required bool isMine,
  DateTime? now,
}) {
  if (!isMine) return false;
  if (message.messageType != MessageType.text) return false;
  if (message.id <= 0) return false; // optimistic/unsent row — no server row yet
  if (!message.hasCopyablePlaintext) return false; // placeholder/terminal labels
  switch (message.deliveryStatus) {
    case MessageDeliveryStatus.sent:
    case MessageDeliveryStatus.delivered:
    case MessageDeliveryStatus.read:
      break;
    case MessageDeliveryStatus.sending:
    case MessageDeliveryStatus.failed:
      return false;
  }
  final reference = now ?? DateTime.now();
  return reference.difference(message.createdAt) < kMessageEditWindow;
}
