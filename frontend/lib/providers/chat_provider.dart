import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../config/app_config.dart';
import '../models/conversation_model.dart';
import '../models/friend_request_model.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import '../services/socket_service.dart';
import 'connection_provider.dart';
import 'conversations_provider.dart';
import 'encryption_provider.dart';
import 'friends_provider.dart';
import 'messaging_provider.dart';

/// ChatProvider — ultra-thin facade that delegates to the new split providers.
///
/// Kept for backward compatibility with existing screens. All logic lives in:
///   - ConnectionProvider  (socket lifecycle, reconnect)
///   - ConversationsProvider (conversation state, active chat)
///   - MessagingProvider   (messages, send/receive, encryption orchestration)
///   - FriendsProvider     (friends, requests, blocking)
///   - EncryptionProvider  (E2E keys, session management)
///
/// Screens should migrate to read from the specific providers directly.
class ChatProvider extends ChangeNotifier {
  // ---------- Provider References ----------
  // Wired in conversations_screen.dart initState via setNewProviders().

  ConnectionProvider? _conn;
  ConversationsProvider? _convs;
  MessagingProvider? _msg;
  FriendsProvider? _friends;
  EncryptionProvider? _enc;

  /// Wire all sub-providers. Called once from conversations_screen.dart initState.
  void setNewProviders({
    required ConnectionProvider conn,
    required ConversationsProvider convs,
    required MessagingProvider msg,
    required FriendsProvider friends,
    required EncryptionProvider enc,
  }) {
    _conn = conn;
    _convs = convs;
    _msg = msg;
    _friends = friends;
    _enc = enc;
  }

  // ---------- Legacy wiring stubs (called from conversations_screen) ----------

  /// Legacy: wire EncryptionProvider. No-op at facade level — ConnectionProvider owns this now.
  void setEncryptionProvider(EncryptionProvider ep) {
    _enc = ep;
  }

  /// Legacy: wire FriendsProvider. Wires cross-provider callbacks.
  void setFriendsProvider(FriendsProvider fp) {
    _friends = fp;
    fp.onRemoveConversationsForUser = (userId) {
      if (userId == -1) {
        final blockedIds = fp.blockedUsers.map((u) => u.id).toSet();
        _convs?.removeConversationsForUser(-1, blockedIds: blockedIds);
      } else {
        _convs?.removeConversationsForUser(userId);
      }
    };
    fp.onClearActiveIfNeeded = (userId) {};
  }

  // ---------- Connect / Disconnect ----------

  void connect({required String token, required int userId}) {
    _conn?.connect(userId, token, AppConfig.baseUrl);
  }

  void disconnect() {
    _conn?.disconnect(isLogout: true);
  }

  void ensureReconnectIfNeeded() {
    _conn?.ensureReconnectIfNeeded();
  }

  // ---------- Conversation state ----------

  List<ConversationModel> get conversations => _convs?.conversations ?? [];

  List<ConversationModel> get sortedConversations =>
      _convs?.sortedConversations ?? [];

  int? get activeConversationId => _convs?.activeConversationId;

  int? get currentUserId => _convs?.currentUserId ?? _conn?.currentUserId;

  String? get errorMessage => _convs?.errorMessage ?? _conn?.errorMessage;

  Map<int, MessageModel> get lastMessages => _convs?.lastMessages ?? {};

  int? get pendingOpenConversationId => _convs?.pendingOpenConversationId;

  bool get activeConversationDeletedByOther =>
      _convs?.activeConversationDeletedByOther ?? false;

  int? get conversationDisappearingTimer =>
      _convs?.conversationDisappearingTimer;

  ConversationModel? getConversationById(int id) =>
      _convs?.getConversationById(id);

  String getOtherUserUsername(ConversationModel conv) =>
      _convs?.getOtherUserUsername(conv) ?? '';

  int getOtherUserId(ConversationModel conv) =>
      _convs?.getOtherUserId(conv) ?? 0;

  UserModel? getOtherUser(ConversationModel conv) =>
      _convs?.getOtherUser(conv);

  int getUnreadCount(int conversationId) =>
      _convs?.getUnreadCount(conversationId) ?? 0;

  int? consumePendingOpen() => _convs?.consumePendingOpen();

  void clearActiveIfDeletedByOther() => _convs?.clearActiveIfDeletedByOther();

  void clearError() => _convs?.clearError();

  void setConversationDisappearingTimer(int? seconds) {
    final convId = _convs?.activeConversationId;
    if (convId == null) return;
    _convs?.setDisappearingTimer(convId, seconds);
  }

  // ---------- Conversation actions ----------

  void setActiveConversation(int conversationId) =>
      _convs?.setActiveConversation(conversationId);

  void openConversation(int conversationId, {int limit = 50}) {
    _convs?.openConversation(conversationId);
    _conn?.socketService.getMessages(conversationId, limit: limit);
  }

  void loadMoreMessages({int additionalLimit = 50}) {
    final convId = _convs?.activeConversationId;
    if (convId == null) return;
    final newLimit = (_msg?.messages.length ?? 0) + additionalLimit;
    _conn?.socketService.getMessages(convId, limit: newLimit);
  }

  void clearActiveConversation() {
    _convs?.closeConversation();
    _msg?.clearMessages();
  }

  void startConversation(int recipientId) =>
      _convs?.startConversation(recipientId);

  void deleteConversationOnly(int conversationId) =>
      _convs?.deleteConversation(conversationId);

  // ---------- Message state ----------

  List<MessageModel> get messages => _msg?.messages ?? [];

  MessageModel? get replyingToMessage => _msg?.replyingToMessage;

  bool get showPingEffect => _msg?.showPingEffect ?? false;

  bool get isRecordingVoice => _msg?.isRecordingVoice ?? false;

  set isRecordingVoice(bool value) {
    if (_msg != null) {
      _msg!.isRecordingVoice = value;
      // Notify MessagingProvider listeners so UI (e.g. countdown timer) updates
      _msg!.notifyListeners();
    }
  }

  ValueNotifier<int> get countdownTickNotifier =>
      _msg?.countdownTickNotifier ?? ValueNotifier(0);

  bool isPartnerTyping(int conversationId) =>
      _msg?.isPartnerTyping(conversationId) ?? false;

  bool isPartnerRecordingVoice(int conversationId) =>
      _msg?.isPartnerRecordingVoice(conversationId) ?? false;

  void setReplyingTo(MessageModel? msg) => _msg?.setReplyingTo(msg);

  void clearReplyingTo() => _msg?.clearReplyingTo();

  void clearPingEffect() => _msg?.clearPingEffect();

  void removeExpiredMessages() => _msg?.removeExpiredMessages();

  void markConversationRead(int conversationId) =>
      _msg?.markConversationRead(conversationId);

  // ---------- Send methods ----------

  void sendMessage(String content, {int? expiresIn, int? replyToMessageId}) =>
      _msg?.sendMessage(content,
          expiresIn: expiresIn, replyToMessageId: replyToMessageId);

  void sendPing(int recipientId) => _msg?.sendPing(recipientId);

  Future<void> sendVoiceMessage({
    required int recipientId,
    required int duration,
    int? conversationId,
    String? localAudioPath,
    List<int>? localAudioBytes,
  }) =>
      _msg?.sendVoiceMessage(
            recipientId: recipientId,
            duration: duration,
            conversationId: conversationId,
            localAudioPath: localAudioPath,
            localAudioBytes: localAudioBytes,
          ) ??
      Future.value();

  Future<void> sendImageMessage(
    String token,
    XFile imageFile,
    int recipientId,
  ) =>
      _msg?.sendImageMessage(token, imageFile, recipientId) ?? Future.value();

  Future<void> sendGif(
    String token,
    String gifUrl,
    int recipientId,
  ) =>
      _msg?.sendGif(token, gifUrl, recipientId) ?? Future.value();

  Future<void> sendFileMessage(
    String token,
    List<int> fileBytes,
    String fileName,
    String fileMimeType,
    int recipientId,
  ) =>
      _msg?.sendFileMessage(
            token, fileBytes, fileName, fileMimeType, recipientId) ??
      Future.value();

  Future<void> sendAntiQuantumNote({
    required String content,
    required int expiresInSeconds,
  }) =>
      _msg?.sendAntiQuantumNote(
            content: content, expiresInSeconds: expiresInSeconds) ??
      Future.value();

  Future<void> retryFailedMessage(String tempId) =>
      _msg?.retryFailedMessage(tempId) ?? Future.value();

  void addReaction(int messageId, String emoji) =>
      _msg?.addReaction(messageId, emoji);

  void removeReaction(int messageId, String emoji) =>
      _msg?.removeReaction(messageId, emoji);

  void deleteMessage(int messageId, {required bool forEveryone}) =>
      _msg?.deleteMessage(messageId, forEveryone: forEveryone);

  void clearChatHistory(int conversationId) =>
      _msg?.clearChatHistory(conversationId);

  void emitTyping() => _msg?.emitTyping();

  // ---------- Friends state ----------

  List<FriendRequestModel> get friendRequests =>
      _friends?.friendRequests ?? [];

  int get pendingRequestsCount => _friends?.pendingRequestsCount ?? 0;

  List<UserModel> get friends => _friends?.friends ?? [];

  List<UserModel> get blockedUsers => _friends?.blockedUsers ?? [];

  Set<int> get blockedByUserIds => _friends?.blockedByUserIds ?? {};

  String? get pendingFriendAcceptedByName =>
      _friends?.pendingFriendAcceptedByName;

  List<UserModel>? get searchResults => _friends?.searchResults;

  bool isFriend(int userId) => _friends?.isFriend(userId) ?? false;

  bool consumeFriendRequestSent() =>
      _friends?.consumeFriendRequestSent() ?? false;

  String? consumePendingFriendAccepted() =>
      _friends?.consumePendingFriendAccepted();

  void searchUsers(String handle) => _friends?.searchUsers(handle);

  void clearSearchResults() => _friends?.clearSearchResults();

  void sendFriendRequest(int recipientId) =>
      _friends?.sendFriendRequest(recipientId);

  void acceptFriendRequest(int requestId) =>
      _friends?.acceptFriendRequest(requestId);

  void rejectFriendRequest(int requestId) =>
      _friends?.rejectFriendRequest(requestId);

  void fetchFriendRequests() => _friends?.loadFriendRequests();

  void fetchFriends() => _friends?.loadFriends();

  void unfriend(int userId) => _friends?.unfriend(userId);

  void blockUser(int userId) => _friends?.blockUser(userId);

  void unblockUser(int userId) => _friends?.unblockUser(userId);

  void loadBlockedList() => _friends?.loadBlockedList();

  // ---------- Encryption ----------

  Future<String?> getIdentityFingerprint() =>
      _enc?.getIdentityFingerprint() ?? Future.value(null);

  Future<void> clearEncryptionKeys() async {
    await _enc?.clearEncryptionKeys();
  }

  // ---------- Socket access (needed by legacy widget code) ----------

  /// Direct access to SocketService for legacy widget usage (e.g. emitRecordingVoice).
  SocketService get socket => _conn?.socketService ?? SocketService();
}
