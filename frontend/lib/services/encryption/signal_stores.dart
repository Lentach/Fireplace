import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/e2e_diag_log.dart';
import '../../utils/e2e_persistent_diag.dart';
import '../secure_kv.dart';
import 'content_key_manager.dart';
import 'content_sealer.dart';
import 'sealed_sig_envelope.dart';
import 'sealed_web_signal_kv.dart';
import 'session_cross_context_lock.dart';

/// The four async operations every web Signal key-value backend exposes.
/// [WebSignalKvStore] is the historical plaintext behavior; the sealed store
/// and its fallback guard wrap it (docs/design/web-sig-sealing.md §3.1).
abstract class SigWebKv {
  Future<void> write(String key, String value);
  Future<String?> read(String key);
  Future<void> delete(String key);
  Future<Map<String, String>> readAll();
}

/// Platform-aware key-value storage for Signal Protocol keys.
///
/// **Web:** Uses ONLY SharedPreferences (localStorage). flutter_secure_storage
/// on web uses IndexedDB+WebCrypto which loses data when browser tabs are closed
/// or the WebCrypto key is evicted. Uses SharedPreferencesAsync so Signal
/// session reads are not served from the legacy SharedPreferences in-memory
/// cache after another tab/client updates localStorage.
///
/// **Mobile:** Uses flutter_secure_storage (Keychain on iOS, Keystore on Android)
/// which is hardware-backed and reliable.
class DualStorage {
  final FlutterSecureStorage _secure;
  final SharedPreferencesAsync? _asyncPrefsOverride;
  SharedPreferencesAsync? _asyncPrefsInstance;
  SharedPreferences? _prefs;
  WebSignalKvStore? _web;
  Future<SigWebKv>? _webOpen;

  /// Test seams for the web sealing path; production leaves them null and
  /// [_openWeb] builds the real sealer/key manager over [_secure].
  final ContentSealer? _sigSealerOverride;
  final ContentKeyManager? _sigKeysOverride;
  final SessionCrossContextLockRunner? _sigLockOverride;
  final bool _debugForceSealedWeb;

  DualStorage(
    this._secure, {
    SharedPreferencesAsync? asyncPrefs,
    ContentSealer? sigSealer,
    ContentKeyManager? sigKeys,
    SessionCrossContextLockRunner? sigLock,
    @visibleForTesting bool debugForceSealedWeb = false,
  }) : _asyncPrefsOverride = asyncPrefs,
       _sigSealerOverride = sigSealer,
       _sigKeysOverride = sigKeys,
       _sigLockOverride = sigLock,
       _debugForceSealedWeb = debugForceSealedWeb;

  /// Lazily built so construction never touches the async platform plugin on
  /// non-web (mobile/tests, where `kIsWeb` is false and the plugin is not
  /// registered) — eager construction threw "SharedPreferencesAsyncPlatform
  /// instance must be set" and broke every unit test that builds the store.
  SharedPreferencesAsync get _asyncPrefs =>
      _asyncPrefsInstance ??= _asyncPrefsOverride ?? SharedPreferencesAsync();

  Future<SharedPreferences> get _sharedPrefs async =>
      _prefs ??= await SharedPreferences.getInstance();

  /// Prefix for Signal keys in SharedPreferences to avoid collisions
  /// with other SharedPreferences data (e.g. decrypted message cache).
  static const String _spPrefix = 'sig_';

  /// Web-only key-value layer (localStorage). Built lazily; never touched on
  /// mobile. The legacy store is supplied through a provider so it is loaded
  /// only when the web path actually runs.
  WebSignalKvStore get _webStore => _web ??= WebSignalKvStore(
    _SharedPrefsAsyncKv(_asyncPrefs),
    () async => _SharedPrefsLegacyKv(await _sharedPrefs),
    _spPrefix,
  );

  bool get _useWeb => kIsWeb || _debugForceSealedWeb;

  /// The web backend for this session, memoized AS A FUTURE (concurrent first
  /// ops cannot race two stores; a failed open keeps rethrowing on every op —
  /// E2E down this session, retried next boot; a fallen-back session stays on
  /// the guarded plaintext store; never a mid-session backend flip).
  Future<SigWebKv> get _webKv => _webOpen ??= _openWeb();

  Future<SigWebKv> _openWeb() async {
    final raw = _webStore;
    try {
      final keys =
          _sigKeysOverride ??
          ContentKeyManager(
            FlutterSecureStorageKv(_secure),
            keyPrefix: ContentKeyManager.sigKeyPrefix,
          );
      return await SealedWebSignalKv.open(
        inner: raw,
        keys: keys,
        sealer: _sigSealerOverride ?? AesGcmContentSealer(),
        lock: _sigLockOverride,
      );
    } on SigSealOpenUnavailable catch (e) {
      if (!e.fallbackLegal) {
        // Sealed rows exist (or their existence is unknowable): running a
        // plaintext store beside them is the rule-4 forbidden state, and an
        // absent-looking identity read could trigger regeneration. E2E stays
        // DOWN this session (docs/design/web-sig-sealing.md §3.4).
        E2ePersistentDiag.record('SIG_KEY_UNAVAILABLE', {'stage': e.stage});
        rethrow;
      }
      // Pre-first-seal world, proven by a successful zero-envelope probe:
      // plaintext is the status quo, loudly diagnosed, write-guarded against
      // a sibling engine sealing later.
      E2ePersistentDiag.record('SIG_STORE_FALLBACK', {'stage': e.stage});
      return FallbackWebSignalKv(raw);
    }
  }

  Future<void> write({required String key, required String value}) async {
    if (_useWeb) {
      await (await _webKv).write(key, value);
    } else {
      await _secure.write(key: key, value: value);
    }
  }

  Future<String?> read({required String key}) async {
    if (_useWeb) {
      return (await _webKv).read(key);
    } else {
      return _secure.read(key: key);
    }
  }

  Future<void> delete({required String key}) async {
    if (_useWeb) {
      await (await _webKv).delete(key);
    } else {
      await _secure.delete(key: key);
    }
  }

  Future<Map<String, String>> readAll() async {
    if (_useWeb) {
      return (await _webKv).readAll();
    } else {
      return _secure.readAll();
    }
  }

  void clearPrefsCache() {
    _prefs = null;
    _web = null;
    _webOpen = null;
  }
}

/// Cache-free async key-value backend (reads straight through to the platform
/// store). Abstracted so [WebSignalKvStore] is unit-testable without a browser
/// or `kIsWeb`. Production impl wraps `SharedPreferencesAsync`.
abstract class AsyncKv {
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);
  Future<void> remove(String key);
  Future<Map<String, Object?>> getAll();
}

/// Legacy (in-memory cached) key-value backend. `reload()` re-reads the backing
/// store before a read. Production impl wraps `SharedPreferences`.
abstract class LegacyKv {
  Future<void> reload();
  Iterable<String> keys();
  String? getString(String key);
  Future<void> remove(String key);
}

class _SharedPrefsAsyncKv implements AsyncKv {
  final SharedPreferencesAsync _p;
  _SharedPrefsAsyncKv(this._p);
  @override
  Future<String?> getString(String key) => _p.getString(key);
  @override
  Future<void> setString(String key, String value) => _p.setString(key, value);
  @override
  Future<void> remove(String key) => _p.remove(key);
  @override
  Future<Map<String, Object?>> getAll() => _p.getAll();
}

class _SharedPrefsLegacyKv implements LegacyKv {
  final SharedPreferences _p;
  _SharedPrefsLegacyKv(this._p);
  @override
  Future<void> reload() => _p.reload();
  @override
  Iterable<String> keys() => _p.getKeys();
  @override
  String? getString(String key) => _p.getString(key);
  @override
  Future<void> remove(String key) => _p.remove(key);
}

/// Web Signal key-value store backing [DualStorage] on `kIsWeb`.
///
/// `SharedPreferencesAsync` (cache-free localStorage) is the source of truth so
/// resumed/multi-tab clients always read the latest ratchet state. Keys written
/// by the legacy `SharedPreferences` API (a different localStorage namespace)
/// are drained into the async store by a **one-time, best-effort** migration on
/// first use:
///  - runs exactly once per instance ([_ensureMigrated] memoizes the future)
///    BEFORE any read/write proceeds, so it never races a concurrent write — no
///    lost update, no stale-session resurrection;
///  - per-key failures (e.g. localStorage quota) are swallowed and leave the
///    legacy copy intact, so a read can still fall back to it (no data loss, no
///    throw — a found key never becomes a decrypt failure);
///  - once every legacy `sig_` key is drained, [_legacyDrained] is set and
///    reads/deletes stop touching the legacy store, so steady-state negative
///    lookups never pay an O(n) `reload()`.
class WebSignalKvStore implements SigWebKv {
  final AsyncKv _async;
  final Future<LegacyKv> Function() _legacyProvider;
  final String _prefix;

  Future<void>? _migration;
  bool _legacyDrained = false;

  WebSignalKvStore(this._async, this._legacyProvider, this._prefix);

  /// Visible for testing: true once no legacy `sig_` keys remain as a fallback.
  bool get legacyDrained => _legacyDrained;

  Future<void> _ensureMigrated() => _migration ??= _migrate();

  Future<void> _migrate() async {
    try {
      final legacy = await _legacyProvider();
      await legacy.reload();
      final keys = legacy.keys().where((k) => k.startsWith(_prefix)).toList();
      var allDrained = true;
      for (final key in keys) {
        final value = legacy.getString(key);
        try {
          // Move into async only if async has no value — never clobber a newer
          // async write with a stale legacy copy.
          if (value != null && await _async.getString(key) == null) {
            await _async.setString(key, value);
          }
          await legacy.remove(key);
        } catch (_) {
          // Quota / platform error: keep the legacy copy so read() can serve
          // it; leave the fallback armed.
          allDrained = false;
        }
      }
      _legacyDrained = allDrained;
    } catch (_) {
      _legacyDrained = false;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    await _ensureMigrated();
    await _async.setString('$_prefix$key', value);
  }

  @override
  Future<String?> read(String key) async {
    await _ensureMigrated();
    final value = await _async.getString('$_prefix$key');
    if (value != null) return value;
    if (_legacyDrained) return null;
    // A legacy key survived migration (e.g. quota). Reload before reading so we
    // never serve a stale in-memory cache, then return it as-is — no write-back
    // (that could lose a concurrent write or throw under quota).
    final legacy = await _legacyProvider();
    await legacy.reload();
    return legacy.getString('$_prefix$key');
  }

  @override
  Future<void> delete(String key) async {
    await _ensureMigrated();
    await _async.remove('$_prefix$key');
    if (_legacyDrained) return;
    // Clear any legacy copy that survived migration so a later fallback read
    // cannot resurrect it.
    final legacy = await _legacyProvider();
    await legacy.reload();
    await legacy.remove('$_prefix$key');
  }

  @override
  Future<Map<String, String>> readAll() async {
    await _ensureMigrated();
    final result = <String, String>{};
    final asyncValues = await _async.getAll();
    for (final entry in asyncValues.entries) {
      if (entry.key.startsWith(_prefix) && entry.value is String) {
        result[entry.key.substring(_prefix.length)] = entry.value as String;
      }
    }
    if (!_legacyDrained) {
      final legacy = await _legacyProvider();
      await legacy.reload();
      for (final key in legacy.keys()) {
        if (key.startsWith(_prefix)) {
          final val = legacy.getString(key);
          if (val != null) {
            result.putIfAbsent(key.substring(_prefix.length), () => val);
          }
        }
      }
    }
    return result;
  }
}

/// Outcome of [SecureIdentityKeyStore.loadFromStorage].
enum IdentityLoadResult {
  /// A complete identity was restored.
  loaded,

  /// Nothing identity-shaped is stored. Genuine fresh install; safe to
  /// generate.
  absent,

  /// Identity material is present but INCOMPLETE. Regenerating here would mint
  /// a new identity and make every peer's history permanently undecryptable,
  /// so the caller must fail closed instead.
  partial,
}

/// Persistent IdentityKeyStore backed by DualStorage.
class SecureIdentityKeyStore extends IdentityKeyStore {
  final DualStorage _storage;
  final String _p;
  IdentityKeyPair? _identityKeyPair;
  int? _localRegistrationId;

  /// Fired when a peer presents an identity key DIFFERENT from the one already
  /// trusted for that address — a reinstall, a storage wipe, or a server
  /// swapping the bundle. Trust-on-first-use is unaffected (no callback for a
  /// peer we have never seen).
  void Function(SignalProtocolAddress address)? onIdentityChanged;

  SecureIdentityKeyStore(this._storage, this._p, {this.onIdentityChanged});

  /// Single-record identity. The pair and the registration id used to be two
  /// independent keys, so losing exactly ONE made [loadFromStorage] report a
  /// fresh install and the caller regenerated the identity — silent, total,
  /// unrecoverable history loss. One key cannot half-exist.
  String get _recordKey => '${_p}identity_record_v1';
  String get _legacyPairKey => '${_p}identity_key_pair';
  String get _legacyRegIdKey => '${_p}registration_id';

  Future<void> initialize(
    IdentityKeyPair identityKeyPair,
    int registrationId,
  ) async {
    _identityKeyPair = identityKeyPair;
    _localRegistrationId = registrationId;
    // Atomic record FIRST: a crash after this point still loads cleanly.
    await _storage.write(
      key: _recordKey,
      value: jsonEncode(<String, dynamic>{
        'pair': base64Encode(identityKeyPair.serialize()),
        'registrationId': registrationId,
      }),
    );
    // Legacy mirror, so rolling back to an older bundle still finds an
    // identity. These two are never read while the record above exists.
    await _storage.write(
      key: _legacyPairKey,
      value: base64Encode(identityKeyPair.serialize()),
    );
    await _storage.write(
      key: _legacyRegIdKey,
      value: registrationId.toString(),
    );
  }

  /// Restore the identity, preferring the atomic record and falling back to the
  /// legacy two-key layout every existing install still has.
  ///
  /// A read that THROWS propagates — the caller must not treat a storage error
  /// as "no keys". Only a definitive absence returns [IdentityLoadResult.absent].
  Future<IdentityLoadResult> loadFromStorage() async {
    final raw = await _storage.read(key: _recordKey);
    if (raw != null) {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final pairB64 = decoded['pair'] as String?;
      final regId = decoded['registrationId'] as int?;
      if (pairB64 != null && regId != null) {
        _identityKeyPair = IdentityKeyPair.fromSerialized(
          base64Decode(pairB64),
        );
        _localRegistrationId = regId;
        return IdentityLoadResult.loaded;
      }
      // A record that exists but cannot be parsed is damage, not absence.
      return IdentityLoadResult.partial;
    }

    final pairB64 = await _storage.read(key: _legacyPairKey);
    final regIdStr = await _storage.read(key: _legacyRegIdKey);
    if (pairB64 == null && regIdStr == null) return IdentityLoadResult.absent;
    if (pairB64 == null || regIdStr == null) return IdentityLoadResult.partial;

    final regId = int.tryParse(regIdStr);
    if (regId == null) return IdentityLoadResult.partial;
    _identityKeyPair = IdentityKeyPair.fromSerialized(base64Decode(pairB64));
    _localRegistrationId = regId;

    // Best-effort upgrade to the atomic record. Purely additive: the legacy
    // keys stay, so a failure here costs nothing and is retried next boot.
    try {
      await _storage.write(
        key: _recordKey,
        value: jsonEncode(<String, dynamic>{
          'pair': pairB64,
          'registrationId': regId,
        }),
      );
    } catch (_) {}
    return IdentityLoadResult.loaded;
  }

  @override
  Future<IdentityKeyPair> getIdentityKeyPair() async {
    return _identityKeyPair!;
  }

  @override
  Future<int> getLocalRegistrationId() async {
    return _localRegistrationId!;
  }

  String _trustedKey(SignalProtocolAddress address) =>
      '${_p}trusted_identity_${address.getName()}_${address.getDeviceId()}';

  /// Write-through memo of the trusted peer keys this engine has already read.
  ///
  /// libsignal calls [isTrustedIdentity] on EVERY encrypt and EVERY decrypt, and
  /// on web a single storage read enumerates the whole localStorage keyspace
  /// (`SharedPreferencesAsyncWeb.getString` filters its allowList only after
  /// materialising every key). Without this memo, change detection would cost
  /// one full enumeration per message. With it, steady state is a memory
  /// compare and — since the write below is now conditional — strictly cheaper
  /// than the unconditional write this code used to do per message.
  ///
  /// Engine-local by design: a sibling tab writing a peer key is not observed
  /// here, which can only cost a duplicate warning, never trust of a key this
  /// engine did not itself verify against storage on first contact.
  final Map<String, IdentityKey> _trustedMemo = {};

  @override
  Future<bool> saveIdentity(
    SignalProtocolAddress address,
    IdentityKey? identityKey,
  ) async {
    if (identityKey == null) return false;
    final key = _trustedKey(address);
    await _storage.write(
      key: key,
      value: base64Encode(identityKey.serialize()),
    );
    _trustedMemo[key] = identityKey;
    return true;
  }

  @override
  Future<bool> isTrustedIdentity(
    SignalProtocolAddress address,
    IdentityKey? identityKey,
    Direction direction,
  ) async {
    if (identityKey == null) return false;
    // Auto-update: accept key rotation (e.g. peer reinstalled / storage
    // evicted). Consumer app — we don't verify fingerprints manually, so TOFU
    // always wins and the message keeps flowing.
    //
    // But a CHANGE is no longer silent. A peer's key changing means either a
    // reinstall or a server handing us a different bundle, and the second case
    // is indistinguishable from a machine-in-the-middle for everything sent
    // afterwards. The user gets told; only first contact stays quiet.
    final existing = await getIdentity(address);
    if (existing != null && _sameIdentity(existing, identityKey)) {
      // Unchanged: deliberately NO write. This runs per message.
      return true;
    }
    await saveIdentity(address, identityKey);
    if (existing != null) {
      onIdentityChanged?.call(address);
    }
    return true;
  }

  bool _sameIdentity(IdentityKey a, IdentityKey b) {
    final x = a.serialize();
    final y = b.serialize();
    if (x.length != y.length) return false;
    for (var i = 0; i < x.length; i++) {
      if (x[i] != y[i]) return false;
    }
    return true;
  }

  @override
  Future<IdentityKey?> getIdentity(SignalProtocolAddress address) async {
    final key = _trustedKey(address);
    final memo = _trustedMemo[key];
    if (memo != null) return memo;
    final stored = await _storage.read(key: key);
    if (stored == null) return null;
    final parsed = IdentityKey.fromBytes(base64Decode(stored), 0);
    _trustedMemo[key] = parsed;
    return parsed;
  }
}

/// Persistent PreKeyStore backed by DualStorage.
class SecurePreKeyStore extends PreKeyStore {
  final DualStorage _storage;
  final String _p;

  SecurePreKeyStore(this._storage, this._p);

  @override
  Future<PreKeyRecord> loadPreKey(int preKeyId) async {
    final data = await _storage.read(key: '${_p}pre_key_$preKeyId');
    if (data == null) {
      throw InvalidKeyIdException('No pre-key found for id: $preKeyId');
    }
    return PreKeyRecord.fromBuffer(base64Decode(data));
  }

  @override
  Future<void> storePreKey(int preKeyId, PreKeyRecord record) async {
    await _storage.write(
      key: '${_p}pre_key_$preKeyId',
      value: base64Encode(record.serialize()),
    );
  }

  @override
  Future<bool> containsPreKey(int preKeyId) async {
    final data = await _storage.read(key: '${_p}pre_key_$preKeyId');
    return data != null;
  }

  @override
  Future<void> removePreKey(int preKeyId) async {
    await _storage.delete(key: '${_p}pre_key_$preKeyId');
  }
}

/// Persistent SignedPreKeyStore backed by DualStorage.
class SecureSignedPreKeyStore extends SignedPreKeyStore {
  final DualStorage _storage;
  final String _p;

  SecureSignedPreKeyStore(this._storage, this._p);

  @override
  Future<SignedPreKeyRecord> loadSignedPreKey(int signedPreKeyId) async {
    final data = await _storage.read(
      key: '${_p}signed_pre_key_$signedPreKeyId',
    );
    if (data == null) {
      throw InvalidKeyIdException(
        'No signed pre-key found for id: $signedPreKeyId',
      );
    }
    return SignedPreKeyRecord.fromSerialized(base64Decode(data));
  }

  @override
  Future<void> storeSignedPreKey(
    int signedPreKeyId,
    SignedPreKeyRecord record,
  ) async {
    await _storage.write(
      key: '${_p}signed_pre_key_$signedPreKeyId',
      value: base64Encode(record.serialize()),
    );
  }

  @override
  Future<List<SignedPreKeyRecord>> loadSignedPreKeys() async {
    // We only use signedPreKeyId=0 in single-device model
    try {
      final record = await loadSignedPreKey(0);
      return [record];
    } catch (_) {
      return [];
    }
  }

  @override
  Future<bool> containsSignedPreKey(int signedPreKeyId) async {
    final data = await _storage.read(
      key: '${_p}signed_pre_key_$signedPreKeyId',
    );
    return data != null;
  }

  @override
  Future<void> removeSignedPreKey(int signedPreKeyId) async {
    await _storage.delete(key: '${_p}signed_pre_key_$signedPreKeyId');
  }
}

/// Persistent SessionStore backed by DualStorage.
class SecureSessionStore extends SessionStore {
  final DualStorage _storage;
  final String _p;

  SecureSessionStore(this._storage, this._p);

  String _sessionKey(SignalProtocolAddress address) =>
      '${_p}session_${address.getName()}_${address.getDeviceId()}';

  @override
  Future<SessionRecord> loadSession(SignalProtocolAddress address) async {
    final data = await _storage.read(key: _sessionKey(address));
    if (data == null) {
      return SessionRecord();
    }
    return SessionRecord.fromSerialized(base64Decode(data));
  }

  @override
  Future<List<int>> getSubDeviceSessions(String name) async {
    // Single-device model — only deviceId 1
    return [1];
  }

  @override
  Future<void> storeSession(
    SignalProtocolAddress address,
    SessionRecord record,
  ) async {
    try {
      await _storage.write(
        key: _sessionKey(address),
        value: base64Encode(record.serialize()),
      );
    } catch (e) {
      // TEMP storage-durability probe: a THROWN write (quota exceeded, private
      // mode, evicted origin) means the ratchet state never persisted — the
      // session will be absent on the next start. Rethrow: behaviour unchanged.
      // (An immediate read-back would NOT catch non-persistence: SharedPreferences
      // serves the in-memory value even when the localStorage flush silently
      // dropped. The cross-reload SESSION_INVENTORY is the real durability test.)
      E2eDiagLog.add('SESSION_STORE_WRITE_FAIL', {
        'peerId': address.getName(),
        'err': e.runtimeType.toString(),
      });
      rethrow;
    }
  }

  /// TEMP storage-durability probe: peer ids that currently have a persisted
  /// session on disk. Captured at every E2E init — a peer present one start and
  /// gone the next, with NO matching SESSION_STORE_DELETE in between, is storage
  /// eviction (not code). No key material is read, only the key names.
  Future<List<String>> inventoryPeerIds() async {
    final all = await _storage.readAll();
    final prefix = '${_p}session_';
    final ids = <String>[];
    for (final key in all.keys) {
      if (!key.startsWith(prefix)) continue;
      final rest = key.substring(prefix.length); // "<peerId>_<deviceId>"
      final cut = rest.lastIndexOf('_');
      ids.add(cut > 0 ? rest.substring(0, cut) : rest);
    }
    return ids;
  }

  @override
  Future<bool> containsSession(SignalProtocolAddress address) async {
    final data = await _storage.read(key: _sessionKey(address));
    return data != null;
  }

  @override
  Future<void> deleteSession(SignalProtocolAddress address) async {
    // TEMP storage-durability probe: log EVERY store-level delete (ours or
    // libsignal's). An inventory drop with no matching delete here ⇒ storage
    // loss; a drop WITH one ⇒ code deleted it.
    E2eDiagLog.add('SESSION_STORE_DELETE', {'peerId': address.getName()});
    await _storage.delete(key: _sessionKey(address));
  }

  @override
  Future<void> deleteAllSessions(String name) async {
    // Delete session for device 1 (our only device)
    await _storage.delete(key: '${_p}session_${name}_1');
  }
}
