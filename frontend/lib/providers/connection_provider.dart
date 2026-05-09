import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../constants/app_constants.dart';
import '../services/api_service.dart';
import '../services/push_service.dart';
import '../services/socket_service.dart';
import 'chat_reconnect_manager.dart';
import 'conversations_provider.dart';
import 'encryption_provider.dart';
import 'friends_provider.dart';
import 'messaging_provider.dart';

/// ConnectionProvider — owns socket lifecycle, reconnection, and coordinates
/// all sub-providers. This is the central coordinator replacing the socket
/// management portion previously in the monolithic chat provider.
class ConnectionProvider extends ChangeNotifier {
  // ---------- Core State ----------

  final SocketService _socketService = SocketService();
  final ChatReconnectManager _reconnectManager = ChatReconnectManager();
  late final ApiService _api = ApiService(baseUrl: AppConfig.baseUrl);
  late final PushService _pushService = PushService(_api);
  bool _pushInitialized = false;

  int? _currentUserId;
  bool _isConnected = false;
  bool _intentionalDisconnect = false;
  String? _errorMessage;

  // ---------- Sub-Provider References ----------

  EncryptionProvider? _encryptionProvider;
  FriendsProvider? _friendsProvider;
  ConversationsProvider? _conversationsProvider;
  MessagingProvider? _messagingProvider;

  // ---------- Public Getters ----------

  int? get currentUserId => _currentUserId;
  bool get isConnected => _isConnected;
  SocketService get socketService => _socketService;
  String? get errorMessage => _errorMessage;

  // ---------- Provider Wiring ----------

  /// Wire all sub-provider references. Called once before connect().
  void setProviders({
    required EncryptionProvider encryption,
    required FriendsProvider friends,
    required ConversationsProvider conversations,
    required MessagingProvider messaging,
  }) {
    _encryptionProvider = encryption;
    _friendsProvider = friends;
    _conversationsProvider = conversations;
    _messagingProvider = messaging;
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
    _reconnectManager.tokenForReconnect = token;

    // 2. Determine if this is a reconnect (same user)
    final bool isReconnect = (_currentUserId == userId);

    _currentUserId = userId;

    // 3. If not reconnect, clear all sub-provider state
    if (!isReconnect) {
      _encryptionProvider?.clearAll();
      _friendsProvider?.clearAll();
      _conversationsProvider?.clearAll();
      _messagingProvider?.clearAll();
    }

    // 4. Notify sub-providers of connect lifecycle
    _encryptionProvider?.onConnect(isReconnect);
    _friendsProvider?.onConnect(isReconnect);
    _friendsProvider?.setCurrentUserId(userId);
    _conversationsProvider?.onConnect(isReconnect);
    _conversationsProvider?.setCurrentUserId(userId);
    _messagingProvider?.onConnect(isReconnect);
    _messagingProvider?.setCurrentUserId(userId);
    _messagingProvider?.setToken(token);

    // 5. Set up emit callbacks so sub-providers can send socket events
    _encryptionProvider?.setEmitCallback((event, data) => emit(event, data));
    _friendsProvider?.setEmitCallback((event, data) => emit(event, data));
    _conversationsProvider?.setEmitCallback((event, data) => emit(event, data));
    _messagingProvider?.setEmitCallback((event, data) => emit(event, data));

    // 6. Wire cross-provider callbacks (friends -> conversations)
    _friendsProvider?.onRemoveConversationsForUser = (uid) {
      if (uid == -1) {
        final blockedIds =
            _friendsProvider!.blockedUsers.map((u) => u.id).toSet();
        _conversationsProvider?.removeConversationsForUser(-1,
            blockedIds: blockedIds);
      } else {
        _conversationsProvider?.removeConversationsForUser(uid);
      }
    };
    // 7. Dispose old socket, create new with enableForceNew (avoids cached JWT)
    _socketService.disconnect();
    _socketService.connect(baseUrl: baseUrl, token: token);

    // 8. Register socket event listeners (routed to sub-providers)
    _registerEventListeners();

    // 9. On 'connect': fetch initial data, init E2E, push
    _socketService.onConnect(() {
      _isConnected = true;
      _reconnectManager.resetAttempts();
      notifyListeners();

      // Fetch initial data
      _socketService.getConversations();
      _socketService.getFriendRequests();
      _socketService.getFriends();
      _socketService.getBlockedList();

      // Re-fetch messages for active conversation on reconnect (preserves open chat)
      final activeConvId = _conversationsProvider?.activeConversationId;
      if (activeConvId != null) {
        _socketService.getMessages(activeConvId,
            limit: AppConstants.messagePageSize);
      }

      // Delayed re-fetch if conversations empty (handles slow first response)
      Future.delayed(AppConstants.conversationsRefreshDelay, () {
        if (_conversationsProvider?.conversations.isEmpty == true) {
          _socketService.getConversations();
        }
      });

      // Initialize E2E encryption (skips if already initialized on reconnect)
      _encryptionProvider?.initializeE2E(userId);

      // Initialize push notifications once per session
      if (!_pushInitialized) {
        _pushInitialized = true;
        _pushService
            .initialize(
              token,
              onAndroidNavigateToConversation: (conversationId) {
                _conversationsProvider?.requestNavigateToConversationFromNotification(
                  conversationId,
                );
              },
            )
            .catchError((_) {});
      }
    });

    // 10. On 'disconnect': handle reconnect
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

  /// Updates reconnect + messaging token after AuthProvider refreshes JWT (no socket reconnect).
  void applyRefreshedAccessToken(String newAccessToken) {
    _reconnectManager.tokenForReconnect = newAccessToken;
    _messagingProvider?.setToken(newAccessToken);
  }

  // ---------- Disconnect ----------

  void disconnect({bool isLogout = false}) {
    _intentionalDisconnect = true;
    _reconnectManager.cancel();

    // Notify sub-providers
    _encryptionProvider?.onDisconnect();
    _friendsProvider?.onDisconnect();
    _conversationsProvider?.onDisconnect();
    _messagingProvider?.onDisconnect();

    // Socket cleanup
    _socketService.disconnect();
    _isConnected = false;
    _errorMessage = null;

    if (isLogout) {
      _pushInitialized = false;
      _currentUserId = null;
      _reconnectManager.tokenForReconnect = null;
      _encryptionProvider?.clearAll();
      _friendsProvider?.clearAll();
      _conversationsProvider?.clearAll();
      _messagingProvider?.clearAll();
    }

    notifyListeners();
  }

  /// Ensure reconnected if needed (e.g. app resume from background).
  void ensureReconnectIfNeeded() {
    if (_socketService.isConnected) return;
    if (_currentUserId == null || _reconnectManager.tokenForReconnect == null) {
      return;
    }
    connect(_currentUserId!, _reconnectManager.tokenForReconnect!,
        AppConfig.baseUrl);
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

    // --- Conversation events ---
    _socketService.on('conversationsList', (data) {
      _conversationsProvider?.onConversationsList(data);
    });
    _socketService.on('openConversation', (data) {
      _conversationsProvider?.onOpenConversation(data);
    });
    _socketService.on('conversationDeleted', (data) {
      _conversationsProvider?.onConversationDeleted(data);
      // Also clear messages from MessagingProvider
      final convId = (data as Map<String, dynamic>)['conversationId'] as int;
      _messagingProvider?.onConversationDeleted(convId);
    });
    _socketService.on('disappearingTimerUpdated', (data) {
      _conversationsProvider?.onDisappearingTimerUpdated(data);
    });
    _socketService.on('chatHistoryCleared', (data) {
      _messagingProvider?.onChatHistoryCleared(data);
    });

    // --- Message events ---
    _socketService.on('newMessage', (data) {
      _messagingProvider?.onNewMessage(data);
    });
    _socketService.on('messageSent', (data) {
      _messagingProvider?.onMessageSent(data);
    });
    _socketService.on('messageHistory', (data) {
      _messagingProvider?.onMessageHistory(data);
    });
    _socketService.on('messageDelivered', (data) {
      _messagingProvider?.onMessageDelivered(data);
    });
    _socketService.on('messageDeleted', (data) {
      _messagingProvider?.onMessageDeleted(data);
    });
    _socketService.on('reactionUpdated', (data) {
      _messagingProvider?.onReactionUpdated(data);
    });
    _socketService.on('linkPreviewReady', (data) {
      _messagingProvider?.onLinkPreviewReady(data);
    });
    _socketService.on('partnerTyping', (data) {
      _messagingProvider?.onPartnerTyping(data);
    });
    _socketService.on('partnerRecordingVoice', (data) {
      _messagingProvider?.onPartnerRecordingVoice(data);
    });

    // --- Error event ---
    _socketService.on('error', (err) {
      final String msg = err is Map<String, dynamic> && err['message'] != null
          ? err['message'] as String
          : err.toString();
      _errorMessage = msg;
      _messagingProvider?.markSendingMessagesFailed(msg);
      notifyListeners();
    });
  }

  // ---------- Dispose ----------

  @override
  void dispose() {
    _reconnectManager.cancel();
    _socketService.disconnect();
    super.dispose();
  }
}
