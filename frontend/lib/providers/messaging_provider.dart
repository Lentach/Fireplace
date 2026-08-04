import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:webcrypto/webcrypto.dart';
import '../utils/file_utils_stub.dart'
    if (dart.library.io) '../utils/file_utils_io.dart'
    as file_utils;

import '../config/app_config.dart';
import '../models/message_model.dart';
import '../services/api_service.dart';
import '../services/media_crypto_service.dart';
import '../services/encrypted_media_upload_service.dart';
import '../services/encryption_service.dart';
import '../services/incoming_message_sound_service.dart';
import '../services/link_preview_service.dart';
import '../services/plaintext_record_codec.dart';
import '../utils/anti_quantum_note_link.dart';
import '../utils/decryption_failure_policy.dart';
import '../utils/e2e_diag_log.dart';
import '../utils/e2e_envelope.dart';
import '../utils/media_preview_metadata.dart';
import '../utils/e2e_persistent_diag.dart';
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
const String kRetiredMessageLabel = '[Message no longer stored on this device]';

/// MessagingProvider — owns all message state, send/receive handlers,
/// encryption orchestration, typing/recording indicators, and reactions.
/// Wired by [ConnectionProvider] and ConversationsScreen (setEncryptionProvider, setConversationsProvider).
class MessagingProvider extends ChangeNotifier {
  // ---------- Dependencies ----------

  late final ApiService _api = ApiService(baseUrl: AppConfig.baseUrl);
  final MediaCryptoService _mediaCrypto = MediaCryptoService();

  late final EncryptedMediaUploadService _mediaUploadDefault =
      EncryptedMediaUploadService(api: _api, crypto: _mediaCrypto);

  /// Test override for the media upload service. Null in production.
  /// Mirrors `_activeConversationIdOverrideForTest`.
  EncryptedMediaUploadService? _mediaUploadOverrideForTest;

  /// Effective media upload service — test override if set, else the default.
  EncryptedMediaUploadService get _mediaUpload =>
      _mediaUploadOverrideForTest ?? _mediaUploadDefault;

  @visibleForTesting
  void setMediaUploadServiceForTest(EncryptedMediaUploadService service) {
    _mediaUploadOverrideForTest = service;
  }

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

  /// Peers already told to re-key after our identity reset (once per session).
  final Set<int> _identityResetRebuildNotified = {};

  /// Peers we already sent `requestSessionRebuild` to. Cleared per peer when a
  /// decrypt from them succeeds; cleared wholesale on fresh connect/logout.
  /// Without this, every history pass re-asked the peer to re-key (the
  /// SESSION_RESET{historyRetry} loop), forcing rebuild churn on every send.
  final Set<int> _rebuildRequestedPeers = {};

  /// tempIds whose `sendMessage` emit already happened — a second emit for the
  /// same optimistic message would advance the ratchet again and hand the
  /// recipient an undecryptable duplicate. Released on send failure (so user
  /// retry works); cleared on connect/logout with [_pendingSendContent].
  final Set<String> _emittedSendTempIds = {};

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

  /// Message currently being edited (set when the user taps Edit in the context
  /// menu; cleared on send/cancel). Drives the composer "editing" banner.
  MessageModel? _editingMessage;

  /// Pre-edit row kept per messageId so a server reject (`editMessageFailed`) or
  /// an encrypt failure can restore the optimistic in-place update verbatim
  /// (copyWith can't reset editedAt to null, so we keep the whole row).
  final Map<int, MessageModel> _pendingEdits = {};

  bool _showPingEffect = false;

  /// Message ids whose ping effect already fired this provider lifetime.
  /// Transient event-dedup only (NOT a persisted played-ids cache): a
  /// redelivered/duplicate `newMessage` for a ping still reaches live decrypt,
  /// so this guarantees the effect flips at most once per id. Cleared on
  /// disconnect/fresh-connect with the rest of the transient decrypt state.
  final Set<int> _pingEffectFiredIds = {};

  /// Set in [dispose]; lets the overlay's dispose-scheduled onComplete
  /// microtask no-op instead of notifying a disposed ChangeNotifier.
  bool _pingEffectConsumerDisposed = false;
  final IncomingMessageSoundService _incomingSound =
      IncomingMessageSoundService();

  // ---------- Typing / Recording Indicators ----------

  final Map<int, bool> _typingStatus = {};
  final Map<int, Timer> _typingTimers = {};
  final Map<int, bool> _partnerRecordingVoice =
      {}; // conversationId -> isRecording

  /// Ticks every second for countdown display. Bubbles use ValueListenableBuilder
  /// so only they rebuild, not the whole screen. Prevents recording timer freeze.
  final ValueNotifier<int> countdownTickNotifier = ValueNotifier(0);

  /// True while user holds mic to record. Countdown timer skips ticks to avoid
  /// starving the recording timer callback (progressive freeze).
  bool isRecordingVoice = false;

  // ---------- Public Getters ----------

  List<MessageModel> get messages => _messages;
  MessageModel? get replyingToMessage => _replyingToMessage;
  MessageModel? get editingMessage => _editingMessage;
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

  /// Builds the optimistic (SENDING) message shown immediately for a media
  /// send, before encrypt/upload. Centralizes the fields every media path
  /// shares; per-type extras (voice `mediaUrl`/`mediaDuration`) are passed in.
  MessageModel _buildOptimisticMediaMessage({
    required String tempId,
    required int conversationId,
    required MessageType messageType,
    required String content,
    required int? effectiveExpiresIn,
    required int? effectiveReplyToId,
    String? mediaUrl,
    int? mediaDuration,
  }) {
    return MessageModel(
      id: -(++MessagingProvider._tempIdSeq),
      content: content,
      senderId: _currentUserId!,
      senderUsername: '',
      conversationId: conversationId,
      createdAt: DateTime.now(),
      deliveryStatus: MessageDeliveryStatus.sending,
      messageType: messageType,
      mediaUrl: mediaUrl,
      mediaDuration: mediaDuration,
      disappearAfterSeconds: effectiveExpiresIn,
      expiresAt: null,
      tempId: tempId,
      replyToMessageId: effectiveReplyToId,
      replyTo: _buildReplyPreviewFromReplyingTo(),
    );
  }

  Future<void> _waitForE2EReady({int maxAttempts = 100}) async {
    for (var i = 0; i < maxAttempts; i++) {
      if (_encryptionProvider?.isE2EReady ?? false) return;
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<T> _runDecryptSerialized<T>(
    int senderId,
    Future<T> Function() action,
  ) {
    final previous = _decryptChainBySender[senderId] ?? Future<void>.value();
    final result = previous.then((_) => action());
    _decryptChainBySender[senderId] = result.then<void>(
      (_) {},
      onError: (_) {},
    );
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

  /// Enter edit mode for [msg]; the composer prefills its text and routes send
  /// to [editMessage]. Focuses the composer like reply.
  void beginEditMessage(MessageModel msg) {
    _editingMessage = msg;
    _replyingToMessage = null;
    _composerFocusRequest?.call();
    notifyListeners();
  }

  /// Leave edit mode without sending.
  void cancelEditMessage() {
    if (_editingMessage != null) {
      _editingMessage = null;
      notifyListeners();
    }
  }

  // ---------- Ping Effect ----------

  void clearPingEffect() {
    // May arrive via PingEffectOverlay's dispose-scheduled microtask AFTER
    // this provider was disposed (full app teardown mid-animation) —
    // notifyListeners on a disposed ChangeNotifier is a debug assert.
    if (_pingEffectConsumerDisposed) return;
    _showPingEffect = false;
    notifyListeners();
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
      _editingMessage = null;
      _pendingEdits.clear();
      _pendingSendContent.clear();
      _emittedSendTempIds.clear();
      _incomingMessageQueue.clear();
      _identityResetRebuildNotified.clear();
      _rebuildRequestedPeers.clear();
      // Fresh connect / user switch: forget which pings already fired.
      // (Reconnect deliberately KEEPS it so resync redelivery stays silent.)
      _pingEffectFiredIds.clear();
      _cancelDelayedRetryIfAny();
    } else {
      // Reconnect (same user): keep messages to avoid flicker.
      // Clear typing/recording indicators (stale after reconnect).
      // NOTE: _rebuildRequestedPeers is deliberately KEPT on reconnect —
      // reconnect storms were exactly what re-fired the rebuild-request loop.
      _typingStatus.clear();
      for (final t in _typingTimers.values) {
        t.cancel();
      }
      _typingTimers.clear();
      _partnerRecordingVoice.clear();
      _replyingToMessage = null;
      _editingMessage = null;
      _pendingEdits.clear();
      _pendingSendContent
          .clear(); // retry was cancelled; orphaned entries serve no purpose
      _emittedSendTempIds.clear();
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
    _editingMessage = null;
    _pendingEdits.clear();
    _showPingEffect = false;
    _pendingSendContent.clear();
    _incomingMessageQueue.clear();
    _decryptChainBySender.clear();
    _decryptingHistory = false;
    _decryptHistoryGeneration++;
    _liveDecryptRetryTimer?.cancel();
    _liveDecryptRetryTimer = null;
    _liveDecryptFailedPeers.clear();
    _identityResetRebuildNotified.clear();
    _rebuildRequestedPeers.clear();
    _pingEffectFiredIds.clear();
    _emittedSendTempIds.clear();
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
    _pingEffectConsumerDisposed = true;
    // Mirror onDisconnect: none of onDisconnect / onConnect / clearAll is
    // guaranteed to run before teardown, so a pending typing / delayed-retry /
    // live-decrypt-retry timer would fire past super.dispose() and notify a
    // disposed ChangeNotifier.
    onDisconnect();
    _incomingSound.dispose();
    countdownTickNotifier.dispose();
    super.dispose();
  }
}
