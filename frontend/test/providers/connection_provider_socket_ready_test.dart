import 'package:fireplace/providers/connection_provider.dart';
import 'package:fireplace/providers/conversations_provider.dart';
import 'package:fireplace/providers/encryption_provider.dart';
import 'package:fireplace/providers/friends_provider.dart';
import 'package:fireplace/providers/messaging_provider.dart';
import 'package:fireplace/services/socket_service.dart';
import 'package:fireplace/services/server_clock.dart';
import 'package:flutter_test/flutter_test.dart';

/// Test double for [SocketService] — simulates connect / socketReady without I/O.
class FakeSocketService extends SocketService {
  final Map<String, List<void Function(dynamic)>> _handlers = {};
  void Function()? _onConnectCallback;

  int getConversationsCalls = 0;
  int getFriendRequestsCalls = 0;
  int getFriendsCalls = 0;
  int getBlockedListCalls = 0;

  /// `getServedMessageIds` emissions as (requestId, ids).
  final servedIdRequests = <MapEntry<String, List<int>>>[];
  final getMessagesConversationIds = <int>[];
  @override
  bool get isConnected => true;

  @override
  void connect({required String baseUrl, required String token}) {}

  @override
  void disconnect() {}


  @override
  void getMessages(int conversationId, {int? limit, int? offset}) {
    getMessagesConversationIds.add(conversationId);
  }
  @override
  void on(String event, void Function(dynamic) callback) {
    _handlers.putIfAbsent(event, () => []).add(callback);
  }

  @override
  void onConnect(void Function() callback) {
    _onConnectCallback = callback;
  }

  @override
  void onDisconnect(void Function(dynamic) callback) {}

  void simulateTransportConnect() {
    _onConnectCallback?.call();
  }

  /// [payload] mirrors the real `socketReady` body. The server sends
  /// `{serverTime: <ISO-8601>}`; null covers an older server that sends none.
  void simulateSocketReady({Object? payload}) {
    for (final handler in _handlers['socketReady'] ?? const []) {
      handler(payload);
    }
  }

  @override
  void getServedMessageIds(String requestId, List<int> messageIds) {
    servedIdRequests.add(MapEntry(requestId, messageIds));
  }

  void simulateServedMessageIds(Object? payload) {
    for (final handler in _handlers['servedMessageIds'] ?? const []) {
      handler(payload);
    }
  }

  @override
  void getConversations() {
    getConversationsCalls++;
  }

  @override
  void getFriendRequests() {
    getFriendRequestsCalls++;
  }

  @override
  void getFriends() {
    getFriendsCalls++;
  }

  @override
  void getBlockedList() {
    getBlockedListCalls++;
  }
}

class RecordingConnectionProvider extends ConnectionProvider {
  RecordingConnectionProvider({required SocketService socketService})
      : super(socketService: socketService);

  final emitted = <MapEntry<String, dynamic>>[];

  @override
  void emit(String event, dynamic data) {
    emitted.add(MapEntry(event, data));
  }
}

/// Records the local-plaintext maintenance calls `_onSocketReady` fires.
class _RecordingEncryption extends EncryptionProvider {
  final calls = <String>[];

  @override
  Future<void> loadRetiredIds() async => calls.add('loadRetiredIds');

  @override
  Future<void> drainPurgeBacklog() async => calls.add('drainPurgeBacklog');

  @override
  Future<void> sweepDestroyablePlaintext() async =>
      calls.add('sweepDestroyablePlaintext');

  @override
  Future<void> reconcileStoredPlaintext(
    Future<Set<int>?> Function(Set<int> batch) askServer, {
    bool force = false,
  }) async =>
      calls.add('reconcileStoredPlaintext');
}

/// Drives ONE real `getServedMessageIds` round trip through
/// [ConnectionProvider]'s socket plumbing and records what came back.
class _RoundTripEncryption extends EncryptionProvider {
  Set<int>? answer;
  bool answered = false;

  @override
  Future<void> loadRetiredIds() async {}

  @override
  Future<void> drainPurgeBacklog() async {}

  @override
  Future<void> sweepDestroyablePlaintext() async {}

  @override
  Future<void> reconcileStoredPlaintext(
    Future<Set<int>?> Function(Set<int> batch) askServer, {
    bool force = false,
  }) async {
    answer = await askServer({1, 2, 3});
    answered = true;
  }
}

Map<String, dynamic> _convJson(int id) => {
      'id': id,
      'userOne': {'id': 1, 'username': 'alice', 'tag': '0001'},
      'userTwo': {'id': 2, 'username': 'bob', 'tag': '0002'},
      'createdAt': DateTime(2026, 1, 1).toIso8601String(),
      'unreadCount': 0,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConnectionProvider socketReady gating', () {
    late FakeSocketService fakeSocket;
    late RecordingConnectionProvider connection;

    setUp(() {
      fakeSocket = FakeSocketService();
      connection = RecordingConnectionProvider(socketService: fakeSocket);
    });

    tearDown(() {
      connection.disconnect();
    });

    test('raw connect alone does not fetch conversations or friends', () async {
      await connection.connect(1, 'test-token', 'http://localhost:3000');

      fakeSocket.simulateTransportConnect();

      expect(fakeSocket.getConversationsCalls, 0);
      expect(fakeSocket.getFriendRequestsCalls, 0);
      expect(fakeSocket.getFriendsCalls, 0);
      expect(fakeSocket.getBlockedListCalls, 0);
      expect(connection.isConnected, isTrue);
    });

    test('socketReady triggers initial authenticated fetches', () async {
      await connection.connect(1, 'test-token', 'http://localhost:3000');

      fakeSocket.simulateTransportConnect();
      fakeSocket.simulateSocketReady();

      expect(fakeSocket.getConversationsCalls, 1);
      expect(fakeSocket.getFriendRequestsCalls, 1);
      expect(fakeSocket.getFriendsCalls, 1);
      expect(fakeSocket.getBlockedListCalls, 1);
    });

    test('socketReady before transport connect still fetches once on ready',
        () async {
      await connection.connect(1, 'test-token', 'http://localhost:3000');

      fakeSocket.simulateSocketReady();

      expect(fakeSocket.getConversationsCalls, 1);
      expect(fakeSocket.getFriendRequestsCalls, 1);
      expect(fakeSocket.getFriendsCalls, 1);
      expect(fakeSocket.getBlockedListCalls, 1);
    });

    test('socketReady reasserts open chat state and refetches active messages',
        () async {
      final conversations = ConversationsProvider()
        ..onConversationsList([_convJson(10)]);
      final messaging = MessagingProvider()
        ..setConversationsProvider(conversations);
      connection.setProviders(
        encryption: EncryptionProvider(),
        friends: FriendsProvider(),
        conversations: conversations,
        messaging: messaging,
      );
      await connection.connect(1, 'test-token', 'http://localhost:3000');

      conversations.openConversation(10);
      connection.emitted.clear();

      fakeSocket.simulateSocketReady();

      expect(fakeSocket.getMessagesConversationIds, [10],
          reason: 'socketReady must refetch the chat that is currently open');
      final pushStates = connection.emitted
          .where((entry) => entry.key == 'pushClientState')
          .map((entry) => Map<String, dynamic>.from(entry.value as Map))
          .toList();
      expect(
        pushStates.any((state) =>
            state['activeConversationId'] == 10 &&
            state['clientVisible'] == true),
        isTrue,
        reason:
            'socketReady must reassert foreground open-chat state after reconnect; states=$pushStates',
      );
    });

    test('socketReady reasserts background active chat as not visible',
        () async {
      final conversations = ConversationsProvider()
        ..onConversationsList([_convJson(10)]);
      final messaging = MessagingProvider()
        ..setConversationsProvider(conversations);
      connection.setProviders(
        encryption: EncryptionProvider(),
        friends: FriendsProvider(),
        conversations: conversations,
        messaging: messaging,
      );
      await connection.connect(1, 'test-token', 'http://localhost:3000');

      conversations.openConversation(10);
      conversations.setClientVisible(false);
      connection.emitted.clear();

      fakeSocket.simulateSocketReady();

      final pushStates = connection.emitted
          .where((entry) => entry.key == 'pushClientState')
          .map((entry) => Map<String, dynamic>.from(entry.value as Map))
          .toList();
      expect(
        pushStates.any((state) =>
            state['activeConversationId'] == 10 &&
            state['clientVisible'] == false),
        isTrue,
        reason:
            'socketReady must preserve background visibility; states=$pushStates',
      );
    });

    test(
        'socketReady with no open conversation neither refetches messages nor '
        'reasserts client state', () async {
      final conversations = ConversationsProvider()
        ..onConversationsList([_convJson(10)]);
      final messaging = MessagingProvider()
        ..setConversationsProvider(conversations);
      connection.setProviders(
        encryption: EncryptionProvider(),
        friends: FriendsProvider(),
        conversations: conversations,
        messaging: messaging,
      );
      await connection.connect(1, 'test-token', 'http://localhost:3000');

      // No conversation is opened: activeConversationId stays null.
      connection.emitted.clear();

      fakeSocket.simulateSocketReady();

      // Baseline authenticated fetches still fire...
      expect(fakeSocket.getConversationsCalls, 1);
      // ...but the active-conversation reassert branch must stay dormant.
      expect(fakeSocket.getMessagesConversationIds, isEmpty,
          reason: 'socketReady must not refetch messages when no chat is open');
      final pushStates = connection.emitted
          .where((entry) => entry.key == 'pushClientState')
          .toList();
      expect(pushStates, isEmpty,
          reason:
              'socketReady must not reassert client state when no chat is open');
    });
  });

  group('ConnectionProvider local-plaintext maintenance', () {
    late FakeSocketService fakeSocket;
    late RecordingConnectionProvider connection;
    late _RecordingEncryption encryption;

    setUp(() {
      ServerClock.instance.resetForTest();
      fakeSocket = FakeSocketService();
      connection = RecordingConnectionProvider(socketService: fakeSocket);
      encryption = _RecordingEncryption();
      connection.setProviders(
        encryption: encryption,
        friends: FriendsProvider(),
        conversations: ConversationsProvider(),
        messaging: MessagingProvider(),
      );
    });

    tearDown(() {
      connection.disconnect();
      ServerClock.instance.resetForTest();
    });

    test('socketReady observes the server clock before sweeping', () async {
      await connection.connect(1, 'test-token', 'http://localhost:3000');
      final serverTime = DateTime.utc(2026, 7, 28, 12, 30);

      expect(ServerClock.instance.estimatedNow, isNull,
          reason: 'no observation yet, so the sweep must refuse to destroy');

      fakeSocket.simulateSocketReady(
        payload: {'serverTime': serverTime.toIso8601String()},
      );
      await pumpEventQueue();

      // Without this the expiry sweep silently never destroys anything, on the
      // one platform this feature exists for, with no error anywhere.
      final estimated = ServerClock.instance.estimatedNow;
      expect(estimated, isNotNull);
      expect(estimated!.isBefore(serverTime), isFalse);

      // Order is load-bearing: retired ids must be loaded before anything can
      // try to decrypt a row whose plaintext was already destroyed, the
      // backlog must drain before the sweep adds more work, and reconciliation
      // goes last so it never asks the server about ids the three local rules
      // were already destroying.
      expect(encryption.calls, [
        'loadRetiredIds',
        'drainPurgeBacklog',
        'sweepDestroyablePlaintext',
        'reconcileStoredPlaintext',
      ]);
    });

    test('maintenance still runs when the server sends no clock', () async {
      await connection.connect(1, 'test-token', 'http://localhost:3000');

      fakeSocket.simulateSocketReady();
      await pumpEventQueue();

      // The sweep is internally a no-op with no clock, but the backlog drain
      // must NOT be skipped — it is what finishes a delete that was cut off by
      // a tab close, and it needs no clock at all.
      expect(encryption.calls, contains('drainPurgeBacklog'));
      expect(ServerClock.instance.estimatedNow, isNull);
    });
  });

  group('ConnectionProvider getServedMessageIds round trip', () {
    late FakeSocketService fakeSocket;
    late RecordingConnectionProvider connection;
    late _RoundTripEncryption encryption;

    setUp(() async {
      ServerClock.instance.resetForTest();
      fakeSocket = FakeSocketService();
      connection = RecordingConnectionProvider(socketService: fakeSocket);
      encryption = _RoundTripEncryption();
      connection.setProviders(
        encryption: encryption,
        friends: FriendsProvider(),
        conversations: ConversationsProvider(),
        messaging: MessagingProvider(),
      );
      await connection.connect(1, 'test-token', 'http://localhost:3000');
      fakeSocket.simulateSocketReady();
      await pumpEventQueue();
    });

    tearDown(() {
      // Also releases any round trip still waiting for an answer.
      connection.disconnect();
      ServerClock.instance.resetForTest();
    });

    String requestId() => fakeSocket.servedIdRequests.single.key;

    test('asks about the batch and returns the ids the server still serves',
        () async {
      expect(fakeSocket.servedIdRequests.single.value, [1, 2, 3]);

      fakeSocket.simulateServedMessageIds({
        'requestId': requestId(),
        'messageIds': [1, 3],
      });
      await pumpEventQueue();

      expect(encryption.answer, {1, 3});
    });

    test('an empty answer is passed through, not swallowed', () async {
      fakeSocket.simulateServedMessageIds({
        'requestId': requestId(),
        'messageIds': <int>[],
      });
      await pumpEventQueue();

      expect(encryption.answered, isTrue);
      expect(encryption.answer, isEmpty);
    });

    test('a malformed answer resolves to null, not to a partial set',
        () async {
      // Parsing what it can would mark the unparsed ids as "the server no
      // longer has this" and destroy their only copy.
      fakeSocket.simulateServedMessageIds({
        'requestId': requestId(),
        'messageIds': [1, 'two', 3],
      });
      await pumpEventQueue();

      expect(encryption.answered, isTrue);
      expect(encryption.answer, isNull);
    });

    test('an answer for a different request is ignored', () async {
      fakeSocket.simulateServedMessageIds({
        'requestId': 'someone-elses-batch',
        'messageIds': <int>[],
      });
      await pumpEventQueue();

      expect(encryption.answered, isFalse,
          reason: 'an empty set destroys everything it is applied to');
    });

    test('disconnect releases the wait as "no answer"', () async {
      connection.disconnect();
      await pumpEventQueue();

      expect(encryption.answered, isTrue);
      expect(encryption.answer, isNull);
    });
  });
}
