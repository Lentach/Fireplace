import 'package:flutter/foundation.dart';

import '../models/friend_request_model.dart';
import '../models/user_model.dart';

/// FriendsProvider — owns all friends, friend requests, blocking, and
/// user search state. [ConnectionProvider] coordinates; this provider holds friends/requests/blocked/search.
class FriendsProvider extends ChangeNotifier {
  // ---------- State ----------
  List<UserModel> _friends = [];
  List<FriendRequestModel> _friendRequests = [];
  int _pendingRequestsCount = 0;
  List<UserModel> _blockedUsers = [];
  final Set<int> _blockedByUserIds = {};
  bool _friendRequestJustSent = false;
  /// Set when we (sender) receive friendRequestAccepted — acceptor's username for snackbar.
  String? _pendingFriendAcceptedByName;
  List<UserModel>? _searchResults;

  int? _currentUserId;

  // ---------- Emit Callback ----------

  /// Callback to emit socket events. Set by [ConnectionProvider] via [setEmitCallback].
  void Function(String event, dynamic data)? _emit;

  /// Wire the socket emit callback so FriendsProvider can send events
  /// without depending on SocketService directly.
  void setEmitCallback(void Function(String event, dynamic data) emit) {
    _emit = emit;
  }

  // ---------- Cross-Provider Callbacks ----------

  /// Called when conversations for a user should be removed (e.g. unfriend, block).
  /// Wired by the wiring layer (e.g. ConversationsScreen) when [ConversationsProvider] exists.
  void Function(int userId)? onRemoveConversationsForUser;

  // ---------- Public Getters ----------

  List<UserModel> get friends => _friends;
  List<FriendRequestModel> get friendRequests => _friendRequests;
  int get pendingRequestsCount => _pendingRequestsCount;
  List<UserModel> get blockedUsers => _blockedUsers;
  Set<int> get blockedByUserIds => Set.unmodifiable(_blockedByUserIds);
  List<UserModel>? get searchResults => _searchResults;
  int? get currentUserId => _currentUserId;
  /// Peek at pending friend-accepted name without clearing it.
  String? get pendingFriendAcceptedByName => _pendingFriendAcceptedByName;

  /// Returns true (and clears) if a friend request was just sent. For snackbar.
  bool consumeFriendRequestSent() {
    final sent = _friendRequestJustSent;
    _friendRequestJustSent = false;
    return sent;
  }

  /// Returns acceptor's username and clears; null if none. For snackbar.
  String? consumePendingFriendAccepted() {
    final name = _pendingFriendAcceptedByName;
    _pendingFriendAcceptedByName = null;
    return name;
  }

  bool isFriend(int userId) {
    return _friends.any((f) => f.id == userId);
  }

  // ---------- Event Handlers (called by socket events, routed from ConnectionProvider) ----------

  void onFriendRequestsList(dynamic data) {
    final list = data as List<dynamic>;
    _friendRequests = list
        .map((r) => FriendRequestModel.fromJson(r as Map<String, dynamic>))
        .toList();
    notifyListeners();
  }

  void onNewFriendRequest(dynamic data) {
    final request =
        FriendRequestModel.fromJson(data as Map<String, dynamic>);
    _friendRequests.insert(0, request);
    notifyListeners();
  }

  void onFriendRequestSent(dynamic data) {
    _friendRequestJustSent = true;
    notifyListeners();
  }

  /// CRITICAL: do NOT call getConversations or getFriends here.
  /// Backend already emits updated lists; extra calls cause race condition
  /// and overwrite with stale data.
  void onFriendRequestAccepted(dynamic data) {
    final request =
        FriendRequestModel.fromJson(data as Map<String, dynamic>);
    _friendRequests.removeWhere((r) => r.id == request.id);
    // If we are the sender (we sent the request), show snackbar
    if (_currentUserId == request.sender.id) {
      _pendingFriendAcceptedByName = request.receiver.username;
    }
    notifyListeners();
  }

  void onFriendRequestRejected(dynamic data) {
    final request =
        FriendRequestModel.fromJson(data as Map<String, dynamic>);
    _friendRequests.removeWhere((r) => r.id == request.id);
    notifyListeners();
  }

  void onPendingRequestsCount(dynamic data) {
    final count = (data as Map<String, dynamic>)['count'] as int;
    _pendingRequestsCount = count;
    notifyListeners();
  }

  void onFriendsList(dynamic data) {
    final list = data as List<dynamic>;
    _friends = list
        .map((u) => UserModel.fromJson(u as Map<String, dynamic>))
        .toList();
    // If someone is in our friends list, they cannot be blocking us — clear them from blockedByUserIds
    // so that after unblock + re-add we can write again (no stale "can't message" state).
    _blockedByUserIds.removeWhere((id) => _friends.any((f) => f.id == id));
    notifyListeners();
  }

  void onUnfriended(dynamic data) {
    final unfriendUserId =
        (data as Map<String, dynamic>)['userId'] as int;
    _friends.removeWhere((f) => f.id == unfriendUserId);
    _friendRequests.removeWhere((r) =>
        r.sender.id == unfriendUserId || r.receiver.id == unfriendUserId);
    onRemoveConversationsForUser?.call(unfriendUserId);
    notifyListeners();
  }

  void onBlockedList(dynamic data) {
    final list = data as List<dynamic>;
    _blockedUsers = list
        .map((u) => UserModel.fromJson(u as Map<String, dynamic>))
        .toList();
    final blockedIds = _blockedUsers.map((u) => u.id).toSet();
    _friends.removeWhere((f) => blockedIds.contains(f.id));
    onRemoveConversationsForUser?.call(-1); // signal handled externally
    notifyListeners();
  }

  void onYouWereBlocked(dynamic data) {
    final blockerId = (data as Map<String, dynamic>)['userId'] as int;
    _blockedByUserIds.add(blockerId);
    _friends.removeWhere((f) => f.id == blockerId);
    onRemoveConversationsForUser?.call(blockerId);
    notifyListeners();
  }

  void onSearchUsersResult(dynamic data) {
    final list = data as List<dynamic>;
    _searchResults = list
        .map((u) => UserModel.fromJson(u as Map<String, dynamic>))
        .toList();
    notifyListeners();
  }

  // ---------- Action Methods (emit socket events) ----------

  void searchUsers(String handle) {
    _searchResults = null;
    notifyListeners();
    _emit?.call('searchUsers', {'handle': handle});
  }

  void clearSearchResults() {
    _searchResults = null;
    notifyListeners();
  }

  void sendFriendRequest(int userId) {
    _emit?.call('sendFriendRequest', {'recipientId': userId});
  }

  void acceptFriendRequest(int requestId) {
    _emit?.call('acceptFriendRequest', {'requestId': requestId});
  }

  void rejectFriendRequest(int requestId) {
    _emit?.call('rejectFriendRequest', {'requestId': requestId});
  }

  void unfriend(int userId) {
    _emit?.call('unfriend', {'userId': userId});
  }

  void blockUser(int userId) {
    _emit?.call('blockUser', {'userId': userId});
  }

  void unblockUser(int userId) {
    _emit?.call('unblockUser', {'userId': userId});
  }

  void loadBlockedList() {
    _emit?.call('getBlockedList', null);
  }

  void loadFriendRequests() {
    _emit?.call('getFriendRequests', null);
  }

  void loadFriends() {
    _emit?.call('getFriends', null);
  }

  // ---------- Lifecycle ----------

  /// Called on socket connect. Fresh connect clears all state;
  /// reconnect preserves friends/blocked to avoid UI flicker.
  /// _blockedByUserIds is always cleared: server does not replay youWereBlocked on reconnect.
  void onConnect(bool isReconnect) {
    _currentUserId = null; // will be set by setCurrentUserId
    _blockedByUserIds.clear();
    if (!isReconnect) {
      _friendRequests = [];
      _pendingRequestsCount = 0;
      _friends = [];
      _friendRequestJustSent = false;
      _pendingFriendAcceptedByName = null;
      _searchResults = null;
      _blockedUsers = [];
    } else {
      _pendingFriendAcceptedByName = null;
      _searchResults = null;
    }
    notifyListeners();
  }

  /// Set the current user ID (needed for sender checks in event handlers).
  void setCurrentUserId(int userId) {
    _currentUserId = userId;
  }

  /// Called on socket disconnect. Minimal cleanup.
  void onDisconnect() {
    // No state cleared on disconnect — reconnect will restore
  }

  /// Full reset of all state.
  void clearAll() {
    _friends = [];
    _friendRequests = [];
    _pendingRequestsCount = 0;
    _blockedUsers = [];
    _blockedByUserIds.clear();
    _friendRequestJustSent = false;
    _pendingFriendAcceptedByName = null;
    _searchResults = null;
    _currentUserId = null;
    notifyListeners();
  }
}
