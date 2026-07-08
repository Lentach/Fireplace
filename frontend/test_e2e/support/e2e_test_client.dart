// Support library for the full-stack two-account E2E wire harness.
//
// NOT part of the default `flutter test` suite (lives in `test_e2e/`, a
// sibling of `test/`). Requires a locally running backend:
//
//   docker-compose up            # repo root: backend :3000 + Postgres
//   cd frontend && flutter test test_e2e
//
// Register throttle is 10/hr per IP and the throttler store is in-memory —
// `docker compose restart backend` resets counters when iterating.
//
// Each E2eClient runs the app's REAL service stack: ApiService (REST auth),
// SocketService (Socket.IO wire), EncryptionService (real libsignal). Only
// the Signal key storage is mocked (in-memory, per-user `e2e_<id>_` prefixes),
// exactly like the existing encryption_service_roundtrip_test.dart.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:fireplace/services/api_service.dart';
import 'package:fireplace/services/encryption_service.dart';
import 'package:fireplace/services/socket_service.dart';
import 'package:fireplace/utils/e2e_envelope.dart';

/// Base URL of the backend under test. Override with the E2E_BASE_URL
/// environment variable when the backend is not on localhost:3000.
String e2eBaseUrl() =>
    Platform.environment['E2E_BASE_URL'] ?? 'http://localhost:3000';

/// The flutter_test binding installs a global HttpOverrides that answers
/// every real HttpClient request with HTTP 400 — including the WebSocket
/// upgrade socket_io_client performs. Call this once AFTER
/// `TestWidgetsFlutterBinding.ensureInitialized()` to restore real
/// networking. Global (not zone-local) on purpose: socket.io reconnect
/// timers can fire outside the test body's zone.
void enableRealNetwork() {
  HttpOverrides.global = null;
}

/// Fails fast (clear message instead of a timeout soup) when the backend is
/// not reachable.
Future<void> requireBackendUp(String baseUrl) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
  try {
    final req = await client.getUrl(Uri.parse('$baseUrl/health'));
    final res = await req.close().timeout(const Duration(seconds: 3));
    await res.drain<void>();
    if (res.statusCode != 200) {
      throw StateError(
          'Backend /health returned ${res.statusCode} at $baseUrl');
    }
  } on StateError {
    rethrow;
  } catch (e) {
    throw StateError(
        'Backend not reachable at $baseUrl ($e).\n'
        'Start it first: `docker-compose up` from the repo root, '
        'then re-run `flutter test test_e2e`.');
  } finally {
    client.close(force: true);
  }
}

class _Waiter {
  _Waiter(this.event, this.where, this.completer);
  final String event;
  final bool Function(dynamic payload)? where;
  final Completer<dynamic> completer;
}

/// Records every tracked socket event and lets tests await one — including
/// events that arrived BEFORE the await (buffered, consumed in order).
class EventLog {
  final Map<String, List<dynamic>> _buffer = {};
  final List<_Waiter> _waiters = [];

  /// `error` events, kept separately so timeout messages can surface them.
  final List<dynamic> errors = [];

  void record(String event, dynamic payload) {
    if (event == 'error') {
      errors.add(payload);
    }
    for (var i = 0; i < _waiters.length; i++) {
      final w = _waiters[i];
      if (w.event == event && (w.where == null || w.where!(payload))) {
        _waiters.removeAt(i);
        w.completer.complete(payload);
        return;
      }
    }
    _buffer.putIfAbsent(event, () => []).add(payload);
  }

  /// Waits for the next [event] payload (optionally matching [where]).
  /// Buffered payloads are consumed first, in arrival order.
  Future<dynamic> next(
    String event, {
    bool Function(dynamic payload)? where,
    Duration timeout = const Duration(seconds: 10),
    String? reason,
  }) {
    final buffered = _buffer[event];
    if (buffered != null) {
      for (var i = 0; i < buffered.length; i++) {
        if (where == null || where(buffered[i])) {
          final payload = buffered.removeAt(i);
          if (buffered.isEmpty) _buffer.remove(event);
          return Future.value(payload);
        }
      }
    }
    final completer = Completer<dynamic>();
    final waiter = _Waiter(event, where, completer);
    _waiters.add(waiter);
    return completer.future.timeout(timeout, onTimeout: () {
      _waiters.remove(waiter);
      final seen = _buffer.entries
          .map((e) => '${e.key} x${e.value.length}')
          .join(', ');
      throw TimeoutException(
          'Timed out waiting for "$event"'
          '${reason != null ? ' ($reason)' : ''}. '
          'Buffered events: [$seen]. '
          'Socket errors so far: $errors');
    });
  }
}

/// One headless account running the real client service stack.
class E2eClient {
  E2eClient(this.label, this.baseUrl) : api = ApiService(baseUrl: baseUrl);

  final String label;
  final String baseUrl;
  final ApiService api;
  final SocketService socketService = SocketService();
  final EncryptionService encryption = EncryptionService();
  final EventLog events = EventLog();

  late int userId;
  late String username;
  late String tag;
  late String accessToken;

  /// Satisfies backend policy: >=8 chars, upper + lower + digit.
  static const String password = 'E2eHarness1x';

  /// Every server emission the harness asserts on (or wants visible in
  /// timeout diagnostics). Anything not listed is simply not recorded.
  static const List<String> _trackedEvents = [
    'socketReady',
    'error',
    'keyBundleUploaded',
    'oneTimePreKeysUploaded',
    'preKeyBundleResponse',
    'preKeysLow',
    'sessionRebuildNeeded',
    'newFriendRequest',
    'friendRequestSent',
    'friendRequestAccepted',
    'friendsList',
    'conversationsList',
    'pendingRequestsCount',
    'openConversation',
    'messageSent',
    'newMessage',
    'messageHistory',
    'messageEdited',
    'editMessageFailed',
    'reactionUpdated',
  ];

  /// Registers a brand-new account. Fresh every run BY DESIGN: reusing
  /// accounts with fresh client keys would get served a stale previous-run
  /// one-time pre-key (server keeps old unused OTPs, oldest-first) and fail
  /// with a phantom bad MAC.
  Future<void> registerFresh() async {
    final suffix = _randomHex(8);
    final name = 'e2e_${label}_$suffix'; // <=20 chars, [a-zA-Z0-9_]
    final data = await api.register(name, password);
    userId = data['id'] as int;
    username = data['username'] as String;
    tag = data['tag'] as String;
    final login = await api.login('$username#$tag', password);
    accessToken = login['access_token'] as String;
  }

  /// Connects the real Socket.IO client and waits for the server's
  /// `socketReady` (auth complete) before returning.
  Future<void> connectSocket() async {
    socketService.connect(baseUrl: baseUrl, token: accessToken);
    for (final event in _trackedEvents) {
      socketService.on(event, (payload) => events.record(event, payload));
    }
    final connectError = Completer<dynamic>();
    socketService.socket!.on('connect_error', (e) {
      if (!connectError.isCompleted) connectError.complete(e);
    });
    await Future.any([
      events.next('socketReady', reason: '$label socket auth'),
      connectError.future.then((e) =>
          throw StateError('$label socket connect_error: $e')),
    ]);
  }

  /// Initializes Signal keys (fresh mock storage → always generates) and
  /// uploads bundle + one-time pre-keys over WS, exactly like
  /// EncryptionProvider does on first run.
  Future<void> initializeAndUploadKeys() async {
    await encryption.initialize(userId);
    final keys = encryption.getKeysForUpload();
    if (keys == null) {
      throw StateError(
          '$label: fresh EncryptionService produced no keys for upload');
    }
    socketService
        .uploadKeyBundle((keys['keyBundle'] as Map).cast<String, dynamic>());
    await events.next('keyBundleUploaded', reason: '$label key bundle');
    socketService.uploadOneTimePreKeys(
        (keys['oneTimePreKeys'] as List).cast<Map<String, dynamic>>());
    await events.next('oneTimePreKeysUploaded', reason: '$label OTPs');
  }

  /// Server enforces a 750 ms per-(requester,target) gap between bundle
  /// fetches (PRE_KEY_FETCH_MIN_INTERVAL_MS); pace with margin so the
  /// harness never trips it into an `error` event.
  static const Duration _bundleFetchGap = Duration(milliseconds: 850);
  final Map<int, DateTime> _lastBundleFetch = {};

  /// Fetches the peer's pre-key bundle over WS. The response bundle is
  /// already flat — directly consumable by EncryptionService.buildSession.
  Future<Map<String, dynamic>> fetchBundleFor(int peerUserId) async {
    final last = _lastBundleFetch[peerUserId];
    if (last != null) {
      final wait = _bundleFetchGap - DateTime.now().difference(last);
      if (wait > Duration.zero) {
        await Future<void>.delayed(wait);
      }
    }
    _lastBundleFetch[peerUserId] = DateTime.now();
    socketService.fetchPreKeyBundle(peerUserId);
    final payload = await events.next(
      'preKeyBundleResponse',
      where: (p) => p is Map && p['userId'] == peerUserId,
      reason: '$label fetching bundle for user $peerUserId',
    ) as Map;
    final bundle = payload['bundle'];
    if (bundle is! Map) {
      throw StateError(
          '$label: no key bundle on server for user $peerUserId: $payload');
    }
    return bundle.cast<String, dynamic>();
  }

  /// Encrypts [content] in the app's real E2E envelope wire format.
  Future<String> encryptText(int peerUserId, String content) {
    final envelopeJson = jsonEncode(E2eEnvelope.build(content));
    return encryption.encrypt(peerUserId, envelopeJson);
  }

  /// Decrypts a wire ciphertext and returns the envelope's text content.
  Future<String> decryptText(int peerUserId, String ciphertext) async {
    final envelopeJson = await encryption.decrypt(peerUserId, ciphertext);
    return E2eEnvelope.parse(envelopeJson).content;
  }

  /// Emits `sendMessage` with the app's real payload shape and returns the
  /// server's `messageSent` confirmation for [tempId].
  Future<Map<String, dynamic>> sendEncrypted(
    int recipientId,
    String ciphertext, {
    required String tempId,
  }) async {
    socketService.sendMessage(
      recipientId,
      '[encrypted]',
      tempId: tempId,
      encryptedContent: ciphertext,
    );
    final payload = await events.next(
      'messageSent',
      where: (p) => p is Map && p['tempId'] == tempId,
      reason: '$label sendMessage tempId=$tempId',
    ) as Map;
    return payload.cast<String, dynamic>();
  }

  /// Waits for an inbound `newMessage` matching [tempId] (the mapper echoes
  /// the sender's tempId to both sides).
  Future<Map<String, dynamic>> awaitNewMessage(String tempId) async {
    final payload = await events.next(
      'newMessage',
      where: (p) => p is Map && p['tempId'] == tempId,
      reason: '$label newMessage tempId=$tempId',
    ) as Map;
    return payload.cast<String, dynamic>();
  }

  /// Emits `editMessage`. There is deliberately no SocketService emitter for
  /// this event — the app sends it through ConnectionProvider.emit's raw
  /// socket path, which this mirrors.
  void emitEditMessage(int messageId, String newCiphertext) {
    socketService.socket!.emit('editMessage', {
      'messageId': messageId,
      'content': '[encrypted]',
      'encryptedContent': newCiphertext,
    });
  }

  void dispose() {
    socketService.disconnect();
  }

  static String _randomHex(int chars) {
    final rng = Random.secure();
    return List.generate(chars, (_) => rng.nextInt(16).toRadixString(16))
        .join();
  }
}
