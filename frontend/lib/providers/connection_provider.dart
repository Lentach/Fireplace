import 'package:flutter/foundation.dart';

import '../services/socket_service.dart';
import 'chat_reconnect_manager.dart';
import 'encryption_provider.dart';
import 'friends_provider.dart';

/// ConnectionProvider — owns socket lifecycle, reconnection, and coordinates
/// sub-providers. This is the central coordinator that replaces the socket
/// management portion of ChatProvider.
///
/// Sub-providers (EncryptionProvider, FriendsProvider, and future
/// ConversationsProvider / MessagingProvider) are wired via [setProviders].
class ConnectionProvider extends ChangeNotifier {
  // ---------- Core State ----------

  final SocketService _socketService = SocketService();
  final ChatReconnectManager _reconnectManager = ChatReconnectManager();

  int? _currentUserId;
  bool _isConnected = false;
  bool _intentionalDisconnect = false;

  // ---------- Sub-Provider References ----------

  EncryptionProvider? _encryptionProvider;
  FriendsProvider? _friendsProvider;
  // ConversationsProvider? _conversationsProvider; // Added when it exists
  // MessagingProvider? _messagingProvider;          // Added when it exists

  // ---------- Public Getters ----------

  int? get currentUserId => _currentUserId;
  bool get isConnected => _isConnected;
  SocketService get socketService => _socketService;

  // ---------- Provider Wiring ----------

  /// Wire sub-provider references. Called once during app initialization.
  void setProviders({
    required EncryptionProvider encryption,
    required FriendsProvider friends,
    // ConversationsProvider and MessagingProvider added when they exist
  }) {
    _encryptionProvider = encryption;
    _friendsProvider = friends;
  }

  // ---------- Emit ----------

  /// Emit a socket event. Used by sub-providers via their emit callbacks.
  void emit(String event, dynamic data) {
    _socketService.socket?.emit(event, data);
  }

  // ---------- Connect ----------

  Future<void> connect(int userId, String token, String baseUrl) async {
    // 1. Cancel any pending reconnect timer
    _reconnectManager.cancel();
    _intentionalDisconnect = false;

    // 2. Determine if this is a reconnect (same user)
    final bool isReconnect = (_currentUserId == userId);

    // 3. If not reconnect, clear all sub-provider state
    if (!isReconnect) {
      _encryptionProvider?.clearAll();
      _friendsProvider?.clearAll();
      // _conversationsProvider?.clearAll();
      // _messagingProvider?.clearAll();
    }

    // 4. Notify sub-providers of connect
    _encryptionProvider?.onConnect(isReconnect);
    _friendsProvider?.onConnect(isReconnect);
    _friendsProvider?.setCurrentUserId(userId);

    // 5. Set up emit callbacks so sub-providers can send socket events
    _encryptionProvider?.setEmitCallback((event, data) => emit(event, data));
    _friendsProvider?.setEmitCallback((event, data) => emit(event, data));

    // 6. Dispose old socket, create new
    _reconnectManager.tokenForReconnect = token;
    _currentUserId = userId;

    _socketService.disconnect();
    _socketService.connect(baseUrl: baseUrl, token: token);

    // 7. Register socket event listeners (routed to sub-providers)
    _registerEventListeners();

    // 8. On 'connect': fetch initial data, init E2E
    _socketService.onConnect(() {
      _isConnected = true;
      _reconnectManager.resetAttempts();
      notifyListeners();

      _encryptionProvider?.initializeE2E(userId);
      _friendsProvider?.loadFriendRequests();
      _friendsProvider?.loadFriends();
      _friendsProvider?.loadBlockedList();
      // More initial fetches added when ConversationsProvider exists
    });

    // 9. On 'disconnect': handle reconnect
    _socketService.onDisconnect((_) {
      _isConnected = false;
      notifyListeners();

      if (!_intentionalDisconnect) {
        _reconnectManager.scheduleReconnect(
          () => connect(userId, token, baseUrl),
        );
      }
    });
  }

  // ---------- Disconnect ----------

  void disconnect({bool isLogout = false}) {
    _intentionalDisconnect = true;
    _reconnectManager.cancel();

    // Notify sub-providers
    _encryptionProvider?.onDisconnect();
    _friendsProvider?.onDisconnect();

    // Socket cleanup
    _socketService.disconnect();
    _isConnected = false;

    if (isLogout) {
      _currentUserId = null;
      _reconnectManager.tokenForReconnect = null;
      _encryptionProvider?.clearAll();
      _friendsProvider?.clearAll();
      // _conversationsProvider?.clearAll();
      // _messagingProvider?.clearAll();
    }

    notifyListeners();
  }

  // ---------- Event Routing ----------

  void _registerEventListeners() {
    // --- Encryption events ---
    _socketService.on('keyBundleUploaded', (data) {
      _encryptionProvider?.onKeyBundleUploaded(data);
    });
    _socketService.on('oneTimePreKeysUploaded', (data) {
      _encryptionProvider?.onOneTimePreKeysUploaded(data);
    });
    _socketService.on('preKeyBundleResponse', (data) {
      _encryptionProvider?.onPreKeyBundleResponse(data);
    });
    _socketService.on('preKeysLow', (data) {
      _encryptionProvider?.onPreKeysLow(data);
    });
    _socketService.on('sessionRebuildNeeded', (data) {
      _encryptionProvider?.onSessionRebuildNeeded(data);
    });

    // --- Friend events ---
    _socketService.on('friendRequestsList', (data) {
      _friendsProvider?.onFriendRequestsList(data);
    });
    _socketService.on('newFriendRequest', (data) {
      _friendsProvider?.onNewFriendRequest(data);
    });
    _socketService.on('friendRequestSent', (data) {
      _friendsProvider?.onFriendRequestSent(data);
    });
    _socketService.on('friendRequestAccepted', (data) {
      _friendsProvider?.onFriendRequestAccepted(data);
    });
    _socketService.on('friendRequestRejected', (data) {
      _friendsProvider?.onFriendRequestRejected(data);
    });
    _socketService.on('pendingRequestsCount', (data) {
      _friendsProvider?.onPendingRequestsCount(data);
    });
    _socketService.on('friendsList', (data) {
      _friendsProvider?.onFriendsList(data);
    });
    _socketService.on('searchUsersResult', (data) {
      _friendsProvider?.onSearchUsersResult(data);
    });
    _socketService.on('unfriended', (data) {
      _friendsProvider?.onUnfriended(data);
    });
    _socketService.on('blockedList', (data) {
      _friendsProvider?.onBlockedList(data);
    });
    _socketService.on('youWereBlocked', (data) {
      _friendsProvider?.onYouWereBlocked(data);
    });

    // --- Conversation events (placeholder for ConversationsProvider) ---
    // _socketService.on('conversationsList', (data) => _conversationsProvider?.onConversationsList(data));
    // _socketService.on('openConversation', (data) => _conversationsProvider?.onOpenConversation(data));
    // _socketService.on('conversationDeleted', (data) => _conversationsProvider?.onConversationDeleted(data));
    // _socketService.on('disappearingTimerUpdated', (data) => _conversationsProvider?.onDisappearingTimerUpdated(data));
    // _socketService.on('chatHistoryCleared', (data) => _conversationsProvider?.onChatHistoryCleared(data));

    // --- Message events (placeholder for MessagingProvider) ---
    // _socketService.on('newMessage', (data) => _messagingProvider?.onNewMessage(data));
    // _socketService.on('messageSent', (data) => _messagingProvider?.onMessageSent(data));
    // _socketService.on('messageHistory', (data) => _messagingProvider?.onMessageHistory(data));
    // _socketService.on('messageDelivered', (data) => _messagingProvider?.onMessageDelivered(data));
    // _socketService.on('messageDeleted', (data) => _messagingProvider?.onMessageDeleted(data));
    // _socketService.on('reactionUpdated', (data) => _messagingProvider?.onReactionUpdated(data));
    // _socketService.on('linkPreviewReady', (data) => _messagingProvider?.onLinkPreviewReady(data));
    // _socketService.on('partnerTyping', (data) => _messagingProvider?.onPartnerTyping(data));
    // _socketService.on('partnerRecordingVoice', (data) => _messagingProvider?.onPartnerRecordingVoice(data));
  }

  // ---------- Dispose ----------

  @override
  void dispose() {
    _reconnectManager.cancel();
    _socketService.disconnect();
    super.dispose();
  }
}
