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
  }) {
    _socket = io.io(
      baseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .setQuery({'token': token})
          .disableAutoConnect()
          .build(),
    );

    _socket!.onConnect((_) => onConnect());
    _socket!.on('conversationsList', onConversationsList);
    _socket!.on('messageHistory', onMessageHistory);
    _socket!.on('messageSent', onMessageSent);
    _socket!.on('newMessage', onNewMessage);
    _socket!.on('openConversation', onOpenConversation);
    _socket!.on('error', onError);
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

  void getMessages(int conversationId) {
    _socket?.emit('getMessages', {
      'conversationId': conversationId,
    });
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }
}
