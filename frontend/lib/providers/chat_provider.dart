import 'package:flutter/foundation.dart';
import '../models/conversation_model.dart';
import '../models/message_model.dart';
import '../models/friend_request_model.dart';
import '../models/user_model.dart';
import '../services/socket_service.dart';
import '../config/app_config.dart';

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

  void clearError() {
    _errorMessage = null;
    notifyListeners();
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

    _currentUserId = userId;
    _socketService.connect(
      baseUrl: AppConfig.baseUrl,
      token: token,
      onConnect: () {
        _socketService.getConversations();
        _socketService.getFriendRequests();
        _socketService.getFriends();
        Future.delayed(const Duration(milliseconds: 500), () {
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
        _messages = list
            .map((m) => MessageModel.fromJson(m as Map<String, dynamic>))
            .toList();
        notifyListeners();
      },
      onMessageSent: (data) {
        final msg =
            MessageModel.fromJson(data as Map<String, dynamic>);
        _lastMessages[msg.conversationId] = msg;
        if (msg.conversationId == _activeConversationId) {
          _messages.add(msg);
        }
        notifyListeners();
      },
      onNewMessage: (data) {
        final msg =
            MessageModel.fromJson(data as Map<String, dynamic>);
        _lastMessages[msg.conversationId] = msg;
        if (msg.conversationId == _activeConversationId) {
          _messages.add(msg);
        }
        notifyListeners();
      },
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
      onUserStatusChanged: (data) {
        final userId = (data as Map<String, dynamic>)['userId'] as int;
        final activeStatus = data['activeStatus'] as bool;
        _friends = _friends.map((f) {
          if (f.id == userId) {
            return f.copyWith(activeStatus: activeStatus);
          }
          return f;
        }).toList();
        _conversations = _conversations.map((c) {
          if (c.userOne.id == userId) {
            return ConversationModel(
              id: c.id,
              userOne: c.userOne.copyWith(activeStatus: activeStatus),
              userTwo: c.userTwo,
              createdAt: c.createdAt,
            );
          }
          if (c.userTwo.id == userId) {
            return ConversationModel(
              id: c.id,
              userOne: c.userOne,
              userTwo: c.userTwo.copyWith(activeStatus: activeStatus),
              createdAt: c.createdAt,
            );
          }
          return c;
        }).toList();
        notifyListeners();
      },
      onDisconnect: (_) {},
    );
  }

  void openConversation(int conversationId, {int limit = 50}) {
    _activeConversationId = conversationId;
    _messages = [];
    _socketService.getMessages(conversationId, limit: limit);
    notifyListeners();
  }

  // Load more messages for the active conversation
  // Fetches messages with increased limit (current + additional)
  void loadMoreMessages({int additionalLimit = 50}) {
    if (_activeConversationId == null) return;
    final newLimit = _messages.length + additionalLimit;
    _socketService.getMessages(_activeConversationId!, limit: newLimit);
  }

  void clearActiveConversation() {
    _activeConversationId = null;
    _messages = [];
    notifyListeners();
  }

  void sendMessage(String content) {
    if (_activeConversationId == null || _currentUserId == null) return;

    final conv = _conversations.firstWhere(
      (c) => c.id == _activeConversationId,
    );

    final recipientId = conv.userOne.id == _currentUserId
        ? conv.userTwo.id
        : conv.userOne.id;

    _socketService.sendMessage(recipientId, content);
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
}
