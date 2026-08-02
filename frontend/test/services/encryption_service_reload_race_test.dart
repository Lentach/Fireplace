import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:fireplace/models/message_model.dart';
import 'package:fireplace/services/encryption_service.dart';

/// Regression cover for the 2026-07-29 "[Decryption failed]" incident.
///
/// `SharedPreferences.reload()` reads the backing store, AWAITS that read, then
/// CLEARS its in-memory cache and refills it from the snapshot it took. A write
/// landing inside the await window survives in the store but is dropped from the
/// cache, so a cache-based read answers null for a record that is still there.
///
/// For a plaintext record that false miss is not "no plaintext": the caller
/// re-decrypts a ciphertext whose Signal ratchet key was consumed at first
/// decrypt, lands on DuplicateMessage, and the row becomes a permanent
/// "[Decryption failed]" while its only readable copy sits on disk.
///
/// The reload cannot be locked out — the Signal session stores reload the same
/// singleton throughout decrypt — so these readers must not depend on that cache.
///
/// [_HoldableStore] makes the window deterministic rather than timing-dependent.
/// That matters: the reload is kIsWeb-gated, so an unheld interleave on the Dart
/// VM proves nothing either way.
class _HoldableStore extends SharedPreferencesStorePlatform {
  _HoldableStore() : _inner = InMemorySharedPreferencesStore.empty();

  final InMemorySharedPreferencesStore _inner;
  Completer<void>? _armed;
  Completer<void>? _parkedAt;
  Completer<void>? _parkedSignal;

  /// Make the NEXT [getAll] take its snapshot and then block until [release] —
  /// precisely `reload()`'s await window.
  void holdNextGetAll() {
    _armed = Completer<void>();
    _parkedSignal = Completer<void>();
  }

  /// Completes once a [getAll] has actually parked, so the test can be sure the
  /// reload — and not some later reader — consumed the hold.
  Future<void> get parked => _parkedSignal!.future;

  /// Lets the parked [getAll] finish. Must target the completer that is
  /// actually parked: the armed slot is cleared on entry so later reads run
  /// free, and completing that cleared slot would leave the reload hung.
  void release() => _parkedAt?.complete();

  @override
  Future<Map<String, Object>> getAll() async {
    final snapshot = await _inner.getAll();
    final hold = _armed;
    if (hold != null) {
      _armed = null; // one-shot, so later reads run free
      _parkedAt = hold;
      _parkedSignal?.complete();
      await hold.future;
    }
    return snapshot;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) =>
      _inner.setValue(valueType, key, value);

  @override
  Future<bool> remove(String key) => _inner.remove(key);

  @override
  Future<bool> clear() => _inner.clear();

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

  late _HoldableStore store;
  late EncryptionService service;
  late SharedPreferences prefs;

  setUp(() async {
    store = _HoldableStore();
    // `flutter test` runs on the Dart VM, where kIsWeb is false and the reads
    // deliberately stay on the cache. Force the web branch, or this whole suite
    // would exercise the path it exists to prove broken.
    EncryptionService.debugForceAuthoritativeReads = true;
    addTearDown(
      () => EncryptionService.debugForceAuthoritativeReads = false,
    );
    SharedPreferencesStorePlatform.instance = store;
    SharedPreferences.resetStatic();
    FlutterSecureStorage.setMockInitialValues({});
    service = EncryptionService();
    await service.initialize(37);
    prefs = await SharedPreferences.getInstance();
  });

  /// Persists [id] and then drops it from the reload cache while leaving it in
  /// the backing store — the exact state the incident left inbound records in.
  Future<void> loseFromCache(
    int id,
    Map<String, dynamic> data, {
    int? conversationId,
  }) async {
    store.holdNextGetAll();
    final reload = prefs.reload(); // snapshots WITHOUT [id], then parks
    await store.parked;
    // Lands in store and cache.
    await service.saveDecryptedContent(
      id,
      data,
      conversationId: conversationId,
    );
    store.release();
    await reload; // clears the cache, refills from the stale snapshot
  }

  test('the hardcoded store prefix matches the package namespace', () async {
    await prefs.setString('probe_key', 'v');

    expect(
      (await store.getAll()).keys,
      contains('${EncryptionService.prefsStorePrefix}probe_key'),
      reason: 'every record read would silently answer null',
    );
  });

  test('a record dropped from the reload cache is still readable', () async {
    await loseFromCache(18597, {'content': 'hello'});

    expect(
      prefs.getString('e2e_37_decrypted_18597'),
      isNull,
      reason: 'precondition: the cache must really have lost it',
    );
    expect((await service.getDecryptedContent(18597))?['content'], 'hello');
  });

  test('the batched history read sees a record the cache lost', () async {
    await loseFromCache(18624, {'content': 'world'});

    final found = await service.getDecryptedContentMany([18624]);

    expect(
      found[18624]?['content'],
      'world',
      reason: 'a missed id is re-decrypted into a permanent failure',
    );
  });

  test('a full local wipe retires what it destroyed', () async {
    await service.saveDecryptedContent(18700, {'content': 'wiped'});
    await service.saveDecryptedContent(18701, {'content': 'also wiped'});

    final result = await service.clearDecryptedContentCache();
    expect(result.isComplete, isTrue, reason: 'precondition: the wipe landed');

    // Without this the server keeps serving those rows, hydration finds no
    // record, the re-decrypt hits a consumed ratchet key, and the user's WHOLE
    // history renders a permanent "[Decryption failed]" — a deliberate action
    // that looks exactly like catastrophic corruption. Retention and LRU
    // eviction already retire for the same reason.
    final retired = await service.retiredMessageIds();
    expect(retired, containsAll(<int>[18700, 18701]));
  });

  test('a user-requested delete still finds a record the cache lost', () async {
    await loseFromCache(18611, {'content': 'scanned'}, conversationId: 71);

    expect(
      await service.messageIdsForConversations([71]),
      contains(18611),
      reason: 'the user asked for it: a miss leaves readable history behind',
    );
  });

  test('reconcile enumeration stays suppressed when the cache lost a record', () async {
    await loseFromCache(18612, {'content': 'not enumerated'});

    // DELIBERATE, not an oversight. storedMessageIds is the sole input to server
    // reconciliation, which destroys every id the server does not return — and
    // expired rows ARE hard-deleted server-side, so orphans exist. Going
    // authoritative here would destroy every orphan at once on the first launch
    // after this change. Over-retention is recoverable; over-destruction is not.
    expect(await service.storedMessageIds(), isNot(contains(18612)));
  });

  test('the failure label never replaces real plaintext', () async {
    await service.saveDecryptedContent(18598, {'content': 'real plaintext'});

    // Exactly what the terminal-failure path persists (decrypt.dart:1113).
    await service.saveDecryptedContent(18598, {
      'content': '[Decryption failed]',
    });

    expect(
      (await service.getDecryptedContent(18598))?['content'],
      'real plaintext',
      reason: 'hydration skips a labelled record, so this loss is permanent',
    );
  });

  test('a real later decrypt still replaces a placeholder record', () async {
    await service.saveDecryptedContent(18599, {
      'content': '[Decryption failed]',
    });

    await service.saveDecryptedContent(18599, {'content': 'recovered'});

    expect(
      (await service.getDecryptedContent(18599))?['content'],
      'recovered',
      reason: 'the guard must not freeze a row on a placeholder',
    );
  });

  test('placeholder set matches what MessageModel treats as unreal', () {
    for (final label in EncryptionService.placeholderContents) {
      final msg = MessageModel(
        id: 1,
        content: label,
        senderId: 43,
        senderUsername: 'peer',
        conversationId: 71,
        createdAt: DateTime.utc(2026, 7, 29),
      );
      expect(
        msg.hasCopyablePlaintext,
        isFalse,
        reason: '$label drifted from the model placeholder set',
      );
    }
  });

  /// Pins the platform gate as deliberate, so nobody deletes it as dead code.
  ///
  /// Off web nothing ever reloads (`_reloadPrefsForCrossContext` is kIsWeb-gated),
  /// so the cache cannot be clobbered and reads stay on it — a platform
  /// `getAll()` per read and per save would be the most expensive call in the
  /// file.
  test('off web, reads stay on the cache', () async {
    EncryptionService.debugForceAuthoritativeReads = false;

    await service.saveDecryptedContent(19000, {'content': 'mobile'});

    // Served from the in-memory cache, with no store round trip.
    expect((await service.getDecryptedContent(19000))?['content'], 'mobile');
    expect(prefs.getString('e2e_37_decrypted_19000'), isNotNull);
  });
}
