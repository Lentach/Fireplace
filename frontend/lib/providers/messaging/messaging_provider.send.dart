part of '../messaging_provider.dart';

// These extension methods live in MessagingProvider's own library and operate on
// its private state, so calling the ChangeNotifier's `notifyListeners()` here is
// legitimate; the analyzer's protected / visible-for-testing checks (which assume
// the call sits in a ChangeNotifier subclass body, not an extension) don't apply.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

/// Optimistic send, encrypt-&-send, send-retry, and typing emit.
extension MessagingSend on MessagingProvider {
  void sendMessage(String content, {int? expiresIn, int? replyToMessageId}) {
    final activeConversationId = _conversationsProvider?.activeConversationId;
    if (activeConversationId == null || _currentUserId == null) return;

    final conversations = _conversationsProvider!.conversations;
    // firstOrNull, NOT firstWhere: a stale active id (e.g. a notification for
    // a deleted conversation) must not throw before the optimistic add — the
    // old StateError here ate typed messages silently.
    final conv =
        conversations.where((c) => c.id == activeConversationId).firstOrNull;
    if (conv == null) return;
    final recipientId = conv_helpers.getOtherUserId(conv, _currentUserId);

    // Use conversation disappearing timer if expiresIn not provided
    final effectiveExpiresIn =
        expiresIn ?? _conversationsProvider!.conversationDisappearingTimer;
    final effectiveReplyToId = replyToMessageId ?? _replyingToMessage?.id;
    final replyPreview = _buildReplyPreviewFromReplyingTo();

    // Generate unique tempId for optimistic message matching
    final tempId =
        'temp_${DateTime.now().millisecondsSinceEpoch}_$_currentUserId';

    // Create optimistic message with SENDING status
    final tempMessage = MessageModel(
      id: -(++MessagingProvider._tempIdSeq), // Monotonic temporary negative ID
      content: content,
      senderId: _currentUserId!,
      senderUsername: '', // Will be replaced when server confirms
      conversationId: activeConversationId,
      createdAt: DateTime.now(),
      deliveryStatus: MessageDeliveryStatus.sending,
      disappearAfterSeconds: effectiveExpiresIn,
      expiresAt: null,
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
      disappearAfterSeconds: effectiveExpiresIn,
      expiresAt: null,
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

  /// Returns true only AFTER the image's `sendMessage` socket emit (spec
  /// §3 ordering contract) — callers sequencing a caption must await this.
  /// False = failed before emit (no conversation, oversize, upload/encrypt
  /// failure); the optimistic bubble is marked failed internally.
  Future<bool> sendImageMessage(
    String token,
    XFile imageFile,
    int recipientId,
  ) async {
    final activeConversationId = _conversationsProvider?.activeConversationId;
    if (activeConversationId == null || _currentUserId == null) return false;

    final effectiveExpiresIn =
        _conversationsProvider!.conversationDisappearingTimer;
    final tempId =
        'temp_${DateTime.now().millisecondsSinceEpoch}_$_currentUserId';
    final effectiveReplyToId = _replyingToMessage?.id;

    _messages.add(_buildOptimisticMediaMessage(
      tempId: tempId,
      conversationId: activeConversationId,
      messageType: MessageType.image,
      content: '',
      effectiveExpiresIn: effectiveExpiresIn,
      effectiveReplyToId: effectiveReplyToId,
    ));
    _pendingSendContent[tempId] =
        <String, dynamic>{'content': '', 'messageType': 'IMAGE'};
    _clearReplyingToAfterSendStart();
    notifyListeners();

    try {
      final rawBytes = await imageFile.readAsBytes();
      if (rawBytes.length > MediaCryptoService.maxBytes) {
        _markMessageFailed(tempId, 'Image too large (max 20 MB)');
        return false;
      }
      final upload = await _mediaUpload.encryptAndUpload(
        bytes: Uint8List.fromList(rawBytes),
        token: token,
        mediaType: 'image',
        expiresIn: effectiveExpiresIn,
        onEncrypted: (key, iv) {
          _pendingSendContent[tempId] = <String, dynamic>{
            'content': '',
            'messageType': 'IMAGE',
            'mediaKey': key,
            'mediaIv': iv,
          };
        },
      );
      _pendingSendContent[tempId]!['mediaUrl'] = upload.mediaUrl;

      final idx = _messages.indexWhere((m) => m.tempId == tempId);
      if (idx != -1) {
        _messages[idx] = _messages[idx].copyWith(
          mediaUrl: upload.mediaUrl,
          mediaKey: upload.keyBase64,
          mediaIv: upload.ivBase64,
        );
        notifyListeners();
      }

      return await _encryptAndSend(
        recipientId: recipientId,
        content: '',
        tempId: tempId,
        effectiveExpiresIn: effectiveExpiresIn,
        effectiveReplyToId: effectiveReplyToId,
        messageType: 'IMAGE',
        mediaUrl: upload.mediaUrl,
        mediaKey: upload.keyBase64,
        mediaIv: upload.ivBase64,
      );
    } catch (e) {
      debugPrint('[MessagingProvider] Image upload failed: $e');
      _markMessageFailed(tempId, 'Image upload failed: ${e.toString()}');
      return false;
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
    if (_currentUserId == null) {
      throw StateError('Cannot send voice message: not authenticated');
    }

    // Use provided conversationId or active one
    final effectiveConvId =
        conversationId ?? _conversationsProvider?.activeConversationId;
    if (effectiveConvId == null) {
      throw StateError('Cannot send voice message: no active conversation');
    }

    final tempId =
        'temp_${DateTime.now().millisecondsSinceEpoch}_$_currentUserId';
    final effectiveReplyToId = _replyingToMessage?.id;
    // Get disappearing timer from conversation (null-safe: stale conv id must
    // not throw mid-send, same reasoning as sendMessage).
    final conversations = _conversationsProvider!.conversations;
    final conv =
        conversations.where((c) => c.id == effectiveConvId).firstOrNull;
    final effectiveExpiresIn = conv?.disappearingTimer;

    final optimisticMessage = _buildOptimisticMediaMessage(
      tempId: tempId,
      conversationId: effectiveConvId,
      messageType: MessageType.voice,
      content: '',
      effectiveExpiresIn: effectiveExpiresIn,
      effectiveReplyToId: effectiveReplyToId,
      mediaUrl: localAudioPath ?? '',
      mediaDuration: duration,
    );

    _messages.add(optimisticMessage);
    _pendingSendContent[tempId] =
        <String, dynamic>{'content': '', 'messageType': 'VOICE'};
    _conversationsProvider?.updateLastMessage(effectiveConvId, optimisticMessage);
    _clearReplyingToAfterSendStart();
    notifyListeners();

    try {
      if (_tokenForReconnect == null) {
        throw Exception('No authentication token available');
      }

      final List<int> rawBytes;
      if (localAudioBytes != null) {
        rawBytes = localAudioBytes;
      } else if (localAudioPath != null) {
        rawBytes = await file_utils.readFileBytes(localAudioPath);
      } else {
        throw Exception('Either localAudioPath or localAudioBytes required');
      }
      if (rawBytes.length > MediaCryptoService.maxBytes) {
        throw Exception('Voice file too large');
      }

      final upload = await _mediaUpload.encryptAndUpload(
        bytes: Uint8List.fromList(rawBytes),
        token: _tokenForReconnect!,
        mediaType: 'voice',
        duration: duration,
        expiresIn: effectiveExpiresIn,
        onEncrypted: (key, iv) {
          _pendingSendContent[tempId] = <String, dynamic>{
            'content': '',
            'messageType': 'VOICE',
            'mediaDuration': duration,
            'mediaKey': key,
            'mediaIv': iv,
          };
        },
      );

      final serverDuration = upload.mediaDuration ?? duration;
      _pendingSendContent[tempId]!['mediaUrl'] = upload.mediaUrl;

      final index = _messages.indexWhere((m) => m.tempId == tempId);
      if (index != -1) {
        _messages[index] = _messages[index].copyWith(
          mediaUrl: upload.mediaUrl,
          mediaDuration: serverDuration,
          mediaKey: upload.keyBase64,
          mediaIv: upload.ivBase64,
        );
        notifyListeners();
      }

      if (!kIsWeb && localAudioPath != null) {
        await file_utils.deleteFileIfExists(localAudioPath);
      }

      _encryptAndSend(
        recipientId: recipientId,
        content: '',
        tempId: tempId,
        effectiveExpiresIn: effectiveExpiresIn,
        effectiveReplyToId: effectiveReplyToId,
        messageType: 'VOICE',
        mediaUrl: upload.mediaUrl,
        mediaDuration: serverDuration,
        mediaKey: upload.keyBase64,
        mediaIv: upload.ivBase64,
      );
    } catch (e) {
      debugPrint('[MessagingProvider] Voice upload failed: $e');
      _markMessageFailed(tempId, 'Failed to send voice message');
    }
  }

  /// Send a GIF message. Downloads from Giphy, encrypts bytes, uploads blob, E2E envelope.
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
    final effectiveReplyToId = _replyingToMessage?.id;
    // 1. Optimistic message
    _messages.add(_buildOptimisticMediaMessage(
      tempId: tempId,
      conversationId: activeConversationId,
      messageType: MessageType.gif,
      content: '',
      effectiveExpiresIn: effectiveExpiresIn,
      effectiveReplyToId: effectiveReplyToId,
    ));
    _pendingSendContent[tempId] =
        <String, dynamic>{'content': '', 'messageType': 'GIF'};
    _clearReplyingToAfterSendStart();
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

      final upload = await _mediaUpload.encryptAndUpload(
        bytes: Uint8List.fromList(gifBytes),
        token: token,
        mediaType: 'gif',
        expiresIn: effectiveExpiresIn,
        onEncrypted: (key, iv) {
          _pendingSendContent[tempId] = <String, dynamic>{
            'content': '',
            'messageType': 'GIF',
            'mediaKey': key,
            'mediaIv': iv,
          };
        },
      );
      _pendingSendContent[tempId]!['mediaUrl'] = upload.mediaUrl;

      final idx = _messages.indexWhere((m) => m.tempId == tempId);
      if (idx != -1) {
        _messages[idx] = _messages[idx].copyWith(
          mediaUrl: upload.mediaUrl,
          mediaKey: upload.keyBase64,
          mediaIv: upload.ivBase64,
        );
        notifyListeners();
      }

      _encryptAndSend(
        recipientId: recipientId,
        content: '',
        tempId: tempId,
        effectiveExpiresIn: effectiveExpiresIn,
        effectiveReplyToId: effectiveReplyToId,
        messageType: 'GIF',
        mediaUrl: upload.mediaUrl,
        mediaKey: upload.keyBase64,
        mediaIv: upload.ivBase64,
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
    final effectiveReplyToId = _replyingToMessage?.id;
    _messages.add(_buildOptimisticMediaMessage(
      tempId: tempId,
      conversationId: activeConversationId,
      messageType: MessageType.file,
      content: fileName,
      effectiveExpiresIn: effectiveExpiresIn,
      effectiveReplyToId: effectiveReplyToId,
    ));
    _pendingSendContent[tempId] = <String, dynamic>{
      'content': fileName,
      'messageType': 'FILE',
    };
    _clearReplyingToAfterSendStart();
    notifyListeners();

    try {
      if (fileBytes.length > MediaCryptoService.maxBytes) {
        _markMessageFailed(tempId, 'File too large (max 20 MB)');
        return;
      }

      final upload = await _mediaUpload.encryptAndUpload(
        bytes: Uint8List.fromList(fileBytes),
        token: token,
        mediaType: 'file',
        fileName: fileName,
        onEncrypted: (key, iv) {
          _pendingSendContent[tempId] = <String, dynamic>{
            'content': fileName,
            'messageType': 'FILE',
            'mediaKey': key,
            'mediaIv': iv,
          };
        },
      );
      _pendingSendContent[tempId]!['mediaUrl'] = upload.mediaUrl;

      final idx = _messages.indexWhere((m) => m.tempId == tempId);
      if (idx != -1) {
        _messages[idx] = _messages[idx].copyWith(
          mediaUrl: upload.mediaUrl,
          mediaKey: upload.keyBase64,
          mediaIv: upload.ivBase64,
        );
        notifyListeners();
      }

      _encryptAndSend(
        recipientId: recipientId,
        content: fileName,
        tempId: tempId,
        effectiveExpiresIn: effectiveExpiresIn,
        effectiveReplyToId: effectiveReplyToId,
        messageType: 'FILE',
        mediaUrl: upload.mediaUrl,
        mediaKey: upload.keyBase64,
        mediaIv: upload.ivBase64,
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

    // AES-256-GCM client-side encryption via WebCrypto / BoringSSL
    final keyBytes = Uint8List(32);
    fillRandomBytes(keyBytes);
    final ivBytes = Uint8List(12);
    fillRandomBytes(ivBytes);

    final aesKey = await AesGcmSecretKey.importRawKey(keyBytes);
    final plainBytes = Uint8List.fromList(utf8.encode(content));
    final ciphertextWithTag = await aesKey.encryptBytes(plainBytes, ivBytes);

    // Format: base64(iv):base64(ciphertext+tag)
    final ciphertextEncoded =
        '${base64.encode(ivBytes)}:${base64.encode(Uint8List.fromList(ciphertextWithTag))}';

    // POST /notes with ciphertext (server never sees key)
    final noteToken =
        await _api.createSecretNote(token, ciphertextEncoded, expiresInSeconds);

    // Key encoded as base64url for URL fragment (#KEY). The fragment also
    // carries c=<convId> (reveal page's "Open Fireplace" deep link back into
    // this chat) and e=<expiry epoch ms> (in-chat self-destruct countdown).
    // Fragments never travel in HTTP requests — the server sees none of it.
    final keyBase64Url = base64Url.encode(keyBytes);
    final convId = _conversationsProvider?.activeConversationId;
    final expiresAtMs = DateTime.now()
        .add(Duration(seconds: expiresInSeconds))
        .millisecondsSinceEpoch;
    final fragmentParams =
        '${convId != null ? '&c=$convId' : ''}&e=$expiresAtMs';
    final noteUrl =
        '${AppConfig.baseUrl}/note/$noteToken#$keyBase64Url$fragmentParams';

    // Send URL as a text message. Notes ignore the conversation's disappearing
    // timer: the carrying message expires with the NOTE's TTL instead, so the
    // banner leaves chat history in step with the note's own destruction.
    sendMessage(noteUrl, expiresIn: expiresInSeconds);
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
      final vUrl = message.mediaUrl;
      final vKey = message.mediaKey;
      final vIv = message.mediaIv;
      // After encrypt+upload, blob URL and keys live on the model — retry E2E send only.
      if (vUrl != null &&
          vUrl.isNotEmpty &&
          vKey != null &&
          vIv != null &&
          vUrl.startsWith('http')) {
        _messages[index] = _messages[index].copyWith(
          deliveryStatus: MessageDeliveryStatus.sending,
        );
        _pendingSendContent[tempId] = <String, dynamic>{
          'content': '',
          'messageType': 'VOICE',
          'mediaUrl': vUrl,
          'mediaDuration': message.mediaDuration,
          'mediaKey': vKey,
          'mediaIv': vIv,
        };
        notifyListeners();
        _encryptAndSend(
          recipientId: recipientId,
          content: '',
          tempId: tempId,
          effectiveExpiresIn: conv.disappearingTimer,
          messageType: 'VOICE',
          mediaUrl: vUrl,
          mediaDuration: message.mediaDuration,
          mediaKey: vKey,
          mediaIv: vIv,
        );
        return;
      }
      if (message.mediaUrl != null &&
          (message.mediaUrl!.contains('cloudinary') ||
              message.mediaUrl!.contains('/media/'))) {
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
      final iUrl = message.mediaUrl;
      final iKey = message.mediaKey;
      final iIv = message.mediaIv;
      if (iUrl != null &&
          iUrl.isNotEmpty &&
          iKey != null &&
          iIv != null) {
        _messages[index] = _messages[index].copyWith(
          deliveryStatus: MessageDeliveryStatus.sending,
        );
        _pendingSendContent[tempId] = <String, dynamic>{
          'content': '',
          'messageType': 'IMAGE',
          'mediaUrl': iUrl,
          'mediaKey': iKey,
          'mediaIv': iIv,
        };
        notifyListeners();
        _encryptAndSend(
          recipientId: recipientId,
          content: '',
          tempId: tempId,
          effectiveExpiresIn: conv.disappearingTimer,
          messageType: 'IMAGE',
          mediaUrl: iUrl,
          mediaKey: iKey,
          mediaIv: iIv,
        );
        return;
      }
      if (message.mediaUrl != null &&
          (message.mediaUrl!.contains('cloudinary') ||
              message.mediaUrl!.contains('/media/'))) {
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

    if (message.messageType == MessageType.gif) {
      final gUrl = message.mediaUrl;
      final gKey = message.mediaKey;
      final gIv = message.mediaIv;
      if (gUrl != null &&
          gUrl.isNotEmpty &&
          gKey != null &&
          gIv != null) {
        _messages[index] = _messages[index].copyWith(
          deliveryStatus: MessageDeliveryStatus.sending,
        );
        _pendingSendContent[tempId] = <String, dynamic>{
          'content': '',
          'messageType': 'GIF',
          'mediaUrl': gUrl,
          'mediaKey': gKey,
          'mediaIv': gIv,
        };
        notifyListeners();
        _encryptAndSend(
          recipientId: recipientId,
          content: '',
          tempId: tempId,
          effectiveExpiresIn: conv.disappearingTimer,
          messageType: 'GIF',
          mediaUrl: gUrl,
          mediaKey: gKey,
          mediaIv: gIv,
        );
      }
      return;
    }

    if (message.messageType == MessageType.file) {
      final fUrl = message.mediaUrl;
      final fKey = message.mediaKey;
      final fIv = message.mediaIv;
      final fileName = message.content;
      if (fUrl != null &&
          fUrl.isNotEmpty &&
          fKey != null &&
          fIv != null) {
        _messages[index] = _messages[index].copyWith(
          deliveryStatus: MessageDeliveryStatus.sending,
        );
        _pendingSendContent[tempId] = <String, dynamic>{
          'content': fileName,
          'messageType': 'FILE',
          'mediaUrl': fUrl,
          'mediaKey': fKey,
          'mediaIv': fIv,
        };
        notifyListeners();
        _encryptAndSend(
          recipientId: recipientId,
          content: fileName,
          tempId: tempId,
          effectiveExpiresIn: conv.disappearingTimer,
          messageType: 'FILE',
          mediaUrl: fUrl,
          mediaKey: fKey,
          mediaIv: fIv,
        );
        return;
      }
      if (message.mediaUrl != null &&
          (message.mediaUrl!.contains('cloudinary') ||
              message.mediaUrl!.contains('/media/'))) {
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

  Future<bool> _encryptAndSend({
    required int recipientId,
    required String content,
    required String tempId,
    int? effectiveExpiresIn,
    int? effectiveReplyToId,
    String messageType = 'TEXT',
    String? mediaUrl,
    int? mediaDuration,
    String? mediaKey,
    String? mediaIv,
  }) async {
    final e2eReady = _encryptionProvider?.isE2EReady ?? false;
    _e2eFlowLog('SEND_START', {
      'recipientId': recipientId,
      'e2eInitialized': e2eReady,
      'messageType': messageType,
      'tempId': tempId,
    });
    if (!e2eReady) {
      _logMediaOrphanLikely(tempId, mediaUrl);
      _markMessageFailed(
        tempId,
        'Encryption not ready. Please wait and try again.',
      );
      return false;
    }

    // Exactly-once per tempId: a second attempt for the same optimistic
    // message must not even ENCRYPT (each encrypt advances the Double Ratchet
    // and hands the recipient a duplicate they may fail on). Latched for the
    // whole attempt; released by _markMessageFailed so a deliberate user
    // retry of a FAILED message still goes through.
    if (!_emittedSendTempIds.add(tempId)) {
      _e2eFlowLog('SEND_DUPLICATE_BLOCKED', {
        'recipientId': recipientId,
        'tempId': tempId,
      });
      return false;
    }

    try {
      // 1. Fetch client-side link preview before encrypting (TEXT only).
      // Anti-Quantum Note links skip previews entirely: the chat renders a
      // dedicated banner card instead, so fetching our own landing page is a
      // wasted round trip on both platforms.
      Map<String, String?>? linkPreview;
      final firstUrl = messageType == 'TEXT'
          ? LinkPreviewService.extractFirstUrl(content)
          : null;
      if (firstUrl != null && !isAntiQuantumNoteUrl(firstUrl)) {
        try {
          if (kIsWeb && _tokenForReconnect != null) {
            // Web goes through the backend proxy (CORS). E2E hygiene: send it
            // ONLY the fragment-stripped first URL, never the message text —
            // plaintext must not reach the server, and URL fragments can hold
            // secrets (Anti-Quantum Note keys ride in `#<key>`).
            linkPreview = await _api.fetchLinkPreview(
              _tokenForReconnect!,
              LinkPreviewService.stripFragment(firstUrl),
            );
            // Preview is for the link as written: restore the full URL so
            // the preview-card tap keeps the fragment (note key).
            if (linkPreview != null) linkPreview['url'] = firstUrl;
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
        if (mediaKey != null) pending['mediaKey'] = mediaKey;
        if (mediaIv != null) pending['mediaIv'] = mediaIv;
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
        mediaKey: mediaKey,
        mediaIv: mediaIv,
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
        // 3 = PreKey (session (re)built), 2 = whisper. A 3 mid-conversation
        // means a spurious rebuild — a prime suspect for peer decrypt failure.
        'ctype': ciphertext.contains(':')
            ? ciphertext.substring(0, ciphertext.indexOf(':'))
            : '?',
      });

      // 5b. Durable lost-ack insurance: snapshot the plaintext payload keyed
      // by the EXACT emitted ciphertext. If the `messageSent` ack is lost to a
      // socket drop (tempId→realId mapping never happens), the history merge
      // reconciles the '[encrypted]' server row back to this snapshot by
      // ciphertext equality — a sender cannot decrypt its own ciphertext.
      // Fire-and-forget: the send is never delayed or failed by this.
      final pendingSnapshot = _pendingSendContent[tempId];
      if (pendingSnapshot != null) {
        _encryptionProvider!
            .savePendingSendRecord(
                ciphertext, Map<String, dynamic>.from(pendingSnapshot))
            .ignore();
      }

      // 6. Send encrypted payload; include type/media metadata so the server
      // can reference self-hosted blobs (orphan media cleanup, expiry deletes).
      _e2eFlowLog('SEND_EMIT', {'recipientId': recipientId, 'tempId': tempId});
      final emitPayload = <String, dynamic>{
        'recipientId': recipientId,
        'content': '[encrypted]',
        'encryptedContent': ciphertext,
        'expiresIn': effectiveExpiresIn,
        'tempId': tempId,
        'replyToMessageId': effectiveReplyToId,
      };
      if (messageType != 'TEXT') {
        emitPayload['messageType'] = messageType;
      }
      if (mediaUrl != null && mediaUrl.isNotEmpty) {
        emitPayload['mediaUrl'] = mediaUrl;
      }
      if (mediaDuration != null) {
        emitPayload['mediaDuration'] = mediaDuration;
      }
      _emit?.call('sendMessage', emitPayload);
      return true;
    } catch (e) {
      _encryptionProvider?.clearPendingPreKeyFetch(recipientId);
      debugPrint('[E2E] Encryption failed: $e');
      E2ePersistentDiag.record('SEND_FAIL', {
        'recipientId': recipientId,
        'error': e.toString(),
      });
      _logMediaOrphanLikely(tempId, mediaUrl);
      final String userMsg = _userFriendlySendError(e, recipientId);
      _markMessageFailed(tempId, userMsg);
      if (_isKeyBundleOrTimeoutError(e)) {
        _scheduleDelayedRetry(tempId);
      }
      return false;
    }
  }

  @visibleForTesting
  Future<void> encryptAndSendForTest({
    required int recipientId,
    required String content,
    required String tempId,
    int? effectiveExpiresIn,
    int? effectiveReplyToId,
    String messageType = 'TEXT',
    String? mediaUrl,
    int? mediaDuration,
    String? mediaKey,
    String? mediaIv,
  }) =>
      _encryptAndSend(
        recipientId: recipientId,
        content: content,
        tempId: tempId,
        effectiveExpiresIn: effectiveExpiresIn,
        effectiveReplyToId: effectiveReplyToId,
        messageType: messageType,
        mediaUrl: mediaUrl,
        mediaDuration: mediaDuration,
        mediaKey: mediaKey,
        mediaIv: mediaIv,
      );

  /// Observability for the I1 media-orphan gap: a media blob was uploaded
  /// (`mediaUrl` obtained) but the send failed before the `sendMessage` emit,
  /// so the `.bin` is now orphaned on the server until the cleanup cron sweeps
  /// it. Logs an id-only event so the client side of the gap is measurable.
  /// No-op for text/ping sends (no upload, so `mediaUrl` is null/empty).
  void _logMediaOrphanLikely(String tempId, String? mediaUrl) {
    if (mediaUrl == null || mediaUrl.isEmpty) return;
    _e2eFlowLog('MEDIA_ORPHAN_LIKELY', {'tempId': tempId});
  }

  void _markMessageFailed(String tempId, String errorMsg) {
    // Failed = eligible for retry; release the exactly-once send latch.
    _emittedSendTempIds.remove(tempId);
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
    for (final msg in sending) {
      final tid = msg.tempId;
      if (tid != null) _emittedSendTempIds.remove(tid);
      final idx = _messages.indexWhere((m) => m.tempId == msg.tempId);
      if (idx != -1) {
        _messages[idx] = _messages[idx].copyWith(
          deliveryStatus: MessageDeliveryStatus.failed,
        );
      }
    }
    notifyListeners();
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
    if (message.disappearAfterSeconds != null) {
      effectiveExpiresIn = message.disappearAfterSeconds;
    } else if (message.expiresAt != null) {
      final secs = message.expiresAt!.difference(DateTime.now()).inSeconds;
      effectiveExpiresIn = secs.clamp(1, kDisappearingMaxSeconds);
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
}
