import 'package:socket_io_client/socket_io_client.dart' as io;

class SocketService {
  io.Socket? _socket;

  io.Socket? get socket => _socket;

  void connect({
    required String baseUrl,
    required String token,
    required void Function() onConnect,
    required void Function(dynamic) onConversationsList,
    required void Function(dynamic) onMessageHistory,
    required void Function(dynamic) onMessageSent,
    required void Function(dynamic) onNewMessage,
    required void Function(dynamic) onOpenConversation,
    required void Function(dynamic) onError,
    required void Function(dynamic) onDisconnect,
    required void Function(dynamic) onFriendRequestsList,
    required void Function(dynamic) onNewFriendRequest,
    required void Function(dynamic) onFriendRequestSent,
    required void Function(dynamic) onFriendRequestAccepted,
    required void Function(dynamic) onFriendRequestRejected,
    required void Function(dynamic) onPendingRequestsCount,
    required void Function(dynamic) onFriendsList,
    required void Function(dynamic) onUnfriended,
  }) {
    // Defensive cleanup: ensure any previous socket is fully disposed
    // before creating a new one (prevents cache reuse)
    if (_socket != null) {
      _socket!.disconnect();
      _socket!.dispose();
      _socket = null;
    }

    _socket = io.io(
      baseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .setQuery({'token': token})
          .disableAutoConnect()
          .enableForceNew()
          .build(),
    );

    _socket!.onConnect((_) => onConnect());
    _socket!.on('conversationsList', onConversationsList);
    _socket!.on('messageHistory', onMessageHistory);
    _socket!.on('messageSent', onMessageSent);
    _socket!.on('newMessage', onNewMessage);
    _socket!.on('openConversation', onOpenConversation);
    _socket!.on('error', onError);
    _socket!.on('friendRequestsList', onFriendRequestsList);
    _socket!.on('newFriendRequest', onNewFriendRequest);
    _socket!.on('friendRequestSent', onFriendRequestSent);
    _socket!.on('friendRequestAccepted', onFriendRequestAccepted);
    _socket!.on('friendRequestRejected', onFriendRequestRejected);
    _socket!.on('pendingRequestsCount', onPendingRequestsCount);
    _socket!.on('friendsList', onFriendsList);
    _socket!.on('unfriended', onUnfriended);
    _socket!.onDisconnect(onDisconnect);

    _socket!.connect();
  }

  void getConversations() {
    _socket?.emit('getConversations');
  }

  void sendMessage(int recipientId, String content) {
    _socket?.emit('sendMessage', {
      'recipientId': recipientId,
      'content': content,
    });
  }

  void startConversation(String recipientEmail) {
    _socket?.emit('startConversation', {
      'recipientEmail': recipientEmail,
    });
  }

  void getMessages(int conversationId, {int? limit, int? offset}) {
    final payload = <String, dynamic>{
      'conversationId': conversationId,
    };
    if (limit != null) payload['limit'] = limit;
    if (offset != null) payload['offset'] = offset;
    _socket?.emit('getMessages', payload);
  }

  void deleteConversation(int conversationId) {
    _socket?.emit('deleteConversation', {
      'conversationId': conversationId,
    });
  }

  void sendFriendRequest(String recipientEmail) {
    _socket?.emit('sendFriendRequest', {
      'recipientEmail': recipientEmail,
    });
  }

  void acceptFriendRequest(int requestId) {
    _socket?.emit('acceptFriendRequest', {
      'requestId': requestId,
    });
  }

  void rejectFriendRequest(int requestId) {
    _socket?.emit('rejectFriendRequest', {
      'requestId': requestId,
    });
  }

  void getFriendRequests() {
    _socket?.emit('getFriendRequests');
  }

  void getFriends() {
    _socket?.emit('getFriends');
  }

  void unfriend(int userId) {
    _socket?.emit('unfriend', {
      'userId': userId,
    });
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }
}
