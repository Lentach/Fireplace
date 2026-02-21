import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

/// Persistent IdentityKeyStore backed by flutter_secure_storage.
class SecureIdentityKeyStore extends IdentityKeyStore {
  final FlutterSecureStorage _storage;
  IdentityKeyPair? _identityKeyPair;
  int? _localRegistrationId;

  SecureIdentityKeyStore(this._storage);

  Future<void> initialize(
      IdentityKeyPair identityKeyPair, int registrationId) async {
    _identityKeyPair = identityKeyPair;
    _localRegistrationId = registrationId;
    await _storage.write(
      key: 'e2e_identity_key_pair',
      value: base64Encode(identityKeyPair.serialize()),
    );
    await _storage.write(
      key: 'e2e_registration_id',
      value: registrationId.toString(),
    );
  }

  Future<bool> loadFromStorage() async {
    final pairB64 = await _storage.read(key: 'e2e_identity_key_pair');
    final regIdStr = await _storage.read(key: 'e2e_registration_id');
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
    final key = 'e2e_trusted_identity_${address.getName()}_${address.getDeviceId()}';
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
    final key = 'e2e_trusted_identity_${address.getName()}_${address.getDeviceId()}';
    final stored = await _storage.read(key: key);
    if (stored == null) return true; // First time — trust on first use (TOFU)
    final storedKey = IdentityKey.fromBytes(base64Decode(stored), 0);
    return identityKey.getFingerprint() == storedKey.getFingerprint();
  }

  @override
  Future<IdentityKey?> getIdentity(SignalProtocolAddress address) async {
    final key = 'e2e_trusted_identity_${address.getName()}_${address.getDeviceId()}';
    final stored = await _storage.read(key: key);
    if (stored == null) return null;
    return IdentityKey.fromBytes(base64Decode(stored), 0);
  }
}

/// Persistent PreKeyStore backed by flutter_secure_storage.
class SecurePreKeyStore extends PreKeyStore {
  final FlutterSecureStorage _storage;

  SecurePreKeyStore(this._storage);

  @override
  Future<PreKeyRecord> loadPreKey(int preKeyId) async {
    final data = await _storage.read(key: 'e2e_pre_key_$preKeyId');
    if (data == null) {
      throw InvalidKeyIdException('No pre-key found for id: $preKeyId');
    }
    return PreKeyRecord.fromBuffer(base64Decode(data));
  }

  @override
  Future<void> storePreKey(int preKeyId, PreKeyRecord record) async {
    await _storage.write(
      key: 'e2e_pre_key_$preKeyId',
      value: base64Encode(record.serialize()),
    );
  }

  @override
  Future<bool> containsPreKey(int preKeyId) async {
    final data = await _storage.read(key: 'e2e_pre_key_$preKeyId');
    return data != null;
  }

  @override
  Future<void> removePreKey(int preKeyId) async {
    await _storage.delete(key: 'e2e_pre_key_$preKeyId');
  }
}

/// Persistent SignedPreKeyStore backed by flutter_secure_storage.
class SecureSignedPreKeyStore extends SignedPreKeyStore {
  final FlutterSecureStorage _storage;

  SecureSignedPreKeyStore(this._storage);

  @override
  Future<SignedPreKeyRecord> loadSignedPreKey(int signedPreKeyId) async {
    final data =
        await _storage.read(key: 'e2e_signed_pre_key_$signedPreKeyId');
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
      key: 'e2e_signed_pre_key_$signedPreKeyId',
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
        await _storage.read(key: 'e2e_signed_pre_key_$signedPreKeyId');
    return data != null;
  }

  @override
  Future<void> removeSignedPreKey(int signedPreKeyId) async {
    await _storage.delete(key: 'e2e_signed_pre_key_$signedPreKeyId');
  }
}

/// Persistent SessionStore backed by flutter_secure_storage.
class SecureSessionStore extends SessionStore {
  final FlutterSecureStorage _storage;

  SecureSessionStore(this._storage);

  String _sessionKey(SignalProtocolAddress address) =>
      'e2e_session_${address.getName()}_${address.getDeviceId()}';

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
    await _storage.delete(key: 'e2e_session_${name}_1');
  }
}
