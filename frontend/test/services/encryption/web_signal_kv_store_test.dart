import 'package:fireplace/services/encryption/signal_stores.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory [AsyncKv] (models cache-free localStorage via SharedPreferencesAsync).
class FakeAsyncKv implements AsyncKv {
  final Map<String, Object?> store;
  bool failNextSet = false;
  FakeAsyncKv([Map<String, Object?>? initial]) : store = {...?initial};

  @override
  Future<String?> getString(String key) async => store[key] as String?;

  @override
  Future<void> setString(String key, String value) async {
    if (failNextSet) {
      failNextSet = false;
      throw Exception('QuotaExceededError');
    }
    store[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    store.remove(key);
  }

  @override
  Future<Map<String, Object?>> getAll() async =>
      Map<String, Object?>.from(store);
}

/// In-memory [LegacyKv] (models the cached legacy SharedPreferences).
class FakeLegacyKv implements LegacyKv {
  final Map<String, String> store;
  int reloadCount = 0;
  bool failRemove = false;
  FakeLegacyKv([Map<String, String>? initial]) : store = {...?initial};

  @override
  Future<void> reload() async => reloadCount++;

  @override
  Iterable<String> keys() => store.keys.toList();

  @override
  String? getString(String key) => store[key];

  @override
  Future<void> remove(String key) async {
    if (failRemove) throw Exception('remove failed');
    store.remove(key);
  }
}

WebSignalKvStore makeStore(FakeAsyncKv async, FakeLegacyKv legacy) =>
    WebSignalKvStore(async, () async => legacy, 'sig_');

void main() {
  group('WebSignalKvStore', () {
    test(
      'fresh user: no legacy keys → drained immediately, reads never reload',
      () async {
        final async = FakeAsyncKv();
        final legacy = FakeLegacyKv();
        final store = makeStore(async, legacy);

        expect(await store.read('x'), isNull);
        expect(store.legacyDrained, isTrue);
        expect(
          legacy.reloadCount,
          1,
          reason: 'only the one-time migration reloads',
        );

        await store.read('y');
        expect(
          legacy.reloadCount,
          1,
          reason: 'once drained, a negative lookup must not reload legacy',
        );
      },
    );

    test(
      'migration drains legacy sig_ keys into async and removes them',
      () async {
        final async = FakeAsyncKv();
        final legacy = FakeLegacyKv({
          'sig_a': '1',
          'sig_b': '2',
          'other': 'keep',
        });
        final store = makeStore(async, legacy);

        expect(await store.read('a'), '1');
        expect(await store.read('b'), '2');
        expect(store.legacyDrained, isTrue);
        expect(async.store['sig_a'], '1');
        expect(async.store['sig_b'], '2');
        expect(legacy.store.containsKey('sig_a'), isFalse);
        expect(legacy.store.containsKey('sig_b'), isFalse);
        expect(
          legacy.store['other'],
          'keep',
          reason: 'non-sig_ keys untouched',
        );
        expect(legacy.reloadCount, 1, reason: 'reads hit async, not legacy');
      },
    );

    test('migration never clobbers a newer async value', () async {
      final async = FakeAsyncKv({'sig_a': 'NEW'});
      final legacy = FakeLegacyKv({'sig_a': 'OLD'});
      final store = makeStore(async, legacy);

      expect(await store.read('a'), 'NEW');
      expect(async.store['sig_a'], 'NEW');
      expect(legacy.store.containsKey('sig_a'), isFalse);
      expect(store.legacyDrained, isTrue);
    });

    test(
      'quota failure during migration: value still readable, no throw, not drained',
      () async {
        final async = FakeAsyncKv()..failNextSet = true;
        final legacy = FakeLegacyKv({'sig_a': '1'});
        final store = makeStore(async, legacy);

        expect(
          await store.read('a'),
          '1',
          reason: 'served from the legacy fallback when async write fails',
        );
        expect(async.store.containsKey('sig_a'), isFalse);
        expect(legacy.store['sig_a'], '1', reason: 'legacy copy retained');
        expect(store.legacyDrained, isFalse);
        expect(await store.read('a'), '1', reason: 'still readable on retry');
      },
    );

    test(
      'delete clears async AND a surviving legacy copy — no resurrection',
      () async {
        final async = FakeAsyncKv()..failNextSet = true;
        final legacy = FakeLegacyKv({'sig_a': '1'});
        final store = makeStore(async, legacy);

        await store.delete('a');
        expect(async.store.containsKey('sig_a'), isFalse);
        expect(legacy.store.containsKey('sig_a'), isFalse);
        expect(await store.read('a'), isNull, reason: 'must not resurrect');
      },
    );

    test(
      'write makes async authoritative even if a legacy copy survived',
      () async {
        final async = FakeAsyncKv()
          ..failNextSet = true; // migration fails to move 'old'
        final legacy = FakeLegacyKv({'sig_a': 'old'});
        final store = makeStore(async, legacy);

        await store.write('a', 'new');
        expect(
          await store.read('a'),
          'new',
          reason: 'async preferred over legacy',
        );
        expect(async.store['sig_a'], 'new');
        expect(store.legacyDrained, isFalse);
      },
    );

    test('readAll merges async-only and legacy-only keys', () async {
      final async = FakeAsyncKv()..failNextSet = true; // sig_a fails to migrate
      final legacy = FakeLegacyKv({'sig_a': 'LA', 'sig_b': 'LB'});
      final store = makeStore(async, legacy);

      await store.read(
        'a',
      ); // trigger migration: sig_a stays legacy, sig_b moves
      final all = await store.readAll();
      expect(all, {'a': 'LA', 'b': 'LB'});
    });

    test(
      'readAll prefers the async value over legacy on a key conflict',
      () async {
        final async = FakeAsyncKv({'sig_k': 'ASYNC'});
        final legacy = FakeLegacyKv({'sig_k': 'LEGACY'})..failRemove = true;
        final store = makeStore(async, legacy);

        final all = await store.readAll();
        expect(all['k'], 'ASYNC');
        expect(
          store.legacyDrained,
          isFalse,
          reason: 'legacy.remove failed, so the fallback stays armed',
        );
      },
    );

    test(
      'multi-tab: stores sharing one async backend see each other\'s writes',
      () async {
        final shared = FakeAsyncKv();
        final storeA = WebSignalKvStore(
          shared,
          () async => FakeLegacyKv(),
          'sig_',
        );
        final storeB = WebSignalKvStore(
          shared,
          () async => FakeLegacyKv(),
          'sig_',
        );

        await storeA.write('k', 'v1');
        expect(await storeB.read('k'), 'v1');
        await storeA.write('k', 'v2');
        expect(
          await storeB.read('k'),
          'v2',
          reason: 'cache-free async = fresh reads',
        );
      },
    );
  });
}
