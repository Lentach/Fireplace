import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/e2e_persistent_diag.dart';
import '../utils/origin_storage_wipe.dart';
import 'local_data_files_stub.dart'
    if (dart.library.io) 'local_data_files_io.dart';
import 'secure_kv.dart';

/// One destroyable store. Named so a partial erase can be reported precisely
/// — "we could not clear the keystore" is actionable, "something failed" is
/// not, and this runs behind a typed confirmation that promised a clean slate.
enum LocalDataEraseArm {
  preferences,
  secureStorage,
  messageStoreFiles,
  originStorage,
}

/// What a wipe actually managed to destroy.
@immutable
class LocalDataEraseReport {
  const LocalDataEraseReport({required this.failed});

  final List<LocalDataEraseArm> failed;

  bool get complete => failed.isEmpty;
}

/// Destroys everything this app keeps on this device.
///
/// A seam because the lock screen calls it: the erase panel's widget tests
/// must exercise the confirmation flow without a platform channel in sight.
abstract class LocalDataEraser {
  Future<LocalDataEraseReport> eraseEverything();
}

/// The real one.
///
/// This is the app's answer to "I forgot my passcode". The passcode has no
/// recovery door on purpose (owner ruling 2026-09-04, and the model every
/// key-derived lock in the field ships — Telegram: *"if you forget your
/// passcode, you'll need to reinstall the app"*; Threema: *"there is no way
/// to recover lost PIN codes"*), so the only way past a forgotten code is to
/// destroy what it guards and sign in again.
///
/// It exists as an in-app action rather than "just reinstall" because on the
/// PWA reinstalling does not clear origin storage — see
/// `utils/origin_storage_wipe_web.dart` for the citations. On Android an
/// uninstall would work, but a user staring at a lock screen should not have
/// to leave the app to escape it.
///
/// Every arm is best-effort and isolated, and the ORDER is load-bearing:
/// preferences (which hold `passcode_enabled`) go first, so a keystore that
/// refuses cannot leave behind a flag whose verifier is gone — that is the
/// `credentialDamaged` shape, and it fails CLOSED into a lock screen no code
/// can open.
class DeviceLocalDataEraser implements LocalDataEraser {
  DeviceLocalDataEraser({SecureKv? secure, bool? useSecureStorage})
    : _secure = secure ?? const FlutterSecureStorageKv(FlutterSecureStorage()),
      _useSecure = useSecureStorage ?? (!kIsWeb && Platform.isAndroid);

  final SecureKv _secure;
  final bool _useSecure;

  @override
  Future<LocalDataEraseReport> eraseEverything() async {
    final failed = <LocalDataEraseArm>[];

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (_) {
      failed.add(LocalDataEraseArm.preferences);
    }

    if (_useSecure) {
      try {
        // `readAll` + delete rather than a `deleteAll` call: the [SecureKv]
        // seam is what every other store in this app shares, and widening it
        // for one caller would force a new method into six test fakes.
        final all = await _secure.readAll();
        for (final key in all.keys) {
          await _secure.delete(key);
        }
      } catch (_) {
        failed.add(LocalDataEraseArm.secureStorage);
      }
    }

    try {
      if (!await deleteLocalMessageStoreFiles()) {
        failed.add(LocalDataEraseArm.messageStoreFiles);
      }
    } catch (_) {
      failed.add(LocalDataEraseArm.messageStoreFiles);
    }

    try {
      if ((await wipeOriginStorage()).isNotEmpty) {
        failed.add(LocalDataEraseArm.originStorage);
      }
    } catch (_) {
      failed.add(LocalDataEraseArm.originStorage);
    }

    // The diagnostic ring lives in RAM as well as prefs, so recording the
    // erase without clearing it first re-persists the PRE-erase history —
    // message ids and peer ids the user just asked us to destroy. Found in
    // live QA 2026-09-04. Clear, then leave exactly one entry saying an
    // erase happened, which support still needs.
    await E2ePersistentDiag.clear();
    E2ePersistentDiag.record('LOCAL_DATA_ERASED', {
      'failed': failed.map((a) => a.name).toList(),
    });

    return LocalDataEraseReport(failed: failed);
  }
}
