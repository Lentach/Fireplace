import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:fireplace/services/encryption_service.dart';

/// A preferences store that accepts writes but can be told to REFUSE removals,
/// reproducing the quota / backend-failure path where `prefs.remove` returns
/// false rather than throwing.
///
/// This exists because it is the only way to exercise the guarantee the whole
/// purge rests on: an operation that could not destroy plaintext must report
/// failure, never success. `SharedPreferences.setMockInitialValues` installs a
/// store whose removals always succeed, so without this the honesty path is
/// untestable — and an untestable guarantee rots silently, which is exactly the
/// class of bug this change exists to remove.
class _RefusingStore extends SharedPreferencesStorePlatform {
  _RefusingStore() : _inner = InMemorySharedPreferencesStore.empty();

  final InMemorySharedPreferencesStore _inner;

  /// While true, every [remove] reports a failed commit AND keeps the value —
  /// so assertions can check that the reported failure is truthful.
  bool refuseRemove = false;

  @override
  Future<bool> remove(String key) async {
    if (refuseRemove) return false;
    return _inner.remove(key);
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) =>
      _inner.setValue(valueType, key, value);

  @override
  Future<bool> clear() => _inner.clear();

  @override
  Future<bool> clearWithPrefix(String prefix) => _inner.clearWithPrefix(prefix);

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) =>
      _inner.clearWithParameters(parameters);

  @override
  Future<Map<String, Object>> getAll() => _inner.getAll();

  @override
  Future<Map<String, Object>> getAllWithPrefix(String prefix) =>
      _inner.getAllWithPrefix(prefix);

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) => _inner.getAllWithParameters(parameters);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('plaintext purge honesty when the store refuses a commit', () {
    late _RefusingStore store;
    late EncryptionService service;

    setUp(() async {
      store = _RefusingStore();
      // Install BEFORE the first getInstance, and reset the cached singleton —
      // it survives between tests and would otherwise pin another store.
      SharedPreferencesStorePlatform.instance = store;
      SharedPreferences.resetStatic();
      FlutterSecureStorage.setMockInitialValues({});
      service = EncryptionService();
      await service.initialize(77);
    });

    test('removeDecryptedContent reports failure rather than success', () async {
      await service.saveDecryptedContent(1, {'content': 'secret'});
      store.refuseRemove = true;

      final result = await service.removeDecryptedContent([1]);

      expect(
        result.isComplete,
        isFalse,
        reason: 'a refused commit must never be reported as a completed purge',
      );
      expect(result.failedIds, contains(1));

      // The report is truthful about the DURABLE store, which is what matters.
      //
      // Note the subtlety this pins down: `SharedPreferences.remove` drops its
      // in-memory cache entry even when the backend refuses the commit, so
      // within this session the row already reads as gone while the bytes are
      // still on disk — a later launch re-reads them and they reappear. That
      // gap is exactly why the retry has to come from a durable backlog and
      // cannot rely on the in-session view of the store.
      expect(
        (await store.getAll()).keys,
        contains('flutter.e2e_77_decrypted_1'),
        reason: 'the refused removal must have left the plaintext on disk',
      );
    });

    test('a refused purge leaves the backlog so it is retried', () async {
      await service.saveDecryptedContent(2, {'content': 'secret'});
      await service.enqueuePurge([2], const <String>[]);
      store.refuseRemove = true;

      expect((await service.removeDecryptedContent([2])).isComplete, isFalse);

      // Nothing resolved it, so the obligation survives to be retried.
      expect((await service.purgeBacklog()).ids, contains(2));

      // Once the store accepts removals again the retry completes, and only
      // then does the backlog entry clear.
      store.refuseRemove = false;
      expect((await service.removeDecryptedContent([2])).isComplete, isTrue);
      await service.resolvePurged([2], const <String>[]);
      expect((await service.purgeBacklog()).ids, isEmpty);
    });

    test('clearDecryptedContentCache names what it could not wipe', () async {
      await service.saveDecryptedContent(3, {'content': 'secret'});
      store.refuseRemove = true;

      final result = await service.clearDecryptedContentCache();

      expect(
        result.isComplete,
        isFalse,
        reason: 'the wipe action must not claim success while residue remains',
      );
      expect(result.failedKeys, isNotEmpty);
      expect(result.removed, 0);
      expect(
        (await store.getAll()).keys,
        contains('flutter.e2e_77_decrypted_3'),
      );
    });

    test('a store that accepts removals reports a complete purge', () async {
      // Guards against the fake making every assertion above vacuous: with
      // removals allowed, the same calls must succeed.
      await service.saveDecryptedContent(4, {'content': 'secret'});

      final result = await service.removeDecryptedContent([4]);

      expect(result.isComplete, isTrue);
      expect(result.removed, 1);
      expect(await service.getDecryptedContent(4), isNull);
    });
  });
}
