import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/models/message_model.dart';
import 'package:fireplace/utils/message_expiry.dart';

MessageModel _msg({
  DateTime? expiresAt,
  int? disappearAfterSeconds,
  DateTime? createdAt,
}) {
  return MessageModel(
    id: 1,
    content: 'x',
    senderId: 1,
    senderUsername: 'a',
    conversationId: 1,
    createdAt: createdAt ?? DateTime(2026, 5, 16, 12),
    expiresAt: expiresAt,
    disappearAfterSeconds: disappearAfterSeconds,
  );
}

void main() {
  group('isMessageExpired', () {
    test('expires when expiresAt is in the past', () {
      final now = DateTime(2026, 5, 17, 12);
      final m = _msg(expiresAt: DateTime(2026, 5, 17, 11));
      expect(isMessageExpired(m, now), isTrue);
    });

    test('never-read read-mode expires after 1 day', () {
      final now = DateTime(2026, 5, 17, 12);
      final m = _msg(
        disappearAfterSeconds: 3600,
        createdAt: DateTime(2026, 5, 15, 12),
      );
      expect(isMessageExpired(m, now), isTrue);
    });

    test('never-read read-mode active within 1 day', () {
      final now = DateTime(2026, 5, 17, 12);
      final m = _msg(
        disappearAfterSeconds: 86400,
        createdAt: DateTime(2026, 5, 17, 10),
      );
      expect(isMessageExpired(m, now), isFalse);
    });

    test('grandfathered future expiresAt is active', () {
      final now = DateTime(2026, 5, 17, 12);
      final m = _msg(expiresAt: DateTime(2026, 5, 18, 12));
      expect(isMessageExpired(m, now), isFalse);
    });
  });

  group('splitDisappearingSeconds / combineDisappearingSeconds', () {
    test('1 day splits to 1/0/0/0', () {
      final parts = splitDisappearingSeconds(86400);
      expect(parts.days, 1);
      expect(parts.hours, 0);
      expect(parts.minutes, 0);
      expect(parts.seconds, 0);
    });

    test('2 days 3 minutes round-trips', () {
      const total = 2 * 86400 + 3 * 60;
      final parts = splitDisappearingSeconds(total);
      expect(
        combineDisappearingSeconds(
          days: parts.days,
          hours: parts.hours,
          minutes: parts.minutes,
          seconds: parts.seconds,
        ),
        total,
      );
    });

    test('all zero combines to 0', () {
      expect(
        combineDisappearingSeconds(days: 0, hours: 0, minutes: 0, seconds: 0),
        0,
      );
    });
  });
}
