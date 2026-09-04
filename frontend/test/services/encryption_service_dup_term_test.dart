import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:fireplace/services/encryption/content_kv.dart';
import 'package:fireplace/services/encryption_service.dart';

/// The terminal-duplicate observation counter
/// (docs/design/terminal-duplicate-retirement.md §3.3).
///
/// The counter is the evidence a destruction-adjacent rule acts on, so every
/// failure direction here must point at "count less, retire slower": an
/// unbound user, a refused commit, a malformed record, and a cap eviction all
/// restore the status quo (retry forever), never a phantom count.
class _RefusingStore extends SharedPreferencesStorePlatform {
  _RefusingStore() : _inner = InMemorySharedPreferencesStore.empty();

  final InMemorySharedPreferencesStore _inner;

  /// Keys matching this substring fail their commit, the way a
  /// quota-exhausted backend does — `setString` reports false, not a throw.
  String? refusePrefix;

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    final refuse = refusePrefix;
    if (refuse != null && key.contains(refuse)) return Future.value(false);
    return _inner.setValue(valueType, key, value);
  }

  @override
  Future<bool> clear() => _inner.clear();

  @override
  Future<Map<String, Object>> getAll() => _inner.getAll();

  @override
  Future<bool> remove(String key) => _inner.remove(key);

  @override
  Future<bool> clearWithPrefix(String prefix) => _inner.clearWithPrefix(prefix);

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) =>
      _inner.clearWithParameters(parameters);

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

  const uid = 37;
  const dupTermKey = 'e2e_${uid}_dupterm_v1';
  const msgId = 19102;

  late _RefusingStore store;
  late EncryptionService service;

  setUp(() async {
    store = _RefusingStore();
    PrefsContentKv.debugForceAuthoritative = true;
    addTearDown(() => PrefsContentKv.debugForceAuthoritative = false);
    SharedPreferencesStorePlatform.instance = store;
    SharedPreferences.resetStatic();
    FlutterSecureStorage.setMockInitialValues({});
    EncryptionService.debugDupTermBootNonce = 'boot-1';
    service = EncryptionService();
    await service.initialize(uid, checkServerIdentity: () async => const ServerIdentityGuard(exists: false));
  });

  test('same boot never counts twice — repeated chat entries are ONE '
      'observation', () async {
    expect(await service.noteTerminalDuplicate(msgId), 1);
    expect(await service.noteTerminalDuplicate(msgId), 1);
    expect(await service.noteTerminalDuplicate(msgId), 1);
  });

  test('distinct boots increment: 3 boots reach the retire threshold',
      () async {
    expect(await service.noteTerminalDuplicate(msgId), 1);
    EncryptionService.debugDupTermBootNonce = 'boot-2';
    expect(await service.noteTerminalDuplicate(msgId), 2);
    EncryptionService.debugDupTermBootNonce = 'boot-3';
    final n = await service.noteTerminalDuplicate(msgId);
    expect(n, EncryptionService.terminalDuplicateRetireSessions);
  });

  test('provider re-creation inside one process shares the nonce and still '
      'counts once (R1)', () async {
    // Simulates in-SPA logout→login: a NEW service instance, same process.
    expect(await service.noteTerminalDuplicate(msgId), 1);
    final second = EncryptionService();
    await second.initialize(uid, checkServerIdentity: () async => const ServerIdentityGuard(exists: false));
    expect(
      await second.noteTerminalDuplicate(msgId),
      1,
      reason: 'three in-process re-inits must not collapse "N distinct '
          'boots" into one wall-clock window',
    );
  });

  test('clear removes the entry; the next observation restarts from 1',
      () async {
    await service.noteTerminalDuplicate(msgId);
    EncryptionService.debugDupTermBootNonce = 'boot-2';
    await service.noteTerminalDuplicate(msgId);
    await service.clearTerminalDuplicate(msgId);
    EncryptionService.debugDupTermBootNonce = 'boot-3';
    expect(
      await service.noteTerminalDuplicate(msgId),
      1,
      reason: 'a readable source resets the clock; a later loss must '
          're-accumulate N boots from zero',
    );
  });

  test('cap 64 evicts the LOWEST ids; an evicted id restarts from zero',
      () async {
    for (var id = 1000; id < 1000 + 65; id++) {
      expect(await service.noteTerminalDuplicate(id), 1);
    }
    // 65 inserts against cap 64: id 1000 (lowest) must be gone.
    EncryptionService.debugDupTermBootNonce = 'boot-2';
    expect(
      await service.noteTerminalDuplicate(1000),
      1,
      reason: 'an evicted entry restores the status quo — never a phantom '
          'count carried past eviction',
    );
    expect(
      await service.noteTerminalDuplicate(1064),
      2,
      reason: 'the highest ids survive the cap',
    );
  });

  test('refused commit returns null and advances nothing — slower to '
      'retire, never faster', () async {
    store.refusePrefix = dupTermKey;
    expect(await service.noteTerminalDuplicate(msgId), isNull);
    store.refusePrefix = null;
    expect(
      await service.noteTerminalDuplicate(msgId),
      1,
      reason: 'the refused observation was LOST, not deferred',
    );
  });

  test('malformed stored record restarts the count instead of throwing',
      () async {
    SharedPreferencesStorePlatform.instance.setValue(
      'String',
      'flutter.$dupTermKey',
      '{"$msgId": "garbage", "19105": {"n": "NaN", "b": 7}}',
    );
    SharedPreferences.resetStatic();
    expect(await service.noteTerminalDuplicate(msgId), 1);
    expect(await service.noteTerminalDuplicate(19105), 1);
  });

  test('unbound user records nothing', () async {
    final unbound = EncryptionService();
    expect(await unbound.noteTerminalDuplicate(msgId), isNull);
  });
}
