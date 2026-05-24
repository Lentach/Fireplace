import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:webcrypto/webcrypto.dart';
import '../utils/file_utils_stub.dart'
    if (dart.library.io) '../utils/file_utils_io.dart' as file_utils;

import '../config/app_config.dart';
import '../models/message_model.dart';
import '../services/api_service.dart';
import '../services/media_crypto_service.dart';
import '../services/link_preview_service.dart';
import '../utils/e2e_envelope.dart';
import '../utils/message_expiry.dart';
import '../utils/reply_preview_helper.dart';
import 'conversation_helpers.dart' as conv_helpers;
import 'conversations_provider.dart';
import 'encryption_provider.dart';

/// MessagingProvider — owns all message state, send/receive handlers,
/// encryption orchestration, typing/recording indicators, and reactions.
/// Wired by [ConnectionProvider] and ConversationsScreen (setEncryptionProvider, setConversationsProvider).
class MessagingProvider extends ChangeNotifier {
  static const String _incomingMessageSoundAsset =
      'assets/sounds/incoming_message_long_pop.wav';

  static void _e2eFlowLog(String step, [Map<String, dynamic>? data]) {
    if (kDebugMode) debugPrint('[E2E-FLOW] $step | ${data ?? {}}');
  }

  // ---------- Dependencies ----------

  late final ApiService _api = ApiService(baseUrl: AppConfig.baseUrl);
  final MediaCryptoService _mediaCrypto = MediaCryptoService();

  /// Callback to emit socket events. Set by the wiring layer.
  void Function(String event, dynamic data)? _emit;

  /// Cross-provider references, set by the wiring layer.
  EncryptionProvider? _encryptionProvider;
  ConversationsProvider? _conversationsProvider;

  /// Auth token for REST calls (media upload, link preview).
  String? _tokenForReconnect;

  int? _currentUserId;

  /// Active conversation ID — uses test override if set, otherwise reads from ConversationsProvider.
  int? get _effectiveActiveConversationId =>
      _activeConversationIdOverrideForTest ??
      _conversationsProvider?.activeConversationId;

  /// Test-only override for activeConversationId.
  int? _activeConversationIdOverrideForTest;

  // ---------- E2E Encryption ----------

  /// Single delayed retry for a failed text message (e.g. recipient had no key bundle, then came online).
  Timer? _delayedRetryTimer;
  String? _delayedRetryTempId;
  bool _decryptingHistory = false;
  /// Peers whose messages failed during the current history decrypt pass.
  Set<int>? _historyDecryptFailedPeers;
  /// Dedupes session-rebuild emits within one history decrypt pass.
  Set<int>? _historySessionRebuildRequested;

  /// Sender peer IDs still showing [encrypted] after history decrypt — UI snackbar + SESSION_RESET.
  Set<int>? _pendingE2eRecoveryPeerIds;

  /// History arrived before E2E finished initializing (common on iOS PWA cold open).
  bool _pendingHistoryDecryptAfterE2EReady = false;

  /// Peers whose live decrypt failed; retried after a short debounce (no per-message SESSION_RESET).
  final Set<int> _liveDecryptFailedPeers = {};
  Timer? _liveDecryptRetryTimer;

  /// Incremented on each new messageHistory to cancel stale in-flight decrypt loops.
  /// Each loop captures its generation at start and exits when the counter changes.
  int _decryptHistoryGeneration = 0;
  final List<Map<String, dynamic>> _incomingMessageQueue = [];

  /// Serializes live decrypt per sender so Signal ratchet order is preserved.
  final Map<int, Future<void>> _decryptChainBySender = {};

  /// Plaintext content + link preview + type/media keyed by tempId — survives
  /// _messages list overwrites (e.g. when messageHistory arrives before messageSent).
  /// Value: {'content': String, 'messageType'?: String, 'mediaUrl'?: String,
  ///         'mediaDuration'?: int, 'linkPreviewUrl'?: String, ...}
  final Map<String, Map<String, dynamic>> _pendingSendContent = {};

  // Monotonic counter for temporary negative message IDs — prevents collision
  // if two messages are sent within the same millisecond.
  static int _tempIdSeq = 0;

  // ---------- Message State ----------

  static const int _pageSize = 50;
  List<MessageModel> _messages = [];
  bool _isLoadingMore = false;
  bool _hasMore = false;
  int _paginationConversationId = -1;
  int _paginationOffset = 0;
  bool _isPaginationLoad = false;
  Completer<void>? _paginationCompleter;

  /// Monotonic id per [getMessages] emit; paired FIFO in [_pendingHistoryFetchSeq].
  int _historyFetchSeq = 0;
  final Map<int, List<int>> _pendingHistoryFetchSeq = {};

  /// Per-conversation message cache for the current session.
  /// Populated/updated by onMessageHistory (after decryption) and all mutation handlers.
  /// Survives back-navigation (clearMessages) and socket reconnects (onConnect).
  /// Cleared only on logout (clearAll).
  final Map<int, List<MessageModel>> _conversationCache = {};

  /// IDs of messages we were told were deleted (messageDeleted). Used so a late
  /// messageHistory response doesn't re-add them.
  final Set<int> _deletedMessageIds = {};

  /// Message being replied to (set when user taps Reply in bubble bottom sheet).
  MessageModel? _replyingToMessage;

  bool _showPingEffect = false;
  AudioPlayer? _incomingMessageSoundPlayer;
  bool _incomingMessageSoundEnabled = true;

  // ---------- Typing / Recording Indicators ----------

  final Map<int, bool> _typingStatus = {};
  final Map<int, Timer> _typingTimers = {};
  final Map<int, bool> _partnerRecordingVoice = {}; // conversationId -> isRecording

  /// Ticks every second for countdown display. Bubbles use ValueListenableBuilder
  /// so only they rebuild, not the whole screen. Prevents recording timer freeze.
  final ValueNotifier<int> countdownTickNotifier = ValueNotifier(0);

  /// True while user holds mic to record. Countdown timer skips ticks to avoid
  /// starving the recording timer callback (progressive freeze).
  bool isRecordingVoice = false;

  // ---------- Public Getters ----------

  List<MessageModel> get messages => _messages;
  MessageModel? get replyingToMessage => _replyingToMessage;
  bool get showPingEffect => _showPingEffect;
  bool get isDecryptingHistory => _decryptingHistory;
  int? get currentUserId => _currentUserId;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMoreMessages => _hasMore;

  /// Peers with undecryptable inbound messages after the last history pass (for snackbar).
  Set<int>? consumePendingE2eRecoveryPeerIds() {
    final pending = _pendingE2eRecoveryPeerIds;
    _pendingE2eRecoveryPeerIds = null;
    return pending;
  }

  /// Whether a warm message cache exists for [conversationId].
  bool hasCachedMessages(int conversationId) =>
      _conversationCache.containsKey(conversationId);

  /// Immediately populates [_messages] from RAM cache if available and calls notifyListeners().
  /// Returns true if cache was used — caller can then skip expensive initial scroll setup.
  /// Always follow this with getMessages() to sync new messages from server.
  bool loadCachedMessages(int conversationId) {
    final cached = _conversationCache[conversationId];
    if (cached == null || cached.isEmpty) return false;
    final now = DateTime.now();
    _messages = List.from(
      cached.where((m) => !isMessageExpired(m, now)),
    );
    notifyListeners();
    return true;
  }

  /// Snapshots messages for [conversationId] into cache.
  /// Filters by conversationId so async paths are safe if _messages holds another conversation.
  /// Removes the cache entry if the filtered list is empty (keeps hasCachedMessages consistent).
  void _updateCache(int conversationId) {
    final now = DateTime.now();
    final filtered = List<MessageModel>.from(
      _messages.where(
        (m) =>
            m.conversationId == conversationId && !isMessageExpired(m, now),
      ),
    );
    if (filtered.isEmpty) {
      _conversationCache.remove(conversationId);
      return;
    }
    final existing = _conversationCache[conversationId];
    if (existing == null || existing.isEmpty) {
      _conversationCache[conversationId] = filtered;
    } else {
      _conversationCache[conversationId] = _mergeHistorySnapshot(
        existingForConv: existing,
        serverSnapshot: filtered,
      );
    }
  }

  /// Test-only: seed the cache directly without going through onMessageHistory.
  @visibleForTesting
  void seedCacheForTest(int conversationId, List<MessageModel> messages) {
    _conversationCache[conversationId] = List.from(messages);
  }

  @visibleForTesting
  MessageModel? cacheMessageForTest(int conversationId, int messageId) {
    final list = _conversationCache[conversationId];
    if (list == null) return null;
    for (final m in list) {
      if (m.id == messageId) return m;
    }
    return null;
  }

  void _trackHistoryFetch(int conversationId) {
    final seq = ++_historyFetchSeq;
    _pendingHistoryFetchSeq
        .putIfAbsent(conversationId, () => <int>[])
        .add(seq);
  }

  void _acknowledgeHistoryFetch(int? conversationId) {
    if (conversationId == null) return;
    final pending = _pendingHistoryFetchSeq[conversationId];
    if (pending != null && pending.isNotEmpty) {
      pending.removeAt(0);
      if (pending.isEmpty) {
        _pendingHistoryFetchSeq.remove(conversationId);
      }
    }
  }

  /// True when a newer [getMessages] was issued before this response arrived.
  bool _isStaleHistoryFetch(int conversationId) {
    final pending = _pendingHistoryFetchSeq[conversationId];
    return pending != null && pending.length > 1;
  }

  static int _deliveryStatusRank(MessageDeliveryStatus status) {
    switch (status) {
      case MessageDeliveryStatus.sending:
      case MessageDeliveryStatus.failed:
        return 0;
      case MessageDeliveryStatus.sent:
        return 1;
      case MessageDeliveryStatus.delivered:
        return 2;
      case MessageDeliveryStatus.read:
        return 3;
    }
  }

  static const String _kDecryptionFailedLabel = '[Decryption failed]';
  static const String _kEncryptedPlaceholderLabel = '[encrypted]';

  /// Self-hosted `/media/msgs/*.bin` blobs are AES-GCM encrypted; keys live only in the E2E envelope.
  bool _requiresEncryptedMediaKeys(MessageModel msg) {
    final url = msg.mediaUrl;
    if (url == null || url.isEmpty || !url.contains('/media/msgs/')) {
      return false;
    }
    switch (msg.messageType) {
      case MessageType.image:
      case MessageType.gif:
      case MessageType.voice:
      case MessageType.file:
        return true;
      default:
        return false;
    }
  }

  bool _missingEncryptedMediaKeys(MessageModel msg) =>
      _requiresEncryptedMediaKeys(msg) &&
      (msg.mediaKey == null || msg.mediaIv == null);

  /// Prefer higher delivery status, non-null expiry fields, and local decrypted text.
  MessageModel _mergeMessagePreferNewer(MessageModel local, MessageModel server) {
    final localRank = _deliveryStatusRank(local.deliveryStatus);
    final serverRank = _deliveryStatusRank(server.deliveryStatus);
    final deliveryStatus =
        serverRank >= localRank ? server.deliveryStatus : local.deliveryStatus;

    DateTime? expiresAt = server.expiresAt ?? local.expiresAt;
    if (server.expiresAt != null && local.expiresAt != null) {
      expiresAt = server.expiresAt!.isAfter(local.expiresAt!)
          ? server.expiresAt
          : local.expiresAt;
    }

    final disappearAfterSeconds =
        server.disappearAfterSeconds ?? local.disappearAfterSeconds;

    var content = local.content;
    // Keep failure label over server "[encrypted]" on reload; successful decrypt wins.
    if (local.content == _kDecryptionFailedLabel) {
      if (!server.displayAsEncryptedPlaceholder &&
          server.content.isNotEmpty &&
          server.content != _kDecryptionFailedLabel) {
        content = server.content;
      } else {
        content = _kDecryptionFailedLabel;
      }
    } else if (!server.displayAsEncryptedPlaceholder &&
        (local.displayAsEncryptedPlaceholder ||
            local.content == _kEncryptedPlaceholderLabel ||
            local.content.isEmpty) &&
        (server.content.isNotEmpty ||
            server.messageType != MessageType.text ||
            server.mediaUrl != null ||
            server.mediaKey != null)) {
      content = server.content;
    } else if (server.content.isNotEmpty &&
        !server.displayAsEncryptedPlaceholder &&
        local.content == _kEncryptedPlaceholderLabel) {
      content = server.content;
    }

    final messageType = local.messageType != MessageType.text &&
            server.messageType == MessageType.text
        ? local.messageType
        : server.messageType;

    return server.copyWith(
      deliveryStatus: deliveryStatus,
      expiresAt: expiresAt,
      disappearAfterSeconds: disappearAfterSeconds,
      content: content,
      messageType: messageType,
      mediaUrl: local.mediaUrl ?? server.mediaUrl,
      mediaDuration: local.mediaDuration ?? server.mediaDuration,
      mediaKey: local.mediaKey ?? server.mediaKey,
      mediaIv: local.mediaIv ?? server.mediaIv,
      linkPreviewUrl: local.linkPreviewUrl ?? server.linkPreviewUrl,
      linkPreviewTitle: local.linkPreviewTitle ?? server.linkPreviewTitle,
      linkPreviewImageUrl:
          local.linkPreviewImageUrl ?? server.linkPreviewImageUrl,
    );
  }

  bool _isDuplicateDecryptError(Object e) =>
      e.toString().contains('DuplicateMessageException');

  bool _isNoSessionDecryptError(Object e) =>
      e.toString().contains('NoSessionException');

  /// Merges [decrypted] into the open chat row when present; returns the row used.
  MessageModel _mergeDecryptedIntoState(MessageModel decrypted) {
    final idx = _messages.indexWhere((m) => m.id == decrypted.id);
    if (idx == -1) return decrypted;
    final merged = _mergeMessagePreferNewer(_messages[idx], decrypted);
    _messages[idx] = merged;
    return merged;
  }

  List<MessageModel> _mergeHistorySnapshot({
    required List<MessageModel> existingForConv,
    required List<MessageModel> serverSnapshot,
  }) {
    final serverIds = <int>{
      for (final m in serverSnapshot)
        if (m.id > 0) m.id,
    };
    final serverTempIds = <String>{
      for (final m in serverSnapshot)
        if (m.tempId != null) m.tempId!,
    };

    final mergedById = <int, MessageModel>{};

    for (final m in existingForConv) {
      if (m.id > 0 && !serverIds.contains(m.id)) {
        mergedById[m.id] = m;
      }
    }

    for (final m in serverSnapshot) {
      if (m.id <= 0) continue;
      final prev = mergedById[m.id];
      mergedById[m.id] =
          prev != null ? _mergeMessagePreferNewer(prev, m) : m;
    }

    final optimistic = <MessageModel>[];
    for (final m in existingForConv) {
      if (m.id > 0) continue;
      if (m.tempId != null && serverTempIds.contains(m.tempId)) continue;
      optimistic.add(m);
    }

    final merged = <MessageModel>[...mergedById.values, ...optimistic];
    merged.sort((a, b) {
      final byTime = a.createdAt.compareTo(b.createdAt);
      if (byTime != 0) return byTime;
      return a.id.compareTo(b.id);
    });
    return merged;
  }

  void _mergeServerSnapshotIntoCache(
    int conversationId,
    List<MessageModel> serverSnapshot,
  ) {
    final existing = _conversationCache[conversationId] ?? [];
    _conversationCache[conversationId] = _mergeHistorySnapshot(
      existingForConv: existing,
      serverSnapshot: serverSnapshot,
    );
  }

  void _finishHistoryDecryptPass(
    int generation, {
    required int? conversationId,
    required bool updateCache,
  }) {
    if (_decryptHistoryGeneration != generation) return;
    _decryptingHistory = false;
    if (updateCache && conversationId != null) {
      _updateCache(conversationId);
    }
    _reEnrichAllReplyQuotes();
    notifyListeners();
    _processIncomingMessageQueue();
  }

  /// Loaded row for the open chat (oldest-first), if present.
  MessageModel? messageById(int messageId) {
    for (final m in _messages) {
      if (m.id == messageId) return m;
    }
    return null;
  }

  MessageModel _enrichReplyPreview(MessageModel msg) {
    return enrichMessageReplyPreview(
      msg,
      encryption: _encryptionProvider,
      messagesForLookup: _messages,
    );
  }

  void _reEnrichAllReplyQuotes() {
    for (var i = 0; i < _messages.length; i++) {
      final enriched = _enrichReplyPreview(_messages[i]);
      if (enriched != _messages[i]) {
        _messages[i] = enriched;
      }
    }
  }

  ReplyToPreview? _buildReplyPreviewFromReplyingTo() {
    final rt = _replyingToMessage;
    if (rt == null) return null;
    const labels = kReplyPreviewLabels;
    return ReplyToPreview(
      id: rt.id,
      content: replyPreviewForMessageModel(
        rt,
        encryption: _encryptionProvider,
        encryptedMessageLabel: labels.encryptedMessageLabel,
        voiceMessageLabel: labels.voiceMessageLabel,
        imageLabel: labels.imageLabel,
        gifLabel: labels.gifLabel,
        documentLabel: labels.documentLabel,
        pingLabel: labels.pingLabel,
      ),
      senderUsername: rt.senderUsername,
      messageType: rt.messageType,
    );
  }

  void _clearReplyingToAfterSendStart() {
    if (_replyingToMessage != null) {
      _replyingToMessage = null;
      notifyListeners();
    }
  }

  Future<void> _waitForE2EReady({int maxAttempts = 100}) async {
    for (var i = 0; i < maxAttempts; i++) {
      if (_encryptionProvider?.isE2EReady ?? false) return;
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  bool _conversationHasUndecryptedInbound(int conversationId) {
    return _messages.any(
      (m) =>
          m.conversationId == conversationId &&
          m.needsDecryption(_currentUserId) &&
          (m.displayAsEncryptedPlaceholder ||
              m.content == _kDecryptionFailedLabel),
    );
  }

  /// Re-run ordered history decrypt for the open chat (after E2E init or session mismatch).
  Future<void> retryDecryptActiveConversation() async {
    final convId = _effectiveActiveConversationId;
    if (convId == null) return;
    if (!(_encryptionProvider?.isE2EReady ?? false)) {
      _pendingHistoryDecryptAfterE2EReady = true;
      return;
    }
    if (!_conversationHasUndecryptedInbound(convId)) {
      _pendingHistoryDecryptAfterE2EReady = false;
      return;
    }
    _pendingHistoryDecryptAfterE2EReady = false;
    _decryptHistoryGeneration++;
    final generation = _decryptHistoryGeneration;
    _decryptingHistory = true;
    await _decryptMessageHistory(generation);
    _finishHistoryDecryptPass(
      generation,
      conversationId: convId,
      updateCache: true,
    );
  }

  Future<T> _runDecryptSerialized<T>(int senderId, Future<T> Function() action) {
    final previous = _decryptChainBySender[senderId] ?? Future<void>.value();
    final result = previous.then((_) => action());
    _decryptChainBySender[senderId] =
        result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  void _patchMessageInCache(
    int conversationId,
    int messageId,
    MessageModel Function(MessageModel current) patch,
  ) {
    final cache = _conversationCache[conversationId];
    if (cache == null) return;
    final idx = cache.indexWhere((m) => m.id == messageId);
    if (idx == -1) return;
    cache[idx] = patch(cache[idx]);
  }

  /// Test-only: set the active conversation ID (replaces ConversationsProvider wiring).
  @visibleForTesting
  void setActiveConversationIdForTest(int? id) {
    _activeConversationIdOverrideForTest = id;
  }

  @visibleForTesting
  void setIncomingMessageSoundEnabledForTest(bool enabled) {
    _incomingMessageSoundEnabled = enabled;
  }

  bool isPartnerTyping(int conversationId) =>
      _typingStatus[conversationId] ?? false;

  bool isPartnerRecordingVoice(int conversationId) =>
      _partnerRecordingVoice[conversationId] ?? false;

  /// Update recording state and notify listeners. Called from ChatInputBar widget.
  void setIsRecordingVoice(bool value) {
    isRecordingVoice = value;
    notifyListeners();
  }

  // ---------- Dependency Wiring ----------

  /// Wire the EncryptionProvider for E2E operations.
  void setEncryptionProvider(EncryptionProvider ep) {
    _encryptionProvider = ep;
  }

  /// Wire the ConversationsProvider for lastMessage/unread updates.
  void setConversationsProvider(ConversationsProvider cp) {
    _conversationsProvider = cp;
  }

  /// Wire the socket emit callback so MessagingProvider can send events
  /// without depending on SocketService directly.
  void setEmitCallback(void Function(String event, dynamic data) emit) {
    _emit = emit;
  }

  /// Set the current user ID and auth token. Called on connect.
  void setCurrentUserId(int userId) {
    _currentUserId = userId;
  }

  /// Set auth token for REST calls (media upload, link preview proxy).
  void setToken(String? token) {
    _tokenForReconnect = token;
  }

  // ---------- Reply-To ----------

  VoidCallback? _composerFocusRequest;

  /// Registered by [ChatInputBar] so reply gestures can focus the composer in the
  /// same user-gesture turn (required for iOS Safari PWA keyboard).
  void setComposerFocusRequest(VoidCallback? request) {
    _composerFocusRequest = request;
  }

  void setReplyingTo(MessageModel? msg) {
    _replyingToMessage = msg;
    if (msg != null) {
      _composerFocusRequest?.call();
    }
    notifyListeners();
  }

  void clearReplyingTo() {
    if (_replyingToMessage != null) {
      _replyingToMessage = null;
      notifyListeners();
    }
  }

  // ---------- Ping Effect ----------

  void clearPingEffect() {
    _showPingEffect = false;
    notifyListeners();
  }

  // ---------- Event Handlers (socket events) ----------

  void onNewMessage(dynamic data) {
    _handleIncomingMessage(data);
  }

  void onMessageSent(dynamic data) {
    _handleIncomingMessage(data);
  }

  void onMessageHistory(dynamic data) {
    final effectiveActive = _effectiveActiveConversationId;

    int? responseConversationId;
    List<dynamic> list;
    if (data is Map<String, dynamic> &&
        data.containsKey('conversationId') &&
        data.containsKey('messages')) {
      responseConversationId = (data['conversationId'] as num).toInt();
      list = data['messages'] as List<dynamic>;
    } else if (data is List<dynamic>) {
      list = data;
    } else {
      return;
    }
    if (responseConversationId != null &&
        effectiveActive != null &&
        responseConversationId != effectiveActive) {
      if (_isPaginationLoad && responseConversationId == _paginationConversationId) {
        _finishPaginationLoad();
        notifyListeners();
      }
      return;
    }
    final newMessages = list
        .map((m) => _enrichReplyPreview(
            MessageModel.fromJson(m as Map<String, dynamic>)))
        .toList();

    if (_isPaginationLoad) {
      if (responseConversationId != null &&
          responseConversationId != _paginationConversationId) {
        _finishPaginationLoad();
        notifyListeners();
        return;
      }

      _messages = [...newMessages, ..._messages];
      _paginationOffset += newMessages.length;
      _hasMore = newMessages.length == _pageSize;
      _finishPaginationLoad();
      notifyListeners();

      _decryptHistoryGeneration++;
      final myGeneration = _decryptHistoryGeneration;
      final cacheId = _paginationConversationId;
      _decryptingHistory = true;
      _decryptMessageHistory(myGeneration).whenComplete(() {
        _finishHistoryDecryptPass(
          myGeneration,
          conversationId: cacheId,
          updateCache: true,
        );
      });
      return;
    }

    if (responseConversationId != null &&
        responseConversationId != _paginationConversationId) {
      final matchesActive = effectiveActive != null &&
          responseConversationId == effectiveActive;
      final paginationUnset = _paginationConversationId < 0;
      if (!matchesActive && !paginationUnset) {
        return;
      }
      _paginationConversationId = responseConversationId;
      _paginationOffset = 0;
    }

    final convIdForMerge =
        responseConversationId ?? _effectiveActiveConversationId;
    final staleHistory = convIdForMerge != null &&
        _isStaleHistoryFetch(convIdForMerge);
    _acknowledgeHistoryFetch(convIdForMerge);

    if (staleHistory) {
      _mergeServerSnapshotIntoCache(convIdForMerge, newMessages);
      // A newer getMessages owns _decryptingHistory — do not release the hold here.
      return;
    }

    final existingForConv = List<MessageModel>.from(
      _messages.where(
        (m) =>
            convIdForMerge == null || m.conversationId == convIdForMerge,
      ),
    );
    _messages = _mergeHistorySnapshot(
      existingForConv: existingForConv,
      serverSnapshot: newMessages,
    );
    _hasMore = newMessages.length == _pageSize;
    _paginationOffset = newMessages.length;

    // Cancel any in-flight decrypt so we process the latest messages
    _decryptHistoryGeneration++;

    // Don't re-add messages we already received as deleted
    _messages.removeWhere((m) => _deletedMessageIds.contains(m.id));

    // Immediately remove any already-expired messages
    final now = DateTime.now();
    _messages.removeWhere((m) => isMessageExpired(m, now));
    notifyListeners();
    // Snapshot to cache immediately (may include encrypted placeholders for E2E messages).
    // A second snapshot runs after _decryptMessageHistory completes with decrypted content.
    // Note: legacy bare-array payloads (responseConversationId == null) skip this first snapshot;
    // only the post-decrypt snapshot via myConversationId runs for them. This is acceptable
    // because the bare-array path is not used by the current protocol.
    if (responseConversationId != null) {
      _updateCache(responseConversationId);
    }

    if (effectiveActive != null) {
      markConversationRead(effectiveActive);
    }

    // Decrypt history first so no live message advances the session before
    // we decrypt in order. Queue any incoming messages until done.
    final myConversationId =
        responseConversationId ?? _effectiveActiveConversationId;
    final myGeneration = _decryptHistoryGeneration;
    _decryptingHistory = true;
    _decryptMessageHistory(myGeneration).whenComplete(() {
      _finishHistoryDecryptPass(
        myGeneration,
        conversationId: myConversationId,
        updateCache: true,
      );
    });
  }

  void getMessages(int conversationId) {
    _finishPaginationLoad();
    _paginationConversationId = conversationId;
    _paginationOffset = 0;
    _hasMore = false;
    _trackHistoryFetch(conversationId);
    _emit?.call('getMessages', {
      'conversationId': conversationId,
      'limit': _pageSize,
      'offset': 0,
    });
  }

  Future<void> loadOlderMessages(int conversationId) {
    if (!_hasMore) return Future<void>.value();
    if (_isLoadingMore) {
      return _paginationCompleter?.future ?? Future<void>.value();
    }
    _isLoadingMore = true;
    _isPaginationLoad = true;
    _paginationCompleter = Completer<void>();
    _emit?.call('getMessages', {
      'conversationId': conversationId,
      'limit': _pageSize,
      'offset': _paginationOffset,
    });
    return _paginationCompleter!.future;
  }

  void _finishPaginationLoad() {
    _isLoadingMore = false;
    _isPaginationLoad = false;
    final completer = _paginationCompleter;
    _paginationCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  void onMessageDelivered(dynamic data) {
    _handleMessageDelivered(data);
  }

  void onMessageDeleted(dynamic data) {
    _handleMessageDeleted(data);
  }

  void onChatHistoryCleared(dynamic data) {
    _handleChatHistoryCleared(data);
  }

  void onReactionUpdated(dynamic data) {
    _handleReactionUpdated(data);
  }

  void onLinkPreviewReady(dynamic data) {
    _handleLinkPreviewReady(data);
  }

  void onPartnerTyping(dynamic data) {
    _handlePartnerTyping(data);
  }

  void onPartnerRecordingVoice(dynamic data) {
    _handlePartnerRecordingVoice(data);
  }

  /// Called by ConnectionProvider when conversationDeleted is received.
  /// Clears messages for the deleted conversation.
  void onConversationDeleted(int conversationId) {
    _messages.removeWhere((m) => m.conversationId == conversationId);
    notifyListeners();
    _conversationCache.remove(conversationId);
  }

  // ---------- Internal Handlers ----------

  void _handleIncomingMessage(dynamic data) {
    final dataMap = data as Map<String, dynamic>;
    var msg = _enrichReplyPreview(MessageModel.fromJson(dataMap));
    final activeConversationId = _effectiveActiveConversationId;

    // Queue incoming encrypted messages for active conversation while we're
    // decrypting history (so history decrypt runs first and session order is preserved).
    if (_decryptingHistory &&
        msg.conversationId == activeConversationId &&
        msg.needsDecryption(_currentUserId)) {
      _incomingMessageQueue.add(dataMap);
      return;
    }
    _e2eFlowLog('RECV_MSG', {
      'msgId': msg.id,
      'senderId': msg.senderId,
      'hasEncryptedContent':
          msg.encryptedContent != null && msg.encryptedContent!.isNotEmpty,
      'needsDecryption': msg.needsDecryption(_currentUserId),
    });
    // If encrypted, decrypt async and update in-place
    if (msg.needsDecryption(_currentUserId)) {
      _addMessageToState(msg);
      _decryptMessageAsyncQueued(msg).then((decrypted) async {
        final merged = _mergeDecryptedIntoState(decrypted);
        _encryptionProvider?.cacheDecryption(merged.id, merged);
        await _persistDecryptedContent(merged);
        if (_hasUsableDecryptedContent(merged)) {
          _reEnrichAllReplyQuotes();
        }
        final idx = _messages.indexWhere((m) => m.id == merged.id);
        final lastMessages = _conversationsProvider?.lastMessages;
        if (lastMessages != null &&
            lastMessages[merged.conversationId]?.id == merged.id) {
          _conversationsProvider?.updateLastMessage(
              merged.conversationId, merged);
        }
        _e2eFlowLog('RECV_DECRYPT_DONE', {
          'msgId': merged.id,
          'contentLength': merged.content.length,
        });
        notifyListeners();
        // Update cache only when the message was actually updated in _messages (idx != -1).
        // If the user navigated away, idx == -1 and _messages holds a different conversation —
        // calling _updateCache would snapshot the wrong data and overwrite the valid cache entry
        // for this conversation with an empty or foreign list.
        final cid = merged.conversationId;
        if (idx != -1 && _conversationCache.containsKey(cid)) {
          _updateCache(cid);
        }
        if (merged.senderId != _currentUserId &&
            merged.messageType != MessageType.ping) {
          _playIncomingMessageSound().ignore();
        }
      });
      return;
    }

    _addMessageToState(msg);
    if (msg.senderId != _currentUserId && msg.messageType != MessageType.ping) {
      _playIncomingMessageSound().ignore();
    }
    // Keep cache current for active conversation.
    final activeIdAfterPlain = _effectiveActiveConversationId;
    if (activeIdAfterPlain != null &&
        _conversationCache.containsKey(activeIdAfterPlain)) {
      _updateCache(activeIdAfterPlain);
    }
  }

  void _processIncomingMessageQueue() {
    if (_incomingMessageQueue.isEmpty) return;
    final queue = List<Map<String, dynamic>>.from(_incomingMessageQueue);
    _incomingMessageQueue.clear();
    for (final data in queue) {
      _handleIncomingMessage(data);
    }
  }

  Future<void> _persistDecryptedContent(MessageModel decrypted) async {
    if (decrypted.content == '[Decryption failed]' ||
        decrypted.content == '[Encryption not initialized]') {
      return;
    }
    final hasText = decrypted.content.isNotEmpty;
    final hasMedia = decrypted.mediaUrl != null;
    if (!hasText && !hasMedia && decrypted.messageType == MessageType.text) {
      return;
    }
    // Validate linkPreviewImageUrl before persist (SSRF defense in depth)
    final safeImageUrl = decrypted.linkPreviewImageUrl != null &&
            decrypted.linkPreviewUrl != null &&
            LinkPreviewService.isSafeImageUrl(
              decrypted.linkPreviewImageUrl,
              decrypted.linkPreviewUrl,
            )
        ? decrypted.linkPreviewImageUrl
        : null;
    final data = <String, dynamic>{
      'content': decrypted.content,
      if (decrypted.messageType != MessageType.text)
        'messageType': decrypted.messageType.name.toUpperCase(),
      if (decrypted.mediaUrl != null) 'mediaUrl': decrypted.mediaUrl!,
      if (decrypted.mediaDuration != null)
        'mediaDuration': decrypted.mediaDuration!,
      if (decrypted.mediaKey != null) 'mediaKey': decrypted.mediaKey!,
      if (decrypted.mediaIv != null) 'mediaIv': decrypted.mediaIv!,
      if (decrypted.linkPreviewUrl != null)
        'linkPreviewUrl': decrypted.linkPreviewUrl!,
      if (decrypted.linkPreviewTitle != null)
        'linkPreviewTitle': decrypted.linkPreviewTitle!,
    };
    if (safeImageUrl != null) {
      data['linkPreviewImageUrl'] = safeImageUrl;
    }
    try {
      await _encryptionProvider?.saveDecryptedContent(decrypted.id, data);
    } catch (_) {}
  }

  void _addMessageToState(MessageModel msg) {
    final activeConversationId = _effectiveActiveConversationId;

    // If this is our own message (messageSent), replace temp optimistic message
    // and keep plaintext for display (server stores "[encrypted]" as content).
    if (msg.senderId == _currentUserId && msg.tempId != null) {
      final savedData = _pendingSendContent.remove(msg.tempId);
      final savedContent = savedData?['content'];
      final tempIndex = _messages.indexWhere((m) => m.tempId == msg.tempId);
      final tempContent = tempIndex != -1 ? _messages[tempIndex].content : null;
      if (tempIndex != -1) _messages.removeAt(tempIndex);
      final plaintextContent = savedContent ?? tempContent ?? '';
      if (msg.content == '[encrypted]') {
        final restoredType =
            _parseMessageTypeString(savedData?['messageType'] as String?);
        msg = msg.copyWith(
          content: plaintextContent.isNotEmpty ? plaintextContent : null,
          messageType: restoredType,
          mediaUrl: savedData?['mediaUrl'] as String?,
          mediaDuration: savedData?['mediaDuration'] as int?,
          mediaKey: savedData?['mediaKey'] as String?,
          mediaIv: savedData?['mediaIv'] as String?,
          linkPreviewUrl: savedData?['linkPreviewUrl'] as String?,
          linkPreviewTitle: savedData?['linkPreviewTitle'] as String?,
          linkPreviewImageUrl: savedData?['linkPreviewImageUrl'] as String?,
        );
        final persistData = <String, dynamic>{
          'content': plaintextContent,
          if (savedData?['messageType'] != null)
            'messageType': savedData!['messageType'],
          if (savedData?['mediaUrl'] != null) 'mediaUrl': savedData!['mediaUrl'],
          if (savedData?['mediaDuration'] != null)
            'mediaDuration': savedData!['mediaDuration'],
          if (savedData?['mediaKey'] != null) 'mediaKey': savedData!['mediaKey'],
          if (savedData?['mediaIv'] != null) 'mediaIv': savedData!['mediaIv'],
          if (savedData?['linkPreviewUrl'] != null)
            'linkPreviewUrl': savedData!['linkPreviewUrl'],
          if (savedData?['linkPreviewTitle'] != null)
            'linkPreviewTitle': savedData!['linkPreviewTitle'],
          if (savedData?['linkPreviewImageUrl'] != null)
            'linkPreviewImageUrl': savedData!['linkPreviewImageUrl'],
        };
        _encryptionProvider
            ?.saveDecryptedContent(msg.id, persistData)
            .ignore();
      }
    }

    // Add or update in the open chat (active id may lag openConversation briefly).
    final viewingConversationId =
        activeConversationId ?? _paginationConversationId;
    if (msg.conversationId == viewingConversationId) {
      final existingById = _messages.indexWhere((m) => m.id == msg.id && msg.id > 0);
      if (existingById != -1) {
        _messages[existingById] =
            _mergeMessagePreferNewer(_messages[existingById], msg);
      } else if (msg.tempId != null) {
        final tempIdx = _messages.indexWhere((m) => m.tempId == msg.tempId);
        if (tempIdx != -1) {
          _messages[tempIdx] = msg;
        } else {
          _messages.add(msg);
        }
      } else {
        _messages.add(msg);
      }
    }

    _conversationsProvider?.updateLastMessage(msg.conversationId, msg);
    if (msg.senderId != _currentUserId) {
      if (msg.conversationId != activeConversationId) {
        _conversationsProvider?.incrementUnreadCount(msg.conversationId);
      }
      _emit?.call('messageDelivered', {'messageId': msg.id});
      if (msg.conversationId == activeConversationId) {
        markConversationRead(msg.conversationId);
      }
    }
    // Clear typing and recording indicators when message arrives
    if (_typingStatus[msg.conversationId] == true) {
      _typingTimers[msg.conversationId]?.cancel();
      _typingTimers.remove(msg.conversationId);
      _typingStatus[msg.conversationId] = false;
    }
    _partnerRecordingVoice.remove(msg.conversationId);
    notifyListeners();
  }

  void _handleMessageDelivered(dynamic data) {
    final map = data as Map<String, dynamic>;
    final messageId = map['messageId'] as int;
    final status = map['deliveryStatus'] as String;
    final conversationId = map['conversationId'] as int?;
    final newStatus = MessageModel.parseDeliveryStatus(status);

    // Update message in _messages list (current chat)
    final index = _messages.indexWhere((m) => m.id == messageId);
    DateTime? newExpiresAt;
    final expiresAtRaw = map['expiresAt'];
    if (expiresAtRaw is String) {
      newExpiresAt = DateTime.parse(expiresAtRaw);
    }

    if (index != -1) {
      _messages[index] = _messages[index].copyWith(
        deliveryStatus: newStatus,
        expiresAt: newExpiresAt ?? _messages[index].expiresAt,
      );
    } else if (conversationId != null) {
      _patchMessageInCache(conversationId, messageId, (m) => m.copyWith(
            deliveryStatus: newStatus,
            expiresAt: newExpiresAt ?? m.expiresAt,
          ));
    }

    // Update _lastMessages so list and re-opened chat show correct status
    if (conversationId != null) {
      final lastMessages = _conversationsProvider?.lastMessages;
      if (lastMessages != null && lastMessages[conversationId]?.id == messageId) {
        _conversationsProvider?.updateLastMessage(
          conversationId,
          lastMessages[conversationId]!.copyWith(
            deliveryStatus: newStatus,
            expiresAt: newExpiresAt ?? lastMessages[conversationId]!.expiresAt,
          ),
        );
      }
    }

    if (index != -1 || conversationId != null) {
      notifyListeners();
    }
    if (index != -1) {
      final cid = _messages[index].conversationId;
      if (_conversationCache.containsKey(cid)) {
        _updateCache(cid);
      }
    }
  }

  void _handleChatHistoryCleared(dynamic data) {
    final m = data as Map<String, dynamic>;
    final conversationId = m['conversationId'] as int;

    // Clear messages from memory
    _messages.removeWhere((m) => m.conversationId == conversationId);
    _conversationsProvider?.updateLastMessage(conversationId, null);

    notifyListeners();
    _conversationCache.remove(conversationId);
  }

  void _handleMessageDeleted(dynamic data) {
    final m = data as Map<String, dynamic>;
    final messageId = m['messageId'] as int;
    final conversationId = m['conversationId'] as int;
    final forEveryone = m['forEveryone'] as bool? ?? false;

    _deletedMessageIds.add(messageId);
    _messages.removeWhere((msg) => msg.id == messageId);

    // Update last message preview for conversation list
    final lastMessages = _conversationsProvider?.lastMessages;
    if (lastMessages != null && lastMessages[conversationId]?.id == messageId) {
      final remaining =
          _messages.where((msg) => msg.conversationId == conversationId).toList();
      if (remaining.isNotEmpty) {
        remaining.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        _conversationsProvider?.updateLastMessage(conversationId, remaining.last);
      } else {
        _conversationsProvider?.updateLastMessage(conversationId, null);
      }
    }

    // If delete for everyone and we weren't viewing this chat, refresh conv list
    final activeConversationId = _conversationsProvider?.activeConversationId;
    if (forEveryone && activeConversationId != conversationId) {
      _emit?.call('getConversations', null);
    }

    notifyListeners();
    // Reflect deletion in cache; remove entry entirely if the conversation is now empty.
    if (_conversationCache.containsKey(conversationId)) {
      final remaining =
          _messages.where((m) => m.conversationId == conversationId).toList();
      if (remaining.isEmpty) {
        _conversationCache.remove(conversationId);
      } else {
        _updateCache(conversationId);
      }
    }
  }

  void _handlePartnerTyping(dynamic data) {
    final map = data as Map<String, dynamic>;
    final conversationId = map['conversationId'] as int;
    _typingStatus[conversationId] = true;
    _typingTimers[conversationId]?.cancel();
    _typingTimers[conversationId] = Timer(const Duration(seconds: 3), () {
      _typingStatus[conversationId] = false;
      _typingTimers.remove(conversationId);
      notifyListeners();
    });
    notifyListeners();
  }

  void _handleReactionUpdated(dynamic data) {
    final m = data as Map<String, dynamic>;
    final messageId = m['messageId'] as int;
    final reactionsRaw = (m['reactions'] as Map<String, dynamic>?) ?? {};
    final reactions = reactionsRaw.map(
      (k, v) => MapEntry(k, (v as List).map((e) => e as int).toList()),
    );

    final index = _messages.indexWhere((msg) => msg.id == messageId);
    if (index != -1) {
      _messages[index] = _messages[index].copyWith(reactions: reactions);
      notifyListeners();
    }
  }

  void _handleLinkPreviewReady(dynamic data) {
    final m = data as Map<String, dynamic>;
    final messageId = m['messageId'] as int;
    final index = _messages.indexWhere((msg) => msg.id == messageId);
    if (index == -1) return;
    _messages[index] = _messages[index].copyWith(
      linkPreviewUrl: m['linkPreviewUrl'] as String?,
      linkPreviewTitle: m['linkPreviewTitle'] as String?,
      linkPreviewImageUrl: m['linkPreviewImageUrl'] as String?,
    );
    notifyListeners();
  }

  void _handlePartnerRecordingVoice(dynamic data) {
    final map = data as Map<String, dynamic>;
    final conversationId = map['conversationId'] as int;
    final isRecording = map['isRecording'] as bool? ?? false;
    if (isRecording) {
      _partnerRecordingVoice[conversationId] = true;
    } else {
      _partnerRecordingVoice.remove(conversationId);
    }
    notifyListeners();
  }

  // ---------- Send Methods ----------

  void sendMessage(String content, {int? expiresIn, int? replyToMessageId}) {
    final activeConversationId = _conversationsProvider?.activeConversationId;
    if (activeConversationId == null || _currentUserId == null) return;

    final conversations = _conversationsProvider!.conversations;
    final conv = conversations.firstWhere((c) => c.id == activeConversationId);
    final recipientId = conv_helpers.getOtherUserId(conv, _currentUserId);

    // Use conversation disappearing timer if expiresIn not provided
    final effectiveExpiresIn =
        expiresIn ?? _conversationsProvider!.conversationDisappearingTimer;
    final effectiveReplyToId = replyToMessageId ?? _replyingToMessage?.id;
    final replyPreview = _buildReplyPreviewFromReplyingTo();

    // Generate unique tempId for optimistic message matching
    final tempId =
        'temp_${DateTime.now().millisecondsSinceEpoch}_$_currentUserId';

    // Create optimistic message with SENDING status
    final tempMessage = MessageModel(
      id: -(++MessagingProvider._tempIdSeq), // Monotonic temporary negative ID
      content: content,
      senderId: _currentUserId!,
      senderUsername: '', // Will be replaced when server confirms
      conversationId: activeConversationId,
      createdAt: DateTime.now(),
      deliveryStatus: MessageDeliveryStatus.sending,
      disappearAfterSeconds: effectiveExpiresIn,
      expiresAt: null,
      tempId: tempId,
      replyToMessageId: effectiveReplyToId,
      replyTo: replyPreview,
    );

    _messages.add(tempMessage);
    // Persist plaintext separately so it survives if _messages is overwritten
    // by a messageHistory response before messageSent arrives.
    // Use explicit Map type to avoid DDC/JS IdentityMap subtype errors.
    _pendingSendContent[tempId] = <String, dynamic>{'content': content};
    if (_replyingToMessage != null) {
      _replyingToMessage = null;
    }
    notifyListeners();

    // Encrypt and send asynchronously
    _encryptAndSend(
      recipientId: recipientId,
      content: content,
      tempId: tempId,
      effectiveExpiresIn: effectiveExpiresIn,
      effectiveReplyToId: effectiveReplyToId,
    );
  }

  void sendPing(int recipientId) {
    final activeConversationId = _conversationsProvider?.activeConversationId;
    if (activeConversationId == null || _currentUserId == null) return;

    final effectiveExpiresIn =
        _conversationsProvider!.conversationDisappearingTimer;
    final tempId =
        'temp_${DateTime.now().millisecondsSinceEpoch}_$_currentUserId';

    final tempMessage = MessageModel(
      id: -(++MessagingProvider._tempIdSeq),
      content: '',
      senderId: _currentUserId!,
      senderUsername: '',
      conversationId: activeConversationId,
      createdAt: DateTime.now(),
      deliveryStatus: MessageDeliveryStatus.sending,
      messageType: MessageType.ping,
      disappearAfterSeconds: effectiveExpiresIn,
      expiresAt: null,
      tempId: tempId,
    );

    _messages.add(tempMessage);
    _pendingSendContent[tempId] =
        <String, dynamic>{'content': '', 'messageType': 'PING'};
    _showPingEffect = true;
    notifyListeners();

    _encryptAndSend(
      recipientId: recipientId,
      content: '',
      tempId: tempId,
      effectiveExpiresIn: effectiveExpiresIn,
      messageType: 'PING',
    );
  }

  Future<void> sendImageMessage(
    String token,
    XFile imageFile,
    int recipientId,
  ) async {
    final activeConversationId = _conversationsProvider?.activeConversationId;
    if (activeConversationId == null || _currentUserId == null) return;

    final effectiveExpiresIn =
        _conversationsProvider!.conversationDisappearingTimer;
    final tempId =
        'temp_${DateTime.now().millisecondsSinceEpoch}_$_currentUserId';
    final effectiveReplyToId = _replyingToMessage?.id;
    final replyPreview = _buildReplyPreviewFromReplyingTo();

    // Create optimistic message
    final tempMessage = MessageModel(
      id: -(++MessagingProvider._tempIdSeq),
      content: '',
      senderId: _currentUserId!,
      senderUsername: '',
      conversationId: activeConversationId,
      createdAt: DateTime.now(),
      deliveryStatus: MessageDeliveryStatus.sending,
      messageType: MessageType.image,
      disappearAfterSeconds: effectiveExpiresIn,
      expiresAt: null,
      tempId: tempId,
      replyToMessageId: effectiveReplyToId,
      replyTo: replyPreview,
    );

    _messages.add(tempMessage);
    _pendingSendContent[tempId] =
        <String, dynamic>{'content': '', 'messageType': 'IMAGE'};
    _clearReplyingToAfterSendStart();
    notifyListeners();

    try {
      final rawBytes = await imageFile.readAsBytes();
      if (rawBytes.length > MediaCryptoService.maxBytes) {
        _markMessageFailed(tempId, 'Image too large (max 20 MB)');
        return;
      }
      final encrypted =
          await _mediaCrypto.encrypt(Uint8List.fromList(rawBytes));
      _pendingSendContent[tempId] = <String, dynamic>{
        'content': '',
        'messageType': 'IMAGE',
        'mediaKey': encrypted.keyBase64,
        'mediaIv': encrypted.ivBase64,
      };

      final responseData = await _api.uploadEncryptedMedia(
        token: token,
        encryptedBytes: encrypted.ciphertext,
        mediaType: 'image',
        expiresIn: effectiveExpiresIn,
      );

      final mediaUrl = responseData['mediaUrl'] as String;
      _pendingSendContent[tempId]!['mediaUrl'] = mediaUrl;

      final idx = _messages.indexWhere((m) => m.tempId == tempId);
      if (idx != -1) {
        _messages[idx] = _messages[idx].copyWith(
          mediaUrl: mediaUrl,
          mediaKey: encrypted.keyBase64,
          mediaIv: encrypted.ivBase64,
        );
        notifyListeners();
      }

      _encryptAndSend(
        recipientId: recipientId,
        content: '',
        tempId: tempId,
        effectiveExpiresIn: effectiveExpiresIn,
        effectiveReplyToId: effectiveReplyToId,
        messageType: 'IMAGE',
        mediaUrl: mediaUrl,
        mediaKey: encrypted.keyBase64,
        mediaIv: encrypted.ivBase64,
      );
    } catch (e) {
      debugPrint('[MessagingProvider] Image upload failed: $e');
      _markMessageFailed(tempId, 'Image upload failed: ${e.toString()}');
    }
  }

  Future<void> sendVoiceMessage({
    required int recipientId,
    required int duration,
    int? conversationId,
    String? localAudioPath,
    List<int>? localAudioBytes,
  }) async {
    if (localAudioPath == null && localAudioBytes == null) {
      throw Exception('Either localAudioPath or localAudioBytes required');
    }
    if (_currentUserId == null) {
      throw StateError('Cannot send voice message: not authenticated');
    }

    // Use provided conversationId or active one
    final effectiveConvId =
        conversationId ?? _conversationsProvider?.activeConversationId;
    if (effectiveConvId == null) {
      throw StateError('Cannot send voice message: no active conversation');
    }

    final tempId =
        'temp_${DateTime.now().millisecondsSinceEpoch}_$_currentUserId';
    final effectiveReplyToId = _replyingToMessage?.id;
    final replyPreview = _buildReplyPreviewFromReplyingTo();

    // Get disappearing timer from conversation
    final conversations = _conversationsProvider!.conversations;
    final conv = conversations.firstWhere((c) => c.id == effectiveConvId);
    final effectiveExpiresIn = conv.disappearingTimer;

    // 1. Create optimistic message
    final optimisticMessage = MessageModel(
      id: -(++MessagingProvider._tempIdSeq),
      content: '',
      senderId: _currentUserId!,
      senderUsername: '',
      conversationId: effectiveConvId,
      createdAt: DateTime.now(),
      deliveryStatus: MessageDeliveryStatus.sending,
      messageType: MessageType.voice,
      mediaUrl: localAudioPath ?? '',
      mediaDuration: duration,
      tempId: tempId,
      disappearAfterSeconds: effectiveExpiresIn,
      expiresAt: null,
      replyToMessageId: effectiveReplyToId,
      replyTo: replyPreview,
    );

    // 2. Add to messages immediately (optimistic)
    _messages.add(optimisticMessage);
    _pendingSendContent[tempId] =
        <String, dynamic>{'content': '', 'messageType': 'VOICE'};
    _conversationsProvider?.updateLastMessage(effectiveConvId, optimisticMessage);
    _clearReplyingToAfterSendStart();
    notifyListeners();

    try {
      if (_tokenForReconnect == null) {
        throw Exception('No authentication token available');
      }

      final List<int> rawBytes;
      if (localAudioBytes != null) {
        rawBytes = localAudioBytes;
      } else if (localAudioPath != null) {
        rawBytes = await file_utils.readFileBytes(localAudioPath);
      } else {
        throw Exception('Either localAudioPath or localAudioBytes required');
      }
      if (rawBytes.length > MediaCryptoService.maxBytes) {
        throw Exception('Voice file too large');
      }
      final encrypted =
          await _mediaCrypto.encrypt(Uint8List.fromList(rawBytes));
      _pendingSendContent[tempId] = <String, dynamic>{
        'content': '',
        'messageType': 'VOICE',
        'mediaDuration': duration,
        'mediaKey': encrypted.keyBase64,
        'mediaIv': encrypted.ivBase64,
      };

      final responseData = await _api.uploadEncryptedMedia(
        token: _tokenForReconnect!,
        encryptedBytes: encrypted.ciphertext,
        mediaType: 'voice',
        duration: duration,
        expiresIn: effectiveExpiresIn,
      );

      final mediaUrl = responseData['mediaUrl'] as String;
      final serverDuration =
          (responseData['mediaDuration'] as num?)?.toInt() ?? duration;
      _pendingSendContent[tempId]!['mediaUrl'] = mediaUrl;

      final index = _messages.indexWhere((m) => m.tempId == tempId);
      if (index != -1) {
        _messages[index] = _messages[index].copyWith(
          mediaUrl: mediaUrl,
          mediaDuration: serverDuration,
          mediaKey: encrypted.keyBase64,
          mediaIv: encrypted.ivBase64,
        );
        notifyListeners();
      }

      if (!kIsWeb && localAudioPath != null) {
        await file_utils.deleteFileIfExists(localAudioPath);
      }

      _encryptAndSend(
        recipientId: recipientId,
        content: '',
        tempId: tempId,
        effectiveExpiresIn: effectiveExpiresIn,
        effectiveReplyToId: effectiveReplyToId,
        messageType: 'VOICE',
        mediaUrl: mediaUrl,
        mediaDuration: serverDuration,
        mediaKey: encrypted.keyBase64,
        mediaIv: encrypted.ivBase64,
      );
    } catch (e) {
      debugPrint('[MessagingProvider] Voice upload failed: $e');
      _markMessageFailed(tempId, 'Failed to send voice message');
    }
  }

  /// Send a GIF message. Downloads from Giphy, encrypts bytes, uploads blob, E2E envelope.
  Future<void> sendGif(
    String token,
    String gifUrl,
    int recipientId,
  ) async {
    final activeConversationId = _conversationsProvider?.activeConversationId;
    if (activeConversationId == null || _currentUserId == null) return;

    final effectiveExpiresIn =
        _conversationsProvider!.conversationDisappearingTimer;
    final tempId =
        'temp_${DateTime.now().millisecondsSinceEpoch}_$_currentUserId';
    final effectiveReplyToId = _replyingToMessage?.id;
    final replyPreview = _buildReplyPreviewFromReplyingTo();

    // 1. Optimistic message
    final tempMessage = MessageModel(
      id: -(++MessagingProvider._tempIdSeq),
      content: '',
      senderId: _currentUserId!,
      senderUsername: '',
      conversationId: activeConversationId,
      createdAt: DateTime.now(),
      deliveryStatus: MessageDeliveryStatus.sending,
      messageType: MessageType.gif,
      disappearAfterSeconds: effectiveExpiresIn,
      expiresAt: null,
      tempId: tempId,
      replyToMessageId: effectiveReplyToId,
      replyTo: replyPreview,
    );

    _messages.add(tempMessage);
    _pendingSendContent[tempId] =
        <String, dynamic>{'content': '', 'messageType': 'GIF'};
    _clearReplyingToAfterSendStart();
    notifyListeners();

    try {
      // 2. Download GIF bytes from Giphy
      final response = await http.get(Uri.parse(gifUrl));
      if (response.statusCode != 200) {
        throw Exception('Failed to download GIF');
      }
      final gifBytes = response.bodyBytes;

      // 3. Size guard
      if (gifBytes.length > 5 * 1024 * 1024) {
        throw Exception('GIF too large (max 5 MB)');
      }

      final encrypted =
          await _mediaCrypto.encrypt(Uint8List.fromList(gifBytes));
      _pendingSendContent[tempId] = <String, dynamic>{
        'content': '',
        'messageType': 'GIF',
        'mediaKey': encrypted.keyBase64,
        'mediaIv': encrypted.ivBase64,
      };

      final responseData = await _api.uploadEncryptedMedia(
        token: token,
        encryptedBytes: encrypted.ciphertext,
        mediaType: 'gif',
        expiresIn: effectiveExpiresIn,
      );

      final mediaUrl = responseData['mediaUrl'] as String;
      _pendingSendContent[tempId]!['mediaUrl'] = mediaUrl;

      final idx = _messages.indexWhere((m) => m.tempId == tempId);
      if (idx != -1) {
        _messages[idx] = _messages[idx].copyWith(
          mediaUrl: mediaUrl,
          mediaKey: encrypted.keyBase64,
          mediaIv: encrypted.ivBase64,
        );
        notifyListeners();
      }

      _encryptAndSend(
        recipientId: recipientId,
        content: '',
        tempId: tempId,
        effectiveExpiresIn: effectiveExpiresIn,
        effectiveReplyToId: effectiveReplyToId,
        messageType: 'GIF',
        mediaUrl: mediaUrl,
        mediaKey: encrypted.keyBase64,
        mediaIv: encrypted.ivBase64,
      );
    } catch (e) {
      debugPrint('[MessagingProvider] GIF send failed: $e');
      _markMessageFailed(tempId, 'GIF send failed: ${e.toString()}');
    }
  }

  /// Send a file (document) message. Uploads to backend, then encrypts URL + filename in envelope.
  Future<void> sendFileMessage(
    String token,
    List<int> fileBytes,
    String fileName,
    String fileMimeType,
    int recipientId,
  ) async {
    final activeConversationId = _conversationsProvider?.activeConversationId;
    if (activeConversationId == null || _currentUserId == null) return;

    final effectiveExpiresIn =
        _conversationsProvider!.conversationDisappearingTimer;
    final tempId =
        'temp_${DateTime.now().millisecondsSinceEpoch}_$_currentUserId';
    final effectiveReplyToId = _replyingToMessage?.id;
    final replyPreview = _buildReplyPreviewFromReplyingTo();

    final tempMessage = MessageModel(
      id: -(++MessagingProvider._tempIdSeq),
      content: fileName,
      senderId: _currentUserId!,
      senderUsername: '',
      conversationId: activeConversationId,
      createdAt: DateTime.now(),
      deliveryStatus: MessageDeliveryStatus.sending,
      messageType: MessageType.file,
      disappearAfterSeconds: effectiveExpiresIn,
      expiresAt: null,
      tempId: tempId,
      replyToMessageId: effectiveReplyToId,
      replyTo: replyPreview,
    );

    _messages.add(tempMessage);
    _pendingSendContent[tempId] = <String, dynamic>{
      'content': fileName,
      'messageType': 'FILE',
    };
    _clearReplyingToAfterSendStart();
    notifyListeners();

    try {
      if (fileBytes.length > MediaCryptoService.maxBytes) {
        _markMessageFailed(tempId, 'File too large (max 20 MB)');
        return;
      }
      final encrypted =
          await _mediaCrypto.encrypt(Uint8List.fromList(fileBytes));
      _pendingSendContent[tempId] = <String, dynamic>{
        'content': fileName,
        'messageType': 'FILE',
        'mediaKey': encrypted.keyBase64,
        'mediaIv': encrypted.ivBase64,
      };

      final responseData = await _api.uploadEncryptedMedia(
        token: token,
        encryptedBytes: encrypted.ciphertext,
        mediaType: 'file',
        fileName: fileName,
      );

      final mediaUrl = responseData['mediaUrl'] as String;
      _pendingSendContent[tempId]!['mediaUrl'] = mediaUrl;

      final idx = _messages.indexWhere((m) => m.tempId == tempId);
      if (idx != -1) {
        _messages[idx] = _messages[idx].copyWith(
          mediaUrl: mediaUrl,
          mediaKey: encrypted.keyBase64,
          mediaIv: encrypted.ivBase64,
        );
        notifyListeners();
      }

      _encryptAndSend(
        recipientId: recipientId,
        content: fileName,
        tempId: tempId,
        effectiveExpiresIn: effectiveExpiresIn,
        effectiveReplyToId: effectiveReplyToId,
        messageType: 'FILE',
        mediaUrl: mediaUrl,
        mediaKey: encrypted.keyBase64,
        mediaIv: encrypted.ivBase64,
      );
    } catch (e) {
      debugPrint('[MessagingProvider] File send failed: $e');
      _markMessageFailed(tempId, 'File send failed: ${e.toString()}');
    }
  }

  /// Anti-Quantum Note: encrypt client-side, POST to server, send URL as text message.
  Future<void> sendAntiQuantumNote({
    required String content,
    required int expiresInSeconds,
  }) async {
    final token = _tokenForReconnect;
    if (token == null) return;

    // AES-256-GCM client-side encryption via WebCrypto / BoringSSL
    final keyBytes = Uint8List(32);
    fillRandomBytes(keyBytes);
    final ivBytes = Uint8List(12);
    fillRandomBytes(ivBytes);

    final aesKey = await AesGcmSecretKey.importRawKey(keyBytes);
    final plainBytes = Uint8List.fromList(utf8.encode(content));
    final ciphertextWithTag = await aesKey.encryptBytes(plainBytes, ivBytes);

    // Format: base64(iv):base64(ciphertext+tag)
    final ciphertextEncoded =
        '${base64.encode(ivBytes)}:${base64.encode(Uint8List.fromList(ciphertextWithTag))}';

    // POST /notes with ciphertext (server never sees key)
    final noteToken =
        await _api.createSecretNote(token, ciphertextEncoded, expiresInSeconds);

    // Key encoded as base64url for URL fragment (#KEY)
    final keyBase64Url = base64Url.encode(keyBytes);
    final noteUrl = '${AppConfig.baseUrl}/note/$noteToken#$keyBase64Url';

    // Send URL as a plain text message in the active conversation
    sendMessage(noteUrl);
  }

  // ---------- Message Actions ----------

  void markConversationRead(int conversationId) {
    _emit?.call('markConversationRead', {'conversationId': conversationId});
  }

  void clearChatHistory(int conversationId) {
    _emit?.call('clearChatHistory', {'conversationId': conversationId});
  }

  void deleteMessage(int messageId, {required bool forEveryone}) {
    _emit?.call('deleteMessage', {
      'messageId': messageId,
      'mode': forEveryone ? 'for_everyone' : 'for_me',
    });
  }

  void pinMessage(int conversationId, int messageId) {
    final local = messageById(messageId);
    if (local != null) {
      _conversationsProvider?.setPinnedPreviewOptimistic(
        conversationId,
        messageId,
        local,
      );
    }
    _emit?.call('pinMessage', {
      'conversationId': conversationId,
      'messageId': messageId,
    });
  }

  void unpinMessage(int conversationId) {
    _emit?.call('unpinMessage', {'conversationId': conversationId});
  }

  void addReaction(int messageId, String emoji) {
    _emit?.call('addReaction', {'messageId': messageId, 'emoji': emoji});
  }

  void removeReaction(int messageId, String emoji) {
    _emit?.call('removeReaction', {'messageId': messageId, 'emoji': emoji});
  }

  void sendTypingIndicator(int recipientId, int conversationId) {
    _emit?.call('typing', {
      'recipientId': recipientId,
      'conversationId': conversationId,
    });
  }

  /// Emit typing for the active conversation.
  void emitTyping() {
    final activeConversationId = _conversationsProvider?.activeConversationId;
    if (activeConversationId == null || _currentUserId == null) return;
    final conversations = _conversationsProvider!.conversations;
    final conv =
        conversations.where((c) => c.id == activeConversationId).firstOrNull;
    if (conv == null) return;
    final recipientId = conv_helpers.getOtherUserId(conv, _currentUserId);
    sendTypingIndicator(recipientId, activeConversationId);
  }

  /// Remove messages whose expiresAt has passed. Called every second by ChatDetailScreen timer.
  void removeExpiredMessages() {
    final now = DateTime.now();
    final hadExpiredInList = _messages.any((m) => isMessageExpired(m, now));
    var hadExpiredInCache = false;
    for (final cid in _conversationCache.keys.toList()) {
      final list = _conversationCache[cid];
      if (list == null) continue;
      final before = list.length;
      list.removeWhere((m) => isMessageExpired(m, now));
      if (list.length != before) hadExpiredInCache = true;
      if (list.isEmpty) _conversationCache.remove(cid);
    }
    if (!hadExpiredInList && !hadExpiredInCache) return;

    _messages.removeWhere((m) => isMessageExpired(m, now));
    _conversationsProvider?.pruneExpiredLastMessages();
    notifyListeners();
  }

  /// Retry sending a failed message (any type).
  Future<void> retryFailedMessage(String tempId) async {
    _cancelDelayedRetry(tempId);
    final index = _messages.indexWhere((m) => m.tempId == tempId);
    if (index == -1) return;
    final message = _messages[index];
    if (message.deliveryStatus != MessageDeliveryStatus.failed) return;

    final conversations = _conversationsProvider?.conversations ?? [];
    final conv =
        conversations.where((c) => c.id == message.conversationId).firstOrNull;
    if (conv == null) return;
    final recipientId = conv_helpers.getOtherUserId(conv, _currentUserId);

    if (message.messageType == MessageType.ping) {
      _messages[index] = _messages[index].copyWith(
        deliveryStatus: MessageDeliveryStatus.sending,
      );
      _pendingSendContent[tempId] =
          <String, dynamic>{'content': '', 'messageType': 'PING'};
      notifyListeners();
      _encryptAndSend(
        recipientId: recipientId,
        content: '',
        tempId: tempId,
        messageType: 'PING',
      );
      return;
    }

    if (message.messageType == MessageType.voice) {
      final vUrl = message.mediaUrl;
      final vKey = message.mediaKey;
      final vIv = message.mediaIv;
      // After encrypt+upload, blob URL and keys live on the model — retry E2E send only.
      if (vUrl != null &&
          vUrl.isNotEmpty &&
          vKey != null &&
          vIv != null &&
          vUrl.startsWith('http')) {
        _messages[index] = _messages[index].copyWith(
          deliveryStatus: MessageDeliveryStatus.sending,
        );
        _pendingSendContent[tempId] = <String, dynamic>{
          'content': '',
          'messageType': 'VOICE',
          'mediaUrl': vUrl,
          'mediaDuration': message.mediaDuration,
          'mediaKey': vKey,
          'mediaIv': vIv,
        };
        notifyListeners();
        _encryptAndSend(
          recipientId: recipientId,
          content: '',
          tempId: tempId,
          effectiveExpiresIn: conv.disappearingTimer,
          messageType: 'VOICE',
          mediaUrl: vUrl,
          mediaDuration: message.mediaDuration,
          mediaKey: vKey,
          mediaIv: vIv,
        );
        return;
      }
      if (message.mediaUrl != null &&
          (message.mediaUrl!.contains('cloudinary') ||
              message.mediaUrl!.contains('/media/'))) {
        _messages[index] = _messages[index].copyWith(
          deliveryStatus: MessageDeliveryStatus.sending,
        );
        _pendingSendContent[tempId] =
            <String, dynamic>{'content': '', 'messageType': 'VOICE'};
        notifyListeners();
        _encryptAndSend(
          recipientId: recipientId,
          content: '',
          tempId: tempId,
          messageType: 'VOICE',
          mediaUrl: message.mediaUrl,
          mediaDuration: message.mediaDuration,
        );
      } else {
        final localPath = message.mediaUrl;
        if (localPath == null || localPath.isEmpty) {
          return;
        }
        _messages[index] = _messages[index].copyWith(
          deliveryStatus: MessageDeliveryStatus.sending,
        );
        notifyListeners();
        await sendVoiceMessage(
          recipientId: recipientId,
          localAudioPath: localPath,
          duration: message.mediaDuration ?? 0,
          conversationId: message.conversationId,
        );
      }
      return;
    }

    if (message.messageType == MessageType.image) {
      final iUrl = message.mediaUrl;
      final iKey = message.mediaKey;
      final iIv = message.mediaIv;
      if (iUrl != null &&
          iUrl.isNotEmpty &&
          iKey != null &&
          iIv != null) {
        _messages[index] = _messages[index].copyWith(
          deliveryStatus: MessageDeliveryStatus.sending,
        );
        _pendingSendContent[tempId] = <String, dynamic>{
          'content': '',
          'messageType': 'IMAGE',
          'mediaUrl': iUrl,
          'mediaKey': iKey,
          'mediaIv': iIv,
        };
        notifyListeners();
        _encryptAndSend(
          recipientId: recipientId,
          content: '',
          tempId: tempId,
          effectiveExpiresIn: conv.disappearingTimer,
          messageType: 'IMAGE',
          mediaUrl: iUrl,
          mediaKey: iKey,
          mediaIv: iIv,
        );
        return;
      }
      if (message.mediaUrl != null &&
          (message.mediaUrl!.contains('cloudinary') ||
              message.mediaUrl!.contains('/media/'))) {
        _messages[index] = _messages[index].copyWith(
          deliveryStatus: MessageDeliveryStatus.sending,
        );
        _pendingSendContent[tempId] =
            <String, dynamic>{'content': '', 'messageType': 'IMAGE'};
        notifyListeners();
        _encryptAndSend(
          recipientId: recipientId,
          content: '',
          tempId: tempId,
          messageType: 'IMAGE',
          mediaUrl: message.mediaUrl,
        );
      }
      return;
    }

    if (message.messageType == MessageType.gif) {
      final gUrl = message.mediaUrl;
      final gKey = message.mediaKey;
      final gIv = message.mediaIv;
      if (gUrl != null &&
          gUrl.isNotEmpty &&
          gKey != null &&
          gIv != null) {
        _messages[index] = _messages[index].copyWith(
          deliveryStatus: MessageDeliveryStatus.sending,
        );
        _pendingSendContent[tempId] = <String, dynamic>{
          'content': '',
          'messageType': 'GIF',
          'mediaUrl': gUrl,
          'mediaKey': gKey,
          'mediaIv': gIv,
        };
        notifyListeners();
        _encryptAndSend(
          recipientId: recipientId,
          content: '',
          tempId: tempId,
          effectiveExpiresIn: conv.disappearingTimer,
          messageType: 'GIF',
          mediaUrl: gUrl,
          mediaKey: gKey,
          mediaIv: gIv,
        );
      }
      return;
    }

    if (message.messageType == MessageType.file) {
      final fUrl = message.mediaUrl;
      final fKey = message.mediaKey;
      final fIv = message.mediaIv;
      final fileName = message.content;
      if (fUrl != null &&
          fUrl.isNotEmpty &&
          fKey != null &&
          fIv != null) {
        _messages[index] = _messages[index].copyWith(
          deliveryStatus: MessageDeliveryStatus.sending,
        );
        _pendingSendContent[tempId] = <String, dynamic>{
          'content': fileName,
          'messageType': 'FILE',
          'mediaUrl': fUrl,
          'mediaKey': fKey,
          'mediaIv': fIv,
        };
        notifyListeners();
        _encryptAndSend(
          recipientId: recipientId,
          content: fileName,
          tempId: tempId,
          effectiveExpiresIn: conv.disappearingTimer,
          messageType: 'FILE',
          mediaUrl: fUrl,
          mediaKey: fKey,
          mediaIv: fIv,
        );
        return;
      }
      if (message.mediaUrl != null &&
          (message.mediaUrl!.contains('cloudinary') ||
              message.mediaUrl!.contains('/media/'))) {
        _messages[index] = _messages[index].copyWith(
          deliveryStatus: MessageDeliveryStatus.sending,
        );
        _pendingSendContent[tempId] = <String, dynamic>{
          'content': message.content,
          'messageType': 'FILE',
          'mediaUrl': message.mediaUrl,
        };
        notifyListeners();
        _encryptAndSend(
          recipientId: recipientId,
          content: message.content,
          tempId: tempId,
          messageType: 'FILE',
          mediaUrl: message.mediaUrl,
        );
      }
      return;
    }

    if (message.messageType == MessageType.text) {
      final content = message.content;
      final conversationId = message.conversationId;
      _messages.removeAt(index);
      final stillInConv =
          _messages.where((m) => m.conversationId == conversationId).toList();
      if (stillInConv.isNotEmpty) {
        stillInConv.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        _conversationsProvider?.updateLastMessage(
            conversationId, stillInConv.last);
      } else {
        _conversationsProvider?.updateLastMessage(conversationId, null);
      }
      notifyListeners();
      final activeConversationId = _conversationsProvider?.activeConversationId;
      if (activeConversationId == conversationId && content.isNotEmpty) {
        sendMessage(content, replyToMessageId: message.replyToMessageId);
      }
    }
  }

  // ---------- Encrypt & Send ----------

  Future<void> _encryptAndSend({
    required int recipientId,
    required String content,
    required String tempId,
    int? effectiveExpiresIn,
    int? effectiveReplyToId,
    String messageType = 'TEXT',
    String? mediaUrl,
    int? mediaDuration,
    String? mediaKey,
    String? mediaIv,
  }) async {
    final e2eReady = _encryptionProvider?.isE2EReady ?? false;
    _e2eFlowLog('SEND_START', {
      'recipientId': recipientId,
      'e2eInitialized': e2eReady,
      'messageType': messageType,
    });
    if (!e2eReady) {
      _markMessageFailed(
        tempId,
        'Encryption not ready. Please wait and try again.',
      );
      return;
    }

    try {
      // 1. Fetch client-side link preview before encrypting (TEXT only)
      Map<String, String?>? linkPreview;
      if (messageType == 'TEXT') {
        try {
          if (kIsWeb && _tokenForReconnect != null) {
            linkPreview = await _api.fetchLinkPreview(
              _tokenForReconnect!,
              content,
            );
          } else {
            linkPreview = await LinkPreviewService.fetchPreview(content);
          }
        } catch (e) {
          debugPrint('[E2E] Link preview fetch failed (non-fatal): $e');
        }
      }

      // 2. Store all fields in pending content so _addMessageToState can restore them
      final pending = _pendingSendContent[tempId];
      if (pending != null) {
        pending['messageType'] = messageType;
        if (mediaUrl != null) pending['mediaUrl'] = mediaUrl;
        if (mediaDuration != null) pending['mediaDuration'] = mediaDuration;
        if (mediaKey != null) pending['mediaKey'] = mediaKey;
        if (mediaIv != null) pending['mediaIv'] = mediaIv;
        if (linkPreview != null) {
          if (linkPreview['url'] != null) {
            pending['linkPreviewUrl'] = linkPreview['url'];
          }
          if (linkPreview['title'] != null) {
            pending['linkPreviewTitle'] = linkPreview['title'];
          }
          if (linkPreview['imageUrl'] != null) {
            pending['linkPreviewImageUrl'] = linkPreview['imageUrl'];
          }
        }
      }

      // 3. Build encrypted envelope (content + type + media + optional linkPreview)
      final envelopeJson = jsonEncode(E2eEnvelope.build(
        content,
        messageType: messageType,
        mediaUrl: mediaUrl,
        mediaDuration: mediaDuration,
        mediaKey: mediaKey,
        mediaIv: mediaIv,
        linkPreview: linkPreview,
      ));

      // 4. Ensure session exists with recipient
      await _encryptionProvider!.ensureSession(recipientId);

      // 5. Encrypt
      final ciphertext =
          await _encryptionProvider!.encrypt(recipientId, envelopeJson);
      _e2eFlowLog('SEND_ENCRYPT_DONE', {
        'recipientId': recipientId,
        'ciphertextLength': ciphertext.length,
      });

      // 6. Send encrypted payload; include type/media metadata so the server
      // can reference self-hosted blobs (orphan media cleanup, expiry deletes).
      _e2eFlowLog('SEND_EMIT', {'recipientId': recipientId});
      final emitPayload = <String, dynamic>{
        'recipientId': recipientId,
        'content': '[encrypted]',
        'encryptedContent': ciphertext,
        'expiresIn': effectiveExpiresIn,
        'tempId': tempId,
        'replyToMessageId': effectiveReplyToId,
      };
      if (messageType != 'TEXT') {
        emitPayload['messageType'] = messageType;
      }
      if (mediaUrl != null && mediaUrl.isNotEmpty) {
        emitPayload['mediaUrl'] = mediaUrl;
      }
      if (mediaDuration != null) {
        emitPayload['mediaDuration'] = mediaDuration;
      }
      _emit?.call('sendMessage', emitPayload);
    } catch (e) {
      _encryptionProvider?.clearPendingPreKeyFetch(recipientId);
      debugPrint('[E2E] Encryption failed: $e');
      _e2eFlowLog('SEND_FAIL', {
        'recipientId': recipientId,
        'error': e.toString(),
      });
      final String userMsg = _userFriendlySendError(e, recipientId);
      _markMessageFailed(tempId, userMsg);
      if (_isKeyBundleOrTimeoutError(e)) {
        _scheduleDelayedRetry(tempId);
      }
    }
  }

  @visibleForTesting
  Future<void> encryptAndSendForTest({
    required int recipientId,
    required String content,
    required String tempId,
    int? effectiveExpiresIn,
    int? effectiveReplyToId,
    String messageType = 'TEXT',
    String? mediaUrl,
    int? mediaDuration,
    String? mediaKey,
    String? mediaIv,
  }) =>
      _encryptAndSend(
        recipientId: recipientId,
        content: content,
        tempId: tempId,
        effectiveExpiresIn: effectiveExpiresIn,
        effectiveReplyToId: effectiveReplyToId,
        messageType: messageType,
        mediaUrl: mediaUrl,
        mediaDuration: mediaDuration,
        mediaKey: mediaKey,
        mediaIv: mediaIv,
      );

  // ---------- Decrypt ----------

  /// True when [msg] has displayable plaintext (or decrypted media), not an E2E placeholder.
  bool _hasUsableDecryptedContent(MessageModel msg) {
    if (msg.content == _kDecryptionFailedLabel ||
        msg.content == '[Encryption not initialized]') {
      return false;
    }
    if (_missingEncryptedMediaKeys(msg)) {
      return false;
    }
    if (!msg.needsDecryption(_currentUserId)) {
      if (msg.content == _kEncryptedPlaceholderLabel ||
          msg.displayAsEncryptedPlaceholder) {
        return false;
      }
      return true;
    }
    if (msg.displayAsEncryptedPlaceholder) return false;
    return msg.content.isNotEmpty ||
        msg.mediaUrl != null ||
        msg.messageType != MessageType.text;
  }

  void _requestSessionRebuildForPeer(int peerId) {
    _encryptionProvider?.markSessionRebuild(peerId);
    _emit?.call('requestSessionRebuild', {'recipientId': peerId});
    _e2eFlowLog('SESSION_RESET', {'peerId': peerId});
  }

  Future<void> _decryptMessageHistory(int generation) async {
    _historyDecryptFailedPeers = <int>{};
    _historySessionRebuildRequested = <int>{};
    await _waitForE2EReady(maxAttempts: 100);
    if (!(_encryptionProvider?.isE2EReady ?? false)) {
      _e2eFlowLog('HISTORY_DECRYPT_SKIP_E2E_NOT_READY', {});
      _pendingHistoryDecryptAfterE2EReady = true;
      return;
    }
    _pendingHistoryDecryptAfterE2EReady = false;
    final toDecrypt =
        _messages.where((m) => m.needsDecryption(_currentUserId)).length;
    if (toDecrypt > 0) {
      _e2eFlowLog('HISTORY_DECRYPT_START', {'count': toDecrypt});
    }
    // Double Ratchet requires decrypting in chronological order (oldest first).
    final sorted = List<MessageModel>.from(_messages)
      ..sort((a, b) {
        final byTime = a.createdAt.compareTo(b.createdAt);
        if (byTime != 0) return byTime;
        return a.id.compareTo(b.id);
      });
    bool changed = false;
    for (var i = 0; i < sorted.length; i++) {
      if (_decryptHistoryGeneration != generation) break;
      final msg = sorted[i];
      if (msg.needsDecryption(_currentUserId)) {
        // Cache-first: only skip live decrypt when cache holds real plaintext.
        final cached = _encryptionProvider?.getCachedDecryption(msg.id);
        if (cached != null && _hasUsableDecryptedContent(cached)) {
          final idx = _messages.indexWhere((m) => m.id == msg.id);
          if (idx != -1) {
            final merged = _mergeMessagePreferNewer(_messages[idx], cached);
            _messages[idx] = merged;
            _encryptionProvider?.cacheDecryption(msg.id, merged);
            changed = true;
          }
          continue;
        }
        // _encryptionProvider is non-null here: this path is reached only when
        // isE2EReady is true, which requires the provider to be set.
        final persisted =
            await _encryptionProvider!.getDecryptedContent(msg.id);
        final pContent = persisted?['content'] as String? ?? '';
        final hasPersistedPayload = persisted != null &&
            (pContent.isNotEmpty ||
                persisted['mediaUrl'] != null ||
                persisted['messageType'] != null);
        if (hasPersistedPayload) {
          final safeImageUrl = persisted['linkPreviewImageUrl'] as String?;
          final safePageUrl = persisted['linkPreviewUrl'] as String?;
          final validImage = safeImageUrl != null &&
                  safePageUrl != null &&
                  LinkPreviewService.isSafeImageUrl(safeImageUrl, safePageUrl)
              ? safeImageUrl
              : null;
          final restoredType =
              _parseMessageTypeString(persisted['messageType'] as String?);
          final restored = msg.copyWith(
            content: pContent.isNotEmpty ? pContent : msg.content,
            messageType: restoredType,
            mediaUrl: persisted['mediaUrl'] as String?,
            mediaDuration: persisted['mediaDuration'] as int?,
            mediaKey: persisted['mediaKey'] as String?,
            mediaIv: persisted['mediaIv'] as String?,
            linkPreviewUrl: persisted['linkPreviewUrl'] as String?,
            linkPreviewTitle: persisted['linkPreviewTitle'] as String?,
            linkPreviewImageUrl: validImage,
          );
          final idx = _messages.indexWhere((m) => m.id == msg.id);
          final merged = idx != -1
              ? _mergeMessagePreferNewer(_messages[idx], restored)
              : restored;
          if (_hasUsableDecryptedContent(merged)) {
            _encryptionProvider?.cacheDecryption(msg.id, merged);
            if (idx != -1) {
              _messages[idx] = merged;
              changed = true;
            }
            continue;
          }
          // Stale persisted row (mediaUrl without keys) — fall through to live decrypt.
        }
        final idx = _messages.indexWhere((m) => m.id == msg.id);
        final rowForDecrypt = idx != -1 ? _messages[idx] : msg;
        if (_hasUsableDecryptedContent(rowForDecrypt)) {
          _encryptionProvider?.cacheDecryption(msg.id, rowForDecrypt);
          continue;
        }
        // No cache — live decrypt (advances session ratchet)
        final decrypted = await _decryptMessageAsyncQueued(rowForDecrypt);
        if (idx != -1) {
          _messages[idx] = _mergeMessagePreferNewer(_messages[idx], decrypted);
          _encryptionProvider?.cacheDecryption(
            msg.id,
            _messages[idx],
          );
          changed = true;
        }
      } else if (msg.senderId == _currentUserId &&
          (msg.content == _kEncryptedPlaceholderLabel ||
              _missingEncryptedMediaKeys(msg))) {
        // _encryptionProvider is non-null here: own-message path requires E2E ready.
        final stored = await _encryptionProvider!.getDecryptedContent(msg.id);
        final storedContent = stored?['content'] as String? ?? '';
        if (storedContent.isNotEmpty ||
            (stored?['messageType'] as String?) != null ||
            stored?['mediaUrl'] != null) {
          // Restore all fields from persisted cache (SSRF validated)
          final rawImageUrl = stored?['linkPreviewImageUrl'] as String?;
          final rawPageUrl = stored?['linkPreviewUrl'] as String?;
          final safeImageUrl = rawImageUrl != null &&
                  rawPageUrl != null &&
                  LinkPreviewService.isSafeImageUrl(rawImageUrl, rawPageUrl)
              ? rawImageUrl
              : null;
          final restoredType =
              _parseMessageTypeString(stored?['messageType'] as String?);
          final restored = msg.copyWith(
            content: storedContent.isNotEmpty ? storedContent : null,
            messageType: restoredType,
            mediaUrl: stored?['mediaUrl'] as String?,
            mediaDuration: stored?['mediaDuration'] as int?,
            mediaKey: stored?['mediaKey'] as String?,
            mediaIv: stored?['mediaIv'] as String?,
            linkPreviewUrl: stored?['linkPreviewUrl'] as String?,
            linkPreviewTitle: stored?['linkPreviewTitle'] as String?,
            linkPreviewImageUrl: safeImageUrl,
          );
          final idx = _messages.indexWhere((m) => m.id == msg.id);
          if (idx != -1) {
            final merged = _mergeMessagePreferNewer(_messages[idx], restored);
            _messages[idx] = merged;
            _encryptionProvider?.cacheDecryption(msg.id, merged);
            changed = true;
          }
        }
      }
    }
    if (_decryptHistoryGeneration == generation) {
      final peersNeedingRetry = <int>{
        ...?_historyDecryptFailedPeers,
        ..._liveDecryptFailedPeers,
        for (final m in _messages)
          if (m.needsDecryption(_currentUserId) &&
              (m.displayAsEncryptedPlaceholder ||
                  m.content == _kDecryptionFailedLabel))
            m.senderId,
      };
      if (peersNeedingRetry.isNotEmpty) {
        final retried = await _retryDecryptForPeers(
          generation,
          peersNeedingRetry,
        );
        if (retried) changed = true;
      }
      if (_recoverUnresolvedEncryptedInbound(generation)) {
        changed = true;
      }
    }
    _historyDecryptFailedPeers = null;
    _historySessionRebuildRequested = null;
    if (changed) _e2eFlowLog('HISTORY_DECRYPT_DONE', {'changed': true});
    if (changed) notifyListeners();
  }

  /// When inbound rows still show [encrypted] after decrypt+retry, ask senders to rebuild session.
  bool _recoverUnresolvedEncryptedInbound(int generation) {
    if (_decryptHistoryGeneration != generation) return false;
    final unresolvedPeers = <int>{};
    for (final m in _messages) {
      if (m.needsDecryption(_currentUserId) &&
          (m.displayAsEncryptedPlaceholder ||
              m.content == _kDecryptionFailedLabel)) {
        unresolvedPeers.add(m.senderId);
      }
    }
    if (unresolvedPeers.isEmpty) return false;
    for (final peerId in unresolvedPeers) {
      _requestSessionRebuildForPeer(peerId);
    }
    _pendingE2eRecoveryPeerIds = unresolvedPeers;
    _e2eFlowLog('E2E_RECOVERY_HINT', {'peerIds': unresolvedPeers.toList()});
    return true;
  }

  /// After history/live decrypt failures, reset the local session with each peer
  /// (once per pass) and replay decrypt oldest-first. Does not downgrade
  /// [Decryption failed] to [encrypted] — failed rows stay failed until decrypt succeeds.
  Future<bool> _retryDecryptForPeers(
    int generation,
    Set<int> peerIds,
  ) async {
    bool changed = false;
    final rebuildRequested = _historySessionRebuildRequested ??= <int>{};
    for (final peerId in peerIds) {
      if (_decryptHistoryGeneration != generation) return changed;
      if (rebuildRequested.add(peerId)) {
        _requestSessionRebuildForPeer(peerId);
      }
      try {
        await _encryptionProvider?.deleteSessionWithPeer(peerId);
      } catch (e) {
        debugPrint('[E2E] deleteSessionWithPeer($peerId) failed: $e');
      }
    }

    final sorted = _messages
        .where(
          (m) =>
              peerIds.contains(m.senderId) &&
              m.needsDecryption(_currentUserId),
        )
        .toList()
      ..sort((a, b) {
        final byTime = a.createdAt.compareTo(b.createdAt);
        if (byTime != 0) return byTime;
        return a.id.compareTo(b.id);
      });

    for (final msg in sorted) {
      if (_decryptHistoryGeneration != generation) break;
      final idx = _messages.indexWhere((m) => m.id == msg.id);
      final row = idx != -1 ? _messages[idx] : msg;
      if (_hasUsableDecryptedContent(row)) {
        _encryptionProvider?.cacheDecryption(msg.id, row);
        continue;
      }
      final decrypted = await _decryptMessageAsyncQueued(row);
      if (idx == -1) continue;
      _messages[idx] = _mergeMessagePreferNewer(_messages[idx], decrypted);
      changed = true;
      if (decrypted.content != _kDecryptionFailedLabel &&
          decrypted.content != '[Encryption not initialized]') {
        _encryptionProvider?.cacheDecryption(msg.id, _messages[idx]);
        _liveDecryptFailedPeers.remove(msg.senderId);
        _encryptionProvider?.clearSessionRebuild(msg.senderId);
      }
    }
    return changed;
  }

  /// Debounced retry after live decrypt failure (no per-message SESSION_RESET).
  void _scheduleLiveDecryptRetry(int peerId) {
    _liveDecryptFailedPeers.add(peerId);
    _liveDecryptRetryTimer?.cancel();
    _liveDecryptRetryTimer = Timer(const Duration(milliseconds: 800), () {
      _liveDecryptRetryTimer = null;
      _runLiveDecryptRetries().ignore();
    });
  }

  Future<void> _runLiveDecryptRetries() async {
    if (_decryptingHistory || _liveDecryptFailedPeers.isEmpty) return;
    final peers = Set<int>.from(_liveDecryptFailedPeers);
    final gen = _decryptHistoryGeneration;
    final changed = await _retryDecryptForPeers(gen, peers);
    if (_decryptHistoryGeneration != gen) return;
    if (changed) {
      final cid = _effectiveActiveConversationId;
      if (cid != null) _updateCache(cid);
      notifyListeners();
    }
  }

  Future<MessageModel> _decryptMessageAsyncQueued(MessageModel msg) {
    if (msg.senderId == _currentUserId) {
      return Future.value(msg);
    }
    return _runDecryptSerialized(
      msg.senderId,
      () => _decryptMessageAsync(msg),
    );
  }

  Future<MessageModel> _decryptMessageAsync(MessageModel msg) async {
    // Own messages: server stored "[encrypted]" as content but we already
    // showed plaintext optimistically, so skip decryption for our own messages.
    if (msg.senderId == _currentUserId) return msg;

    // Already decrypted (e.g. live path) — never re-run ratchet decrypt on the
    // same ciphertext; that advances the session and causes Bad Mac on retry.
    if (_hasUsableDecryptedContent(msg)) return msg;

    await _waitForE2EReady();
    if (!(_encryptionProvider?.isE2EReady ?? false)) {
      return msg.copyWith(content: '[Encryption not initialized]');
    }

    _e2eFlowLog(
        'DECRYPT_START', {'msgId': msg.id, 'senderId': msg.senderId});
    try {
      final plaintext = await _encryptionProvider!.decrypt(
        msg.senderId,
        msg.encryptedContent!,
      );
      try {
        final parsed = E2eEnvelope.parse(plaintext);
        _e2eFlowLog('DECRYPT_OK', {
          'msgId': msg.id,
          'contentLength': parsed.content.length,
        });
        // SSRF: validate imageUrl before storing
        final safeImageUrl = parsed.linkPreviewImageUrl != null &&
                parsed.linkPreviewUrl != null &&
                LinkPreviewService.isSafeImageUrl(
                  parsed.linkPreviewImageUrl,
                  parsed.linkPreviewUrl,
                )
            ? parsed.linkPreviewImageUrl
            : null;
        final parsedType = _parseMessageTypeString(parsed.messageType);
        final decryptedMsg = msg.copyWith(
          content: parsed.content,
          messageType: parsedType,
          mediaUrl: parsed.mediaUrl,
          mediaDuration: parsed.mediaDuration,
          mediaKey: parsed.mediaKey,
          mediaIv: parsed.mediaIv,
          linkPreviewUrl: parsed.linkPreviewUrl,
          linkPreviewTitle: parsed.linkPreviewTitle,
          linkPreviewImageUrl: safeImageUrl,
        );
        // Trigger ping effect for recipient when decrypted type is PING
        if (parsedType == MessageType.ping &&
            msg.senderId != _currentUserId) {
          _showPingEffect = true;
        }
        _encryptionProvider?.cacheDecryption(msg.id, decryptedMsg);
        await _persistDecryptedContent(decryptedMsg);
        return decryptedMsg;
      } catch (parseErr) {
        debugPrint(
            '[E2E] Envelope parse failed for msg ${msg.id}, using raw plaintext: $parseErr');
        final fallback = msg.copyWith(content: plaintext);
        _encryptionProvider?.cacheDecryption(msg.id, fallback);
        if (plaintext.isNotEmpty) await _persistDecryptedContent(fallback);
        return fallback;
      }
    } catch (e) {
      final cached = _encryptionProvider?.getCachedDecryption(msg.id);
      if (cached != null && _hasUsableDecryptedContent(cached)) return cached;
      if (_hasUsableDecryptedContent(msg)) return msg;

      final persisted =
          await _encryptionProvider!.getDecryptedContent(msg.id);
      final persistedContent = persisted?['content'] as String? ?? '';
      final canRestorePersisted = persisted != null &&
          (persistedContent.isNotEmpty ||
              persisted['mediaUrl'] != null ||
              persisted['messageType'] != null);
      if (canRestorePersisted) {
        final rawImageUrl = persisted['linkPreviewImageUrl'] as String?;
        final rawPageUrl = persisted['linkPreviewUrl'] as String?;
        final safeImageUrl = rawImageUrl != null &&
                rawPageUrl != null &&
                LinkPreviewService.isSafeImageUrl(rawImageUrl, rawPageUrl)
            ? rawImageUrl
            : null;
        final restoredType =
            _parseMessageTypeString(persisted['messageType'] as String?);
        final restored = msg.copyWith(
          content: persistedContent.isNotEmpty ? persistedContent : msg.content,
          messageType: restoredType,
          mediaUrl: persisted['mediaUrl'] as String?,
          mediaDuration: persisted['mediaDuration'] as int?,
          mediaKey: persisted['mediaKey'] as String?,
          mediaIv: persisted['mediaIv'] as String?,
          linkPreviewUrl: persisted['linkPreviewUrl'] as String?,
          linkPreviewTitle: persisted['linkPreviewTitle'] as String?,
          linkPreviewImageUrl: safeImageUrl,
        );
        if (_hasUsableDecryptedContent(restored)) {
          _encryptionProvider?.cacheDecryption(msg.id, restored);
          return restored;
        }
      }

      if (_isDuplicateDecryptError(e) || _isNoSessionDecryptError(e)) {
        _e2eFlowLog('DECRYPT_SKIP', {
          'msgId': msg.id,
          'reason': e.toString(),
        });
        if (_decryptingHistory) {
          _historyDecryptFailedPeers?.add(msg.senderId);
        } else {
          _scheduleLiveDecryptRetry(msg.senderId);
        }
        return msg;
      }

      debugPrint('[E2E] Decrypt failed for msg ${msg.id}: $e');
      _e2eFlowLog(
          'DECRYPT_FAIL', {'msgId': msg.id, 'error': e.toString()});
      if (_decryptingHistory) {
        _historyDecryptFailedPeers?.add(msg.senderId);
      } else {
        _scheduleLiveDecryptRetry(msg.senderId);
      }
      return msg.copyWith(content: _kDecryptionFailedLabel);
    }
  }

  // ---------- Internal Helpers ----------

  Future<void> _playIncomingMessageSound() async {
    if (kIsWeb || !_incomingMessageSoundEnabled) return;
    try {
      _incomingMessageSoundPlayer ??= AudioPlayer();
      final player = _incomingMessageSoundPlayer!;
      if (player.audioSource == null) {
        await player.setAsset(_incomingMessageSoundAsset);
      }
      await player.seek(Duration.zero);
      await player.play();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[MessagingProvider] Incoming sound failed: $e');
      }
    }
  }

  void _markMessageFailed(String tempId, String errorMsg) {
    final idx = _messages.indexWhere((m) => m.tempId == tempId);
    if (idx != -1) {
      _messages[idx] = _messages[idx].copyWith(
        deliveryStatus: MessageDeliveryStatus.failed,
      );
    }
    notifyListeners();
  }

  /// Mark any message currently in "sending" state as failed.
  void markSendingMessagesFailed(String errorMsg) {
    final sending = _messages
        .where((m) => m.deliveryStatus == MessageDeliveryStatus.sending)
        .toList();
    if (sending.isEmpty) return;
    for (final msg in sending) {
      final idx = _messages.indexWhere((m) => m.tempId == msg.tempId);
      if (idx != -1) {
        _messages[idx] = _messages[idx].copyWith(
          deliveryStatus: MessageDeliveryStatus.failed,
        );
      }
    }
    notifyListeners();
  }

  bool _isKeyBundleOrTimeoutError(Object e) {
    final s = e.toString();
    return s.contains('key bundle') ||
        s.contains('no key bundle') ||
        s.contains('timed out') ||
        s.contains('Timeout') ||
        e is TimeoutException;
  }

  void _cancelDelayedRetry(String? tempId) {
    if (tempId != null && _delayedRetryTempId == tempId) {
      _delayedRetryTimer?.cancel();
      _delayedRetryTimer = null;
      _delayedRetryTempId = null;
    }
  }

  void _cancelDelayedRetryIfAny() {
    _delayedRetryTimer?.cancel();
    _delayedRetryTimer = null;
    _delayedRetryTempId = null;
  }

  void _scheduleDelayedRetry(String tempId) {
    _delayedRetryTimer?.cancel();
    _delayedRetryTempId = tempId;
    _delayedRetryTimer = Timer(const Duration(seconds: 4), () {
      _delayedRetryTimer = null;
      final tid = _delayedRetryTempId;
      _delayedRetryTempId = null;
      if (tid != null) _retrySendInPlace(tid);
      notifyListeners();
    });
  }

  void _retrySendInPlace(String tempId) {
    final idx = _messages.indexWhere((m) => m.tempId == tempId);
    if (idx == -1) return;
    final message = _messages[idx];
    if (message.deliveryStatus != MessageDeliveryStatus.failed) {
      return;
    }
    // Only auto-retry text and ping
    if (message.messageType != MessageType.text &&
        message.messageType != MessageType.ping) {
      return;
    }
    if (message.messageType == MessageType.text && message.content.isEmpty) {
      return;
    }
    final conversations = _conversationsProvider?.conversations ?? [];
    final convList =
        conversations.where((c) => c.id == message.conversationId).toList();
    if (convList.isEmpty) return;
    final conv = convList.first;
    final recipientId = conv_helpers.getOtherUserId(conv, _currentUserId);
    int? effectiveExpiresIn;
    if (message.disappearAfterSeconds != null) {
      effectiveExpiresIn = message.disappearAfterSeconds;
    } else if (message.expiresAt != null) {
      final secs = message.expiresAt!.difference(DateTime.now()).inSeconds;
      effectiveExpiresIn = secs.clamp(1, kDisappearingMaxSeconds);
    } else {
      effectiveExpiresIn = conv.disappearingTimer;
    }
    _messages[idx] =
        message.copyWith(deliveryStatus: MessageDeliveryStatus.sending);
    notifyListeners();
    _encryptAndSend(
      recipientId: recipientId,
      content: message.content,
      tempId: tempId,
      effectiveExpiresIn: effectiveExpiresIn,
      effectiveReplyToId: message.replyToMessageId,
      messageType: message.messageType.name.toUpperCase(),
    );
  }

  /// Parse a message type string from envelope/persisted data into MessageType enum.
  MessageType? _parseMessageTypeString(String? type) {
    switch (type) {
      case 'TEXT':
        return MessageType.text;
      case 'PING':
        return MessageType.ping;
      case 'VOICE':
        return MessageType.voice;
      case 'IMAGE':
        return MessageType.image;
      case 'GIF':
        return MessageType.gif;
      case 'FILE':
        return MessageType.file;
      default:
        return null;
    }
  }

  /// User-friendly error when encrypt/send fails.
  String _userFriendlySendError(Object e, int recipientId) {
    final s = e.toString();
    if (s.contains('Recipient has no key bundle') ||
        s.contains('no key bundle')) {
      final conversations = _conversationsProvider?.conversations ?? [];
      final otherName = conversations
          .where((c) =>
              conv_helpers.getOtherUserId(c, _currentUserId) == recipientId)
          .map((c) => conv_helpers.getOtherUserUsername(c, _currentUserId))
          .firstOrNull;
      final who = otherName ?? 'Recipient';
      return 'Cannot send: $who does not have encryption keys yet. Ask them to open the app.';
    }
    if (e is TimeoutException ||
        s.contains('timed out') ||
        s.contains('Timeout')) {
      return 'Timed out waiting for recipient keys. Try again.';
    }
    if (!(_encryptionProvider?.isE2EReady ?? false)) {
      return 'Encryption not ready. Wait a moment and try again.';
    }
    return 'Cannot send encrypted message. Recipient may not have encryption enabled – ask them to open the app.';
  }

  // ---------- Lifecycle ----------

  /// Called on socket connect. Clears message state for fresh connect,
  /// preserves for reconnect (same user).
  void onConnect(bool isReconnect) {
    _decryptHistoryGeneration++; // cancel any in-flight history decrypt
    _pendingHistoryFetchSeq.clear();
    _pendingE2eRecoveryPeerIds = null;
    _pendingHistoryDecryptAfterE2EReady = false;

    if (!isReconnect) {
      // Fresh connect or switch user: clear ALL message state
      _messages = [];
      _deletedMessageIds.clear();
      _typingStatus.clear();
      for (final t in _typingTimers.values) {
        t.cancel();
      }
      _typingTimers.clear();
      _partnerRecordingVoice.clear();
      _replyingToMessage = null;
      _pendingSendContent.clear();
      _incomingMessageQueue.clear();
      _cancelDelayedRetryIfAny();
    } else {
      // Reconnect (same user): keep messages to avoid flicker.
      // Clear typing/recording indicators (stale after reconnect).
      _typingStatus.clear();
      for (final t in _typingTimers.values) {
        t.cancel();
      }
      _typingTimers.clear();
      _partnerRecordingVoice.clear();
      _replyingToMessage = null;
      _pendingSendContent.clear(); // retry was cancelled; orphaned entries serve no purpose
      _cancelDelayedRetryIfAny();
    }

    notifyListeners();
  }

  /// Called on socket disconnect. Cancels timers.
  void onDisconnect() {
    _cancelDelayedRetryIfAny();
    _liveDecryptRetryTimer?.cancel();
    _liveDecryptRetryTimer = null;
    for (final t in _typingTimers.values) {
      t.cancel();
    }
    _typingTimers.clear();
  }

  /// Full reset — called on logout / account deletion.
  void clearAll() {
    _messages = [];
    _conversationCache.clear();
    _pendingHistoryFetchSeq.clear();
    _deletedMessageIds.clear();
    _typingStatus.clear();
    for (final t in _typingTimers.values) {
      t.cancel();
    }
    _typingTimers.clear();
    _partnerRecordingVoice.clear();
    _replyingToMessage = null;
    _showPingEffect = false;
    _pendingSendContent.clear();
    _incomingMessageQueue.clear();
    _decryptChainBySender.clear();
    _decryptingHistory = false;
    _decryptHistoryGeneration++;
    _liveDecryptRetryTimer?.cancel();
    _liveDecryptRetryTimer = null;
    _liveDecryptFailedPeers.clear();
    _pendingE2eRecoveryPeerIds = null;
    _pendingHistoryDecryptAfterE2EReady = false;
    _cancelDelayedRetryIfAny();
    _currentUserId = null;
    _tokenForReconnect = null;
    notifyListeners();
  }

  /// Clear messages for the active conversation (used when clearing active chat).
  void clearMessages() {
    _finishPaginationLoad();
    _messages = [];
    _hasMore = false;
    _paginationOffset = 0;
    _paginationConversationId = -1;
    notifyListeners();
  }

  @override
  void dispose() {
    _incomingMessageSoundPlayer?.dispose().ignore();
    countdownTickNotifier.dispose();
    super.dispose();
  }
}
