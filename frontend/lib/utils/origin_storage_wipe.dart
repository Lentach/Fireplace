// Keyed on dart.library.js_interop, not dart.library.html — same wasm trap as
// boot_markers.dart: under `flutter build web --wasm` the latter is false and
// the wipe would silently become a no-op on the very platform that needs it.
import 'origin_storage_wipe_stub.dart'
    if (dart.library.js_interop) 'origin_storage_wipe_web.dart' as impl;

/// Destroys everything this origin's browser storage holds — localStorage,
/// sessionStorage, every IndexedDB database and every Cache Storage entry.
/// No-op off the web.
///
/// Returns the store names that refused, so the caller can tell the user the
/// erase was partial instead of claiming a clean slate.
Future<List<String>> wipeOriginStorage() => impl.wipeOriginStorage();
