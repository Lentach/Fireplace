part of '../messaging_provider.dart';

// These extension methods live in MessagingProvider's own library and operate on
// its private state, so calling the ChangeNotifier's `notifyListeners()` here is
// legitimate; the analyzer's protected / visible-for-testing checks (which assume
// the call sits in a ChangeNotifier subclass body, not an extension) don't apply.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

/// User- and timer-driven mutations: read / clear / delete / pin / react / expiry.
extension MessagingActions on MessagingProvider {
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

  /// Optimistically apply a TEXT edit to a sent message, then encrypt the new
  /// plaintext over the existing Signal session and emit `editMessage`.
  /// Only own, TEXT, server-confirmed (positive id) rows are editable.
  void editMessage(int messageId, String newContent) {
    final trimmed = newContent.trim();
    if (trimmed.isEmpty || _currentUserId == null) return;
    final activeConversationId = _conversationsProvider?.activeConversationId;
    if (activeConversationId == null) return;
    final conv = _conversationsProvider!.conversations
        .where((c) => c.id == activeConversationId)
        .firstOrNull;
    if (conv == null) return;
    final recipientId = conv_helpers.getOtherUserId(conv, _currentUserId);

    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx == -1) return;
    final original = _messages[idx];
    if (original.senderId != _currentUserId ||
        messageId <= 0 ||
        original.messageType != MessageType.text ||
        DateTime.now().difference(original.createdAt) >=
            const Duration(minutes: 15)) {
      cancelEditMessage();
      return;
    }
    if (original.content == trimmed) {
      cancelEditMessage();
      return;
    }

    _pendingEdits[messageId] = original;
    final edited = original.copyWith(content: trimmed, editedAt: DateTime.now());
    _messages[idx] = edited;
    _reEnrichAllReplyQuotes();
    final lastMessages = _conversationsProvider?.lastMessages;
    if (lastMessages != null &&
        lastMessages[activeConversationId]?.id == messageId) {
      _conversationsProvider?.updateLastMessage(activeConversationId, edited);
    }
    if (_conversationCache.containsKey(activeConversationId)) {
      _updateCache(activeConversationId);
    }
    cancelEditMessage();
    notifyListeners();

    _encryptAndEmitEdit(
      messageId: messageId,
      recipientId: recipientId,
      content: trimmed,
    );
  }

  /// Encrypt [content] for [recipientId] and emit the `editMessage` event.
  /// On any failure the optimistic update is reverted. TEXT only; link preview
  /// is intentionally not regenerated in v1 (kept as-is).
  Future<void> _encryptAndEmitEdit({
    required int messageId,
    required int recipientId,
    required String content,
  }) async {
    if (!(_encryptionProvider?.isE2EReady ?? false)) {
      _revertPendingEdit(messageId, 'Encryption not ready');
      return;
    }
    try {
      final envelopeJson = jsonEncode(E2eEnvelope.build(content));
      await _encryptionProvider!.ensureSession(recipientId);
      final ciphertext =
          await _encryptionProvider!.encrypt(recipientId, envelopeJson);
      // Mirror send: enforce the server's encryptedContent cap so an over-long
      // edit fails clearly here instead of bouncing back from validation.
      if (ciphertext.length > 65536) {
        _revertPendingEdit(messageId, 'Message is too long to send');
        return;
      }
      _emit?.call('editMessage', {
        'messageId': messageId,
        'content': '[encrypted]',
        'encryptedContent': ciphertext,
      });
      // Sender owns plaintext: persist the FULL edited row (content + editedAt +
      // kept link preview) so reloads (own-message restore) show the edit and
      // nothing is silently dropped.
      final i = _messages.indexWhere((m) => m.id == messageId);
      if (i != -1) await _persistDecryptedContent(_messages[i]);
      _e2eFlowLog('EDIT_EMIT', {'messageId': messageId});
    } catch (e) {
      _e2eFlowLog('EDIT_FAILED', {'messageId': messageId});
      _revertPendingEdit(messageId, 'Edit failed');
    }
  }

  /// Restore the pre-edit row after a reject/failure: in-memory row, the
  /// persisted plaintext cache (written optimistically on the success path), and
  /// the conversation-list preview. Without all three a rejected edit would
  /// resurrect on reopen and diverge from the peer (server is authoritative).
  void _revertPendingEdit(int messageId, String reason) {
    final original = _pendingEdits.remove(messageId);
    if (original == null) return;
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx != -1) {
      _messages[idx] = original;
      _reEnrichAllReplyQuotes();
      if (_conversationCache.containsKey(original.conversationId)) {
        _updateCache(original.conversationId);
      }
    }
    // Roll back the persisted plaintext written by _encryptAndEmitEdit.
    _persistDecryptedContent(original).ignore();
    final lastMessages = _conversationsProvider?.lastMessages;
    if (lastMessages != null &&
        lastMessages[original.conversationId]?.id == messageId) {
      _conversationsProvider?.updateLastMessage(original.conversationId, original);
    }
    notifyListeners();
  }

  void pinMessage(int conversationId, int messageId) {
    final local = messageById(messageId);
    if (local != null) {
      _conversationsProvider?.setPinnedPreviewOptimistic(
        conversationId,
        messageId,
        local,
      );
    }
    _emit?.call('pinMessage', {
      'conversationId': conversationId,
      'messageId': messageId,
    });
  }

  void unpinMessage(int conversationId) {
    _emit?.call('unpinMessage', {'conversationId': conversationId});
  }

  void addReaction(int messageId, String emoji) {
    _emit?.call('addReaction', {'messageId': messageId, 'emoji': emoji});
  }

  void removeReaction(int messageId, String emoji) {
    _emit?.call('removeReaction', {'messageId': messageId, 'emoji': emoji});
  }

  /// Remove messages whose expiresAt has passed. Called every second by ChatDetailScreen timer.
  void removeExpiredMessages() {
    final now = DateTime.now();
    final hadExpiredInList = _messages.any((m) => isMessageExpired(m, now));
    var hadExpiredInCache = false;
    for (final cid in _conversationCache.keys.toList()) {
      final list = _conversationCache[cid];
      if (list == null) continue;
      final before = list.length;
      list.removeWhere((m) => isMessageExpired(m, now));
      if (list.length != before) hadExpiredInCache = true;
      if (list.isEmpty) _conversationCache.remove(cid);
    }
    if (!hadExpiredInList && !hadExpiredInCache) return;

    _messages.removeWhere((m) => isMessageExpired(m, now));
    _conversationsProvider?.pruneExpiredLastMessages();
    notifyListeners();
  }
}
