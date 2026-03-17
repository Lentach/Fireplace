import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:pointycastle/export.dart';
import '../utils/file_utils_stub.dart'
    if (dart.library.io) '../utils/file_utils_io.dart' as file_utils;

import '../config/app_config.dart';
import '../models/message_model.dart';
import '../services/api_service.dart';
import '../services/link_preview_service.dart';
import '../utils/e2e_envelope.dart';
import 'conversation_helpers.dart' as conv_helpers;
import 'conversations_provider.dart';
import 'encryption_provider.dart';

/// MessagingProvider — owns all message state, send/receive handlers,
/// encryption orchestration, typing/recording indicators, and reactions.
/// Wired by [ConnectionProvider] and ConversationsScreen (setEncryptionProvider, setConversationsProvider).
class MessagingProvider extends ChangeNotifier {
  static void _e2eFlowLog(String step, [Map<String, dynamic>? data]) {
    if (kDebugMode) debugPrint('[E2E-FLOW] $step | ${data ?? {}}');
  }

  // ---------- Dependencies ----------

  late final ApiService _api = ApiService(baseUrl: AppConfig.baseUrl);

  /// Callback to emit socket events. Set by the wiring layer.
  void Function(String event, dynamic data)? _emit;

  /// Cross-provider references, set by the wiring layer.
  EncryptionProvider? _encryptionProvider;
  ConversationsProvider? _conversationsProvider;

  /// Auth token for REST calls (media upload, link preview).
  String? _tokenForReconnect;

  int? _currentUserId;

  // ---------- E2E Encryption ----------

  /// Single delayed retry for a failed text message (e.g. recipient had no key bundle, then came online).
  Timer? _delayedRetryTimer;
  String? _delayedRetryTempId;
  bool _decryptingHistory = false;

  /// Incremented on each new messageHistory to cancel stale in-flight decrypt loops.
  /// Each loop captures its generation at start and exits when the counter changes.
  int _decryptHistoryGeneration = 0;
  final List<Map<String, dynamic>> _incomingMessageQueue = [];

  /// Plaintext content + link preview + type/media keyed by tempId — survives
  /// _messages list overwrites (e.g. when messageHistory arrives before messageSent).
  /// Value: {'content': String, 'messageType'?: String, 'mediaUrl'?: String,
  ///         'mediaDuration'?: int, 'linkPreviewUrl'?: String, ...}
  final Map<String, Map<String, dynamic>> _pendingSendContent = {};

  // Monotonic counter for temporary negative message IDs — prevents collision
  // if two messages are sent within the same millisecond.
  static int _tempIdSeq = 0;

  // ---------- Message State ----------

  List<MessageModel> _messages = [];

  /// IDs of messages we were told were deleted (messageDeleted). Used so a late
  /// messageHistory response doesn't re-add them.
  final Set<int> _deletedMessageIds = {};

  /// Message being replied to (set when user taps Reply in bubble bottom sheet).
  MessageModel? _replyingToMessage;

  bool _showPingEffect = false;

  // ---------- Typing / Recording Indicators ----------

  final Map<int, bool> _typingStatus = {};
  final Map<int, Timer> _typingTimers = {};
  final Map<int, bool> _partnerRecordingVoice = {}; // conversationId -> isRecording

  /// Ticks every second for countdown display. Bubbles use ValueListenableBuilder
  /// so only they rebuild, not the whole screen. Prevents recording timer freeze.
  final ValueNotifier<int> countdownTickNotifier = ValueNotifier(0);

  /// True while user holds mic to record. Countdown timer skips ticks to avoid
  /// starving the recording timer callback (progressive freeze).
  bool isRecordingVoice = false;

  // ---------- Public Getters ----------

  List<MessageModel> get messages => _messages;
  MessageModel? get replyingToMessage => _replyingToMessage;
  bool get showPingEffect => _showPingEffect;
  bool get isDecryptingHistory => _decryptingHistory;
  int? get currentUserId => _currentUserId;

  bool isPartnerTyping(int conversationId) =>
      _typingStatus[conversationId] ?? false;

  bool isPartnerRecordingVoice(int conversationId) =>
      _partnerRecordingVoice[conversationId] ?? false;

  /// Update recording state and notify listeners. Called from ChatInputBar widget.
  void setIsRecordingVoice(bool value) {
    isRecordingVoice = value;
    notifyListeners();
  }

  // ---------- Dependency Wiring ----------

  /// Wire the EncryptionProvider for E2E operations.
  void setEncryptionProvider(EncryptionProvider ep) {
    _encryptionProvider = ep;
  }

  /// Wire the ConversationsProvider for lastMessage/unread updates.
  void setConversationsProvider(ConversationsProvider cp) {
    _conversationsProvider = cp;
  }

  /// Wire the socket emit callback so MessagingProvider can send events
  /// without depending on SocketService directly.
  void setEmitCallback(void Function(String event, dynamic data) emit) {
    _emit = emit;
  }

  /// Set the current user ID and auth token. Called on connect.
  void setCurrentUserId(int userId) {
    _currentUserId = userId;
  }

  /// Set auth token for REST calls (media upload, link preview proxy).
  void setToken(String? token) {
    _tokenForReconnect = token;
  }

  // ---------- Reply-To ----------

  void setReplyingTo(MessageModel? msg) {
    _replyingToMessage = msg;
    notifyListeners();
  }

  void clearReplyingTo() {
    if (_replyingToMessage != null) {
      _replyingToMessage = null;
      notifyListeners();
    }
  }

  // ---------- Ping Effect ----------

  void clearPingEffect() {
    _showPingEffect = false;
    notifyListeners();
  }

  // ---------- Event Handlers (socket events) ----------

  void onNewMessage(dynamic data) {
    _handleIncomingMessage(data);
  }

  void onMessageSent(dynamic data) {
    _handleIncomingMessage(data);
  }

  void onMessageHistory(dynamic data) {
    final activeConversationId = _conversationsProvider?.activeConversationId;

    int? responseConversationId;
    List<dynamic> list;
    if (data is Map<String, dynamic> &&
        data.containsKey('conversationId') &&
        data.containsKey('messages')) {
      responseConversationId = (data['conversationId'] as num).toInt();
      list = data['messages'] as List<dynamic>;
    } else if (data is List<dynamic>) {
      list = data;
    } else {
      return;
    }
    if (responseConversationId != null &&
        activeConversationId != null &&
        responseConversationId != activeConversationId) {
      return;
    }
    _messages = list
        .map((m) => MessageModel.fromJson(m as Map<String, dynamic>))
        .toList();

    // Cancel any in-flight decrypt so we process the latest messages
    _decryptHistoryGeneration++;

    // Don't re-add messages we already received as deleted
    _messages.removeWhere((m) => _deletedMessageIds.contains(m.id));

    // Immediately remove any already-expired messages
    final now = DateTime.now();
    _messages.removeWhere(
      (m) => m.expiresAt != null && m.expiresAt!.isBefore(now),
    );
    notifyListeners();
    if (activeConversationId != null) {
      markConversationRead(activeConversationId);
    }

    // Decrypt history first so no live message advances the session before
    // we decrypt in order. Queue any incoming messages until done.
    final myGeneration = _decryptHistoryGeneration;
    _decryptingHistory = true;
    _decryptMessageHistory(myGeneration).whenComplete(() {
      if (_decryptHistoryGeneration == myGeneration) {
        _decryptingHistory = false;
      }
      _processIncomingMessageQueue();
    });
  }

  void onMessageDelivered(dynamic data) {
    _handleMessageDelivered(data);
  }

  void onMessageDeleted(dynamic data) {
    _handleMessageDeleted(data);
  }

  void onChatHistoryCleared(dynamic data) {
    _handleChatHistoryCleared(data);
  }

  void onReactionUpdated(dynamic data) {
    _handleReactionUpdated(data);
  }

  void onLinkPreviewReady(dynamic data) {
    _handleLinkPreviewReady(data);
  }

  void onPartnerTyping(dynamic data) {
    _handlePartnerTyping(data);
  }

  void onPartnerRecordingVoice(dynamic data) {
    _handlePartnerRecordingVoice(data);
  }

  /// Called by ConnectionProvider when conversationDeleted is received.
  /// Clears messages for the deleted conversation.
  void onConversationDeleted(int conversationId) {
    _messages.removeWhere((m) => m.conversationId == conversationId);
    notifyListeners();
  }

  // ---------- Internal Handlers ----------

  void _handleIncomingMessage(dynamic data) {
    final dataMap = data as Map<String, dynamic>;
    final msg = MessageModel.fromJson(dataMap);
    final activeConversationId = _conversationsProvider?.activeConversationId;

    // Queue incoming encrypted messages for active conversation while we're
    // decrypting history (so history decrypt runs first and session order is preserved).
    if (_decryptingHistory &&
        msg.conversationId == activeConversationId &&
        msg.needsDecryption(_currentUserId)) {
      _incomingMessageQueue.add(dataMap);
      return;
    }
    _e2eFlowLog('RECV_MSG', {
      'msgId': msg.id,
      'senderId': msg.senderId,
      'hasEncryptedContent':
          msg.encryptedContent != null && msg.encryptedContent!.isNotEmpty,
      'needsDecryption': msg.needsDecryption(_currentUserId),
    });
    // If encrypted, decrypt async and update in-place
    if (msg.needsDecryption(_currentUserId)) {
      _addMessageToState(msg);
      _decryptMessageAsync(msg).then((decrypted) async {
        _encryptionProvider?.cacheDecryption(decrypted.id, decrypted);
        await _persistDecryptedContent(decrypted);
        final idx = _messages.indexWhere((m) => m.id == decrypted.id);
        if (idx != -1) {
          _messages[idx] = decrypted;
        }
        final lastMessages = _conversationsProvider?.lastMessages;
        if (lastMessages != null &&
            lastMessages[decrypted.conversationId]?.id == decrypted.id) {
          _conversationsProvider?.updateLastMessage(
              decrypted.conversationId, decrypted);
        }
        _e2eFlowLog('RECV_DECRYPT_DONE', {
          'msgId': decrypted.id,
          'contentLength': decrypted.content.length,
        });
        notifyListeners();
      });
      return;
    }

    _addMessageToState(msg);
  }

  void _processIncomingMessageQueue() {
    if (_incomingMessageQueue.isEmpty) return;
    final queue = List<Map<String, dynamic>>.from(_incomingMessageQueue);
    _incomingMessageQueue.clear();
    for (final data in queue) {
      _handleIncomingMessage(data);
    }
  }

  Future<void> _persistDecryptedContent(MessageModel decrypted) async {
    if (decrypted.content.isEmpty ||
        decrypted.content == '[Decryption failed]' ||
        decrypted.content == '[Encryption not initialized]') {
      return;
    }
    // Validate linkPreviewImageUrl before persist (SSRF defense in depth)
    final safeImageUrl = decrypted.linkPreviewImageUrl != null &&
            decrypted.linkPreviewUrl != null &&
            LinkPreviewService.isSafeImageUrl(
              decrypted.linkPreviewImageUrl,
              decrypted.linkPreviewUrl,
            )
        ? decrypted.linkPreviewImageUrl
        : null;
    final data = <String, dynamic>{
      'content': decrypted.content,
      if (decrypted.messageType != MessageType.text)
        'messageType': decrypted.messageType.name.toUpperCase(),
      if (decrypted.mediaUrl != null) 'mediaUrl': decrypted.mediaUrl!,
      if (decrypted.mediaDuration != null)
        'mediaDuration': decrypted.mediaDuration!,
      if (decrypted.linkPreviewUrl != null)
        'linkPreviewUrl': decrypted.linkPreviewUrl!,
      if (decrypted.linkPreviewTitle != null)
        'linkPreviewTitle': decrypted.linkPreviewTitle!,
      if (safeImageUrl != null) 'linkPreviewImageUrl': safeImageUrl,
    };
    try {
      await _encryptionProvider?.saveDecryptedContent(decrypted.id, data);
    } catch (_) {}
  }

  void _addMessageToState(MessageModel msg) {
    final activeConversationId = _conversationsProvider?.activeConversationId;

    // If this is our own message (messageSent), replace temp optimistic message
    // and keep plaintext for display (server stores "[encrypted]" as content).
    if (msg.senderId == _currentUserId && msg.tempId != null) {
      final savedData = _pendingSendContent.remove(msg.tempId);
      final savedContent = savedData?['content'];
      final tempIndex = _messages.indexWhere((m) => m.tempId == msg.tempId);
      final tempContent = tempIndex != -1 ? _messages[tempIndex].content : null;
      if (tempIndex != -1) _messages.removeAt(tempIndex);
      final plaintextContent = savedContent ?? tempContent ?? '';
      if (msg.content == '[encrypted]') {
        final restoredType =
            _parseMessageTypeString(savedData?['messageType'] as String?);
        msg = msg.copyWith(
          content: plaintextContent.isNotEmpty ? plaintextContent : null,
          messageType: restoredType,
          mediaUrl: savedData?['mediaUrl'] as String?,
          mediaDuration: savedData?['mediaDuration'] as int?,
          linkPreviewUrl: savedData?['linkPreviewUrl'] as String?,
          linkPreviewTitle: savedData?['linkPreviewTitle'] as String?,
          linkPreviewImageUrl: savedData?['linkPreviewImageUrl'] as String?,
        );
        final persistData = <String, dynamic>{
          'content': plaintextContent,
          if (savedData?['messageType'] != null)
            'messageType': savedData!['messageType'],
          if (savedData?['mediaUrl'] != null) 'mediaUrl': savedData!['mediaUrl'],
          if (savedData?['mediaDuration'] != null)
            'mediaDuration': savedData!['mediaDuration'],
          if (savedData?['linkPreviewUrl'] != null)
            'linkPreviewUrl': savedData!['linkPreviewUrl'],
          if (savedData?['linkPreviewTitle'] != null)
            'linkPreviewTitle': savedData!['linkPreviewTitle'],
          if (savedData?['linkPreviewImageUrl'] != null)
            'linkPreviewImageUrl': savedData!['linkPreviewImageUrl'],
        };
        _encryptionProvider
            ?.saveDecryptedContent(msg.id, persistData)
            .ignore();
      }
    }

    // Add confirmed message
    if (msg.conversationId == activeConversationId) {
      _messages.add(msg);
    }

    _conversationsProvider?.updateLastMessage(msg.conversationId, msg);
    if (msg.senderId != _currentUserId) {
      if (msg.conversationId != activeConversationId) {
        _conversationsProvider?.incrementUnreadCount(msg.conversationId);
      }
      _emit?.call('messageDelivered', {'messageId': msg.id});
      if (msg.conversationId == activeConversationId) {
        markConversationRead(msg.conversationId);
      }
    }
    // Clear typing and recording indicators when message arrives
    if (_typingStatus[msg.conversationId] == true) {
      _typingTimers[msg.conversationId]?.cancel();
      _typingTimers.remove(msg.conversationId);
      _typingStatus[msg.conversationId] = false;
    }
    _partnerRecordingVoice.remove(msg.conversationId);
    notifyListeners();
  }

  void _handleMessageDelivered(dynamic data) {
    final map = data as Map<String, dynamic>;
    final messageId = map['messageId'] as int;
    final status = map['deliveryStatus'] as String;
    final conversationId = map['conversationId'] as int?;
    final newStatus = MessageModel.parseDeliveryStatus(status);

    // Update message in _messages list (current chat)
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index != -1) {
      _messages[index] = _messages[index].copyWith(
        deliveryStatus: newStatus,
      );
    }

    // Update _lastMessages so list and re-opened chat show correct status
    if (conversationId != null) {
      final lastMessages = _conversationsProvider?.lastMessages;
      if (lastMessages != null && lastMessages[conversationId]?.id == messageId) {
        _conversationsProvider?.updateLastMessage(
          conversationId,
          lastMessages[conversationId]!.copyWith(deliveryStatus: newStatus),
        );
      }
    }

    if (index != -1 || conversationId != null) {
      notifyListeners();
    }
  }

  void _handleChatHistoryCleared(dynamic data) {
    final m = data as Map<String, dynamic>;
    final conversationId = m['conversationId'] as int;

    // Clear messages from memory
    _messages.removeWhere((m) => m.conversationId == conversationId);
    _conversationsProvider?.updateLastMessage(conversationId, null);

    notifyListeners();
  }

  void _handleMessageDeleted(dynamic data) {
    final m = data as Map<String, dynamic>;
    final messageId = m['messageId'] as int;
    final conversationId = m['conversationId'] as int;
    final forEveryone = m['forEveryone'] as bool? ?? false;

    _deletedMessageIds.add(messageId);
    _messages.removeWhere((msg) => msg.id == messageId);

    // Update last message preview for conversation list
    final lastMessages = _conversationsProvider?.lastMessages;
    if (lastMessages != null && lastMessages[conversationId]?.id == messageId) {
      final remaining =
          _messages.where((msg) => msg.conversationId == conversationId).toList();
      if (remaining.isNotEmpty) {
        remaining.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        _conversationsProvider?.updateLastMessage(conversationId, remaining.last);
      } else {
        _conversationsProvider?.updateLastMessage(conversationId, null);
      }
    }

    // If delete for everyone and we weren't viewing this chat, refresh conv list
    final activeConversationId = _conversationsProvider?.activeConversationId;
    if (forEveryone && activeConversationId != conversationId) {
      _emit?.call('getConversations', null);
    }

    notifyListeners();
  }

  void _handlePartnerTyping(dynamic data) {
    final map = data as Map<String, dynamic>;
    final conversationId = map['conversationId'] as int;
    _typingStatus[conversationId] = true;
    _typingTimers[conversationId]?.cancel();
    _typingTimers[conversationId] = Timer(const Duration(seconds: 3), () {
      _typingStatus[conversationId] = false;
      _typingTimers.remove(conversationId);
      notifyListeners();
    });
    notifyListeners();
  }

  void _handleReactionUpdated(dynamic data) {
    final m = data as Map<String, dynamic>;
    final messageId = m['messageId'] as int;
    final reactionsRaw = (m['reactions'] as Map<String, dynamic>?) ?? {};
    final reactions = reactionsRaw.map(
      (k, v) => MapEntry(k, (v as List).map((e) => e as int).toList()),
    );

    final index = _messages.indexWhere((msg) => msg.id == messageId);
    if (index != -1) {
      _messages[index] = _messages[index].copyWith(reactions: reactions);
      notifyListeners();
    }
  }

  void _handleLinkPreviewReady(dynamic data) {
    final m = data as Map<String, dynamic>;
    final messageId = m['messageId'] as int;
    final index = _messages.indexWhere((msg) => msg.id == messageId);
    if (index == -1) return;
    _messages[index] = _messages[index].copyWith(
      linkPreviewUrl: m['linkPreviewUrl'] as String?,
      linkPreviewTitle: m['linkPreviewTitle'] as String?,
      linkPreviewImageUrl: m['linkPreviewImageUrl'] as String?,
    );
    notifyListeners();
  }

  void _handlePartnerRecordingVoice(dynamic data) {
    final map = data as Map<String, dynamic>;
    final conversationId = map['conversationId'] as int;
    final isRecording = map['isRecording'] as bool? ?? false;
    if (isRecording) {
      _partnerRecordingVoice[conversationId] = true;
    } else {
      _partnerRecordingVoice.remove(conversationId);
    }
    notifyListeners();
  }

  // ---------- Send Methods ----------

  void sendMessage(String content, {int? expiresIn, int? replyToMessageId}) {
    final activeConversationId = _conversationsProvider?.activeConversationId;
    if (activeConversationId == null || _currentUserId == null) return;

    final conversations = _conversationsProvider!.conversations;
    final conv = conversations.firstWhere((c) => c.id == activeConversationId);
    final recipientId = conv_helpers.getOtherUserId(conv, _currentUserId);

    // Use conversation disappearing timer if expiresIn not provided
    final effectiveExpiresIn =
        expiresIn ?? _conversationsProvider!.conversationDisappearingTimer;
    final effectiveReplyToId = replyToMessageId ?? _replyingToMessage?.id;

    // Generate unique tempId for optimistic message matching
    final tempId =
        'temp_${DateTime.now().millisecondsSinceEpoch}_$_currentUserId';

    ReplyToPreview? replyPreview;
    if (_replyingToMessage != null) {
      final rt = _replyingToMessage!;
      final contentPreview = rt.messageType == MessageType.voice
          ? 'Voice message'
          : rt.messageType == MessageType.image
              ? 'Image'
              : rt.messageType == MessageType.file
                  ? 'File'
                  : rt.messageType == MessageType.ping
                      ? 'Ping'
                      : rt.content.length > 150
                          ? '${rt.content.substring(0, 150)}...'
                          : rt.content;
      replyPreview = ReplyToPreview(
        id: rt.id,
        content: contentPreview,
        senderUsername: rt.senderUsername,
        messageType: rt.messageType,
      );
    }

    // Create optimistic message with SENDING status
    final tempMessage = MessageModel(
      id: -(++MessagingProvider._tempIdSeq), // Monotonic temporary negative ID
      content: content,
      senderId: _currentUserId!,
      senderUsername: '', // Will be replaced when server confirms
      conversationId: activeConversationId,
      createdAt: DateTime.now(),
      deliveryStatus: MessageDeliveryStatus.sending,
      expiresAt: effectiveExpiresIn != null
          ? DateTime.now().add(Duration(seconds: effectiveExpiresIn))
          : null,
      tempId: tempId,
      replyToMessageId: effectiveReplyToId,
      replyTo: replyPreview,
    );

    _messages.add(tempMessage);
    // Persist plaintext separately so it survives if _messages is overwritten
    // by a messageHistory response before messageSent arrives.
    // Use explicit Map type to avoid DDC/JS IdentityMap subtype errors.
    _pendingSendContent[tempId] = <String, dynamic>{'content': content};
    if (_replyingToMessage != null) {
      _replyingToMessage = null;
    }
    notifyListeners();

    // Encrypt and send asynchronously
    _encryptAndSend(
      recipientId: recipientId,
      content: content,
      tempId: tempId,
      effectiveExpiresIn: effectiveExpiresIn,
      effectiveReplyToId: effectiveReplyToId,
    );
  }

  void sendPing(int recipientId) {
    final activeConversationId = _conversationsProvider?.activeConversationId;
    if (activeConversationId == null || _currentUserId == null) return;

    final effectiveExpiresIn =
        _conversationsProvider!.conversationDisappearingTimer;
    final tempId =
        'temp_${DateTime.now().millisecondsSinceEpoch}_$_currentUserId';

    final tempMessage = MessageModel(
      id: -(++MessagingProvider._tempIdSeq),
      content: '',
      senderId: _currentUserId!,
      senderUsername: '',
      conversationId: activeConversationId,
      createdAt: DateTime.now(),
      deliveryStatus: MessageDeliveryStatus.sending,
      messageType: MessageType.ping,
      expiresAt: effectiveExpiresIn != null
          ? DateTime.now().add(Duration(seconds: effectiveExpiresIn))
          : null,
      tempId: tempId,
    );

    _messages.add(tempMessage);
    _pendingSendContent[tempId] =
        <String, dynamic>{'content': '', 'messageType': 'PING'};
    _showPingEffect = true;
    notifyListeners();

    _encryptAndSend(
      recipientId: recipientId,
      content: '',
      tempId: tempId,
      effectiveExpiresIn: effectiveExpiresIn,
      messageType: 'PING',
    );
  }

  Future<void> sendImageMessage(
    String token,
    XFile imageFile,
    int recipientId,
  ) async {
    final activeConversationId = _conversationsProvider?.activeConversationId;
    if (activeConversationId == null || _currentUserId == null) return;

    final effectiveExpiresIn =
        _conversationsProvider!.conversationDisappearingTimer;
    final tempId =
        'temp_${DateTime.now().millisecondsSinceEpoch}_$_currentUserId';

    // Create optimistic message
    final tempMessage = MessageModel(
      id: -(++MessagingProvider._tempIdSeq),
      content: '',
      senderId: _currentUserId!,
      senderUsername: '',
      conversationId: activeConversationId,
      createdAt: DateTime.now(),
      deliveryStatus: MessageDeliveryStatus.sending,
      messageType: MessageType.image,
      expiresAt: effectiveExpiresIn != null
          ? DateTime.now().add(Duration(seconds: effectiveExpiresIn))
          : null,
      tempId: tempId,
    );

    _messages.add(tempMessage);
    _pendingSendContent[tempId] =
        <String, dynamic>{'content': '', 'messageType': 'IMAGE'};
    notifyListeners();

    try {
      // Upload to Cloudinary
      final responseData = await _api.uploadMedia(
        token: token,
        type: 'image',
        imageFile: imageFile,
        expiresIn: effectiveExpiresIn,
      );

      final cloudinaryUrl = responseData['mediaUrl'] as String;

      // Update optimistic message with URL
      final idx = _messages.indexWhere((m) => m.tempId == tempId);
      if (idx != -1) {
        _messages[idx] = _messages[idx].copyWith(mediaUrl: cloudinaryUrl);
        notifyListeners();
      }

      // Encrypt and send
      _encryptAndSend(
        recipientId: recipientId,
        content: '',
        tempId: tempId,
        effectiveExpiresIn: effectiveExpiresIn,
        messageType: 'IMAGE',
        mediaUrl: cloudinaryUrl,
      );
    } catch (e) {
      debugPrint('[MessagingProvider] Image upload failed: $e');
      _markMessageFailed(tempId, 'Image upload failed: ${e.toString()}');
    }
  }

  Future<void> sendVoiceMessage({
    required int recipientId,
    required int duration,
    int? conversationId,
    String? localAudioPath,
    List<int>? localAudioBytes,
  }) async {
    if (localAudioPath == null && localAudioBytes == null) {
      throw Exception('Either localAudioPath or localAudioBytes required');
    }
    if (_currentUserId == null) return;

    // Use provided conversationId or active one
    final effectiveConvId =
        conversationId ?? _conversationsProvider?.activeConversationId;
    if (effectiveConvId == null) return;

    final tempId =
        'temp_${DateTime.now().millisecondsSinceEpoch}_$_currentUserId';

    // Get disappearing timer from conversation
    final conversations = _conversationsProvider!.conversations;
    final conv = conversations.firstWhere((c) => c.id == effectiveConvId);
    final effectiveExpiresIn = conv.disappearingTimer;

    // 1. Create optimistic message
    final optimisticMessage = MessageModel(
      id: -(++MessagingProvider._tempIdSeq),
      content: '',
      senderId: _currentUserId!,
      senderUsername: '',
      conversationId: effectiveConvId,
      createdAt: DateTime.now(),
      deliveryStatus: MessageDeliveryStatus.sending,
      messageType: MessageType.voice,
      mediaUrl: localAudioPath ?? '',
      mediaDuration: duration,
      tempId: tempId,
      expiresAt: effectiveExpiresIn != null
          ? DateTime.now().add(Duration(seconds: effectiveExpiresIn))
          : null,
    );

    // 2. Add to messages immediately (optimistic)
    _messages.add(optimisticMessage);
    _pendingSendContent[tempId] =
        <String, dynamic>{'content': '', 'messageType': 'VOICE'};
    _conversationsProvider?.updateLastMessage(effectiveConvId, optimisticMessage);
    notifyListeners();

    // 3. Upload to Cloudinary
    try {
      if (_tokenForReconnect == null) {
        throw Exception('No authentication token available');
      }

      final responseData = await _api.uploadMedia(
        token: _tokenForReconnect!,
        type: 'voice',
        duration: duration,
        expiresIn: effectiveExpiresIn,
        audioPath: localAudioPath,
        audioBytes: localAudioBytes,
      );

      final cloudinaryUrl = responseData['mediaUrl'] as String;
      final serverDuration =
          (responseData['mediaDuration'] as num?)?.toInt() ?? duration;

      // 4. Update optimistic message with Cloudinary URL
      final index = _messages.indexWhere((m) => m.tempId == tempId);
      if (index != -1) {
        _messages[index] = _messages[index].copyWith(
          mediaUrl: cloudinaryUrl,
          mediaDuration: serverDuration,
        );
        notifyListeners();
      }

      // 5. Delete temp file after successful upload (native only; web uses blob)
      if (!kIsWeb && localAudioPath != null) {
        await file_utils.deleteFileIfExists(localAudioPath);
      }

      // 6. Encrypt and send via WebSocket (URL hidden in envelope)
      _encryptAndSend(
        recipientId: recipientId,
        content: '',
        tempId: tempId,
        effectiveExpiresIn: effectiveExpiresIn,
        messageType: 'VOICE',
        mediaUrl: cloudinaryUrl,
        mediaDuration: serverDuration,
      );
    } catch (e) {
      debugPrint('[MessagingProvider] Voice upload failed: $e');
      _markMessageFailed(tempId, 'Failed to send voice message');
    }
  }

  /// Send a GIF message. Downloads from Giphy, uploads to Cloudinary, encrypts URL.
  Future<void> sendGif(
    String token,
    String gifUrl,
    int recipientId,
  ) async {
    final activeConversationId = _conversationsProvider?.activeConversationId;
    if (activeConversationId == null || _currentUserId == null) return;

    final effectiveExpiresIn =
        _conversationsProvider!.conversationDisappearingTimer;
    final tempId =
        'temp_${DateTime.now().millisecondsSinceEpoch}_$_currentUserId';

    // 1. Optimistic message
    final tempMessage = MessageModel(
      id: -(++MessagingProvider._tempIdSeq),
      content: '',
      senderId: _currentUserId!,
      senderUsername: '',
      conversationId: activeConversationId,
      createdAt: DateTime.now(),
      deliveryStatus: MessageDeliveryStatus.sending,
      messageType: MessageType.gif,
      expiresAt: effectiveExpiresIn != null
          ? DateTime.now().add(Duration(seconds: effectiveExpiresIn))
          : null,
      tempId: tempId,
    );

    _messages.add(tempMessage);
    _pendingSendContent[tempId] =
        <String, dynamic>{'content': '', 'messageType': 'GIF'};
    notifyListeners();

    try {
      // 2. Download GIF bytes from Giphy
      final response = await http.get(Uri.parse(gifUrl));
      if (response.statusCode != 200) {
        throw Exception('Failed to download GIF');
      }
      final gifBytes = response.bodyBytes;

      // 3. Size guard
      if (gifBytes.length > 5 * 1024 * 1024) {
        throw Exception('GIF too large (max 5 MB)');
      }

      // 4. Upload to Cloudinary
      final responseData = await _api.uploadMedia(
        token: token,
        type: 'gif',
        gifBytes: gifBytes,
        expiresIn: effectiveExpiresIn,
      );

      final cloudinaryUrl = responseData['mediaUrl'] as String;

      // 5. Update optimistic message with URL
      final idx = _messages.indexWhere((m) => m.tempId == tempId);
      if (idx != -1) {
        _messages[idx] = _messages[idx].copyWith(mediaUrl: cloudinaryUrl);
        notifyListeners();
      }

      // 6. Encrypt and send
      _encryptAndSend(
        recipientId: recipientId,
        content: '',
        tempId: tempId,
        effectiveExpiresIn: effectiveExpiresIn,
        messageType: 'GIF',
        mediaUrl: cloudinaryUrl,
      );
    } catch (e) {
      debugPrint('[MessagingProvider] GIF send failed: $e');
      _markMessageFailed(tempId, 'GIF send failed: ${e.toString()}');
    }
  }

  /// Send a file (document) message. Uploads to backend, then encrypts URL + filename in envelope.
  Future<void> sendFileMessage(
    String token,
    List<int> fileBytes,
    String fileName,
    String fileMimeType,
    int recipientId,
  ) async {
    final activeConversationId = _conversationsProvider?.activeConversationId;
    if (activeConversationId == null || _currentUserId == null) return;

    final effectiveExpiresIn =
        _conversationsProvider!.conversationDisappearingTimer;
    final tempId =
        'temp_${DateTime.now().millisecondsSinceEpoch}_$_currentUserId';

    final tempMessage = MessageModel(
      id: -(++MessagingProvider._tempIdSeq),
      content: fileName,
      senderId: _currentUserId!,
      senderUsername: '',
      conversationId: activeConversationId,
      createdAt: DateTime.now(),
      deliveryStatus: MessageDeliveryStatus.sending,
      messageType: MessageType.file,
      tempId: tempId,
    );

    _messages.add(tempMessage);
    _pendingSendContent[tempId] = <String, dynamic>{
      'content': fileName,
      'messageType': 'FILE',
    };
    notifyListeners();

    try {
      final responseData = await _api.uploadMedia(
        token: token,
        type: 'file',
        fileBytes: fileBytes,
        fileName: fileName,
        fileMimeType: fileMimeType,
      );

      final mediaUrl = responseData['mediaUrl'] as String;

      final idx = _messages.indexWhere((m) => m.tempId == tempId);
      if (idx != -1) {
        _messages[idx] = _messages[idx].copyWith(mediaUrl: mediaUrl);
        notifyListeners();
      }

      _pendingSendContent[tempId] = <String, dynamic>{
        'content': fileName,
        'messageType': 'FILE',
        'mediaUrl': mediaUrl,
      };

      _encryptAndSend(
        recipientId: recipientId,
        content: fileName,
        tempId: tempId,
        effectiveExpiresIn: effectiveExpiresIn,
        messageType: 'FILE',
        mediaUrl: mediaUrl,
      );
    } catch (e) {
      debugPrint('[MessagingProvider] File send failed: $e');
      _markMessageFailed(tempId, 'File send failed: ${e.toString()}');
    }
  }

  /// Anti-Quantum Note: encrypt client-side, POST to server, send URL as text message.
  Future<void> sendAntiQuantumNote({
    required String content,
    required int expiresInSeconds,
  }) async {
    final token = _tokenForReconnect;
    if (token == null) return;

    // AES-256-GCM client-side encryption using pointycastle
    final keyBytes = _secureRandomBytes(32);
    final ivBytes = _secureRandomBytes(12);

    final cipher = GCMBlockCipher(AESEngine());
    final params = AEADParameters(
      KeyParameter(keyBytes),
      128, // auth tag length in bits
      ivBytes,
      Uint8List(0),
    );
    cipher.init(true, params);

    final plainBytes = Uint8List.fromList(utf8.encode(content));
    final ciphertextWithTag = cipher.process(plainBytes);

    // Format: base64(iv):base64(ciphertext+tag)
    final ciphertextEncoded =
        '${base64.encode(ivBytes)}:${base64.encode(ciphertextWithTag)}';

    // POST /notes with ciphertext (server never sees key)
    final noteToken =
        await _api.createSecretNote(token, ciphertextEncoded, expiresInSeconds);

    // Key encoded as base64url for URL fragment (#KEY)
    final keyBase64Url = base64Url.encode(keyBytes);
    final noteUrl = '${AppConfig.baseUrl}/note/$noteToken#$keyBase64Url';

    // Send URL as a plain text message in the active conversation
    sendMessage(noteUrl);
  }

  Uint8List _secureRandomBytes(int length) {
    final random = FortunaRandom();
    final seedSource = Random.secure();
    final seeds = List<int>.generate(32, (_) => seedSource.nextInt(256));
    random.seed(KeyParameter(Uint8List.fromList(seeds)));
    return random.nextBytes(length);
  }

  // ---------- Message Actions ----------

  void markConversationRead(int conversationId) {
    _emit?.call('markConversationRead', {'conversationId': conversationId});
  }

  void clearChatHistory(int conversationId) {
    _emit?.call('clearChatHistory', {'conversationId': conversationId});
  }

  void deleteMessage(int messageId, {required bool forEveryone}) {
    _emit?.call('deleteMessage', {
      'messageId': messageId,
      'mode': forEveryone ? 'for_everyone' : 'for_me',
    });
  }

  void addReaction(int messageId, String emoji) {
    _emit?.call('addReaction', {'messageId': messageId, 'emoji': emoji});
  }

  void removeReaction(int messageId, String emoji) {
    _emit?.call('removeReaction', {'messageId': messageId, 'emoji': emoji});
  }

  void sendTypingIndicator(int recipientId, int conversationId) {
    _emit?.call('typing', {
      'recipientId': recipientId,
      'conversationId': conversationId,
    });
  }

  /// Emit typing for the active conversation.
  void emitTyping() {
    final activeConversationId = _conversationsProvider?.activeConversationId;
    if (activeConversationId == null || _currentUserId == null) return;
    final conversations = _conversationsProvider!.conversations;
    final conv =
        conversations.where((c) => c.id == activeConversationId).firstOrNull;
    if (conv == null) return;
    final recipientId = conv_helpers.getOtherUserId(conv, _currentUserId);
    sendTypingIndicator(recipientId, activeConversationId);
  }

  /// Remove messages whose expiresAt has passed. Called every second by ChatDetailScreen timer.
  void removeExpiredMessages() {
    final now = DateTime.now();
    final hadExpired = _messages.any(
      (m) => m.expiresAt != null && m.expiresAt!.isBefore(now),
    );
    if (!hadExpired) return;

    _messages.removeWhere(
      (m) => m.expiresAt != null && m.expiresAt!.isBefore(now),
    );
    // Also tell ConversationsProvider to clean expired lastMessages
    _conversationsProvider?.removeExpiredLastMessages();
    notifyListeners();
  }

  /// Retry sending a failed message (any type).
  Future<void> retryFailedMessage(String tempId) async {
    _cancelDelayedRetry(tempId);
    final index = _messages.indexWhere((m) => m.tempId == tempId);
    if (index == -1) return;
    final message = _messages[index];
    if (message.deliveryStatus != MessageDeliveryStatus.failed) return;

    final conversations = _conversationsProvider?.conversations ?? [];
    final conv =
        conversations.where((c) => c.id == message.conversationId).firstOrNull;
    if (conv == null) return;
    final recipientId = conv_helpers.getOtherUserId(conv, _currentUserId);

    if (message.messageType == MessageType.ping) {
      _messages[index] = _messages[index].copyWith(
        deliveryStatus: MessageDeliveryStatus.sending,
      );
      _pendingSendContent[tempId] =
          <String, dynamic>{'content': '', 'messageType': 'PING'};
      notifyListeners();
      _encryptAndSend(
        recipientId: recipientId,
        content: '',
        tempId: tempId,
        messageType: 'PING',
      );
      return;
    }

    if (message.messageType == MessageType.voice) {
      if (message.mediaUrl != null &&
          message.mediaUrl!.contains('cloudinary')) {
        _messages[index] = _messages[index].copyWith(
          deliveryStatus: MessageDeliveryStatus.sending,
        );
        _pendingSendContent[tempId] =
            <String, dynamic>{'content': '', 'messageType': 'VOICE'};
        notifyListeners();
        _encryptAndSend(
          recipientId: recipientId,
          content: '',
          tempId: tempId,
          messageType: 'VOICE',
          mediaUrl: message.mediaUrl,
          mediaDuration: message.mediaDuration,
        );
      } else {
        final localPath = message.mediaUrl;
        if (localPath == null || localPath.isEmpty) {
          return;
        }
        _messages[index] = _messages[index].copyWith(
          deliveryStatus: MessageDeliveryStatus.sending,
        );
        notifyListeners();
        await sendVoiceMessage(
          recipientId: recipientId,
          localAudioPath: localPath,
          duration: message.mediaDuration ?? 0,
          conversationId: message.conversationId,
        );
      }
      return;
    }

    if (message.messageType == MessageType.image) {
      if (message.mediaUrl != null &&
          message.mediaUrl!.contains('cloudinary')) {
        _messages[index] = _messages[index].copyWith(
          deliveryStatus: MessageDeliveryStatus.sending,
        );
        _pendingSendContent[tempId] =
            <String, dynamic>{'content': '', 'messageType': 'IMAGE'};
        notifyListeners();
        _encryptAndSend(
          recipientId: recipientId,
          content: '',
          tempId: tempId,
          messageType: 'IMAGE',
          mediaUrl: message.mediaUrl,
        );
      }
      return;
    }

    if (message.messageType == MessageType.file) {
      if (message.mediaUrl != null &&
          message.mediaUrl!.contains('cloudinary')) {
        _messages[index] = _messages[index].copyWith(
          deliveryStatus: MessageDeliveryStatus.sending,
        );
        _pendingSendContent[tempId] = <String, dynamic>{
          'content': message.content,
          'messageType': 'FILE',
          'mediaUrl': message.mediaUrl,
        };
        notifyListeners();
        _encryptAndSend(
          recipientId: recipientId,
          content: message.content,
          tempId: tempId,
          messageType: 'FILE',
          mediaUrl: message.mediaUrl,
        );
      }
      return;
    }

    if (message.messageType == MessageType.text) {
      final content = message.content;
      final conversationId = message.conversationId;
      _messages.removeAt(index);
      final stillInConv =
          _messages.where((m) => m.conversationId == conversationId).toList();
      if (stillInConv.isNotEmpty) {
        stillInConv.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        _conversationsProvider?.updateLastMessage(
            conversationId, stillInConv.last);
      } else {
        _conversationsProvider?.updateLastMessage(conversationId, null);
      }
      notifyListeners();
      final activeConversationId = _conversationsProvider?.activeConversationId;
      if (activeConversationId == conversationId && content.isNotEmpty) {
        sendMessage(content, replyToMessageId: message.replyToMessageId);
      }
    }
  }

  // ---------- Encrypt & Send ----------

  Future<void> _encryptAndSend({
    required int recipientId,
    required String content,
    required String tempId,
    int? effectiveExpiresIn,
    int? effectiveReplyToId,
    String messageType = 'TEXT',
    String? mediaUrl,
    int? mediaDuration,
  }) async {
    final e2eReady = _encryptionProvider?.isE2EReady ?? false;
    _e2eFlowLog('SEND_START', {
      'recipientId': recipientId,
      'e2eInitialized': e2eReady,
      'messageType': messageType,
    });
    if (!e2eReady) {
      _markMessageFailed(
        tempId,
        'Encryption not ready. Please wait and try again.',
      );
      return;
    }

    try {
      // 1. Fetch client-side link preview before encrypting (TEXT only)
      Map<String, String?>? linkPreview;
      if (messageType == 'TEXT') {
        try {
          if (kIsWeb && _tokenForReconnect != null) {
            linkPreview = await _api.fetchLinkPreview(
              _tokenForReconnect!,
              content,
            );
          } else {
            linkPreview = await LinkPreviewService.fetchPreview(content);
          }
        } catch (e) {
          debugPrint('[E2E] Link preview fetch failed (non-fatal): $e');
        }
      }

      // 2. Store all fields in pending content so _addMessageToState can restore them
      final pending = _pendingSendContent[tempId];
      if (pending != null) {
        pending['messageType'] = messageType;
        if (mediaUrl != null) pending['mediaUrl'] = mediaUrl;
        if (mediaDuration != null) pending['mediaDuration'] = mediaDuration;
        if (linkPreview != null) {
          if (linkPreview['url'] != null) {
            pending['linkPreviewUrl'] = linkPreview['url'];
          }
          if (linkPreview['title'] != null) {
            pending['linkPreviewTitle'] = linkPreview['title'];
          }
          if (linkPreview['imageUrl'] != null) {
            pending['linkPreviewImageUrl'] = linkPreview['imageUrl'];
          }
        }
      }

      // 3. Build encrypted envelope (content + type + media + optional linkPreview)
      final envelopeJson = jsonEncode(E2eEnvelope.build(
        content,
        messageType: messageType,
        mediaUrl: mediaUrl,
        mediaDuration: mediaDuration,
        linkPreview: linkPreview,
      ));

      // 4. Ensure session exists with recipient
      await _encryptionProvider!.ensureSession(recipientId);

      // 5. Encrypt
      final ciphertext =
          await _encryptionProvider!.encrypt(recipientId, envelopeJson);
      _e2eFlowLog('SEND_ENCRYPT_DONE', {
        'recipientId': recipientId,
        'ciphertextLength': ciphertext.length,
      });

      // 6. Send with encrypted content — server is blind to type/media
      _e2eFlowLog('SEND_EMIT', {'recipientId': recipientId});
      _emit?.call('sendMessage', {
        'recipientId': recipientId,
        'content': '[encrypted]',
        'encryptedContent': ciphertext,
        'expiresIn': effectiveExpiresIn,
        'tempId': tempId,
        'replyToMessageId': effectiveReplyToId,
      });
    } catch (e) {
      _encryptionProvider?.clearPendingPreKeyFetch(recipientId);
      debugPrint('[E2E] Encryption failed: $e');
      _e2eFlowLog('SEND_FAIL', {
        'recipientId': recipientId,
        'error': e.toString(),
      });
      final String userMsg = _userFriendlySendError(e, recipientId);
      _markMessageFailed(tempId, userMsg);
      if (_isKeyBundleOrTimeoutError(e)) {
        _scheduleDelayedRetry(tempId);
      }
    }
  }

  // ---------- Decrypt ----------

  Future<void> _decryptMessageHistory(int generation) async {
    final toDecrypt =
        _messages.where((m) => m.needsDecryption(_currentUserId)).length;
    if (toDecrypt > 0) {
      _e2eFlowLog('HISTORY_DECRYPT_START', {'count': toDecrypt});
    }
    // Double Ratchet requires decrypting in chronological order (oldest first).
    final sorted = List<MessageModel>.from(_messages)
      ..sort((a, b) {
        final byTime = a.createdAt.compareTo(b.createdAt);
        if (byTime != 0) return byTime;
        return a.id.compareTo(b.id);
      });
    bool changed = false;
    for (var i = 0; i < sorted.length; i++) {
      if (_decryptHistoryGeneration != generation) break;
      final msg = sorted[i];
      // Skip messages we already failed to decrypt
      if (msg.content == '[Decryption failed]') continue;
      if (msg.needsDecryption(_currentUserId)) {
        // Cache-first: check persisted cache before attempting live decryption.
        final cached = _encryptionProvider?.getCachedDecryption(msg.id);
        if (cached != null) {
          final idx = _messages.indexWhere((m) => m.id == msg.id);
          if (idx != -1) {
            _messages[idx] = cached;
            changed = true;
          }
          continue;
        }
        // _encryptionProvider is non-null here: this path is reached only when
        // isE2EReady is true, which requires the provider to be set.
        final persisted =
            await _encryptionProvider!.getDecryptedContent(msg.id);
        if (persisted != null &&
            (persisted['content'] as String? ?? '').isNotEmpty) {
          final safeImageUrl = persisted['linkPreviewImageUrl'] as String?;
          final safePageUrl = persisted['linkPreviewUrl'] as String?;
          final validImage = safeImageUrl != null &&
                  safePageUrl != null &&
                  LinkPreviewService.isSafeImageUrl(safeImageUrl, safePageUrl)
              ? safeImageUrl
              : null;
          final restoredType =
              _parseMessageTypeString(persisted['messageType'] as String?);
          final restored = msg.copyWith(
            content: persisted['content'] as String,
            messageType: restoredType,
            mediaUrl: persisted['mediaUrl'] as String?,
            mediaDuration: persisted['mediaDuration'] as int?,
            linkPreviewUrl: persisted['linkPreviewUrl'] as String?,
            linkPreviewTitle: persisted['linkPreviewTitle'] as String?,
            linkPreviewImageUrl: validImage,
          );
          _encryptionProvider?.cacheDecryption(msg.id, restored);
          final idx = _messages.indexWhere((m) => m.id == msg.id);
          if (idx != -1) {
            _messages[idx] = restored;
            changed = true;
          }
          continue;
        }
        // No cache — live decrypt (advances session ratchet)
        final decrypted = await _decryptMessageAsync(msg);
        final idx = _messages.indexWhere((m) => m.id == msg.id);
        if (idx != -1) {
          _messages[idx] = decrypted;
          changed = true;
        }
      } else if (msg.senderId == _currentUserId &&
          msg.content == '[encrypted]') {
        // _encryptionProvider is non-null here: own-message path requires E2E ready.
        final stored = await _encryptionProvider!.getDecryptedContent(msg.id);
        final storedContent = stored?['content'] as String? ?? '';
        if (storedContent.isNotEmpty ||
            (stored?['messageType'] as String?) != null) {
          // Restore all fields from persisted cache (SSRF validated)
          final rawImageUrl = stored?['linkPreviewImageUrl'] as String?;
          final rawPageUrl = stored?['linkPreviewUrl'] as String?;
          final safeImageUrl = rawImageUrl != null &&
                  rawPageUrl != null &&
                  LinkPreviewService.isSafeImageUrl(rawImageUrl, rawPageUrl)
              ? rawImageUrl
              : null;
          final restoredType =
              _parseMessageTypeString(stored?['messageType'] as String?);
          final restored = msg.copyWith(
            content: storedContent.isNotEmpty ? storedContent : null,
            messageType: restoredType,
            mediaUrl: stored?['mediaUrl'] as String?,
            mediaDuration: stored?['mediaDuration'] as int?,
            linkPreviewUrl: stored?['linkPreviewUrl'] as String?,
            linkPreviewTitle: stored?['linkPreviewTitle'] as String?,
            linkPreviewImageUrl: safeImageUrl,
          );
          final idx = _messages.indexWhere((m) => m.id == msg.id);
          if (idx != -1) {
            _messages[idx] = restored;
            changed = true;
          }
        }
      }
    }
    if (changed) _e2eFlowLog('HISTORY_DECRYPT_DONE', {'changed': true});
    if (changed) notifyListeners();
  }

  Future<MessageModel> _decryptMessageAsync(MessageModel msg) async {
    // Own messages: server stored "[encrypted]" as content but we already
    // showed plaintext optimistically, so skip decryption for our own messages.
    if (msg.senderId == _currentUserId) return msg;

    if (!(_encryptionProvider?.isE2EReady ?? false)) {
      return msg.copyWith(content: '[Encryption not initialized]');
    }

    _e2eFlowLog(
        'DECRYPT_START', {'msgId': msg.id, 'senderId': msg.senderId});
    try {
      final plaintext = await _encryptionProvider!.decrypt(
        msg.senderId,
        msg.encryptedContent!,
      );
      try {
        final parsed = E2eEnvelope.parse(plaintext);
        _e2eFlowLog('DECRYPT_OK', {
          'msgId': msg.id,
          'contentLength': parsed.content.length,
        });
        // SSRF: validate imageUrl before storing
        final safeImageUrl = parsed.linkPreviewImageUrl != null &&
                parsed.linkPreviewUrl != null &&
                LinkPreviewService.isSafeImageUrl(
                  parsed.linkPreviewImageUrl,
                  parsed.linkPreviewUrl,
                )
            ? parsed.linkPreviewImageUrl
            : null;
        final parsedType = _parseMessageTypeString(parsed.messageType);
        final decryptedMsg = msg.copyWith(
          content: parsed.content,
          messageType: parsedType,
          mediaUrl: parsed.mediaUrl,
          mediaDuration: parsed.mediaDuration,
          linkPreviewUrl: parsed.linkPreviewUrl,
          linkPreviewTitle: parsed.linkPreviewTitle,
          linkPreviewImageUrl: safeImageUrl,
        );
        // Trigger ping effect for recipient when decrypted type is PING
        if (parsedType == MessageType.ping &&
            msg.senderId != _currentUserId) {
          _showPingEffect = true;
        }
        _encryptionProvider?.cacheDecryption(msg.id, decryptedMsg);
        await _persistDecryptedContent(decryptedMsg);
        return decryptedMsg;
      } catch (parseErr) {
        debugPrint(
            '[E2E] Envelope parse failed for msg ${msg.id}, using raw plaintext: $parseErr');
        final fallback = msg.copyWith(content: plaintext);
        _encryptionProvider?.cacheDecryption(msg.id, fallback);
        if (plaintext.isNotEmpty) await _persistDecryptedContent(fallback);
        return fallback;
      }
    } catch (e) {
      // DuplicateMessageException: session was already advanced. Use cache.
      final cached = _encryptionProvider?.getCachedDecryption(msg.id);
      if (cached != null) return cached;
      // _encryptionProvider is non-null here: catch path reached only during
      // active decryption, which requires E2E to be initialized.
      final persisted =
          await _encryptionProvider!.getDecryptedContent(msg.id);
      final persistedContent = persisted?['content'] as String? ?? '';
      if (persisted != null && persistedContent.isNotEmpty) {
        final rawImageUrl = persisted['linkPreviewImageUrl'] as String?;
        final rawPageUrl = persisted['linkPreviewUrl'] as String?;
        final safeImageUrl = rawImageUrl != null &&
                rawPageUrl != null &&
                LinkPreviewService.isSafeImageUrl(rawImageUrl, rawPageUrl)
            ? rawImageUrl
            : null;
        final restoredType =
            _parseMessageTypeString(persisted['messageType'] as String?);
        final restored = msg.copyWith(
          content: persistedContent,
          messageType: restoredType,
          mediaUrl: persisted['mediaUrl'] as String?,
          mediaDuration: persisted['mediaDuration'] as int?,
          linkPreviewUrl: persisted['linkPreviewUrl'] as String?,
          linkPreviewTitle: persisted['linkPreviewTitle'] as String?,
          linkPreviewImageUrl: safeImageUrl,
        );
        _encryptionProvider?.cacheDecryption(msg.id, restored);
        return restored;
      }
      debugPrint('[E2E] Decrypt failed for msg ${msg.id}: $e');
      _e2eFlowLog(
          'DECRYPT_FAIL', {'msgId': msg.id, 'error': e.toString()});
      // For live incoming messages (not history replay): mark for session rebuild
      if (!_decryptingHistory) {
        _encryptionProvider?.markSessionRebuild(msg.senderId);
        _emit?.call('requestSessionRebuild', {'recipientId': msg.senderId});
        _e2eFlowLog('SESSION_RESET', {'peerId': msg.senderId});
      }
      return msg.copyWith(content: '[Decryption failed]');
    }
  }

  // ---------- Internal Helpers ----------

  void _markMessageFailed(String tempId, String errorMsg) {
    final idx = _messages.indexWhere((m) => m.tempId == tempId);
    if (idx != -1) {
      _messages[idx] = _messages[idx].copyWith(
        deliveryStatus: MessageDeliveryStatus.failed,
      );
    }
    notifyListeners();
  }

  /// Mark any message currently in "sending" state as failed.
  void markSendingMessagesFailed(String errorMsg) {
    final sending = _messages
        .where((m) => m.deliveryStatus == MessageDeliveryStatus.sending)
        .toList();
    if (sending.isEmpty) return;
    sending.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final last = sending.first;
    final idx = _messages.indexWhere((m) => m.tempId == last.tempId);
    if (idx != -1) {
      _messages[idx] = _messages[idx].copyWith(
        deliveryStatus: MessageDeliveryStatus.failed,
      );
    }
  }

  bool _isKeyBundleOrTimeoutError(Object e) {
    final s = e.toString();
    return s.contains('key bundle') ||
        s.contains('no key bundle') ||
        s.contains('timed out') ||
        s.contains('Timeout') ||
        e is TimeoutException;
  }

  void _cancelDelayedRetry(String? tempId) {
    if (tempId != null && _delayedRetryTempId == tempId) {
      _delayedRetryTimer?.cancel();
      _delayedRetryTimer = null;
      _delayedRetryTempId = null;
    }
  }

  void _cancelDelayedRetryIfAny() {
    _delayedRetryTimer?.cancel();
    _delayedRetryTimer = null;
    _delayedRetryTempId = null;
  }

  void _scheduleDelayedRetry(String tempId) {
    _delayedRetryTimer?.cancel();
    _delayedRetryTempId = tempId;
    _delayedRetryTimer = Timer(const Duration(seconds: 4), () {
      _delayedRetryTimer = null;
      final tid = _delayedRetryTempId;
      _delayedRetryTempId = null;
      if (tid != null) _retrySendInPlace(tid);
      notifyListeners();
    });
  }

  void _retrySendInPlace(String tempId) {
    final idx = _messages.indexWhere((m) => m.tempId == tempId);
    if (idx == -1) return;
    final message = _messages[idx];
    if (message.deliveryStatus != MessageDeliveryStatus.failed) {
      return;
    }
    // Only auto-retry text and ping
    if (message.messageType != MessageType.text &&
        message.messageType != MessageType.ping) {
      return;
    }
    if (message.messageType == MessageType.text && message.content.isEmpty) {
      return;
    }
    final conversations = _conversationsProvider?.conversations ?? [];
    final convList =
        conversations.where((c) => c.id == message.conversationId).toList();
    if (convList.isEmpty) return;
    final conv = convList.first;
    final recipientId = conv_helpers.getOtherUserId(conv, _currentUserId);
    int? effectiveExpiresIn;
    if (message.expiresAt != null) {
      final secs = message.expiresAt!.difference(DateTime.now()).inSeconds;
      effectiveExpiresIn = secs.clamp(1, 86400 * 30);
    } else {
      effectiveExpiresIn = conv.disappearingTimer;
    }
    _messages[idx] =
        message.copyWith(deliveryStatus: MessageDeliveryStatus.sending);
    notifyListeners();
    _encryptAndSend(
      recipientId: recipientId,
      content: message.content,
      tempId: tempId,
      effectiveExpiresIn: effectiveExpiresIn,
      effectiveReplyToId: message.replyToMessageId,
      messageType: message.messageType.name.toUpperCase(),
    );
  }

  /// Parse a message type string from envelope/persisted data into MessageType enum.
  MessageType? _parseMessageTypeString(String? type) {
    switch (type) {
      case 'TEXT':
        return MessageType.text;
      case 'PING':
        return MessageType.ping;
      case 'VOICE':
        return MessageType.voice;
      case 'IMAGE':
        return MessageType.image;
      case 'GIF':
        return MessageType.gif;
      case 'FILE':
        return MessageType.file;
      default:
        return null;
    }
  }

  /// User-friendly error when encrypt/send fails.
  String _userFriendlySendError(Object e, int recipientId) {
    final s = e.toString();
    if (s.contains('Recipient has no key bundle') ||
        s.contains('no key bundle')) {
      final conversations = _conversationsProvider?.conversations ?? [];
      final otherName = conversations
          .where((c) =>
              conv_helpers.getOtherUserId(c, _currentUserId) == recipientId)
          .map((c) => conv_helpers.getOtherUserUsername(c, _currentUserId))
          .firstOrNull;
      final who = otherName ?? 'Recipient';
      return 'Cannot send: $who does not have encryption keys yet. Ask them to open the app.';
    }
    if (e is TimeoutException ||
        s.contains('timed out') ||
        s.contains('Timeout')) {
      return 'Timed out waiting for recipient keys. Try again.';
    }
    if (!(_encryptionProvider?.isE2EReady ?? false)) {
      return 'Encryption not ready. Wait a moment and try again.';
    }
    return 'Cannot send encrypted message. Recipient may not have encryption enabled – ask them to open the app.';
  }

  // ---------- Lifecycle ----------

  /// Called on socket connect. Clears message state for fresh connect,
  /// preserves for reconnect (same user).
  void onConnect(bool isReconnect) {
    _decryptHistoryGeneration++; // cancel any in-flight history decrypt

    if (!isReconnect) {
      // Fresh connect or switch user: clear ALL message state
      _messages = [];
      _deletedMessageIds.clear();
      _typingStatus.clear();
      for (final t in _typingTimers.values) {
        t.cancel();
      }
      _typingTimers.clear();
      _partnerRecordingVoice.clear();
      _replyingToMessage = null;
      _pendingSendContent.clear();
      _incomingMessageQueue.clear();
      _cancelDelayedRetryIfAny();
    } else {
      // Reconnect (same user): keep messages to avoid flicker.
      // Clear typing/recording indicators (stale after reconnect).
      _typingStatus.clear();
      for (final t in _typingTimers.values) {
        t.cancel();
      }
      _typingTimers.clear();
      _partnerRecordingVoice.clear();
      _replyingToMessage = null;
      _cancelDelayedRetryIfAny();
    }

    notifyListeners();
  }

  /// Called on socket disconnect. Cancels timers.
  void onDisconnect() {
    _cancelDelayedRetryIfAny();
    for (final t in _typingTimers.values) {
      t.cancel();
    }
    _typingTimers.clear();
  }

  /// Full reset — called on logout / account deletion.
  void clearAll() {
    _messages = [];
    _deletedMessageIds.clear();
    _typingStatus.clear();
    for (final t in _typingTimers.values) {
      t.cancel();
    }
    _typingTimers.clear();
    _partnerRecordingVoice.clear();
    _replyingToMessage = null;
    _showPingEffect = false;
    _pendingSendContent.clear();
    _incomingMessageQueue.clear();
    _decryptingHistory = false;
    _decryptHistoryGeneration++;
    _cancelDelayedRetryIfAny();
    _currentUserId = null;
    _tokenForReconnect = null;
    notifyListeners();
  }

  /// Clear messages for the active conversation (used when clearing active chat).
  void clearMessages() {
    _messages = [];
    notifyListeners();
  }
}
