import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fireplace/providers/auth_provider.dart';
import 'package:fireplace/services/api_service.dart';

// exp 9999999999; the client never verifies the signature.
const _accessJwt =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOjEsInVzZXJuYW1lIjoibWEwaSIsInRhZyI6IjUyNjkiLCJleHAiOjk5OTk5OTk5OTl9.abc';

http.Response _json(Object body, int status) => http.Response(
  jsonEncode(body),
  status,
  headers: {'Content-Type': 'application/json'},
);

AuthProvider _provider(http.Client client) =>
    AuthProvider(api: ApiService(baseUrl: 'http://localhost:3999', httpClient: client));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // What a senior dev hit in production: register → 409 → "Coś poszło nie tak"
  // → he picked a different name. The account was HIS. Every assertion here is
  // about what the surface can now say and offer.
  group('registration outcome is explained, not swallowed', () {
    test('a taken name that opens with these credentials signs the user in',
        () async {
      // The friend's ACTUAL situation: his first register committed the row,
      // its answer was lost, and his retry hit 409. The password he just typed
      // is the account's password, so the retry can simply land him inside.
      final auth = _provider(
        MockClient((req) async => switch (req.url.path) {
              '/auth/register' =>
                _json({'message': 'nickname is already taken'}, 409),
              '/auth/login' =>
                _json({'access_token': _accessJwt, 'refresh_token': 'r'}, 200),
              '/users/me' =>
                _json({'id': 114, 'username': 'ma0i', 'tag': '5269'}, 200),
              _ => throw StateError('unexpected ${req.url.path}'),
            }),
      );

      expect(await auth.register('ma0i', 'Password1'), isTrue);
      expect(auth.isLoggedIn, isTrue);
      expect(auth.statusCode, isNull);
      expect(auth.recoverableUsername, isNull);
    });

    test("someone else's name is named, and offers the sign-in door",
        () async {
      final auth = _provider(
        MockClient((req) async => switch (req.url.path) {
              '/auth/register' =>
                _json({'message': 'nickname is already taken'}, 409),
              // Not this user's account: the credentials do not open it.
              '/auth/login' => _json({'message': 'Invalid credentials'}, 401),
              _ => throw StateError('unexpected ${req.url.path}'),
            }),
      );

      expect(await auth.register('maoi', 'Password1'), isFalse);
      expect(auth.isLoggedIn, isFalse);
      expect(auth.statusCode, AuthStatusCode.nicknameTaken);
      expect(auth.recoverableUsername, 'maoi');
    });

    test('a successful registration signs the user in, no second step',
        () async {
      final calls = <String>[];
      final auth = _provider(
        MockClient((req) async {
          calls.add('${req.method} ${req.url.path}');
          return switch (req.url.path) {
            '/auth/register' => _json({'id': 114, 'username': 'ma0i', 'tag': '5269'}, 201),
            '/auth/login' =>
              _json({'access_token': _accessJwt, 'refresh_token': 'r'}, 200),
            '/users/me' =>
              _json({'id': 114, 'username': 'ma0i', 'tag': '5269'}, 200),
            _ => throw StateError('unexpected ${req.url.path}'),
          };
        }),
      );

      expect(await auth.register('ma0i', 'Password1'), isTrue);
      expect(auth.isLoggedIn, isTrue);
      expect(auth.currentUser?.username, 'ma0i');
      // Nothing left on screen to interpret: no status, no recovery offer.
      expect(auth.statusCode, isNull);
      expect(auth.recoverableUsername, isNull);
      expect(calls, contains('POST /auth/login'));
    });

    test(
        'a created account whose auto sign-in fails still reports success and '
        'hands the username to the login tab', () async {
      final auth = _provider(
        MockClient((req) async => switch (req.url.path) {
              '/auth/register' => _json({'id': 7, 'username': 'nowy'}, 201),
              // e.g. the login throttle after several attempts.
              '/auth/login' => _json({'message': 'ThrottlerException'}, 429),
              _ => throw StateError('unexpected ${req.url.path}'),
            }),
      );

      expect(await auth.register('nowy', 'Password1'), isTrue);
      expect(auth.isLoggedIn, isFalse);
      expect(auth.statusCode, AuthStatusCode.registerSucceeded);
      expect(auth.isError, isFalse);
      expect(auth.recoverableUsername, 'nowy');
    });

    test(
        'a lost register answer says the account may exist instead of blaming '
        'the user', () async {
      // The 2026-09-05 shape: request delivered, answer never arrived (WiFi →
      // cellular handoff). `Future.timeout` cannot abort it, so the row can be
      // committed while the client sees only a failure.
      final auth = _provider(
        MockClient((req) async => throw TimeoutException('no answer')),
      );

      expect(await auth.register('ma0i', 'Password1'), isFalse);
      expect(auth.statusCode, AuthStatusCode.registerOutcomeUnknown);
      expect(auth.recoverableUsername, 'ma0i');
    });
  });

  group('sign-in refusals are distinguishable', () {
    test('wrong password is not "something went wrong"', () async {
      final auth = _provider(
        MockClient((req) async => _json({'message': 'Invalid credentials'}, 401)),
      );

      expect(await auth.login('ma0i', 'nope'), isFalse);
      expect(auth.statusCode, AuthStatusCode.invalidCredentials);
    });

    test('the rate limit says so', () async {
      final auth = _provider(
        MockClient((req) async => _json({'message': 'ThrottlerException'}, 429)),
      );

      expect(await auth.login('ma0i', 'Password1'), isFalse);
      expect(auth.statusCode, AuthStatusCode.tooManyAttempts);
    });

    test('a backend 502 mid-deploy is a server problem, not a user error',
        () async {
      final auth = _provider(
        MockClient((req) async => http.Response('<html>502</html>', 502)),
      );

      expect(await auth.login('ma0i', 'Password1'), isFalse);
      expect(auth.statusCode, AuthStatusCode.serverError);
    });

    test(
        'a WebKit-worded transport failure is reported as a connection problem',
        () async {
      // The wording is the browser engine's, not a library constant
      // (`package:http` re-throws the TypeError text), so classification must
      // be by TYPE — "Load failed" matched none of the old substrings.
      final auth = _provider(
        MockClient((req) async => throw http.ClientException('Load failed')),
      );

      expect(await auth.login('ma0i', 'Password1'), isFalse);
      expect(auth.statusCode, AuthStatusCode.serverUnreachable);
    });
  });

  group('a status describes the attempt in front of the user', () {
    test('a new attempt clears the previous verdict before it runs', () async {
      // First attempt: a name owned by SOMEONE ELSE (the recovery sign-in is
      // refused), so the taken-name verdict stands and must not outlive it.
      var registerCalls = 0;
      final auth = _provider(
        MockClient((req) async {
          if (req.url.path == '/auth/register') {
            registerCalls++;
            return registerCalls == 1
                ? _json({'message': 'nickname is already taken'}, 409)
                : _json({'id': 8, 'username': 'inny'}, 201);
          }
          return switch (req.url.path) {
            // The recovery sign-in after the first 409 is refused; the one
            // after the second (successful) register is not.
            '/auth/login' => registerCalls >= 2
                ? _json({'access_token': _accessJwt, 'refresh_token': 'r'}, 200)
                : _json({'message': 'Invalid credentials'}, 401),
            '/users/me' => _json({'id': 8, 'username': 'inny'}, 200),
            _ => throw StateError('unexpected ${req.url.path}'),
          };
        }),
      );

      await auth.register('maoi', 'Password1');
      expect(auth.statusCode, AuthStatusCode.nicknameTaken);

      await auth.register('inny', 'Password1');
      expect(auth.statusCode, isNull);
      expect(auth.recoverableUsername, isNull);
    });
  });
}
