import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import 'encryption/signal_stores.dart';

class EncryptionService {
  static const int _preKeyBatchSize = 100;
  static const int _deviceId = 1;

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  late SecureIdentityKeyStore _identityStore;
  late SecurePreKeyStore _preKeyStore;
  late SecureSignedPreKeyStore _signedPreKeyStore;
  late SecureSessionStore _sessionStore;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  /// True if keys were just generated and need to be uploaded to the server.
  bool needsKeyUpload = false;

  /// Public key data to upload to the server (set after key generation).
  Map<String, dynamic>? _keysForUpload;

  /// Initialize the encryption service. Loads keys from secure storage
  /// or generates new ones if this is a fresh install.
  Future<void> initialize() async {
    _identityStore = SecureIdentityKeyStore(_storage);
    _preKeyStore = SecurePreKeyStore(_storage);
    _signedPreKeyStore = SecureSignedPreKeyStore(_storage);
    _sessionStore = SecureSessionStore(_storage);

    final loaded = await _identityStore.loadFromStorage();
    if (loaded) {
      debugPrint('[EncryptionService] Loaded existing keys from storage');
      needsKeyUpload = false;
    } else {
      debugPrint('[EncryptionService] Generating new keys (fresh install)');
      await _generateKeys();
      needsKeyUpload = true;
    }

    _initialized = true;
  }

  /// Get the public key data to upload to the server.
  Map<String, dynamic>? getKeysForUpload() => _keysForUpload;

  /// Generate identity key pair, signed pre-key, and one-time pre-keys.
  Future<void> _generateKeys() async {
    final identityKeyPair = generateIdentityKeyPair();
    final registrationId = generateRegistrationId(false);

    await _identityStore.initialize(identityKeyPair, registrationId);

    // Generate signed pre-key (id = 0)
    final signedPreKey = generateSignedPreKey(identityKeyPair, 0);
    await _signedPreKeyStore.storeSignedPreKey(
        signedPreKey.id, signedPreKey);

    // Generate one-time pre-keys (ids 0..99)
    final preKeys = generatePreKeys(0, _preKeyBatchSize);
    for (final pk in preKeys) {
      await _preKeyStore.storePreKey(pk.id, pk);
    }

    // Save next pre-key id
    await _storage.write(
      key: 'e2e_next_pre_key_id',
      value: _preKeyBatchSize.toString(),
    );

    // Prepare public data for server upload
    _keysForUpload = {
      'keyBundle': {
        'registrationId': registrationId,
        'identityPublicKey':
            base64Encode(identityKeyPair.getPublicKey().serialize()),
        'signedPreKeyId': signedPreKey.id,
        'signedPreKeyPublic':
            base64Encode(signedPreKey.getKeyPair().publicKey.serialize()),
        'signedPreKeySignature': base64Encode(signedPreKey.signature),
      },
      'oneTimePreKeys': preKeys
          .map((pk) => {
                'keyId': pk.id,
                'publicKey':
                    base64Encode(pk.getKeyPair().publicKey.serialize()),
              })
          .toList(),
    };

    await _storage.write(key: 'e2e_setup_complete', value: 'true');
  }

  /// Check if we have an active session with the given user.
  Future<bool> hasSession(int userId) async {
    final address = SignalProtocolAddress(userId.toString(), _deviceId);
    return _sessionStore.containsSession(address);
  }

  /// Build a session with the given user from their pre-key bundle.
  Future<void> buildSession(
      int userId, Map<String, dynamic> preKeyBundle) async {
    final address = SignalProtocolAddress(userId.toString(), _deviceId);
    final builder = SessionBuilder(_sessionStore, _preKeyStore,
        _signedPreKeyStore, _identityStore, address);

    ECPublicKey? oneTimePreKey;
    if (preKeyBundle['oneTimePreKeyPublic'] != null) {
      oneTimePreKey = Curve.decodePoint(
          base64Decode(preKeyBundle['oneTimePreKeyPublic'] as String), 0);
    }

    final bundle = PreKeyBundle(
      preKeyBundle['registrationId'] as int,
      _deviceId,
      preKeyBundle['oneTimePreKeyId'] as int? ?? 0,
      oneTimePreKey,
      preKeyBundle['signedPreKeyId'] as int,
      Curve.decodePoint(
          base64Decode(preKeyBundle['signedPreKeyPublic'] as String), 0),
      Uint8List.fromList(
          base64Decode(preKeyBundle['signedPreKeySignature'] as String)),
      IdentityKey.fromBytes(
          base64Decode(preKeyBundle['identityPublicKey'] as String), 0),
    );

    await builder.processPreKeyBundle(bundle);
    debugPrint('[EncryptionService] Session built with userId=$userId');
  }

  /// Encrypt a plaintext string for the given recipient.
  /// Returns "{type}:{base64_body}" format.
  Future<String> encrypt(int recipientUserId, String plaintext) async {
    final address =
        SignalProtocolAddress(recipientUserId.toString(), _deviceId);
    final cipher = SessionCipher(_sessionStore, _preKeyStore,
        _signedPreKeyStore, _identityStore, address);

    final ciphertext =
        await cipher.encrypt(Uint8List.fromList(utf8.encode(plaintext)));

    return '${ciphertext.getType()}:${base64Encode(ciphertext.serialize())}';
  }

  /// Decrypt a ciphertext string from the given sender.
  /// Input format: "{type}:{base64_body}".
  Future<String> decrypt(int senderUserId, String ciphertextStr) async {
    final address =
        SignalProtocolAddress(senderUserId.toString(), _deviceId);
    final cipher = SessionCipher(_sessionStore, _preKeyStore,
        _signedPreKeyStore, _identityStore, address);

    final colonIdx = ciphertextStr.indexOf(':');
    final type = int.parse(ciphertextStr.substring(0, colonIdx));
    final body = base64Decode(ciphertextStr.substring(colonIdx + 1));

    Uint8List plaintext;
    if (type == CiphertextMessage.prekeyType) {
      plaintext = await cipher.decrypt(PreKeySignalMessage(body));
    } else {
      plaintext =
          await cipher.decryptFromSignal(SignalMessage.fromSerialized(body));
    }

    return utf8.decode(plaintext);
  }

  /// Generate more one-time pre-keys and return them for server upload.
  Future<List<Map<String, dynamic>>> generateMorePreKeys() async {
    final nextIdStr = await _storage.read(key: 'e2e_next_pre_key_id');
    final nextId = int.parse(nextIdStr ?? '100');

    final preKeys = generatePreKeys(nextId, _preKeyBatchSize);
    for (final pk in preKeys) {
      await _preKeyStore.storePreKey(pk.id, pk);
    }

    await _storage.write(
      key: 'e2e_next_pre_key_id',
      value: (nextId + _preKeyBatchSize).toString(),
    );

    debugPrint(
        '[EncryptionService] Generated ${preKeys.length} more pre-keys (nextId=${nextId + _preKeyBatchSize})');

    return preKeys
        .map((pk) => {
              'keyId': pk.id,
              'publicKey':
                  base64Encode(pk.getKeyPair().publicKey.serialize()),
            })
        .toList();
  }

  /// Get the identity key fingerprint (for display in Privacy & Safety).
  Future<String?> getIdentityFingerprint() async {
    if (!_initialized) return null;
    final keyPair = await _identityStore.getIdentityKeyPair();
    final bytes = keyPair.getPublicKey().serialize();
    // Format as hex groups of 4 for readability
    final hex = bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final groups = <String>[];
    for (var i = 0; i < hex.length; i += 4) {
      final end = (i + 4 > hex.length) ? hex.length : i + 4;
      groups.add(hex.substring(i, end));
    }
    return groups.join(' ');
  }

  /// Clear all encryption keys from storage (on logout or account deletion).
  Future<void> clearAllKeys() async {
    await _storage.deleteAll();
    _initialized = false;
    needsKeyUpload = false;
    _keysForUpload = null;
    debugPrint('[EncryptionService] All encryption keys cleared');
  }
}
