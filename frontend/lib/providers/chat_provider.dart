import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
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
import '../services/link_preview_service.dart';
import '../utils/e2e_envelope.dart';
import '../services/push_service.dart';
import '../services/socket_service.dart';
import 'chat_reconnect_manager.dart';
import 'conversation_helpers.dart' as conv_helpers;
import 'encryption_provider.dart';
import 'friends_provider.dart';

class ChatProvider extends ChangeNotifier {
  static void _e2eFlowLog(String step, [Map<String, dynamic>? data]) {
    if (kDebugMode) debugPrint('[E2E-FLOW] $step | ${data ?? {}}');
  }

  final SocketService _socketService = SocketService();
  final ChatReconnectManager _reconnect = ChatReconnectManager();
  late final ApiService _api = ApiService(baseUrl: AppConfig.baseUrl);
  late final PushService _pushService = PushService(_api);
  bool _pushInitialized = false;

  // ---------- EncryptionProvider facade ----------
  EncryptionProvider? _encryptionProvider;

  /// Wire the EncryptionProvider so ChatProvider can delegate E2E state.
  /// Called once from the widget tree after both providers are available.
  void setEncryptionProvider(EncryptionProvider ep) {
    _encryptionProvider = ep;
    // Set up emit callback so EncryptionProvider can send socket events
    ep.setEmitCallback((event, data) {
      switch (event) {
        case 'uploadKeyBundle':
          _socketService.uploadKeyBundle(data as Map<String, dynamic>);
        case 'uploadOneTimePreKeys':
          _socketService.uploadOneTimePreKeys(
              (data as List).cast<Map<String, dynamic>>());
        case 'fetchPreKeyBundle':
          _socketService.fetchPreKeyBundle(data as int);
        default:
          debugPrint('[ChatProvider] Unknown emit event: $event');
      }
    });
  }

  // ---------- FriendsProvider facade ----------
  FriendsProvider? _friendsProvider;

  /// Wire the FriendsProvider so ChatProvider can delegate friend state.
  /// Called once from the widget tree after both providers are available.
  void setFriendsProvider(FriendsProvider fp) {
    _friendsProvider = fp;
    // Set up emit callback so FriendsProvider can send socket events
    fp.setEmitCallback((event, data) {
      switch (event) {
        case 'searchUsers':
          _socketService.searchUsers(data as String);
        case 'sendFriendRequest':
          _socketService.sendFriendRequest(data as int);
        case 'acceptFriendRequest':
          _socketService.acceptFriendRequest(data as int);
        case 'rejectFriendRequest':
          _socketService.rejectFriendRequest(data as int);
        case 'unfriend':
          _socketService.unfriend(data as int);
        case 'blockUser':
          _socketService.emitBlockUser(data as int);
        case 'unblockUser':
          _socketService.emitUnblockUser(data as int);
        case 'getBlockedList':
          _socketService.getBlockedList();
        case 'getFriendRequests':
          _socketService.getFriendRequests();
        case 'getFriends':
          _socketService.getFriends();
        default:
          debugPrint('[ChatProvider] Unknown friend emit event: $event');
      }
    });
    // Wire cross-provider callbacks so friend events can update conversations
    fp.onRemoveConversationsForUser = (userId) {
      if (userId == -1) {
        // blockedList: remove convs for all blocked users
        final blockedIds = fp.blockedUsers.map((u) => u.id).toSet();
        _conversations.removeWhere((c) =>
            blockedIds.contains(c.userOne.id) || blockedIds.contains(c.userTwo.id));
      } else {
        _conversations.removeWhere((c) =>
            c.userOne.id == userId || c.userTwo.id == userId);
      }
      _clearActiveIfRemoved();
      notifyListeners();
    };
    fp.onClearActiveIfNeeded = (userId) {
      // Already handled by _clearActiveIfRemoved in onRemoveConversationsForUser
    };
  }

  // ---------- E2E Encryption ----------
  /// Single delayed retry for a failed text message (e.g. recipient had no key bundle, then came online).
  Timer? _delayedRetryTimer;
  String? _delayedRetryTempId;
  bool _decryptingHistory = false;
  /// Incremented on each new messageHistory to cancel stale in-flight decrypt loops.
  /// Each loop captures its generation at start and exits when the counter changes.
  int _decryptHistoryGeneration = 0;
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
  /// True when our active conversation was removed from list (e.g. other user deleted).
  bool _activeConversationDeletedByOther = false;
  bool _showPingEffect = false;
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
  List<FriendRequestModel> get friendRequests => _friendsProvider?.friendRequests ?? [];
  int get pendingRequestsCount => _friendsProvider?.pendingRequestsCount ?? 0;
  List<UserModel> get friends => _friendsProvider?.friends ?? [];
  List<UserModel> get blockedUsers => _friendsProvider?.blockedUsers ?? [];
  Set<int> get blockedByUserIds => _friendsProvider?.blockedByUserIds ?? {};
  String? get pendingFriendAcceptedByName => _friendsProvider?.pendingFriendAcceptedByName;
  bool get activeConversationDeletedByOther => _activeConversationDeletedByOther;
  List<UserModel>? get searchResults => _friendsProvider?.searchResults;
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
        _encryptionProvider?.cacheDecryption(decrypted.id, decrypted);
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
      await _encryptionProvider?.encryptionService.saveDecryptedContent(decrypted.id, data);
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
        _encryptionProvider?.encryptionService.saveDecryptedContent(msg.id, persistData).catchError((_) {});
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
    return _friendsProvider?.consumeFriendRequestSent() ?? false;
  }

  /// Returns acceptor's username and clears; null if none. Call when showing snackbar.
  String? consumePendingFriendAccepted() {
    return _friendsProvider?.consumePendingFriendAccepted();
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
      _activeConversationDeletedByOther = false;
      _errorMessage = null;
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
      _activeConversationDeletedByOther = false;
      _errorMessage = null;
      _cancelDelayedRetryIfAny();
    }

    notifyListeners();

    // Notify EncryptionProvider of connect lifecycle
    _encryptionProvider?.onConnect(isReconnect);

    // Notify FriendsProvider of connect lifecycle
    _friendsProvider?.setCurrentUserId(userId);
    _friendsProvider?.onConnect(isReconnect);

    // Clean up old socket if it exists
    if (_socketService.socket != null) {
      _socketService.disconnect();
    }

    _currentUserId = userId;
    _socketService.connect(baseUrl: AppConfig.baseUrl, token: token);

    // ---------- Register event listeners ----------

    _socketService.onConnect(() {
      _reconnect.resetAttempts();
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
      // Initialize E2E encryption (delegated to EncryptionProvider)
      _encryptionProvider?.initializeE2E(userId);
    });

    _socketService.on('conversationsList', (data) {
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
    });

    _socketService.on('messageHistory', (data) {
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
    });

    _socketService.on('messageSent', _handleIncomingMessage);
    _socketService.on('newMessage', _handleIncomingMessage);

    _socketService.on('openConversation', (data) {
      final convId = (data as Map<String, dynamic>)['conversationId'] as int;
      _pendingOpenConversationId = convId;
      notifyListeners();
    });

    _socketService.on('error', (err) {
      final String msg = err is Map<String, dynamic> && err['message'] != null
          ? err['message'] as String
          : err.toString();
      _errorMessage = msg;
      // If server rejected send (e.g. not friends, blocked), mark optimistic message as failed so Retry appears
      _markSendingMessagesFailed(msg);
      notifyListeners();
    });

    // Friend events -> FriendsProvider
    _socketService.on('friendRequestsList', (data) => _friendsProvider?.onFriendRequestsList(data));
    _socketService.on('newFriendRequest', (data) => _friendsProvider?.onNewFriendRequest(data));
    _socketService.on('friendRequestSent', (data) => _friendsProvider?.onFriendRequestSent(data));
    _socketService.on('friendRequestAccepted', (data) => _friendsProvider?.onFriendRequestAccepted(data));
    _socketService.on('friendRequestRejected', (data) => _friendsProvider?.onFriendRequestRejected(data));
    _socketService.on('pendingRequestsCount', (data) => _friendsProvider?.onPendingRequestsCount(data));
    _socketService.on('friendsList', (data) => _friendsProvider?.onFriendsList(data));
    _socketService.on('unfriended', (data) => _friendsProvider?.onUnfriended(data));
    _socketService.on('blockedList', (data) => _friendsProvider?.onBlockedList(data));
    _socketService.on('youWereBlocked', (data) => _friendsProvider?.onYouWereBlocked(data));
    _socketService.on('searchUsersResult', (data) => _friendsProvider?.onSearchUsersResult(data));

    // Message state events
    _socketService.on('messageDelivered', _handleMessageDelivered);
    _socketService.on('chatHistoryCleared', _handleChatHistoryCleared);
    _socketService.on('messageDeleted', _handleMessageDeleted);
    _socketService.on('disappearingTimerUpdated', _handleDisappearingTimerUpdated);
    _socketService.on('conversationDeleted', _handleConversationDeleted);

    // UI events
    _socketService.on('partnerTyping', _handlePartnerTyping);
    _socketService.on('partnerRecordingVoice', _handlePartnerRecordingVoice);
    _socketService.on('reactionUpdated', _handleReactionUpdated);
    _socketService.on('linkPreviewReady', _handleLinkPreviewReady);

    // Encryption events -> EncryptionProvider
    _socketService.on('keyBundleUploaded', _encryptionProvider?.onKeyBundleUploaded ?? (_) {});
    _socketService.on('oneTimePreKeysUploaded', _encryptionProvider?.onOneTimePreKeysUploaded ?? (_) {});
    _socketService.on('preKeyBundleResponse', _encryptionProvider?.onPreKeyBundleResponse ?? (_) {});
    _socketService.on('preKeysLow', _encryptionProvider?.onPreKeysLow ?? (_) {});
    _socketService.on('sessionRebuildNeeded', _encryptionProvider?.onSessionRebuildNeeded ?? (_) {});

    _socketService.onDisconnect((_) {
      _reconnect.onDisconnect(
        () => connect(token: _reconnect.tokenForReconnect!, userId: _currentUserId!),
        (msg) {
          _errorMessage = msg;
          notifyListeners();
        },
      );
    });
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
              : rt.messageType == MessageType.file
                  ? 'File'
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
    final e2eReady = _encryptionProvider?.isE2EReady ?? false;
    _e2eFlowLog('SEND_START', {'recipientId': recipientId, 'e2eInitialized': e2eReady, 'messageType': messageType});
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
      await _encryptionProvider!.ensureSession(recipientId);

      // 5. Encrypt
      final ciphertext =
          await _encryptionProvider!.encrypt(recipientId, envelopeJson);
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
      _encryptionProvider?.clearPendingPreKeyFetch(recipientId);
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
      case 'GIF': return MessageType.gif;
      case 'FILE': return MessageType.file;
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
    if (!(_encryptionProvider?.isE2EReady ?? false)) {
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

    if (message.messageType == MessageType.file) {
      if (message.mediaUrl != null && message.mediaUrl!.contains('cloudinary')) {
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

  /// Send a GIF message. Downloads from Giphy, uploads to Cloudinary, encrypts URL.
  Future<void> sendGif(
    String token,
    String gifUrl,
    int recipientId,
  ) async {
    if (_activeConversationId == null || _currentUserId == null) return;

    final effectiveExpiresIn = conversationDisappearingTimer;
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}_$_currentUserId';

    // 1. Optimistic message
    final tempMessage = MessageModel(
      id: -(++ChatProvider._tempIdSeq),
      content: '',
      senderId: _currentUserId!,
      senderUsername: '',
      conversationId: _activeConversationId!,
      createdAt: DateTime.now(),
      deliveryStatus: MessageDeliveryStatus.sending,
      messageType: MessageType.gif,
      expiresAt: effectiveExpiresIn != null
          ? DateTime.now().add(Duration(seconds: effectiveExpiresIn))
          : null,
      tempId: tempId,
    );

    _messages.add(tempMessage);
    _pendingSendContent[tempId] = <String, dynamic>{'content': '', 'messageType': 'GIF'};
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

      // 4. Upload to Cloudinary
      final responseData = await _api.uploadMedia(
        token: token,
        type: 'gif',
        gifBytes: gifBytes,
        expiresIn: effectiveExpiresIn,
      );

      final cloudinaryUrl = responseData['mediaUrl'] as String;

      // 5. Update optimistic message with URL
      final idx = _messages.indexWhere((m) => m.tempId == tempId);
      if (idx != -1) {
        _messages[idx] = _messages[idx].copyWith(mediaUrl: cloudinaryUrl);
        notifyListeners();
      }

      // 6. Encrypt and send
      _encryptAndSend(
        recipientId: recipientId,
        content: '',
        tempId: tempId,
        effectiveExpiresIn: effectiveExpiresIn,
        messageType: 'GIF',
        mediaUrl: cloudinaryUrl,
      );
    } catch (e) {
      debugPrint('[ChatProvider] GIF send failed: $e');
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
    if (_activeConversationId == null || _currentUserId == null) return;

    final effectiveExpiresIn = conversationDisappearingTimer;
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}_$_currentUserId';

    final tempMessage = MessageModel(
      id: -(++ChatProvider._tempIdSeq),
      content: fileName,
      senderId: _currentUserId!,
      senderUsername: '',
      conversationId: _activeConversationId!,
      createdAt: DateTime.now(),
      deliveryStatus: MessageDeliveryStatus.sending,
      messageType: MessageType.file,
      tempId: tempId,
    );

    _messages.add(tempMessage);
    _pendingSendContent[tempId] = <String, dynamic>{
      'content': fileName,
      'messageType': 'FILE',
    };
    notifyListeners();

    try {
      final responseData = await _api.uploadMedia(
        token: token,
        type: 'file',
        fileBytes: fileBytes,
        fileName: fileName,
        fileMimeType: fileMimeType,
      );

      final mediaUrl = responseData['mediaUrl'] as String;

      final idx = _messages.indexWhere((m) => m.tempId == tempId);
      if (idx != -1) {
        _messages[idx] = _messages[idx].copyWith(mediaUrl: mediaUrl);
        notifyListeners();
      }

      _pendingSendContent[tempId] = <String, dynamic>{
        'content': fileName,
        'messageType': 'FILE',
        'mediaUrl': mediaUrl,
      };

      _encryptAndSend(
        recipientId: recipientId,
        content: fileName,
        tempId: tempId,
        effectiveExpiresIn: effectiveExpiresIn,
        messageType: 'FILE',
        mediaUrl: mediaUrl,
      );
    } catch (e) {
      debugPrint('[ChatProvider] File send failed: $e');
      _markMessageFailed(tempId, 'File send failed: ${e.toString()}');
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
    _friendsProvider?.searchUsers(handle);
  }

  void clearSearchResults() {
    _friendsProvider?.clearSearchResults();
  }

  void startConversation(int recipientId) {
    _socketService.startConversation(recipientId);
  }

  void deleteConversationOnly(int conversationId) {
    _socketService.emitDeleteConversationOnly(conversationId);
  }

  void sendFriendRequest(int recipientId) {
    _friendsProvider?.sendFriendRequest(recipientId);
  }

  void acceptFriendRequest(int requestId) {
    _friendsProvider?.acceptFriendRequest(requestId);
  }

  void rejectFriendRequest(int requestId) {
    _friendsProvider?.rejectFriendRequest(requestId);
  }

  void fetchFriendRequests() {
    _friendsProvider?.loadFriendRequests();
  }

  void fetchFriends() {
    _friendsProvider?.loadFriends();
  }

  void unfriend(int userId) {
    _friendsProvider?.unfriend(userId);
  }

  void blockUser(int userId) {
    _friendsProvider?.blockUser(userId);
  }

  void unblockUser(int userId) {
    _friendsProvider?.unblockUser(userId);
  }

  void loadBlockedList() {
    _friendsProvider?.loadBlockedList();
  }

  bool isFriend(int userId) {
    return _friendsProvider?.isFriend(userId) ?? false;
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
        final cached = _encryptionProvider?.getCachedDecryption(msg.id);
        if (cached != null) {
          final idx = _messages.indexWhere((m) => m.id == msg.id);
          if (idx != -1) { _messages[idx] = cached; changed = true; }
          continue;
        }
        final persisted = await _encryptionProvider!.encryptionService.getDecryptedContent(msg.id);
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
          _encryptionProvider?.cacheDecryption(msg.id, restored);
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
        final stored = await _encryptionProvider!.encryptionService.getDecryptedContent(msg.id);
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

    if (!(_encryptionProvider?.isE2EReady ?? false)) {
      return msg.copyWith(content: '[Encryption not initialized]');
    }

    _e2eFlowLog('DECRYPT_START', {'msgId': msg.id, 'senderId': msg.senderId});
    try {
      final plaintext = await _encryptionProvider!.decrypt(
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
        _encryptionProvider?.cacheDecryption(msg.id, decryptedMsg);
        await _persistDecryptedContent(decryptedMsg);
        return decryptedMsg;
      } catch (parseErr) {
        debugPrint('[E2E] Envelope parse failed for msg ${msg.id}, using raw plaintext: $parseErr');
        final fallback = msg.copyWith(content: plaintext);
        _encryptionProvider?.cacheDecryption(msg.id, fallback);
        if (plaintext.isNotEmpty) await _persistDecryptedContent(fallback);
        return fallback;
      }
    } catch (e) {
      // DuplicateMessageException: session was already advanced. Use memory cache or persisted cache (survives logout).
      final cached = _encryptionProvider?.getCachedDecryption(msg.id);
      if (cached != null) return cached;
      final persisted = await _encryptionProvider!.encryptionService.getDecryptedContent(msg.id);
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
        _encryptionProvider?.cacheDecryption(msg.id, restored);
        return restored;
      }
      debugPrint('[E2E] Decrypt failed for msg ${msg.id}: $e');
      _e2eFlowLog('DECRYPT_FAIL', {'msgId': msg.id, 'error': e.toString()});
      // For live incoming messages (not history replay): delete the broken session
      // and ask sender to rebuild theirs too, so their next message is type-3.
      if (!_decryptingHistory) {
        // Mark for rebuild on next send (atomic in ensureSession); don't delete here
        // to avoid racing with an in-flight encrypt() on the same session.
        _encryptionProvider?.markSessionRebuild(msg.senderId);
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
    _pushInitialized = false; // Allow re-registration on next login
    // Notify EncryptionProvider of disconnect lifecycle (clears pending fetches,
    // but keys persist in secure storage for next login)
    _encryptionProvider?.onDisconnect();
    _encryptionProvider?.clearAll();
    // Notify FriendsProvider of disconnect lifecycle
    _friendsProvider?.onDisconnect();
    _friendsProvider?.clearAll();
    _pendingSendContent.clear();
    _incomingMessageQueue.clear();
    _decryptingHistory = false;
    _decryptHistoryGeneration++; // cancel any in-flight history decrypt
    notifyListeners();
  }

  /// Identity key fingerprint for display in Privacy & Safety screen.
  Future<String?> getIdentityFingerprint() =>
      _encryptionProvider?.getIdentityFingerprint() ?? Future.value(null);

  /// Clear all E2E encryption keys. Call on account deletion only.
  Future<void> clearEncryptionKeys() async {
    await _encryptionProvider?.clearEncryptionKeys();
  }

}
