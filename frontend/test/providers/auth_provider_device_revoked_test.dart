import 'dart:convert';

import 'package:fireplace/providers/auth_provider.dart';
import 'package:fireplace/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The kicked device's own behaviour (multi-device spec §5.5 + §12 amendment
/// (xxvi)).
///
/// Logout semantics, deliberately NOT a wipe: remote wipe of a revoked
/// device's local data is an explicit §1 non-goal, and the whole reason the
/// server tells the device before dropping it is so the user reads "this device
/// was removed" instead of a generic connection error.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const base = 'http://localhost:3000';
  const notice = 'This device was removed from your account.';

  /// A far-future access JWT, so boot restores a session without a refresh.
  String validAccessJwt() {
    String seg(Map<String, dynamic> m) =>
        base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
    final exp = DateTime.now().add(const Duration(hours: 12));
    return '${seg({'alg': 'HS256', 'typ': 'JWT'})}.'
        '${seg({'sub': 1, 'exp': exp.millisecondsSinceEpoch ~/ 1000})}.sig';
  }

  MockClient client() => MockClient((req) async {
    if (req.url.path == '/users/me') {
      return http.Response(
        jsonEncode({'id': 1, 'username': 'test', 'tag': '0001'}),
        200,
        headers: {'Content-Type': 'application/json'},
      );
    }
    if (req.url.path == '/auth/refresh') {
      return http.Response('{}', 500);
    }
    throw Exception('Unexpected ${req.url.path}');
  });

  Future<AuthProvider> loggedIn() async {
    SharedPreferences.setMockInitialValues({
      'jwt_token': validAccessJwt(),
      'refresh_token': 'opaque_refresh',
    });
    final auth = AuthProvider(
      api: ApiService(baseUrl: base, httpClient: client()),
    );
    for (var i = 0; i < 60 && !auth.isLoggedIn; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(auth.isLoggedIn, isTrue, reason: 'boot must restore the session');
    return auth;
  }

  test('ends the session and states the reason', () async {
    final auth = await loggedIn();

    await auth.logoutBecauseDeviceRevoked(notice);

    expect(auth.isLoggedIn, isFalse);
    // The reason survives the clear — the auth screen renders it, and it is the
    // only place the user ever learns WHY the session ended.
    expect(auth.statusMessage, notice);
    expect(auth.isError, isTrue);
  });

  test('is a no-op when no session is held', () async {
    SharedPreferences.setMockInitialValues({});
    final auth = AuthProvider(
      api: ApiService(baseUrl: base, httpClient: client()),
    );

    await auth.logoutBecauseDeviceRevoked(notice);

    // A `deviceRevoked` arriving on a socket that is already logged out must
    // not plant an alarming message on a fresh login screen.
    expect(auth.statusMessage, isNull);
    expect(auth.isError, isFalse);
  });
}
