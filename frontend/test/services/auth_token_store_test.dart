import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fireplace/services/auth_token_store.dart';
import 'package:fireplace/services/secure_kv.dart';

class _FakeSecureKv implements SecureKv {
  final Map<String, String> data = {};

  /// Writes "succeed" but persist nothing — the read-back-verified migration
  /// must then refuse to delete the prefs copy.
  bool dropWrites = false;
  bool throwOnRead = false;

  @override
  Future<String?> read(String key) async {
    if (throwOnRead) throw Exception('secure storage unavailable');
    return data[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (dropWrites) return;
    data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    data.remove(key);
  }

  @override
  Future<Map<String, String>> readAll() async => Map.of(data);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeSecureKv secure;

  AuthTokenStore nativeStore() =>
      AuthTokenStore(secure: secure, useSecureStorage: true);

  AuthTokenStore prefsStore() =>
      AuthTokenStore(secure: secure, useSecureStorage: false);

  setUp(() {
    secure = _FakeSecureKv();
    SharedPreferences.setMockInitialValues({});
  });

  group('prefs path (web / non-Android)', () {
    test('write/read/clear round-trip through SharedPreferences', () async {
      final store = prefsStore();
      await store.write(access: 'a1', refresh: 'r1');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('jwt_token'), 'a1');
      expect(prefs.getString('refresh_token'), 'r1');
      final read = await store.read();
      expect(read.access, 'a1');
      expect(read.refresh, 'r1');
      await store.clear();
      expect(prefs.getString('jwt_token'), isNull);
      expect(prefs.getString('refresh_token'), isNull);
      expect(secure.data, isEmpty, reason: 'never touches secure storage');
    });
  });

  group('native path', () {
    test('write/read/clear round-trip through secure storage', () async {
      final store = nativeStore();
      await store.write(access: 'a1', refresh: 'r1');
      expect(secure.data['jwt_token'], 'a1');
      expect(secure.data['refresh_token'], 'r1');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('jwt_token'), isNull,
          reason: 'tokens must never land in the plaintext XML');
      final read = await store.read();
      expect(read.access, 'a1');
      expect(read.refresh, 'r1');
      await store.clear();
      expect(secure.data, isEmpty);
    });

    test('migrates a pre-Phase-2 install: copy, verify, then delete prefs',
        () async {
      SharedPreferences.setMockInitialValues({
        'jwt_token': 'legacy-access',
        'refresh_token': 'legacy-refresh',
      });
      final read = await nativeStore().read();
      // Serves the tokens THIS launch (no forced re-login)...
      expect(read.access, 'legacy-access');
      expect(read.refresh, 'legacy-refresh');
      // ...has moved them to secure storage...
      expect(secure.data['jwt_token'], 'legacy-access');
      expect(secure.data['refresh_token'], 'legacy-refresh');
      // ...and only then removed the prefs copies.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('jwt_token'), isNull);
      expect(prefs.getString('refresh_token'), isNull);
    });

    test('a dropped secure write leaves the prefs copy as the working set',
        () async {
      SharedPreferences.setMockInitialValues({
        'jwt_token': 'legacy-access',
        'refresh_token': 'legacy-refresh',
      });
      secure.dropWrites = true;
      final read = await nativeStore().read();
      // Still logged in off the prefs copy this launch...
      expect(read.access, 'legacy-access');
      // ...and the prefs copy MUST survive: it is the only durable home the
      // tokens have until a secure write can be proven.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('jwt_token'), 'legacy-access');
      expect(prefs.getString('refresh_token'), 'legacy-refresh');
    });

    test('a throwing secure store reads as logged out, never crashes',
        () async {
      secure.throwOnRead = true;
      final read = await nativeStore().read();
      expect(read.access, isNull);
      expect(read.refresh, isNull);
    });

    test('clear removes secure AND legacy prefs residue', () async {
      SharedPreferences.setMockInitialValues({
        'jwt_token': 'stale-legacy',
      });
      secure.data['jwt_token'] = 'a1';
      await nativeStore().clear();
      expect(secure.data, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('jwt_token'), isNull);
    });

    test('post-migration reads clean stray prefs residue', () async {
      // Tokens already secure; a prefs twin survived (e.g. an old backup of
      // the XML got restored). Reads must not resurrect it — secure wins and
      // the residue goes.
      secure.data['jwt_token'] = 'secure-access';
      secure.data['refresh_token'] = 'secure-refresh';
      SharedPreferences.setMockInitialValues({
        'jwt_token': 'stale-prefs-copy',
      });
      final read = await nativeStore().read();
      expect(read.access, 'secure-access');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('jwt_token'), isNull);
    });
  });
}
