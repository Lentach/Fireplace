import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fireplace/providers/encryption_provider.dart';
import 'package:fireplace/services/encryption_service.dart';

/// Phase 0b client contract (multi-device spec §6.1/§6.2).
///
/// The server is authoritative for the ceremony; this pins that the client
/// mirrors it faithfully, keeps the 0.1.10 UNKNOWN invariant intact, and never
/// resurrects an alarm the user already dismissed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late EncryptionProvider provider;
  late List<({String event, dynamic data})> emitted;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    provider = EncryptionProvider(service: EncryptionService());
    emitted = [];
    provider.setEmitCallback((event, data) {
      emitted.add((event: event, data: data));
    });
  });

  group('reset ceremony state', () {
    test('a pending broadcast raises the countdown on every session', () {
      final deadline = DateTime.now().toUtc().add(const Duration(hours: 72));

      provider.onIdentityResetPending({
        'deadlineAt': deadline.toIso8601String(),
        'shortened': false,
        'occurredAt': DateTime.now().toUtc().toIso8601String(),
      });

      expect(provider.identityResetDeadline, isNotNull);
      expect(provider.identityResetShortened, isFalse);
    });

    test('a shortened ceremony is still surfaced, just with a nearer deadline',
        () {
      final deadline = DateTime.now().toUtc().add(const Duration(hours: 1));

      provider.onIdentityResetPending({
        'deadlineAt': deadline.toIso8601String(),
        'shortened': true,
        'occurredAt': DateTime.now().toUtc().toIso8601String(),
      });

      expect(provider.identityResetDeadline, isNotNull);
      expect(
        provider.identityResetShortened,
        isTrue,
        reason: 'a recovery key shortens the wait; it never silences it',
      );
    });

    test('the cancelled broadcast clears the countdown', () {
      provider.onIdentityResetPending({
        'deadlineAt':
            DateTime.now().toUtc().add(const Duration(hours: 72)).toIso8601String(),
        'shortened': false,
      });

      provider.onIdentityResetCancelled({'occurredAt': 'now'});

      expect(provider.identityResetDeadline, isNull);
    });

    test('cancelling emits the server event', () {
      provider.cancelIdentityReset();

      expect(emitted.single.event, 'resetIdentityCancel');
    });

    test('requesting without a phrase sends no phrase field', () {
      provider.requestIdentityReset();

      expect(emitted.single.event, 'resetIdentityRequest');
      expect((emitted.single.data as Map).containsKey('recoveryPhrase'), isFalse);
    });

    test('requesting with a phrase forwards it once', () {
      provider.requestIdentityReset(recoveryPhrase: 'twelve words here');

      expect(emitted.single.data, {'recoveryPhrase': 'twelve words here'});
    });

    test('a malformed payload changes nothing', () {
      provider.onIdentityResetPending({'deadlineAt': 'not-a-date'});
      expect(provider.identityResetDeadline, isNull);

      provider.onIdentityResetPending('garbage');
      expect(provider.identityResetDeadline, isNull);
    });

    test('refusal statuses are reported without inventing a deadline', () {
      for (final status in ['cooldown', 'invalid_phrase', 'locked']) {
        provider.onIdentityResetStatus({'status': status});
        expect(provider.identityResetRequestStatus, status);
        expect(provider.identityResetDeadline, isNull);
      }
    });
  });

  group('registration lock refusal', () {
    test('an identity_locked answer is terminal, not a retry signal', () {
      provider.onKeyBundleUploaded({
        'success': false,
        'error': 'identity_locked',
      });

      expect(provider.identityUploadLocked, isTrue);
    });

    test('a successful upload clears the locked state', () {
      provider.onKeyBundleUploaded({
        'success': false,
        'error': 'identity_locked',
      });
      provider.onKeyBundleUploaded({'success': true});

      expect(provider.identityUploadLocked, isFalse);
    });
  });

  group('connect-time hydration', () {
    test('a pending ceremony is restored for a session that was offline', () {
      final deadline = DateTime.now().toUtc().add(const Duration(hours: 40));

      provider.onOwnKeyBundleStatus({
        'exists': true,
        'identityReset': {
          'status': 'pending',
          'deadlineAt': deadline.toIso8601String(),
        },
        'identityReplacedAt': null,
      });

      expect(provider.identityResetDeadline, isNotNull);
    });

    test('an explicit null clears a stale local countdown', () {
      provider.onIdentityResetPending({
        'deadlineAt':
            DateTime.now().toUtc().add(const Duration(hours: 72)).toIso8601String(),
        'shortened': false,
      });

      provider.onOwnKeyBundleStatus({
        'exists': true,
        'identityReset': null,
        'identityReplacedAt': null,
      });

      expect(provider.identityResetDeadline, isNull);
    });

    test('a completed ceremony is reported as spendable', () {
      provider.onOwnKeyBundleStatus({
        'exists': true,
        'identityReset': {
          'status': 'completed',
          'deadlineAt': DateTime.now().toUtc().toIso8601String(),
        },
        'identityReplacedAt': null,
      });

      expect(provider.identityResetCompleted, isTrue);
      expect(provider.identityResetDeadline, isNull);
    });

    test('an older server answer (no 0b fields) keeps the UNKNOWN invariant',
        () async {
      // Absent fields must not be read as "nothing pending" for key generation
      // purposes: `exists` still drives that decision, unchanged from 0.1.10.
      provider.onOwnKeyBundleStatus({'exists': true});

      expect(provider.identityResetDeadline, isNull);
      expect(provider.identityResetCompleted, isFalse);
    });
  });

  group('own-replacement hydration respects dismissal', () {
    test('a replacement reported at connect raises the banner', () async {
      final service = EncryptionService();
      await service.recordOwnIdentityReplacedFromServer(
        '2026-08-18T00:00:00.000Z',
      );

      expect(service.ownIdentityReplacedAt, '2026-08-18T00:00:00.000Z');
    });

    test('the SAME replacement never comes back after dismissal', () async {
      final service = EncryptionService();
      await service.recordOwnIdentityReplaced('2026-08-18T00:00:00.000Z');
      await service.dismissOwnIdentityReplaced();

      // Every reconnect re-reports the audit row; without a watermark this
      // would re-raise a banner the user already handled, forever.
      await service.recordOwnIdentityReplacedFromServer(
        '2026-08-18T00:00:00.000Z',
      );

      expect(service.ownIdentityReplacedAt, isNull);
    });

    test('a NEWER replacement still alarms after an earlier dismissal',
        () async {
      final service = EncryptionService();
      await service.recordOwnIdentityReplaced('2026-08-18T00:00:00.000Z');
      await service.dismissOwnIdentityReplaced();

      await service.recordOwnIdentityReplacedFromServer(
        '2026-08-19T00:00:00.000Z',
      );

      expect(service.ownIdentityReplacedAt, '2026-08-19T00:00:00.000Z');
    });
  });
}
