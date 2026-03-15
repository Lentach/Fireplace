import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';
import '../utils/file_utils_stub.dart' if (dart.library.io) '../utils/file_utils_io.dart' as file_utils;
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
  late final ApiService _api = ApiService(baseUrl: AppConfig.baseUrl);
  late final PushService _pushService = PushService(_api);
  bool _pushInitialized = false;

  // ---------- E2E Encryption ----------
  final EncryptionService _encryptionService = EncryptionService();
  bool _e2eInitialized = false;
  final Map<int, Completer<Map<String, dynamic>>> _pendingPreKeyFetches = {};
  bool _generatingMoreKeys = false;
  /// Single delayed retry for a failed text message (e.g. recipient had no key bundle, then came online).
  Timer? _delayedRetryTimer;
  String? _delayedRetryTempId;
  /// Cache of decrypted messages by id. Used when history decrypt hits DuplicateMessageException (session already advanced by live messages).
  final Map<int, MessageModel> _decryptedContentCache = {};
  bool _decryptingHistory = false;
  /// Incremented on each new messageHistory to cancel stale in-flight decrypt loops.
  /// Each loop captures its generation at start and exits when the counter changes.
  int _decryptHistoryGeneration = 0;
  /// User IDs whose sessions should be force-rebuilt on the next _ensureSession call.
  /// Handlers add to this set (synchronously, no async); _ensureSession drains it atomically.
  final Set<int> _forceSessionRebuild = {};
  final List<Map<String, dynamic>> _incomingMessageQueue = [];
  /// Plaintext content + link preview + type/media keyed by tempId — survives
  /// _messages list overwrites (e.g. when messageHistory arrives before messageSent).
  /// Value: {'content': String, 'messageType'?: String, 'mediaUrl'?: String,
  ///         'mediaDuration'?: int, 'linkPreviewUrl'?: String, ...}
  final Map<String, Map<String, dynamic>> _pendingSendContent = {};

  // Monotonic counter for temporary negative message IDs — prevents collision
  // if two messages are sent within the same millisecond.
  static int _tempIdSeq = 0;

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
  /// Set when we (sender) receive friendRequestAccepted — acceptor's username for snackbar.
  String? _pendingFriendAcceptedByName;
  /// True when our active conversation was removed from list (e.g. other user deleted).
  bool _activeConversationDeletedByOther = false;
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
  String? get pendingFriendAcceptedByName => _pendingFriendAcceptedByName;
  bool get activeConversationDeletedByOther => _activeConversationDeletedByOther;
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
    final dataMap = data as Map<String, dynamic>;
    final msg = MessageModel.fromJson(dataMap);
    // Queue incoming encrypted messages for active conversation while we're decrypting history (so history decrypt runs first and session order is preserved).
    if (_decryptingHistory &&
        msg.conversationId == _activeConversationId &&
        msg.needsDecryption(_currentUserId)) {
      _incomingMessageQueue.add(dataMap);
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
    // I1: validate linkPreviewImageUrl before persist (SSRF defense in depth)
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
      if (decrypted.messageType != MessageType.text) 'messageType': decrypted.messageType.name.toUpperCase(),
      if (decrypted.mediaUrl != null) 'mediaUrl': decrypted.mediaUrl!,
      if (decrypted.mediaDuration != null) 'mediaDuration': decrypted.mediaDuration!,
      if (decrypted.linkPreviewUrl != null) 'linkPreviewUrl': decrypted.linkPreviewUrl!,
      if (decrypted.linkPreviewTitle != null) 'linkPreviewTitle': decrypted.linkPreviewTitle!,
      if (safeImageUrl != null) 'linkPreviewImageUrl': safeImageUrl,
    };
    try {
      await _encryptionService.saveDecryptedContent(decrypted.id, data);
    } catch (_) {}
  }

  void _addMessageToState(MessageModel msg) {
    // If this is our own message (messageSent), replace temp optimistic message
    // and keep plaintext for display (server stores "[encrypted]" as content).
    if (msg.senderId == _currentUserId && msg.tempId != null) {
      // Retrieve plaintext + link preview: prefer _pendingSendContent (survives list
      // overwrites when messageHistory arrives before messageSent), fall back to temp message.
      final savedData = _pendingSendContent.remove(msg.tempId);
      final savedContent = savedData?['content'];
      final tempIndex = _messages.indexWhere((m) => m.tempId == msg.tempId);
      final tempContent = tempIndex != -1 ? _messages[tempIndex].content : null;
      if (tempIndex != -1) _messages.removeAt(tempIndex);
      final plaintextContent = savedContent ?? tempContent ?? '';
      if (msg.content == '[encrypted]') {
        final restoredType = _parseMessageTypeString(savedData?['messageType'] as String?);
        msg = msg.copyWith(
          content: plaintextContent.isNotEmpty ? plaintextContent : null,
          messageType: restoredType,
          mediaUrl: savedData?['mediaUrl'] as String?,
          mediaDuration: savedData?['mediaDuration'] as int?,
          linkPreviewUrl: savedData?['linkPreviewUrl'] as String?,
          linkPreviewTitle: savedData?['linkPreviewTitle'] as String?,
          linkPreviewImageUrl: savedData?['linkPreviewImageUrl'] as String?,
        );
        final persistData = <String, dynamic>{
          'content': plaintextContent,
          if (savedData?['messageType'] != null) 'messageType': savedData!['messageType'],
          if (savedData?['mediaUrl'] != null) 'mediaUrl': savedData!['mediaUrl'],
          if (savedData?['mediaDuration'] != null) 'mediaDuration': savedData!['mediaDuration'],
          if (savedData?['linkPreviewUrl'] != null) 'linkPreviewUrl': savedData!['linkPreviewUrl'],
          if (savedData?['linkPreviewTitle'] != null) 'linkPreviewTitle': savedData!['linkPreviewTitle'],
          if (savedData?['linkPreviewImageUrl'] != null) 'linkPreviewImageUrl': savedData!['linkPreviewImageUrl'],
        };
        _encryptionService.saveDecryptedContent(msg.id, persistData).catchError((_) {});
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

  /// Returns acceptor's username and clears; null if none. Call when showing snackbar.
  String? consumePendingFriendAccepted() {
    final name = _pendingFriendAcceptedByName;
    _pendingFriendAcceptedByName = null;
    return name;
  }

  /// Call when user navigates back from a chat that was deleted by the other user.
  void clearActiveIfDeletedByOther() {
    if (_activeConversationDeletedByOther) {
      _activeConversationDeletedByOther = false;
      _activeConversationId = null;
      _messages = [];
      notifyListeners();
    }
  }

  String getOtherUserUsername(ConversationModel conv) =>
      conv_helpers.getOtherUserUsername(conv, _currentUserId);

  int getOtherUserId(ConversationModel conv) =>
      conv_helpers.getOtherUserId(conv, _currentUserId);

  UserModel? getOtherUser(ConversationModel conv) =>
      conv_helpers.getOtherUser(conv, _currentUserId);

  void connect({required String token, required int userId}) {
    _reconnect.cancel();
    _reconnect.intentionalDisconnect = false;
    _reconnect.tokenForReconnect = token;
    _decryptHistoryGeneration++; // cancel any in-flight history decrypt from previous connect

    final isReconnect = (_currentUserId == userId);

    if (!isReconnect) {
      // Fresh connect or switch user: clear ALL state to prevent data leakage
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
      _pendingFriendAcceptedByName = null;
      _activeConversationDeletedByOther = false;
      _searchResults = null;
      _errorMessage = null;
      _e2eInitialized = false;
      _pendingPreKeyFetches.clear();
      _forceSessionRebuild.clear();
      _pendingSendContent.clear();
      _cancelDelayedRetryIfAny();
    } else {
      // Reconnect (same user): keep list state and active chat to avoid flicker and empty chat.
      // Do NOT clear _messages — messageHistory will replace them when it arrives.
      // Clearing here causes a ~500ms blank-chat flash on screen wake.
      _typingStatus.clear();
      for (final t in _typingTimers.values) { t.cancel(); }
      _typingTimers.clear();
      _partnerRecordingVoice.clear();
      _replyingToMessage = null;
      _pendingOpenConversationId = null;
      _pendingFriendAcceptedByName = null;
      _activeConversationDeletedByOther = false;
      _searchResults = null;
      _errorMessage = null;
      _cancelDelayedRetryIfAny();
    }

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
        if (_activeConversationId != null) {
          _socketService.getMessages(_activeConversationId!, limit: AppConstants.messagePageSize);
        }
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
        final newConvs = list
            .map((c) =>
                ConversationModel.fromJson(c as Map<String, dynamic>))
            .toList();
        // If our active conv is no longer in list (e.g. other user deleted), mark it — don't auto-close
        if (_activeConversationId != null &&
            !newConvs.any((c) => c.id == _activeConversationId)) {
          _activeConversationDeletedByOther = true;
        }
        _conversations = newConvs;
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
            _activeConversationId != null &&
            responseConversationId != _activeConversationId) {
          return;
        }
        _messages = list
            .map((m) => MessageModel.fromJson(m as Map<String, dynamic>))
            .toList();

        // Cancel any in-flight decrypt so we process the latest messages
        _decryptHistoryGeneration++;

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
        final myGeneration = _decryptHistoryGeneration;
        _decryptingHistory = true;
        _decryptMessageHistory(myGeneration).whenComplete(() {
          if (_decryptHistoryGeneration == myGeneration) {
            _decryptingHistory = false;
          }
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
        // If we are the sender (we sent the request), show snackbar "X accepted your invitation"
        if (_currentUserId == request.sender.id) {
          _pendingFriendAcceptedByName = request.receiver.username;
        }
        // Do NOT call getConversations/getFriends here — backend already emits
        // conversationsList and friendsList; calling get* causes race and overwrites
        // with stale data (A loses new conversation and contact flickers/disappears).
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
      onSessionRebuildNeeded: (data) {
        final fromUserId = (data as Map<String, dynamic>)['fromUserId'] as int;
        // Mark session for rebuild — actual delete happens atomically in _ensureSession
        // before the next send, avoiding the race where a hot-path deleteSession
        // wipes a session that encrypt() is about to use.
        _forceSessionRebuild.add(fromUserId);
        _e2eFlowLog('SESSION_REBUILD_RECEIVED', {'fromUserId': fromUserId});
      },
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

  /// Sets active conversation without fetching messages. Use when ChatDetailScreen
  /// will call openConversation (avoids double getMessages on desktop).
  void setActiveConversation(int conversationId) {
    _activeConversationId = conversationId;
    _activeConversationDeletedByOther = false;
    _unreadCounts[conversationId] = 0;
    notifyListeners();
  }

  void openConversation(int conversationId, {int limit = AppConstants.messagePageSize}) {
    _activeConversationId = conversationId;
    _activeConversationDeletedByOther = false;
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
          : rt.messageType == MessageType.image
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
      id: -(++ChatProvider._tempIdSeq), // Monotonic temporary negative ID
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
    // Persist plaintext separately so it survives if _messages is overwritten
    // by a messageHistory response before messageSent arrives.
    // Use explicit Map type to avoid DDC/JS IdentityMap subtype errors when assigning.
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
    String messageType = 'TEXT',
    String? mediaUrl,
    int? mediaDuration,
  }) async {
    _e2eFlowLog('SEND_START', {'recipientId': recipientId, 'e2eInitialized': _e2eInitialized, 'messageType': messageType});
    if (!_e2eInitialized) {
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
          if (kIsWeb && _reconnect.tokenForReconnect != null) {
            linkPreview = await _api.fetchLinkPreview(
              _reconnect.tokenForReconnect!,
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
        if (linkPreview != null) {
          if (linkPreview['url'] != null) pending['linkPreviewUrl'] = linkPreview['url'];
          if (linkPreview['title'] != null) pending['linkPreviewTitle'] = linkPreview['title'];
          if (linkPreview['imageUrl'] != null) pending['linkPreviewImageUrl'] = linkPreview['imageUrl'];
        }
      }

      // 3. Build encrypted envelope (content + type + media + optional linkPreview)
      final envelopeJson = jsonEncode(E2eEnvelope.build(
        content,
        messageType: messageType,
        mediaUrl: mediaUrl,
        mediaDuration: mediaDuration,
        linkPreview: linkPreview,
      ));

      // 4. Ensure session exists with recipient
      await _ensureSession(recipientId);

      // 5. Encrypt
      final ciphertext =
          await _encryptionService.encrypt(recipientId, envelopeJson);
      _e2eFlowLog('SEND_ENCRYPT_DONE', {'recipientId': recipientId, 'ciphertextLength': ciphertext.length});

      // 6. Send with encrypted content — server is blind to type/media
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
      _pendingPreKeyFetches.remove(recipientId);
      debugPrint('[E2E] Encryption failed: $e');
      _e2eFlowLog('SEND_FAIL', {'recipientId': recipientId, 'error': e.toString()});
      final String userMsg = _userFriendlySendError(e, recipientId);
      _markMessageFailed(tempId, userMsg);
      if (_isKeyBundleOrTimeoutError(e)) {
        _scheduleDelayedRetry(tempId);
      }
    }
  }

  bool _isKeyBundleOrTimeoutError(Object e) {
    final s = e.toString();
    return s.contains('key bundle') || s.contains('no key bundle') ||
        s.contains('timed out') || s.contains('Timeout') || e is TimeoutException;
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
    if (message.deliveryStatus != MessageDeliveryStatus.failed) return;
    // Only auto-retry text and ping (media types need re-upload check)
    if (message.messageType != MessageType.text && message.messageType != MessageType.ping) return;
    if (message.messageType == MessageType.text && message.content.isEmpty) return;
    final convList = _conversations.where((c) => c.id == message.conversationId).toList();
    if (convList.isEmpty) return;
    final conv = convList.first;
    final recipientId = conv_helpers.getOtherUserId(conv, _currentUserId);
    int? effectiveExpiresIn;
    if (message.expiresAt != null) {
      final secs = message.expiresAt!.difference(DateTime.now()).inSeconds;
      effectiveExpiresIn = secs.clamp(1, 86400 * 30);
    } else {
      effectiveExpiresIn = conv.disappearingTimer;
    }
    _messages[idx] = message.copyWith(deliveryStatus: MessageDeliveryStatus.sending);
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
      case 'TEXT': return MessageType.text;
      case 'PING': return MessageType.ping;
      case 'VOICE': return MessageType.voice;
      case 'IMAGE': return MessageType.image;
      default: return null;
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
      final who = otherName ?? 'Recipient';
      return 'Cannot send: $who does not have encryption keys yet. Ask them to open the app.';
    }
    if (e is TimeoutException || s.contains('timed out') || s.contains('Timeout')) {
      return 'Timed out waiting for recipient keys. Try again.';
    }
    if (!_e2eInitialized) {
      return 'Encryption not ready. Wait a moment and try again.';
    }
    return 'Cannot send encrypted message. Recipient may not have encryption enabled – ask them to open the app.';
  }

  void sendPing(int recipientId) {
    if (_activeConversationId == null || _currentUserId == null) return;

    final effectiveExpiresIn = conversationDisappearingTimer;
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}_$_currentUserId';

    final tempMessage = MessageModel(
      id: -(++ChatProvider._tempIdSeq),
      content: '',
      senderId: _currentUserId!,
      senderUsername: '',
      conversationId: _activeConversationId!,
      createdAt: DateTime.now(),
      deliveryStatus: MessageDeliveryStatus.sending,
      messageType: MessageType.ping,
      expiresAt: effectiveExpiresIn != null
          ? DateTime.now().add(Duration(seconds: effectiveExpiresIn))
          : null,
      tempId: tempId,
    );

    _messages.add(tempMessage);
    _pendingSendContent[tempId] = <String, dynamic>{'content': '', 'messageType': 'PING'};
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
      id: -(++ChatProvider._tempIdSeq),
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
      expiresAt: effectiveExpiresIn != null
          ? DateTime.now().add(Duration(seconds: effectiveExpiresIn))
          : null,
    );

    // 2. Add to messages immediately (optimistic)
    _messages.add(optimisticMessage);
    _pendingSendContent[tempId] = <String, dynamic>{'content': '', 'messageType': 'VOICE'};
    _lastMessages[effectiveConvId] = optimisticMessage;
    notifyListeners();

    // 3. Upload to Cloudinary (no message created in DB)
    try {
      if (_reconnect.tokenForReconnect == null) {
        throw Exception('No authentication token available');
      }

      final responseData = await _api.uploadMedia(
        token: _reconnect.tokenForReconnect!,
        type: 'voice',
        duration: duration,
        expiresIn: effectiveExpiresIn,
        audioPath: localAudioPath,
        audioBytes: localAudioBytes,
      );

      final cloudinaryUrl = responseData['mediaUrl'] as String;
      final serverDuration = (responseData['mediaDuration'] as num?)?.toInt() ?? duration;

      // 4. Update optimistic message with Cloudinary URL
      final index = _messages.indexWhere((m) => m.tempId == tempId);
      if (index != -1) {
        _messages[index] = _messages[index].copyWith(
          mediaUrl: cloudinaryUrl,
          mediaDuration: serverDuration,
        );
        notifyListeners();
      }

      // 5. Delete temp file after successful upload (native only; web uses blob)
      if (!kIsWeb && localAudioPath != null) {
        await file_utils.deleteFileIfExists(localAudioPath);
      }

      // 6. Encrypt and send via WebSocket (URL hidden in envelope)
      _encryptAndSend(
        recipientId: recipientId,
        content: '',
        tempId: tempId,
        effectiveExpiresIn: effectiveExpiresIn,
        messageType: 'VOICE',
        mediaUrl: cloudinaryUrl,
        mediaDuration: serverDuration,
      );
    } catch (e) {
      debugPrint('[ChatProvider] Voice upload failed: $e');
      _markMessageFailed(tempId, 'Failed to send voice message');
    }
  }

  /// Retry sending a failed message (any type).
  Future<void> retryFailedMessage(String tempId) async {
    _cancelDelayedRetry(tempId);
    final index = _messages.indexWhere((m) => m.tempId == tempId);
    if (index == -1) return;
    final message = _messages[index];
    if (message.deliveryStatus != MessageDeliveryStatus.failed) return;

    final conv = _conversations.where((c) => c.id == message.conversationId).firstOrNull;
    if (conv == null) return;
    final recipientId = conv_helpers.getOtherUserId(conv, _currentUserId);

    if (message.messageType == MessageType.ping) {
      _messages[index] = _messages[index].copyWith(
        deliveryStatus: MessageDeliveryStatus.sending,
      );
      _pendingSendContent[tempId] = <String, dynamic>{'content': '', 'messageType': 'PING'};
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
      // If Cloudinary URL already obtained, skip re-upload
      if (message.mediaUrl != null && message.mediaUrl!.contains('cloudinary')) {
        _messages[index] = _messages[index].copyWith(
          deliveryStatus: MessageDeliveryStatus.sending,
        );
        _pendingSendContent[tempId] = <String, dynamic>{'content': '', 'messageType': 'VOICE'};
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
        // Re-upload needed (native only; web has no cached bytes)
        final localPath = message.mediaUrl;
        if (localPath == null || localPath.isEmpty) {
          _errorMessage = 'Retry not available for this message';
          notifyListeners();
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
      // If Cloudinary URL already obtained, skip re-upload
      if (message.mediaUrl != null && message.mediaUrl!.contains('cloudinary')) {
        _messages[index] = _messages[index].copyWith(
          deliveryStatus: MessageDeliveryStatus.sending,
        );
        _pendingSendContent[tempId] = <String, dynamic>{'content': '', 'messageType': 'IMAGE'};
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
        sendMessage(content, replyToMessageId: message.replyToMessageId);
      }
    }
  }

  Future<void> sendImageMessage(
    String token,
    XFile imageFile,
    int recipientId,
  ) async {
    if (_activeConversationId == null || _currentUserId == null) return;

    final effectiveExpiresIn = conversationDisappearingTimer;
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}_$_currentUserId';

    // Create optimistic message
    final tempMessage = MessageModel(
      id: -(++ChatProvider._tempIdSeq),
      content: '',
      senderId: _currentUserId!,
      senderUsername: '',
      conversationId: _activeConversationId!,
      createdAt: DateTime.now(),
      deliveryStatus: MessageDeliveryStatus.sending,
      messageType: MessageType.image,
      expiresAt: effectiveExpiresIn != null
          ? DateTime.now().add(Duration(seconds: effectiveExpiresIn))
          : null,
      tempId: tempId,
    );

    _messages.add(tempMessage);
    _pendingSendContent[tempId] = <String, dynamic>{'content': '', 'messageType': 'IMAGE'};
    notifyListeners();

    try {
      // Upload to Cloudinary (no message created in DB)
      final responseData = await _api.uploadMedia(
        token: token,
        type: 'image',
        imageFile: imageFile,
        expiresIn: effectiveExpiresIn,
      );

      final cloudinaryUrl = responseData['mediaUrl'] as String;

      // Update optimistic message with URL
      final idx = _messages.indexWhere((m) => m.tempId == tempId);
      if (idx != -1) {
        _messages[idx] = _messages[idx].copyWith(mediaUrl: cloudinaryUrl);
        notifyListeners();
      }

      // Encrypt and send
      _encryptAndSend(
        recipientId: recipientId,
        content: '',
        tempId: tempId,
        effectiveExpiresIn: effectiveExpiresIn,
        messageType: 'IMAGE',
        mediaUrl: cloudinaryUrl,
      );
    } catch (e) {
      debugPrint('[ChatProvider] Image upload failed: $e');
      _markMessageFailed(tempId, 'Image upload failed: ${e.toString()}');
    }
  }

  Future<void> sendAntiQuantumNote({
    required String content,
    required int expiresInSeconds,
  }) async {
    final token = _reconnect.tokenForReconnect;
    if (token == null) return;

    // AES-256-GCM client-side encryption using pointycastle
    // Key: 32 random bytes; IV: 12 random bytes (96-bit, standard for GCM)
    final keyBytes = _secureRandomBytes(32);
    final ivBytes = _secureRandomBytes(12);

    final cipher = GCMBlockCipher(AESEngine());
    final params = AEADParameters(
      KeyParameter(keyBytes),
      128, // auth tag length in bits
      ivBytes,
      Uint8List(0), // no additional authenticated data
    );
    cipher.init(true, params); // true = encrypt

    final plainBytes = Uint8List.fromList(utf8.encode(content));
    final ciphertextWithTag = cipher.process(plainBytes);

    // Format: base64(iv):base64(ciphertext+tag)
    final ciphertextEncoded =
        '${base64.encode(ivBytes)}:${base64.encode(ciphertextWithTag)}';

    // POST /notes with ciphertext (server never sees key)
    final noteToken =
        await _api.createSecretNote(token, ciphertextEncoded, expiresInSeconds);

    // Key encoded as base64url for URL fragment (#KEY)
    final keyBase64Url = base64Url.encode(keyBytes);
    final noteUrl = '${AppConfig.baseUrl}/note/$noteToken#$keyBase64Url';

    // Send URL as a plain text message in the active conversation
    sendMessage(noteUrl);
  }

  Uint8List _secureRandomBytes(int length) {
    final random = FortunaRandom();
    final seedSource = Random.secure();
    final seeds = List<int>.generate(32, (_) => seedSource.nextInt(256));
    random.seed(KeyParameter(Uint8List.fromList(seeds)));
    return random.nextBytes(length);
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

    // Clear active conversation if it was deleted (we are the initiator)
    if (_activeConversationId == convId) {
      _activeConversationId = null;
      _activeConversationDeletedByOther = false;
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
    _e2eFlowLog('E2E_INIT_START', {'alreadyInitialized': _e2eInitialized});
    try {
      if (!_e2eInitialized) {
        // Fresh session: load keys from storage (or generate on first install).
        await _encryptionService.initialize(_currentUserId!);
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
      // Only clear the flag if we hadn't initialized yet; don't undo a working
      // reconnect just because the re-upload attempt threw.
      if (!_e2eInitialized) _e2eInitialized = false;
      _e2eFlowLog('E2E_INIT_FAIL', {'error': e.toString()});
    }
  }

  Future<void> _ensureSession(int recipientId) async {
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

  Future<void> _decryptMessageHistory(int generation) async {
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
      if (_decryptHistoryGeneration != generation) break; // newer history arrived, abort
      final msg = sorted[i];
      // Skip messages we already failed to decrypt (avoids repeated work and UI freeze)
      if (msg.content == '[Decryption failed]') continue;
      if (msg.needsDecryption(_currentUserId)) {
        // Cache-first: check persisted cache before attempting live decryption.
        // This avoids unnecessary session ratchet advancement and recovers
        // messages when keys are lost (e.g. IndexedDB eviction on web).
        final cached = _decryptedContentCache[msg.id];
        if (cached != null) {
          final idx = _messages.indexWhere((m) => m.id == msg.id);
          if (idx != -1) { _messages[idx] = cached; changed = true; }
          continue;
        }
        final persisted = await _encryptionService.getDecryptedContent(msg.id);
        if (persisted != null && (persisted['content'] as String? ?? '').isNotEmpty) {
          final safeImageUrl = persisted['linkPreviewImageUrl'] as String?;
          final safePageUrl = persisted['linkPreviewUrl'] as String?;
          final validImage = safeImageUrl != null &&
                  safePageUrl != null &&
                  LinkPreviewService.isSafeImageUrl(safeImageUrl, safePageUrl)
              ? safeImageUrl
              : null;
          final restoredType = _parseMessageTypeString(persisted['messageType'] as String?);
          final restored = msg.copyWith(
            content: persisted['content'] as String,
            messageType: restoredType,
            mediaUrl: persisted['mediaUrl'] as String?,
            mediaDuration: persisted['mediaDuration'] as int?,
            linkPreviewUrl: persisted['linkPreviewUrl'] as String?,
            linkPreviewTitle: persisted['linkPreviewTitle'] as String?,
            linkPreviewImageUrl: validImage,
          );
          _decryptedContentCache[msg.id] = restored;
          final idx = _messages.indexWhere((m) => m.id == msg.id);
          if (idx != -1) { _messages[idx] = restored; changed = true; }
          continue;
        }
        // No cache — live decrypt (advances session ratchet)
        final decrypted = await _decryptMessageAsync(msg);
        final idx = _messages.indexWhere((m) => m.id == msg.id);
        if (idx != -1) {
          _messages[idx] = decrypted;
          changed = true;
        }
      } else if (msg.senderId == _currentUserId && msg.content == '[encrypted]') {
        final stored = await _encryptionService.getDecryptedContent(msg.id);
        final storedContent = stored?['content'] as String? ?? '';
        if (storedContent.isNotEmpty || (stored?['messageType'] as String?) != null) {
          // Restore all fields from persisted cache (SSRF validated)
          final rawImageUrl = stored?['linkPreviewImageUrl'] as String?;
          final rawPageUrl = stored?['linkPreviewUrl'] as String?;
          final safeImageUrl = rawImageUrl != null &&
                  rawPageUrl != null &&
                  LinkPreviewService.isSafeImageUrl(rawImageUrl, rawPageUrl)
              ? rawImageUrl
              : null;
          final restoredType = _parseMessageTypeString(stored?['messageType'] as String?);
          final restored = msg.copyWith(
            content: storedContent.isNotEmpty ? storedContent : null,
            messageType: restoredType,
            mediaUrl: stored?['mediaUrl'] as String?,
            mediaDuration: stored?['mediaDuration'] as int?,
            linkPreviewUrl: stored?['linkPreviewUrl'] as String?,
            linkPreviewTitle: stored?['linkPreviewTitle'] as String?,
            linkPreviewImageUrl: safeImageUrl,
          );
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
        // SSRF: validate imageUrl before storing (defense in depth for old/untrusted envelopes)
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
          linkPreviewUrl: parsed.linkPreviewUrl,
          linkPreviewTitle: parsed.linkPreviewTitle,
          linkPreviewImageUrl: safeImageUrl,
        );
        // Trigger ping effect for recipient when decrypted type is PING
        if (parsedType == MessageType.ping && msg.senderId != _currentUserId) {
          _showPingEffect = true;
        }
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
        // SSRF: validate imageUrl when restoring from persistence (defense in depth for old data)
        final rawImageUrl = persisted['linkPreviewImageUrl'] as String?;
        final rawPageUrl = persisted['linkPreviewUrl'] as String?;
        final safeImageUrl = rawImageUrl != null &&
                rawPageUrl != null &&
                LinkPreviewService.isSafeImageUrl(rawImageUrl, rawPageUrl)
            ? rawImageUrl
            : null;
        final restoredType = _parseMessageTypeString(persisted['messageType'] as String?);
        final restored = msg.copyWith(
          content: persistedContent,
          messageType: restoredType,
          mediaUrl: persisted['mediaUrl'] as String?,
          mediaDuration: persisted['mediaDuration'] as int?,
          linkPreviewUrl: persisted['linkPreviewUrl'] as String?,
          linkPreviewTitle: persisted['linkPreviewTitle'] as String?,
          linkPreviewImageUrl: safeImageUrl,
        );
        _decryptedContentCache[msg.id] = restored;
        return restored;
      }
      debugPrint('[E2E] Decrypt failed for msg ${msg.id}: $e');
      _e2eFlowLog('DECRYPT_FAIL', {'msgId': msg.id, 'error': e.toString()});
      // For live incoming messages (not history replay): delete the broken session
      // and ask sender to rebuild theirs too, so their next message is type-3.
      if (!_decryptingHistory) {
        // Mark for rebuild on next send (atomic in _ensureSession); don't delete here
        // to avoid racing with an in-flight encrypt() on the same session.
        _forceSessionRebuild.add(msg.senderId);
        _socketService.requestSessionRebuild(msg.senderId);
        _e2eFlowLog('SESSION_RESET', {'peerId': msg.senderId});
      }
      return msg.copyWith(content: '[Decryption failed]');
    }
  }

  // ---------- Connection lifecycle ----------

  /// If socket is disconnected but we have token and userId (user was logged in),
  /// reconnect and refetch. Call when app resumes from background.
  void ensureReconnectIfNeeded() {
    if (_socketService.isConnected) return;
    if (_currentUserId == null || _reconnect.tokenForReconnect == null) return;
    connect(token: _reconnect.tokenForReconnect!, userId: _currentUserId!);
  }

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
    _pendingSendContent.clear();
    _decryptedContentCache.clear();
    _incomingMessageQueue.clear();
    _decryptingHistory = false;
    _decryptHistoryGeneration++; // cancel any in-flight history decrypt
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

}
