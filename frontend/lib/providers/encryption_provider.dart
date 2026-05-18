import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/message_model.dart';
import '../services/encryption_service.dart';

/// EncryptionProvider — owns all E2E encryption state, initialization,
/// key exchange, and session management.
class EncryptionProvider extends ChangeNotifier {
  static void _e2eFlowLog(String step, [Map<String, dynamic>? data]) {
    if (kDebugMode) debugPrint('[E2E-FLOW] $step | ${data ?? {}}');
  }

  // ---------- E2E Encryption State ----------
  final EncryptionService _encryptionService = EncryptionService();
  bool _e2eInitialized = false;
  final Map<int, Completer<Map<String, dynamic>>> _pendingPreKeyFetches = {};
  bool _generatingMoreKeys = false;

  /// User IDs whose sessions should be force-rebuilt on the next ensureSession call.
  final Set<int> _forceSessionRebuild = {};

  /// Cache of decrypted messages by id. Used when history decrypt hits
  /// DuplicateMessageException (session already advanced by live messages).
  final Map<int, MessageModel> _decryptedContentCache = {};

  String? _error;

  /// Callback to emit socket events. Set by [ConnectionProvider] via [setEmitCallback].
  void Function(String event, dynamic data)? _emit;

  int? _currentUserId;

  // ---------- Public Getters ----------

  /// Whether the E2E encryption layer has been initialized for the current user.
  bool get isE2EReady => _e2eInitialized;

  /// Last error from encryption operations, if any.
  String? get error => _error;

  /// Whether more one-time pre-keys are currently being generated.
  bool get isGeneratingMoreKeys => _generatingMoreKeys;

  /// The pending pre-key fetch completers, keyed by recipient user ID.
  Map<int, Completer<Map<String, dynamic>>> get pendingPreKeyFetches =>
      _pendingPreKeyFetches;

  // ---------- Emit Callback ----------

  /// Wire the socket emit callback so EncryptionProvider can send events
  /// without depending on SocketService directly.
  void setEmitCallback(void Function(String event, dynamic data) emit) {
    _emit = emit;
  }

  // ---------- Public Interface ----------

  /// Encrypt plaintext for the given recipient.
  /// Delegates to [EncryptionService.encrypt].
  Future<String> encrypt(int recipientId, String plaintext) async {
    try {
      return await _encryptionService.encrypt(recipientId, plaintext);
    } catch (e) {
      _error = 'Encryption failed: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Decrypt ciphertext from the given sender.
  /// Delegates to [EncryptionService.decrypt].
  Future<String> decrypt(int senderId, String ciphertext) async {
    try {
      return await _encryptionService.decrypt(senderId, ciphertext);
    } catch (e) {
      _error = 'Decryption failed: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Ensure a Signal session exists with [recipientId]. If not, fetches their
  /// pre-key bundle from the server (via emit callback) and builds a session.
  /// Uses a Completer with 10s timeout.
  Future<void> ensureSession(int recipientId) async {
    if (!_e2eInitialized || _currentUserId == null) {
      throw StateError('E2E not initialized or user not authenticated');
    }
    final needsRebuild = _forceSessionRebuild.remove(recipientId);
    final hasSession = await _encryptionService.hasSession(recipientId);
    _e2eFlowLog('SESSION_ENSURE', {'recipientId': recipientId, 'hasSession': hasSession, 'needsRebuild': needsRebuild});
    if (hasSession && !needsRebuild) return;

    // Delete stale session before fetching a fresh bundle (atomic with rebuild).
    if (needsRebuild && hasSession) {
      await _encryptionService.deleteSession(recipientId);
      _e2eFlowLog('SESSION_DELETED_FOR_REBUILD', {'recipientId': recipientId});
    }

    // Check if we already have a pending fetch for this user
    if (_pendingPreKeyFetches.containsKey(recipientId)) {
      await _pendingPreKeyFetches[recipientId]!.future;
      return;
    }

    final completer = Completer<Map<String, dynamic>>();
    _pendingPreKeyFetches[recipientId] = completer;

    _e2eFlowLog('SESSION_FETCH_EMIT', {'recipientId': recipientId});
    _emit?.call('fetchPreKeyBundle', {'userId': recipientId});

    // Wait for the server response with a timeout
    final bundle = await completer.future
        .timeout(const Duration(seconds: 10), onTimeout: () {
      _pendingPreKeyFetches.remove(recipientId);
      throw TimeoutException('Pre-key bundle fetch timed out for user $recipientId');
    });

    await _encryptionService.buildSession(recipientId, bundle);
    debugPrint('[E2E] Session established with userId=$recipientId');
    _e2eFlowLog('SESSION_BUILT', {'recipientId': recipientId});
  }

  /// Whether the session for [recipientId] should be force-rebuilt.
  bool needsSessionRebuild(int recipientId) {
    return _forceSessionRebuild.contains(recipientId);
  }

  /// Remove [recipientId] from the force-rebuild set.
  void clearSessionRebuild(int recipientId) {
    _forceSessionRebuild.remove(recipientId);
  }

  /// Mark [recipientId] for session force-rebuild on next ensureSession.
  void markSessionRebuild(int recipientId) {
    _forceSessionRebuild.add(recipientId);
  }

  /// Delete the local Signal session with [peerUserId] (sender or recipient).
  /// Used when inbound history decrypt fails and the ratchet must be replayed.
  Future<void> deleteSessionWithPeer(int peerUserId) async {
    if (!_e2eInitialized) return;
    await _encryptionService.deleteSession(peerUserId);
  }

  /// Get a previously cached decrypted message by message ID.
  MessageModel? getCachedDecryption(int messageId) {
    return _decryptedContentCache[messageId];
  }

  /// Cache a decrypted message by its ID.
  void cacheDecryption(int messageId, MessageModel msg) {
    _decryptedContentCache[messageId] = msg;
  }

  /// Persist decrypted message content to local cache.
  /// Delegates to [EncryptionService.saveDecryptedContent].
  /// Silent on failure (matches service behavior).
  Future<void> saveDecryptedContent(
      int messageId, Map<String, dynamic> data) async {
    await _encryptionService.saveDecryptedContent(messageId, data);
  }

  /// Retrieve persisted decrypted message content, or null if not cached.
  /// Delegates to [EncryptionService.getDecryptedContent].
  Future<Map<String, dynamic>?> getDecryptedContent(int messageId) async {
    return _encryptionService.getDecryptedContent(messageId);
  }

  /// Clear locally cached decrypted plaintext without deleting Signal keys.
  Future<int> clearLocalDecryptedContentCache() async {
    final removed = await _encryptionService.clearDecryptedContentCache();
    _decryptedContentCache.clear();
    notifyListeners();
    return removed;
  }

  /// Clear a pending pre-key fetch for [recipientId] (e.g. on send failure
  /// so retry gets a fresh fetch).
  void clearPendingPreKeyFetch(int recipientId) {
    _pendingPreKeyFetches.remove(recipientId);
  }

  // ---------- E2E Initialization ----------

  /// Initialize E2E encryption for the current user. On fresh connect,
  /// generates/loads keys and uploads them. On reconnect (same user),
  /// skips re-initialization but still re-uploads the key bundle.
  ///
  /// CLAUDE.md gotcha: skips `_encryptionService.initialize()` when
  /// `_e2eInitialized = true` (reconnect path) to prevent transient
  /// mobile storage errors from setting `_e2eInitialized = false`.
  Future<void> initializeE2E(int userId) async {
    _currentUserId = userId;
    _e2eFlowLog('E2E_INIT_START', {'alreadyInitialized': _e2eInitialized});
    try {
      if (!_e2eInitialized) {
        // Fresh session: load keys from storage (or generate on first install).
        await _encryptionService.initialize(userId);
        _e2eInitialized = true;
        debugPrint('[E2E] Encryption service initialized');
        _e2eFlowLog('E2E_INIT_DONE', {'needsKeyUpload': _encryptionService.needsKeyUpload});
      } else {
        // Reconnect: stores are already valid — skip re-initialization to avoid
        // the window where _identityStore._identityKeyPair is null and to prevent
        // a transient storage error from incorrectly setting _e2eInitialized = false.
        debugPrint('[E2E] Reconnect: skipping re-init, E2E already active');
        _e2eFlowLog('E2E_RECONNECT_SKIP_INIT', {});
      }

      if (_encryptionService.needsKeyUpload) {
        final keys = _encryptionService.getKeysForUpload();
        if (keys != null) {
          _emit?.call('uploadKeyBundle', keys['keyBundle'] as Map<String, dynamic>);
          _emit?.call('uploadOneTimePreKeys', {
            'keys': (keys['oneTimePreKeys'] as List).cast<Map<String, dynamic>>(),
          });
          debugPrint('[E2E] Uploaded key bundle + one-time pre-keys');
          _e2eFlowLog('E2E_KEYS_UPLOADED', {});
        }
      } else {
        // Always re-upload key bundle so server has our keys (e.g. after DB restart).
        final keyBundle = await _encryptionService.getKeyBundleForReupload();
        if (keyBundle != null) {
          _emit?.call('uploadKeyBundle', keyBundle);
          debugPrint('[E2E] Re-uploaded key bundle on connect');
          _e2eFlowLog('E2E_KEYS_REUPLOADED', {});
        } else {
          debugPrint('[E2E] Re-upload skipped: could not build key bundle from storage');
        }
      }
    } catch (e) {
      debugPrint('[E2E] Initialization failed: $e');
      // Only clear the flag if we hadn't initialized yet; don't undo a working
      // reconnect just because the re-upload attempt threw.
      if (!_e2eInitialized) _e2eInitialized = false;
      _e2eFlowLog('E2E_INIT_FAIL', {'error': e.toString()});
    }
  }

  // ---------- Key Exchange Event Handlers ----------

  /// Handler for `keyBundleUploaded` server event.
  void onKeyBundleUploaded(dynamic data) {
    debugPrint('[E2E] Key bundle uploaded to server');
  }

  /// Handler for `oneTimePreKeysUploaded` server event.
  void onOneTimePreKeysUploaded(dynamic data) {
    debugPrint('[E2E] One-time pre-keys uploaded to server');
  }

  /// Handler for `preKeyBundleResponse` server event.
  /// Completes the pending pre-key fetch for the given user.
  void onPreKeyBundleResponse(dynamic data) {
    final map = data as Map<String, dynamic>;
    final userId = map['userId'] as int;
    final bundle = map['bundle'];
    _e2eFlowLog('PREKEY_RESP', {'userId': userId, 'hasBundle': bundle != null && bundle is Map<String, dynamic>});

    final completer = _pendingPreKeyFetches.remove(userId);
    if (completer == null || completer.isCompleted) return;

    if (bundle == null || bundle is! Map<String, dynamic>) {
      completer.completeError(
        StateError('Recipient has no key bundle (userId=$userId)'),
      );
      return;
    }
    completer.complete(bundle);
  }

  /// Handler for `preKeysLow` server event.
  /// Generates more one-time pre-keys and uploads them.
  void onPreKeysLow(dynamic data) {
    if (_generatingMoreKeys) return;
    _generatingMoreKeys = true;
    debugPrint('[E2E] Server reports pre-keys low, generating more...');
    _encryptionService.generateMorePreKeys().then((keys) {
      _emit?.call('uploadOneTimePreKeys', {'keys': keys});
      debugPrint('[E2E] Uploaded ${keys.length} new one-time pre-keys');
    }).catchError((e) {
      debugPrint('[E2E] Failed to generate more pre-keys: $e');
    }).whenComplete(() => _generatingMoreKeys = false);
  }

  /// Handler for `sessionRebuildNeeded` server event.
  /// Marks the session for rebuild on the next ensureSession call.
  void onSessionRebuildNeeded(dynamic data) {
    final fromUserId = (data as Map<String, dynamic>)['fromUserId'] as int;
    // Mark session for rebuild — actual delete happens atomically in ensureSession
    // before the next send, avoiding the race where a hot-path deleteSession
    // wipes a session that encrypt() is about to use.
    _forceSessionRebuild.add(fromUserId);
    _e2eFlowLog('SESSION_REBUILD_RECEIVED', {'fromUserId': fromUserId});
  }

  // ---------- Lifecycle ----------

  /// Called when the socket connects.
  ///
  /// On fresh connect: resets all state.
  /// On reconnect (same user): preserves [_e2eInitialized] to avoid
  /// re-running initialize() which can cause transient mobile storage errors
  /// (CLAUDE.md gotcha: `_initializeE2E()` skips when `_e2eInitialized = true`).
  void onConnect(bool isReconnect) {
    _error = null;
    if (!isReconnect) {
      _e2eInitialized = false;
      _decryptedContentCache.clear();
      _forceSessionRebuild.clear();
      _generatingMoreKeys = false;
      _currentUserId = null;
      _cancelPendingFetches();
    }
    // On reconnect: preserve _e2eInitialized and caches
  }

  /// Called when the socket disconnects.
  ///
  /// Clears pending fetches but does NOT clear keys
  /// (CLAUDE.md: "Keys NOT cleared on logout").
  void onDisconnect() {
    _cancelPendingFetches();
  }

  /// Sets [_e2eInitialized] to true. Called after successful E2E initialization.
  void markE2EInitialized() {
    _e2eInitialized = true;
  }

  /// Full reset — clears all E2E state. Used on logout / account switch.
  /// Does NOT clear persisted keys (use [EncryptionService.clearAllKeys] for that).
  void clearAll() {
    _e2eInitialized = false;
    _generatingMoreKeys = false;
    _error = null;
    _currentUserId = null;
    _decryptedContentCache.clear();
    _forceSessionRebuild.clear();
    _cancelPendingFetches();
    notifyListeners();
  }

  /// Identity key fingerprint for display in Privacy & Safety screen.
  Future<String?> getIdentityFingerprint() =>
      _encryptionService.getIdentityFingerprint();

  /// Clear all E2E encryption keys. Call on account deletion only.
  Future<void> clearEncryptionKeys() async {
    await _encryptionService.clearAllKeys();
    _e2eInitialized = false;
    _pendingPreKeyFetches.clear();
  }

  @override
  void dispose() {
    _cancelPendingFetches();
    super.dispose();
  }

  // ---------- Private Helpers ----------

  void _cancelPendingFetches() {
    for (final completer in _pendingPreKeyFetches.values) {
      if (!completer.isCompleted) {
        completer.completeError('Disconnected');
      }
    }
    _pendingPreKeyFetches.clear();
  }
}
