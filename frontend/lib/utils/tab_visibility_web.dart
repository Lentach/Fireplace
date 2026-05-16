import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Fires when the browser tab becomes hidden or visible (non-PWA tabs included).
StreamSubscription<web.Event>? registerTabVisibilityListener(
  void Function(bool isVisible) onChanged,
) {
  void handler(web.Event _) {
    onChanged(web.document.visibilityState == 'visible');
  }

  final jsHandler = handler.toJS;
  web.document.addEventListener('visibilitychange', jsHandler);
  onChanged(web.document.visibilityState == 'visible');
  return _VisibilityChangeSubscription(
    () => web.document.removeEventListener('visibilitychange', jsHandler),
  );
}

class _VisibilityChangeSubscription implements StreamSubscription<web.Event> {
  _VisibilityChangeSubscription(this._onCancel);

  final void Function() _onCancel;
  bool _cancelled = false;

  @override
  Future<void> cancel() async {
    if (_cancelled) return;
    _cancelled = true;
    _onCancel();
  }

  @override
  bool get isPaused => false;

  @override
  void pause([Future<void>? resumeSignal]) {}

  @override
  void resume() {}

  @override
  void onData(void Function(web.Event data)? handleData) {}

  @override
  void onDone(void Function()? handleDone) {}

  @override
  void onError(Function? handleError) {}

  @override
  Future<E> asFuture<E>([E? futureValue]) => Completer<E>().future;
}
