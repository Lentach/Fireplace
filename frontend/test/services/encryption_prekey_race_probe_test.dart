import 'dart:convert';

import 'package:fireplace/services/encryption_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One-time pre-key generation is a read-modify-write of `next_pre_key_id`,
/// and same-origin PWA engines share that counter through storage while each
/// keeps its own Dart heap.
///
/// Two engines both handling `preKeysLow` could therefore both read `next=20`,
/// both mint ids 20..119 with DIFFERENT private halves, and both upload. The
/// last local write wins, so the server ends up serving a public pre-key whose
/// private half this device overwrote — and the peer who draws it gets a
/// bad-MAC session no retry can fix.
///
/// Same shape as the `_sessionTails` lost update, same remedy: an origin-wide
/// lock. These tests pin that the lock is taken, and that it actually prevents
/// the id collision.
class _InMemoryCrossContextLock {
  final Map<String, Future<void>> _tails = {};
  final Map<String, int> acquisitions = {};

  Future<T> run<T>(String name, Future<T> Function() action) {
    final tail = _tails[name] ?? Future<void>.value();
    final result = tail.then((_) {
      acquisitions.update(name, (count) => count + 1, ifAbsent: () => 1);
      return action();
    });
    _tails[name] = result.then<void>((_) {}, onError: (_) {});
    return result;
  }
}

/// A lock that records but does NOT serialize — models the pre-fix behaviour
/// so the collision the real lock prevents is observable.
Future<T> _unserialized<T>(String name, Future<T> Function() action) => action();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const uid = 42;
  const secure = FlutterSecureStorage();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  Set<int> idsOf(List<Map<String, dynamic>> keys) =>
      keys.map((k) => k['keyId'] as int).toSet();

  test('pre-key generation is taken under its own origin-wide lock', () async {
    final lock = _InMemoryCrossContextLock();
    final svc = EncryptionService(sessionCrossContextLock: lock.run);
    await svc.initialize(uid, checkServerBundleExists: () async => false);

    await svc.generateMorePreKeys();

    expect(
      lock.acquisitions['fireplace-e2e-prekeys-$uid'],
      1,
      reason: 'the read-modify-write of next_pre_key_id must be serialized',
    );
    expect(
      lock.acquisitions.keys.any((n) => n.startsWith('fireplace-e2e-session-')),
      isFalse,
      reason:
          'it touches no SessionRecord; reusing the session lock would '
          'serialize pre-key generation against unrelated conversations',
    );
  });

  test('two engines sharing the lock never mint overlapping pre-key ids',
      () async {
    final lock = _InMemoryCrossContextLock();
    final engineA = EncryptionService(sessionCrossContextLock: lock.run);
    final engineB = EncryptionService(sessionCrossContextLock: lock.run);
    await engineA.initialize(uid, checkServerBundleExists: () async => false);
    // Second engine, same account, same persisted storage — a second PWA tab.
    await engineB.initialize(uid, checkServerBundleExists: () async => false);

    final results = await Future.wait([
      engineA.generateMorePreKeys(),
      engineB.generateMorePreKeys(),
    ]);

    final first = idsOf(results[0]);
    final second = idsOf(results[1]);
    expect(first, isNotEmpty);
    expect(second, isNotEmpty);
    expect(
      first.intersection(second),
      isEmpty,
      reason:
          'an id minted twice means one private half overwrote the other '
          'while both public halves sit on the server',
    );

    // Every id this device claims to own must still have its private half in
    // storage under exactly that id.
    for (final id in {...first, ...second}) {
      expect(
        await secure.read(key: 'e2e_${uid}_pre_key_$id'),
        isNotNull,
        reason: 'uploaded pre-key $id has no stored private half',
      );
    }
  });

  test('FALSIFICATION: without serialization the two engines collide',
      () async {
    final engineA = EncryptionService(sessionCrossContextLock: _unserialized);
    final engineB = EncryptionService(sessionCrossContextLock: _unserialized);
    await engineA.initialize(uid, checkServerBundleExists: () async => false);
    await engineB.initialize(uid, checkServerBundleExists: () async => false);

    final results = await Future.wait([
      engineA.generateMorePreKeys(),
      engineB.generateMorePreKeys(),
    ]);

    expect(
      idsOf(results[0]).intersection(idsOf(results[1])),
      isNotEmpty,
      reason:
          'this is the bug the lock prevents — if this ever comes back empty '
          'the two-engine test above has stopped proving anything',
    );
  });

  test('the counter advances once per batch, not once per engine', () async {
    final lock = _InMemoryCrossContextLock();
    final engineA = EncryptionService(sessionCrossContextLock: lock.run);
    final engineB = EncryptionService(sessionCrossContextLock: lock.run);
    await engineA.initialize(uid, checkServerBundleExists: () async => false);
    await engineB.initialize(uid, checkServerBundleExists: () async => false);

    final before = int.parse(
      (await secure.read(key: 'e2e_${uid}_next_pre_key_id'))!,
    );
    final results = await Future.wait([
      engineA.generateMorePreKeys(),
      engineB.generateMorePreKeys(),
    ]);
    final after = int.parse(
      (await secure.read(key: 'e2e_${uid}_next_pre_key_id'))!,
    );

    final minted = results[0].length + results[1].length;
    expect(
      after - before,
      minted,
      reason: 'a lost update would advance the counter by only one batch',
    );
  });

  test('uploaded pre-keys carry a public half and no private material',
      () async {
    final lock = _InMemoryCrossContextLock();
    final svc = EncryptionService(sessionCrossContextLock: lock.run);
    await svc.initialize(uid, checkServerBundleExists: () async => false);

    final keys = await svc.generateMorePreKeys();

    expect(keys, isNotEmpty);
    for (final key in keys) {
      expect(key.keys.toSet(), {'keyId', 'publicKey'});
      expect(() => base64Decode(key['publicKey'] as String), returnsNormally);
    }
  });
}
