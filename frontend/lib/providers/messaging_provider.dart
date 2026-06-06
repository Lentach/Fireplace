import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:webcrypto/webcrypto.dart';
import '../utils/file_utils_stub.dart'
    if (dart.library.io) '../utils/file_utils_io.dart' as file_utils;

import '../config/app_config.dart';
import '../models/message_model.dart';
import '../services/api_service.dart';
import '../services/media_crypto_service.dart';
import '../services/incoming_message_sound_service.dart';
import '../services/link_preview_service.dart';
import '../utils/e2e_diag_log.dart';
import '../utils/e2e_envelope.dart';
import '../utils/message_expiry.dart';
import '../utils/reply_preview_helper.dart';
import 'conversation_helpers.dart' as conv_helpers;
import 'conversations_provider.dart';
import 'encryption_provider.dart';

part 'messaging/messaging_provider.history.dart';
part 'messaging/messaging_provider.events.dart';
part 'messaging/messaging_provider.send.dart';
part 'messaging/messaging_provider.decrypt.dart';
part 'messaging/messaging_provider.actions.dart';

// ---------- Library-private top-level helpers ----------
// Hoisted from MessagingProvider statics so the part-file extensions can
// reference them by bare name (an extension cannot see a class's statics).

void _e2eFlowLog(String step, [Map<String, dynamic>? data]) {
  E2eDiagLog.add(step, data ?? {});
  if (kDebugMode) debugPrint('[E2E-FLOW] $step | ${data ?? {}}');
}

int _deliveryStatusRank(MessageDeliveryStatus status) {
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

const int _pageSize = 50;
const String _kDecryptionFailedLabel = '[Decryption failed]';
const String _kEncryptedPlaceholderLabel = '[encrypted]';

/// MessagingProvider — owns all message state, send/receive handlers,
/// encryption orchestration, typing/recording indicators, and reactions.
/// Wired by [ConnectionProvider] and ConversationsScreen (setEncryptionProvider, setConversationsProvider).
class MessagingProvider extends ChangeNotifier {
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
  final IncomingMessageSoundService _incomingSound =
      IncomingMessageSoundService();

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

  bool _isDuplicateDecryptError(Object e) =>
      e.toString().contains('DuplicateMessageException');

  // Bad Mac = message encrypted for a different/old session key.
  // Session itself is valid — treat as terminal like DuplicateMessageException.
  bool _isBadMacDecryptError(Object e) => e.toString().contains('Bad Mac');

  bool _isNoSessionDecryptError(Object e) =>
      e.toString().contains('NoSessionException');

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
          m.displayAsEncryptedPlaceholder,
    );
  }

  /// Re-run ordered history decrypt for the open chat (after E2E init or session mismatch).
  Future<void> retryDecryptActiveConversation() async {
    final convId = _effectiveActiveConversationId;
    if (convId == null) return;
    if (!(_encryptionProvider?.isE2EReady ?? false)) {
      return;
    }
    if (!_conversationHasUndecryptedInbound(convId)) {
      return;
    }
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

  /// Test-only: set the active conversation ID (replaces ConversationsProvider wiring).
  @visibleForTesting
  void setActiveConversationIdForTest(int? id) {
    _activeConversationIdOverrideForTest = id;
  }

  @visibleForTesting
  void setIncomingMessageSoundEnabledForTest(bool enabled) {
    _incomingSound.setEnabledForTest(enabled);
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

  // ---------- Internal Handlers ----------

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

  // ---------- Send Methods ----------

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

  // ---------- Encrypt & Send ----------

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
      return;
    }
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
        if (cached != null) {
          if (cached.content == _kDecryptionFailedLabel) {
            // Terminal failure cached — restore and skip without live decrypt.
            final idx = _messages.indexWhere((m) => m.id == msg.id);
            if (idx != -1 && _messages[idx].content != _kDecryptionFailedLabel) {
              _messages[idx] = _messages[idx].copyWith(content: _kDecryptionFailedLabel);
              changed = true;
            }
            continue;
          }
          if (_hasUsableDecryptedContent(cached)) {
            final idx = _messages.indexWhere((m) => m.id == msg.id);
            if (idx != -1) {
              final merged = _mergeMessagePreferNewer(_messages[idx], cached);
              _messages[idx] = merged;
              _encryptionProvider?.cacheDecryption(msg.id, merged);
              changed = true;
            }
            continue;
          }
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
          if (pContent == _kDecryptionFailedLabel) {
            // Terminal failure persisted — restore and skip without live decrypt.
            final idx = _messages.indexWhere((m) => m.id == msg.id);
            if (idx != -1 && _messages[idx].content != _kDecryptionFailedLabel) {
              _messages[idx] = _messages[idx].copyWith(content: _kDecryptionFailedLabel);
              changed = true;
            }
            continue;
          }
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
        // [Decryption failed] is a terminal state from a prior retry — skipping
        // prevents re-triggering deleteSessionWithPeer on every reconnect, which
        // would cascade to break decryption of all subsequent messages from this peer.
        if (rowForDecrypt.content == _kDecryptionFailedLabel) continue;
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
              m.displayAsEncryptedPlaceholder)
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
      if (_markHistoryDecryptFailuresAfterRetry(generation)) {
        changed = true;
      }
    }
    _historyDecryptFailedPeers = null;
    _historySessionRebuildRequested = null;
    if (changed) _e2eFlowLog('HISTORY_DECRYPT_DONE', {'changed': true});
    if (changed) notifyListeners();
  }

  /// When inbound rows still show [encrypted] (not [Decryption failed]) after decrypt+retry, request session rebuild (silent).
  /// [Decryption failed] is terminal — excluded here to avoid markSessionRebuild on every history pass.
  bool _recoverUnresolvedEncryptedInbound(int generation) {
    if (_decryptHistoryGeneration != generation) return false;
    final unresolvedPeers = <int>{};
    for (final m in _messages) {
      if (m.needsDecryption(_currentUserId) && m.displayAsEncryptedPlaceholder) {
        unresolvedPeers.add(m.senderId);
      }
    }
    if (unresolvedPeers.isEmpty) return false;
    for (final peerId in unresolvedPeers) {
      _requestSessionRebuildForPeer(peerId);
    }
    _e2eFlowLog('E2E_RECOVERY_SESSION_RESET', {'peerIds': unresolvedPeers.toList()});
    return true;
  }

  /// After ordered history decrypt + session retry, mark rows that are still locked.
  bool _markHistoryDecryptFailuresAfterRetry(int generation) {
    if (_decryptHistoryGeneration != generation) return false;
    var changed = false;
    for (var i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      if (!m.needsDecryption(_currentUserId)) continue;
      if (!_hasUsableDecryptedContent(m) &&
          m.content != _kDecryptionFailedLabel &&
          (m.displayAsEncryptedPlaceholder ||
              m.content == _kEncryptedPlaceholderLabel)) {
        _messages[i] = m.copyWith(content: _kDecryptionFailedLabel);
        changed = true;
      }
    }
    return changed;
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

      if (_isDuplicateDecryptError(e)) {
        // Ratchet already consumed this key (message was live-decrypted earlier).
        // Session is valid — do NOT delete it or schedule retry. Mark terminal now.
        // Persist so future app starts skip this message without re-attempting.
        _e2eFlowLog('DECRYPT_DUPLICATE', {'msgId': msg.id});
        await _encryptionProvider?.saveDecryptedContent(
            msg.id, {'content': _kDecryptionFailedLabel});
        return msg.copyWith(content: _kDecryptionFailedLabel);
      }
      if (_isBadMacDecryptError(e)) {
        // MAC mismatch: message was encrypted for a different/old session key.
        // Session is valid — do NOT delete it or add to historyDecryptFailedPeers.
        // Persist so future app starts skip this message without re-attempting.
        _e2eFlowLog('DECRYPT_BAD_MAC', {'msgId': msg.id});
        await _encryptionProvider?.saveDecryptedContent(
            msg.id, {'content': _kDecryptionFailedLabel});
        return msg.copyWith(content: _kDecryptionFailedLabel);
      }
      if (_encryptionProvider?.hadIdentityReset == true) {
        // Identity was just regenerated (reinstall / storage loss).
        // All messages encrypted for the old identity are permanently unrecoverable.
        // Do NOT delete sessions or schedule retries — a fresh session will be built
        // by the next PreKey message the peer sends.
        _e2eFlowLog('DECRYPT_IDENTITY_RESET', {'msgId': msg.id});
        return msg.copyWith(content: _kDecryptionFailedLabel);
      }
      if (_isNoSessionDecryptError(e)) {
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
        // Keep [encrypted] until retry + session reset finish (see
        // [_markHistoryDecryptFailuresAfterRetry]).
        return msg;
      }
      _scheduleLiveDecryptRetry(msg.senderId);
      return msg.copyWith(content: _kDecryptionFailedLabel);
    }
  }

  // ---------- Internal Helpers ----------

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

  // ---------- Lifecycle ----------

  /// Called on socket connect. Clears message state for fresh connect,
  /// preserves for reconnect (same user).
  void onConnect(bool isReconnect) {
    _decryptHistoryGeneration++; // cancel any in-flight history decrypt
    _pendingHistoryFetchSeq.clear();

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
    _incomingSound.dispose();
    countdownTickNotifier.dispose();
    super.dispose();
  }
}
