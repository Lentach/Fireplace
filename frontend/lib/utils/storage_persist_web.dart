import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Web: request persistent storage via the StorageManager API.
/// `persisted()` reports current state; `persist()` requests it.
Future<Map<String, bool>> requestPersistentStorage() async {
  try {
    final storage = web.window.navigator.storage;
    final already = (await storage.persisted().toDart).toDart;
    if (already) return const {'supported': true, 'granted': true};
    final granted = (await storage.persist().toDart).toDart;
    return {'supported': true, 'granted': granted};
  } catch (_) {
    return const {'supported': false, 'granted': false};
  }
}

/// Web: `navigator.storage.estimate()` — how full the origin's bucket is.
/// Null when the API is unavailable or throws; never a decision input, purely
/// diagnostic (the app was previously blind to remaining quota).
Future<Map<String, num>?> storageEstimate() async {
  try {
    final estimate = await web.window.navigator.storage.estimate().toDart;
    return {
      'usage': estimate.usage,
      'quota': estimate.quota,
    };
  } catch (_) {
    return null;
  }
}
