import 'package:fireplace/providers/connection_provider.dart';
import 'package:fireplace/providers/conversations_provider.dart';
import 'package:fireplace/providers/encryption_provider.dart';
import 'package:fireplace/providers/friends_provider.dart';
import 'package:fireplace/providers/messaging_provider.dart';
import 'package:fireplace/services/socket_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Test double for [SocketService] — simulates connect / socketReady without I/O.
class FakeSocketService extends SocketService {
  final Map<String, List<void Function(dynamic)>> _handlers = {};
  void Function()? _onConnectCallback;

  int getConversationsCalls = 0;
  int getFriendRequestsCalls = 0;
  int getFriendsCalls = 0;
  int getBlockedListCalls = 0;
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

  void simulateSocketReady() {
    for (final handler in _handlers['socketReady'] ?? const []) {
      handler(null);
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
  });
}
