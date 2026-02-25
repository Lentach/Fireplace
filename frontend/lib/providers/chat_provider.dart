import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../config/app_config.dart';
import '../constants/app_constants.dart';
import '../models/conversation_model.dart';
import '../models/friend_request_model.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';
import '../services/encryption_service.dart';
import '../services/link_preview_service.dart';
import '../utils/e2e_envelope.dart';
import '../services/push_service.dart';
import '../services/socket_service.dart';
import 'chat_reconnect_manager.dart';
import 'conversation_helpers.dart' as conv_helpers;

class ChatProvider extends ChangeNotifier {
  static void _e2eFlowLog(String step, [Map<String, dynamic>? data]) {
    if (kDebugMode) debugPrint('[E2E-FLOW] $step | ${data ?? {}}');
  }

  final SocketService _socketService = SocketService();
  final ChatReconnectManager _reconnect = ChatReconnectManager();
  late final PushService _pushService =
      PushService(ApiService(baseUrl: AppConfig.baseUrl));
  bool _pushInitialized = false;

  // ---------- E2E Encryption ----------
  final EncryptionService _encryptionService = EncryptionService();
  bool _e2eInitialized = false;
  final Map<int, Completer<Map<String, dynamic>>> _pendingPreKeyFetches = {};
  bool _generatingMoreKeys = false;
  /// Cache of decrypted messages by id. Used when history decrypt hits DuplicateMessageException (session already advanced by live messages).
  final Map<int, MessageModel> _decryptedContentCache = {};
  bool _decryptingHistory = false;
  final List<Map<String, dynamic>> _incomingMessageQueue = [];

  // ---------- State ----------
  List<ConversationModel> _conversations = [];
  List<MessageModel> _messages = [];
  int? _activeConversationId;
  int? _currentUserId;
  String? _errorMessage;
  final Map<int, MessageModel> _lastMessages = {};
  int? _pendingOpenConversationId;
  List<FriendRequestModel> _friendRequests = [];
  int _pendingRequestsCount = 0;
  List<UserModel> _friends = [];
  List<UserModel> _blockedUsers = [];
  final Set<int> _blockedByUserIds = {};
  bool _friendRequestJustSent = false;
  bool _showPingEffect = false;
  List<UserModel>? _searchResults;
  final Map<int, int> _unreadCounts = {}; // conversationId -> count
  final Map<int, bool> _typingStatus = {};
  final Map<int, Timer> _typingTimers = {};
  final Map<int, bool> _partnerRecordingVoice = {}; // conversationId -> isRecording
  /// IDs of messages we were told were deleted (messageDeleted). Used so a late messageHistory response doesn't re-add them.
  final Set<int> _deletedMessageIds = {};

  /// Ticks every second for countdown display. Bubbles use ValueListenableBuilder
  /// so only they rebuild, not the whole screen. Prevents recording timer freeze.
  final ValueNotifier<int> countdownTickNotifier = ValueNotifier(0);

  /// True while user holds mic to record. Countdown timer skips ticks to avoid
  /// starving the recording timer callback (progressive freeze).
  bool isRecordingVoice = false;

  /// Message being replied to (set when user taps Reply in bubble bottom sheet).
  MessageModel? _replyingToMessage;

  MessageModel? get replyingToMessage => _replyingToMessage;

  void setReplyingTo(MessageModel? msg) {
    _replyingToMessage = msg;
    notifyListeners();
  }

  void clearReplyingTo() {
    if (_replyingToMessage != null) {
      _replyingToMessage = null;
      notifyListeners();
    }
  }

  List<ConversationModel> get conversations => _conversations;

  /// Conversations sorted by newest message first (for list display).
  List<ConversationModel> get sortedConversations {
    final list = List<ConversationModel>.from(_conversations);
    list.sort((a, b) {
      final aTime = _lastMessages[a.id]?.createdAt ?? a.createdAt;
      final bTime = _lastMessages[b.id]?.createdAt ?? b.createdAt;
      return bTime.compareTo(aTime);
    });
    return list;
  }
  List<MessageModel> get messages => _messages;
  int? get activeConversationId => _activeConversationId;
  int? get currentUserId => _currentUserId;
  String? get errorMessage => _errorMessage;
  Map<int, MessageModel> get lastMessages => _lastMessages;
  int? get pendingOpenConversationId => _pendingOpenConversationId;
  List<FriendRequestModel> get friendRequests => _friendRequests;
  int get pendingRequestsCount => _pendingRequestsCount;
  List<UserModel> get friends => _friends;
  List<UserModel> get blockedUsers => _blockedUsers;
  Set<int> get blockedByUserIds => Set<int>.from(_blockedByUserIds);
  bool get friendRequestJustSent => _friendRequestJustSent;
  List<UserModel>? get searchResults => _searchResults;
  SocketService get socket => _socketService;

  int? get conversationDisappearingTimer {
    if (_activeConversationId == null) return null;
    final conv = _conversations
        .where((c) => c.id == _activeConversationId)
        .firstOrNull;
    return conv?.disappearingTimer;
  }

  bool get showPingEffect => _showPingEffect;

  int getUnreadCount(int conversationId) => _unreadCounts[conversationId] ?? 0;
  bool isPartnerTyping(int conversationId) => _typingStatus[conversationId] ?? false;
  bool isPartnerRecordingVoice(int conversationId) =>
      _partnerRecordingVoice[conversationId] ?? false;

  /// Returns conversation by id, or null if not found.
  ConversationModel? getConversationById(int id) =>
      _conversations.where((c) => c.id == id).firstOrNull;

  /// Clears active conversation and messages if the active conv was removed.
  void _clearActiveIfRemoved() {
    if (_activeConversationId == null) return;
    final exists = _conversations.any((c) => c.id == _activeConversationId);
    if (!exists) {
      _activeConversationId = null;
      _messages = [];
    }
  }

  void setConversationDisappearingTimer(int? seconds) {
    if (_activeConversationId == null) return;
    _socketService.emitSetDisappearingTimer(_activeConversationId!, seconds);
    // Timer will be updated when backend confirms via disappearingTimerUpdated event
  }

  void clearPingEffect() {
    _showPingEffect = false;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  // ---------- Message handlers (socket events) ----------

  void _handleIncomingMessage(dynamic data) {
    final msg = MessageModel.fromJson(data as Map<String, dynamic>);
    // Queue incoming encrypted messages for active conversation while we're decrypting history (so history decrypt runs first and session order is preserved).
    if (_decryptingHistory &&
        msg.conversationId == _activeConversationId &&
        msg.needsDecryption(_currentUserId)) {
      _incomingMessageQueue.add(data as Map<String, dynamic>);
      return;
    }
    _e2eFlowLog('RECV_MSG', {
      'msgId': msg.id,
      'senderId': msg.senderId,
      'hasEncryptedContent': msg.encryptedContent != null && msg.encryptedContent!.isNotEmpty,
      'needsDecryption': msg.needsDecryption(_currentUserId),
    });
    // If encrypted, decrypt async and update in-place
    if (msg.needsDecryption(_currentUserId)) {
      _addMessageToState(msg);
      _decryptMessageAsync(msg).then((decrypted) async {
        _decryptedContentCache[decrypted.id] = decrypted;
        await _persistDecryptedContent(decrypted);
        final idx = _messages.indexWhere((m) => m.id == decrypted.id);
        if (idx != -1) {
          _messages[idx] = decrypted;
        }
        if (_lastMessages[decrypted.conversationId]?.id == decrypted.id) {
          _lastMessages[decrypted.conversationId] = decrypted;
        }
        _e2eFlowLog('RECV_DECRYPT_DONE', {'msgId': decrypted.id, 'contentLength': decrypted.content.length});
        notifyListeners();
      });
      return;
    }

    _addMessageToState(msg);
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
    if (decrypted.content.isEmpty ||
        decrypted.content == '[Decryption failed]' ||
        decrypted.content == '[Encryption not initialized]') return;
    final data = <String, dynamic>{
      'content': decrypted.content,
      if (decrypted.linkPreviewUrl != null) 'linkPreviewUrl': decrypted.linkPreviewUrl!,
      if (decrypted.linkPreviewTitle != null) 'linkPreviewTitle': decrypted.linkPreviewTitle!,
      if (decrypted.linkPreviewImageUrl != null) 'linkPreviewImageUrl': decrypted.linkPreviewImageUrl!,
    };
    try {
      await _encryptionService.saveDecryptedContent(decrypted.id, data);
    } catch (_) {}
  }

  void _addMessageToState(MessageModel msg) {
    // If this is our own message (messageSent), replace temp optimistic message
    // and keep plaintext for display (server stores "[encrypted]" as content).
    if (msg.senderId == _currentUserId && msg.tempId != null) {
      final tempIndex = _messages.indexWhere((m) => m.tempId == msg.tempId);
      if (tempIndex != -1) {
        final plaintextContent = _messages[tempIndex].content;
        _messages.removeAt(tempIndex);
        if (msg.content == '[encrypted]' && plaintextContent.isNotEmpty) {
          msg = msg.copyWith(content: plaintextContent);
          _encryptionService.saveDecryptedContent(msg.id, {'content': plaintextContent}).catchError((_) {});
        }
      }
    }

    // Add confirmed message
    if (msg.conversationId == _activeConversationId) {
      _messages.add(msg);
    }

    _lastMessages[msg.conversationId] = msg;
    if (msg.senderId != _currentUserId) {
      if (msg.conversationId != _activeConversationId) {
        _unreadCounts[msg.conversationId] =
            (_unreadCounts[msg.conversationId] ?? 0) + 1;
      }
      _socketService.emitMessageDelivered(msg.id);
      if (msg.conversationId == _activeConversationId) {
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

  void markConversationRead(int conversationId) {
    _socketService.emitMarkConversationRead(conversationId);
  }

  int? consumePendingOpen() {
    final id = _pendingOpenConversationId;
    _pendingOpenConversationId = null;
    return id;
  }

  bool consumeFriendRequestSent() {
    final sent = _friendRequestJustSent;
    _friendRequestJustSent = false;
    return sent;
  }

  String getOtherUserUsername(ConversationModel conv) =>
      conv_helpers.getOtherUserUsername(conv, _currentUserId);

  String getOtherUserDisplayHandle(ConversationModel conv) =>
      conv_helpers.getOtherUserDisplayHandle(conv, _currentUserId);

  int getOtherUserId(ConversationModel conv) =>
      conv_helpers.getOtherUserId(conv, _currentUserId);

  UserModel? getOtherUser(ConversationModel conv) =>
      conv_helpers.getOtherUser(conv, _currentUserId);

  void connect({required String token, required int userId}) {
    _reconnect.cancel();
    _reconnect.intentionalDisconnect = false;
    _reconnect.tokenForReconnect = token;

    // Clear ALL state before connecting to prevent data leakage between users
    _conversations = [];
    _messages = [];
    _activeConversationId = null;
    _lastMessages.clear();
    _deletedMessageIds.clear();
    _unreadCounts.clear();
    _typingStatus.clear();
    for (final t in _typingTimers.values) { t.cancel(); }
    _typingTimers.clear();
    _partnerRecordingVoice.clear();
    _replyingToMessage = null;
    _pendingOpenConversationId = null;
    _friendRequests = [];
    _pendingRequestsCount = 0;
    _friends = [];
    _friendRequestJustSent = false;
    _searchResults = null;
    _errorMessage = null;
    _e2eInitialized = false;
    _pendingPreKeyFetches.clear();

    // Notify listeners immediately so UI shows empty state
    notifyListeners();

    // Clean up old socket if it exists
    if (_socketService.socket != null) {
      _socketService.disconnect();
    }

    _currentUserId = userId;
    _socketService.connect(
      baseUrl: AppConfig.baseUrl,
      token: token,
      onConnect: () {
        _reconnect.resetAttempts();
        _blockedByUserIds.clear();
        _socketService.getConversations();
        _socketService.getFriendRequests();
        _socketService.getFriends();
        _socketService.getBlockedList();
        Future.delayed(AppConstants.conversationsRefreshDelay, () {
          if (_conversations.isEmpty) {
            _socketService.getConversations();
          }
        });
        // Initialize push notifications once per session (first connect only)
        if (!_pushInitialized) {
          _pushInitialized = true;
          _pushService.initialize(token).catchError((_) {});
        }
        // Initialize E2E encryption
        _initializeE2E();
      },
      onConversationsList: (data) {
        final list = data as List<dynamic>;
        _conversations = list
            .map((c) =>
                ConversationModel.fromJson(c as Map<String, dynamic>))
            .toList();
        _unreadCounts.clear();
        for (final c in list) {
          final m = c as Map<String, dynamic>;
          final convId = m['id'] as int;
          final unread = (m['unreadCount'] as num?)?.toInt() ?? 0;
          _unreadCounts[convId] = unread;

          // Update last message from backend data (fixes preview not showing when user was offline)
          final lastMsgData = m['lastMessage'];
          if (lastMsgData != null) {
            try {
              var lastMsg = MessageModel.fromJson(lastMsgData as Map<String, dynamic>);
              if (lastMsg.displayAsEncryptedPlaceholder) {
                lastMsg = lastMsg.copyWith(content: 'Encrypted message');
              }
              _lastMessages[convId] = lastMsg;
            } catch (e) {
              debugPrint('[ChatProvider] Failed to parse lastMessage for conversation $convId: $e');
            }
          }
        }
        notifyListeners();
      },
      onMessageHistory: (data) {
        final list = data as List<dynamic>;
        _messages = list
            .map((m) => MessageModel.fromJson(m as Map<String, dynamic>))
            .toList();

        // Don't re-add messages we already received as deleted (e.g. ping deleted by other user; late messageHistory can overwrite)
        _messages.removeWhere((m) => _deletedMessageIds.contains(m.id));

        // Immediately remove any already-expired messages
        final now = DateTime.now();
        _messages.removeWhere(
          (m) => m.expiresAt != null && m.expiresAt!.isBefore(now),
        );
        notifyListeners();
        if (_activeConversationId != null) {
          markConversationRead(_activeConversationId!);
        }

        // Decrypt history first so no live message advances the session before we decrypt in order. Queue any incoming messages until done.
        _decryptingHistory = true;
        _decryptMessageHistory().whenComplete(() {
          _decryptingHistory = false;
          _processIncomingMessageQueue();
        });
      },
      onMessageSent: _handleIncomingMessage,
      onNewMessage: _handleIncomingMessage,
      onOpenConversation: (data) {
        final convId = (data as Map<String, dynamic>)['conversationId'] as int;
        _pendingOpenConversationId = convId;
        notifyListeners();
      },
      onError: (err) {
        final String msg = err is Map<String, dynamic> && err['message'] != null
            ? err['message'] as String
            : err.toString();
        _errorMessage = msg;
        // If server rejected send (e.g. not friends, blocked), mark optimistic message as failed so Retry appears
        _markSendingMessagesFailed(msg);
        notifyListeners();
      },
      onFriendRequestsList: (data) {
        final list = data as List<dynamic>;
        _friendRequests = list
            .map((r) => FriendRequestModel.fromJson(r as Map<String, dynamic>))
            .toList();
        notifyListeners();
      },
      onNewFriendRequest: (data) {
        final request = FriendRequestModel.fromJson(data as Map<String, dynamic>);
        _friendRequests.insert(0, request);
        notifyListeners();
      },
      onFriendRequestSent: (data) {
        _friendRequestJustSent = true;
        notifyListeners();
      },
      onFriendRequestAccepted: (data) {
        final request = FriendRequestModel.fromJson(data as Map<String, dynamic>);
        _friendRequests.removeWhere((r) => r.id == request.id);
        _socketService.getConversations();
        _socketService.getFriends();
        notifyListeners();
      },
      onFriendRequestRejected: (data) {
        final request = FriendRequestModel.fromJson(data as Map<String, dynamic>);
        _friendRequests.removeWhere((r) => r.id == request.id);
        notifyListeners();
      },
      onPendingRequestsCount: (data) {
        final count = (data as Map<String, dynamic>)['count'] as int;
        _pendingRequestsCount = count;
        notifyListeners();
      },
      onFriendsList: (data) {
        final list = data as List<dynamic>;
        _friends = list
            .map((u) => UserModel.fromJson(u as Map<String, dynamic>))
            .toList();
        notifyListeners();
      },
      onUnfriended: (data) {
        final unfriendUserId = (data as Map<String, dynamic>)['userId'] as int;
        _conversations.removeWhere((c) =>
            c.userOne.id == unfriendUserId || c.userTwo.id == unfriendUserId);
        _friends.removeWhere((f) => f.id == unfriendUserId);
        _friendRequests.removeWhere((r) =>
            r.sender.id == unfriendUserId || r.receiver.id == unfriendUserId);
        _clearActiveIfRemoved();
        notifyListeners();
      },
      onBlockedList: (data) {
        final list = data as List<dynamic>;
        _blockedUsers = list
            .map((u) => UserModel.fromJson(u as Map<String, dynamic>))
            .toList();
        final blockedIds = _blockedUsers.map((u) => u.id).toSet();
        _friends.removeWhere((f) => blockedIds.contains(f.id));
        _conversations.removeWhere((c) =>
            blockedIds.contains(c.userOne.id) || blockedIds.contains(c.userTwo.id));
        _clearActiveIfRemoved();
        notifyListeners();
      },
      onYouWereBlocked: (data) {
        final blockerId = (data as Map<String, dynamic>)['userId'] as int;
        _blockedByUserIds.add(blockerId);
        _friends.removeWhere((f) => f.id == blockerId);
        _conversations.removeWhere((c) =>
            c.userOne.id == blockerId || c.userTwo.id == blockerId);
        _clearActiveIfRemoved();
        notifyListeners();
      },
      onMessageDelivered: _handleMessageDelivered,
      onPingReceived: _handlePingReceived,
      onPingSent: _handlePingReceived,
      onChatHistoryCleared: _handleChatHistoryCleared,
      onMessageDeleted: _handleMessageDeleted,
      onDisappearingTimerUpdated: _handleDisappearingTimerUpdated,
      onConversationDeleted: _handleConversationDeleted,
      onSearchUsersResult: (data) {
        final list = data as List<dynamic>;
        _searchResults = list
            .map((u) => UserModel.fromJson(u as Map<String, dynamic>))
            .toList();
        notifyListeners();
      },
      onPartnerTyping: _handlePartnerTyping,
      onPartnerRecordingVoice: _handlePartnerRecordingVoice,
      onReactionUpdated: _handleReactionUpdated,
      onLinkPreviewReady: _handleLinkPreviewReady,
      onKeyBundleUploaded: (_) {
        debugPrint('[E2E] Key bundle uploaded to server');
      },
      onOneTimePreKeysUploaded: (_) {
        debugPrint('[E2E] One-time pre-keys uploaded to server');
      },
      onPreKeyBundleResponse: _handlePreKeyBundleResponse,
      onPreKeysLow: _handlePreKeysLow,
      onDisconnect: (_) {
        _reconnect.onDisconnect(
          () => connect(token: _reconnect.tokenForReconnect!, userId: _currentUserId!),
          (msg) {
            _errorMessage = msg;
            notifyListeners();
          },
        );
      },
    );
  }

  // ---------- Open conversation & message list ----------

  void openConversation(int conversationId, {int limit = AppConstants.messagePageSize}) {
    _activeConversationId = conversationId;
    _unreadCounts[conversationId] = 0;
    _messages = [];
    _socketService.getMessages(conversationId, limit: limit);
    notifyListeners();
  }

  // Load more messages for the active conversation
  // Fetches messages with increased limit (current + additional)
  void loadMoreMessages({int additionalLimit = AppConstants.messagePageSize}) {
    if (_activeConversationId == null) return;
    final newLimit = _messages.length + additionalLimit;
    _socketService.getMessages(_activeConversationId!, limit: newLimit);
  }

  void clearActiveConversation() {
    _activeConversationId = null;
    _messages = [];
    notifyListeners();
  }

  /// Remove messages whose expiresAt has passed. Called every second by ChatDetailScreen timer.
  void removeExpiredMessages() {
    final now = DateTime.now();
    final hadExpired = _messages.any(
      (m) => m.expiresAt != null && m.expiresAt!.isBefore(now),
    );
    if (!hadExpired) return;

    _messages.removeWhere(
      (m) => m.expiresAt != null && m.expiresAt!.isBefore(now),
    );
    _lastMessages.removeWhere(
      (_, m) => m.expiresAt != null && m.expiresAt!.isBefore(now),
    );
    notifyListeners();
  }

  // ---------- Send message / voice / image ----------

  void sendMessage(String content, {int? expiresIn, int? replyToMessageId}) {
    if (_activeConversationId == null || _currentUserId == null) return;

    final conv = _conversations.firstWhere(
      (c) => c.id == _activeConversationId,
    );
    final recipientId = conv_helpers.getOtherUserId(conv, _currentUserId);

    // Use conversation disappearing timer if expiresIn not provided
    final effectiveExpiresIn = expiresIn ?? conversationDisappearingTimer;
    final effectiveReplyToId = replyToMessageId ?? _replyingToMessage?.id;

    // Generate unique tempId for optimistic message matching
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}_$_currentUserId';

    ReplyToPreview? replyPreview;
    if (_replyingToMessage != null) {
      final rt = _replyingToMessage!;
      final contentPreview = rt.messageType == MessageType.voice
          ? 'Voice message'
          : rt.messageType == MessageType.image ||
                  rt.messageType == MessageType.drawing
              ? 'Image'
              : rt.messageType == MessageType.ping
                  ? 'Ping'
                  : rt.content.length > 150
                      ? '${rt.content.substring(0, 150)}...'
                      : rt.content;
      replyPreview = ReplyToPreview(
        id: rt.id,
        content: contentPreview,
        senderUsername: rt.senderUsername,
        messageType: rt.messageType,
      );
    }

    // Create optimistic message with SENDING status
    final tempMessage = MessageModel(
      id: -DateTime.now().millisecondsSinceEpoch, // Temporary negative ID
      content: content,
      senderId: _currentUserId!,
      senderUsername: '', // Will be replaced when server confirms
      conversationId: _activeConversationId!,
      createdAt: DateTime.now(),
      deliveryStatus: MessageDeliveryStatus.sending,
      expiresAt: effectiveExpiresIn != null
          ? DateTime.now().add(Duration(seconds: effectiveExpiresIn))
          : null,
      tempId: tempId,
      replyToMessageId: effectiveReplyToId,
      replyTo: replyPreview,
    );

    _messages.add(tempMessage);
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

  void _markMessageFailed(String tempId, String errorMsg) {
    final idx = _messages.indexWhere((m) => m.tempId == tempId);
    if (idx != -1) {
      _messages[idx] = _messages[idx].copyWith(
        deliveryStatus: MessageDeliveryStatus.failed,
      );
    }
    _errorMessage = errorMsg;
    notifyListeners();
  }

  /// Mark any message currently in "sending" state as failed (e.g. after socket 'error' from server).
  void _markSendingMessagesFailed(String errorMsg) {
    final sending = _messages
        .where((m) => m.deliveryStatus == MessageDeliveryStatus.sending)
        .toList();
    if (sending.isEmpty) return;
    // Mark most recent sending message (user usually has only one)
    sending.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final last = sending.first;
    final idx = _messages.indexWhere((m) => m.tempId == last.tempId);
    if (idx != -1) {
      _messages[idx] = _messages[idx].copyWith(
        deliveryStatus: MessageDeliveryStatus.failed,
      );
    }
  }

  Future<void> _encryptAndSend({
    required int recipientId,
    required String content,
    required String tempId,
    int? effectiveExpiresIn,
    int? effectiveReplyToId,
  }) async {
    _e2eFlowLog('SEND_START', {'recipientId': recipientId, 'e2eInitialized': _e2eInitialized});
    if (!_e2eInitialized) {
      _markMessageFailed(
        tempId,
        'Encryption not ready. Please wait and try again.',
      );
      return;
    }

    try {
      // 1. Fetch client-side link preview before encrypting
      Map<String, String?>? linkPreview;
      try {
        linkPreview = await LinkPreviewService.fetchPreview(content);
      } catch (e) {
        debugPrint('[E2E] Link preview fetch failed (non-fatal): $e');
      }

      // 2. Build encrypted envelope (content + optional linkPreview)
      final envelopeJson = jsonEncode(E2eEnvelope.build(content, linkPreview));

      // 3. Ensure session exists with recipient
      await _ensureSession(recipientId);

      // 4. Encrypt
      final ciphertext =
          await _encryptionService.encrypt(recipientId, envelopeJson);
      _e2eFlowLog('SEND_ENCRYPT_DONE', {'recipientId': recipientId, 'ciphertextLength': ciphertext.length});

      // 5. Send with encrypted content
      _e2eFlowLog('SEND_EMIT', {'recipientId': recipientId});
      _socketService.sendMessage(
        recipientId,
        '[encrypted]',
        encryptedContent: ciphertext,
        expiresIn: effectiveExpiresIn,
        tempId: tempId,
        replyToMessageId: effectiveReplyToId,
      );
    } catch (e) {
      debugPrint('[E2E] Encryption failed: $e');
      _e2eFlowLog('SEND_FAIL', {'recipientId': recipientId, 'error': e.toString()});
      final String userMsg = _userFriendlySendError(e, recipientId);
      _markMessageFailed(tempId, userMsg);
    }
  }

  /// User-friendly error when encrypt/send fails (e.g. no key bundle, timeout).
  String _userFriendlySendError(Object e, int recipientId) {
    final s = e.toString();
    if (s.contains('Recipient has no key bundle') || s.contains('no key bundle')) {
      final otherName = _conversations
          .where((c) => conv_helpers.getOtherUserId(c, _currentUserId) == recipientId)
          .map((c) => conv_helpers.getOtherUserUsername(c, _currentUserId))
          .firstOrNull;
      final who = otherName ?? 'Odbiorca';
      return 'Nie można wysłać: $who nie ma jeszcze kluczy szyfrowania. Poproś, żeby otworzył aplikację.';
    }
    if (e is TimeoutException || s.contains('timed out') || s.contains('Timeout')) {
      return 'Przekroczono czas oczekiwania na klucze odbiorcy. Spróbuj ponownie.';
    }
    if (!_e2eInitialized) {
      return 'Szyfrowanie nie gotowe. Poczekaj chwilę i spróbuj ponownie.';
    }
    return 'Nie można wysłać wiadomości szyfrowanej. Odbiorca może nie mieć włączonego szyfrowania – poproś, żeby otworzył aplikację.';
  }

  void sendPing(int recipientId) {
    _socketService.sendPing(recipientId);
  }

  void addReaction(int messageId, String emoji) {
    _socketService.emitAddReaction(messageId, emoji);
  }

  void removeReaction(int messageId, String emoji) {
    _socketService.emitRemoveReaction(messageId, emoji);
  }

  void emitTyping() {
    if (_activeConversationId == null || _currentUserId == null) return;
    final conv = _conversations.where((c) => c.id == _activeConversationId).firstOrNull;
    if (conv == null) return;
    final recipientId = conv_helpers.getOtherUserId(conv, _currentUserId);
    _socketService.emitTyping(recipientId, _activeConversationId!);
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
    if (_currentUserId == null) return;

    // Use provided conversationId or active one
    final effectiveConvId = conversationId ?? _activeConversationId;
    if (effectiveConvId == null) return;

    // Generate unique tempId for optimistic message matching
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}_$_currentUserId';

    // Get disappearing timer from conversation
    final conv = _conversations.firstWhere((c) => c.id == effectiveConvId);
    final effectiveExpiresIn = conv.disappearingTimer;

    // 1. Create optimistic message
    final optimisticMessage = MessageModel(
      id: -DateTime.now().millisecondsSinceEpoch, // Temporary negative ID
      content: '',
      senderId: _currentUserId!,
      senderUsername: '', // Will be replaced when server confirms
      conversationId: effectiveConvId,
      createdAt: DateTime.now(),
      deliveryStatus: MessageDeliveryStatus.sending,
      messageType: MessageType.voice,
      mediaUrl: localAudioPath ?? '', // local path or empty on web
      mediaDuration: duration,
      tempId: tempId,
      expiresAt: effectiveExpiresIn != null
          ? DateTime.now().add(Duration(seconds: effectiveExpiresIn))
          : null,
    );

    // 2. Add to messages immediately (optimistic)
    _messages.add(optimisticMessage);
    _lastMessages[effectiveConvId] = optimisticMessage;
    notifyListeners();

    // 3. Upload to backend in background
    try {
      if (_reconnect.tokenForReconnect == null) {
        throw Exception('No authentication token available');
      }

      final api = ApiService(baseUrl: AppConfig.baseUrl);
      final result = await api.uploadVoiceMessage(
        token: _reconnect.tokenForReconnect!,
        duration: duration,
        expiresIn: effectiveExpiresIn,
        audioPath: localAudioPath,
        audioBytes: localAudioBytes,
      );

      // 4. Send via WebSocket with Cloudinary URL
      _socketService.sendMessage(
        recipientId,
        '', // empty content for voice
        messageType: 'VOICE',
        mediaUrl: result.mediaUrl,
        mediaDuration: result.duration,
        expiresIn: effectiveExpiresIn,
        tempId: tempId,
      );

      // 5. Update local message with Cloudinary URL
      final index = _messages.indexWhere((m) => m.tempId == tempId);
      if (index != -1) {
        _messages[index] = _messages[index].copyWith(
          mediaUrl: result.mediaUrl,
          mediaDuration: result.duration,
          deliveryStatus: MessageDeliveryStatus.sent,
        );
        notifyListeners();
      }

      // 6. Delete temp file after successful upload (native only; web uses blob)
      if (!kIsWeb && localAudioPath != null) {
        final file = File(localAudioPath);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (e) {
      // 7. Mark as failed, keep local file for retry
      final index = _messages.indexWhere((m) => m.tempId == tempId);
      if (index != -1) {
        _messages[index] = _messages[index].copyWith(
          deliveryStatus: MessageDeliveryStatus.failed,
        );
        notifyListeners();
      }

      _errorMessage = 'Failed to send voice message';
      debugPrint('Voice upload error: $e');
    }
  }

  Future<void> retryVoiceMessage(String tempId) async {
    final message = _messages.firstWhere(
      (m) => m.tempId == tempId,
      orElse: () => throw Exception('Message not found'),
    );

    if (message.messageType != MessageType.voice) {
      throw Exception('Not a voice message');
    }

    if (message.deliveryStatus != MessageDeliveryStatus.failed) {
      return; // Already sent
    }

    final conversation = _conversations.firstWhere(
      (c) => c.id == message.conversationId,
    );
    final recipientId = conv_helpers.getOtherUserId(conversation, _currentUserId);

    // Update status to SENDING
    final index = _messages.indexWhere((m) => m.tempId == tempId);
    if (index != -1) {
      _messages[index] = _messages[index].copyWith(
        deliveryStatus: MessageDeliveryStatus.sending,
      );
      notifyListeners();
    }

    // Re-attempt upload (native only; web retry not supported - no cached bytes)
    final localPath = message.mediaUrl;
    if (localPath == null || localPath.isEmpty) {
      _errorMessage = 'Retry not available for this message';
      notifyListeners();
      return;
    }
    await sendVoiceMessage(
      recipientId: recipientId,
      localAudioPath: localPath,
      duration: message.mediaDuration ?? 0,
      conversationId: message.conversationId,
    );
  }

  /// Retry sending a failed message (text or voice). Voice uses cached file; text re-sends content.
  Future<void> retryFailedMessage(String tempId) async {
    final index = _messages.indexWhere((m) => m.tempId == tempId);
    if (index == -1) return;
    final message = _messages[index];
    if (message.deliveryStatus != MessageDeliveryStatus.failed) return;

    if (message.messageType == MessageType.voice) {
      await retryVoiceMessage(tempId);
      return;
    }
    if (message.messageType == MessageType.text) {
      final content = message.content;
      final conversationId = message.conversationId;
      _messages.removeAt(index);
      final stillInConv = _messages.where((m) => m.conversationId == conversationId).toList();
      if (stillInConv.isNotEmpty) {
        stillInConv.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        _lastMessages[conversationId] = stillInConv.last;
      } else {
        _lastMessages.remove(conversationId);
      }
      notifyListeners();
      if (_activeConversationId == conversationId && content.isNotEmpty) {
        sendMessage(content);
      }
    }
  }

  Future<void> sendImageMessage(
    String token,
    XFile imageFile,
    int recipientId,
  ) async {
    final api = ApiService(baseUrl: AppConfig.baseUrl);

    // Use conversation disappearing timer
    final effectiveExpiresIn = conversationDisappearingTimer;

    try {
      final response = await api.uploadImageMessage(
        token,
        imageFile,
        recipientId,
        effectiveExpiresIn,
      );

      // Parse response and add to messages
      final message = MessageModel.fromJson(response);

      if (_activeConversationId == message.conversationId) {
        _messages.add(message);
      }

      _lastMessages[message.conversationId] = message;
      notifyListeners();
    } catch (e) {
      debugPrint('[ChatProvider] Image upload failed: $e');
      _errorMessage = 'Image upload failed: ${e.toString()}';
      notifyListeners();
      rethrow;
    }
  }

  void clearChatHistory(int conversationId) {
    _socketService.emitClearChatHistory(conversationId);
  }

  void deleteMessage(int messageId, {required bool forEveryone}) {
    _socketService.emitDeleteMessage(messageId, forEveryone: forEveryone);
  }

  // ---------- Message delivery & history events ----------

  void _handleMessageDelivered(dynamic data) {
    final map = data as Map<String, dynamic>;
    final messageId = map['messageId'] as int;
    final status = map['deliveryStatus'] as String;
    final conversationId = map['conversationId'] as int?;
    final newStatus = MessageModel.parseDeliveryStatus(status);

    // Update message in _messages list (current chat)
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index != -1) {
      _messages[index] = _messages[index].copyWith(
        deliveryStatus: newStatus,
      );
    }

    // Update _lastMessages so list and re-opened chat show correct status
    if (conversationId != null &&
        _lastMessages[conversationId]?.id == messageId) {
      _lastMessages[conversationId] =
          _lastMessages[conversationId]!.copyWith(deliveryStatus: newStatus);
    }

    if (index != -1 || conversationId != null) {
      notifyListeners();
    }
  }

  void _handlePingReceived(dynamic data) {
    final message = MessageModel.fromJson(data as Map<String, dynamic>);

    // Add to messages if active conversation matches
    if (_activeConversationId == message.conversationId) {
      _messages.add(message);
    }

    // Update last message
    _lastMessages[message.conversationId] = message;

    // Update unread count (same logic as normal messages)
    if (message.senderId != _currentUserId) {
      if (message.conversationId != _activeConversationId) {
        _unreadCounts[message.conversationId] =
            (_unreadCounts[message.conversationId] ?? 0) + 1;
      }
      _socketService.emitMessageDelivered(message.id);
      if (message.conversationId == _activeConversationId) {
        markConversationRead(message.conversationId);
      }
    }

    // Set flag for showing ping effect
    _showPingEffect = true;

    notifyListeners();
  }

  void _handleChatHistoryCleared(dynamic data) {
    final m = data as Map<String, dynamic>;
    final conversationId = m['conversationId'] as int;

    // Clear messages from memory
    _messages.removeWhere((m) => m.conversationId == conversationId);
    _lastMessages.remove(conversationId);

    notifyListeners();
  }

  void _handleMessageDeleted(dynamic data) {
    final m = data as Map<String, dynamic>;
    final messageId = m['messageId'] as int;
    final conversationId = m['conversationId'] as int;
    final forEveryone = m['forEveryone'] as bool? ?? false;

    _deletedMessageIds.add(messageId);
    _messages.removeWhere((msg) => msg.id == messageId);

    // Update last message preview for conversation list
    if (_lastMessages[conversationId]?.id == messageId) {
      final remaining = _messages.where((msg) => msg.conversationId == conversationId).toList();
      if (remaining.isNotEmpty) {
        remaining.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        _lastMessages[conversationId] = remaining.last;
      } else {
        _lastMessages.remove(conversationId);
      }
    }

    // If delete for everyone and we weren't viewing this chat, refresh conv list to update lastMessage
    if (forEveryone && _activeConversationId != conversationId) {
      _socketService.getConversations();
    }

    notifyListeners();
  }

  // ---------- Conversation events ----------

  void _handleDisappearingTimerUpdated(dynamic data) {
    final m = data as Map<String, dynamic>;
    final conversationId = m['conversationId'] as int;
    final seconds = m['seconds'] as int?;

    // Find and update conversation in list
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index != -1) {
      final oldConv = _conversations[index];
      // Create new instance with updated timer (ConversationModel is immutable)
      _conversations[index] = ConversationModel(
        id: oldConv.id,
        userOne: oldConv.userOne,
        userTwo: oldConv.userTwo,
        createdAt: oldConv.createdAt,
        disappearingTimer: seconds,
      );
    }

    notifyListeners();
  }

  void _handleConversationDeleted(dynamic data) {
    final convId = data['conversationId'] as int;

    // Remove from conversations list
    _conversations.removeWhere((c) => c.id == convId);

    // Remove all messages for this conversation
    _messages.removeWhere((m) => m.conversationId == convId);

    // Remove from last messages
    _lastMessages.remove(convId);

    // Remove from unread counts
    _unreadCounts.remove(convId);

    // Clear active conversation if it was deleted
    if (_activeConversationId == convId) {
      _activeConversationId = null;
    }

    notifyListeners();
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

  // ---------- Conversation & friend actions (socket) ----------

  void searchUsers(String handle) {
    _searchResults = null;
    notifyListeners();
    _socketService.searchUsers(handle);
  }

  void clearSearchResults() {
    _searchResults = null;
    notifyListeners();
  }

  void startConversation(int recipientId) {
    _socketService.startConversation(recipientId);
  }

  void deleteConversationOnly(int conversationId) {
    _socketService.emitDeleteConversationOnly(conversationId);
  }

  void sendFriendRequest(int recipientId) {
    _socketService.sendFriendRequest(recipientId);
  }

  void acceptFriendRequest(int requestId) {
    _socketService.acceptFriendRequest(requestId);
  }

  void rejectFriendRequest(int requestId) {
    _socketService.rejectFriendRequest(requestId);
  }

  void fetchFriendRequests() {
    _socketService.getFriendRequests();
  }

  void fetchFriends() {
    _socketService.getFriends();
  }

  void unfriend(int userId) {
    _socketService.unfriend(userId);
  }

  void blockUser(int userId) {
    _socketService.emitBlockUser(userId);
    // Server will emit blockedList and unfriended; we may remove from friends/conversations locally after blockedList
  }

  void unblockUser(int userId) {
    _socketService.emitUnblockUser(userId);
  }

  void loadBlockedList() {
    _socketService.getBlockedList();
  }

  bool isFriend(int userId) {
    return _friends.any((f) => f.id == userId);
  }

  // ---------- E2E Encryption ----------

  Future<void> _initializeE2E() async {
    if (_currentUserId == null) return;
    _e2eFlowLog('E2E_INIT_START', {});
    try {
      await _encryptionService.initialize(_currentUserId!);
      _e2eInitialized = true;
      debugPrint('[E2E] Encryption service initialized');
      _e2eFlowLog('E2E_INIT_DONE', {'needsKeyUpload': _encryptionService.needsKeyUpload});

      if (_encryptionService.needsKeyUpload) {
        final keys = _encryptionService.getKeysForUpload();
        if (keys != null) {
          _socketService.uploadKeyBundle(
              keys['keyBundle'] as Map<String, dynamic>);
          _socketService.uploadOneTimePreKeys(
              (keys['oneTimePreKeys'] as List)
                  .cast<Map<String, dynamic>>());
          debugPrint('[E2E] Uploaded key bundle + one-time pre-keys');
          _e2eFlowLog('E2E_KEYS_UPLOADED', {});
        }
      } else {
        // Always re-upload key bundle so server has our keys (e.g. after DB restart).
        final keyBundle = await _encryptionService.getKeyBundleForReupload();
        if (keyBundle != null) {
          _socketService.uploadKeyBundle(keyBundle);
          debugPrint('[E2E] Re-uploaded key bundle on connect');
          _e2eFlowLog('E2E_KEYS_REUPLOADED', {});
        } else {
          debugPrint('[E2E] Re-upload skipped: could not build key bundle from storage');
        }
      }
    } catch (e) {
      debugPrint('[E2E] Initialization failed: $e');
      _e2eInitialized = false;
      _e2eFlowLog('E2E_INIT_FAIL', {'error': e.toString()});
    }
  }

  Future<void> _ensureSession(int recipientId) async {
    if (!_e2eInitialized || _currentUserId == null) {
      throw StateError('E2E not initialized or user not authenticated');
    }
    final hasSession = await _encryptionService.hasSession(recipientId);
    _e2eFlowLog('SESSION_ENSURE', {'recipientId': recipientId, 'hasSession': hasSession});
    if (hasSession) return;

    // Check if we already have a pending fetch for this user
    if (_pendingPreKeyFetches.containsKey(recipientId)) {
      await _pendingPreKeyFetches[recipientId]!.future;
      return;
    }

    final completer = Completer<Map<String, dynamic>>();
    _pendingPreKeyFetches[recipientId] = completer;

    _e2eFlowLog('SESSION_FETCH_EMIT', {'recipientId': recipientId});
    _socketService.fetchPreKeyBundle(recipientId);

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

  void _handlePreKeyBundleResponse(dynamic data) {
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

  void _handlePreKeysLow(dynamic data) {
    if (_generatingMoreKeys) return;
    _generatingMoreKeys = true;
    debugPrint('[E2E] Server reports pre-keys low, generating more...');
    _encryptionService.generateMorePreKeys().then((keys) {
      _socketService.uploadOneTimePreKeys(keys);
      debugPrint('[E2E] Uploaded ${keys.length} new one-time pre-keys');
    }).catchError((e) {
      debugPrint('[E2E] Failed to generate more pre-keys: $e');
    }).whenComplete(() => _generatingMoreKeys = false);
  }

  Future<void> _decryptMessageHistory() async {
    final toDecrypt = _messages.where((m) => m.needsDecryption(_currentUserId)).length;
    if (toDecrypt > 0) _e2eFlowLog('HISTORY_DECRYPT_START', {'count': toDecrypt});
    // Double Ratchet requires decrypting in chronological order (oldest first) to avoid DuplicateMessageException.
    final sorted = List<MessageModel>.from(_messages)
      ..sort((a, b) {
        final byTime = a.createdAt.compareTo(b.createdAt);
        if (byTime != 0) return byTime;
        return a.id.compareTo(b.id);
      });
    bool changed = false;
    for (var i = 0; i < sorted.length; i++) {
      final msg = sorted[i];
      if (msg.needsDecryption(_currentUserId)) {
        final decrypted = await _decryptMessageAsync(msg);
        final idx = _messages.indexWhere((m) => m.id == msg.id);
        if (idx != -1) {
          _messages[idx] = decrypted;
          changed = true;
        }
      } else if (msg.senderId == _currentUserId && msg.content == '[encrypted]') {
        final stored = await _encryptionService.getDecryptedContent(msg.id);
        final storedContent = stored?['content'] as String? ?? '';
        if (storedContent.isNotEmpty) {
          final restored = msg.copyWith(content: storedContent);
          final idx = _messages.indexWhere((m) => m.id == msg.id);
          if (idx != -1) {
            _messages[idx] = restored;
            changed = true;
          }
        }
      }
    }
    if (changed) _e2eFlowLog('HISTORY_DECRYPT_DONE', {'changed': true});
    if (changed) notifyListeners();
  }

  Future<MessageModel> _decryptMessageAsync(MessageModel msg) async {
    // Own messages: server stored "[encrypted]" as content but we already
    // showed plaintext optimistically, so skip decryption for our own messages.
    if (msg.senderId == _currentUserId) return msg;

    if (!_e2eInitialized) {
      return msg.copyWith(content: '[Encryption not initialized]');
    }

    _e2eFlowLog('DECRYPT_START', {'msgId': msg.id, 'senderId': msg.senderId});
    try {
      final plaintext = await _encryptionService.decrypt(
        msg.senderId,
        msg.encryptedContent!,
      );
      try {
        final parsed = E2eEnvelope.parse(plaintext);
        _e2eFlowLog('DECRYPT_OK', {'msgId': msg.id, 'contentLength': parsed.content.length});
        final decryptedMsg = msg.copyWith(
          content: parsed.content,
          linkPreviewUrl: parsed.linkPreviewUrl,
          linkPreviewTitle: parsed.linkPreviewTitle,
          linkPreviewImageUrl: parsed.linkPreviewImageUrl,
        );
        _decryptedContentCache[msg.id] = decryptedMsg;
        await _persistDecryptedContent(decryptedMsg);
        return decryptedMsg;
      } catch (parseErr) {
        debugPrint('[E2E] Envelope parse failed for msg ${msg.id}, using raw plaintext: $parseErr');
        final fallback = msg.copyWith(content: plaintext);
        _decryptedContentCache[msg.id] = fallback;
        if (plaintext.isNotEmpty) await _persistDecryptedContent(fallback);
        return fallback;
      }
    } catch (e) {
      // DuplicateMessageException: session was already advanced. Use memory cache or persisted cache (survives logout).
      final cached = _decryptedContentCache[msg.id];
      if (cached != null) return cached;
      final persisted = await _encryptionService.getDecryptedContent(msg.id);
      final persistedContent = persisted?['content'] as String? ?? '';
      if (persisted != null && persistedContent.isNotEmpty) {
        final restored = msg.copyWith(
          content: persistedContent,
          linkPreviewUrl: persisted['linkPreviewUrl'] as String?,
          linkPreviewTitle: persisted['linkPreviewTitle'] as String?,
          linkPreviewImageUrl: persisted['linkPreviewImageUrl'] as String?,
        );
        _decryptedContentCache[msg.id] = restored;
        return restored;
      }
      debugPrint('[E2E] Decrypt failed for msg ${msg.id}: $e');
      _e2eFlowLog('DECRYPT_FAIL', {'msgId': msg.id, 'error': e.toString()});
      return msg.copyWith(content: '[Decryption failed]');
    }
  }

  // ---------- Connection lifecycle ----------

  void disconnect() {
    _reconnect.intentionalDisconnect = true;
    _reconnect.tokenForReconnect = null;
    _reconnect.cancel();
    _reconnect.resetAttempts();
    _socketService.disconnect();
    _conversations = [];
    _messages = [];
    _activeConversationId = null;
    _currentUserId = null;
    _lastMessages.clear();
    _deletedMessageIds.clear();
    _unreadCounts.clear();
    _typingStatus.clear();
    for (final t in _typingTimers.values) { t.cancel(); }
    _typingTimers.clear();
    _partnerRecordingVoice.clear();
    _replyingToMessage = null;
    _pendingOpenConversationId = null;
    _friendRequests = [];
    _pendingRequestsCount = 0;
    _friends = [];
    _friendRequestJustSent = false;
    _pushInitialized = false; // Allow re-registration on next login
    // Clear E2E state (keys persist in secure storage for next login)
    _e2eInitialized = false;
    _pendingPreKeyFetches.clear();
    _decryptedContentCache.clear();
    _incomingMessageQueue.clear();
    _decryptingHistory = false;
    notifyListeners();
  }

  /// Clear all E2E encryption keys. Call on account deletion only.
  Future<void> clearEncryptionKeys() async {
    await _encryptionService.clearAllKeys();
    _e2eInitialized = false;
    _pendingPreKeyFetches.clear();
  }

}
