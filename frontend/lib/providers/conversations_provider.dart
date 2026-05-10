import 'package:flutter/foundation.dart';

import '../models/conversation_model.dart';
import '../models/message_model.dart';
import 'conversation_helpers.dart' as conv_helpers;
import '../models/user_model.dart';

/// ConversationsProvider — owns conversation list state, active conversation,
/// unread counts, and pending-open navigation pattern.
/// [ConnectionProvider] coordinates; this provider holds conversation list and active chat.
class ConversationsProvider extends ChangeNotifier {
  // ---------- State ----------
  List<ConversationModel> _conversations = [];
  int? _activeConversationId;
  final Map<int, int> _unreadCounts = {}; // conversationId -> count
  final Map<int, MessageModel> _lastMessages = {};
  int? _pendingOpenConversationId;
  /// Open this conversation from a notification tap (consumed by [MainShell], not socket flows).
  int? _pendingNotificationConversationId;

  /// True when our active conversation was removed from list (e.g. other user deleted).
  bool _activeConversationDeletedByOther = false;
  String? _errorMessage;

  /// App/window foreground — server skips push when this chat is already open.
  bool _clientVisible = true;

  int? _currentUserId;

  // ---------- Emit Callback ----------

  /// Callback to emit socket events. Set by [ConnectionProvider] via [setEmitCallback].
  void Function(String event, dynamic data)? _emit;

  /// Wire the socket emit callback so ConversationsProvider can send events
  /// without depending on SocketService directly.
  void setEmitCallback(void Function(String event, dynamic data) emit) {
    _emit = emit;
  }

  /// Called from [MainShell] lifecycle / tab visibility so backend can suppress redundant pushes.
  void setClientVisible(bool visible) {
    if (_clientVisible == visible) return;
    _clientVisible = visible;
    _emitPushClientState();
  }

  void _emitPushClientState() {
    _emit?.call('pushClientState', {
      'activeConversationId': _activeConversationId,
      'clientVisible': _clientVisible,
    });
  }

  // ---------- Public Getters ----------

  List<ConversationModel> get conversations => _conversations;

  /// Conversations sorted by newest message first (for list display).
  List<ConversationModel> get sortedConversations {
    final list = List<ConversationModel>.from(_conversations);
    list.sort((a, b) {
      final aTime = _lastMessages[a.id]?.createdAt ?? a.createdAt;
      final bTime = _lastMessages[b.id]?.createdAt ?? b.createdAt;
      return bTime.compareTo(aTime);
    });
    return list;
  }

  int? get activeConversationId => _activeConversationId;
  int? get currentUserId => _currentUserId;
  String? get errorMessage => _errorMessage;
  Map<int, MessageModel> get lastMessages => _lastMessages;
  int? get pendingOpenConversationId => _pendingOpenConversationId;
  int? get pendingNotificationConversationId =>
      _pendingNotificationConversationId;
  bool get activeConversationDeletedByOther => _activeConversationDeletedByOther;
  Map<int, int> get unreadCounts => _unreadCounts;

  int getUnreadCount(int conversationId) => _unreadCounts[conversationId] ?? 0;

  /// Returns conversation by id, or null if not found.
  ConversationModel? getConversationById(int id) =>
      _conversations.where((c) => c.id == id).firstOrNull;

  /// Returns the disappearing timer for the active conversation, or null.
  int? get conversationDisappearingTimer {
    if (_activeConversationId == null) return null;
    final conv = _conversations
        .where((c) => c.id == _activeConversationId)
        .firstOrNull;
    return conv?.disappearingTimer;
  }

  // ---------- Consume Patterns ----------

  /// Returns and clears pending open conversation ID. Used by screens to navigate.
  int? consumePendingOpen() {
    final id = _pendingOpenConversationId;
    _pendingOpenConversationId = null;
    return id;
  }

  /// Queue navigation from Android notification tap / FCM open — [MainShell] consumes.
  void requestNavigateToConversationFromNotification(int conversationId) {
    if (_pendingNotificationConversationId == conversationId) return;
    _pendingNotificationConversationId = conversationId;
    notifyListeners();
  }

  int? consumePendingNotificationConversationId() {
    final id = _pendingNotificationConversationId;
    _pendingNotificationConversationId = null;
    return id;
  }

  /// Call when user navigates back from a chat that was deleted by the other user.
  void clearActiveIfDeletedByOther() {
    if (_activeConversationDeletedByOther) {
      _activeConversationDeletedByOther = false;
      _activeConversationId = null;
      notifyListeners();
      _emitPushClientState();
    }
  }

  // ---------- Conversation Helpers ----------

  String getOtherUserUsername(ConversationModel conv) =>
      conv_helpers.getOtherUserUsername(conv, _currentUserId);

  int getOtherUserId(ConversationModel conv) =>
      conv_helpers.getOtherUserId(conv, _currentUserId);

  UserModel? getOtherUser(ConversationModel conv) =>
      conv_helpers.getOtherUser(conv, _currentUserId);

  // ---------- Event Handlers (called by socket events) ----------

  /// Handle 'conversationsList' event from backend.
  void onConversationsList(dynamic data) {
    final list = data as List<dynamic>;
    final previousUnread = Map<int, int>.from(_unreadCounts);
    final newConvs = list
        .map((c) => ConversationModel.fromJson(c as Map<String, dynamic>))
        .toList();

    // If our active conv is no longer in list (e.g. other user deleted), mark it
    if (_activeConversationId != null &&
        !newConvs.any((c) => c.id == _activeConversationId)) {
      _activeConversationDeletedByOther = true;
    }

    _conversations = newConvs;
    _unreadCounts.clear();

    for (final c in list) {
      final m = c as Map<String, dynamic>;
      final convId = m['id'] as int;
      final serverUnread = (m['unreadCount'] as num?)?.toInt() ?? 0;
      final prev = previousUnread[convId] ?? 0;
      // [newMessage] + incrementUnreadCount may run before this snapshot includes the
      // latest DB counts (reconnect, delayed getConversations, friend flows). Prefer the
      // higher of local vs server so we do not wipe badge/UI unread.
      final merged = prev > serverUnread ? prev : serverUnread;
      _unreadCounts[convId] = merged;

      // Update last message from backend data
      final lastMsgData = m['lastMessage'];
      if (lastMsgData != null) {
        try {
          var lastMsg =
              MessageModel.fromJson(lastMsgData as Map<String, dynamic>);
          if (lastMsg.displayAsEncryptedPlaceholder) {
            lastMsg = lastMsg.copyWith(content: 'Encrypted message');
          }
          _lastMessages[convId] = lastMsg;
        } catch (e) {
          debugPrint(
              '[ConversationsProvider] Failed to parse lastMessage for conversation $convId: $e');
        }
      }
    }

    if (_activeConversationId != null) {
      _unreadCounts[_activeConversationId!] = 0;
    }

    notifyListeners();
  }

  /// Handle 'openConversation' event — store pending ID for screen navigation.
  void onOpenConversation(dynamic data) {
    final convId = (data as Map<String, dynamic>)['conversationId'] as int;
    _pendingOpenConversationId = convId;
    notifyListeners();
  }

  /// Handle 'conversationDeleted' event — remove from list, handle active.
  void onConversationDeleted(dynamic data) {
    final convId = data['conversationId'] as int;
    _removeConversationById(convId);
    notifyListeners();
  }

  /// Handle 'disappearingTimerUpdated' event — update conversation timer.
  void onDisappearingTimerUpdated(dynamic data) {
    final m = data as Map<String, dynamic>;
    final conversationId = m['conversationId'] as int;
    final seconds = m['seconds'] as int?;

    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index != -1) {
      final oldConv = _conversations[index];
      _conversations[index] = ConversationModel(
        id: oldConv.id,
        userOne: oldConv.userOne,
        userTwo: oldConv.userTwo,
        createdAt: oldConv.createdAt,
        disappearingTimer: seconds,
      );
    }

    notifyListeners();
  }

  // ---------- Action Methods ----------

  /// Emit getConversations socket event.
  void getConversations() {
    _emit?.call('getConversations', null);
  }

  /// Emit startConversation socket event.
  void startConversation(int recipientId) {
    _emit?.call('startConversation', {'recipientId': recipientId});
  }

  /// Removes the conversation locally immediately, then emits deleteConversationOnly.
  ///
  /// Swipe [Dismissible] must remove the row from the list in the same frame as
  /// [onDismissed]; otherwise the tile stays in the tree while the dismiss
  /// animation completes and the widget can rebuild with a stuck red background.
  void deleteConversation(int conversationId) {
    _removeConversationById(conversationId);
    notifyListeners();
    _emit?.call('deleteConversationOnly', {'conversationId': conversationId});
  }

  /// Emit setDisappearingTimer socket event.
  void setDisappearingTimer(int conversationId, int? timer) {
    _emit?.call('setDisappearingTimer', {
      'conversationId': conversationId,
      'seconds': timer,
    });
  }

  /// Sets active conversation ID and clears unread count.
  void openConversation(int? conversationId) {
    _activeConversationId = conversationId;
    _activeConversationDeletedByOther = false;
    if (conversationId != null) {
      _unreadCounts[conversationId] = 0;
    }
    notifyListeners();
    _emitPushClientState();
  }

  /// Sets active conversation without fetching messages. Use when ChatDetailScreen
  /// will call openConversation (avoids double getMessages on desktop).
  void setActiveConversation(int conversationId) {
    _activeConversationId = conversationId;
    _activeConversationDeletedByOther = false;
    _unreadCounts[conversationId] = 0;
    notifyListeners();
    _emitPushClientState();
  }

  /// Clears the active conversation.
  void closeConversation() {
    _activeConversationId = null;
    notifyListeners();
    _emitPushClientState();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  // ---------- Inter-Provider Interface ----------

  /// Set the current user ID (called during connect).
  void setCurrentUserId(int userId) {
    _currentUserId = userId;
  }

  /// Remove all conversations involving a user (called by FriendsProvider on unfriend/block).
  /// Pass userId=-1 to remove conversations for a set of blocked users (caller provides IDs).
  void removeConversationsForUser(int userId, {Set<int>? blockedIds}) {
    if (userId == -1 && blockedIds != null) {
      _conversations.removeWhere((c) =>
          blockedIds.contains(c.userOne.id) ||
          blockedIds.contains(c.userTwo.id));
    } else {
      _conversations.removeWhere(
          (c) => c.userOne.id == userId || c.userTwo.id == userId);
    }
    _clearActiveIfRemoved();
    notifyListeners();
    _emitPushClientState();
  }

  /// Update the last message for a conversation (called by MessagingProvider).
  void updateLastMessage(int conversationId, MessageModel? message) {
    if (message != null) {
      _lastMessages[conversationId] = message;
    } else {
      _lastMessages.remove(conversationId);
    }
    notifyListeners();
  }

  /// Update the unread count for a conversation (called by MessagingProvider).
  void updateUnreadCount(int conversationId, int count) {
    _unreadCounts[conversationId] = count;
    notifyListeners();
  }

  /// Increment the unread count for a conversation by 1.
  void incrementUnreadCount(int conversationId) {
    _unreadCounts[conversationId] =
        (_unreadCounts[conversationId] ?? 0) + 1;
    notifyListeners();
  }

  /// Remove expired messages from lastMessages map.
  void removeExpiredLastMessages() {
    _lastMessages.removeWhere(
      (_, m) => m.expiresAt != null && m.expiresAt!.isBefore(DateTime.now()),
    );
    // No notifyListeners — caller decides when to notify.
  }

  // ---------- Lifecycle ----------

  /// Called on socket connect. Fresh: clear all; reconnect: preserve (NO FLICKER).
  void onConnect(bool isReconnect) {
    if (!isReconnect) {
      _conversations = [];
      _activeConversationId = null;
      _lastMessages.clear();
      _unreadCounts.clear();
      _pendingOpenConversationId = null;
      _pendingNotificationConversationId = null;
      _activeConversationDeletedByOther = false;
      _errorMessage = null;
      _clientVisible = true;
    } else {
      // Reconnect (same user): keep conversations and active chat to avoid flicker.
      _pendingOpenConversationId = null;
      _activeConversationDeletedByOther = false;
      _errorMessage = null;
    }
    notifyListeners();
    _emitPushClientState();
  }

  /// Called on socket disconnect. Minimal cleanup.
  void onDisconnect() {
    // Minimal — state preserved for potential reconnect.
  }

  /// Full reset — called on logout or user switch.
  void clearAll() {
    _conversations = [];
    _activeConversationId = null;
    _currentUserId = null;
    _lastMessages.clear();
    _unreadCounts.clear();
    _pendingOpenConversationId = null;
    _pendingNotificationConversationId = null;
    _activeConversationDeletedByOther = false;
    _errorMessage = null;
    _clientVisible = true;
    notifyListeners();
    _emitPushClientState();
  }

  // ---------- Private Helpers ----------

  void _removeConversationById(int convId) {
    _conversations.removeWhere((c) => c.id == convId);
    _lastMessages.remove(convId);
    _unreadCounts.remove(convId);
    if (_activeConversationId == convId) {
      _activeConversationId = null;
      _activeConversationDeletedByOther = false;
    }
    _emitPushClientState();
  }

  /// Clears active conversation if it was removed from the list.
  void _clearActiveIfRemoved() {
    if (_activeConversationId == null) return;
    final exists = _conversations.any((c) => c.id == _activeConversationId);
    if (!exists) {
      _activeConversationId = null;
    }
  }
}
