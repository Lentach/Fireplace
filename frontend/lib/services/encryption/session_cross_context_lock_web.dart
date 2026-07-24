import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Web Locks are origin-scoped, so separate PWA tabs/windows/workers requesting
/// the same name cannot mutate one persisted Signal SessionRecord concurrently.
Future<T> runSessionCrossContextLocked<T>(
  String name,
  Future<T> Function() action,
) async {
  final navigatorObject = web.window.navigator as JSObject;
  if (!navigatorObject.hasProperty('locks'.toJS).toDart) {
    throw UnsupportedError(
      'End-to-end encryption requires the browser Web Locks API',
    );
  }

  final result = Completer<T>();
  JSAny? onGranted(JSAny? _) {
    return (() async {
      try {
        result.complete(await action());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
        rethrow;
      }
      return null;
    })().toJS;
  }

  final locks = navigatorObject.getProperty<JSObject?>('locks'.toJS);
  if (locks == null) {
    throw UnsupportedError(
      'End-to-end encryption requires the browser Web Locks API',
    );
  }
  try {
    final request = locks.callMethod<JSPromise<JSAny?>>(
      'request'.toJS,
      name.toJS,
      onGranted.toJS,
    );
    unawaited(
      request.toDart.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          if (!result.isCompleted) result.completeError(error, stackTrace);
        },
      ),
    );
  } catch (error, stackTrace) {
    if (!result.isCompleted) result.completeError(error, stackTrace);
  }
  return result.future;
}
