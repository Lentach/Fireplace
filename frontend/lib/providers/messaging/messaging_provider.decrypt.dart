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

  /// Classify a raw decrypt exception (string-matched). Precedence:
  /// duplicate → badMac → noSession → unknown. Identity-reset is orthogonal and
  /// applied by [decideDecryptionFailure], not here.
  DecryptionFailureKind _classifyDecryptError(Object e) {
    if (_isDuplicateDecryptError(e)) return DecryptionFailureKind.duplicate;
    if (_isBadMacDecryptError(e)) return DecryptionFailureKind.badMac;
    if (_isNoSessionDecryptError(e)) return DecryptionFailureKind.noSession;
    return DecryptionFailureKind.unknown;
  }

  /// Emit the same diagnostic the original if-chain did, per fired rule.
  void _logDecryptionFailure(
    DecryptionFailureRule rule,
    MessageModel msg,
    Object e,
  ) {
    switch (rule) {
      case DecryptionFailureRule.duplicate:
        // Ratchet already consumed this key (live-decrypted earlier); session valid.
        _e2eFlowLog('DECRYPT_DUPLICATE', {'msgId': msg.id});
        break;
      case DecryptionFailureRule.badMac:
        // MAC mismatch: encrypted for a different/old session key; session valid.
        _e2eFlowLog('DECRYPT_BAD_MAC', {'msgId': msg.id});
        break;
      case DecryptionFailureRule.identityReset:
        // Identity regenerated (reinstall / storage loss) — old messages unrecoverable.
        _e2eFlowLog('DECRYPT_IDENTITY_RESET', {'msgId': msg.id});
        break;
      case DecryptionFailureRule.noSession:
        _e2eFlowLog('DECRYPT_SKIP', {'msgId': msg.id, 'reason': e.toString()});
        break;
      case DecryptionFailureRule.unknown:
        debugPrint('[E2E] Decrypt failed for msg ${msg.id}: $e');
        _e2eFlowLog('DECRYPT_FAIL', {'msgId': msg.id, 'error': e.toString()});
        break;
    }
  }

  /// True for a row that still NEEDS a decrypt pass: shows the "[encrypted]"
  /// placeholder AND has no usable decrypted content. The second check is
  /// load-bearing: restored keyed-media rows (voice/image) legitimately keep
  /// `content == '[encrypted]'` forever — their decrypted payload is the
  /// mediaKey/mediaIv, not text — so placeholder-only predicates counted every
  /// received media message as "still undecrypted" and re-armed the
  /// session-reset machinery on every history pass (the 2026-06-12
  /// SESSION_RESET{historyRetry} loop).
  bool _isUnresolvedEncryptedInbound(MessageModel m) =>
      m.needsDecryption(_currentUserId) &&
      m.displayAsEncryptedPlaceholder &&
      !_hasUsableDecryptedContent(m);

  bool _conversationHasUndecryptedInbound(int conversationId) {
    return _messages.any(
      (m) =>
          m.conversationId == conversationId &&
          _isUnresolvedEncryptedInbound(m),
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
    final safeImageUrl =
        decrypted.linkPreviewImageUrl != null &&
            decrypted.linkPreviewUrl != null &&
            LinkPreviewService.isSafeImageUrl(
              decrypted.linkPreviewImageUrl,
              decrypted.linkPreviewUrl,
            )
        ? decrypted.linkPreviewImageUrl
        : null;
    final data = <String, dynamic>{
      'content': decrypted.content,
      if (decrypted.editedAt != null)
        'editedAt': decrypted.editedAt!.toIso8601String(),
      if (decrypted.messageType != MessageType.text)
        'messageType': decrypted.messageType.name.toUpperCase(),
      if (decrypted.mediaUrl != null) 'mediaUrl': decrypted.mediaUrl!,
      if (decrypted.mediaDuration != null)
        'mediaDuration': decrypted.mediaDuration!,
      if (decrypted.mediaKey != null) 'mediaKey': decrypted.mediaKey!,
      if (decrypted.mediaIv != null) 'mediaIv': decrypted.mediaIv!,
      if (decrypted.mediaWidth != null) 'mediaWidth': decrypted.mediaWidth!,
      if (decrypted.mediaHeight != null) 'mediaHeight': decrypted.mediaHeight!,
      if (decrypted.mediaThumbHash != null)
        'mediaThumbHash': decrypted.mediaThumbHash!,
      if (decrypted.linkPreviewUrl != null)
        'linkPreviewUrl': decrypted.linkPreviewUrl!,
      if (decrypted.linkPreviewTitle != null)
        'linkPreviewTitle': decrypted.linkPreviewTitle!,
    };
    if (safeImageUrl != null) {
      data['linkPreviewImageUrl'] = safeImageUrl;
    }
    try {
      await _encryptionProvider?.saveDecryptedContent(decrypted.id, data);
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

  /// True when [serverEditedAt] is newer than the [cachedEditedAt] a stored
  /// plaintext was decrypted at — i.e. an edit landed and the cache is stale, so
  /// the new ciphertext must be re-decrypted instead of served from cache.
  bool _isEditStale(DateTime? serverEditedAt, DateTime? cachedEditedAt) {
    if (serverEditedAt == null) return false;
    if (cachedEditedAt == null) return true;
    return serverEditedAt.isAfter(cachedEditedAt);
  }

  /// Ciphertext type prefix ("{type}:{base64}"): 3 = PreKey, 2 = Signal
  /// (CiphertextMessage.prekeyType / whisperType in libsignal_protocol_dart).
  /// Diagnostic only — null when the prefix is absent/unparseable.
  int? _ciphertextType(String? ciphertext) {
    if (ciphertext == null) return null;
    final colonIdx = ciphertext.indexOf(':');
    if (colonIdx <= 0) return null;
    return int.tryParse(ciphertext.substring(0, colonIdx));
  }

  void _requestSessionRebuildForPeer(int peerId, {required String trigger}) {
    // Once per peer until a decrypt from them succeeds: every emit forces the
    // peer to re-key on their next send (OTP burn; on pre-fix clients a
    // lossful local delete), so the old per-pass dedupe re-spammed it on
    // every reconnect/history pass — the SESSION_RESET{historyRetry} loop.
    if (!_rebuildRequestedPeers.add(peerId)) {
      _e2eFlowLog('SESSION_RESET_SKIPPED', {
        'peerId': peerId,
        'trigger': trigger,
        'reason': 'alreadyRequested',
      });
      return;
    }
    // NOTE: deliberately NO markSessionRebuild here. This request asks the
    // PEER to re-key; our own outbound session stays untouched — it either
    // still works, or the peer sends US sessionRebuildNeeded (the one
    // legitimate setter of the force-rebuild flag). The old mark made our
    // next send rebuild a perfectly valid session, and with the pre-fix
    // delete-on-rebuild that destroyed the archived ratchet states the
    // peer's in-flight messages needed (msg 8489 Bad-MAC class).
    _emit?.call('requestSessionRebuild', {'recipientId': peerId});
    E2ePersistentDiag.record('SESSION_RESET', {
      'peerId': peerId,
      'trigger': trigger,
    });
  }

  /// Drop peers whose inbound rows are all resolved or terminal — nothing a
  /// session rebuild could still recover. Without this, one live decrypt
  /// failure keeps the peer armed for the whole app session, and every later
  /// history pass re-fires the reset machinery (the Bad-MAC → reset loop).
  void _pruneLiveDecryptFailedPeers() {
    if (_liveDecryptFailedPeers.isEmpty) return;
    _liveDecryptFailedPeers.removeWhere((peerId) {
      final hasRecoverable = _messages.any(
        (m) => m.senderId == peerId && _isUnresolvedEncryptedInbound(m),
      );
      if (!hasRecoverable) {
        _e2eFlowLog('LIVE_RETRY_PRUNED', {'peerId': peerId});
      }
      return !hasRecoverable;
    });
  }

  Future<void> _decryptMessageHistory(int generation) async {
    _historyDecryptFailedPeers = <int>{};
    _historySessionRebuildRequested = <int>{};
    await _waitForE2EReady(maxAttempts: 100);
    if (!(_encryptionProvider?.isE2EReady ?? false)) {
      _e2eFlowLog('HISTORY_DECRYPT_SKIP_E2E_NOT_READY', {});
      return;
    }
    final toDecrypt = _messages
        .where((m) => m.needsDecryption(_currentUserId))
        .length;
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
            if (idx != -1 &&
                _messages[idx].content != _kDecryptionFailedLabel) {
              _messages[idx] = _messages[idx].copyWith(
                content: _kDecryptionFailedLabel,
              );
              changed = true;
            }
            continue;
          }
          if (_hasUsableDecryptedContent(cached) &&
              !_isEditStale(msg.editedAt, cached.editedAt)) {
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
        final persisted = await _encryptionProvider!.getDecryptedContent(
          msg.id,
        );
        final pContent = persisted?['content'] as String? ?? '';
        final persistedEditedAt = persisted?['editedAt'] != null
            ? DateTime.tryParse(persisted!['editedAt'] as String)
            : null;
        final hasPersistedPayload =
            persisted != null &&
            (pContent.isNotEmpty ||
                persisted['mediaUrl'] != null ||
                persisted['messageType'] != null);
        if (hasPersistedPayload &&
            !_isEditStale(msg.editedAt, persistedEditedAt)) {
          if (pContent == _kDecryptionFailedLabel) {
            // Terminal failure persisted — restore and skip without live decrypt.
            final idx = _messages.indexWhere((m) => m.id == msg.id);
            if (idx != -1 &&
                _messages[idx].content != _kDecryptionFailedLabel) {
              _messages[idx] = _messages[idx].copyWith(
                content: _kDecryptionFailedLabel,
              );
              changed = true;
            }
            continue;
          }
          final safeImageUrl = persisted['linkPreviewImageUrl'] as String?;
          final safePageUrl = persisted['linkPreviewUrl'] as String?;
          final validImage =
              safeImageUrl != null &&
                  safePageUrl != null &&
                  LinkPreviewService.isSafeImageUrl(safeImageUrl, safePageUrl)
              ? safeImageUrl
              : null;
          final restoredType = _parseMessageTypeString(
            persisted['messageType'] as String?,
          );
          final restored = msg.copyWith(
            content: pContent.isNotEmpty ? pContent : msg.content,
            messageType: restoredType,
            mediaUrl: persisted['mediaUrl'] as String?,
            mediaDuration: persisted['mediaDuration'] as int?,
            mediaKey: persisted['mediaKey'] as String?,
            mediaIv: persisted['mediaIv'] as String?,
            mediaWidth: persisted['mediaWidth'] as int?,
            mediaHeight: persisted['mediaHeight'] as int?,
            mediaThumbHash: persisted['mediaThumbHash'] as String?,
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
          _encryptionProvider?.cacheDecryption(msg.id, _messages[idx]);
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
          final safeImageUrl =
              rawImageUrl != null &&
                  rawPageUrl != null &&
                  LinkPreviewService.isSafeImageUrl(rawImageUrl, rawPageUrl)
              ? rawImageUrl
              : null;
          final restoredType = _parseMessageTypeString(
            stored?['messageType'] as String?,
          );
          final restored = msg.copyWith(
            content: storedContent.isNotEmpty ? storedContent : null,
            messageType: restoredType,
            mediaUrl: stored?['mediaUrl'] as String?,
            mediaDuration: stored?['mediaDuration'] as int?,
            mediaKey: stored?['mediaKey'] as String?,
            mediaIv: stored?['mediaIv'] as String?,
            mediaWidth: stored?['mediaWidth'] as int?,
            mediaHeight: stored?['mediaHeight'] as int?,
            mediaThumbHash: stored?['mediaThumbHash'] as String?,
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
        } else {
          // Lost-ack reconcile: the `messageSent` ack died with a socket drop,
          // so this own row arrived as '[encrypted]' with nothing persisted
          // under its real id. Match the durable pending-send record by EXACT
          // ciphertext equality (unique by ratchet construction — a miss means
          // stay '[encrypted]', never a heuristic guess; see the 07-08 field
          // case msg 14667 and docs/runbooks/e2e-decryption-failed.md).
          final ciphertext = msg.encryptedContent;
          // Peek (never consume-first): the pending record is the ONLY
          // surviving plaintext copy, and saveDecryptedContent swallows
          // failures — so persist, VERIFY by read-back, and only then take.
          // A failed persist leaves the record for the next history pass.
          final pending = ciphertext != null
              ? await _encryptionProvider!.peekPendingSendRecord(ciphertext)
              : null;
          if (pending != null) {
            final restoredType = _parseMessageTypeString(
              pending['messageType'] as String?,
            );
            final pendingContent = pending['content'] as String? ?? '';
            final restored = msg.copyWith(
              content: pendingContent.isNotEmpty ? pendingContent : null,
              messageType: restoredType,
              mediaUrl: pending['mediaUrl'] as String?,
              mediaDuration: pending['mediaDuration'] as int?,
              mediaKey: pending['mediaKey'] as String?,
              mediaIv: pending['mediaIv'] as String?,
              mediaWidth: pending['mediaWidth'] as int?,
              mediaHeight: pending['mediaHeight'] as int?,
              mediaThumbHash: pending['mediaThumbHash'] as String?,
              linkPreviewUrl: pending['linkPreviewUrl'] as String?,
              linkPreviewTitle: pending['linkPreviewTitle'] as String?,
              linkPreviewImageUrl: pending['linkPreviewImageUrl'] as String?,
            );
            // peek → persist → verify → take:
            await _encryptionProvider!.saveDecryptedContent(msg.id, {
              'content': pendingContent,
              if (pending['messageType'] != null)
                'messageType': pending['messageType'],
              if (pending['mediaUrl'] != null) 'mediaUrl': pending['mediaUrl'],
              if (pending['mediaDuration'] != null)
                'mediaDuration': pending['mediaDuration'],
              if (pending['mediaKey'] != null) 'mediaKey': pending['mediaKey'],
              if (pending['mediaIv'] != null) 'mediaIv': pending['mediaIv'],
              if (pending['mediaWidth'] != null)
                'mediaWidth': pending['mediaWidth'],
              if (pending['mediaHeight'] != null)
                'mediaHeight': pending['mediaHeight'],
              if (pending['mediaThumbHash'] != null)
                'mediaThumbHash': pending['mediaThumbHash'],
              if (pending['linkPreviewUrl'] != null)
                'linkPreviewUrl': pending['linkPreviewUrl'],
              if (pending['linkPreviewTitle'] != null)
                'linkPreviewTitle': pending['linkPreviewTitle'],
              if (pending['linkPreviewImageUrl'] != null)
                'linkPreviewImageUrl': pending['linkPreviewImageUrl'],
            });
            final persisted = await _encryptionProvider!.getDecryptedContent(
              msg.id,
            );
            final verified =
                (persisted?['content'] as String? ?? '') == pendingContent &&
                (pendingContent.isNotEmpty ||
                    persisted?['messageType'] != null);
            if (verified) {
              await _encryptionProvider!.takePendingSendRecord(ciphertext!);
            }
            final idx = _messages.indexWhere((m) => m.id == msg.id);
            if (idx != -1) {
              final merged = _mergeMessagePreferNewer(_messages[idx], restored);
              _messages[idx] = merged;
              _encryptionProvider?.cacheDecryption(msg.id, merged);
              changed = true;
            }
            _e2eFlowLog('SEND_ACK_RECONCILED', {
              'msgId': msg.id,
              'persistVerified': verified,
            });
            E2ePersistentDiag.record('SEND_ACK_RECONCILED', {
              'msgId': msg.id,
              'persistVerified': verified,
            });
          }
        }
      }
    }
    if (_decryptHistoryGeneration == generation) {
      final peersNeedingRetry = <int>{
        ...?_historyDecryptFailedPeers,
        ..._liveDecryptFailedPeers,
        for (final m in _messages)
          if (_isUnresolvedEncryptedInbound(m)) m.senderId,
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
      // Rows that stayed locked are terminal now — disarm their peers so the
      // next pass doesn't re-run the reset machinery for unrecoverable rows.
      _pruneLiveDecryptFailedPeers();
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
      if (_isUnresolvedEncryptedInbound(m)) {
        unresolvedPeers.add(m.senderId);
      }
    }
    if (unresolvedPeers.isEmpty) return false;
    // Dedupe against the rebuilds _retryDecryptForPeers already requested this
    // pass — the old double emit made the peer discard their session twice.
    final rebuildRequested = _historySessionRebuildRequested ??= <int>{};
    for (final peerId in unresolvedPeers) {
      if (rebuildRequested.add(peerId)) {
        _requestSessionRebuildForPeer(peerId, trigger: 'recoverUnresolved');
      }
    }
    _e2eFlowLog('E2E_RECOVERY_SESSION_RESET', {
      'peerIds': unresolvedPeers.toList(),
    });
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

  /// After history/live decrypt failures, request a session rebuild from each
  /// peer (once per pass) and replay decrypt oldest-first. Does not downgrade
  /// [Decryption failed] to [encrypted] — failed rows stay failed until decrypt succeeds.
  ///
  /// This path must NEVER call deleteSessionWithPeer. Deleting the local
  /// SessionRecord wipes the current AND archived ratchet states, so every
  /// message the peer already encrypted with them becomes a permanent Bad-MAC
  /// loss — that is the mid-conversation [Decryption failed] cascade. The
  /// rebuild *request* is lossless: when either side later sends a PreKey
  /// message, libsignal archives the old state instead of destroying it, so
  /// in-flight old-session messages stay decryptable.
  Future<bool> _retryDecryptForPeers(
    int generation,
    Set<int> peerIds, {
    String trigger = 'historyRetry',
  }) async {
    bool changed = false;
    final rebuildRequested = _historySessionRebuildRequested ??= <int>{};
    for (final peerId in peerIds) {
      if (_decryptHistoryGeneration != generation) return changed;
      if (rebuildRequested.add(peerId)) {
        _requestSessionRebuildForPeer(peerId, trigger: trigger);
      }
    }

    final sorted =
        _messages
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
      // [Decryption failed] is terminal (same guard as the main history loop):
      // re-attempting it can only fail again, and the failure re-arms the
      // retry sets — that re-arming is what kept the reset loop alive forever.
      if (row.content == _kDecryptionFailedLabel) continue;
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
    _pruneLiveDecryptFailedPeers();
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
    final changed = await _retryDecryptForPeers(
      gen,
      peers,
      trigger: 'liveRetry',
    );
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
    return _runDecryptSerialized(msg.senderId, () => _decryptMessageAsync(msg));
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

    // hasSession + ciphertext type make every failure self-explaining in the
    // field: a type-1 (Signal) message with hasSession:false is state loss on
    // our side; type 3 (PreKey) failing means OTP/identity trouble. Ids,
    // types and booleans only — never plaintext or key material.
    final hadSessionAtDecrypt = await _encryptionProvider!.hasSessionWith(
      msg.senderId,
    );
    _e2eFlowLog('DECRYPT_START', {
      'msgId': msg.id,
      'senderId': msg.senderId,
      'ctype': _ciphertextType(msg.encryptedContent),
      'hasSession': hadSessionAtDecrypt,
    });
    try {
      final plaintext = await _encryptionProvider!.decrypt(
        msg.senderId,
        msg.encryptedContent!,
      );
      // Decrypt from this peer works again — allow a future failure to issue
      // a fresh rebuild request.
      _rebuildRequestedPeers.remove(msg.senderId);
      try {
        final parsed = E2eEnvelope.parse(plaintext);
        _e2eFlowLog('DECRYPT_OK', {
          'msgId': msg.id,
          'contentLength': parsed.content.length,
        });
        // SSRF: validate imageUrl before storing
        final safeImageUrl =
            parsed.linkPreviewImageUrl != null &&
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
          mediaWidth: parsed.mediaWidth,
          mediaHeight: parsed.mediaHeight,
          mediaThumbHash: parsed.mediaThumbHash,
          linkPreviewUrl: parsed.linkPreviewUrl,
          linkPreviewTitle: parsed.linkPreviewTitle,
          linkPreviewImageUrl: safeImageUrl,
        );
        // Trigger ping effect for recipient when decrypted type is PING
        if (parsedType == MessageType.ping && msg.senderId != _currentUserId) {
          _showPingEffect = true;
        }
        _encryptionProvider?.cacheDecryption(msg.id, decryptedMsg);
        await _persistDecryptedContent(decryptedMsg);
        return decryptedMsg;
      } catch (parseErr) {
        debugPrint(
          '[E2E] Envelope parse failed for msg ${msg.id}, using raw plaintext: $parseErr',
        );
        final fallback = msg.copyWith(content: plaintext);
        _encryptionProvider?.cacheDecryption(msg.id, fallback);
        if (plaintext.isNotEmpty) await _persistDecryptedContent(fallback);
        return fallback;
      }
    } catch (e) {
      final cached = _encryptionProvider?.getCachedDecryption(msg.id);
      if (cached != null && _hasUsableDecryptedContent(cached)) return cached;
      if (_hasUsableDecryptedContent(msg)) return msg;

      final persisted = await _encryptionProvider!.getDecryptedContent(msg.id);
      final persistedContent = persisted?['content'] as String? ?? '';
      final canRestorePersisted =
          persisted != null &&
          (persistedContent.isNotEmpty ||
              persisted['mediaUrl'] != null ||
              persisted['messageType'] != null);
      if (canRestorePersisted) {
        final rawImageUrl = persisted['linkPreviewImageUrl'] as String?;
        final rawPageUrl = persisted['linkPreviewUrl'] as String?;
        final safeImageUrl =
            rawImageUrl != null &&
                rawPageUrl != null &&
                LinkPreviewService.isSafeImageUrl(rawImageUrl, rawPageUrl)
            ? rawImageUrl
            : null;
        final restoredType = _parseMessageTypeString(
          persisted['messageType'] as String?,
        );
        final restored = msg.copyWith(
          content: persistedContent.isNotEmpty ? persistedContent : msg.content,
          messageType: restoredType,
          mediaUrl: persisted['mediaUrl'] as String?,
          mediaDuration: persisted['mediaDuration'] as int?,
          mediaKey: persisted['mediaKey'] as String?,
          mediaIv: persisted['mediaIv'] as String?,
          mediaWidth: persisted['mediaWidth'] as int?,
          mediaHeight: persisted['mediaHeight'] as int?,
          mediaThumbHash: persisted['mediaThumbHash'] as String?,
          linkPreviewUrl: persisted['linkPreviewUrl'] as String?,
          linkPreviewTitle: persisted['linkPreviewTitle'] as String?,
          linkPreviewImageUrl: safeImageUrl,
        );
        if (_hasUsableDecryptedContent(restored)) {
          _encryptionProvider?.cacheDecryption(msg.id, restored);
          return restored;
        }
      }

      // Decision logic extracted to a pure, characterization-tested policy
      // (utils/decryption_failure_policy.dart). A wrong branch here deletes a
      // working Signal session, so the branching is unit-tested in isolation.
      // Precedence: duplicate/badMac (terminal, persist) > identityReset
      // (terminal, no persist) > noSession (keep [encrypted], retry) > unknown
      // (live: terminal+retry; history: keep [encrypted], retry).
      final kind = _classifyDecryptError(e);
      final decision = decideDecryptionFailure(
        kind,
        hadIdentityReset: _encryptionProvider?.hadIdentityReset == true,
        isHistory: _decryptingHistory,
      );
      _logDecryptionFailure(decision.rule, msg, e);
      // One line that fully explains the outcome of this failure: what the
      // error was classified as, which rule fired and with which inputs, and
      // exactly what the caller will do about it.
      E2ePersistentDiag.record('DECRYPT_DECISION', {
        'msgId': msg.id,
        'senderId': msg.senderId,
        'kind': kind.name,
        'rule': decision.rule.name,
        'isHistory': _decryptingHistory,
        'idReset': _encryptionProvider?.hadIdentityReset == true,
        'hadSession': hadSessionAtDecrypt,
        'persist': decision.persistTerminalFailure,
        'markFailed': decision.markContentFailed,
        'retry': decision.retryAction.name,
        'notifyPeer': decision.notifyPeerRebuild,
      });
      if (decision.persistTerminalFailure) {
        // Persist so future app starts skip this message without re-attempting.
        await _encryptionProvider?.saveDecryptedContent(msg.id, {
          'content': _kDecryptionFailedLabel,
        });
      }
      if (decision.notifyPeerRebuild) {
        if (decision.rule == DecryptionFailureRule.identityReset) {
          if (_identityResetRebuildNotified.add(msg.senderId)) {
            // Identity reset: tell the peer to re-key on their next send. No
            // local state is touched (there is none to protect — the old
            // identity is gone); without this the peer keeps sending
            // undecryptable messages until we happen to reply.
            _emit?.call('requestSessionRebuild', {'recipientId': msg.senderId});
            _e2eFlowLog('IDENTITY_RESET_REBUILD_REQUESTED', {
              'peerId': msg.senderId,
            });
          }
        } else if (decision.rule == DecryptionFailureRule.badMac) {
          // The failed row is unrecoverable, but a Bad MAC on a fresh type-2
          // message is evidence the peer is encrypting from a stale sender
          // ratchet. Ask them to build over their session on the next send.
          _requestSessionRebuildForPeer(msg.senderId, trigger: 'badMac');
        }
      }
      switch (decision.retryAction) {
        case DecryptionRetryAction.markHistoryPeerForRetry:
          // Keep [encrypted] until retry + session reset finish (see
          // [_markHistoryDecryptFailuresAfterRetry]).
          _historyDecryptFailedPeers?.add(msg.senderId);
          break;
        case DecryptionRetryAction.scheduleLiveRetry:
          _scheduleLiveDecryptRetry(msg.senderId);
          break;
        case DecryptionRetryAction.none:
          break;
      }
      return decision.markContentFailed
          ? msg.copyWith(content: _kDecryptionFailedLabel)
          : msg;
    }
  }
}
