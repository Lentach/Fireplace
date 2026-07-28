import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fireplace/services/content_key_canary.dart';
import 'package:fireplace/utils/e2e_diag_log.dart';
import 'package:fireplace/utils/e2e_persistent_diag.dart';

class _FakeSecureStore implements ContentKeyCanarySecureStore {
  _FakeSecureStore([this.value]);

  String? value;
  int writes = 0;
  bool throwOnRead = false;

  @override
  Future<String?> read() async {
    if (throwOnRead) throw StateError('secure read failed');
    return value;
  }

  @override
  Future<void> write(String nextValue) async {
    writes++;
    value = nextValue;
  }
}

class _FakeShadowStore implements ContentKeyCanaryShadowStore {
  _FakeShadowStore([this.value]);

  String? value;
  int writes = 0;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String nextValue) async {
    writes++;
    value = nextValue;
  }
}

Map<String, dynamic> _record(String value) =>
    jsonDecode(value) as Map<String, dynamic>;

String _value(String id, int mintedAtMs) =>
    jsonEncode({'id': id, 'mintedAtMs': mintedAtMs});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 7, 29, 12);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await E2ePersistentDiag.clear();
    E2eDiagLog.clear();
    await E2ePersistentDiag.init();
  });

  tearDown(() async {
    await E2ePersistentDiag.clear();
    E2eDiagLog.clear();
  });

  ContentKeyCanary canary(
    _FakeSecureStore secure,
    _FakeShadowStore shadow, {
    Random? random,
  }) => ContentKeyCanary(
    secureStore: secure,
    shadowStore: shadow,
    isWeb: true,
    random: random ?? Random(7),
    now: () => now,
  );

  test(
    'fresh web device mints and writes the same record to both stores',
    () async {
      final secure = _FakeSecureStore();
      final shadow = _FakeShadowStore();

      await canary(secure, shadow).checkAndArm();

      expect(secure.writes, 1);
      expect(shadow.writes, 1);
      expect(secure.value, isNotNull);
      expect(shadow.value, secure.value);
      final record = _record(secure.value!);
      expect(record['id'], matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(record['mintedAtMs'], now.millisecondsSinceEpoch);
      expect(E2eDiagLog.entries.single, contains('CANARY_MINTED'));
    },
  );

  test('healthy revisit logs OK and does not rewrite the canary id', () async {
    final existing = _value('0123456789abcdef0123456789abcdef', 0);
    final secure = _FakeSecureStore(existing);
    final shadow = _FakeShadowStore(existing);

    await canary(secure, shadow).checkAndArm();

    expect(secure.writes, 0);
    expect(shadow.writes, 0);
    expect(secure.value, existing);
    expect(shadow.value, existing);
    expect(E2eDiagLog.entries.single, contains('CANARY_OK'));
  });

  test(
    'missing secure value with shadow records loss and re-mints both',
    () async {
      final previous = _value('0123456789abcdef0123456789abcdef', 0);
      final secure = _FakeSecureStore();
      final shadow = _FakeShadowStore(previous);

      await canary(secure, shadow).checkAndArm();

      expect(secure.writes, 1);
      expect(shadow.writes, 1);
      expect(secure.value, shadow.value);
      expect(_record(secure.value!)['id'], isNot(_record(previous)['id']));
      final lost = E2ePersistentDiag.entries.single;
      expect(lost, contains('CONTENT_KEY_CANARY_LOST'));
      expect(lost, contains('mismatch: false'));
    },
  );

  test('mismatched ids count as a storage loss', () async {
    final secure = _FakeSecureStore(
      _value('0123456789abcdef0123456789abcdef', 0),
    );
    final shadow = _FakeShadowStore(
      _value('fedcba9876543210fedcba9876543210', 0),
    );

    await canary(secure, shadow).checkAndArm();

    expect(secure.value, shadow.value);
    final lost = E2ePersistentDiag.entries.single;
    expect(lost, contains('CONTENT_KEY_CANARY_LOST'));
    expect(lost, contains('mismatch: true'));
  });

  test('throwing secure store records an error and never fails boot', () async {
    final secure = _FakeSecureStore()..throwOnRead = true;
    final shadow = _FakeShadowStore();

    await canary(secure, shadow).checkAndArm();

    expect(secure.writes, 0);
    expect(shadow.writes, 0);
    expect(
      E2ePersistentDiag.entries.single,
      contains('CONTENT_KEY_CANARY_ERROR'),
    );
  });

  test('native path is a no-op', () async {
    final secure = _FakeSecureStore();
    final shadow = _FakeShadowStore();
    final nativeCanary = ContentKeyCanary(
      secureStore: secure,
      shadowStore: shadow,
      isWeb: false,
      now: () => now,
    );

    await nativeCanary.checkAndArm();

    expect(secure.writes, 0);
    expect(shadow.writes, 0);
    expect(E2eDiagLog.entries, isEmpty);
    expect(E2ePersistentDiag.entries, isEmpty);
  });
}
