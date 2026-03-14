import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Platform-aware key-value storage for Signal Protocol keys.
///
/// **Web:** Uses ONLY SharedPreferences (localStorage). flutter_secure_storage
/// on web uses IndexedDB+WebCrypto which loses data when browser tabs are closed
/// or the WebCrypto key is evicted. localStorage never loses data.
///
/// **Mobile:** Uses flutter_secure_storage (Keychain on iOS, Keystore on Android)
/// which is hardware-backed and reliable.
class DualStorage {
  final FlutterSecureStorage _secure;
  SharedPreferences? _prefs;

  DualStorage(this._secure);

  Future<SharedPreferences> get _sharedPrefs async =>
      _prefs ??= await SharedPreferences.getInstance();

  /// Prefix for Signal keys in SharedPreferences to avoid collisions
  /// with other SharedPreferences data (e.g. decrypted message cache).
  static const String _spPrefix = 'sig_';

  Future<void> write({required String key, required String value}) async {
    if (kIsWeb) {
      final prefs = await _sharedPrefs;
      await prefs.setString('$_spPrefix$key', value);
    } else {
      await _secure.write(key: key, value: value);
    }
  }

  Future<String?> read({required String key}) async {
    if (kIsWeb) {
      final prefs = await _sharedPrefs;
      return prefs.getString('$_spPrefix$key');
    } else {
      return _secure.read(key: key);
    }
  }

  Future<void> delete({required String key}) async {
    if (kIsWeb) {
      final prefs = await _sharedPrefs;
      await prefs.remove('$_spPrefix$key');
    } else {
      await _secure.delete(key: key);
    }
  }

  Future<Map<String, String>> readAll() async {
    if (kIsWeb) {
      final prefs = await _sharedPrefs;
      final result = <String, String>{};
      for (final key in prefs.getKeys()) {
        if (key.startsWith(_spPrefix)) {
          final val = prefs.getString(key);
          if (val != null) result[key.substring(_spPrefix.length)] = val;
        }
      }
      return result;
    } else {
      return _secure.readAll();
    }
  }

  void clearPrefsCache() {
    _prefs = null;
  }
}

/// Persistent IdentityKeyStore backed by DualStorage.
class SecureIdentityKeyStore extends IdentityKeyStore {
  final DualStorage _storage;
  final String _p;
  IdentityKeyPair? _identityKeyPair;
  int? _localRegistrationId;

  SecureIdentityKeyStore(this._storage, this._p);

  Future<void> initialize(
      IdentityKeyPair identityKeyPair, int registrationId) async {
    _identityKeyPair = identityKeyPair;
    _localRegistrationId = registrationId;
    await _storage.write(
      key: '${_p}identity_key_pair',
      value: base64Encode(identityKeyPair.serialize()),
    );
    await _storage.write(
      key: '${_p}registration_id',
      value: registrationId.toString(),
    );
  }

  Future<bool> loadFromStorage() async {
    final pairB64 = await _storage.read(key: '${_p}identity_key_pair');
    final regIdStr = await _storage.read(key: '${_p}registration_id');
    if (pairB64 == null || regIdStr == null) return false;
    _identityKeyPair =
        IdentityKeyPair.fromSerialized(base64Decode(pairB64));
    _localRegistrationId = int.parse(regIdStr);
    return true;
  }

  @override
  Future<IdentityKeyPair> getIdentityKeyPair() async {
    return _identityKeyPair!;
  }

  @override
  Future<int> getLocalRegistrationId() async {
    return _localRegistrationId!;
  }

  @override
  Future<bool> saveIdentity(
      SignalProtocolAddress address, IdentityKey? identityKey) async {
    if (identityKey == null) return false;
    final key = '${_p}trusted_identity_${address.getName()}_${address.getDeviceId()}';
    await _storage.write(
      key: key,
      value: base64Encode(identityKey.serialize()),
    );
    return true;
  }

  @override
  Future<bool> isTrustedIdentity(SignalProtocolAddress address,
      IdentityKey? identityKey, Direction direction) async {
    if (identityKey == null) return false;
    // Auto-update: accept key rotation (e.g. peer reinstalled / storage evicted).
    // Consumer app — we don't verify fingerprints manually, so TOFU always wins.
    await saveIdentity(address, identityKey);
    return true;
  }

  @override
  Future<IdentityKey?> getIdentity(SignalProtocolAddress address) async {
    final key = '${_p}trusted_identity_${address.getName()}_${address.getDeviceId()}';
    final stored = await _storage.read(key: key);
    if (stored == null) return null;
    return IdentityKey.fromBytes(base64Decode(stored), 0);
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
    final data =
        await _storage.read(key: '${_p}signed_pre_key_$signedPreKeyId');
    if (data == null) {
      throw InvalidKeyIdException(
          'No signed pre-key found for id: $signedPreKeyId');
    }
    return SignedPreKeyRecord.fromSerialized(base64Decode(data));
  }

  @override
  Future<void> storeSignedPreKey(
      int signedPreKeyId, SignedPreKeyRecord record) async {
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
    final data =
        await _storage.read(key: '${_p}signed_pre_key_$signedPreKeyId');
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
      SignalProtocolAddress address, SessionRecord record) async {
    await _storage.write(
      key: _sessionKey(address),
      value: base64Encode(record.serialize()),
    );
  }

  @override
  Future<bool> containsSession(SignalProtocolAddress address) async {
    final data = await _storage.read(key: _sessionKey(address));
    return data != null;
  }

  @override
  Future<void> deleteSession(SignalProtocolAddress address) async {
    await _storage.delete(key: _sessionKey(address));
  }

  @override
  Future<void> deleteAllSessions(String name) async {
    // Delete session for device 1 (our only device)
    await _storage.delete(key: '${_p}session_${name}_1');
  }
}
