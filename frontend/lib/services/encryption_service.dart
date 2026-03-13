import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'encryption/signal_stores.dart';

class EncryptionService {
  /// Batch size for replenishment (preKeysLow). Server threshold is 10.
  static const int _preKeyBatchSize = 100;
  /// Smaller initial batch for fresh install — faster startup, preKeysLow replenishes when low.
  static const int _initialPreKeyBatchSize = 20;
  static const int _deviceId = 1;

  /// On web: app-specific dbName isolates from other apps; WebCrypto encrypts at rest.
  /// Mobile: uses Keychain/Keystore (hardware-backed when available).
  final FlutterSecureStorage _storage = FlutterSecureStorage(
    webOptions: const WebOptions(dbName: 'FireplaceE2E'),
  );

  late SecureIdentityKeyStore _identityStore;
  late SecurePreKeyStore _preKeyStore;
  late SecureSignedPreKeyStore _signedPreKeyStore;
  late SecureSessionStore _sessionStore;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  int? _userId;

  /// Cached SharedPreferences instance for synchronous-on-web message content cache.
  SharedPreferences? _prefs;
  Future<SharedPreferences> get _sharedPrefs async =>
      _prefs ??= await SharedPreferences.getInstance();

  /// True if keys were just generated and need to be uploaded to the server.
  bool needsKeyUpload = false;

  /// Public key data to upload to the server (set after key generation).
  Map<String, dynamic>? _keysForUpload;

  /// Initialize the encryption service for the given user. Loads keys from
  /// secure storage or generates new ones if this is a fresh install.
  Future<void> initialize(int userId) async {
    _userId = userId;
    final p = 'e2e_${userId}_'; // per-user storage key prefix

    _identityStore = SecureIdentityKeyStore(_storage, p);
    _preKeyStore = SecurePreKeyStore(_storage, p);
    _signedPreKeyStore = SecureSignedPreKeyStore(_storage, p);
    _sessionStore = SecureSessionStore(_storage, p);

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
    final uid = _userId; // always non-null when called from initialize()
    if (uid == null) return;
    final identityKeyPair = generateIdentityKeyPair();
    final registrationId = generateRegistrationId(false);

    await _identityStore.initialize(identityKeyPair, registrationId);

    // Generate signed pre-key (id = 0)
    final signedPreKey = generateSignedPreKey(identityKeyPair, 0);
    await _signedPreKeyStore.storeSignedPreKey(
        signedPreKey.id, signedPreKey);

    // Generate one-time pre-keys (smaller batch for fast startup; preKeysLow replenishes)
    final preKeys = generatePreKeys(0, _initialPreKeyBatchSize);
    await Future.wait(
      preKeys.map((pk) => _preKeyStore.storePreKey(pk.id, pk)),
    );

    // Save next pre-key id
    await _storage.write(
      key: 'e2e_${uid}_next_pre_key_id',
      value: _initialPreKeyBatchSize.toString(),
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
      'oneTimePreKeys': preKeys.map(_preKeyToUploadFormat).toList(),
    };

    await _storage.write(key: 'e2e_${uid}_setup_complete', value: 'true');
  }

  /// Check if we have an active session with the given user.
  Future<bool> hasSession(int userId) async {
    final address = SignalProtocolAddress(userId.toString(), _deviceId);
    return _sessionStore.containsSession(address);
  }

  /// Delete the session with the given user. Forces a fresh X3DH exchange
  /// on the next outgoing message (type-3 PreKeySignalMessage), which allows
  /// the remote peer to re-establish their session too.
  Future<void> deleteSession(int userId) async {
    final address = SignalProtocolAddress(userId.toString(), _deviceId);
    await _sessionStore.deleteSession(address);
    debugPrint('[EncryptionService] Session deleted for userId=$userId (broken session reset)');
  }

  /// Build a session with the given user from their pre-key bundle.
  ///
  /// [preKeyBundle] must contain: registrationId, identityPublicKey,
  /// signedPreKeyId, signedPreKeyPublic, signedPreKeySignature.
  /// Optional: oneTimePreKeyId, oneTimePreKeyPublic (null when no unused OTPs).
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

    final identityKey = IdentityKey.fromBytes(
        base64Decode(preKeyBundle['identityPublicKey'] as String), 0);
    // Trust the identity from the bundle so we don't throw UntrustedIdentityException
    // when the peer has rotated keys (e.g. after they regenerated keys).
    await _identityStore.saveIdentity(address, identityKey);

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
      identityKey,
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
    final uid = _userId;
    if (uid == null) return [];
    final nextIdStr = await _storage.read(key: 'e2e_${uid}_next_pre_key_id');
    final nextId = int.parse(nextIdStr ?? '100');

    final preKeys = generatePreKeys(nextId, _preKeyBatchSize);
    // Parallel writes (chunked to avoid overwhelming secure storage)
    const chunkSize = 25;
    for (var i = 0; i < preKeys.length; i += chunkSize) {
      final chunk = preKeys.skip(i).take(chunkSize).toList();
      await Future.wait(
        chunk.map((pk) => _preKeyStore.storePreKey(pk.id, pk)),
      );
    }

    await _storage.write(
      key: 'e2e_${uid}_next_pre_key_id',
      value: (nextId + _preKeyBatchSize).toString(),
    );

    debugPrint(
        '[EncryptionService] Generated ${preKeys.length} more pre-keys (nextId=${nextId + _preKeyBatchSize})');

    return preKeys.map(_preKeyToUploadFormat).toList();
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

  static Map<String, dynamic> _preKeyToUploadFormat(PreKeyRecord pk) => {
        'keyId': pk.id,
        'publicKey': base64Encode(pk.getKeyPair().publicKey.serialize()),
      };

  /// Build the public key bundle from stored keys for re-upload on reconnect.
  /// Returns null if keys are not loaded yet.
  Future<Map<String, dynamic>?> getKeyBundleForReupload() async {
    if (!_initialized) return null;
    try {
      final keyPair = await _identityStore.getIdentityKeyPair();
      final registrationId = await _identityStore.getLocalRegistrationId();
      final signedPreKey = await _signedPreKeyStore.loadSignedPreKey(0);
      return {
        'registrationId': registrationId,
        'identityPublicKey': base64Encode(keyPair.getPublicKey().serialize()),
        'signedPreKeyId': signedPreKey.id,
        'signedPreKeyPublic':
            base64Encode(signedPreKey.getKeyPair().publicKey.serialize()),
        'signedPreKeySignature': base64Encode(signedPreKey.signature),
      };
    } catch (e) {
      debugPrint('[EncryptionService] getKeyBundleForReupload failed: $e');
      return null;
    }
  }

  /// Persist decrypted message content to survive app restart.
  ///
  /// Uses SharedPreferences (localStorage on web) instead of flutter_secure_storage
  /// (IndexedDB) because localStorage writes are synchronous in JS — they survive
  /// browser tab close, unlike in-flight IndexedDB transactions which are aborted.
  Future<void> saveDecryptedContent(int id, Map<String, dynamic> data) async {
    final userId = _userId;
    if (userId == null) return;
    try {
      final prefs = await _sharedPrefs;
      await prefs.setString('e2e_${userId}_decrypted_$id', jsonEncode(data));
    } catch (_) {}
  }

  /// Retrieve persisted decrypted message content, or null if not found.
  /// Falls back to flutter_secure_storage for entries written by older versions.
  Future<Map<String, dynamic>?> getDecryptedContent(int id) async {
    final userId = _userId;
    if (userId == null) return null;
    final key = 'e2e_${userId}_decrypted_$id';
    try {
      // Primary: SharedPreferences (reliable on web — synchronous localStorage)
      final prefs = await _sharedPrefs;
      final raw = prefs.getString(key);
      if (raw != null) return jsonDecode(raw) as Map<String, dynamic>;
      // Fallback: flutter_secure_storage (written by older app versions)
      final oldRaw = await _storage.read(key: key);
      if (oldRaw != null) return jsonDecode(oldRaw) as Map<String, dynamic>;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Clear all E2E encryption keys for this user from storage.
  /// Uses selective deletion (not deleteAll) to avoid wiping non-E2E data.
  Future<void> clearAllKeys() async {
    final userId = _userId;
    if (userId != null) {
      final prefix = 'e2e_${userId}_';
      // flutter_secure_storage: collect keys first to avoid concurrent-modification
      final all = await _storage.readAll();
      final keysToDelete = all.keys.where((k) => k.startsWith(prefix)).toList();
      for (final key in keysToDelete) {
        await _storage.delete(key: key);
      }
      // SharedPreferences: clear decrypted content cache entries
      try {
        final prefs = await _sharedPrefs;
        final spKeysToDelete = prefs
            .getKeys()
            .where((k) => k.startsWith('e2e_${userId}_decrypted_'))
            .toList();
        for (final key in spKeysToDelete) {
          await prefs.remove(key);
        }
      } catch (_) {}
    }
    _initialized = false;
    needsKeyUpload = false;
    _keysForUpload = null;
    _userId = null;
    _prefs = null;
    debugPrint('[EncryptionService] All encryption keys cleared');
  }
}
