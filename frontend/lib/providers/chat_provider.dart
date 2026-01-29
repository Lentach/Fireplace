import 'package:flutter/foundation.dart';
import '../models/conversation_model.dart';
import '../models/message_model.dart';
import '../services/socket_service.dart';
import '../config/app_config.dart';

class ChatProvider extends ChangeNotifier {
  final SocketService _socketService = SocketService();

  List<ConversationModel> _conversations = [];
  List<MessageModel> _messages = [];
  int? _activeConversationId;
  int? _currentUserId;
  String? _errorMessage;

  List<ConversationModel> get conversations => _conversations;
  List<MessageModel> get messages => _messages;
  int? get activeConversationId => _activeConversationId;
  String? get errorMessage => _errorMessage;

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void connect({required String token, required int userId}) {
    _currentUserId = userId;
    _socketService.connect(
      baseUrl: AppConfig.baseUrl,
      token: token,
      onConnect: () {
        _socketService.getConversations();
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
        if (msg.conversationId == _activeConversationId) {
          _messages.add(msg);
        }
        _socketService.getConversations();
        notifyListeners();
      },
      onNewMessage: (data) {
        final msg =
            MessageModel.fromJson(data as Map<String, dynamic>);
        if (msg.conversationId == _activeConversationId) {
          _messages.add(msg);
        }
        _socketService.getConversations();
        notifyListeners();
      },
      onOpenConversation: (data) {
        final convId = (data as Map<String, dynamic>)['conversationId'] as int;
        openConversation(convId);
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

  void disconnect() {
    _socketService.disconnect();
    _conversations = [];
    _messages = [];
    _activeConversationId = null;
    _currentUserId = null;
    notifyListeners();
  }
}
