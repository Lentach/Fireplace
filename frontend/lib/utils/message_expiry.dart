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
