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
import '../utils/boot_markers.dart';

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

  /// ISO-8601 instant of the last server-reported replacement of this
  /// account's key bundle by ANOTHER session (Phase 0a takeover alarm), or
  /// null. Drives the account-level notice; persisted until dismissed.
  String? get ownIdentityReplacedAt => _encryptionService.ownIdentityReplacedAt;

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
  ///
  /// Backfills first, so an account that predates the ledger is protected from
  /// its very first pass instead of only for messages decrypted from now on.
  Future<void> loadDecryptedLedger() async {
    await _encryptionService.backfillLedgerFromStore();
    final ids = await _encryptionService.decryptedLedgerIds();
    _decryptedLedger
      ..clear()
      ..addAll(ids);
  }

  /// Persist ids buffered during a decrypt pass. Called at pass boundaries.
  Future<void> flushDecryptedLedger() =>
      _encryptionService.flushDecryptedLedger();

  /// Diagnostic snapshot of the three persisted id sets, for the hacker-mode
  /// Privacy & Safety panel. Read-only; disk truth, not the in-memory mirrors
  /// (the mirrors can be stale within a session — that staleness is one of
  /// the things this exists to make visible in the field, where the owner has
  /// no devtools (iOS Safari PWA)). Metadata only: message ids, never content.
  Future<({Set<int> retired, Set<int> ledger, Set<int> stored})>
  diagStorageSets() async {
    return (
      retired: await _encryptionService.retiredMessageIds(),
      ledger: await _encryptionService.decryptedLedgerIds(),
      stored: await _encryptionService.storedMessageIds(),
    );
  }

  /// Record that [messageId] is known-lost so later passes short-circuit
  /// without re-deriving it, and the state survives a restart.
  Future<void> retireLostMessage(int messageId) async {
    _retiredIds.add(messageId);
    await _encryptionService.markRetired(<int>[messageId]);
  }

  /// Record one terminal-duplicate observation (design
  /// `terminal-duplicate-retirement.md` §3.3). Returns the count after this
  /// call, or null when nothing was recorded — callers treat null as "no
  /// observation", never as progress.
  Future<int?> noteTerminalDuplicate(int messageId) =>
      _encryptionService.noteTerminalDuplicate(messageId);

  /// Drop [messageId]'s terminal-duplicate counter — called only on a DEFINITE
  /// readable source (never on an undetermined answer).
  Future<void> clearTerminalDuplicate(int messageId) =>
      _encryptionService.clearTerminalDuplicate(messageId);

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

  /// True when the previous sweep found nothing to destroy. The sweep ticks
  /// once a minute, so logging every empty pass would churn the 200-entry
  /// ring and evict actual evidence — the exact noise-evicts-evidence failure
  /// the durable-log dedupe fixed in 0.1.6, one level down. Instead the ring
  /// gets one `PLAINTEXT_SWEEP {expired: 0, ...}` entry per TRANSITION into
  /// "nothing due": liveness stays visible ("the sweep ran and found
  /// nothing"), consecutive empty ticks stay silent.
  bool _lastSweepFoundNothing = false;

  /// Ring-entry id-list cap for [sweepDestroyablePlaintext]. A retention
  /// sweep after a long absence can condemn hundreds of ids; the diag dump
  /// copies the whole ring, so unbounded lists would bloat it for no
  /// diagnostic gain beyond "which rows died" on a normal-sized sweep.
  static const int _sweepDiagIdCap = 30;

  /// Destroy plaintext whose message has expired, or aged past retention.
  ///
  /// No-op unless the server clock can be confirmed. Both rules destroy the
  /// only copy of a message, so "cannot confirm" must never become "go ahead":
  /// a device with a wrong clock would otherwise wipe live messages, or its
  /// whole store, with nothing to restore from.
  ///
  /// Every acting pass logs `PLAINTEXT_SWEEP` to the RING (never the cap-80
  /// durable log — success is routine, the durable log is failure evidence):
  /// expired/retired counts, the removed count from the purge, and the
  /// condemned ids (capped). Failures inside the purge keep their existing
  /// `PLAINTEXT_PURGE_INCOMPLETE` / `PLAINTEXT_PURGE_LOST` channels.
  Future<void> sweepDestroyablePlaintext() async {
    final serverNow = ServerClock.instance.estimatedNow;
    if (serverNow == null) return;

    final due = await _encryptionService.destroyableMessageIds(
      serverNow: serverNow,
      expiryGrace: kExpiryPurgeGrace,
    );
    if (due.expired.isEmpty && due.retired.isEmpty) {
      if (!_lastSweepFoundNothing) {
        _lastSweepFoundNothing = true;
        _e2eFlowLog('PLAINTEXT_SWEEP', {'expired': 0, 'retired': 0});
      }
      return;
    }
    _lastSweepFoundNothing = false;

    // Mark retired BEFORE destroying. Retention removes plaintext for rows the
    // server still serves, so losing the marking would turn a deliberate state
    // into an undecryptable "[Decryption failed]" the user reads as corruption.
    if (due.retired.isNotEmpty) {
      await _encryptionService.markRetired(due.retired);
      _retiredIds.addAll(due.retired);
    }
    final result = await purgeLocalPlaintext({...due.expired, ...due.retired});
    final condemned = [...due.expired, ...due.retired]..sort();
    _e2eFlowLog('PLAINTEXT_SWEEP', {
      'expired': due.expired.length,
      'retired': due.retired.length,
      'removed': result.removed,
      'ids': condemned.take(_sweepDiagIdCap).toList(),
      if (condemned.length > _sweepDiagIdCap)
        'idsTruncated': condemned.length - _sweepDiagIdCap,
    });
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


  /// True when the raw replay cache can still serve [messageId] without any
  /// ratchet work. Delegates to [EncryptionService.rawReplayExists]. A missing
  /// `_decrypted_` record is NOT proof of loss while this answers true.
  Future<bool?> rawReplayExists(int messageId) =>
      _encryptionService.rawReplayExists(messageId);
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
    // Mirror the wipe into the in-memory sets. `markRetired` inside the
    // service persists to DISK; `isRetired` reads THIS set, and the ledger
    // gate runs only when the retired check misses. Without this sync a
    // history pass in the SAME session read the stale RAM set, missed every
    // wiped id, and reported the user's own deliberate wipe as
    // `LEDGER_RECORD_LOST` (2026-08-02, five false alarms).
    _retiredIds.addAll(result.wipedIds);
    _decryptedLedger.removeAll(result.wipedIds);
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
    // One-time upgrade amnesty (marker-guarded, cheap after the first run):
    // obligations enqueued by the pre-0.1.4 fallback-expiry sweep must not be
    // replayed against records the fixed sweep refuses to condemn.
    await _encryptionService.amnestyUnstampedPurgeObligations();
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

    // Ledger hygiene for DELIBERATE destruction: an id purged on purpose must
    // not read as unexpected loss when the server briefly serves the row
    // again. Only ids whose disk removal CONFIRMED are forgotten — a failed
    // removal leaves readable plaintext, and its ledger entry must keep
    // protecting it. Failed audio does not gate this: the ledger tracks the
    // text record, and audio failures already fail the purge result.
    final settled = ids.difference(disk.failedIds);
    if (settled.isNotEmpty) {
      _decryptedLedger.removeAll(settled);
      await _encryptionService.forgetDecryptedMany(settled);
    }

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

  /// Logged once per app run.
  static bool _bootMarkersProbed = false;

  /// Boot-marker forensics (§5.3 of the 08-16 handoff): read which of the
  /// three in-bucket stores still hold last boot's marker, THEN replant all
  /// three, and record the read durably. All three absent on a container that
  /// ran before = whole-bucket eviction; IDB or Cache alive while
  /// localStorage reads empty = localStorage-only loss = ours. Must run
  /// BEFORE the keystore is opened so the evidence predates any writes.
  Future<void> _recordBootMarkersOnce() async {
    if (_bootMarkersProbed) return;
    _bootMarkersProbed = true;
    try {
      // Bounded: IndexedDB/CacheStorage can hang (a second live context on
      // this origin is a proven state here — Morion). Boot must not; a
      // timeout records ERROR on every arm, which is honest: inconclusive.
      final triple = await readAndPlantBootMarkers().timeout(
        const Duration(seconds: 4),
        onTimeout: () => const BootMarkerTriple(
          localStorage: BootMarkerState.error,
          indexedDb: BootMarkerState.error,
          cacheStorage: BootMarkerState.error,
        ),
      );
      final payload = triple.toDiagnosticPayload();
      _e2eFlowLog('BOOT_MARKERS', payload);
      if (kIsWeb) {
        E2ePersistentDiag.record('BOOT_MARKERS', payload);
      }
    } catch (_) {}
  }

  Future<void> _probeStoragePersistenceOnce() async {
    if (_persistProbed) return;
    _persistProbed = true;
    try {
      final r = await requestPersistentStorage();
      final supported = r['supported'] ?? false;
      final granted = r['granted'] ?? false;
      // Quota telemetry: the app used to be completely blind to how full the
      // bucket was (nothing ever called estimate()). Diagnostic only.
      final estimate = await storageEstimate();
      _e2eFlowLog('STORAGE_PERSIST', {
        'supported': supported,
        'granted': granted,
        if (estimate != null) 'usage': estimate['usage'],
        if (estimate != null) 'quota': estimate['quota'],
      });
      // A denied grant is the one storage fact that can end in unrecoverable
      // Signal key loss: iOS evicts a non-persistent origin and there is no
      // key recovery. The in-memory ring rotates long before any field dump is
      // taken, so the evidence has to be durable. Deduped, or the cap-80 log
      // would re-burn a slot every boot; eviction re-arms it by design.
      // Web only — the native stub always answers {supported:false} and native
      // keys live in secure storage, not a browser origin.
      if (kIsWeb && !granted) {
        E2ePersistentDiag.recordDeduped(
          'STORAGE_PERSIST_DENIED',
          {'supported': supported, 'granted': granted},
          matchAll: ['{supported: $supported,'],
        );
      }
    } catch (_) {}
  }

  // ---------- E2E Initialization ----------

  /// Initialize E2E encryption for the current user. On fresh connect,
  /// generates/loads keys and uploads them. On reconnect (same user),
  /// skips re-initialization but still re-uploads the key bundle.
  ///
  /// Re-entrancy latch (review finding, 0.1.10): this is fired on every
  /// socket connect, and the identity guard's server round-trip widened the
  /// window in which a reconnect enters a second concurrent init — hanging
  /// on the shared bundle check or racing a double `_generateKeys()`.
  /// Concurrent calls for the same user share one run; a different user
  /// waits its turn.
  Future<void> initializeE2E(int userId) async {
    while (true) {
      final inFlight = _e2eInitInFlight;
      if (inFlight == null) break;
      if (_currentUserId == userId) return inFlight;
      await inFlight;
    }
    final run = _initializeE2EInner(userId);
    _e2eInitInFlight = run;
    try {
      await run;
    } finally {
      _e2eInitInFlight = null;
    }
  }

  Future<void>? _e2eInitInFlight;

  /// CLAUDE.md gotcha: skips `_encryptionService.initialize()` when
  /// `_e2eInitialized = true` (reconnect path) to prevent transient
  /// mobile storage errors from setting `_e2eInitialized = false`.
  /// Never throws — every failure mode is caught and logged inside.
  Future<void> _initializeE2EInner(int userId) async {
    _currentUserId = userId;
    _e2eFlowLog('E2E_INIT_START', {'alreadyInitialized': _e2eInitialized});
    try {
      // Forensics + persistence BEFORE the keystore is created: every prior
      // `granted: true` reading was post-loss, and the ordering defect (probe
      // after initialize) is exactly what kept the persistence premise
      // unverifiable in the field. Both are once-per-run.
      await _recordBootMarkersOnce();
      await _probeStoragePersistenceOnce();
      if (!_e2eInitialized) {
        // Rebuild the UI when a peer's identity key changes so the warning can
        // appear without waiting for the next message.
        _encryptionService.onPeerIdentityChanged = (_) => notifyListeners();
        // Same for the account-level own-identity-replaced alarm.
        _encryptionService.onOwnIdentityReplaced = notifyListeners;
        // Fresh session: load keys from storage (or generate on first install).
        await _encryptionService.initialize(
          userId,
          checkServerBundleExists: _checkServerBundleExists,
        );
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

      // TEMP storage-durability probe — snapshot which sessions survived to
      // this start (compare across reloads). Remove with the rest of the
      // SESSION_* probes.
      await _logSessionInventory();

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
    } on E2eIdentityCheckUnavailableException {
      // UNKNOWN is transient by contract: the server could not be asked
      // whether this account already has a bundle, so neither generating keys
      // nor declaring the identity damaged is safe. E2E stays down for this
      // session; the next connect re-runs initializeE2E because
      // _e2eInitialized is still false. Treating UNKNOWN as "no bundle" would
      // re-mint an identity on every flaky boot — the exact data-loss bug.
      debugPrint('[E2E] Identity check unavailable — deferring E2E init');
      _e2eFlowLog('E2E_INIT_GUARD_UNKNOWN', {});
      _e2eInitialized = false;
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
  ///
  /// Phase 0b: a `success:false` answer with `identity_locked` means the
  /// registration lock refused to replace this account's stored identity key.
  /// That is terminal for this attempt — retrying mints nothing and would just
  /// loop. The user's route forward is the reset ceremony, so surface it.
  void onKeyBundleUploaded(dynamic data) {
    if (data is Map && data['success'] == false) {
      final error = data['error'];
      if (error == 'identity_locked') {
        // This is the dangerous case for a user who just re-minted keys after
        // losing theirs: the local device now believes it is healthy, but the
        // server still publishes the PREVIOUS identity, so peers keep
        // encrypting to keys this device cannot read. Recording it drives the
        // banner that routes them to the reset ceremony — the only thing that
        // can make these keys land — instead of leaving them silently
        // unreachable behind a "recovered" UI.
        _e2eFlowLog('KEY_BUNDLE_IDENTITY_LOCKED', {});
        E2ePersistentDiag.record('KEY_BUNDLE_IDENTITY_LOCKED', {});
        _identityUploadLocked = true;
        notifyListeners();
        return;
      }
      debugPrint('[E2E] Key bundle upload refused: $error');
      return;
    }
    _identityUploadLocked = false;
    debugPrint('[E2E] Key bundle uploaded to server');
  }

  /// True once the server refused an identity replacement for this account.
  /// Cleared by a successful upload (which a completed ceremony enables).
  bool _identityUploadLocked = false;
  bool get identityUploadLocked => _identityUploadLocked;

  // ---------- Identity reset ceremony (Phase 0b, spec §6.2) ----------

  DateTime? _identityResetDeadline;
  bool _identityResetShortened = false;
  String? _identityResetRequestStatus;

  /// Deadline of the pending ceremony, or null when none is running. Server
  /// authoritative: re-hydrated from `ownKeyBundleStatus` on every connect, so
  /// it never needs local persistence.
  DateTime? get identityResetDeadline => _identityResetDeadline;

  /// Whether the pending ceremony used a recovery key (1 h instead of 72 h).
  bool get identityResetShortened => _identityResetShortened;

  /// Last answer to a reset request: 'pending', 'existing', 'cooldown',
  /// 'invalid_phrase' or 'locked'. Null once consumed by the UI.
  String? get identityResetRequestStatus => _identityResetRequestStatus;

  /// A completed ceremony is waiting to be spent by a key upload.
  bool _identityResetCompleted = false;
  bool get identityResetCompleted => _identityResetCompleted;

  void clearIdentityResetRequestStatus() {
    if (_identityResetRequestStatus == null) return;
    _identityResetRequestStatus = null;
    notifyListeners();
  }

  /// Starts the ceremony. A recovery phrase shortens the wait but never
  /// silences the notifications, and never grants an instant replacement.
  void requestIdentityReset({String? recoveryPhrase}) {
    _e2eFlowLog('IDENTITY_RESET_REQUEST', {
      'withPhrase': recoveryPhrase != null,
    });
    _emit?.call('resetIdentityRequest', <String, dynamic>{
      if (recoveryPhrase != null && recoveryPhrase.isNotEmpty)
        'recoveryPhrase': recoveryPhrase,
    });
  }

  /// Stops a pending ceremony. Any signed-in session may do this, with no key
  /// required — that is the whole point of the delay.
  void cancelIdentityReset() {
    _e2eFlowLog('IDENTITY_RESET_CANCEL', {});
    _emit?.call('resetIdentityCancel', <String, dynamic>{});
  }

  /// Enrolls or replaces the recovery phrase. The phrase is generated on this
  /// device, shown once, and never stored locally.
  void setRecoveryKey(String phrase) {
    _emit?.call('setRecoveryKey', <String, dynamic>{'phrase': phrase});
  }

  /// Handler for `identityResetStatus` — the answer to our own request.
  void onIdentityResetStatus(dynamic data) {
    if (data is! Map) return;
    final status = data['status'];
    if (status is! String) return;
    _identityResetRequestStatus = status;
    if (status == 'pending' || status == 'existing') {
      _applyResetDeadline(data['deadlineAt'], data['shortened'] == true);
    }
    _e2eFlowLog('IDENTITY_RESET_STATUS', {'status': status});
    notifyListeners();
  }

  /// Handler for `identityResetPending` — broadcast to EVERY session of the
  /// account, including sessions that did not ask for it. That is the alarm.
  void onIdentityResetPending(dynamic data) {
    if (data is! Map) return;
    _applyResetDeadline(data['deadlineAt'], data['shortened'] == true);
    _e2eFlowLog('IDENTITY_RESET_PENDING', {
      'shortened': _identityResetShortened,
    });
    notifyListeners();
  }

  /// Handler for `identityResetCancelled` — room-wide, so every surface clears
  /// together no matter which session tapped cancel.
  void onIdentityResetCancelled(dynamic data) {
    _identityResetDeadline = null;
    _identityResetShortened = false;
    _identityResetCompleted = false;
    _e2eFlowLog('IDENTITY_RESET_CANCELLED', {});
    notifyListeners();
  }

  /// Handler for `identityResetCancelResult` — this session's own answer.
  void onIdentityResetCancelResult(dynamic data) {
    final cancelled = data is Map && data['cancelled'] == true;
    if (!cancelled) {
      // Nothing pending: the ceremony already reached a terminal state.
      _e2eFlowLog('IDENTITY_RESET_CANCEL_NOOP', {});
    }
  }

  /// Handler for `recoveryKeySet`.
  bool? _recoveryKeySetResult;
  bool? get recoveryKeySetResult => _recoveryKeySetResult;

  void onRecoveryKeySet(dynamic data) {
    _recoveryKeySetResult = data is Map && data['success'] == true;
    notifyListeners();
  }

  void clearRecoveryKeySetResult() {
    if (_recoveryKeySetResult == null) return;
    _recoveryKeySetResult = null;
    notifyListeners();
  }

  void _applyResetDeadline(dynamic deadlineAt, bool shortened) {
    if (deadlineAt is! String) return;
    final parsed = DateTime.tryParse(deadlineAt);
    if (parsed == null) return;
    _identityResetDeadline = parsed.toLocal();
    _identityResetShortened = shortened;
    _identityResetCompleted = false;
  }

  /// Handler for the `ownIdentityReplaced` server event (Phase 0a): ANOTHER
  /// sign-in replaced this account's key bundle. Usually a legitimate new
  /// device/browser sign-in or reinstall — the UI copy must say so — but it is
  /// also exactly what a password-only takeover looks like, so it is durable
  /// and survives restarts until dismissed.
  void onOwnIdentityReplaced(dynamic data) {
    final occurredAt = data is Map && data['occurredAt'] is String
        ? data['occurredAt'] as String
        : DateTime.now().toUtc().toIso8601String();
    _e2eFlowLog('OWN_IDENTITY_REPLACED_EVENT', {'occurredAt': occurredAt});
    _encryptionService.recordOwnIdentityReplaced(occurredAt);
    notifyListeners();
  }

  /// Handler for the `peerIdentityChanged` server event (Phase 0a): a peer's
  /// key bundle was replaced server-side. Feeds the same warning state as the
  /// local libsignal detection (in-conversation timeline row + verify door).
  void onPeerIdentityChanged(dynamic data) {
    final peerId = data is Map ? data['userId'] : null;
    if (peerId is! int) return;
    _e2eFlowLog('PEER_IDENTITY_CHANGED_EVENT', {'peerId': peerId});
    _encryptionService.recordPeerIdentityChangedFromServer(peerId);
    notifyListeners();
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

  /// Handler for `ownKeyBundleStatus` server event — the answer to
  /// `checkOwnKeyBundle`. A malformed payload completes as null (UNKNOWN),
  /// never as false: only an explicit server "no bundle" may authorize key
  /// generation.
  ///
  /// Phase 0b also carries the account-protection state, which is how a
  /// session that was offline at the time still learns about a pending reset
  /// ceremony or a replacement of its identity key.
  void onOwnKeyBundleStatus(dynamic data) {
    final exists = data is Map && data['exists'] is bool
        ? data['exists'] as bool
        : null;
    _e2eFlowLog('OWN_BUNDLE_STATUS', {'exists': exists});
    if (data is Map) {
      _hydrateIdentityResetState(data['identityReset']);
      final replacedAt = data['identityReplacedAt'];
      if (replacedAt is String && replacedAt.isNotEmpty) {
        // Respects the user's dismissal watermark inside the service.
        unawaited(
          _encryptionService
              .recordOwnIdentityReplacedFromServer(replacedAt)
              .then((_) => notifyListeners()),
        );
      }
    }
    final completer = _pendingOwnBundleCheck;
    if (completer == null || completer.isCompleted) return;
    completer.complete(exists);
  }

  /// Applies the server's view of the ceremony. Absent field (older server)
  /// leaves local state untouched; explicit null means "nothing running".
  void _hydrateIdentityResetState(dynamic identityReset) {
    if (identityReset == null) {
      if (_identityResetDeadline == null && !_identityResetCompleted) return;
      _identityResetDeadline = null;
      _identityResetShortened = false;
      _identityResetCompleted = false;
      notifyListeners();
      return;
    }
    if (identityReset is! Map) return;
    final status = identityReset['status'];
    if (status == 'pending') {
      _applyResetDeadline(identityReset['deadlineAt'], false);
      notifyListeners();
      return;
    }
    if (status == 'completed') {
      _identityResetDeadline = null;
      _identityResetCompleted = true;
      notifyListeners();
    }
  }

  Completer<bool?>? _pendingOwnBundleCheck;

  /// Tri-state server check backing the identity guard in
  /// [EncryptionService.initialize]: true/false only on an explicit server
  /// answer; null (UNKNOWN) on no socket, timeout, or any error. Callers MUST
  /// treat null as "do not decide".
  Future<bool?> _checkServerBundleExists() async {
    final emit = _emit;
    if (emit == null) return null;
    final existing = _pendingOwnBundleCheck;
    if (existing != null) return existing.future;
    final completer = Completer<bool?>();
    _pendingOwnBundleCheck = completer;
    // The timeout completes the SHARED completer, not a per-caller wrapper:
    // a per-caller `.timeout()` resolves only the first awaiter and orphans
    // any concurrent one forever (review finding). Completing the completer
    // itself resolves every awaiter to UNKNOWN together.
    final timeout = Timer(const Duration(seconds: 6), () {
      if (!completer.isCompleted) completer.complete(null);
    });
    try {
      _e2eFlowLog('OWN_BUNDLE_CHECK_EMIT', {});
      emit('checkOwnKeyBundle', <String, dynamic>{});
      return await completer.future;
    } catch (_) {
      return null;
    } finally {
      timeout.cancel();
      // A newer check may already own the field — never clobber it.
      if (identical(_pendingOwnBundleCheck, completer)) {
        _pendingOwnBundleCheck = null;
      }
    }
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

  /// The user compared fingerprints out of band and accepted [peerId]'s current
  /// key. Clears the standing identity-change warning — the ONLY thing that
  /// does, so an unacknowledged warning survives restarts.
  Future<void> acknowledgePeerIdentity(int peerId) async {
    await _encryptionService.acknowledgePeerIdentity(peerId);
    notifyListeners();
  }

  /// User dismissed the own-identity-replaced notice.
  Future<void> dismissOwnIdentityReplaced() async {
    await _encryptionService.dismissOwnIdentityReplaced();
    notifyListeners();
  }

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
