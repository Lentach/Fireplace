import 'dart:convert';

import 'package:fireplace/providers/encryption_provider.dart';
import 'package:fireplace/providers/messaging_provider.dart';
import 'package:fireplace/utils/e2e_envelope.dart';
import 'package:flutter_test/flutter_test.dart';

/// Chat-entry hydration contracts.
///
/// The server ships `content: "[encrypted]"` for every E2E row, so a history
/// snapshot is all placeholders until local plaintext is applied. Two things
/// used to go wrong on entry to a chat with real history:
///
///  1. the snapshot was merged and painted BEFORE any plaintext was applied,
///     so the list showed "[encrypted]" and flipped to real text once the
///     async decrypt pass finished — the reported flash; and
///  2. that pass resolved plaintext ONE ROW AT A TIME, each read paying a full
///     `SharedPreferences.reload()` on web (a complete localStorage
///     enumeration + JSON decode of every cached record), which is what made
///     the flash long enough to see and janked the entry.
///
/// These tests pin both, plus the safety properties the batching must not
/// trade away.
class _RecordingEncryption extends EncryptionProvider {
  _RecordingEncryption({Map<int, Map<String, dynamic>>? persisted})
    : persisted = <int, Map<String, dynamic>>{...?persisted};

  /// messageId -> persisted plaintext payload.
  final Map<int, Map<String, dynamic>> persisted;

  /// Ids the batched read refuses to answer, to model a record that only the
  /// single (legacy-store) read can resolve.
  final Set<int> hideFromBatch = <int>{};

  int singleReads = 0;
  int batchedReads = 0;
  int decryptCalls = 0;

  /// Gates the history decrypt pass the way a not-yet-initialised E2E stack
  /// does, so a pass can be driven with rows already sitting as placeholders.
  bool ready = true;
  void markReady() => ready = true;

  @override
  bool get isE2EReady => ready;

  @override
  bool get hadIdentityReset => false;

  @override
  Future<void> deleteSessionWithPeer(int peerUserId) async {}

  @override
  Future<void> ensureSession(int recipientId) async {}

  @override
  Future<String> decrypt(
    int senderId,
    String ciphertext, {
    int? messageId,
  }) async {
    decryptCalls++;
    return jsonEncode(E2eEnvelope.build('live-decrypt-$messageId'));
  }

  @override
  Future<Map<String, dynamic>?> getDecryptedContent(int messageId) async {
    singleReads++;
    return persisted[messageId];
  }

  @override
  Future<Map<int, Map<String, dynamic>>> getDecryptedContentMany(
    Iterable<int> messageIds,
  ) async {
    batchedReads++;
    final out = <int, Map<String, dynamic>>{};
    for (final id in messageIds) {
      if (hideFromBatch.contains(id)) continue;
      final hit = persisted[id];
      if (hit != null) out[id] = hit;
    }
    return out;
  }
}

Map<String, dynamic> inboundJson(int id) => {
  'id': id,
  'content': '[encrypted]',
  'encryptedContent': 'cipher-$id',
  'senderId': 2,
  'senderUsername': 'bob',
  'conversationId': 10,
  'deliveryStatus': 'DELIVERED',
  'messageType': 'TEXT',
  'createdAt': DateTime.utc(2026, 1, 1).add(Duration(seconds: id))
      .toIso8601String(),
};

Future<void> pump() async {
  for (var i = 0; i < 40; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('chat entry hydration', () {
    late MessagingProvider provider;

    setUp(() {
      provider = MessagingProvider();
      provider.onConnect(false);
      provider.setCurrentUserId(1);
      provider.setToken('tok');
      provider.setActiveConversationIdForTest(10);
    });

    tearDown(() => provider.dispose());

    /// THE FLICKER. Every row's plaintext is already on disk, so entering the
    /// chat must never expose a frame holding "[encrypted]". Before the
    /// pre-paint hydration, the merge notified with raw server placeholders and
    /// only the post-decrypt notify carried plaintext, so the very first
    /// snapshot here was all placeholders.
    test('no notification ever exposes a placeholder row when plaintext is '
        'already persisted', () async {
      final encryption = _RecordingEncryption(
        persisted: {
          for (var id = 1; id <= 30; id++)
            id: <String, dynamic>{'content': 'plain-$id'},
        },
      );
      provider.setEncryptionProvider(encryption);

      final placeholderFrames = <List<String>>[];
      provider.addListener(() {
        final contents = provider.messages.map((m) => m.content).toList();
        if (contents.any((c) => c == '[encrypted]')) {
          placeholderFrames.add(contents);
        }
      });

      provider.getMessages(10);
      provider.onMessageHistory({
        'conversationId': 10,
        'messages': [for (var id = 1; id <= 30; id++) inboundJson(id)],
      });
      await pump();

      expect(
        placeholderFrames,
        isEmpty,
        reason:
            'a snapshot whose plaintext is already cached must never be '
            'painted as "[encrypted]" first',
      );
      expect(provider.messages.length, 30);
      expect(provider.messages.first.content, 'plain-1');
      expect(provider.messages.last.content, 'plain-30');
      expect(
        encryption.decryptCalls,
        0,
        reason: 'cached plaintext must never re-run Signal',
      );
    });

    /// THE COST. One batched read for the whole entry instead of one
    /// per-message read (each of which reloads the entire prefs store on web).
    /// Before the fix this was 30 single reads; the bound is what keeps the
    /// entry O(1) in storage round trips rather than O(history).
    test('resolves a whole history page with a bounded number of storage '
        'reads', () async {
      final encryption = _RecordingEncryption(
        persisted: {
          for (var id = 1; id <= 30; id++)
            id: <String, dynamic>{'content': 'plain-$id'},
        },
      );
      provider.setEncryptionProvider(encryption);

      provider.getMessages(10);
      provider.onMessageHistory({
        'conversationId': 10,
        'messages': [for (var id = 1; id <= 30; id++) inboundJson(id)],
      });
      await pump();

      expect(
        encryption.singleReads,
        0,
        reason:
            'every row was answered by the batch; a per-row read is the '
            'per-row prefs.reload() this fix removed',
      );
      expect(
        encryption.batchedReads,
        lessThanOrEqualTo(2),
        reason: 'at most one batch to hydrate the paint, one for the pass',
      );
    });

    /// THE COST, at the history-pass level. The pre-paint hydration covers the
    /// normal entry, but the decrypt pass runs on its own for a retry after
    /// E2E comes up, for pagination, and for rows that arrive between passes.
    /// It must also resolve its rows from ONE batched read rather than a read
    /// (and therefore a full prefs reload on web) per row.
    test('a history decrypt pass over placeholder rows takes one batched read, '
        'not one per row', () async {
      final encryption = _RecordingEncryption()..ready = false;
      provider.setEncryptionProvider(encryption);

      // E2E is not up yet: the snapshot lands as placeholders and the pass
      // bails without resolving anything.
      provider.getMessages(10);
      await provider.onMessageHistory({
        'conversationId': 10,
        'messages': [for (var id = 1; id <= 30; id++) inboundJson(id)],
      });
      await pump();
      expect(
        provider.messages.every((m) => m.displayAsEncryptedPlaceholder),
        isTrue,
        reason: 'precondition: the pass has not resolved these rows yet',
      );

      // Plaintext becomes readable and E2E comes up — now drive the pass.
      for (var id = 1; id <= 30; id++) {
        encryption.persisted[id] = <String, dynamic>{'content': 'plain-$id'};
      }
      encryption.markReady();
      encryption.singleReads = 0;
      encryption.batchedReads = 0;

      await provider.retryDecryptActiveConversation();
      await pump();

      expect(provider.messages.first.content, 'plain-1');
      expect(provider.messages.last.content, 'plain-30');
      expect(
        encryption.decryptCalls,
        0,
        reason: 'persisted plaintext must never re-run Signal',
      );
      expect(
        encryption.singleReads,
        0,
        reason:
            'the pass prefetches once; a per-row read here is the per-row '
            'prefs.reload() this fix removed',
      );
      expect(encryption.batchedReads, 1);
    });

    /// A BATCH MISS IS NOT AN ANSWER. The batch covers the SharedPreferences
    /// namespace only; the mobile legacy store is reachable solely through the
    /// single read. Treating an absent id as "no plaintext" would strand the
    /// row on "[encrypted]" — the exact bug this change is meant to remove.
    test('a row the batch cannot answer still resolves through the single '
        'read', () async {
      final encryption = _RecordingEncryption(
        persisted: {
          1: <String, dynamic>{'content': 'plain-1'},
          2: <String, dynamic>{'content': 'legacy-only-2'},
        },
      )..hideFromBatch.add(2);
      provider.setEncryptionProvider(encryption);

      provider.getMessages(10);
      provider.onMessageHistory({
        'conversationId': 10,
        'messages': [inboundJson(1), inboundJson(2)],
      });
      await pump();

      expect(
        provider.messages.firstWhere((m) => m.id == 2).content,
        'legacy-only-2',
      );
      expect(
        encryption.decryptCalls,
        0,
        reason: 'a batch miss must fall through to the read, not re-decrypt',
      );
    });

    /// Rows with no plaintext anywhere must still reach the live decrypt — the
    /// hydration is an accelerator, never a gate.
    test('rows with no cached plaintext still live-decrypt', () async {
      final encryption = _RecordingEncryption(
        persisted: {1: <String, dynamic>{'content': 'plain-1'}},
      );
      provider.setEncryptionProvider(encryption);

      provider.getMessages(10);
      provider.onMessageHistory({
        'conversationId': 10,
        'messages': [inboundJson(1), inboundJson(2)],
      });
      await pump();

      expect(provider.messages.firstWhere((m) => m.id == 1).content, 'plain-1');
      expect(
        provider.messages.firstWhere((m) => m.id == 2).content,
        'live-decrypt-2',
      );
      expect(encryption.decryptCalls, 1);
    });

    /// The hydration introduced a suspension point before the merge. A history
    /// payload that was superseded while it hydrated must not land in the
    /// visible list against the newer conversation's state.
    test('a snapshot superseded while hydrating never reaches the message '
        'list', () async {
      final encryption = _RecordingEncryption(
        persisted: {
          for (var id = 1; id <= 5; id++)
            id: <String, dynamic>{'content': 'plain-$id'},
        },
      );
      provider.setEncryptionProvider(encryption);

      provider.getMessages(10);
      final inFlight = provider.onMessageHistory({
        'conversationId': 10,
        'messages': [for (var id = 1; id <= 5; id++) inboundJson(id)],
      });
      // A newer fetch is issued before the hydrate resolves.
      provider.getMessages(10);
      await inFlight;
      await pump();

      expect(
        provider.messages,
        isEmpty,
        reason:
            'the superseded payload must not paint; the newer fetch owns the '
            'list',
      );
      expect(
        provider.cacheMessageForTest(10, 1)?.content,
        'plain-1',
        reason:
            'its plaintext is still kept in the conversation cache, never '
            'discarded',
      );
      expect(provider.cacheMessageForTest(10, 5)?.content, 'plain-5');
    });
  });
}
