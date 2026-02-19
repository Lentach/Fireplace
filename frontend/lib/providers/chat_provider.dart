import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import '../config/app_config.dart';
import '../constants/app_constants.dart';
import '../models/conversation_model.dart';
import '../models/friend_request_model.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import 'chat_reconnect_manager.dart';
import 'conversation_helpers.dart' as conv_helpers;

class ChatProvider extends ChangeNotifier {
  final SocketService _socketService = SocketService();
  final ChatReconnectManager _reconnect = ChatReconnectManager();

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
  bool _friendRequestJustSent = false;
  bool _showPingEffect = false;
  List<UserModel>? _searchResults;
  final Map<int, int> _unreadCounts = {}; // conversationId -> count

  /// Ticks every second for countdown display. Bubbles use ValueListenableBuilder
  /// so only they rebuild, not the whole screen. Prevents recording timer freeze.
  final ValueNotifier<int> countdownTickNotifier = ValueNotifier(0);

  /// True while user holds mic to record. Countdown timer skips ticks to avoid
  /// starving the recording timer callback (progressive freeze).
  bool isRecordingVoice = false;

  List<ConversationModel> get conversations => _conversations;
  List<MessageModel> get messages => _messages;
  int? get activeConversationId => _activeConversationId;
  int? get currentUserId => _currentUserId;
  String? get errorMessage => _errorMessage;
  Map<int, MessageModel> get lastMessages => _lastMessages;
  int? get pendingOpenConversationId => _pendingOpenConversationId;
  List<FriendRequestModel> get friendRequests => _friendRequests;
  int get pendingRequestsCount => _pendingRequestsCount;
  List<UserModel> get friends => _friends;
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

  /// Returns conversation by id, or null if not found.
  ConversationModel? getConversationById(int id) =>
      _conversations.where((c) => c.id == id).firstOrNull;

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

    // If this is our own message (messageSent), replace temp optimistic message
    if (msg.senderId == _currentUserId && msg.tempId != null) {
      final tempIndex = _messages.indexWhere((m) => m.tempId == msg.tempId);
      if (tempIndex != -1) {
        _messages.removeAt(tempIndex);
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
    _unreadCounts.clear();
    _pendingOpenConversationId = null;
    _friendRequests = [];
    _pendingRequestsCount = 0;
    _friends = [];
    _friendRequestJustSent = false;
    _searchResults = null;
    _errorMessage = null;

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
        _socketService.getConversations();
        _socketService.getFriendRequests();
        _socketService.getFriends();
        Future.delayed(AppConstants.conversationsRefreshDelay, () {
          if (_conversations.isEmpty) {
            _socketService.getConversations();
          }
        });
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
              final lastMsg = MessageModel.fromJson(lastMsgData as Map<String, dynamic>);
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

        // Immediately remove any already-expired messages
        final now = DateTime.now();
        _messages.removeWhere(
          (m) => m.expiresAt != null && m.expiresAt!.isBefore(now),
        );
        notifyListeners();
        if (_activeConversationId != null) {
          markConversationRead(_activeConversationId!);
        }
      },
      onMessageSent: _handleIncomingMessage,
      onNewMessage: _handleIncomingMessage,
      onOpenConversation: (data) {
        final convId = (data as Map<String, dynamic>)['conversationId'] as int;
        _pendingOpenConversationId = convId;
        notifyListeners();
      },
      onError: (err) {
        if (err is Map<String, dynamic> && err['message'] != null) {
          _errorMessage = err['message'] as String;
        } else {
          _errorMessage = err.toString();
        }
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
        if (_activeConversationId != null) {
          final activeConv = _conversations.where((c) => c.id == _activeConversationId).firstOrNull;
          if (activeConv == null) {
            _activeConversationId = null;
            _messages = [];
          }
        }
        notifyListeners();
      },
      onMessageDelivered: _handleMessageDelivered,
      onPingReceived: _handlePingReceived,
      onPingSent: _handlePingReceived,
      onChatHistoryCleared: _handleChatHistoryCleared,
      onDisappearingTimerUpdated: _handleDisappearingTimerUpdated,
      onConversationDeleted: _handleConversationDeleted,
      onSearchUsersResult: (data) {
        final list = data as List<dynamic>;
        _searchResults = list
            .map((u) => UserModel.fromJson(u as Map<String, dynamic>))
            .toList();
        notifyListeners();
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

  void sendMessage(String content, {int? expiresIn}) {
    if (_activeConversationId == null || _currentUserId == null) return;

    final conv = _conversations.firstWhere(
      (c) => c.id == _activeConversationId,
    );

    final recipientId = conv.userOne.id == _currentUserId
        ? conv.userTwo.id
        : conv.userOne.id;

    // Use conversation disappearing timer if expiresIn not provided
    final effectiveExpiresIn = expiresIn ?? conversationDisappearingTimer;

    // Generate unique tempId for optimistic message matching
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}_$_currentUserId';

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
    );

    _messages.add(tempMessage);
    notifyListeners();

    _socketService.sendMessage(
      recipientId,
      content,
      expiresIn: effectiveExpiresIn,
      tempId: tempId,
    );
  }

  void sendPing(int recipientId) {
    _socketService.sendPing(recipientId);
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

  bool isFriend(int userId) {
    return _friends.any((f) => f.id == userId);
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
    _unreadCounts.clear();
    _pendingOpenConversationId = null;
    _friendRequests = [];
    _pendingRequestsCount = 0;
    _friends = [];
    _friendRequestJustSent = false;
    notifyListeners();
  }

}
