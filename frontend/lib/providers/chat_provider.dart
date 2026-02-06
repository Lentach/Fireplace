import 'dart:async';

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

class ChatProvider extends ChangeNotifier {
  final SocketService _socketService = SocketService();

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
  bool _intentionalDisconnect = false;
  String? _tokenForReconnect;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  final Map<int, int?> _conversationTimers = {}; // conversationId -> seconds
  bool _showPingEffect = false;

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
  SocketService get socket => _socketService;

  int? get conversationDisappearingTimer {
    if (_activeConversationId == null) return null;
    return _conversationTimers[_activeConversationId];
  }

  bool get showPingEffect => _showPingEffect;

  void setConversationDisappearingTimer(int? seconds) {
    if (_activeConversationId == null) return;
    _conversationTimers[_activeConversationId!] = seconds;
    notifyListeners();
  }

  void clearPingEffect() {
    _showPingEffect = false;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

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
    notifyListeners();

    if (msg.senderId != _currentUserId) {
      _socketService.emitMessageDelivered(msg.id);
      if (msg.conversationId == _activeConversationId) {
        markConversationRead(msg.conversationId);
      }
    }
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

  String getOtherUserEmail(ConversationModel conv) {
    if (_currentUserId == null) return '';
    return conv.userOne.id == _currentUserId
        ? conv.userTwo.email
        : conv.userOne.email;
  }

  String getOtherUserUsername(ConversationModel conv) {
    if (_currentUserId == null) return '';
    final otherUser = conv.userOne.id == _currentUserId
        ? conv.userTwo
        : conv.userOne;
    return otherUser.username ?? otherUser.email;
  }

  int getOtherUserId(ConversationModel conv) {
    if (_currentUserId == null) return 0;
    return conv.userOne.id == _currentUserId
        ? conv.userTwo.id
        : conv.userOne.id;
  }

  UserModel? getOtherUser(ConversationModel conv) {
    if (_currentUserId == null) return null;
    return conv.userOne.id == _currentUserId
        ? conv.userTwo
        : conv.userOne;
  }

  void connect({required String token, required int userId}) {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _intentionalDisconnect = false;
    _tokenForReconnect = token;

    // Clear ALL state before connecting to prevent data leakage between users
    _conversations = [];
    _messages = [];
    _activeConversationId = null;
    _lastMessages.clear();
    _pendingOpenConversationId = null;
    _friendRequests = [];
    _pendingRequestsCount = 0;
    _friends = [];
    _friendRequestJustSent = false;
    _errorMessage = null;

    // Notify listeners immediately so UI shows empty state
    notifyListeners();

    // Clean up old socket if it exists
    if (_socketService.socket != null) {
      _socketService.disconnect();
    }

    debugPrint('[ChatProvider] Connecting WebSocket for userId=$userId');

    _currentUserId = userId;
    _socketService.connect(
      baseUrl: AppConfig.baseUrl,
      token: token,
      onConnect: () {
        _reconnectAttempts = 0; // Reset on successful connection
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
        notifyListeners();
      },
      onMessageHistory: (data) {
        final list = data as List<dynamic>;
        final now = DateTime.now();
        _messages = list
            .map((m) => MessageModel.fromJson(m as Map<String, dynamic>))
            .where((m) => m.expiresAt == null || m.expiresAt!.isAfter(now))
            .toList();
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
      onDisconnect: (_) => _onDisconnect(),
    );
  }

  void openConversation(int conversationId, {int limit = AppConstants.messagePageSize}) {
    _activeConversationId = conversationId;
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
    // Also clean up lastMessages so conversation list doesn't show stale entries
    _lastMessages.removeWhere(
      (_, m) => m.expiresAt != null && m.expiresAt!.isBefore(now),
    );
    notifyListeners();
  }

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
      senderEmail: '', // Will be replaced when server confirms
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

    // Set flag for showing ping effect
    _showPingEffect = true;

    notifyListeners();
  }

  void startConversation(String recipientEmail) {
    _socketService.startConversation(recipientEmail);
  }

  void deleteConversation(int conversationId) {
    // Optimistic UI update
    _conversations.removeWhere((c) => c.id == conversationId);
    _lastMessages.remove(conversationId);

    if (_activeConversationId == conversationId) {
      _activeConversationId = null;
      _messages = [];
    }

    notifyListeners();
    _socketService.deleteConversation(conversationId);
  }

  void sendFriendRequest(String recipientEmail) {
    _socketService.sendFriendRequest(recipientEmail);
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

  void disconnect() {
    debugPrint('[ChatProvider] Disconnecting WebSocket');
    _intentionalDisconnect = true;
    _tokenForReconnect = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
    _socketService.disconnect();
    _conversations = [];
    _messages = [];
    _activeConversationId = null;
    _currentUserId = null;
    _lastMessages.clear();
    _pendingOpenConversationId = null;
    _friendRequests = [];
    _pendingRequestsCount = 0;
    _friends = [];
    _friendRequestJustSent = false;
    notifyListeners();
  }

  void _onDisconnect() {
    if (_intentionalDisconnect || _tokenForReconnect == null || _currentUserId == null) {
      return;
    }
    if (_reconnectAttempts >= AppConstants.reconnectMaxAttempts) {
      debugPrint('[ChatProvider] Reconnect max attempts reached');
      _errorMessage = 'Connection lost. Please refresh the page.';
      notifyListeners();
      return;
    }
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectAttempts++;
    final delay = _reconnectDelay;
    debugPrint('[ChatProvider] Scheduling reconnect attempt $_reconnectAttempts in ${delay.inSeconds}s');
    _reconnectTimer = Timer(delay, () {
      if (_intentionalDisconnect || _tokenForReconnect == null || _currentUserId == null) {
        return;
      }
      debugPrint('[ChatProvider] Reconnecting WebSocket...');
      connect(token: _tokenForReconnect!, userId: _currentUserId!);
    });
  }

  Duration get _reconnectDelay {
    final exponential = AppConstants.reconnectInitialDelay.inMilliseconds * (1 << (_reconnectAttempts - 1));
    final capped = exponential.clamp(0, AppConstants.reconnectMaxDelay.inMilliseconds);
    return Duration(milliseconds: capped);
  }
}
