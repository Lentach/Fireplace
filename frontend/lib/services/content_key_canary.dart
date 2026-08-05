import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/e2e_diag_log.dart';
import '../utils/e2e_persistent_diag.dart';

const _secureKey = 'content_key_canary_v1';
const _shadowKey = 'content_key_canary_shadow_v1';

/// One-key wrapper around the WebCrypto-backed secure store under observation.
///
/// This narrow seam keeps [ContentKeyCanary] testable without a platform
/// channel while ensuring production cannot accidentally probe another key.
abstract interface class ContentKeyCanarySecureStore {
  Future<String?> read();
  Future<void> write(String value);
}

/// One-key wrapper around the durable localStorage shadow record.
abstract interface class ContentKeyCanaryShadowStore {
  Future<String?> read();
  Future<void> write(String value);
}

class _FlutterSecureContentKeyCanaryStore
    implements ContentKeyCanarySecureStore {
  _FlutterSecureContentKeyCanaryStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _secureKey);

  @override
  Future<void> write(String value) =>
      _storage.write(key: _secureKey, value: value);
}

class _SharedPreferencesContentKeyCanaryShadowStore
    implements ContentKeyCanaryShadowStore {
  SharedPreferences? _prefs;

  Future<SharedPreferences> get _instance async =>
      _prefs ??= await SharedPreferences.getInstance();

  @override
  Future<String?> read() async => (await _instance).getString(_shadowKey);

  @override
  Future<void> write(String value) async {
    await (await _instance).setString(_shadowKey, value);
  }
}

/// #105 B2 phase 0: production durability canary for at-rest content-key storage.
///
/// ⚠️ **THIS CANARY DOES NOT MEASURE WHAT ITS ORIGINAL COMMENT CLAIMED, and the
/// B2b deploy gate built on it is therefore not evidence. Verified 2026-08-05.**
/// The original text said flutter_secure_storage on web "uses IndexedDB +
/// WebCrypto". It does not: the pinned `flutter_secure_storage_web` 1.2.1 keeps
/// every value in `window.localStorage` and writes its raw AES master key there
/// as well (`flutter_secure_storage_web.dart:110-116`; no IndexedDB anywhere in
/// that package). So [_secureStore] (flutter_secure_storage) and [_shadowStore]
/// (SharedPreferences) are BOTH localStorage on the same origin — they are
/// evicted together, so `secure == null && shadow != null` (the only state that
/// reports `CONTENT_KEY_CANARY_LOST`) is essentially unreachable. A long run of
/// `CANARY_OK {ageDays: N}` demonstrates that localStorage survived N days; it
/// says NOTHING about a distinct, more-durable key store, because there isn't
/// one. Two consequences: (1) do not read `ageDays > 7` as clearance to seal
/// irreplaceable key material; (2) sealing on web currently stores the lock and
/// the key in the same drawer (see `signal_stores.dart` for the full note).
/// Re-point this at a non-extractable IndexedDB `CryptoKey` before trusting it.
///
/// Original intent, kept for context: one content key would live in
/// flutter_secure_storage on web; losing it makes every sealed plaintext record
/// on a device unreadable, so this measures the loss rate before B2 seals
/// anything. `CONTENT_KEY_CANARY_LOST` in field diagnostics still means STOP.
///
/// Native Keychain/Keystore is already trusted; this is deliberately a no-op
/// there. The localStorage shadow lets a later boot distinguish a fresh web
/// device from a missing or substituted secure value.
class ContentKeyCanary {
  ContentKeyCanary({
    ContentKeyCanarySecureStore? secureStore,
    ContentKeyCanaryShadowStore? shadowStore,
    bool? isWeb,
    Random? random,
    DateTime Function()? now,
  }) : _secureStore = secureStore ?? _FlutterSecureContentKeyCanaryStore(),
       _shadowStore =
           shadowStore ?? _SharedPreferencesContentKeyCanaryShadowStore(),
       _isWeb = isWeb ?? kIsWeb,
       _random = random ?? Random.secure(),
       _now = now ?? DateTime.now;

  final ContentKeyCanarySecureStore _secureStore;
  final ContentKeyCanaryShadowStore _shadowStore;
  final bool _isWeb;
  final Random _random;
  final DateTime Function() _now;

  /// Checks the current pair once, then arms its successor. Never throw from
  /// here: the canary measures storage safety and must not become a boot risk.
  Future<void> checkAndArm() async {
    if (!_isWeb) return;

    try {
      await _checkAndArm();
    } catch (error) {
      _recordError('canary', 'check', error);
    }
  }

  Future<void> _checkAndArm() async {
    final secure = await _readSecure();
    if (secure.failed) return;

    final shadow = await _readShadow();
    if (shadow.failed) return;

    if (secure.value == null && shadow.value == null) {
      await _arm();
      return;
    }

    final secureRecord = _CanaryRecord.tryParse(secure.value);
    final shadowRecord = _CanaryRecord.tryParse(shadow.value);

    if (secureRecord != null &&
        (shadow.value == null ||
            (shadowRecord != null && secureRecord.id == shadowRecord.id))) {
      E2eDiagLog.add('CANARY_OK', {'ageDays': _ageDays(secureRecord)});
      if (shadow.value == null) {
        await _writeShadow(secure.value!);
      }
      return;
    }

    if (shadow.value != null) {
      final mismatch = secure.value != null;
      E2ePersistentDiag.record('CONTENT_KEY_CANARY_LOST', {
        'ageDays': shadowRecord == null ? 0 : _ageDays(shadowRecord),
        'mismatch': mismatch,
      });
      await _arm(excludingId: shadowRecord?.id ?? secureRecord?.id);
      return;
    }

    // A malformed secure value without a shadow cannot prove loss, but it is
    // still unsafe to carry forward. Replace it and preserve the fault signal.
    _recordError('secure', 'decode', FormatException('invalid canary record'));
    await _arm();
  }

  Future<_StoreRead> _readSecure() async {
    try {
      return _StoreRead.value(await _secureStore.read());
    } catch (error) {
      _recordError('secure', 'read', error);
      return const _StoreRead.failed();
    }
  }

  Future<_StoreRead> _readShadow() async {
    try {
      return _StoreRead.value(await _shadowStore.read());
    } catch (error) {
      _recordError('shadow', 'read', error);
      return const _StoreRead.failed();
    }
  }

  Future<void> _arm({String? excludingId}) async {
    final record = _mint(excludingId: excludingId);
    final value = jsonEncode(record.toJson());
    await _writeSecure(value);
    await _writeShadow(value);
    E2eDiagLog.add('CANARY_MINTED', {'ageDays': 0});
  }

  Future<void> _writeSecure(String value) async {
    try {
      await _secureStore.write(value);
    } catch (error) {
      _recordError('secure', 'write', error);
    }
  }

  Future<void> _writeShadow(String value) async {
    try {
      await _shadowStore.write(value);
    } catch (error) {
      _recordError('shadow', 'write', error);
    }
  }

  _CanaryRecord _mint({String? excludingId}) {
    late String id;
    do {
      id = List<String>.generate(
        16,
        (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        growable: false,
      ).join();
    } while (id == excludingId);
    return _CanaryRecord(id, _now().millisecondsSinceEpoch);
  }

  int _ageDays(_CanaryRecord record) {
    final elapsed = _now().millisecondsSinceEpoch - record.mintedAtMs;
    return elapsed <= 0 ? 0 : elapsed ~/ Duration.millisecondsPerDay;
  }

  void _recordError(String store, String operation, Object error) {
    E2ePersistentDiag.record('CONTENT_KEY_CANARY_ERROR', {
      'store': store,
      'operation': operation,
      'error': error.runtimeType.toString(),
    });
  }
}

class _StoreRead {
  const _StoreRead._(this.value, this.failed);

  const _StoreRead.value(String? value) : this._(value, false);
  const _StoreRead.failed() : this._(null, true);

  final String? value;
  final bool failed;
}

class _CanaryRecord {
  const _CanaryRecord(this.id, this.mintedAtMs);

  final String id;
  final int mintedAtMs;

  Map<String, Object> toJson() => {'id': id, 'mintedAtMs': mintedAtMs};

  static _CanaryRecord? tryParse(String? value) {
    if (value == null) return null;
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map) return null;
      final id = decoded['id'];
      final mintedAtMs = decoded['mintedAtMs'];
      if (id is! String ||
          !RegExp(r'^[0-9a-f]{32}$').hasMatch(id) ||
          mintedAtMs is! int) {
        return null;
      }
      return _CanaryRecord(id, mintedAtMs);
    } catch (_) {
      return null;
    }
  }
}
