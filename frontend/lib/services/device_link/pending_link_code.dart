import 'package:flutter/foundation.dart';

/// One-shot carrier for a §5.1 link code that arrived by deep link (the QR
/// scanned by a phone camera) before the app had a session or a devices
/// screen to hand it to.
///
/// Set once at boot from the URL fragment, consumed exactly once by the
/// devices screen. `ValueNotifier` so the shell can react to it being armed
/// after login and route to the devices screen; `take()` clears it so a
/// second open never replays a stale code (the stage it names is single-use
/// server-side anyway, but the screen must not offer a ghost ceremony).
class PendingLinkCode {
  PendingLinkCode._();

  static final ValueNotifier<String?> _slot = ValueNotifier<String?>(null);

  static ValueListenable<String?> get listenable => _slot;

  static bool get isArmed => _slot.value != null;

  static void arm(String rawCode) => _slot.value = rawCode;

  /// Return the pending code and clear the slot.
  static String? take() {
    final code = _slot.value;
    _slot.value = null;
    return code;
  }
}
