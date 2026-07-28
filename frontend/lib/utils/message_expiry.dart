import '../models/message_model.dart';

/// Never-read retention for read-mode messages (1 day from send).
const int kNeverReadRetentionSeconds = 86400;

const int kDisappearingMinSeconds = 5;
const int kDisappearingMaxSeconds = 2592000;

bool isMessageExpired(MessageModel message, [DateTime? now]) {
  final n = now ?? DateTime.now();
  if (message.expiresAt != null && message.expiresAt!.isBefore(n)) {
    return true;
  }
  if (message.disappearAfterSeconds != null && message.expiresAt == null) {
    final deadline = message.createdAt.add(
      const Duration(seconds: kNeverReadRetentionSeconds),
    );
    if (n.isAfter(deadline)) return true;
  }
  return false;
}

/// Delay between a message expiring and its plaintext being DESTROYED.
///
/// Covers the server's own lag plus error in the server-time estimate. The
/// backend deletes expired rows from `@Cron(EVERY_MINUTE)`, so a row can
/// outlive its `expiresAt` by up to 60s; destroying inside that window means
/// the server re-serves a message whose only plaintext copy we just deleted,
/// which re-decrypts into a permanent "[Decryption failed]". Five minutes buys
/// that back many times over, and the cost of waiting is only that expired
/// plaintext lingers a few minutes longer than the UI shows it.
const Duration kExpiryPurgeGrace = Duration(minutes: 5);

/// The instant [message] expires, or null if it never does.
///
/// Mirrors [isMessageExpired] exactly, including that a non-null `expiresAt`
/// is authoritative and suppresses the never-read fallback. Any divergence
/// between the two would let a message be destroyed while still displayed.
DateTime? messageExpiryDeadline(MessageModel message) {
  final expiresAt = message.expiresAt;
  if (expiresAt != null) return expiresAt;
  if (message.disappearAfterSeconds != null) {
    return message.createdAt.add(
      const Duration(seconds: kNeverReadRetentionSeconds),
    );
  }
  return null;
}

/// Whether [message]'s plaintext may be DESTROYED, given [serverNow] from
/// `ServerClock.estimatedNow`.
///
/// Deliberately separate from [isMessageExpired]. Hiding a message is
/// reversible and may run on the local clock; destroying its plaintext is
/// irreversible — the persisted record is the only copy — and must not. A
/// device running fast would otherwise wipe messages that are still live on
/// the server.
///
/// [serverNow] of null means the server clock could not be confirmed, and that
/// is answered with false. "Cannot confirm" is never "safe to destroy".
bool mayDestroyExpiredPlaintext(MessageModel message, DateTime? serverNow) {
  if (serverNow == null) return false;
  final deadline = messageExpiryDeadline(message);
  if (deadline == null) return false;
  return serverNow.isAfter(deadline.add(kExpiryPurgeGrace));
}

/// Split [totalSeconds] into days, hours, minutes, seconds.
({int days, int hours, int minutes, int seconds}) splitDisappearingSeconds(
  int totalSeconds,
) {
  var remaining = totalSeconds;
  final days = remaining ~/ 86400;
  remaining %= 86400;
  final hours = remaining ~/ 3600;
  remaining %= 3600;
  final minutes = remaining ~/ 60;
  final seconds = remaining % 60;
  return (days: days, hours: hours, minutes: minutes, seconds: seconds);
}

int combineDisappearingSeconds({
  required int days,
  required int hours,
  required int minutes,
  required int seconds,
}) {
  return days * 86400 + hours * 3600 + minutes * 60 + seconds;
}
