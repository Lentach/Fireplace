import 'storage_persist_stub.dart'
    if (dart.library.html) 'storage_persist_web.dart' as impl;

/// Asks the browser to make this origin's storage persistent (exempt from
/// automatic eviction) and reports the resulting state. No-op off web.
///
/// Returns `{supported, granted}`. On an installed PWA with engagement the
/// browser usually grants this, which stops OS-driven eviction of the Signal
/// keystore in `localStorage`. It does NOT protect against the user manually
/// clearing site data.
Future<Map<String, bool>> requestPersistentStorage() =>
    impl.requestPersistentStorage();
