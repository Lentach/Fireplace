import 'dart:convert';

import 'package:fireplace/providers/auth_provider.dart';
import 'package:fireplace/services/api_service.dart';
import 'package:fireplace/services/auth_token_store.dart';
import 'package:fireplace/services/secure_kv.dart';
import 'package:fireplace/utils/e2e_persistent_diag.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// §5.4 provider contract: the auth provider must never convert a storage
/// fault into a logout, and must never let a LOCALLY-derived session end
/// delete the persisted tokens (the manufactured-permanent-logout path —
/// user 54's refresh row was valid to 2027 while he sat on a login screen).

// Built at runtime (not a literal): it is the public jwt.io example token —
// zero secret value — but a literal JWT trips the gitleaks pre-commit gate.
final String _expiredAccessJwt = [
  base64Url.encode(utf8.encode('{"alg":"HS256","typ":"JWT"}')),
  base64Url.encode(
    utf8.encode('{"sub":1,"username":"test","tag":"0000","exp":1516239022}'),
  ),
  'not-a-real-signature',
].join('.');

class _ThrowingKv implements SecureKv {
  final Map<String, String> data = {};
  bool throwOnRead = false;

  @override
  Future<String?> read(String key) async {
    if (throwOnRead) throw Exception('secure storage unavailable');
    return data[key];
  }

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> delete(String key) async => data.remove(key);

  @override
  Future<Map<String, String>> readAll() async => Map.of(data);
}

ApiService _apiWith(http.Response Function(http.Request) handler) =>
    ApiService(
      baseUrl: 'http://localhost:3999',
      httpClient: MockClient((request) async => handler(request)),
    );

Future<void> _waitRestored(AuthProvider auth) async {
  for (var i = 0; i < 200 && auth.isRestoringSession; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  expect(auth.isRestoringSession, isFalse, reason: 'boot never finished');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // The durable diag cache is static — isolate it or dedup assertions
    // observe records from earlier tests in this file.
    await E2ePersistentDiag.clear();
  });

  test('an unreadable token store concedes the boot WITHOUT a fake logout',
      () async {
    final kv = _ThrowingKv()
      ..data['jwt_token'] = 'intact'
      ..data['refresh_token'] = 'intact'
      ..throwOnRead = true;
    final auth = AuthProvider(
      api: _apiWith((_) => http.Response('unexpected', 500)),
      tokenStore: AuthTokenStore(secure: kv, useSecureStorage: true),
      tokenReadRetryDelays: const [Duration(milliseconds: 10)],
    );
    await _waitRestored(auth);

    expect(auth.currentUser, isNull);
    expect(auth.isError, isTrue);
    expect(
      auth.statusCode,
      AuthStatusCode.savedSessionUnreadable,
      reason: 'the user is told the truth, not shown a silent login screen',
    );
    expect(
      auth.statusMessage,
      isNull,
      reason:
          'the provider has no locale, so it must never build the prose — the '
          'widget layer maps the code to an ARB string',
    );
    expect(
      kv.data['refresh_token'],
      'intact',
      reason: 'the store is left untouched for the next boot to recover',
    );
    expect(
      auth.lastSessionEndReason,
      isNull,
      reason: 'no session ended — nothing may claim one did',
    );
    auth.dispose();
  });

  test(
      'expired access without refresh clears the SESSION but never the STORE',
      () async {
    final kv = _ThrowingKv()..data['jwt_token'] = _expiredAccessJwt;
    final auth = AuthProvider(
      // fetchMe answers 401: with no refresh token this lands on the
      // locally-derived `access_401_without_refresh` branch.
      api: _apiWith(
        (req) => req.url.path == '/users/me'
            ? http.Response(jsonEncode({'message': 'unauthorized'}), 401)
            : http.Response('unexpected ${req.url.path}', 500),
      ),
      tokenStore: AuthTokenStore(secure: kv, useSecureStorage: true),
      tokenReadRetryDelays: const [],
    );
    await _waitRestored(auth);

    expect(auth.currentUser, isNull, reason: 'the dead session is cleared');
    expect(
      kv.data['jwt_token'],
      _expiredAccessJwt,
      reason: 'a LOCALLY-derived session end must never delete stored '
          'tokens — only server-authoritative refresh_invalid may',
    );
    expect(
      E2ePersistentDiag.entries.any(
        (e) => e.contains('access_401_without_refresh'),
      ),
      isTrue,
      reason: 'the involuntary session end is still recorded durably',
    );
    auth.dispose();
  });

  test('repeated no-op session ends are deduped in the durable log',
      () async {
    // The §5.4 keep-the-store tradeoff makes this boot repeat forever for a
    // user holding only a dead access token. The durable log is an 80-entry
    // FIFO: without dedup, ~80 boots evict the BOOT_MARKERS forensics that
    // 0.1.10 planted to diagnose the next storage wipe.
    final kv = _ThrowingKv()..data['jwt_token'] = _expiredAccessJwt;
    ApiService api() => _apiWith(
          (req) => req.url.path == '/users/me'
              ? http.Response(jsonEncode({'message': 'unauthorized'}), 401)
              : http.Response('unexpected ${req.url.path}', 500),
        );
    for (var boot = 0; boot < 3; boot++) {
      final auth = AuthProvider(
        api: api(),
        tokenStore: AuthTokenStore(secure: kv, useSecureStorage: true),
        tokenReadRetryDelays: const [],
      );
      await _waitRestored(auth);
      auth.dispose();
    }

    final durable = E2ePersistentDiag.entries
        .where(
          (e) =>
              e.contains('AUTH_SESSION_END') &&
              e.contains('access_401_without_refresh'),
        )
        .length;
    expect(
      durable,
      1,
      reason: 'boot-loop repeats must not churn the FIFO; eviction re-arms '
          'the event so recurrence is never permanently lost',
    );
  });
}
