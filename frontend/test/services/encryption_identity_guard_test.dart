import 'dart:convert';

import 'package:fireplace/services/encryption/signal_stores.dart';
import 'package:fireplace/services/encryption_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The identity is the one piece of Signal state whose loss is total and
/// silent: regenerate it and every peer's history becomes permanently
/// undecryptable, with no error and nothing on screen. It used to live in TWO
/// independent storage keys, so losing exactly one made `loadFromStorage()`
/// report "fresh install" and the service happily minted a new identity.
///
/// These tests pin the three things that stop that:
///   1. the identity is now ONE atomic record;
///   2. the legacy two-key layout every existing install has still loads, and
///      is migrated without regenerating anything;
///   3. anything that looks like partial loss fails CLOSED — no new identity,
///      no writes — and offers an explicit, consented way out.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secure = FlutterSecureStorage();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  String legacyPair(IdentityKeyPair pair) => base64Encode(pair.serialize());

  group('identity load', () {
    test('fresh install with nothing stored generates an identity', () async {
      final svc = EncryptionService();
      await svc.initialize(1, checkServerBundleExists: () async => false);

      expect(svc.needsKeyUpload, isTrue);
      expect(svc.identityIncomplete, isFalse);
      expect(
        await secure.read(key: 'e2e_1_identity_record_v1'),
        isNotNull,
        reason: 'the atomic record is the new source of truth',
      );
    });

    /// The installed base has ONLY the two legacy keys. If they stopped being
    /// read, every existing user would look like a fresh install and lose
    /// everything — the exact disaster this change exists to prevent.
    test('legacy two-key identity loads and is migrated, never regenerated',
        () async {
      final pair = generateIdentityKeyPair();
      FlutterSecureStorage.setMockInitialValues({
        'e2e_5_identity_key_pair': legacyPair(pair),
        'e2e_5_registration_id': '9182',
        'e2e_5_session_7_1': 'fake-record',
      });

      final svc = EncryptionService();
      await svc.initialize(5, checkServerBundleExists: () async => false);

      expect(
        svc.needsKeyUpload,
        isFalse,
        reason: 'loading a legacy identity must NOT count as a fresh install',
      );
      expect(
        await secure.read(key: 'e2e_5_identity_key_pair'),
        legacyPair(pair),
        reason: 'the legacy keys are left intact for older bundles',
      );
      final migrated = await secure.read(key: 'e2e_5_identity_record_v1');
      expect(migrated, isNotNull, reason: 'upgraded to the atomic record');
      final decoded = jsonDecode(migrated!) as Map<String, dynamic>;
      expect(decoded['pair'], legacyPair(pair));
      expect(decoded['registrationId'], 9182);
    });

    test('an identity written today survives a reload', () async {
      final first = EncryptionService();
      await first.initialize(11, checkServerBundleExists: () async => false);
      final record = await secure.read(key: 'e2e_11_identity_record_v1');

      final second = EncryptionService();
      await second.initialize(11, checkServerBundleExists: () async => false);

      expect(second.needsKeyUpload, isFalse);
      expect(await secure.read(key: 'e2e_11_identity_record_v1'), record);
    });
  });

  group('partial loss fails closed', () {
    /// Half the legacy pair survives. This is the shape that used to silently
    /// mint a new identity.
    test('only the key pair survives -> refuses, mints nothing', () async {
      final pair = generateIdentityKeyPair();
      FlutterSecureStorage.setMockInitialValues({
        'e2e_2_identity_key_pair': legacyPair(pair),
      });

      final svc = EncryptionService();
      await expectLater(
        svc.initialize(2, checkServerBundleExists: () async => false),
        throwsA(isA<E2eIdentityIncompleteException>()),
      );
      expect(svc.identityIncomplete, isTrue);
      expect(
        await secure.read(key: 'e2e_2_identity_record_v1'),
        isNull,
        reason: 'no new identity may be written over damaged material',
      );
      expect(
        await secure.read(key: 'e2e_2_identity_key_pair'),
        legacyPair(pair),
        reason: 'the surviving bytes are left alone; they may be recoverable',
      );
    });

    test('only the registration id survives -> refuses', () async {
      FlutterSecureStorage.setMockInitialValues({
        'e2e_3_registration_id': '4242',
      });

      final svc = EncryptionService();
      await expectLater(
        svc.initialize(3, checkServerBundleExists: () async => false),
        throwsA(isA<E2eIdentityIncompleteException>()),
      );
    });

    /// Identity fully gone but sessions survive: also partial loss, and
    /// regenerating would strand every one of those sessions.
    test('sessions survive without an identity -> refuses', () async {
      FlutterSecureStorage.setMockInitialValues({
        'e2e_4_session_49_1': 'fake-record',
      });

      final svc = EncryptionService();
      await expectLater(
        svc.initialize(4, checkServerBundleExists: () async => false),
        throwsA(isA<E2eIdentityIncompleteException>()),
      );
      expect(await secure.read(key: 'e2e_4_identity_record_v1'), isNull);
    });

    test('a corrupt atomic record is damage, not absence', () async {
      FlutterSecureStorage.setMockInitialValues({
        'e2e_6_identity_record_v1': '{"registrationId": 7}',
      });

      final svc = EncryptionService();
      await expectLater(
        svc.initialize(6, checkServerBundleExists: () async => false),
        throwsA(isA<E2eIdentityIncompleteException>()),
      );
    });

    /// Fail-closed must protect users with data at risk, not brick users who
    /// have none: leftover PLAINTEXT cache is not Signal material.
    test('a decrypted-content cache alone is not prior-install residue',
        () async {
      SharedPreferences.setMockInitialValues({
        'flutter.e2e_8_decrypted_1': '{"content":"hi"}',
      });

      final svc = EncryptionService();
      await svc.initialize(8, checkServerBundleExists: () async => false);

      expect(svc.needsKeyUpload, isTrue);
      expect(svc.identityIncomplete, isFalse);
    });
  });

  /// The server-backed fresh-install guard (0.1.10). A truly empty store is
  /// NOT proof of a fresh install: the same emptiness is produced by a storage
  /// wipe and by a second-device login, and generating keys in either case
  /// silently destroys every peer's history. Only an explicit server
  /// "no bundle" may authorize generation; everything else fails closed.
  group('server-backed fresh-install guard', () {
    test('empty store + server bundle exists -> refuses, mints nothing',
        () async {
      final svc = EncryptionService();
      await expectLater(
        svc.initialize(21, checkServerBundleExists: () async => true),
        throwsA(isA<E2eIdentityIncompleteException>()),
      );
      expect(svc.identityIncomplete, isTrue);
      expect(
        await secure.read(key: 'e2e_21_identity_record_v1'),
        isNull,
        reason: 'a wipe or second-device login must never silently re-mint',
      );
    });

    test('empty store + server says no bundle -> genuine fresh install',
        () async {
      final svc = EncryptionService();
      await svc.initialize(22, checkServerBundleExists: () async => false);

      expect(svc.needsKeyUpload, isTrue);
      expect(svc.identityIncomplete, isFalse);
      expect(await secure.read(key: 'e2e_22_identity_record_v1'), isNotNull);
    });

    test('UNKNOWN (null) defers: no keys, not damaged, retryable', () async {
      final svc = EncryptionService();
      await expectLater(
        svc.initialize(23, checkServerBundleExists: () async => null),
        throwsA(isA<E2eIdentityCheckUnavailableException>()),
      );
      expect(
        svc.identityIncomplete,
        isFalse,
        reason: 'UNKNOWN is transient — it must not raise the '
            'destructive-recovery surface',
      );
      expect(await secure.read(key: 'e2e_23_identity_record_v1'), isNull);
    });

    test('a throwing check is UNKNOWN, never a fresh install', () async {
      final svc = EncryptionService();
      await expectLater(
        svc.initialize(
          24,
          checkServerBundleExists: () async => throw StateError('offline'),
        ),
        throwsA(isA<E2eIdentityCheckUnavailableException>()),
      );
      expect(await secure.read(key: 'e2e_24_identity_record_v1'), isNull);
    });

    test('an absent callback is UNKNOWN: no caller may skip the check',
        () async {
      final svc = EncryptionService();
      await expectLater(
        svc.initialize(25),
        throwsA(isA<E2eIdentityCheckUnavailableException>()),
      );
    });

    test('an existing identity never consults the server', () async {
      final svc = EncryptionService();
      await svc.initialize(26, checkServerBundleExists: () async => false);

      final reloaded = EncryptionService();
      var consulted = false;
      await reloaded.initialize(
        26,
        checkServerBundleExists: () async {
          consulted = true;
          return true;
        },
      );

      expect(
        consulted,
        isFalse,
        reason: 'the guard runs only on a truly empty store — a boot-time '
            'round trip on every healthy start would be a regression',
      );
      expect(reloaded.needsKeyUpload, isFalse);
    });
  });

  group('consented recovery', () {
    test('regeneration clears the damaged material and starts a new identity',
        () async {
      final pair = generateIdentityKeyPair();
      FlutterSecureStorage.setMockInitialValues({
        'e2e_9_identity_key_pair': legacyPair(pair),
        'e2e_9_session_49_1': 'fake-record',
        'e2e_9_signed_pre_key_0': 'stale',
        'e2e_9_next_pre_key_id': '120',
      });

      final svc = EncryptionService();
      await expectLater(
        svc.initialize(9, checkServerBundleExists: () async => false),
        throwsA(isA<E2eIdentityIncompleteException>()),
      );

      await svc.regenerateIdentityAfterConfirmedLoss(9);

      expect(svc.identityIncomplete, isFalse);
      expect(
        svc.needsKeyUpload,
        isTrue,
        reason: 'the new bundle has to reach the server',
      );
      expect(await secure.read(key: 'e2e_9_identity_record_v1'), isNotNull);
      expect(
        await secure.read(key: 'e2e_9_session_49_1'),
        isNull,
        reason: 'stale sessions would strand the new identity',
      );
      expect(
        await secure.read(key: 'e2e_9_identity_key_pair'),
        isNot(legacyPair(pair)),
        reason: 'the damaged legacy identity is replaced, not kept',
      );

      // And the service is usable again.
      final reloaded = EncryptionService();
      await reloaded.initialize(9, checkServerBundleExists: () async => false);
      expect(reloaded.needsKeyUpload, isFalse);
    });
  });

  group('peer identity change is surfaced', () {
    late DualStorage storage;

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      storage = DualStorage(const FlutterSecureStorage());
    });

    test('first contact is silent (trust on first use)', () async {
      final changed = <String>[];
      final store = SecureIdentityKeyStore(
        storage,
        'tofu_',
        onIdentityChanged: (a) => changed.add(a.getName()),
      );
      final peer = generateIdentityKeyPair();

      await store.isTrustedIdentity(
        SignalProtocolAddress('7', 1),
        peer.getPublicKey(),
        Direction.receiving,
      );

      expect(changed, isEmpty);
    });

    /// libsignal calls isTrustedIdentity on EVERY encrypt and EVERY decrypt.
    /// It used to write the peer key back each time; now the write is skipped
    /// when nothing changed.
    ///
    /// Falsifiable without a mocking framework: delete the row underneath the
    /// store, then present the SAME key again. An unconditional write would
    /// resurrect the row; the memoised compare must leave it deleted.
    test('the same key again is silent AND does not rewrite storage',
        () async {
      final changed = <String>[];
      final store = SecureIdentityKeyStore(
        storage,
        'same_',
        onIdentityChanged: (a) => changed.add(a.getName()),
      );
      final peer = generateIdentityKeyPair();
      final address = SignalProtocolAddress('7', 1);
      const rowKey = 'same_trusted_identity_7_1';

      await store.isTrustedIdentity(
        address,
        peer.getPublicKey(),
        Direction.receiving,
      );
      expect(await secure.read(key: rowKey), isNotNull);

      await secure.delete(key: rowKey);
      final trusted = await store.isTrustedIdentity(
        address,
        peer.getPublicKey(),
        Direction.sending,
      );

      expect(trusted, isTrue);
      expect(changed, isEmpty, reason: 'nothing changed, so no warning');
      expect(
        await secure.read(key: rowKey),
        isNull,
        reason:
            'an unchanged key must not be written back on every message; '
            'a resurrected row here means the write is unconditional again',
      );
    });

    /// A peer key changing is either a reinstall or a server swapping the
    /// bundle. The second is indistinguishable from a machine-in-the-middle,
    /// so it must never pass silently again.
    test('a changed key still trusts but reports the change', () async {
      final changed = <String>[];
      final store = SecureIdentityKeyStore(
        storage,
        'rotate_',
        onIdentityChanged: (a) => changed.add(a.getName()),
      );
      final address = SignalProtocolAddress('42', 1);
      final original = generateIdentityKeyPair();
      final replacement = generateIdentityKeyPair();

      await store.isTrustedIdentity(
        address,
        original.getPublicKey(),
        Direction.receiving,
      );
      final trusted = await store.isTrustedIdentity(
        address,
        replacement.getPublicKey(),
        Direction.receiving,
      );

      expect(trusted, isTrue, reason: 'TOFU still accepts, messages keep flowing');
      expect(changed, ['42'], reason: 'but the user gets told exactly once');
      expect(
        (await store.getIdentity(address))!.serialize(),
        replacement.getPublicKey().serialize(),
        reason: 'the rotated key is persisted',
      );
    });
  });
}
