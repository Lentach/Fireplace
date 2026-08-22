import 'package:fireplace/providers/connection_provider.dart';
import 'package:fireplace/providers/conversations_provider.dart';
import 'package:fireplace/providers/encryption_provider.dart';
import 'package:fireplace/providers/friends_provider.dart';
import 'package:fireplace/providers/messaging_provider.dart';
import 'package:fireplace/services/socket_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// The §6.2 recovery ack re-homes this account onto a NEWLY allocated device
/// and hands back the session bound to it. The server states the contract at
/// its own emit site: *the client MUST adopt these before uploading one-time
/// pre-keys, or those keys land in the namespace the teardown just abandoned.*
///
/// That upload is triggered BY the ack — `onKeyBundleUploaded` replenishes on
/// `identityChanged` — so the whole contract is an ORDERING one, and ordering
/// is what these tests pin. A test that only checked "the token was persisted"
/// would pass with the adoption running after the ack and the pre-keys still
/// landing on the revoked device.
class _FakeSocket extends SocketService {
  final Map<String, List<void Function(dynamic)>> handlers = {};
  int connects = 0;
  int disconnects = 0;

  @override
  bool get isConnected => true;

  @override
  void connect({required String baseUrl, required String token}) {
    connects++;
  }

  @override
  void disconnect() => disconnects++;

  @override
  void on(String event, void Function(dynamic) callback) {
    handlers.putIfAbsent(event, () => []).add(callback);
  }

  @override
  void onConnect(void Function() callback) {}

  @override
  void onDisconnect(void Function(dynamic) callback) {}

  void emitServer(String event, dynamic payload) {
    for (final h in List.of(handlers[event] ?? const [])) {
      h(payload);
    }
  }
}

/// Records WHEN the ack reached the encryption layer, relative to the rebind.
class _RecordingEncryption extends EncryptionProvider {
  final List<String> order;
  _RecordingEncryption(this.order);

  @override
  void onKeyBundleUploaded(dynamic data) => order.add('ack');
}

void main() {
  late _FakeSocket socket;
  late List<String> order;
  late ConnectionProvider conn;

  Future<void> connectOnce() =>
      conn.connect(7, 'old-token', 'http://127.0.0.1:3000');

  setUp(() async {
    socket = _FakeSocket();
    order = <String>[];
    conn = ConnectionProvider(socketService: socket);
    conn.setProviders(
      encryption: _RecordingEncryption(order),
      friends: FriendsProvider(),
      conversations: ConversationsProvider(),
      messaging: MessagingProvider(),
    );
    await connectOnce();
  });

  tearDown(() => conn.dispose());

  Map<String, dynamic> recoveryAck() => {
    'success': true,
    'identityChanged': true,
    'deviceId': 3,
    'access_token': 'new-access',
    'refresh_token': 'new-refresh',
  };

  test('adopts the session and reconnects BEFORE delivering the ack', () async {
    final adopted = <Map<String, dynamic>>[];
    conn.onSessionRebound = (tokens) async {
      order.add('adopt');
      adopted.add(tokens);
    };
    final connectsBefore = socket.connects;

    socket.emitServer('keyBundleUploaded', recoveryAck());
    await Future<void>.delayed(Duration.zero);

    expect(
      order,
      ['adopt', 'ack'],
      reason:
          'the ack is what triggers the pre-key upload, so adopting after it '
          'publishes those keys under the device the teardown revoked',
    );
    expect(adopted.single, {
      'access_token': 'new-access',
      'refresh_token': 'new-refresh',
    });
    expect(
      socket.connects,
      greaterThan(connectsBefore),
      reason: 'persisting the token is not enough — the SOCKET must rebind',
    );
  });

  test('an ordinary ack is passed straight through, untouched', () async {
    var adoptCalls = 0;
    conn.onSessionRebound = (_) async => adoptCalls++;
    final connectsBefore = socket.connects;

    socket.emitServer('keyBundleUploaded', {
      'success': true,
      'identityChanged': false,
    });
    await Future<void>.delayed(Duration.zero);

    expect(order, ['ack']);
    expect(adoptCalls, 0, reason: 'no reset happened; nothing to adopt');
    expect(socket.connects, connectsBefore);
  });

  test('a refusal never rebinds, even carrying a token-shaped body', () async {
    var adoptCalls = 0;
    conn.onSessionRebound = (_) async => adoptCalls++;

    socket.emitServer('keyBundleUploaded', {
      'success': false,
      'error': 'identity_locked',
      'access_token': 'attacker-supplied',
      'refresh_token': 'attacker-supplied',
    });
    await Future<void>.delayed(Duration.zero);

    expect(adoptCalls, 0);
    expect(order, ['ack']);
  });

  test('a HALF payload is ignored rather than half-adopted', () async {
    var adoptCalls = 0;
    conn.onSessionRebound = (_) async => adoptCalls++;

    // An access token with no refresh token would leave a session that cannot
    // be renewed — worse than not adopting at all.
    socket.emitServer('keyBundleUploaded', {
      'success': true,
      'identityChanged': true,
      'access_token': 'only-access',
    });
    await Future<void>.delayed(Duration.zero);

    expect(adoptCalls, 0);
    expect(order, ['ack']);
  });

  test('the ack still reaches the client when the rebind THROWS', () async {
    conn.onSessionRebound = (_) async {
      order.add('adopt');
      throw StateError('storage unavailable');
    };

    socket.emitServer('keyBundleUploaded', recoveryAck());
    await Future<void>.delayed(Duration.zero);

    expect(
      order,
      ['adopt', 'ack'],
      reason:
          'dropping the ack strands the stashed pre-keys forever, which is '
          'worse than publishing them somewhere a later rebind can replace',
    );
  });

  test('a SECOND recovery in the same session still rebinds', () async {
    var adoptCalls = 0;
    conn.onSessionRebound = (_) async => adoptCalls++;

    socket.emitServer('keyBundleUploaded', recoveryAck());
    await Future<void>.delayed(Duration.zero);
    socket.emitServer('keyBundleUploaded', recoveryAck());
    await Future<void>.delayed(Duration.zero);

    expect(
      adoptCalls,
      2,
      reason:
          'the in-flight latch guards concurrency, not the lifetime of the '
          'provider — a later ceremony is a legitimate second rebind',
    );
  });
}
