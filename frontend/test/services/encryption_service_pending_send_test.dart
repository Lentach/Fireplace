import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fireplace/services/encryption_service.dart';

/// Store contract for the lost-`messageSent`-ack reconcile record
/// (`savePendingSendRecord` / `peekPendingSendRecord` / `takePendingSendRecord`).
///
/// The record is the sender's ONLY surviving plaintext copy after a socket
/// drop eats the ack, so the store guarantees that matter are: EXACT ciphertext
/// keying (a wrong match persists the wrong plaintext under a real id forever),
/// non-consuming peek vs consuming take, TTL + cap pruning, per-user isolation,
/// wipe-on-clear (plaintext at rest), and total tolerance of corrupt bytes.
///
/// Real [EncryptionService] over the standard mocked storage (see
/// encryption_service_content_cache_test.dart / encryption_send_race_probe_test.dart).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EncryptionService pending-send reconcile store', () {
    const uid = 42;
    // ONE SharedPreferences key per ciphertext: `e2e_<uid>_pendsend_v1_<cipher>`.
    const pendPrefix = 'e2e_${uid}_pendsend_v1_';

    late EncryptionService service;

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      service = EncryptionService();
      await service.initialize(uid, checkServerIdentity: () async => const ServerIdentityGuard(exists: false));
    });

    // Contract 1: save persists, peek returns the exact payload and does NOT
    // consume — the reconcile peeks (never take-first) because a failed persist
    // must leave the record for the next history pass.
    test('save then peek returns the exact data and peek does not consume',
        () async {
      await service.savePendingSendRecord('2:ct-abc', {
        'content': 'hello world',
        'messageType': 'TEXT',
      });

      final first = await service.peekPendingSendRecord('2:ct-abc');
      expect(first, isNotNull);
      expect(first!['content'], 'hello world');
      expect(first['messageType'], 'TEXT');

      // Second peek still returns it — peek is non-destructive.
      final second = await service.peekPendingSendRecord('2:ct-abc');
      expect(second, isNotNull);
      expect(second!['content'], 'hello world');
    });

    // Contract 2: take returns the payload once and removes it; a normal ack
    // consumes via take so the store stays self-cleaning and a stale record can
    // never be applied twice.
    test('take returns data then consumes (second take null, peek after null)',
        () async {
      await service.savePendingSendRecord('2:ct-take', {'content': 'once'});

      final taken = await service.takePendingSendRecord('2:ct-take');
      expect(taken, isNotNull);
      expect(taken!['content'], 'once');

      expect(await service.takePendingSendRecord('2:ct-take'), isNull);
      expect(await service.peekPendingSendRecord('2:ct-take'), isNull);
    });

    // Contract 3: EXACT ciphertext match only. Ciphertext is unique by ratchet
    // construction; any near miss MUST NOT resolve, or reconcile would persist
    // the wrong plaintext under a real id permanently.
    test('exact match only: any near-miss ciphertext resolves to null',
        () async {
      const key = '2:abcdef';
      await service.savePendingSendRecord(key, {'content': 'guarded'});

      // name -> a ciphertext that is NOT exactly `key`.
      const nearMisses = <String, String>{
        'one char flipped': '2:abcdeg',
        'truncated (prefix)': '2:abcde',
        'extra char (suffix)': '2:abcdef0',
        'case differs': '2:ABCDEF',
        'type prefix differs': '3:abcdef',
        'empty': '',
      };
      for (final entry in nearMisses.entries) {
        expect(await service.peekPendingSendRecord(entry.value), isNull,
            reason: 'peek must reject ${entry.key} ("${entry.value}")');
        expect(await service.takePendingSendRecord(entry.value), isNull,
            reason: 'take must reject ${entry.key} ("${entry.value}")');
      }

      // The exact key is untouched by all the near-miss lookups.
      final exact = await service.peekPendingSendRecord(key);
      expect(exact!['content'], 'guarded');
    });

    // Contract 4: TTL. A record older than 72h is pruned by the next save.
    // Seed the crafted stale entry directly so the age is deterministic.
    test('TTL: an entry older than 72h is pruned on the next save', () async {
      final prefs = await SharedPreferences.getInstance();
      final staleAt = DateTime.now()
              .subtract(const Duration(hours: 73))
              .millisecondsSinceEpoch;
      await prefs.setString(
        '${pendPrefix}2:stale',
        jsonEncode({'at': staleAt, 'data': {'content': 'expired'}}),
      );
      // Present before any save prunes it.
      expect(await service.peekPendingSendRecord('2:stale'), isNotNull);

      // Any save runs the TTL sweep.
      await service.savePendingSendRecord('2:fresh', {'content': 'kept'});

      expect(await service.peekPendingSendRecord('2:stale'), isNull,
          reason: '73h-old record is past the 72h TTL and must be swept');
      expect((await service.peekPendingSendRecord('2:fresh'))!['content'],
          'kept');
    });

    // Contract 5: cap 40, oldest-out. Seed 40 records with strictly increasing
    // timestamps, then one more via save: the single oldest is evicted, leaving
    // exactly the newest 40.
    test('cap: the 41st live record evicts the single oldest, leaving 40',
        () async {
      final prefs = await SharedPreferences.getInstance();
      // Base an hour ago (well within TTL); 1s apart so ordering is total.
      final base =
          DateTime.now().subtract(const Duration(hours: 1)).millisecondsSinceEpoch;
      for (var i = 0; i < 40; i++) {
        await prefs.setString(
          '${pendPrefix}c-old-$i',
          jsonEncode({'at': base + i * 1000, 'data': {'content': 'old-$i'}}),
        );
      }

      // The newest record — its `at` is DateTime.now(), the largest of all 41.
      await service.savePendingSendRecord('c-new', {'content': 'newest'});

      // Exactly the single oldest (base) was evicted.
      expect(await service.peekPendingSendRecord('c-old-0'), isNull,
          reason: 'oldest of 41 must be evicted at cap 40');
      expect((await service.peekPendingSendRecord('c-old-1'))!['content'],
          'old-1');
      expect((await service.peekPendingSendRecord('c-old-39'))!['content'],
          'old-39');
      expect((await service.peekPendingSendRecord('c-new'))!['content'],
          'newest');

      final liveCount =
          prefs.getKeys().where((k) => k.startsWith(pendPrefix)).length;
      expect(liveCount, 40, reason: 'cap must hold the store at 40 records');
    });

    // Contract 6: per-user isolation. Records are keyed under the current user's
    // prefix; another user cannot see (or consume) them.
    test('records saved as user A are invisible to user B', () async {
      await service.savePendingSendRecord('2:userA', {'content': 'A only'});

      final other = EncryptionService();
      await other.initialize(99, checkServerIdentity: () async => const ServerIdentityGuard(exists: false));
      expect(await other.peekPendingSendRecord('2:userA'), isNull);
      expect(await other.takePendingSendRecord('2:userA'), isNull);

      // User A's record is intact after user B's lookups.
      expect((await service.peekPendingSendRecord('2:userA'))!['content'],
          'A only');
    });

    // Contract 7a: clearAllKeys (account deletion) wipes pending records —
    // plaintext at rest must not survive. Re-initialize the SAME service (so the
    // store is NOT reset by the mock) to prove the keys were actually removed.
    test('clearAllKeys wipes pending-send records', () async {
      await service.savePendingSendRecord('2:c1', {'content': 'one'});
      await service.savePendingSendRecord('2:c2', {'content': 'two'});

      await service.clearAllKeys();
      await service.initialize(uid, checkServerIdentity: () async => const ServerIdentityGuard(exists: false));

      expect(await service.peekPendingSendRecord('2:c1'), isNull);
      expect(await service.peekPendingSendRecord('2:c2'), isNull);
    });

    // Contract 7b: clearDecryptedContentCache ("clear local message cache")
    // also wipes pending records — same plaintext-at-rest privacy scope. It
    // keeps the user id, so peek directly proves removal.
    test('clearDecryptedContentCache wipes pending-send records', () async {
      await service.savePendingSendRecord('2:c3', {'content': 'three'});
      expect(await service.peekPendingSendRecord('2:c3'), isNotNull);

      final result = await service.clearDecryptedContentCache();
      expect(result.removed, 1);
      expect(result.isComplete, isTrue);

      expect(await service.peekPendingSendRecord('2:c3'), isNull);
    });

    // Contract 8: corrupt stored bytes never throw — peek/take return null.
    // Malformed persisted state must degrade to "no record", never crash the
    // history decrypt pass.
    test('corrupt stored value: peek and take return null without throwing',
        () async {
      final prefs = await SharedPreferences.getInstance();
      // name -> raw stored string that is not a well-formed record.
      const corrupt = <String, String>{
        '2:bad-json': 'not-valid-json{',
        '2:not-a-map': '"just a string"',
        '2:missing-data': '{"at":123}',
        '2:data-not-map': '{"at":123,"data":"oops"}',
      };
      for (final entry in corrupt.entries) {
        await prefs.setString('$pendPrefix${entry.key}', entry.value);
      }

      for (final cipher in corrupt.keys) {
        expect(await service.peekPendingSendRecord(cipher), isNull,
            reason: 'peek must null-out corrupt record "$cipher"');
      }
      for (final cipher in corrupt.keys) {
        expect(await service.takePendingSendRecord(cipher), isNull,
            reason: 'take must null-out corrupt record "$cipher"');
      }
    });
  });
}
