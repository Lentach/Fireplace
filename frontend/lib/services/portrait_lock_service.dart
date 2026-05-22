import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import 'web_orientation_lock_stub.dart'
    if (dart.library.html) 'web_orientation_lock_web.dart' as web_orientation;

class PortraitLockService {
  PortraitLockService._();
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    if (kIsWeb) {
      await web_orientation.lockPortraitPrimaryIfSupported();
      return;
    }
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
  }

  /// Re-attempt web lock after tab becomes visible (optional hardening).
  static Future<void> reapplyWebLockIfNeeded() async {
    if (!kIsWeb) return;
    await web_orientation.lockPortraitPrimaryIfSupported();
  }
}
