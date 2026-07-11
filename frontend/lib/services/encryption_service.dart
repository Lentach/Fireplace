import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/e2e_persistent_diag.dart';
import 'encryption/signal_stores.dart';

class EncryptionService {
  EncryptionService({int decryptedContentCacheLimit = 2000})
      : _decryptedContentCacheLimit = decryptedContentCacheLimit;

  /// Batch size for replenishment (preKeysLow). Server threshold is 10.
  static const int _preKeyBatchSize = 100;
  /// Smaller initial batch for fresh install — faster startup, preKeysLow replenishes when low.
  static const int _initialPreKeyBatchSize = 20;
  static const int _deviceId = 1;

  /// DualStorage: writes to both flutter_secure_storage (IndexedDB on web) AND
  /// SharedPreferences (localStorage on web). Reads try flutter_secure_storage
  /// first, then falls back to SharedPreferences. This prevents data loss when
  /// IndexedDB/WebCrypto keys are evicted by the browser.
  final DualStorage _storage = DualStorage(FlutterSecureStorage(
    webOptions: const WebOptions(dbName: 'FireplaceE2E'),
  ));

  late SecureIdentityKeyStore _identityStore;
  late SecurePreKeyStore _preKeyStore;
  late SecureSignedPreKeyStore _signedPreKeyStore;
  late SecureSessionStore _sessionStore;

  /// The session store handed to SessionCipher/SessionBuilder. Same object as
  /// [_sessionStore] in production; race probes wrap it via
  /// [debugWrapSessionStore] to gate storeSession deterministically.
  late SessionStore _cipherSessionStore;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  int? _userId;

  /// Cached SharedPreferences instance for synchronous-on-web message content cache.
  SharedPreferences? _prefs;
  Future<SharedPreferences> get _sharedPrefs async =>
      _prefs ??= await SharedPreferences.getInstance();
  final int _decryptedContentCacheLimit;

  /// Test-only seam: wrap the session store used by SessionCipher /
  /// SessionBuilder (e.g. to hold a storeSession mid-flight and force a
  /// lost-update interleave). Diagnostics ([sessionInventoryPeerIds]) keep
  /// reading the real [_sessionStore].
  @visibleForTesting
  void debugWrapSessionStore(SessionStore Function(SessionStore inner) wrap) {
    _cipherSessionStore = wrap(_cipherSessionStore);
  }

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
    _cipherSessionStore = _sessionStore;

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
  ///
  /// Serialized per peer (see [_sessionTails]) so a delete never lands in the
  /// middle of an in-flight encrypt/decrypt load→store window.
  Future<void> deleteSession(int userId) {
    return _runSessionSerialized(userId, () async {
      final address = SignalProtocolAddress(userId.toString(), _deviceId);
      await _sessionStore.deleteSession(address);
      debugPrint(
          '[EncryptionService] Session deleted for userId=$userId (broken session reset)');
    });
  }

  /// TEMP storage-durability probe: peer ids with a persisted Signal session.
  /// Drives the SESSION_INVENTORY diag event (see [SecureSessionStore.inventoryPeerIds]).
  Future<List<String>> sessionInventoryPeerIds() async {
    if (!_initialized) return const [];
    return _sessionStore.inventoryPeerIds();
  }

  /// Build a session with the given user from their pre-key bundle.
  ///
  /// [preKeyBundle] must contain: registrationId, identityPublicKey,
  /// signedPreKeyId, signedPreKeyPublic, signedPreKeySignature.
  /// Optional: oneTimePreKeyId, oneTimePreKeyPublic (null when no unused OTPs).
  ///
  /// Serialized per peer (see [_sessionTails]): processPreKeyBundle archives
  /// the current ratchet state and stores a new record — racing it against an
  /// in-flight encrypt/decrypt store loses one side's advance.
  Future<void> buildSession(int userId, Map<String, dynamic> preKeyBundle) {
    return _runSessionSerialized(
        userId, () => _buildSessionSerialized(userId, preKeyBundle));
  }

  Future<void> _buildSessionSerialized(
      int userId, Map<String, dynamic> preKeyBundle) async {
    final address = SignalProtocolAddress(userId.toString(), _deviceId);
    final builder = SessionBuilder(_cipherSessionStore, _preKeyStore,
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

  /// Tail of the in-flight session-mutation chain per peer. Signal's Double
  /// Ratchet is stateful: EVERY operation that does load→mutate→store on a
  /// peer's SessionRecord — encrypt, decrypt, buildSession, deleteSession —
  /// must run through [_runSessionSerialized]. Two such operations
  /// interleaving at store await points lose one side's advance (lost
  /// update):
  ///  - encrypt vs encrypt: both load the same state and emit DUPLICATE
  ///    chain counters (the 2026-07-07 note-burst bug, 0.0.90);
  ///  - encrypt vs decrypt: a decrypt store landing after a concurrent
  ///    encrypt store rolls the SENDER chain back, so the next encrypt
  ///    reuses a counter the receiver already consumed →
  ///    DuplicateMessageException → permanent "[Decryption failed]" on a
  ///    brand-new message (the post-0.0.90 field reports). Reproduced
  ///    deterministically in encryption_encrypt_decrypt_race_probe_test.dart.
  ///
  /// NOT a reentrant mutex: guarded methods must stay leaf-level and never
  /// await another guarded method for the same peer, or they chain behind
  /// themselves and hang. Cross-operation sequencing (ensureSession →
  /// buildSession then encrypt) belongs at the provider layer as separate
  /// sequential acquisitions.
  final Map<int, Future<void>> _sessionTails = {};

  /// Queue [action] behind every in-flight session mutation for [peerId].
  /// Callers run in call order; a failed predecessor never poisons the queue
  /// (errors are contained to the caller that owns them).
  Future<T> _runSessionSerialized<T>(int peerId, Future<T> Function() action) {
    final tail = _sessionTails[peerId] ?? Future<void>.value();
    final result = tail.then((_) => action());
    _sessionTails[peerId] = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// In-flight encrypt count per recipient — the overlap probe. If this is
  /// ever >0 at enqueue, two sends WERE concurrent even if they did not feel
  /// "rapid" (a note send overlapping a resync decrypt, a typing-driven op,
  /// another message). Logged durably so the field report can confirm or rule
  /// out concurrency as the cause of a peer decrypt failure.
  final Map<int, int> _encryptInFlight = {};

  /// Encrypt a plaintext string for the given recipient.
  /// Returns "{type}:{base64_body}" format.
  ///
  /// Serialized per peer with decrypt/buildSession/deleteSession (see
  /// [_sessionTails]): concurrent callers queue in call order.
  Future<String> encrypt(int recipientUserId, String plaintext) {
    final inFlight = _encryptInFlight[recipientUserId] ?? 0;
    if (inFlight > 0) {
      E2ePersistentDiag.record(
          'ENCRYPT_OVERLAP', {'recipientId': recipientUserId, 'inFlight': inFlight});
    }
    _encryptInFlight[recipientUserId] = inFlight + 1;

    final result = _runSessionSerialized(
        recipientUserId, () => _encryptSerialized(recipientUserId, plaintext));
    // Error-swallowed continuation as the decrement hook, so a failed encrypt
    // never leaks an unhandled async error (the owning caller still sees it
    // via `result`).
    result.then<void>((_) {}, onError: (_) {}).whenComplete(() {
      final n = (_encryptInFlight[recipientUserId] ?? 1) - 1;
      if (n <= 0) {
        _encryptInFlight.remove(recipientUserId);
      } else {
        _encryptInFlight[recipientUserId] = n;
      }
    });
    return result;
  }

  Future<String> _encryptSerialized(
      int recipientUserId, String plaintext) async {
    final address =
        SignalProtocolAddress(recipientUserId.toString(), _deviceId);
    final cipher = SessionCipher(_cipherSessionStore, _preKeyStore,
        _signedPreKeyStore, _identityStore, address);

    final ciphertext =
        await cipher.encrypt(Uint8List.fromList(utf8.encode(plaintext)));

    return '${ciphertext.getType()}:${base64Encode(ciphertext.serialize())}';
  }

  /// Decrypt a ciphertext string from the given sender.
  /// Input format: "{type}:{base64_body}".
  ///
  /// Serialized per peer with encrypt/buildSession/deleteSession (see
  /// [_sessionTails]). The provider's per-sender decrypt chain orders the
  /// higher-level cache/persist side effects; THIS lock is the ratchet-record
  /// guard — without it a decrypt store can land over a concurrent encrypt
  /// store and roll the sender chain back.
  Future<String> decrypt(int senderUserId, String ciphertextStr) {
    return _runSessionSerialized(
        senderUserId, () => _decryptSerialized(senderUserId, ciphertextStr));
  }

  Future<String> _decryptSerialized(
      int senderUserId, String ciphertextStr) async {
    final address =
        SignalProtocolAddress(senderUserId.toString(), _deviceId);
    final cipher = SessionCipher(_cipherSessionStore, _preKeyStore,
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

  /// Current identity public key (base64) — the epoch tag sent with one-time
  /// pre-key uploads so the server binds each OTP to this identity and never
  /// serves a stale key from a superseded epoch. Null before init.
  Future<String?> currentIdentityPublicKeyBase64() async {
    if (!_initialized) return null;
    try {
      final keyPair = await _identityStore.getIdentityKeyPair();
      return base64Encode(keyPair.getPublicKey().serialize());
    } catch (_) {
      return null;
    }
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
      final key = _decryptedContentKey(userId, id);
      // Never downgrade a keyed media entry to a keyless one. E2E media keys
      // (mediaKey/mediaIv) are persisted at first successful decrypt and are the
      // ONLY way to replay the message — re-decryption is impossible once the
      // Double Ratchet consumed the message key. A later keyless write (e.g. a
      // transient re-decrypt that throws DuplicateMessage and tries to store
      // "[Decryption failed]") must not destroy them.
      if (data['mediaKey'] == null) {
        final existingRaw = prefs.getString(key);
        if (existingRaw != null) {
          try {
            final existing = jsonDecode(existingRaw) as Map<String, dynamic>;
            if (existing['mediaKey'] != null) return;
          } catch (_) {}
        }
      }
      final payload = jsonEncode(data);
      // A dropped write is how a decrypted message later re-decrypts, throws
      // DuplicateMessage (ratchet key consumed), and becomes a permanent
      // [Decryption failed] (the 2026-07-11 bob210 report — storage was
      // granted-persistent yet the plaintext was gone). setString returns
      // whether the backend commit succeeded (false on quota/exception); a
      // read-back would be vacuous because getString serves the plugin's
      // in-memory cache and matches even when the localStorage write dropped.
      // Retry once on failure, then surface a hard loss instead of swallowing it.
      var ok = false;
      try {
        ok = await prefs.setString(key, payload);
        if (!ok) ok = await prefs.setString(key, payload);
      } catch (_) {
        ok = false; // some backends throw (quota/exception) instead of false
      }
      if (!ok) {
        // Surface the hard loss even when the backend threw — otherwise the
        // outer catch swallows it and the message silently becomes a future
        // DuplicateMessage → permanent [Decryption failed].
        E2ePersistentDiag.record('DECRYPT_PERSIST_FAILED', {'msgId': id});
        return; // don't prune on a failed write
      }
      await _pruneDecryptedContentCache(prefs, userId);
    } catch (_) {}
  }

  /// Retrieve persisted decrypted message content, or null if not found.
  /// Falls back to flutter_secure_storage for entries written by older versions.
  Future<Map<String, dynamic>?> getDecryptedContent(int id) async {
    final userId = _userId;
    if (userId == null) return null;
    final key = _decryptedContentKey(userId, id);
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

  Future<int> clearDecryptedContentCache() async {
    final userId = _userId;
    if (userId == null) return 0;
    final prefix = _decryptedContentPrefix(userId);
    final keysToDelete = <String>{};

    try {
      final prefs = await _sharedPrefs;
      keysToDelete.addAll(prefs.getKeys().where((key) => key.startsWith(prefix)));
      for (final key in keysToDelete) {
        await prefs.remove(key);
      }
    } catch (_) {}

    try {
      final all = await _storage.readAll();
      keysToDelete.addAll(all.keys.where((key) => key.startsWith(prefix)));
      for (final key in all.keys.where((key) => key.startsWith(prefix))) {
        await _storage.delete(key: key);
      }
    } catch (_) {}

    // Pending-send records hold plaintext at rest too — same privacy scope.
    try {
      final prefs = await _sharedPrefs;
      final pendPrefix = _pendingSendPrefix(userId);
      for (final key
          in prefs.getKeys().where((k) => k.startsWith(pendPrefix)).toList()) {
        await prefs.remove(key);
      }
    } catch (_) {}

    return keysToDelete.length;
  }

  // ── Pending-send reconcile store (lost `messageSent` ack) ────────────────
  //
  // A socket drop inside the ack window orphans the sender's plaintext under
  // a tempId: the server row later arrives as '[encrypted]' and a Signal
  // sender CANNOT decrypt its own ciphertext (it is encrypted to the
  // recipient's ratchet) — the 07-08 field case (msg 14667). At SEND_EMIT the
  // emitted ciphertext + plaintext payload are recorded here; the ack
  // consumes the entry; a history merge reconciles an own '[encrypted]' row
  // by EXACT ciphertext equality (unique by ratchet construction). NEVER
  // match heuristically — review rejected timestamp proximity because a
  // wrong match persists the WRONG plaintext under a real id, permanently.
  //
  // Lifecycle: consumed on ack/reconcile, TTL-pruned, capped; wiped by
  // clearAllKeys and clearDecryptedContentCache (plaintext at rest).
  // Deliberately NOT cleared on reconnect — the lost-ack case IS a reconnect.
  //
  // ONE SharedPreferences key PER ciphertext — deliberately NOT a shared JSON
  // map: concurrent burst sends doing read-modify-write on one blob is the
  // same lost-update shape as the _sessionTails bug. Per-key setString/remove
  // needs no serialization at all.

  static const int _pendingSendCap = 40;
  static const Duration _pendingSendTtl = Duration(hours: 72);

  String _pendingSendPrefix(int userId) => 'e2e_${userId}_pendsend_v1_';

  String _pendingSendRecordKey(int userId, String ciphertext) =>
      '${_pendingSendPrefix(userId)}$ciphertext';

  /// Record an emitted send (ciphertext → plaintext payload) for lost-ack
  /// reconciliation. Silent on failure (send must never be blocked by this).
  Future<void> savePendingSendRecord(
      String ciphertext, Map<String, dynamic> data) async {
    final userId = _userId;
    if (userId == null) return;
    try {
      final prefs = await _sharedPrefs;
      final now = DateTime.now().millisecondsSinceEpoch;
      await prefs.setString(
        _pendingSendRecordKey(userId, ciphertext),
        jsonEncode(<String, dynamic>{'at': now, 'data': data}),
      );
      await _prunePendingSendRecords(prefs, userId, now);
    } catch (_) {}
  }

  /// Read a pending-send record WITHOUT consuming it. The reconcile path
  /// peeks, persists under the real id, VERIFIES the persist by read-back
  /// (saveDecryptedContent swallows failures), and only then takes — so a
  /// failed persist leaves the record for the next history pass instead of
  /// destroying the only surviving plaintext copy.
  Future<Map<String, dynamic>?> peekPendingSendRecord(String ciphertext) async {
    final userId = _userId;
    if (userId == null) return null;
    try {
      final prefs = await _sharedPrefs;
      final raw = prefs.getString(_pendingSendRecordKey(userId, ciphertext));
      if (raw == null) return null;
      final entry = jsonDecode(raw);
      final data = entry is Map ? entry['data'] : null;
      return data is Map ? data.cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    }
  }

  /// Consume the pending-send record whose ciphertext equals [ciphertext]
  /// EXACTLY, or null. Removing on read keeps normal acks self-cleaning and
  /// prevents a stale record from ever being applied twice.
  Future<Map<String, dynamic>?> takePendingSendRecord(String ciphertext) async {
    final userId = _userId;
    if (userId == null) return null;
    try {
      final prefs = await _sharedPrefs;
      final key = _pendingSendRecordKey(userId, ciphertext);
      final raw = prefs.getString(key);
      if (raw == null) return null;
      await prefs.remove(key);
      final entry = jsonDecode(raw);
      final data = entry is Map ? entry['data'] : null;
      return data is Map ? data.cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    }
  }

  /// TTL + cap sweep. Concurrent sweeps may double-remove a key — harmless
  /// (remove is idempotent); an entry is never modified in place.
  Future<void> _prunePendingSendRecords(
      SharedPreferences prefs, int userId, int now) async {
    final prefix = _pendingSendPrefix(userId);
    final cutoff = now - _pendingSendTtl.inMilliseconds;
    final live = <MapEntry<String, int>>[];
    for (final key
        in prefs.getKeys().where((k) => k.startsWith(prefix)).toList()) {
      int? at;
      try {
        final entry = jsonDecode(prefs.getString(key) ?? '');
        final v = entry is Map ? entry['at'] : null;
        if (v is int) at = v;
      } catch (_) {}
      if (at == null || at < cutoff) {
        await prefs.remove(key);
      } else {
        live.add(MapEntry(key, at));
      }
    }
    if (live.length > _pendingSendCap) {
      live.sort((a, b) => a.value.compareTo(b.value));
      for (final e in live.take(live.length - _pendingSendCap)) {
        await prefs.remove(e.key);
      }
    }
  }

  /// Clear all E2E encryption keys for this user from storage.
  /// Uses selective deletion (not deleteAll) to avoid wiping non-E2E data.
  Future<void> clearAllKeys() async {
    final userId = _userId;
    if (userId != null) {
      final prefix = 'e2e_${userId}_';
      // DualStorage.readAll() merges both storages
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
            .where((k) => k.startsWith(prefix))
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
    _storage.clearPrefsCache();
    debugPrint('[EncryptionService] All encryption keys cleared');
  }

  String _decryptedContentPrefix(int userId) => 'e2e_${userId}_decrypted_';

  String _decryptedContentKey(int userId, int messageId) =>
      '${_decryptedContentPrefix(userId)}$messageId';

  Future<void> _pruneDecryptedContentCache(
    SharedPreferences prefs,
    int userId,
  ) async {
    if (_decryptedContentCacheLimit <= 0) {
      await clearDecryptedContentCache();
      return;
    }

    final prefix = _decryptedContentPrefix(userId);
    final keys = <String>{
      ...prefs.getKeys().where((key) => key.startsWith(prefix)),
      ...(await _storage.readAll()).keys.where((key) => key.startsWith(prefix)),
    }.toList();
    if (keys.length <= _decryptedContentCacheLimit) return;

    keys.sort((a, b) {
      final aId = int.tryParse(a.substring(prefix.length)) ?? 0;
      final bId = int.tryParse(b.substring(prefix.length)) ?? 0;
      return aId.compareTo(bId);
    });

    final overflow = keys.length - _decryptedContentCacheLimit;
    for (final key in keys.take(overflow)) {
      await prefs.remove(key);
      await _storage.delete(key: key);
    }
  }
}
