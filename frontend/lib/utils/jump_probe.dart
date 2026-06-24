import 'jump_probe_stub.dart' if (dart.library.html) 'jump_probe_web.dart'
    as impl;

/// TEMP: install a visual-viewport-pinned DOM readout to diagnose the iOS
/// "screen jumps up on composer focus" bug. iOS-WebKit only; no-op elsewhere.
void installJumpProbe() => impl.installJumpProbe();

/// Remove the jump probe overlay.
void removeJumpProbe() => impl.removeJumpProbe();
