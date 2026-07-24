import 'session_cross_context_lock_stub.dart'
    if (dart.library.html) 'session_cross_context_lock_web.dart'
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
