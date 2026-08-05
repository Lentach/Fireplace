// Keyed on dart.library.js_interop, NOT dart.library.html: the latter is FALSE
// under `flutter build web --wasm`, which would silently select the stub and
// delete the cross-context lock with no diagnostic. The web implementation is
// package:web + dart:js_interop and compiles unchanged on both web backends.
import 'session_cross_context_lock_stub.dart'
    if (dart.library.js_interop) 'session_cross_context_lock_web.dart'
    as impl;

typedef SessionCrossContextLockRunner =
    Future<T> Function<T>(String name, Future<T> Function() action);

/// Serializes one Signal session mutation across every app context sharing the
/// same origin. Native builds only need the in-process queue in
/// [EncryptionService]; web builds additionally use the browser Web Locks API.
Future<T> runSessionCrossContextLocked<T>(
  String name,
  Future<T> Function() action,
) => impl.runSessionCrossContextLocked(name, action);
