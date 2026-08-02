import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/message_model.dart';
import '../services/audio_cache_store.dart';
import '../services/encryption_service.dart';
import '../services/server_clock.dart';
import '../utils/e2e_diag_log.dart';
import '../utils/e2e_persistent_diag.dart';
import '../utils/message_expiry.dart' show kExpiryPurgeGrace;
import '../utils/storage_persist.dart';

/// EncryptionProvider — owns all E2E encryption state, initialization,
class EncryptionProvider extends ChangeNotifier {
  EncryptionProvider({EncryptionService? service})
    : _encryptionService = service ?? EncryptionService();

  static void _e2eFlowLog(String step, [Map<String, dynamic>? data]) {
    E2eDiagLog.add(step, data ?? {});
    if (kDebugMode) debugPrint('[E2E-FLOW] $step | ${data ?? {}}');
  }

  // ---------- E2E Encryption State ----------
  final EncryptionService _encryptionService;
  bool _e2eInitialized = false;
  final Map<int, Completer<Map<String, dynamic>>> _pendingPreKeyFetches = {};
  bool _generatingMoreKeys = false;

  /// User IDs whose sessions should be force-rebuilt on the next ensureSession call.
  final Set<int> _forceSessionRebuild = {};

  /// Cache of decrypted messages by id. Used when history decrypt hits
  /// DuplicateMessageException (session already advanced by live messages).
  final Map<int, MessageModel> _decryptedContentCache = {};

  /// Ids whose plaintext retention destroyed while the server may STILL serve
  /// the row. Mirrors the persisted set; see [isRetired].
  final Set<int> _retiredIds = {};

  /// Ids whose plaintext was successfully persisted at least once. Mirrors the
  /// persisted ledger; see [wasDecryptedBefore].
  final Set<int> _decryptedLedger = {};

  String? _error;

  /// Callback to emit socket events. Set by [ConnectionProvider] via [setEmitCallback].
  void Function(String event, dynamic data)? _emit;

  int? _currentUserId;

  /// Called after E2E init/re-upload completes so [MessagingProvider] can retry history decrypt.
  void Function()? onE2EReady;

  // ---------- Public Getters ----------

  /// Whether the E2E encryption layer has been initialized for the current user.
  bool get isE2EReady => _e2eInitialized;

  /// Last error from encryption operations, if any.
  String? get error => _error;

  /// Whether more one-time pre-keys are currently being generated.
  bool get isGeneratingMoreKeys => _generatingMoreKeys;

  /// True when this session generated a brand-new Signal identity (fresh install or
  /// storage loss). All messages encrypted for the old identity are unrecoverable.
  bool get hadIdentityReset => _encryptionService.needsKeyUpload;

  /// True when initialization REFUSED to start because the stored identity is
  /// damaged (present but incomplete). E2E is down and stays down until the
  /// user consents to [recoverFromIncompleteIdentity]. Distinct from a
  /// transient init failure precisely so the UI can say so and offer the way
  /// out instead of looping forever on `[encrypted]`.
  bool get identityIncomplete => _identityIncomplete;
  bool _identityIncomplete = false;

  /// Peers whose Signal identity key changed under us. A reinstall looks
  /// identical to a server swapping the bundle, so the user is told rather
  /// than silently re-trusted.
  Set<int> get peersWithChangedIdentity =>
      _encryptionService.peersWithChangedIdentity;

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

  /// Decrypt ciphertext from the given sender. [messageId] binds the
  /// one-shot Signal decrypt to its durable raw replay record.
  /// Delegates to [EncryptionService.decrypt].
  Future<String> decrypt(
    int senderId,
    String ciphertext, {
    int? messageId,
  }) async {
    try {
      return await _encryptionService.decrypt(
        senderId,
        ciphertext,
        messageId: messageId,
      );
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
    _e2eFlowLog('SESSION_ENSURE', {
      'recipientId': recipientId,
      'hasSession': hasSession,
      'needsRebuild': needsRebuild,
    });
    if (hasSession && !needsRebuild) return;

    // Rebuild = build OVER the existing record, never delete it first.
    // libsignal's processPreKeyBundle archives the current ratchet state
    // itself (libsignal_protocol_dart 0.7.4 session_builder.dart:139) and
    // persists the record in one storeSession write, so the peer's in-flight
    // messages on the old state still decrypt via the archived-states
    // iteration in decryptFromSignal. The deleteSession that used to live
    // here wiped current + all 40 archived states and turned every in-flight
    // old-session message into a permanent Bad-MAC loss (msg 8489 class).
    if (needsRebuild && hasSession) {
      _e2eFlowLog('SESSION_ARCHIVED_FOR_REBUILD', {'recipientId': recipientId});
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
    final bundle = await completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        _pendingPreKeyFetches.remove(recipientId);
        throw TimeoutException(
          'Pre-key bundle fetch timed out for user $recipientId',
        );
      },
    );

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

  /// Whether a Signal session exists with [peerUserId]. Diagnostic + policy
  /// input; false when E2E is not initialized.
  Future<bool> hasSessionWith(int peerUserId) async {
    if (!_e2eInitialized) return false;
    return _encryptionService.hasSession(peerUserId);
  }

  /// Delete the local Signal session with [peerUserId] (sender or recipient).
  ///
  /// DANGER: this wipes the current AND archived ratchet states, making every
  /// message the peer already encrypted with them permanently undecryptable.
  /// The inbound decrypt-failure path must never call this (see
  /// `_retryDecryptForPeers`); session replacement on send goes through
  /// [ensureSession]'s atomic rebuild instead.
  Future<void> deleteSessionWithPeer(int peerUserId) async {
    if (!_e2eInitialized) return;
    _e2eFlowLog('SESSION_DELETE', {'peerId': peerUserId});
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

  /// Drop the in-RAM decrypted entry for [messageId] so the next decrypt pass
  /// re-decrypts (used when a message is edited and its ciphertext changes).
  ///
  /// Also clears the decrypt-ledger entry, and that is load-bearing: an edit
  /// puts NEW ciphertext under an id the ledger has already seen. Leaving the
  /// entry would make [wasDecryptedBefore] veto the decrypt of a payload that
  /// has genuinely never been decrypted, and the edit would render "no longer
  /// stored" forever.
  void invalidateDecryptionCache(int messageId) {
    _decryptedContentCache.remove(messageId);
    _decryptedLedger.remove(messageId);
    _encryptionService.forgetDecrypted(messageId).ignore();
  }

  /// Persist decrypted message content to local cache.
  /// Delegates to [EncryptionService.saveDecryptedContent].
  /// Silent on failure (matches service behavior).
  Future<void> saveDecryptedContent(
    int messageId,
    Map<String, dynamic> data, {
    int? conversationId,
    DateTime? createdAt,
    DateTime? expiresAt,
    int? disappearAfterSeconds,
  }) async {
    await _encryptionService.saveDecryptedContent(
      messageId,
      data,
      conversationId: conversationId,
      createdAt: createdAt,
      expiresAt: expiresAt,
      disappearAfterSeconds: disappearAfterSeconds,
    );
  }

  /// Keep a stored record's expiry deadline authoritative after the server
  /// assigns one. Delegates to [EncryptionService.stampRecordExpiry].
  Future<void> stampRecordExpiry(int messageId, DateTime expiresAt) async {
    await _encryptionService.stampRecordExpiry(messageId, expiresAt);
  }

  /// True when [messageId]'s plaintext was destroyed by RETENTION while the
  /// server may still serve the row.
  ///
  /// Such a row must never enter the decrypt path: its ratchet key was consumed
  /// at first decrypt, so a retry lands on DuplicateMessage and renders as
  /// "[Decryption failed]" — a data-loss alarm for something the app did on
  /// purpose. Callers show a deliberate "no longer stored on this device"
  /// state instead.
  bool isRetired(int messageId) => _retiredIds.contains(messageId);

  /// Load the persisted retired-id set into memory. Called once per session,
  /// before the first history pass can try to decrypt anything.
  Future<void> loadRetiredIds() async {
    final ids = await _encryptionService.retiredMessageIds();
    _retiredIds
      ..clear()
      ..addAll(ids);
  }

  /// True when [messageId]'s plaintext was persisted at least once, so a
  /// missing record means it was LOST rather than never decrypted.
  ///
  /// The distinction is the whole point: retrying a lost row re-runs Signal
  /// decrypt against a consumed ratchet key, which throws DuplicateMessage and
  /// burns the row into a permanent "[Decryption failed]". A ledger hit means
  /// the app can say "no longer available, ask the sender to resend" instead
  /// of destroying the row to find out.
  bool wasDecryptedBefore(int messageId) =>
      _decryptedLedger.contains(messageId);

  /// Load the persisted ledger. Sits beside [loadRetiredIds] and must complete
  /// before the first history pass, or that pass makes exactly the mistake the
  /// ledger exists to prevent.
  Future<void> loadDecryptedLedger() async {
    final ids = await _encryptionService.decryptedLedgerIds();
    _decryptedLedger
      ..clear()
      ..addAll(ids);
  }

  /// Persist ids buffered during a decrypt pass. Called at pass boundaries.
  Future<void> flushDecryptedLedger() =>
      _encryptionService.flushDecryptedLedger();

  /// Record that [messageId] is known-lost so later passes short-circuit
  /// without re-deriving it, and the state survives a restart.
  Future<void> retireLostMessage(int messageId) async {
    _retiredIds.add(messageId);
    await _encryptionService.markRetired(<int>[messageId]);
  }

  /// Destroy the local plaintext for every message stored under
  /// [conversationIds] — not only the rows currently loaded in memory.
  Future<PlaintextPurgeResult> purgeConversations(
    Iterable<int> conversationIds, {
    Iterable<String> ciphertexts = const <String>[],
  }) async {
    final ids = await _encryptionService.messageIdsForConversations(
      conversationIds,
    );
    if (ids.isEmpty && ciphertexts.isEmpty) {
      return const PlaintextPurgeResult.empty();
    }
    return purgeLocalPlaintext(ids, ciphertexts: ciphertexts);
  }

  /// Destroy plaintext whose message has expired, or aged past retention.
  ///
  /// No-op unless the server clock can be confirmed. Both rules destroy the
  /// only copy of a message, so "cannot confirm" must never become "go ahead":
  /// a device with a wrong clock would otherwise wipe live messages, or its
  /// whole store, with nothing to restore from.
  Future<void> sweepDestroyablePlaintext() async {
    final serverNow = ServerClock.instance.estimatedNow;
    if (serverNow == null) return;

    final due = await _encryptionService.destroyableMessageIds(
      serverNow: serverNow,
      expiryGrace: kExpiryPurgeGrace,
    );
    if (due.expired.isEmpty && due.retired.isEmpty) return;

    // Mark retired BEFORE destroying. Retention removes plaintext for rows the
    // server still serves, so losing the marking would turn a deliberate state
    // into an undecryptable "[Decryption failed]" the user reads as corruption.
    if (due.retired.isNotEmpty) {
      await _encryptionService.markRetired(due.retired);
      _retiredIds.addAll(due.retired);
    }
    await purgeLocalPlaintext({...due.expired, ...due.retired});
    notifyListeners();
  }

  /// How long a COMPLETED reconciliation pass suppresses the next one.
  ///
  /// Not a one-off migration: `messageDeleted` is a live socket event, so a
  /// message the peer deletes while this device is offline leaves no trace to
  /// react to — the row is simply absent from history afterwards. Asking the
  /// server is the only thing that ever notices. It repeats for that reason,
  /// but not on every `socketReady`: a flaky connection reconnects many times
  /// a minute and this costs real round trips.
  static const Duration reconcileInterval = Duration(hours: 6);

  /// Ids per request. Matches the server's own per-batch cap.
  static const int reconcileBatchSize = 500;

  /// Destroy the local plaintext of every stored message the server no longer
  /// serves this account.
  ///
  /// This is what makes "deleted messages are gone" true for messages that
  /// were already deleted or expired when this feature shipped. Delete and
  /// expiry purge as they happen, but only for events this device saw: a
  /// record orphaned earlier carries none of the metadata
  /// [destroyableMessageIds] matches on, and its server row is gone, so
  /// nothing local would ever come back for it.
  ///
  /// [askServer] answers "of these ids, which do you still serve me". It MUST
  /// return null for any failure — timeout, dropped socket, malformed reply.
  /// Three properties make this safe to act on:
  ///
  ///  * A batch with no answer purges nothing. Silence must never read as
  ///    "the server has none of these", because an empty answer is a real and
  ///    destructive instruction (a fully cleared history).
  ///  * The local id set is snapshotted BEFORE the first request, so a message
  ///    that arrives mid-pass is not in any batch and cannot be mistaken for
  ///    one the server dropped.
  ///  * The answer is authoritative and global. Nothing is inferred from what
  ///    a history PAGE contained, which would read "older than this page" as
  ///    "deleted" and destroy the archive of every long conversation.
  Future<void> reconcileStoredPlaintext(
    Future<Set<int>?> Function(Set<int> batch) askServer, {
    bool force = false,
  }) async {
    // The interval below cannot hold on its own: the stamp is written only
    // after the LAST batch is answered, so a reconnect storm would start a
    // second pass while the first is still waiting on the network and both
    // would sail past the due check. Purging twice is harmless; paying for
    // several concurrent passes is exactly what the interval exists to avoid.
    if (_reconcileInFlight) return;
    _reconcileInFlight = true;
    try {
      await _reconcileStoredPlaintext(askServer, force: force);
    } finally {
      _reconcileInFlight = false;
    }
  }

  bool _reconcileInFlight = false;

  Future<void> _reconcileStoredPlaintext(
    Future<Set<int>?> Function(Set<int> batch) askServer, {
    required bool force,
  }) async {
    final userId = _encryptionService.activeUserId;
    if (userId == null) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (!force) {
      final lastMs = await _encryptionService.lastReconcileAtMs();
      final elapsed = lastMs == null ? null : nowMs - lastMs;
      if (elapsed != null &&
          elapsed >= 0 &&
          elapsed < reconcileInterval.inMilliseconds) {
        return;
      }
    }

    final stored = await _encryptionService.storedMessageIds();
    if (stored.isEmpty) {
      await _encryptionService.markReconciledAt(nowMs);
      return;
    }

    final batch = <int>{};
    final orphans = <int>{};
    var answeredAll = true;

    Future<bool> ask() async {
      final served = await askServer(Set<int>.unmodifiable(batch));
      if (served == null) return false;
      orphans.addAll(batch.difference(served));
      batch.clear();
      return true;
    }

    for (final id in stored) {
      batch.add(id);
      if (batch.length < reconcileBatchSize) continue;
      if (!await ask()) {
        answeredAll = false;
        break;
      }
    }
    if (answeredAll && batch.isNotEmpty && !await ask()) {
      answeredAll = false;
    }

    // The account can change while the round trips are in flight (logout, then
    // a login as the chat partner). Storage keys are namespaced per user, so
    // purging ids collected under one account against another's namespace
    // could destroy the partner's copy of a shared message id.
    if (_encryptionService.activeUserId != userId) return;

    if (orphans.isNotEmpty) {
      await purgeLocalPlaintext(orphans);
      notifyListeners();
    }
    _e2eFlowLog('PLAINTEXT_RECONCILED', {
      'stored': stored.length,
      'orphaned': orphans.length,
      'complete': answeredAll,
    });

    // Only a pass that heard back about EVERY batch may throttle the next one.
    // A partial pass leaves residue it has not proven anything about.
    if (answeredAll) await _encryptionService.markReconciledAt(nowMs);
  }

  /// Retrieve persisted decrypted message content, or null if not cached.
  /// Delegates to [EncryptionService.getDecryptedContent].
  Future<Map<String, dynamic>?> getDecryptedContent(int messageId) async {
    return _encryptionService.getDecryptedContent(messageId);
  }

  /// Tri-state: `true` on disk, `false` definitely absent, `null` unknown.
  /// Delegates to [EncryptionService.recordExists]. Never treat `null` as
  /// absence — that is how a transient storage error becomes permanent loss.
  Future<bool?> recordExists(int messageId) =>
      _encryptionService.recordExists(messageId);

  /// Batched persisted-plaintext lookup for a bounded id set (one cross-engine
  /// reload for the whole set). Delegates to
  /// [EncryptionService.getDecryptedContentMany] — see the safety note there
  /// before using it anywhere other than a history pass.
  Future<Map<int, Map<String, dynamic>>> getDecryptedContentMany(
    Iterable<int> messageIds,
  ) async {
    return _encryptionService.getDecryptedContentMany(messageIds);
  }

  /// Record an emitted send for lost-ack reconciliation (keyed by the exact
  /// emitted ciphertext). Delegates to [EncryptionService.savePendingSendRecord].
  Future<void> savePendingSendRecord(
    String ciphertext,
    Map<String, dynamic> data,
  ) async {
    await _encryptionService.savePendingSendRecord(ciphertext, data);
  }

  /// Read a pending-send record without consuming it (reconcile uses
  /// peek → persist → verify → take). Delegates to
  /// [EncryptionService.peekPendingSendRecord].
  Future<Map<String, dynamic>?> peekPendingSendRecord(String ciphertext) async {
    return _encryptionService.peekPendingSendRecord(ciphertext);
  }

  /// Consume the pending-send record matching [ciphertext] exactly, or null.
  /// Delegates to [EncryptionService.takePendingSendRecord].
  Future<Map<String, dynamic>?> takePendingSendRecord(String ciphertext) async {
    return _encryptionService.takePendingSendRecord(ciphertext);
  }

  /// Destroy every locally persisted plaintext record for this account.
  ///
  /// IRREVERSIBLE — see [EncryptionService.clearDecryptedContentCache]. Signal
  /// identity, sessions and pre-keys survive; only readable message content
  /// dies. Callers MUST check [LocalHistoryWipeResult.isComplete] before
  /// reporting success: a refused commit leaves plaintext on disk, and this is
  /// the primitive behind a button that promises the opposite.
  Future<LocalHistoryWipeResult> clearLocalDecryptedContentCache() async {
    final result = await _encryptionService.clearDecryptedContentCache();
    _decryptedContentCache.clear();
    // Scope on record: plaintext cache only — identity, sessions and pre-keys
    // are untouched. If a user report says "cleared cache" and sessions died,
    // it was NOT this path (browser site-data clear / reinstall wipes those).
    _e2eFlowLog('CACHE_CLEAR', {
      'scope': 'decryptedContent',
      'removed': result.removed,
      'failed': result.failedKeys.length,
    });
    notifyListeners();
    return result;
  }

  /// Destroy the persisted plaintext for [messageIds] and the outgoing
  /// pending-send records for [ciphertexts].
  ///
  /// IRREVERSIBLE — see [EncryptionService.removeDecryptedContent]. The RAM
  /// cache is dropped FIRST so no in-flight reader can re-persist a purged id
  /// from memory while the disk work is still running.
  ///
  /// [ciphertexts] exists because the sender's own outgoing plaintext is keyed
  /// by ciphertext rather than by message id, so an id-only purge would leave
  /// it readable. Callers should pass `MessageModel.encryptedContent` for
  /// every row they purge, captured BEFORE the row leaves local state.
  Future<PlaintextPurgeResult> purgeLocalPlaintext(
    Iterable<int> messageIds, {
    Iterable<String> ciphertexts = const <String>[],
  }) async {
    final ids = messageIds.toSet();
    final cts = ciphertexts.toSet();

    // Write the obligation down FIRST. Everything below can be interrupted by
    // a tab close or a refused commit, and once the row is gone from memory
    // and from the server nothing else would ever come looking for its
    // residue. The backlog is what makes this at-least-once.
    final recorded = await _encryptionService.enqueuePurge(ids, cts);

    final result = await _runPurge(ids, cts);
    if (result.isComplete) {
      await _encryptionService.resolvePurged(ids, cts);
    } else if (!recorded) {
      // Worst case, and worth separating from an ordinary failure: the purge
      // did not finish AND the obligation was never written down, so nothing
      // will come back for it. "Failed, will retry" and "failed, now lost" are
      // very different for a promise that plaintext eventually dies.
      _e2eFlowLog('PLAINTEXT_PURGE_LOST', {
        'requested': ids.length,
        'failedIds': result.failedIds.length,
      });
    }
    return result;
  }

  /// Retry every purge that was recorded but never confirmed complete.
  ///
  /// Runs at startup and after each `socketReady`. Entries survive until a
  /// purge confirms, so a device that was closed mid-delete finishes the job
  /// on its next launch rather than keeping the plaintext forever.
  Future<void> drainPurgeBacklog() async {
    final backlog = await _encryptionService.purgeBacklog();
    if (backlog.ids.isEmpty && backlog.ciphertexts.isEmpty) return;
    final result = await _runPurge(backlog.ids, backlog.ciphertexts);
    final settledIds = backlog.ids.difference(result.failedIds);
    final settledCiphertexts = backlog.ciphertexts.difference(
      result.failedCiphertexts,
    );
    await _encryptionService.resolvePurged(settledIds, settledCiphertexts);
    _e2eFlowLog('PURGE_BACKLOG_DRAINED', {
      'owed': backlog.ids.length,
      'settled': settledIds.length,
    });
  }

  Future<PlaintextPurgeResult> _runPurge(
    Set<int> ids,
    Set<String> ciphertexts,
  ) async {
    for (final id in ids) {
      _decryptedContentCache.remove(id);
    }

    final failedCiphertexts = <String>{};
    for (final ciphertext in ciphertexts) {
      if (!await _encryptionService.removePendingSendRecord(ciphertext)) {
        failedCiphertexts.add(ciphertext);
      }
    }

    final disk = await _encryptionService.removeDecryptedContent(ids);

    // Voice notes are cached DECRYPTED on native, keyed by the same message
    // id. Purging them here rather than at the call sites means no caller can
    // destroy a message's text and leave its audio readable — and that
    // directory is swept into iCloud / Android auto-backup.
    final failedAudio = await AudioCacheStore.remove(ids);

    final result = PlaintextPurgeResult(
      removed: disk.removed,
      failedIds: {...disk.failedIds, ...failedAudio},
      failedCiphertexts: failedCiphertexts,
    );
    if (!result.isComplete) {
      _e2eFlowLog('PLAINTEXT_PURGE_INCOMPLETE', {
        'requested': ids.length,
        'removed': result.removed,
        'failedIds': result.failedIds.length,
        'failedCiphertexts': result.failedCiphertexts.length,
      });
    }
    return result;
  }

  /// Clear a pending pre-key fetch for [recipientId] (e.g. on send failure
  /// so retry gets a fresh fetch).
  void clearPendingPreKeyFetch(int recipientId) {
    _pendingPreKeyFetches.remove(recipientId);
  }

  // ---------- TEMP storage-durability probes (remove after root cause) ----------

  /// Logged once per app run.
  static bool _persistProbed = false;

  Future<void> _logSessionInventory() async {
    try {
      final peers = await _encryptionService.sessionInventoryPeerIds();
      _e2eFlowLog('SESSION_INVENTORY', {
        'count': peers.length,
        'peerIds': peers,
      });
    } catch (_) {}
  }

  Future<void> _probeStoragePersistenceOnce() async {
    if (_persistProbed) return;
    _persistProbed = true;
    try {
      final r = await requestPersistentStorage();
      _e2eFlowLog('STORAGE_PERSIST', {
        'supported': r['supported'] ?? false,
        'granted': r['granted'] ?? false,
      });
    } catch (_) {}
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
        // Rebuild the UI when a peer's identity key changes so the warning can
        // appear without waiting for the next message.
        _encryptionService.onPeerIdentityChanged = (_) => notifyListeners();
        // Fresh session: load keys from storage (or generate on first install).
        await _encryptionService.initialize(userId);
        _identityIncomplete = false;
        // Load the retired-id set BEFORE flipping the ready flag. This is the
        // only point that provably precedes any decrypt attempt: decrypting
        // requires E2E to be ready, so nothing can start while this await is
        // outstanding. Setting `_e2eInitialized = true` first would reopen the
        // window — the await yields with the flag already true and the set
        // still empty — and a decrypt that wins that race persists a permanent
        // "[Decryption failed]" for a row the app deliberately purged.
        await loadRetiredIds();
        // Same reason, one step further: without the ledger loaded, the first
        // history pass cannot tell a lost record from one never decrypted.
        await loadDecryptedLedger();
        _e2eInitialized = true;
        debugPrint('[E2E] Encryption service initialized');
        _e2eFlowLog('E2E_INIT_DONE', {
          'needsKeyUpload': _encryptionService.needsKeyUpload,
        });
      } else {
        // Reconnect: stores are already valid — skip re-initialization to avoid
        // the window where _identityStore._identityKeyPair is null and to prevent
        // a transient storage error from incorrectly setting _e2eInitialized = false.
        debugPrint('[E2E] Reconnect: skipping re-init, E2E already active');
        _e2eFlowLog('E2E_RECONNECT_SKIP_INIT', {});
      }

      // TEMP storage-durability probe — snapshot which sessions survived to this
      // start (compare across reloads), and once per app run ask the browser to
      // stop evicting our keystore. Remove with the rest of the SESSION_* probes.
      await _logSessionInventory();
      await _probeStoragePersistenceOnce();

      if (_encryptionService.needsKeyUpload) {
        final keys = _encryptionService.getKeysForUpload();
        if (keys != null) {
          final keyBundle = keys['keyBundle'] as Map<String, dynamic>;
          final identity = keyBundle['identityPublicKey'];
          if (identity is! String || identity.isEmpty) {
            const reason = 'identity_epoch_required';
            debugPrint('[E2E] Key upload deferred: $reason');
            E2ePersistentDiag.record('KEY_UPLOAD_DEFERRED', {'reason': reason});
            _e2eFlowLog('E2E_KEYS_UPLOAD_DEFERRED', {'reason': reason});
            return;
          }
          _emit?.call('uploadKeyBundle', keyBundle);
          _emit?.call('uploadOneTimePreKeys', {
            'keys': (keys['oneTimePreKeys'] as List)
                .cast<Map<String, dynamic>>(),
            'identityPublicKey': identity,
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
          debugPrint(
            '[E2E] Re-upload skipped: could not build key bundle from storage',
          );
        }
      }
    } on E2eIdentityIncompleteException catch (e) {
      // NOT a transient failure and NOT recoverable by retrying: the stored
      // identity is damaged and we refused to regenerate over it. Surface it
      // so the UI can explain and offer recoverFromIncompleteIdentity(),
      // instead of leaving the user staring at "[encrypted]" every boot.
      debugPrint('[E2E] $e');
      _identityIncomplete = true;
      _e2eInitialized = false;
      _e2eFlowLog('E2E_INIT_IDENTITY_INCOMPLETE', {});
      notifyListeners();
    } catch (e) {
      debugPrint('[E2E] Initialization failed: $e');
      // Only clear the flag if we hadn't initialized yet; don't undo a working
      // reconnect just because the re-upload attempt threw.
      if (!_e2eInitialized) _e2eInitialized = false;
      _e2eFlowLog('E2E_INIT_FAIL', {'error': e.toString()});
    } finally {
      if (_e2eInitialized) {
        onE2EReady?.call();
      }
    }
  }

  /// DESTRUCTIVE, only after explicit user consent. The escape hatch from
  /// [identityIncomplete]: wipe the damaged Signal material and start a new
  /// identity so the app can send and receive again.
  ///
  /// Tell the user the truth first: no existing ciphertext will ever decrypt
  /// again and peers must re-key, but history this device already decrypted
  /// stays readable (the plaintext cache is not touched).
  Future<void> recoverFromIncompleteIdentity() async {
    final userId = _currentUserId;
    if (userId == null || !_identityIncomplete) return;
    // Set SYNCHRONOUSLY, before any await: key generation mints 100 prekeys and
    // is far from instant, and `_identityIncomplete` only clears at the end. A
    // second tap in that window would otherwise pass the guard above and run a
    // concurrent identity write + prekey batch against the same counter.
    if (_identityRecoveryInFlight) return;
    _identityRecoveryInFlight = true;
    notifyListeners();
    try {
      await _runIdentityRecovery(userId);
    } finally {
      _identityRecoveryInFlight = false;
      notifyListeners();
    }
  }

  /// True while [recoverFromIncompleteIdentity] is running, so the UI can
  /// disable its own trigger instead of relying on the user not double-tapping.
  bool get identityRecoveryInFlight => _identityRecoveryInFlight;
  bool _identityRecoveryInFlight = false;

  Future<void> _runIdentityRecovery(int userId) async {
    _e2eFlowLog('E2E_IDENTITY_RECOVERY_START', {'userId': userId});
    await _encryptionService.regenerateIdentityAfterConfirmedLoss(userId);
    _identityIncomplete = false;
    _e2eInitialized = true;
    notifyListeners();
    // Publish the new bundle; without it peers cannot start a session.
    final keys = _encryptionService.getKeysForUpload();
    if (keys != null) {
      final keyBundle = keys['keyBundle'] as Map<String, dynamic>;
      final identity = keyBundle['identityPublicKey'];
      if (identity is String && identity.isNotEmpty) {
        _emit?.call('uploadKeyBundle', keyBundle);
        _emit?.call('uploadOneTimePreKeys', {
          'keys': (keys['oneTimePreKeys'] as List).cast<Map<String, dynamic>>(),
          'identityPublicKey': identity,
        });
      }
    }
    _e2eFlowLog('E2E_IDENTITY_RECOVERY_DONE', {'userId': userId});
    onE2EReady?.call();
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
    _e2eFlowLog('PREKEY_RESP', {
      'userId': userId,
      'hasBundle': bundle != null && bundle is Map<String, dynamic>,
    });
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

  void onPreKeysLow(dynamic data) {
    if (_generatingMoreKeys) return;
    _generatingMoreKeys = true;
    debugPrint('[E2E] Server reports pre-keys low, generating more...');
    Future<void>(() async {
          final identity = await _encryptionService
              .currentIdentityPublicKeyBase64();
          if (identity == null || identity.isEmpty) {
            const reason = 'identity_epoch_required';
            debugPrint('[E2E] OTP replenishment deferred: $reason');
            E2ePersistentDiag.record('OTP_REPLENISH_DEFERRED', {
              'reason': reason,
            });
            _e2eFlowLog('OTP_REPLENISH_DEFERRED', {'reason': reason});
            return;
          }
          final keys = await _encryptionService.generateMorePreKeys();
          _emit?.call('uploadOneTimePreKeys', {
            'keys': keys,
            'identityPublicKey': identity,
          });
          debugPrint('[E2E] Uploaded ${keys.length} new one-time pre-keys');
        })
        .catchError((e) {
          debugPrint('[E2E] Failed to replenish pre-keys: $e');
          E2ePersistentDiag.record('OTP_REPLENISH_FAILED', {
            'reason': e.toString(),
          });
        })
        .whenComplete(() => _generatingMoreKeys = false);
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
      _retiredIds.clear();
      _decryptedLedger.clear();
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
    _retiredIds.clear();
    _decryptedLedger.clear();
    _forceSessionRebuild.clear();
    _cancelPendingFetches();
    notifyListeners();
  }

  /// Identity key fingerprint for display in Privacy & Safety screen.
  Future<String?> getIdentityFingerprint() =>
      _encryptionService.getIdentityFingerprint();

  /// Stored trusted identity fingerprint for out-of-band peer verification.
  Future<String?> getPeerIdentityFingerprint(int peerId) =>
      _encryptionService.getPeerIdentityFingerprint(peerId);

  /// Clear all E2E encryption keys. Call on account deletion only.
  Future<void> clearEncryptionKeys() async {
    _e2eFlowLog('CACHE_CLEAR', {'scope': 'allE2EKeys'});
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
