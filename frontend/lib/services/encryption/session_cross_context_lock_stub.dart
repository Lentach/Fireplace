/// Native/non-web fallback. Cross-isolate native use is unsupported by the
/// single-device app; the caller's in-process queue remains the lock.
Future<T> runSessionCrossContextLocked<T>(
  String name,
  Future<T> Function() action,
) => action();
