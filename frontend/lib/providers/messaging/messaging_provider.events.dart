part of '../messaging_provider.dart';

// These extension methods live in MessagingProvider's own library and operate on
// its private state, so calling the ChangeNotifier's `notifyListeners()` here is
// legitimate; the analyzer's protected / visible-for-testing checks (which assume
// the call sits in a ChangeNotifier subclass body, not an extension) don't apply.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

/// Socket event entrypoints (`onX`) and their internal handlers (`_handleX`).
extension MessagingEvents on MessagingProvider {
  void onNewMessage(dynamic data) {
    _handleIncomingMessage(data);
  }

  void onMessageSent(dynamic data) {
    _handleIncomingMessage(data);
  }

  void onMessageDelivered(dynamic data) {
    _handleMessageDelivered(data);
  }

  void onMessageDeleted(dynamic data) {
    _handleMessageDeleted(data);
  }

  void onMessageEdited(dynamic data) {
    _handleMessageEdited(data);
  }

  void onEditMessageFailed(dynamic data) {
    final m = data as Map<String, dynamic>;
    final messageId = m['messageId'] as int;
    final reason = m['reason'] as String? ?? 'edit_failed';
    _revertPendingEdit(messageId, reason);
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
    // Collect BEFORE removing — see [_purgeConversationsLocally].
    _purgeConversationsLocally([conversationId]);
    _messages.removeWhere((m) => m.conversationId == conversationId);
    notifyListeners();
    _conversationCache.remove(conversationId);
  }

  void _handleIncomingMessage(dynamic data) {
    final dataMap = data as Map<String, dynamic>;
    var msg = _enrichReplyPreview(MessageModel.fromJson(dataMap));
    final activeConversationId = _effectiveActiveConversationId;

    // Queue incoming encrypted messages for active conversation while we're
    // decrypting history (so history decrypt runs first and session order is preserved).
    if (_decryptingHistory &&
        msg.conversationId == activeConversationId &&
        _needsDecryption(msg)) {
      // DIAGNOSTIC (iOS-PWA live-receive drop): message queued behind history decrypt.
      _e2eFlowLog('RECV_QUEUED', {
        'msgId': msg.id,
        'msgConvId': msg.conversationId,
        'activeId': activeConversationId,
        'paginationConvId': _paginationConversationId,
      });
      _incomingMessageQueue.add(dataMap);
      return;
    }
    _e2eFlowLog('RECV_MSG', {
      'msgId': msg.id,
      'senderId': msg.senderId,
      // DIAGNOSTIC (iOS-PWA live-receive drop): capture active/pagination id state.
      'msgConvId': msg.conversationId,
      'activeId': activeConversationId,
      'paginationConvId': _paginationConversationId,
      'decryptingHistory': _decryptingHistory,
      'hasEncryptedContent':
          msg.encryptedContent != null && msg.encryptedContent!.isNotEmpty,
      'needsDecryption': _needsDecryption(msg),
    });
    // If encrypted, decrypt async and update in-place
    if (_needsDecryption(msg)) {
      _addMessageToState(msg);
      final viewingConversationId =
          activeConversationId ?? _paginationConversationId;
      // Background decrypt for chats the user is not viewing breaks Signal ordering
      // (PWA push / morning resume) — decrypt only in ordered history when chat opens.
      if (viewingConversationId < 0 ||
          msg.conversationId != viewingConversationId) {
        return;
      }
      _decryptMessageAsyncQueued(msg).then((decrypted) async {
        final merged = _mergeDecryptedIntoState(decrypted);
        _encryptionProvider?.cacheDecryption(merged.id, merged);
        await _persistDecryptedContent(merged);
        if (_hasUsableDecryptedContent(merged)) {
          _reEnrichAllReplyQuotes();
        }
        final idx = _messages.indexWhere((m) => m.id == merged.id);
        final lastMessages = _conversationsProvider?.lastMessages;
        if (lastMessages != null &&
            lastMessages[merged.conversationId]?.id == merged.id) {
          _conversationsProvider?.updateLastMessage(
            merged.conversationId,
            merged,
          );
        }
        _e2eFlowLog('RECV_DECRYPT_DONE', {
          'msgId': merged.id,
          'contentLength': merged.content.length,
        });
        notifyListeners();
        // Update cache only when the message was actually updated in _messages (idx != -1).
        // If the user navigated away, idx == -1 and _messages holds a different conversation —
        // calling _updateCache would snapshot the wrong data and overwrite the valid cache entry
        // for this conversation with an empty or foreign list.
        final cid = merged.conversationId;
        if (idx != -1 && _conversationCache.containsKey(cid)) {
          _updateCache(cid);
        }
        if (merged.senderId != _currentUserId &&
            merged.messageType != MessageType.ping) {
          _incomingSound.play().ignore();
        }
      });
      return;
    }

    _addMessageToState(msg);
    if (msg.senderId != _currentUserId && msg.messageType != MessageType.ping) {
      _incomingSound.play().ignore();
    }
    // Keep cache current for active conversation.
    final activeIdAfterPlain = _effectiveActiveConversationId;
    if (activeIdAfterPlain != null &&
        _conversationCache.containsKey(activeIdAfterPlain)) {
      _updateCache(activeIdAfterPlain);
    }
  }

  void _processIncomingMessageQueue() {
    if (_incomingMessageQueue.isEmpty) return;
    final queue = List<Map<String, dynamic>>.from(_incomingMessageQueue);
    _incomingMessageQueue.clear();
    for (final data in queue) {
      _handleIncomingMessage(data);
    }
  }

  void _handleMessageDelivered(dynamic data) {
    final map = data as Map<String, dynamic>;
    final messageId = map['messageId'] as int;
    final status = map['deliveryStatus'] as String;
    final conversationId = map['conversationId'] as int?;
    final newStatus = MessageModel.parseDeliveryStatus(status);

    // Update message in _messages list (current chat)
    final index = _messages.indexWhere((m) => m.id == messageId);
    DateTime? newExpiresAt;
    final expiresAtRaw = map['expiresAt'];
    if (expiresAtRaw is String) {
      // tryParse, not parse: a malformed timestamp would throw inside this
      // synchronous socket handler and abort the delivery-status update, the
      // cache patch and the conversation-list update for this message.
      // Same rule as ServerClock.observeIso.
      newExpiresAt = DateTime.tryParse(expiresAtRaw);
    }

    // Keep the stored record's deadline authoritative. A read-mode
    // disappearing message is persisted at DECRYPT time, before the server
    // assigns `expiresAt`; this event is where the real deadline arrives.
    // Without re-stamping, the sweep would fall back to the never-read rule
    // and hold that plaintext up to a day past when it should be gone.
    final encryption = _encryptionProvider;
    if (newExpiresAt != null && encryption != null) {
      unawaited(encryption.stampRecordExpiry(messageId, newExpiresAt));
    }

    if (index != -1) {
      _messages[index] = _messages[index].copyWith(
        deliveryStatus: newStatus,
        expiresAt: newExpiresAt ?? _messages[index].expiresAt,
      );
    } else if (conversationId != null) {
      _patchMessageInCache(
        conversationId,
        messageId,
        (m) => m.copyWith(
          deliveryStatus: newStatus,
          expiresAt: newExpiresAt ?? m.expiresAt,
        ),
      );
    }

    // Update _lastMessages so list and re-opened chat show correct status
    if (conversationId != null) {
      final lastMessages = _conversationsProvider?.lastMessages;
      if (lastMessages != null &&
          lastMessages[conversationId]?.id == messageId) {
        _conversationsProvider?.updateLastMessage(
          conversationId,
          lastMessages[conversationId]!.copyWith(
            deliveryStatus: newStatus,
            expiresAt: newExpiresAt ?? lastMessages[conversationId]!.expiresAt,
          ),
        );
      }
    }

    if (index != -1 || conversationId != null) {
      notifyListeners();
    }
    if (index != -1) {
      final cid = _messages[index].conversationId;
      if (_conversationCache.containsKey(cid)) {
        _updateCache(cid);
      }
    }
  }

  void _handleChatHistoryCleared(dynamic data) {
    final m = data as Map<String, dynamic>;
    final conversationId = m['conversationId'] as int;

    // Collect BEFORE removing — see [_purgeConversationsLocally].
    _purgeConversationsLocally([conversationId]);

    // Clear messages from memory
    _messages.removeWhere((m) => m.conversationId == conversationId);
    _conversationsProvider?.updateLastMessage(conversationId, null);

    notifyListeners();
    _conversationCache.remove(conversationId);
  }

  /// Unfriend / block: destroy the local plaintext for [conversationIds] and
  /// drop their rows.
  ///
  /// Previously nothing cleared these at all — removing a contact left their
  /// decrypted history in memory AND on disk indefinitely, which is the widest
  /// version of the bug this change exists to fix.
  void onConversationsRemovedForUser(Iterable<int> conversationIds) {
    final targets = conversationIds.toSet();
    if (targets.isEmpty) return;
    _purgeConversationsLocally(targets);
    _messages.removeWhere((m) => targets.contains(m.conversationId));
    for (final id in targets) {
      _conversationCache.remove(id);
    }
    notifyListeners();
  }

  /// Destroy every persisted plaintext record this device holds for
  /// [conversationIds] — including messages this session never loaded.
  ///
  /// The ids come from a scan of the store, keyed on the `_cid` stamped into
  /// each record, NOT from `_messages`. That distinction is the whole point:
  /// history pages in ~50 rows at a time while up to 2000 records persist
  /// across sessions, so purging only the loaded rows would strand the rest
  /// permanently — a cleared or unfriended message has no expiry, so no later
  /// sweep would find it either.
  ///
  /// Ciphertexts still come from the loaded rows: the pending-send store is
  /// keyed by ciphertext and only a live row carries one. Those records are few
  /// and TTL-bounded, and the wipe action clears them outright.
  void _purgeConversationsLocally(Iterable<int> conversationIds) {
    final targets = conversationIds.toSet();
    if (targets.isEmpty) return;

    final ciphertexts = <String>{};
    void collect(Iterable<MessageModel> rows) {
      for (final msg in rows) {
        if (!targets.contains(msg.conversationId)) continue;
        final ciphertext = msg.encryptedContent;
        if (ciphertext != null) ciphertexts.add(ciphertext);
      }
    }

    collect(_messages);
    for (final id in targets) {
      final cached = _conversationCache[id];
      if (cached != null) collect(cached);
    }

    final encryption = _encryptionProvider;
    if (encryption == null) return;
    // Safe to fire and forget: purgeConversations routes through
    // purgeLocalPlaintext, which writes a durable backlog entry before it
    // touches anything, so an interrupted purge is retried on the next launch.
    _firePurge(
      encryption.purgeConversations(targets, ciphertexts: ciphertexts),
    );
  }

  /// Start a purge without awaiting it, and without letting a failure escape as
  /// an unhandled async error.
  ///
  /// These run from synchronous socket handlers, so there is nobody to await
  /// them. A throw here would abandon the rest of the handler and surface as an
  /// unhandled zone error rather than as a retry. Correctness does not depend on
  /// this completing: the durable purge backlog is written before any store is
  /// touched, so whatever fails is retried on the next `socketReady`.
  void _firePurge(Future<void> purge) {
    unawaited(
      purge.catchError((Object error) {
        E2ePersistentDiag.record('PLAINTEXT_PURGE_THREW', {'error': '$error'});
      }),
    );
  }

  void _handleMessageDeleted(dynamic data) {
    final m = data as Map<String, dynamic>;
    final messageId = m['messageId'] as int;
    final conversationId = m['conversationId'] as int;
    final forEveryone = m['forEveryone'] as bool? ?? false;

    _deletedMessageIds.add(messageId);

    // Take the ciphertext BEFORE the row leaves local state: it is the only
    // key to the sender's own outgoing plaintext (pending-send records are
    // keyed by ciphertext, not id), and the removeWhere below destroys the
    // handle. Then destroy every local copy.
    //
    // Safe to make irreversible here, and irreversible is the point: the
    // server row is already gone — hard-deleted for everyone, or filtered out
    // of history by `hiddenByUserIds` for delete-for-me — so it can never be
    // re-served and re-decrypted. No clock is involved, unlike expiry, where
    // the row may still be live on the server.
    //
    // Fire-and-forget is safe only because purgeLocalPlaintext writes a
    // durable backlog entry first; an interrupted purge is retried on the next
    // launch instead of leaving plaintext nothing will ever look at again.
    final ciphertext = _ciphertextFor(messageId, conversationId);
    final encryption = _encryptionProvider;
    if (encryption != null) {
      _firePurge(
        encryption.purgeLocalPlaintext([
          messageId,
        ], ciphertexts: ciphertext == null ? const <String>[] : [ciphertext]),
      );
    }

    _messages.removeWhere((msg) => msg.id == messageId);

    // Update last message preview for conversation list
    final lastMessages = _conversationsProvider?.lastMessages;
    if (lastMessages != null && lastMessages[conversationId]?.id == messageId) {
      final remaining = _messages
          .where((msg) => msg.conversationId == conversationId)
          .toList();
      if (remaining.isNotEmpty) {
        remaining.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        _conversationsProvider?.updateLastMessage(
          conversationId,
          remaining.last,
        );
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
    // Reflect deletion in cache; remove entry entirely if the conversation is now empty.
    if (_conversationCache.containsKey(conversationId)) {
      final remaining = _messages
          .where((m) => m.conversationId == conversationId)
          .toList();
      if (remaining.isEmpty) {
        _conversationCache.remove(conversationId);
      } else {
        _updateCache(conversationId);
      }
    }
  }

  /// The ciphertext of [messageId] if the row is still in local state.
  ///
  /// Pending-send records — the sender's own outgoing plaintext — are keyed by
  /// ciphertext, so this handle must be taken before the row is dropped.
  ///
  /// Null when the message was never loaded this session (a delete arriving
  /// for a conversation the user has not opened). That record then expires on
  /// its own 72h TTL; closing the gap fully would need an id→ciphertext index
  /// nothing else wants, and the wipe action clears the store outright.
  String? _ciphertextFor(int messageId, int conversationId) {
    for (final msg in _messages) {
      if (msg.id == messageId) return msg.encryptedContent;
    }
    final cached = _conversationCache[conversationId];
    if (cached != null) {
      for (final msg in cached) {
        if (msg.id == messageId) return msg.encryptedContent;
      }
    }
    return null;
  }

  void _handleMessageEdited(dynamic data) {
    final m = data as Map<String, dynamic>;
    final messageId = m['messageId'] as int;
    final conversationId = m['conversationId'] as int?;
    final newCipher = m['encryptedContent'] as String?;
    final editedAtRaw = m['editedAt'];
    final editedAt = editedAtRaw is String
        ? DateTime.tryParse(editedAtRaw)
        : null;

    // Edit-vs-delete race: a deleted row must stay gone.
    if (_deletedMessageIds.contains(messageId)) return;

    final idx = _messages.indexWhere((msg) => msg.id == messageId);
    MessageModel? existing = idx != -1 ? _messages[idx] : null;
    if (existing == null && conversationId != null) {
      final list = _conversationCache[conversationId];
      if (list != null) {
        for (final msg in list) {
          if (msg.id == messageId) {
            existing = msg;
            break;
          }
        }
      }
    }
    // Not loaded anywhere — the edited ciphertext arrives later via messageHistory.
    if (existing == null) return;

    // OWN edit echo: content already applied optimistically; reconcile editedAt.
    if (existing.senderId == _currentUserId) {
      _pendingEdits.remove(messageId);
      if (idx != -1) {
        _messages[idx] = _messages[idx].copyWith(editedAt: editedAt);
      }
      if (conversationId != null) {
        _patchMessageInCache(
          conversationId,
          messageId,
          (msg) => msg.copyWith(editedAt: editedAt),
        );
      }
      _reEnrichAllReplyQuotes();
      notifyListeners();
      return;
    }

    // PEER edit: the new ciphertext supersedes the cached plaintext.
    _encryptionProvider?.invalidateDecryptionCache(messageId);
    final candidate = existing.copyWith(
      encryptedContent: newCipher,
      content: _kEncryptedPlaceholderLabel,
      editedAt: editedAt,
    );
    final activeId = _effectiveActiveConversationId;
    final isActive = conversationId != null && conversationId == activeId;
    final e2eReady = _encryptionProvider?.isE2EReady ?? false;

    if (isActive && e2eReady && newCipher != null && newCipher.isNotEmpty) {
      // Decrypt the new ciphertext now (serialized per sender), then apply.
      _decryptEditedMessage(candidate);
    } else {
      // Defer: store the new ciphertext; it re-decrypts when the chat opens.
      if (idx != -1) _messages[idx] = candidate;
      if (conversationId != null) {
        _patchMessageInCache(conversationId, messageId, (_) => candidate);
        // Do NOT push the '[encrypted]' placeholder into the conv-list preview:
        // keep the readable pre-edit text until the row re-decrypts on open
        // (avoids a "last message → Encrypted message" regression). M1.
      }
      _reEnrichAllReplyQuotes();
      notifyListeners();
    }
  }

  Future<void> _decryptEditedMessage(MessageModel candidate) async {
    final decrypted = await _decryptMessageAsyncQueued(candidate);
    final idx = _messages.indexWhere((msg) => msg.id == candidate.id);
    if (idx != -1) _messages[idx] = decrypted;
    _patchMessageInCache(
      decrypted.conversationId,
      decrypted.id,
      (_) => decrypted,
    );
    await _persistDecryptedContent(decrypted);
    _maybeUpdateLastEdited(decrypted.conversationId, decrypted.id, decrypted);
    _reEnrichAllReplyQuotes();
    notifyListeners();
  }

  void _maybeUpdateLastEdited(
    int conversationId,
    int messageId,
    MessageModel updated,
  ) {
    final lastMessages = _conversationsProvider?.lastMessages;
    if (lastMessages != null && lastMessages[conversationId]?.id == messageId) {
      _conversationsProvider?.updateLastMessage(conversationId, updated);
    }
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
}
