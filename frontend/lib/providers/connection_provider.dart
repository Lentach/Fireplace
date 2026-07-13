import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../constants/app_constants.dart';
import '../services/api_service.dart';
import '../services/push_service.dart';
import '../services/socket_service.dart';
import '../utils/e2e_diag_log.dart';
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

  final SocketService _socketService;

  ConnectionProvider({
    SocketService? socketService,
    int? coldStartConversationId,
  })  : _socketService = socketService ?? SocketService(),
        _coldStartConversationId = coldStartConversationId;
  final ChatReconnectManager _reconnectManager = ChatReconnectManager();
  late final ApiService _api = ApiService(baseUrl: AppConfig.baseUrl);
  late final PushService _pushService = PushService(_api);
  bool _pushInitialized = false;
  int? _coldStartConversationId;
  DateTime? _lastConnectStartedAt;
  Timer? _debouncedConnectTimer;

  /// Bumped on every conversationsList/messageHistory response — liveness
  /// signal for the resume probe (zombie-socket detection, see
  /// [ensureReconnectIfNeeded]).
  int _serverResponseCounter = 0;
  Timer? _resumeProbeTimer;

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
    final now = DateTime.now();
    if (_lastConnectStartedAt != null) {
      final since = now.difference(_lastConnectStartedAt!);
      if (since < AppConstants.reconnectConnectCooldown) {
        final wait = AppConstants.reconnectConnectCooldown - since;
        _debouncedConnectTimer?.cancel();
        _debouncedConnectTimer = Timer(wait, () {
          connect(userId, token, baseUrl);
        });
        return;
      }
    }
    _debouncedConnectTimer?.cancel();
    _lastConnectStartedAt = now;

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
    _encryptionProvider?.onE2EReady =
        () => _messagingProvider?.retryDecryptActiveConversation();

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
    // 7. Replace socket (enableForceNew). Suppress reconnect from the old socket's
    // disconnect event — otherwise WiFi/cellular handoff + connect() races schedule
    // extra connect() calls that can clear lists (non-reconnect) or use a stale JWT.
    _intentionalDisconnect = true;
    _socketService.disconnect();
    _socketService.connect(baseUrl: baseUrl, token: token);

    // 8. Register socket event listeners (routed to sub-providers)
    _registerEventListeners();

    // 9. Transport connect + socketReady (authenticated fetches only on ready)
    _socketService.onConnect(() => _onSocketTransportConnect(userId, token));
    _socketService.on('socketReady', (_) => _onSocketReady());

    // 10. On 'disconnect': handle reconnect
    _socketService.onDisconnect((_) {
      E2eDiagLog.add('SOCKET_DISCONNECT', {'intentional': _intentionalDisconnect});
      _isConnected = false;
      notifyListeners();

      if (!_intentionalDisconnect) {
        _reconnectManager.onDisconnect(
          _scheduleReconnect,
          (msg) {
            _errorMessage = msg;
            notifyListeners();
          },
        );
      }
    });
  }

  void _scheduleReconnect() {
    final userId = _currentUserId;
    final token = _reconnectManager.tokenForReconnect;
    if (userId == null || token == null) return;
    connect(userId, token, AppConfig.baseUrl);
  }

  void _onSocketTransportConnect(int userId, String token) {
    E2eDiagLog.add('SOCKET_CONNECT', {'userId': userId});
    _intentionalDisconnect = false;
    _isConnected = true;
    notifyListeners();

    _encryptionProvider?.initializeE2E(userId);

    if (!_pushInitialized) {
      _pushInitialized = true;
      void onNavigateToConversation(int conversationId) {
        _conversationsProvider?.requestNavigateToConversationFromNotification(
          conversationId,
        );
      }

      _pushService
          .initialize(
            token,
            onNavigateToConversation: onNavigateToConversation,
          )
          .catchError((_) {});

      // Seed cold-start id from URL param (set once; subsequent reconnects skip it).
      _pushService.coldStartConversationId ??= _coldStartConversationId;
      _coldStartConversationId = null;

      // Drain cold-start notification deep-link (web: URL param; Android: handled by FCM path)
      final coldConvId = _pushService.coldStartConversationId;
      if (coldConvId != null) {
        _pushService.coldStartConversationId = null;
        onNavigateToConversation(coldConvId);
      }
    }
  }

  /// After JWT auth completes on the server (`socketReady` event).
  void _onSocketReady() {
    final activeConvId = _conversationsProvider?.activeConversationId;
    E2eDiagLog.add('SOCKET_READY', {
      'activeConvId': activeConvId ?? -1,
      'socketConnected': _socketService.isConnected,
    });
    _reconnectManager.resetAttempts();
    _socketService.getConversations();
    _socketService.getFriendRequests();
    _socketService.getFriends();
    _socketService.getBlockedList();

    if (activeConvId != null) {
      _conversationsProvider?.reemitPushClientState();
      E2eDiagLog.add('ACTIVE_REASSERT', {
        'source': 'socketReady',
        'activeConvId': activeConvId,
        'socketConnected': _socketService.isConnected,
      });
      _socketService.getMessages(activeConvId,
          limit: AppConstants.messagePageSize);
    }

    Future.delayed(AppConstants.conversationsRefreshDelay, () {
      if (_conversationsProvider?.conversations.isEmpty == true) {
        _socketService.getConversations();
      }
      if (_friendsProvider?.friends.isEmpty == true) {
        _socketService.getFriends();
      }
    });

    // Morning PWA resume: messageHistory may finish before or after E2E init;
    // re-run ordered decrypt for the open chat once the socket is authenticated.
    Future.delayed(const Duration(milliseconds: 900), () {
      _messagingProvider?.retryDecryptActiveConversation();
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
    _debouncedConnectTimer?.cancel();
    _resumeProbeTimer?.cancel();
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
  /// Test-only: seed identity so [ensureReconnectIfNeeded]'s guards pass
  /// without a full connect() (which arms the real connect cooldown).
  @visibleForTesting
  void setIdentityForTest(int userId, String token) {
    _currentUserId = userId;
    _reconnectManager.tokenForReconnect = token;
  }

  void ensureReconnectIfNeeded() {
    final claimsConnected = _socketService.isConnected;
    E2eDiagLog.add('RESUME_CHECK', {'socketConnected': claimsConnected});
    if (_currentUserId == null || _reconnectManager.tokenForReconnect == null) {
      return;
    }
    if (!claimsConnected) {
      connect(_currentUserId!, _reconnectManager.tokenForReconnect!,
          AppConfig.baseUrl);
      return;
    }
    // Socket CLAIMS connected, but iOS suspends the transport in background
    // and socket.io only notices on ping timeout (zombie socket) — the resume
    // used to do nothing, leaving pushed messages invisible until a full
    // relaunch. Re-sync now and arm a liveness probe: if no server response
    // lands within the window, force a fresh connect (cheap; reconnect
    // preserves state by design).
    _resyncAfterResume();
  }

  static const _kResumeProbeWindow = Duration(seconds: 6);

  void _resyncAfterResume() {
    final probeStart = _serverResponseCounter;
    final activeConvId = _conversationsProvider?.activeConversationId;
    _socketService.getConversations();
    if (activeConvId != null) {
      _conversationsProvider?.reemitPushClientState();
      _socketService.getMessages(activeConvId,
          limit: AppConstants.messagePageSize);
    }
    E2eDiagLog.add('RESUME_RESYNC', {
      'activeConvId': activeConvId ?? -1,
      'socketConnected': _socketService.isConnected,
    });

    _resumeProbeTimer?.cancel();
    _resumeProbeTimer = Timer(_kResumeProbeWindow, () {
      if (_serverResponseCounter != probeStart) return; // server replied: alive
      E2eDiagLog.add('RESUME_PROBE_TIMEOUT', {'forcedReconnect': true});
      final userId = _currentUserId;
      final token = _reconnectManager.tokenForReconnect;
      if (userId == null || token == null) return;
      connect(userId, token, AppConfig.baseUrl);
    });
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
      _serverResponseCounter++;
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
    _socketService.on('conversationMuteUpdated', (data) {
      _conversationsProvider?.onConversationMuteUpdated(data);
    });
    _socketService.on('messagePinned', (data) {
      final m = data as Map<String, dynamic>;
      final pinnedId = m['pinnedMessageId'] as int?;
      final local = pinnedId != null
          ? _messagingProvider?.messageById(pinnedId)
          : null;
      _conversationsProvider?.onMessagePinned(data, localPinnedMessage: local);
    });
    _socketService.on('messageUnpinned', (data) {
      _conversationsProvider?.onMessageUnpinned(data);
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
      _serverResponseCounter++;
      _messagingProvider?.onMessageHistory(data);
    });
    _socketService.on('messageDelivered', (data) {
      _messagingProvider?.onMessageDelivered(data);
    });
    _socketService.on('messageDeleted', (data) {
      _messagingProvider?.onMessageDeleted(data);
    });
    _socketService.on('messageEdited', (data) {
      _messagingProvider?.onMessageEdited(data);
    });
    _socketService.on('editMessageFailed', (data) {
      _messagingProvider?.onEditMessageFailed(data);
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
    _debouncedConnectTimer?.cancel();
    _reconnectManager.cancel();
    _socketService.disconnect();
    super.dispose();
  }
}
