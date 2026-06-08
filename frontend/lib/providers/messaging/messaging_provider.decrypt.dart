part of '../messaging_provider.dart';

// These extension methods live in MessagingProvider's own library and operate on
// its private state, so calling the ChangeNotifier's `notifyListeners()` here is
// legitimate; the analyzer's protected / visible-for-testing checks (which assume
// the call sits in a ChangeNotifier subclass body, not an extension) don't apply.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

/// Decrypt, per-sender ordering, decrypt-retry, and decrypted-content persistence.
extension MessagingDecrypt on MessagingProvider {
  bool _isDuplicateDecryptError(Object e) =>
      e.toString().contains('DuplicateMessageException');

  // Bad Mac = message encrypted for a different/old session key.
  // Session itself is valid — treat as terminal like DuplicateMessageException.
  bool _isBadMacDecryptError(Object e) => e.toString().contains('Bad Mac');

  bool _isNoSessionDecryptError(Object e) =>
      e.toString().contains('NoSessionException');

  bool _conversationHasUndecryptedInbound(int conversationId) {
    return _messages.any(
      (m) =>
          m.conversationId == conversationId &&
          m.needsDecryption(_currentUserId) &&
          m.displayAsEncryptedPlaceholder,
    );
  }

  /// Re-run ordered history decrypt for the open chat (after E2E init or session mismatch).
  Future<void> retryDecryptActiveConversation() async {
    final convId = _effectiveActiveConversationId;
    if (convId == null) return;
    if (!(_encryptionProvider?.isE2EReady ?? false)) {
      return;
    }
    if (!_conversationHasUndecryptedInbound(convId)) {
      return;
    }
    _decryptHistoryGeneration++;
    final generation = _decryptHistoryGeneration;
    _decryptingHistory = true;
    await _decryptMessageHistory(generation);
    _finishHistoryDecryptPass(
      generation,
      conversationId: convId,
      updateCache: true,
    );
  }

  Future<void> _persistDecryptedContent(MessageModel decrypted) async {
    if (decrypted.content == '[Decryption failed]' ||
        decrypted.content == '[Encryption not initialized]') {
      return;
    }
    final hasText = decrypted.content.isNotEmpty;
    final hasMedia = decrypted.mediaUrl != null;
    if (!hasText && !hasMedia && decrypted.messageType == MessageType.text) {
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
      if (decrypted.mediaKey != null) 'mediaKey': decrypted.mediaKey!,
      if (decrypted.mediaIv != null) 'mediaIv': decrypted.mediaIv!,
      if (decrypted.linkPreviewUrl != null)
        'linkPreviewUrl': decrypted.linkPreviewUrl!,
      if (decrypted.linkPreviewTitle != null)
        'linkPreviewTitle': decrypted.linkPreviewTitle!,
    };
    if (safeImageUrl != null) {
      data['linkPreviewImageUrl'] = safeImageUrl;
    }
    _e2eFlowLog('persist', {
      'id': decrypted.id,
      'hasKey': data.containsKey('mediaKey'),
      'type': data['messageType'],
      'hasMedia': data.containsKey('mediaUrl'),
    });
    try {
      await _encryptionProvider?.saveDecryptedContent(decrypted.id, data);
      // VERIFY: read straight back to prove the write actually committed.
      final back = await _encryptionProvider?.getDecryptedContent(decrypted.id);
      _e2eFlowLog('persist.verify', {
        'id': decrypted.id,
        'readBackExists': back != null,
        'readBackHasKey': back?['mediaKey'] != null,
        'readBackType': back?['messageType'],
      });
    } catch (_) {}
  }

  /// True when [msg] has displayable plaintext (or decrypted media), not an E2E placeholder.
  bool _hasUsableDecryptedContent(MessageModel msg) {
    if (msg.content == _kDecryptionFailedLabel ||
        msg.content == '[Encryption not initialized]') {
      return false;
    }
    if (_missingEncryptedMediaKeys(msg)) {
      return false;
    }
    // Decrypted E2E media is usable once it has its one-shot keys + URL, even if
    // the text content is still the "[encrypted]" placeholder — voice/image rows
    // carry no text, so their decrypted content is legitimately empty. Without
    // this, restore-on-reopen treats a keyed media row as an undecrypted
    // placeholder and pointlessly re-decrypts it → DuplicateMessage →
    // "[Decryption failed]" in memory (the keys are safe in storage but unused),
    // so received voice/image fails to replay after reopening the chat.
    if (msg.mediaKey != null &&
        msg.mediaIv != null &&
        msg.mediaUrl != null &&
        msg.messageType != MessageType.text) {
      return true;
    }
    if (!msg.needsDecryption(_currentUserId)) {
      if (msg.content == _kEncryptedPlaceholderLabel ||
          msg.displayAsEncryptedPlaceholder) {
        return false;
      }
      return true;
    }
    if (msg.displayAsEncryptedPlaceholder) return false;
    return msg.content.isNotEmpty ||
        msg.mediaUrl != null ||
        msg.messageType != MessageType.text;
  }

  void _requestSessionRebuildForPeer(int peerId) {
    _encryptionProvider?.markSessionRebuild(peerId);
    _emit?.call('requestSessionRebuild', {'recipientId': peerId});
    _e2eFlowLog('SESSION_RESET', {'peerId': peerId});
  }

  Future<void> _decryptMessageHistory(int generation) async {
    _historyDecryptFailedPeers = <int>{};
    _historySessionRebuildRequested = <int>{};
    await _waitForE2EReady(maxAttempts: 100);
    if (!(_encryptionProvider?.isE2EReady ?? false)) {
      _e2eFlowLog('HISTORY_DECRYPT_SKIP_E2E_NOT_READY', {});
      return;
    }
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
      if (msg.needsDecryption(_currentUserId)) {
        // Cache-first: only skip live decrypt when cache holds real plaintext.
        final cached = _encryptionProvider?.getCachedDecryption(msg.id);
        if (cached != null) {
          if (cached.content == _kDecryptionFailedLabel) {
            // Terminal failure cached — restore and skip without live decrypt.
            final idx = _messages.indexWhere((m) => m.id == msg.id);
            if (idx != -1 && _messages[idx].content != _kDecryptionFailedLabel) {
              _messages[idx] = _messages[idx].copyWith(content: _kDecryptionFailedLabel);
              changed = true;
            }
            continue;
          }
          if (_hasUsableDecryptedContent(cached)) {
            final idx = _messages.indexWhere((m) => m.id == msg.id);
            if (idx != -1) {
              final merged = _mergeMessagePreferNewer(_messages[idx], cached);
              _messages[idx] = merged;
              _encryptionProvider?.cacheDecryption(msg.id, merged);
              changed = true;
            }
            continue;
          }
        }
        // _encryptionProvider is non-null here: this path is reached only when
        // isE2EReady is true, which requires the provider to be set.
        final persisted =
            await _encryptionProvider!.getDecryptedContent(msg.id);
        if (_requiresEncryptedMediaKeys(msg)) {
          _e2eFlowLog('hist.persisted', {
            'id': msg.id,
            'exists': persisted != null,
            'hasKey': persisted?['mediaKey'] != null,
            'type': persisted?['messageType'],
          });
        }
        final pContent = persisted?['content'] as String? ?? '';
        final hasPersistedPayload = persisted != null &&
            (pContent.isNotEmpty ||
                persisted['mediaUrl'] != null ||
                persisted['messageType'] != null);
        if (hasPersistedPayload) {
          if (pContent == _kDecryptionFailedLabel) {
            // Terminal failure persisted — restore and skip without live decrypt.
            final idx = _messages.indexWhere((m) => m.id == msg.id);
            if (idx != -1 && _messages[idx].content != _kDecryptionFailedLabel) {
              _messages[idx] = _messages[idx].copyWith(content: _kDecryptionFailedLabel);
              changed = true;
            }
            continue;
          }
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
            content: pContent.isNotEmpty ? pContent : msg.content,
            messageType: restoredType,
            mediaUrl: persisted['mediaUrl'] as String?,
            mediaDuration: persisted['mediaDuration'] as int?,
            mediaKey: persisted['mediaKey'] as String?,
            mediaIv: persisted['mediaIv'] as String?,
            linkPreviewUrl: persisted['linkPreviewUrl'] as String?,
            linkPreviewTitle: persisted['linkPreviewTitle'] as String?,
            linkPreviewImageUrl: validImage,
          );
          final idx = _messages.indexWhere((m) => m.id == msg.id);
          final merged = idx != -1
              ? _mergeMessagePreferNewer(_messages[idx], restored)
              : restored;
          if (_hasUsableDecryptedContent(merged)) {
            _encryptionProvider?.cacheDecryption(msg.id, merged);
            if (idx != -1) {
              _messages[idx] = merged;
              changed = true;
            }
            continue;
          }
          // Stale persisted row (mediaUrl without keys) — fall through to live decrypt.
        }
        final idx = _messages.indexWhere((m) => m.id == msg.id);
        final rowForDecrypt = idx != -1 ? _messages[idx] : msg;
        if (_hasUsableDecryptedContent(rowForDecrypt)) {
          _encryptionProvider?.cacheDecryption(msg.id, rowForDecrypt);
          continue;
        }
        // [Decryption failed] is a terminal state from a prior retry — skipping
        // prevents re-triggering deleteSessionWithPeer on every reconnect, which
        // would cascade to break decryption of all subsequent messages from this peer.
        if (rowForDecrypt.content == _kDecryptionFailedLabel) continue;
        // No cache — live decrypt (advances session ratchet)
        final decrypted = await _decryptMessageAsyncQueued(rowForDecrypt);
        if (idx != -1) {
          _messages[idx] = _mergeMessagePreferNewer(_messages[idx], decrypted);
          _encryptionProvider?.cacheDecryption(
            msg.id,
            _messages[idx],
          );
          changed = true;
        }
      } else if (msg.senderId == _currentUserId &&
          (msg.content == _kEncryptedPlaceholderLabel ||
              _missingEncryptedMediaKeys(msg))) {
        // _encryptionProvider is non-null here: own-message path requires E2E ready.
        final stored = await _encryptionProvider!.getDecryptedContent(msg.id);
        final storedContent = stored?['content'] as String? ?? '';
        if (storedContent.isNotEmpty ||
            (stored?['messageType'] as String?) != null ||
            stored?['mediaUrl'] != null) {
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
            mediaKey: stored?['mediaKey'] as String?,
            mediaIv: stored?['mediaIv'] as String?,
            linkPreviewUrl: stored?['linkPreviewUrl'] as String?,
            linkPreviewTitle: stored?['linkPreviewTitle'] as String?,
            linkPreviewImageUrl: safeImageUrl,
          );
          final idx = _messages.indexWhere((m) => m.id == msg.id);
          if (idx != -1) {
            final merged = _mergeMessagePreferNewer(_messages[idx], restored);
            _messages[idx] = merged;
            _encryptionProvider?.cacheDecryption(msg.id, merged);
            changed = true;
          }
        }
      }
    }
    if (_decryptHistoryGeneration == generation) {
      final peersNeedingRetry = <int>{
        ...?_historyDecryptFailedPeers,
        ..._liveDecryptFailedPeers,
        for (final m in _messages)
          if (m.needsDecryption(_currentUserId) &&
              m.displayAsEncryptedPlaceholder)
            m.senderId,
      };
      if (peersNeedingRetry.isNotEmpty) {
        final retried = await _retryDecryptForPeers(
          generation,
          peersNeedingRetry,
        );
        if (retried) changed = true;
      }
      if (_recoverUnresolvedEncryptedInbound(generation)) {
        changed = true;
      }
      if (_markHistoryDecryptFailuresAfterRetry(generation)) {
        changed = true;
      }
    }
    _historyDecryptFailedPeers = null;
    _historySessionRebuildRequested = null;
    if (changed) _e2eFlowLog('HISTORY_DECRYPT_DONE', {'changed': true});
    if (changed) notifyListeners();
  }

  /// When inbound rows still show [encrypted] (not [Decryption failed]) after decrypt+retry, request session rebuild (silent).
  /// [Decryption failed] is terminal — excluded here to avoid markSessionRebuild on every history pass.
  bool _recoverUnresolvedEncryptedInbound(int generation) {
    if (_decryptHistoryGeneration != generation) return false;
    final unresolvedPeers = <int>{};
    for (final m in _messages) {
      if (m.needsDecryption(_currentUserId) && m.displayAsEncryptedPlaceholder) {
        unresolvedPeers.add(m.senderId);
      }
    }
    if (unresolvedPeers.isEmpty) return false;
    for (final peerId in unresolvedPeers) {
      _requestSessionRebuildForPeer(peerId);
    }
    _e2eFlowLog('E2E_RECOVERY_SESSION_RESET', {'peerIds': unresolvedPeers.toList()});
    return true;
  }

  /// After ordered history decrypt + session retry, mark rows that are still locked.
  bool _markHistoryDecryptFailuresAfterRetry(int generation) {
    if (_decryptHistoryGeneration != generation) return false;
    var changed = false;
    for (var i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      if (!m.needsDecryption(_currentUserId)) continue;
      if (!_hasUsableDecryptedContent(m) &&
          m.content != _kDecryptionFailedLabel &&
          (m.displayAsEncryptedPlaceholder ||
              m.content == _kEncryptedPlaceholderLabel)) {
        _messages[i] = m.copyWith(content: _kDecryptionFailedLabel);
        changed = true;
      }
    }
    return changed;
  }

  /// After history/live decrypt failures, reset the local session with each peer
  /// (once per pass) and replay decrypt oldest-first. Does not downgrade
  /// [Decryption failed] to [encrypted] — failed rows stay failed until decrypt succeeds.
  Future<bool> _retryDecryptForPeers(
    int generation,
    Set<int> peerIds,
  ) async {
    bool changed = false;
    final rebuildRequested = _historySessionRebuildRequested ??= <int>{};
    for (final peerId in peerIds) {
      if (_decryptHistoryGeneration != generation) return changed;
      if (rebuildRequested.add(peerId)) {
        _requestSessionRebuildForPeer(peerId);
      }
      try {
        await _encryptionProvider?.deleteSessionWithPeer(peerId);
      } catch (e) {
        debugPrint('[E2E] deleteSessionWithPeer($peerId) failed: $e');
      }
    }

    final sorted = _messages
        .where(
          (m) =>
              peerIds.contains(m.senderId) &&
              m.needsDecryption(_currentUserId),
        )
        .toList()
      ..sort((a, b) {
        final byTime = a.createdAt.compareTo(b.createdAt);
        if (byTime != 0) return byTime;
        return a.id.compareTo(b.id);
      });

    for (final msg in sorted) {
      if (_decryptHistoryGeneration != generation) break;
      final idx = _messages.indexWhere((m) => m.id == msg.id);
      final row = idx != -1 ? _messages[idx] : msg;
      if (_hasUsableDecryptedContent(row)) {
        _encryptionProvider?.cacheDecryption(msg.id, row);
        continue;
      }
      final decrypted = await _decryptMessageAsyncQueued(row);
      if (idx == -1) continue;
      _messages[idx] = _mergeMessagePreferNewer(_messages[idx], decrypted);
      changed = true;
      if (decrypted.content != _kDecryptionFailedLabel &&
          decrypted.content != '[Encryption not initialized]') {
        _encryptionProvider?.cacheDecryption(msg.id, _messages[idx]);
        _liveDecryptFailedPeers.remove(msg.senderId);
        _encryptionProvider?.clearSessionRebuild(msg.senderId);
      }
    }
    return changed;
  }

  /// Debounced retry after live decrypt failure (no per-message SESSION_RESET).
  void _scheduleLiveDecryptRetry(int peerId) {
    _liveDecryptFailedPeers.add(peerId);
    _liveDecryptRetryTimer?.cancel();
    _liveDecryptRetryTimer = Timer(const Duration(milliseconds: 800), () {
      _liveDecryptRetryTimer = null;
      _runLiveDecryptRetries().ignore();
    });
  }

  Future<void> _runLiveDecryptRetries() async {
    if (_decryptingHistory || _liveDecryptFailedPeers.isEmpty) return;
    final peers = Set<int>.from(_liveDecryptFailedPeers);
    final gen = _decryptHistoryGeneration;
    final changed = await _retryDecryptForPeers(gen, peers);
    if (_decryptHistoryGeneration != gen) return;
    if (changed) {
      final cid = _effectiveActiveConversationId;
      if (cid != null) _updateCache(cid);
      notifyListeners();
    }
  }

  Future<MessageModel> _decryptMessageAsyncQueued(MessageModel msg) {
    if (msg.senderId == _currentUserId) {
      return Future.value(msg);
    }
    return _runDecryptSerialized(
      msg.senderId,
      () => _decryptMessageAsync(msg),
    );
  }

  Future<MessageModel> _decryptMessageAsync(MessageModel msg) async {
    // Own messages: server stored "[encrypted]" as content but we already
    // showed plaintext optimistically, so skip decryption for our own messages.
    if (msg.senderId == _currentUserId) return msg;

    // Already decrypted (e.g. live path) — never re-run ratchet decrypt on the
    // same ciphertext; that advances the session and causes Bad Mac on retry.
    if (_hasUsableDecryptedContent(msg)) return msg;

    await _waitForE2EReady();
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
          mediaKey: parsed.mediaKey,
          mediaIv: parsed.mediaIv,
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
      final cached = _encryptionProvider?.getCachedDecryption(msg.id);
      if (cached != null && _hasUsableDecryptedContent(cached)) return cached;
      if (_hasUsableDecryptedContent(msg)) return msg;

      final persisted =
          await _encryptionProvider!.getDecryptedContent(msg.id);
      final persistedContent = persisted?['content'] as String? ?? '';
      final canRestorePersisted = persisted != null &&
          (persistedContent.isNotEmpty ||
              persisted['mediaUrl'] != null ||
              persisted['messageType'] != null);
      if (canRestorePersisted) {
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
          content: persistedContent.isNotEmpty ? persistedContent : msg.content,
          messageType: restoredType,
          mediaUrl: persisted['mediaUrl'] as String?,
          mediaDuration: persisted['mediaDuration'] as int?,
          mediaKey: persisted['mediaKey'] as String?,
          mediaIv: persisted['mediaIv'] as String?,
          linkPreviewUrl: persisted['linkPreviewUrl'] as String?,
          linkPreviewTitle: persisted['linkPreviewTitle'] as String?,
          linkPreviewImageUrl: safeImageUrl,
        );
        if (_hasUsableDecryptedContent(restored)) {
          _encryptionProvider?.cacheDecryption(msg.id, restored);
          return restored;
        }
      }

      if (_isDuplicateDecryptError(e)) {
        // Ratchet already consumed this key (message was live-decrypted earlier).
        // Session is valid — do NOT delete it or schedule retry. Mark terminal now.
        // Persist so future app starts skip this message without re-attempting.
        _e2eFlowLog('DECRYPT_DUPLICATE', {'msgId': msg.id});
        await _encryptionProvider?.saveDecryptedContent(
            msg.id, {'content': _kDecryptionFailedLabel});
        return msg.copyWith(content: _kDecryptionFailedLabel);
      }
      if (_isBadMacDecryptError(e)) {
        // MAC mismatch: message was encrypted for a different/old session key.
        // Session is valid — do NOT delete it or add to historyDecryptFailedPeers.
        // Persist so future app starts skip this message without re-attempting.
        _e2eFlowLog('DECRYPT_BAD_MAC', {'msgId': msg.id});
        await _encryptionProvider?.saveDecryptedContent(
            msg.id, {'content': _kDecryptionFailedLabel});
        return msg.copyWith(content: _kDecryptionFailedLabel);
      }
      if (_encryptionProvider?.hadIdentityReset == true) {
        // Identity was just regenerated (reinstall / storage loss).
        // All messages encrypted for the old identity are permanently unrecoverable.
        // Do NOT delete sessions or schedule retries — a fresh session will be built
        // by the next PreKey message the peer sends.
        _e2eFlowLog('DECRYPT_IDENTITY_RESET', {'msgId': msg.id});
        return msg.copyWith(content: _kDecryptionFailedLabel);
      }
      if (_isNoSessionDecryptError(e)) {
        _e2eFlowLog('DECRYPT_SKIP', {
          'msgId': msg.id,
          'reason': e.toString(),
        });
        if (_decryptingHistory) {
          _historyDecryptFailedPeers?.add(msg.senderId);
        } else {
          _scheduleLiveDecryptRetry(msg.senderId);
        }
        return msg;
      }

      debugPrint('[E2E] Decrypt failed for msg ${msg.id}: $e');
      _e2eFlowLog(
          'DECRYPT_FAIL', {'msgId': msg.id, 'error': e.toString()});
      if (_decryptingHistory) {
        _historyDecryptFailedPeers?.add(msg.senderId);
        // Keep [encrypted] until retry + session reset finish (see
        // [_markHistoryDecryptFailuresAfterRetry]).
        return msg;
      }
      _scheduleLiveDecryptRetry(msg.senderId);
      return msg.copyWith(content: _kDecryptionFailedLabel);
    }
  }
}
