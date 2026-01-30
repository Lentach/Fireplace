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

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  int? consumePendingOpen() {
    final id = _pendingOpenConversationId;
    _pendingOpenConversationId = null;
    return id;
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

  void connect({required String token, required int userId}) {
    _currentUserId = userId;
    _socketService.connect(
      baseUrl: AppConfig.baseUrl,
      token: token,
      onConnect: () {
        debugPrint('WebSocket connected, fetching conversations...');
        _socketService.getConversations();
        _socketService.getFriendRequests();
        _socketService.getFriends();
        Future.delayed(const Duration(milliseconds: 500), () {
          if (_conversations.isEmpty) {
            debugPrint('Retrying getConversations...');
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
        debugPrint('Socket error: $err');
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
        debugPrint('Friend request sent');
      },
      onFriendRequestAccepted: (data) {
        final request = FriendRequestModel.fromJson(data as Map<String, dynamic>);
        _friendRequests.removeWhere((r) => r.id == request.id);
        _socketService.getConversations();
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
        if (_activeConversationId != null) {
          final activeConv = _conversations.where((c) => c.id == _activeConversationId).firstOrNull;
          if (activeConv == null) {
            _activeConversationId = null;
            _messages = [];
          }
        }
        notifyListeners();
      },
      onDisconnect: (_) {
        debugPrint('Disconnected from WebSocket');
      },
    );
  }

  void openConversation(int conversationId) {
    _activeConversationId = conversationId;
    _messages = [];
    _socketService.getMessages(conversationId);
    notifyListeners();
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
    notifyListeners();
  }
}
