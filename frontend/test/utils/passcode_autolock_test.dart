import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/utils/passcode_autolock.dart';

void main() {
  const t0 = 1757000000000; // fixed wall clock, ms

  group('shouldLockOnForeground', () {
    test('a disabled passcode never locks, however long the app was away', () {
      expect(
        shouldLockOnForeground(
          enabled: false,
          lastActiveAtMs: t0,
          nowMs: t0 + const Duration(days: 7).inMilliseconds,
          autoLockSeconds: 60,
        ),
        isFalse,
      );
    });

    test('stays unlocked while inside the auto-lock window', () {
      expect(
        shouldLockOnForeground(
          enabled: true,
          lastActiveAtMs: t0,
          nowMs: t0 + const Duration(seconds: 59).inMilliseconds,
          autoLockSeconds: 60,
        ),
        isFalse,
      );
    });

    test('locks once the away time reaches the auto-lock window', () {
      expect(
        shouldLockOnForeground(
          enabled: true,
          lastActiveAtMs: t0,
          nowMs: t0 + const Duration(seconds: 60).inMilliseconds,
          autoLockSeconds: 60,
        ),
        isTrue,
      );
    });

    test('autoLockSeconds 0 means lock the moment the app leaves foreground',
        () {
      expect(
        shouldLockOnForeground(
          enabled: true,
          lastActiveAtMs: t0,
          nowMs: t0 + 1,
          autoLockSeconds: 0,
        ),
        isTrue,
      );
    });

    // Fail-closed cases. A missing stamp is exactly the cold-boot/cleared-
    // storage shape, and a backwards clock is what a timezone change or a
    // deliberate clock rollback looks like; both MUST lock rather than hand
    // the chat list to whoever is holding the phone.
    test('a missing last-active stamp locks (cold boot, wiped prefs)', () {
      expect(
        shouldLockOnForeground(
          enabled: true,
          lastActiveAtMs: null,
          nowMs: t0,
          autoLockSeconds: 3600,
        ),
        isTrue,
      );
    });

    test('a clock that moved backwards locks instead of granting free time',
        () {
      expect(
        shouldLockOnForeground(
          enabled: true,
          lastActiveAtMs: t0,
          nowMs: t0 - 1,
          autoLockSeconds: 3600,
        ),
        isTrue,
      );
    });
  });

  group('kPasscodeAutoLockChoices', () {
    test('offers immediate, 1 min, 5 min and 1 hour, in ascending order', () {
      expect(kPasscodeAutoLockChoices, const [0, 60, 300, 3600]);
    });

    test('the default is 1 minute (owner ruling 2026-09-03)', () {
      expect(kPasscodeAutoLockDefaultSeconds, 60);
      expect(kPasscodeAutoLockChoices, contains(kPasscodeAutoLockDefaultSeconds));
    });
  });

  group('passcodeBackoffFor', () {
    test('the first wrong codes cost nothing', () {
      for (var i = 0; i < kPasscodeAttemptsBeforeBackoff; i++) {
        expect(passcodeBackoffFor(i), Duration.zero, reason: 'attempt $i');
      }
    });

    test('escalates 30s, 1m, 5m and then caps at 15m', () {
      expect(passcodeBackoffFor(5), const Duration(seconds: 30));
      expect(passcodeBackoffFor(6), const Duration(minutes: 1));
      expect(passcodeBackoffFor(7), const Duration(minutes: 5));
      expect(passcodeBackoffFor(8), const Duration(minutes: 15));
      expect(passcodeBackoffFor(99), const Duration(minutes: 15));
    });

    test('never decreases as attempts pile up', () {
      var previous = Duration.zero;
      for (var i = 0; i <= 20; i++) {
        final current = passcodeBackoffFor(i);
        expect(current, greaterThanOrEqualTo(previous), reason: 'attempt $i');
        previous = current;
      }
    });
  });
}
