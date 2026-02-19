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
    required void Function(dynamic) onBlockedList,
    required void Function(dynamic) onYouWereBlocked,
    required void Function(dynamic) onMessageDelivered,
    required void Function(dynamic) onPingReceived,
    required void Function(dynamic) onPingSent,
    required void Function(dynamic) onChatHistoryCleared,
    required void Function(dynamic) onMessageDeleted,
    required void Function(dynamic) onDisappearingTimerUpdated,
    required void Function(dynamic) onConversationDeleted,
    required void Function(dynamic) onSearchUsersResult,
    void Function(dynamic)? onPartnerTyping,
    void Function(dynamic)? onPartnerRecordingVoice,
    void Function(dynamic)? onReactionUpdated,
    void Function(dynamic)? onLinkPreviewReady,
  }) {
    // Defensive cleanup: ensure any previous socket is fully disposed
    // before creating a new one (prevents cache reuse)
    if (_socket != null) {
      _socket!.disconnect();
      _socket!.dispose();
      _socket = null;
    }

    // Token in auth only (not query) — avoids URL/log/Referer leakage
    _socket = io.io(
      baseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
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
    _socket!.on('blockedList', onBlockedList);
    _socket!.on('youWereBlocked', onYouWereBlocked);
    _socket!.on('messageDelivered', onMessageDelivered);
    _socket!.on('newPing', onPingReceived);
    _socket!.on('pingSent', onPingSent);
    _socket!.on('chatHistoryCleared', onChatHistoryCleared);
    _socket!.on('messageDeleted', onMessageDeleted);
    _socket!.on('disappearingTimerUpdated', onDisappearingTimerUpdated);
    _socket!.on('conversationDeleted', onConversationDeleted);
    _socket!.on('searchUsersResult', onSearchUsersResult);
    if (onPartnerTyping != null) {
      _socket!.on('partnerTyping', onPartnerTyping);
    }
    if (onPartnerRecordingVoice != null) {
      _socket!.on('partnerRecordingVoice', onPartnerRecordingVoice);
    }
    if (onReactionUpdated != null) {
      _socket!.on('reactionUpdated', onReactionUpdated);
    }
    if (onLinkPreviewReady != null) {
      _socket!.on('linkPreviewReady', onLinkPreviewReady);
    }
    _socket!.onDisconnect(onDisconnect);

    _socket!.connect();
  }

  void getConversations() {
    _socket?.emit('getConversations');
  }

  void sendMessage(
    int recipientId,
    String content, {
    String? messageType,
    String? mediaUrl,
    int? mediaDuration,
    int? expiresIn,
    String? tempId,
    int? replyToMessageId,
  }) {
    final payload = <String, dynamic>{
      'recipientId': recipientId,
      'content': content,
    };
    if (messageType != null) {
      payload['messageType'] = messageType;
    }
    if (mediaUrl != null) {
      payload['mediaUrl'] = mediaUrl;
    }
    if (mediaDuration != null) {
      payload['mediaDuration'] = mediaDuration;
    }
    if (expiresIn != null) {
      payload['expiresIn'] = expiresIn;
    }
    if (tempId != null) {
      payload['tempId'] = tempId;
    }
    if (replyToMessageId != null) {
      payload['replyToMessageId'] = replyToMessageId;
    }
    _socket?.emit('sendMessage', payload);
  }

  void sendPing(int recipientId) {
    _socket?.emit('sendPing', {
      'recipientId': recipientId,
    });
  }

  void emitMessageDelivered(int messageId) {
    _socket?.emit('messageDelivered', {
      'messageId': messageId,
    });
  }

  void emitClearChatHistory(int conversationId) {
    if (_socket == null) return;
    _socket!.emit('clearChatHistory', {'conversationId': conversationId});
  }

  void emitDeleteMessage(int messageId, {required bool forEveryone}) {
    if (_socket == null) return;
    _socket!.emit('deleteMessage', {
      'messageId': messageId,
      'mode': forEveryone ? 'for_everyone' : 'for_me',
    });
  }

  void emitDeleteConversationOnly(int conversationId) {
    _socket?.emit('deleteConversationOnly', {
      'conversationId': conversationId,
    });
  }

  void emitSetDisappearingTimer(int conversationId, int? seconds) {
    if (_socket == null) return;
    _socket!.emit('setDisappearingTimer', {
      'conversationId': conversationId,
      'seconds': seconds,
    });
  }

  void emitTyping(int recipientId, int conversationId) {
    _socket?.emit('typing', {
      'recipientId': recipientId,
      'conversationId': conversationId,
    });
  }

  void emitRecordingVoice(int recipientId, int conversationId, bool isRecording) {
    _socket?.emit('recordingVoice', {
      'recipientId': recipientId,
      'conversationId': conversationId,
      'isRecording': isRecording,
    });
  }

  void emitMarkConversationRead(int conversationId) {
    _socket?.emit('markConversationRead', {
      'conversationId': conversationId,
    });
  }

  void emitAddReaction(int messageId, String emoji) {
    _socket?.emit('addReaction', {'messageId': messageId, 'emoji': emoji});
  }

  void emitRemoveReaction(int messageId, String emoji) {
    _socket?.emit('removeReaction', {'messageId': messageId, 'emoji': emoji});
  }

  void searchUsers(String handle) {
    _socket?.emit('searchUsers', {'handle': handle});
  }

  void startConversation(int recipientId) {
    _socket?.emit('startConversation', {
      'recipientId': recipientId,
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

  void sendFriendRequest(int recipientId) {
    _socket?.emit('sendFriendRequest', {
      'recipientId': recipientId,
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

  void emitBlockUser(int userId) {
    _socket?.emit('blockUser', {'userId': userId});
  }

  void emitUnblockUser(int userId) {
    _socket?.emit('unblockUser', {'userId': userId});
  }

  void getBlockedList() {
    _socket?.emit('getBlockedList');
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }
}
