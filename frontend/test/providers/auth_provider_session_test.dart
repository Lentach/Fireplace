import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fireplace/providers/auth_provider.dart';
import 'package:fireplace/services/api_service.dart';

/// Expired access JWT (exp 1516239022). Signature is not verified client-side.
const _expiredAccessJwt =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOjEsInVzZXJuYW1lIjoidGVzdCIsInRhZyI6IjAwMDAiLCJleHAiOjE1MTYyMzkwMjJ9.4Adcj3UFYzPUBaY63_UWOshvRZQZjm7uI9uWGQ8RrXc';

const _validAccessJwt =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOjEsInVzZXJuYW1lIjoidGVzdCIsInRhZyI6IjAwMDAiLCJleHAiOjk5OTk5OTk5OTl9.abc';

Future<void> _waitForAuthSettled(
  AuthProvider auth, {
  required bool expectLoggedIn,
}) async {
  for (var i = 0; i < 40; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!auth.isRestoringSession && auth.isLoggedIn == expectLoggedIn) return;
  }
  fail(
    'AuthProvider did not settle (isRestoringSession=${auth.isRestoringSession}, isLoggedIn=${auth.isLoggedIn}, expected=$expectLoggedIn)',
  );
}

void main() {
  group('AuthProvider session refresh', () {
    const base = 'http://localhost:3999';

    test('refresh 401 clears auth and stored tokens', () async {
      SharedPreferences.setMockInitialValues({
        'jwt_token': _expiredAccessJwt,
        'refresh_token': 'opaque_refresh',
      });

      final mock = MockClient((request) async {
        if (request.url.path == '/auth/refresh') {
          return http.Response(
            jsonEncode({'message': 'Invalid refresh token'}),
            401,
            headers: {'Content-Type': 'application/json'},
          );
        }
        throw Exception('Unexpected ${request.url.path}');
      });

      final auth = AuthProvider(
        api: ApiService(baseUrl: base, httpClient: mock),
      );
      await _waitForAuthSettled(auth, expectLoggedIn: false);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('jwt_token'), isNull);
      expect(prefs.getString('refresh_token'), isNull);
      expect(auth.lastSessionEndReason, 'refresh_invalid');
    });

    test('refresh network error keeps auth with JWT user', () async {
      SharedPreferences.setMockInitialValues({
        'jwt_token': _expiredAccessJwt,
        'refresh_token': 'opaque_refresh',
      });

      final mock = MockClient((request) async {
        if (request.url.path == '/auth/refresh') {
          return http.Response(
            jsonEncode({'message': 'Service unavailable'}),
            503,
            headers: {'Content-Type': 'application/json'},
          );
        }
        if (request.url.path == '/users/me') {
          return http.Response(
            jsonEncode({
              'id': 1,
              'username': 'test',
              'tag': '0000',
              'profilePictureUrl': null,
            }),
            200,
            headers: {'Content-Type': 'application/json'},
          );
        }
        throw Exception('Unexpected ${request.url.path}');
      });

      final auth = AuthProvider(
        api: ApiService(baseUrl: base, httpClient: mock),
      );
      await _waitForAuthSettled(auth, expectLoggedIn: true);

      expect(auth.isLoggedIn, isTrue);
      expect(auth.currentUser?.username, 'test');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('refresh_token'), 'opaque_refresh');
      expect(prefs.getString('jwt_token'), _expiredAccessJwt);
    });

    test('parallel ensureSessionReady performs single refresh call', () async {
      SharedPreferences.setMockInitialValues({
        'jwt_token': _validAccessJwt,
        'refresh_token': 'opaque_refresh',
      });

      var refreshCalls = 0;
      final mock = MockClient((request) async {
        if (request.url.path == '/auth/refresh') {
          refreshCalls++;
          await Future<void>.delayed(const Duration(milliseconds: 80));
          return http.Response(
            jsonEncode({
              'access_token': _validAccessJwt,
              'refresh_token': 'rotated_refresh',
            }),
            200,
            headers: {'Content-Type': 'application/json'},
          );
        }
        if (request.url.path == '/users/me') {
          return http.Response(
            jsonEncode({
              'id': 1,
              'username': 'test',
              'tag': '0000',
              'profilePictureUrl': null,
            }),
            200,
            headers: {'Content-Type': 'application/json'},
          );
        }
        throw Exception('Unexpected ${request.url.path}');
      });

      final api = ApiService(baseUrl: base, httpClient: mock);
      final auth = AuthProvider(api: api);
      await _waitForAuthSettled(auth, expectLoggedIn: true);

      auth.setAccessTokenForTest(_expiredAccessJwt);
      refreshCalls = 0;
      await Future.wait([
        auth.ensureSessionReady(),
        auth.ensureSessionReady(),
        auth.ensureSessionReady(),
      ]);

      expect(refreshCalls, 1);
      expect(auth.isLoggedIn, isTrue);
    });

    test(
      'startup load and ensureSessionReady share single refresh call',
      () async {
        SharedPreferences.setMockInitialValues({
          'jwt_token': _expiredAccessJwt,
          'refresh_token': 'opaque_refresh',
        });

        var refreshCalls = 0;
        final mock = MockClient((request) async {
          if (request.url.path == '/auth/refresh') {
            refreshCalls++;
            await Future<void>.delayed(const Duration(milliseconds: 120));
            return http.Response(
              jsonEncode({
                'access_token': _validAccessJwt,
                'refresh_token': 'rotated_refresh',
              }),
              200,
              headers: {'Content-Type': 'application/json'},
            );
          }
          if (request.url.path == '/users/me') {
            return http.Response(
              jsonEncode({
                'id': 1,
                'username': 'test',
                'tag': '0000',
                'profilePictureUrl': null,
              }),
              200,
              headers: {'Content-Type': 'application/json'},
            );
          }
          throw Exception('Unexpected ${request.url.path}');
        });

        final api = ApiService(baseUrl: base, httpClient: mock);
        final auth = AuthProvider(api: api);
        await Future<void>.delayed(Duration.zero);
        await Future.wait([
          auth.ensureSessionReady(),
          auth.ensureSessionReady(),
        ]);
        await _waitForAuthSettled(auth, expectLoggedIn: true);

        expect(refreshCalls, 1);
      },
    );

    test(
      'password reset clears invalidated local session with reason',
      () async {
        SharedPreferences.setMockInitialValues({
          'jwt_token': _validAccessJwt,
          'refresh_token': 'opaque_refresh',
        });

        final mock = MockClient((request) async {
          if (request.url.path == '/users/me') {
            return http.Response(
              jsonEncode({
                'id': 1,
                'username': 'test',
                'tag': '0000',
                'profilePictureUrl': null,
              }),
              200,
              headers: {'Content-Type': 'application/json'},
            );
          }
          if (request.url.path == '/users/reset-password') {
            expect(request.headers['Authorization'], 'Bearer $_validAccessJwt');
            return http.Response('{}', 200);
          }
          throw Exception('Unexpected ${request.url.path}');
        });

        final auth = AuthProvider(
          api: ApiService(baseUrl: base, httpClient: mock),
        );
        await _waitForAuthSettled(auth, expectLoggedIn: true);

        await auth.resetPassword('old-password', 'new-password');

        final prefs = await SharedPreferences.getInstance();
        expect(auth.isLoggedIn, isFalse);
        expect(auth.lastSessionEndReason, 'password_changed');
        expect(prefs.getString('jwt_token'), isNull);
        expect(prefs.getString('refresh_token'), isNull);
      },
    );
  });
}
