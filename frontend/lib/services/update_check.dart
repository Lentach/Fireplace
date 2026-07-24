import 'update_check_stub.dart'
    if (dart.library.js_interop) 'update_check_web.dart' as impl;

/// True when the served web bundle is newer than the running one (stale PWA).
/// Always false on native and on any failure — a nudge, never a gate.
Future<bool> isServedBundleNewer() => impl.isServedBundleNewer();
