import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/e2e_diag_log.dart';
import '../utils/e2e_persistent_diag.dart';
import 'encryption/signal_stores.dart';
import 'encryption/session_cross_context_lock.dart';

/// Thrown by [EncryptionService.initialize] when identity material is present
/// but incomplete.
///
/// Initialization fails CLOSED here on purpose: regenerating would mint a new
/// identity and make every peer's history permanently undecryptable, while
/// refusing leaves the surviving bytes on disk where they may still be
/// recoverable. Because that also means E2E never comes up, this is a distinct
/// type — callers must surface it and offer
/// [EncryptionService.regenerateIdentityAfterConfirmedLoss] as an explicit,
/// user-consented way out, NOT treat it as a transient init failure.
class E2eIdentityIncompleteException implements Exception {
  const E2eIdentityIncompleteException();

  @override
  String toString() =>
      'E2eIdentityIncompleteException: identity material is incomplete; '
      'refusing to regenerate without explicit consent';
}

class EncryptionService {
  EncryptionService({
    int decryptedContentCacheLimit = 2000,
    SessionCrossContextLockRunner? sessionCrossContextLock,
  }) : _decryptedContentCacheLimit = decryptedContentCacheLimit,
       _sessionCrossContextLock =
           sessionCrossContextLock ?? runSessionCrossContextLocked;

  /// Batch size for replenishment (preKeysLow). Server threshold is 10.
  static const int _preKeyBatchSize = 100;

  /// Smaller initial batch for fresh install — faster startup, preKeysLow replenishes when low.
  static const int _initialPreKeyBatchSize = 20;
  static const int _deviceId = 1;

  /// DualStorage: platform-branched Signal-key storage (see
  /// encryption/signal_stores.dart). On web, keys live ONLY in
  /// SharedPreferences/localStorage — flutter_secure_storage's IndexedDB+
  /// WebCrypto backing loses data when tabs close or the WebCrypto key is
  /// evicted. On mobile, ONLY flutter_secure_storage (Keychain/Keystore).
  final DualStorage _storage = DualStorage(
    FlutterSecureStorage(webOptions: const WebOptions(dbName: 'FireplaceE2E')),
  );

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

  Future<void> _reloadPrefsForCrossContext(SharedPreferences prefs) async {
    if (kIsWeb) await prefs.reload();
  }

  final int _decryptedContentCacheLimit;
  final SessionCrossContextLockRunner _sessionCrossContextLock;

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
  /// True once [initialize] refused to start because identity material is
  /// incomplete. The only way forward is
  /// [regenerateIdentityAfterConfirmedLoss], which the USER must consent to.
  bool identityIncomplete = false;

  /// Peers whose identity key changed under us this session, surfaced so the
  /// UI can warn instead of silently trusting the new key.
  final Set<int> _peersWithChangedIdentity = <int>{};
  Set<int> get peersWithChangedIdentity =>
      Set.unmodifiable(_peersWithChangedIdentity);

  /// Called when a peer's identity key changes. Set by the provider.
  void Function(int peerId)? onPeerIdentityChanged;

  /// Construct the four Signal stores for prefix [p].
  ///
  /// Single place on purpose: the identity store carries the
  /// peer-identity-change callback, and a second construction site that forgot
  /// it would silently disable the MITM/re-key warning.
  void _buildStores(String p) {
    _identityStore = SecureIdentityKeyStore(
      _storage,
      p,
      onIdentityChanged: (address) {
        final peerId = int.tryParse(address.getName());
        if (peerId == null) return;
        if (!_peersWithChangedIdentity.add(peerId)) return;
        E2ePersistentDiag.record('PEER_IDENTITY_CHANGED', {'peerId': peerId});
        onPeerIdentityChanged?.call(peerId);
      },
    );
    _preKeyStore = SecurePreKeyStore(_storage, p);
    _signedPreKeyStore = SecureSignedPreKeyStore(_storage, p);
    _sessionStore = SecureSessionStore(_storage, p);
    _cipherSessionStore = _sessionStore;
  }

  /// Initialize the encryption service for the given user. Loads keys from
  /// secure storage or generates new ones if this is a fresh install.
  Future<void> initialize(int userId) async {
    _userId = userId;
    final p = 'e2e_${userId}_'; // per-user storage key prefix

    _buildStores(p);

    // A THROWING read propagates: a storage error must never be read as "no
    // keys". Only a definitive absence reaches the generate branch.
    var load = await _identityStore.loadFromStorage();
    if (load == IdentityLoadResult.absent &&
        await _hasPriorInstallResidue(p)) {
      // No identity, yet sessions/prekeys from a previous install survive.
      // That is partial storage loss, not a fresh install.
      load = IdentityLoadResult.partial;
    }

    switch (load) {
      case IdentityLoadResult.loaded:
        debugPrint('[EncryptionService] Loaded existing keys from storage');
        needsKeyUpload = false;
      case IdentityLoadResult.partial:
        E2ePersistentDiag.record('IDENTITY_INCOMPLETE', {'userId': userId});
        debugPrint(
          '[EncryptionService] Identity incomplete — refusing to regenerate',
        );
        identityIncomplete = true;
        throw const E2eIdentityIncompleteException();
      case IdentityLoadResult.absent:
        debugPrint('[EncryptionService] Generating new keys (fresh install)');
        await _generateKeys();
        needsKeyUpload = true;
    }

    _initialized = true;
  }

  /// True when storage still holds Signal material from a previous install of
  /// this account — sessions, prekeys, or the prekey counter. Identity absent
  /// while these survive means partial loss, and regenerating would strand
  /// every one of those sessions.
  ///
  /// Only consulted after [SecureIdentityKeyStore.loadFromStorage] returned
  /// `absent`, which already proves the identity reads themselves succeeded —
  /// storage is broadly working. A throwing `readAll` is therefore
  /// INCONCLUSIVE, not evidence of residue: biasing it to `true` would brick
  /// genuine fresh installs on a transient error and prompt a "your keys are
  /// damaged" recovery at a user who has no keys and nothing to lose. Retry
  /// once, then treat it as a fresh install and leave a forensic trail. The
  /// primary guard against partial loss is `loadFromStorage` returning
  /// `partial`, which never depends on this check.
  Future<bool> _hasPriorInstallResidue(String prefix) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final all = await _storage.readAll();
        for (final key in all.keys) {
          if (!key.startsWith(prefix)) continue;
          final suffix = key.substring(prefix.length);
          if (suffix.startsWith('session_') ||
              suffix.startsWith('pre_key_') ||
              suffix.startsWith('signed_pre_key_') ||
              suffix == 'next_pre_key_id') {
            return true;
          }
        }
        return false;
      } catch (_) {
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }
    }
    E2ePersistentDiag.record('IDENTITY_RESIDUE_UNKNOWN', {'prefix': prefix});
    return false;
  }

  /// DESTRUCTIVE, USER-CONSENTED. Mint a brand-new identity after the user has
  /// been told the stored one is damaged.
  ///
  /// What is actually lost: every existing Signal session, so NO ciphertext can
  /// be decrypted from here on — any message whose plaintext was never cached
  /// is gone for good, and peers must re-key. What survives: the decrypted
  /// plaintext cache is deliberately NOT deleted, so history this device
  /// already decrypted stays readable. Say exactly that in the consent dialog;
  /// do not promise total loss.
  ///
  /// This is the escape hatch for [E2eIdentityIncompleteException]: the guard
  /// in [initialize] deliberately refuses to do this on its own, because doing
  /// it silently IS the data-loss bug. Old sessions and prekeys are cleared
  /// first — leaving them would strand the new identity against ratchets no
  /// peer can follow.
  Future<void> regenerateIdentityAfterConfirmedLoss(int userId) async {
    _userId = userId;
    final p = 'e2e_${userId}_';
    E2ePersistentDiag.record('IDENTITY_REGEN_CONSENTED', {'userId': userId});

    try {
      final all = await _storage.readAll();
      for (final key in all.keys.toList()) {
        if (!key.startsWith(p)) continue;
        final suffix = key.substring(p.length);
        final isSignalMaterial =
            suffix.startsWith('session_') ||
            suffix.startsWith('pre_key_') ||
            suffix.startsWith('signed_pre_key_') ||
            suffix.startsWith('trusted_identity_') ||
            suffix.startsWith('identity_') ||
            suffix == 'registration_id' ||
            suffix == 'next_pre_key_id';
        if (isSignalMaterial) {
          await _storage.delete(key: key);
        }
      }
    } catch (_) {}

    _buildStores(p);
    _peersWithChangedIdentity.clear();

    await _generateKeys();
    needsKeyUpload = true;
    identityIncomplete = false;
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
    await _signedPreKeyStore.storeSignedPreKey(signedPreKey.id, signedPreKey);

    // Generate one-time pre-keys (smaller batch for fast startup; preKeysLow replenishes)
    final preKeys = generatePreKeys(0, _initialPreKeyBatchSize);
    await Future.wait(preKeys.map((pk) => _preKeyStore.storePreKey(pk.id, pk)));

    // Save next pre-key id
    await _storage.write(
      key: 'e2e_${uid}_next_pre_key_id',
      value: _initialPreKeyBatchSize.toString(),
    );

    // Prepare public data for server upload
    _keysForUpload = {
      'keyBundle': {
        'registrationId': registrationId,
        'identityPublicKey': base64Encode(
          identityKeyPair.getPublicKey().serialize(),
        ),
        'signedPreKeyId': signedPreKey.id,
        'signedPreKeyPublic': base64Encode(
          signedPreKey.getKeyPair().publicKey.serialize(),
        ),
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
        '[EncryptionService] Session deleted for userId=$userId (broken session reset)',
      );
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
      userId,
      () => _buildSessionSerialized(userId, preKeyBundle),
    );
  }

  Future<void> _buildSessionSerialized(
    int userId,
    Map<String, dynamic> preKeyBundle,
  ) async {
    final address = SignalProtocolAddress(userId.toString(), _deviceId);
    final builder = SessionBuilder(
      _cipherSessionStore,
      _preKeyStore,
      _signedPreKeyStore,
      _identityStore,
      address,
    );

    ECPublicKey? oneTimePreKey;
    if (preKeyBundle['oneTimePreKeyPublic'] != null) {
      oneTimePreKey = Curve.decodePoint(
        base64Decode(preKeyBundle['oneTimePreKeyPublic'] as String),
        0,
      );
    }

    final identityKey = IdentityKey.fromBytes(
      base64Decode(preKeyBundle['identityPublicKey'] as String),
      0,
    );
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
        base64Decode(preKeyBundle['signedPreKeyPublic'] as String),
        0,
      ),
      Uint8List.fromList(
        base64Decode(preKeyBundle['signedPreKeySignature'] as String),
      ),
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

  String _sessionLockName(int peerId) {
    final userId = _userId;
    if (userId == null) {
      throw StateError('EncryptionService is not initialized');
    }
    return 'fireplace-e2e-session-$userId-$peerId';
  }

  /// Queue [action] behind every in-flight mutation in this app engine, then
  /// take the origin-wide Web Lock for the same account/peer. The browser lock
  /// is load-bearing: separate PWA tabs have separate Dart heaps and therefore
  /// separate [_sessionTails], but they mutate the same persisted SessionRecord.
  Future<T> _runSessionSerialized<T>(int peerId, Future<T> Function() action) {
    final tail = _sessionTails[peerId] ?? Future<void>.value();
    final result = tail.then(
      (_) => _sessionCrossContextLock(_sessionLockName(peerId), action),
    );
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
      E2ePersistentDiag.record('ENCRYPT_OVERLAP', {
        'recipientId': recipientUserId,
        'inFlight': inFlight,
      });
    }
    _encryptInFlight[recipientUserId] = inFlight + 1;

    final result = _runSessionSerialized(
      recipientUserId,
      () => _encryptSerialized(recipientUserId, plaintext),
    );
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
    int recipientUserId,
    String plaintext,
  ) async {
    final address = SignalProtocolAddress(
      recipientUserId.toString(),
      _deviceId,
    );
    final cipher = SessionCipher(
      _cipherSessionStore,
      _preKeyStore,
      _signedPreKeyStore,
      _identityStore,
      address,
    );

    final ciphertext = await cipher.encrypt(
      Uint8List.fromList(utf8.encode(plaintext)),
    );

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
  Future<String> decrypt(
    int senderUserId,
    String ciphertextStr, {
    int? messageId,
  }) {
    return _runSessionSerialized(senderUserId, () async {
      if (messageId != null) {
        final replay = await _loadRawDecryptedContent(messageId, ciphertextStr);
        if (replay != null) {
          E2eDiagLog.add('DECRYPT_RAW_REPLAY', {
            'msgId': messageId,
            'senderId': senderUserId,
          });
          return replay;
        }
      }

      final plaintext = await _decryptSerialized(senderUserId, ciphertextStr);
      if (messageId != null) {
        await _saveRawDecryptedContent(messageId, ciphertextStr, plaintext);
      }
      return plaintext;
    });
  }

  Future<String> _decryptSerialized(
    int senderUserId,
    String ciphertextStr,
  ) async {
    final address = SignalProtocolAddress(senderUserId.toString(), _deviceId);
    final cipher = SessionCipher(
      _cipherSessionStore,
      _preKeyStore,
      _signedPreKeyStore,
      _identityStore,
      address,
    );

    final colonIdx = ciphertextStr.indexOf(':');
    final type = int.parse(ciphertextStr.substring(0, colonIdx));
    final body = base64Decode(ciphertextStr.substring(colonIdx + 1));

    Uint8List plaintext;
    if (type == CiphertextMessage.prekeyType) {
      plaintext = await cipher.decrypt(PreKeySignalMessage(body));
    } else {
      plaintext = await cipher.decryptFromSignal(
        SignalMessage.fromSerialized(body),
      );
    }

    return utf8.decode(plaintext);
  }

  /// Generate more one-time pre-keys and return them for server upload.
  ///
  /// Serialized origin-wide. The whole body is a read-modify-write of
  /// `next_pre_key_id`, and same-origin PWA engines share that counter: two
  /// engines both handling `preKeysLow` could both read `next=20`, both mint
  /// ids 20..119 with DIFFERENT private halves, and both upload. The last
  /// local write wins, so the server ends up serving a public prekey whose
  /// private half this device overwrote — and the peer who draws it gets a
  /// bad-MAC session that no retry can fix.
  ///
  /// Its own lock name, never the per-peer session lock: this touches no
  /// SessionRecord, and reusing the session name would serialize prekey
  /// generation against unrelated conversations. Same shape as the existing
  /// raw-replay lock. Leaf-level, like every other guarded body — it must not
  /// call into a session-locked method.
  Future<List<Map<String, dynamic>>> generateMorePreKeys() {
    final uid = _userId;
    if (uid == null) return Future.value(const <Map<String, dynamic>>[]);
    return _sessionCrossContextLock(
      'fireplace-e2e-prekeys-$uid',
      () => _generateMorePreKeysLocked(uid),
    );
  }

  Future<List<Map<String, dynamic>>> _generateMorePreKeysLocked(int uid) async {
    final nextIdStr = await _storage.read(key: 'e2e_${uid}_next_pre_key_id');
    final storedNext = int.tryParse(nextIdStr ?? '');
    // If the counter was lost but pre-keys survive, derive the next id from the
    // highest stored key so we never reuse an id — reusing one overwrites a live
    // pre-key's private half while its public half is already on the server.
    final nextId = storedNext ?? (await _highestStoredPreKeyId()) + 1;

    final preKeys = generatePreKeys(nextId, _preKeyBatchSize);
    // Parallel writes (chunked to avoid overwhelming secure storage)
    const chunkSize = 25;
    for (var i = 0; i < preKeys.length; i += chunkSize) {
      final chunk = preKeys.skip(i).take(chunkSize).toList();
      await Future.wait(chunk.map((pk) => _preKeyStore.storePreKey(pk.id, pk)));
    }

    await _storage.write(
      key: 'e2e_${uid}_next_pre_key_id',
      value: (nextId + _preKeyBatchSize).toString(),
    );

    debugPrint(
      '[EncryptionService] Generated ${preKeys.length} more pre-keys (nextId=${nextId + _preKeyBatchSize})',
    );

    return preKeys.map(_preKeyToUploadFormat).toList();
  }

  /// Highest stored one-time pre-key id for the current user, or
  /// [_initialPreKeyBatchSize] - 1 when none are found. Used only as the
  /// fallback when the persisted next-id counter is missing, to avoid reusing a
  /// pre-key id (which would strand the recipient on an unusable OTP).
  Future<int> _highestStoredPreKeyId() async {
    final uid = _userId;
    if (uid == null) return _initialPreKeyBatchSize - 1;
    final prefix = 'e2e_${uid}_pre_key_';
    var maxId = -1;
    try {
      final all = await _storage.readAll();
      for (final key in all.keys) {
        if (!key.startsWith(prefix)) continue;
        final id = int.tryParse(key.substring(prefix.length));
        if (id != null && id > maxId) maxId = id;
      }
    } catch (_) {}
    return maxId < 0 ? _initialPreKeyBatchSize - 1 : maxId;
  }

  /// Get the identity key fingerprint (for display in Privacy & Safety).
  Future<String?> getIdentityFingerprint() async {
    if (!_initialized) return null;
    final keyPair = await _identityStore.getIdentityKeyPair();
    final bytes = keyPair.getPublicKey().serialize();
    // Format as hex groups of 4 for readability
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
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
        'signedPreKeyPublic': base64Encode(
          signedPreKey.getKeyPair().publicKey.serialize(),
        ),
        'signedPreKeySignature': base64Encode(signedPreKey.signature),
      };
    } catch (e) {
      debugPrint('[EncryptionService] getKeyBundleForReupload failed: $e');
      return null;
    }
  }

  /// A Signal decrypt consumes a one-shot ratchet key before the provider can
  /// parse and persist the envelope. Keep a bounded raw replay under the
  /// message id while still holding the cross-context session lock. Exact
  /// ciphertext matching makes retention safe across edits and closes both the
  /// multi-engine duplicate and post-decrypt app-termination windows.
  Future<void> _saveRawDecryptedContent(
    int messageId,
    String ciphertext,
    String plaintext,
  ) async {
    final userId = _userId;
    if (userId == null) return;
    try {
      await _sessionCrossContextLock(
        'fireplace-e2e-raw-replay-$userId',
        () async {
          final prefs = await _sharedPrefs;
          await _reloadPrefsForCrossContext(prefs);
          final key = _rawDecryptedContentKey(userId, messageId);
          final payload = jsonEncode({
            'ciphertext': ciphertext,
            'plaintext': plaintext,
          });
          var ok = await prefs.setString(key, payload);
          if (!ok) ok = await prefs.setString(key, payload);
          if (!ok) {
            E2ePersistentDiag.record('DECRYPT_RAW_PERSIST_FAILED', {
              'msgId': messageId,
            });
            return;
          }
          await _pruneRawDecryptedContent(prefs, userId);
        },
      );
    } catch (_) {
      E2ePersistentDiag.record('DECRYPT_RAW_PERSIST_FAILED', {
        'msgId': messageId,
      });
    }
  }

  Future<String?> _loadRawDecryptedContent(
    int messageId,
    String ciphertext,
  ) async {
    final userId = _userId;
    if (userId == null) return null;
    try {
      final prefs = await _sharedPrefs;
      await _reloadPrefsForCrossContext(prefs);
      final raw = prefs.getString(_rawDecryptedContentKey(userId, messageId));
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['ciphertext'] != ciphertext) return null;
      return decoded['plaintext'] as String?;
    } catch (_) {
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
      await _reloadPrefsForCrossContext(prefs);
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
  /// On mobile, falls back to flutter_secure_storage for entries written by
  /// older versions ([_legacyDecryptedContentFallback]).
  Future<Map<String, dynamic>?> getDecryptedContent(int id) async {
    final userId = _userId;
    if (userId == null) return null;
    final key = _decryptedContentKey(userId, id);
    try {
      // Legacy SharedPreferences caches per engine. Reload before every read so
      // plaintext written by another PWA tab is visible immediately.
      final prefs = await _sharedPrefs;
      await _reloadPrefsForCrossContext(prefs);
      final raw = prefs.getString(key);
      if (raw != null) return jsonDecode(raw) as Map<String, dynamic>;
      final oldRaw = await _legacyDecryptedContentFallback(key);
      if (oldRaw != null) return jsonDecode(oldRaw) as Map<String, dynamic>;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Legacy plaintext-cache fallback for entries written by older app versions.
  ///
  /// MOBILE ONLY, and provably so: [saveDecryptedContent] has only ever written
  /// through the raw [SharedPreferences] namespace, while [DualStorage.read]
  /// routes web reads to the `sig_`-prefixed async store. A
  /// `e2e_<uid>_decrypted_<id>` key therefore cannot exist there, so on web
  /// this lookup could only ever return null — at the cost of a full
  /// localStorage key enumeration per call (SharedPreferencesAsyncWeb filters
  /// its allowList only AFTER materialising every key). Rows with no persisted
  /// plaintext — terminal failures above all — miss on EVERY chat entry, so
  /// that was a recurring cost for a guaranteed null.
  Future<String?> _legacyDecryptedContentFallback(String key) async {
    if (kIsWeb) return null;
    return _storage.read(key: key);
  }

  /// Batched sibling of [getDecryptedContent]: resolves many message ids while
  /// paying the cross-engine coherence reload exactly ONCE.
  ///
  /// WHY THIS IS SAFE — read before "simplifying" it. The plaintext cache is
  /// itself a cross-engine coherence surface, NOT just a UI convenience: if
  /// another PWA engine persisted plaintext for a row and this engine's prefs
  /// snapshot is stale, we miss the cache, live-decrypt a ciphertext whose
  /// ratchet key the other engine already consumed, and land on
  /// DuplicateMessage -> "[Decryption failed]". That is exactly why
  /// [getDecryptedContent] reloads, and why deleting the reload is NOT the
  /// optimisation to make. Batching keeps the guarantee because:
  ///   * one reload at the head of the pass makes everything another engine
  ///     wrote BEFORE the pass visible to every row in it; and
  ///   * anything another engine writes DURING the pass is still caught by the
  ///     raw replay cache, which keeps its own reload
  ///     ([_loadRawDecryptedContent]) and is written before the peer-session
  ///     lock is released — bounded by [_rawDecryptedContentCacheLimit] (40)
  ///     records, i.e. the other engine would have to decrypt >40 messages
  ///     inside our pass to slip past both layers.
  /// A MISS IS NOT AN ANSWER. This reads the SharedPreferences namespace only,
  /// so callers must treat an absent id as "unknown" and fall through to
  /// [getDecryptedContent] (which also serves the mobile legacy store).
  /// Reading a miss as "no plaintext" would strand a row on "[encrypted]".
  /// Keeping the legacy store out of the batch is deliberate: on mobile that
  /// is a Keychain/Keystore hit per id, and a whole-pass prefetch would pay it
  /// for every row instead of only the rows that actually need it.
  Future<Map<int, Map<String, dynamic>>> getDecryptedContentMany(
    Iterable<int> ids,
  ) async {
    final userId = _userId;
    final result = <int, Map<String, dynamic>>{};
    if (userId == null) return result;
    final wanted = ids.toSet();
    if (wanted.isEmpty) return result;
    try {
      final prefs = await _sharedPrefs;
      await _reloadPrefsForCrossContext(prefs);
      for (final id in wanted) {
        final raw = prefs.getString(_decryptedContentKey(userId, id));
        if (raw == null) continue;
        try {
          result[id] = jsonDecode(raw) as Map<String, dynamic>;
        } catch (_) {
          // Corrupt record: leave the id absent so the caller falls through to
          // the authoritative single read.
        }
      }
    } catch (_) {
      return result;
    }
    return result;
  }

  Future<int> clearDecryptedContentCache() async {
    final userId = _userId;
    if (userId == null) return 0;
    final prefix = _decryptedContentPrefix(userId);
    final keysToDelete = <String>{};

    try {
      final prefs = await _sharedPrefs;
      await _reloadPrefsForCrossContext(prefs);
      keysToDelete.addAll(
        prefs.getKeys().where((key) => key.startsWith(prefix)),
      );
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

    try {
      final prefs = await _sharedPrefs;
      await _reloadPrefsForCrossContext(prefs);
      final rawPrefix = _rawDecryptedContentPrefix(userId);
      for (final key
          in prefs
              .getKeys()
              .where((key) => key.startsWith(rawPrefix))
              .toList()) {
        await prefs.remove(key);
      }
    } catch (_) {}

    // Pending-send records are required for lost-ack reconciliation and are
    // not part of the user-facing audio-cache action.
    try {
      final prefs = await _sharedPrefs;
      await _reloadPrefsForCrossContext(prefs);
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
    String ciphertext,
    Map<String, dynamic> data,
  ) async {
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
    SharedPreferences prefs,
    int userId,
    int now,
  ) async {
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
        await _reloadPrefsForCrossContext(prefs);
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

  String _rawDecryptedContentPrefix(int userId) =>
      'e2e_${userId}_decrypt_raw_v1_';
  static const int _rawDecryptedContentCacheLimit = 40;

  String _rawDecryptedContentKey(int userId, int messageId) =>
      '${_rawDecryptedContentPrefix(userId)}$messageId';

  Future<void> _pruneRawDecryptedContent(
    SharedPreferences prefs,
    int userId,
  ) async {
    final prefix = _rawDecryptedContentPrefix(userId);
    final keys = prefs
        .getKeys()
        .where((key) => key.startsWith(prefix))
        .toList();
    if (keys.length <= _rawDecryptedContentCacheLimit) return;
    keys.sort((a, b) {
      final aId = int.tryParse(a.substring(prefix.length)) ?? 0;
      final bId = int.tryParse(b.substring(prefix.length)) ?? 0;
      return aId.compareTo(bId);
    });
    for (final key in keys.take(keys.length - _rawDecryptedContentCacheLimit)) {
      await prefs.remove(key);
    }
  }

  Future<void> _pruneDecryptedContentCache(
    SharedPreferences prefs,
    int userId,
  ) async {
    await _reloadPrefsForCrossContext(prefs);
    if (_decryptedContentCacheLimit <= 0) {
      await clearDecryptedContentCache();
      return;
    }

    final prefix = _decryptedContentPrefix(userId);
    final keys = <String>{
      ...prefs.getKeys().where((key) => key.startsWith(prefix)),
      // Legacy store, mobile only. On web DualStorage reads the `sig_`-prefixed
      // async namespace, which never held a `_decryptedContentKey`, so this
      // matched nothing while decoding EVERY value in localStorage
      // (SharedPreferencesAsyncWeb.getPreferences has no prefix filter) — on
      // every single saveDecryptedContent. Measured ~2.5 ms per persisted
      // message at the 2000-record cap, all of it for an empty set.
      if (!kIsWeb)
        ...(await _storage.readAll()).keys.where(
          (key) => key.startsWith(prefix),
        ),
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
