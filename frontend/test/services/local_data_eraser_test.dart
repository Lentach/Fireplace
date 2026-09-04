import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fireplace/services/local_data_eraser.dart';
import 'package:fireplace/utils/e2e_persistent_diag.dart';
import 'package:fireplace/services/secure_kv.dart';

class _FakeSecureKv implements SecureKv {
  final Map<String, String> values = {};
  bool throwOnReadAll = false;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<Map<String, String>> readAll() async {
    if (throwOnReadAll) throw Exception('keystore refused enumeration');
    return Map.of(values);
  }
}

void main() {
  // The PWA equivalent of "uninstall the app": the owner's mental model was
  // that reinstalling clears everything, but deleting an installed PWA's icon
  // is documented as NOT necessarily clearing origin storage
  // (https://web.dev/learn/pwa/installation), so the app has to do it itself.
  group('DeviceLocalDataEraser', () {
    test('clears every stored preference', () async {
      SharedPreferences.setMockInitialValues({
        'passcode_enabled': true,
        'passcode_mode': 'digits4',
        'theme_preference': '"dark"',
        'jwt_token': 'stale',
      });
      final eraser = DeviceLocalDataEraser(
        secure: _FakeSecureKv(),
        useSecureStorage: false,
      );

      final report = await eraser.eraseEverything();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
      expect(report.complete, isTrue);
      expect(report.failed, isEmpty);
    });

    test('deletes every secure-storage entry where secure storage is used',
        () async {
      SharedPreferences.setMockInitialValues({});
      final secure = _FakeSecureKv();
      secure.values.addAll({
        'fp_passcode_salt_v1': 'salt',
        'fp_passcode_verifier_v1': 'verifier',
        'fp_content_db_key_v1': 'dbkey',
        'jwt_token': 'token',
      });
      final eraser = DeviceLocalDataEraser(
        secure: secure,
        useSecureStorage: true,
      );

      final report = await eraser.eraseEverything();

      expect(secure.values, isEmpty);
      expect(report.complete, isTrue);
    });

    // The order is load-bearing, not cosmetic. `passcode_enabled` living on
    // after the verifier is gone is exactly the `credentialDamaged` shape,
    // which fails CLOSED — a lock screen no code can open. So the flag half
    // must be cleared first, and a keystore that refuses must be reported
    // rather than thrown, because this runs from the lock screen itself.
    test('a refusing keystore is reported, and the passcode flag is still gone',
        () async {
      SharedPreferences.setMockInitialValues({'passcode_enabled': true});
      final secure = _FakeSecureKv()..throwOnReadAll = true;
      secure.values['fp_passcode_verifier_v1'] = 'verifier';
      final eraser = DeviceLocalDataEraser(
        secure: secure,
        useSecureStorage: true,
      );

      final report = await eraser.eraseEverything();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
      expect(report.complete, isFalse);
      expect(report.failed, contains(LocalDataEraseArm.secureStorage));
    });

    // Found in live QA 2026-09-04: after a full wipe the origin still held
    // `e2e_diag_persist_v1`, and it carried the PRE-erase forensic history
    // (message ids, peer ids) — the in-memory ring re-persisted itself when
    // the eraser recorded its own event. An action that promises a clean
    // slate must not leave a log of what used to be there.
    test('does not resurrect the pre-erase diagnostic log', () async {
      SharedPreferences.setMockInitialValues({
        E2ePersistentDiag.storageKey: <String>[
          '09-01 04:17:14 DECRYPT_DECISION | {msgId: 3, senderId: 3}',
        ],
        'passcode_enabled': true,
      });
      await E2ePersistentDiag.init();
      final eraser = DeviceLocalDataEraser(
        secure: _FakeSecureKv(),
        useSecureStorage: false,
      );

      await eraser.eraseEverything();

      final prefs = await SharedPreferences.getInstance();
      final log =
          prefs.getStringList(E2ePersistentDiag.storageKey) ?? const <String>[];
      expect(
        log.where((e) => e.contains('DECRYPT_DECISION')),
        isEmpty,
        reason: 'pre-erase forensics must not survive the wipe',
      );
      expect(log.where((e) => e.contains('LOCAL_DATA_ERASED')), hasLength(1));
    });
  });
}
