// Keyed on dart.library.js_interop, not dart.library.html — same wasm trap as
// boot_markers.dart and origin_storage_wipe.dart: under
// `flutter build web --wasm` the latter is false and the relaunch would
// silently become a no-op on the one platform that has it.
import 'app_relaunch_stub.dart'
    if (dart.library.js_interop) 'app_relaunch_web.dart' as impl;

/// Whether this platform can restart the app process in place.
///
/// True only on web, where a hard `location.reload()` replaces the document —
/// the same mechanism `page_lifecycle_web.dart` already uses to replace a
/// frozen PWA, and the same event a backgrounded Android-Chrome PWA produces
/// on thaw. There is no equivalent on native, and faking one (restarting the
/// widget tree) would not clear the heap, which is the entire point.
bool canRelaunchApp() => impl.canRelaunchApp();

/// Replaces the running app with a fresh process. Returns to the caller only
/// if the platform refused (a reload requested from a `pagehide` handler can
/// be ignored), so callers MUST have already made the app safe to leave
/// running.
void relaunchApp() => impl.relaunchApp();
