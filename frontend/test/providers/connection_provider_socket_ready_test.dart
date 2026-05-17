import 'package:fireplace/providers/connection_provider.dart';
import 'package:fireplace/services/socket_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Test double for [SocketService] — simulates connect / socketReady without I/O.
class FakeSocketService extends SocketService {
  final Map<String, List<void Function(dynamic)>> _handlers = {};
  void Function()? _onConnectCallback;
  void Function(dynamic)? _onDisconnectCallback;

  int getConversationsCalls = 0;
  int getFriendRequestsCalls = 0;
  int getFriendsCalls = 0;
  int getBlockedListCalls = 0;

  @override
  bool get isConnected => true;

  @override
  void connect({required String baseUrl, required String token}) {}

  @override
  void disconnect() {}

  @override
  void on(String event, void Function(dynamic) callback) {
    _handlers.putIfAbsent(event, () => []).add(callback);
  }

  @override
  void onConnect(void Function() callback) {
    _onConnectCallback = callback;
  }

  @override
  void onDisconnect(void Function(dynamic) callback) {
    _onDisconnectCallback = callback;
  }

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConnectionProvider socketReady gating', () {
    late FakeSocketService fakeSocket;
    late ConnectionProvider connection;

    setUp(() {
      fakeSocket = FakeSocketService();
      connection = ConnectionProvider(socketService: fakeSocket);
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
  });
}
