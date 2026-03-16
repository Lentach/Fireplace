import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/message_model.dart';
import '../services/encryption_service.dart';

/// EncryptionProvider — owns all E2E encryption state.
///
/// This is a skeleton extracted from ChatProvider. ChatProvider still owns the
/// actual E2E logic until the full migration (Task 2.3). This provider holds
/// the state fields and exposes a clean public interface.
class EncryptionProvider extends ChangeNotifier {
  // ---------- E2E Encryption State ----------
  final EncryptionService _encryptionService = EncryptionService();
  bool _e2eInitialized = false;
  final Map<int, Completer<Map<String, dynamic>?>> _pendingPreKeyFetches = {};
  bool _generatingMoreKeys = false;

  /// User IDs whose sessions should be force-rebuilt on the next ensureSession call.
  final Set<int> _forceSessionRebuild = {};

  /// Cache of decrypted messages by id. Used when history decrypt hits
  /// DuplicateMessageException (session already advanced by live messages).
  final Map<int, MessageModel> _decryptedContentCache = {};

  String? _error;

  // ---------- Public Getters ----------

  /// Whether the E2E encryption layer has been initialized for the current user.
  bool get isE2EReady => _e2eInitialized;

  /// Last error from encryption operations, if any.
  String? get error => _error;

  /// Direct access to the underlying EncryptionService for internals that
  /// haven't been fully extracted yet.
  EncryptionService get encryptionService => _encryptionService;

  /// Whether more one-time pre-keys are currently being generated.
  bool get isGeneratingMoreKeys => _generatingMoreKeys;
  set isGeneratingMoreKeys(bool value) {
    _generatingMoreKeys = value;
  }

  /// The pending pre-key fetch completers, keyed by recipient user ID.
  Map<int, Completer<Map<String, dynamic>?>> get pendingPreKeyFetches =>
      _pendingPreKeyFetches;

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

  /// Placeholder for session establishment logic.
  /// Will be filled in Task 2.3 when the actual logic is moved from ChatProvider.
  Future<void> ensureSession(int recipientId) async {
    // TODO: Move _ensureSession logic from ChatProvider (Task 2.3)
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

  /// Get a previously cached decrypted message by message ID.
  MessageModel? getCachedDecryption(int messageId) {
    return _decryptedContentCache[messageId];
  }

  /// Cache a decrypted message by its ID.
  void cacheDecryption(int messageId, MessageModel msg) {
    _decryptedContentCache[messageId] = msg;
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
    _decryptedContentCache.clear();
    _forceSessionRebuild.clear();
    _cancelPendingFetches();
    notifyListeners();
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
