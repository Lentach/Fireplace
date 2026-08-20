import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Fires [onRevived] when a frozen/bfcached page comes back to life. Android
/// Chrome freezes backgrounded PWA tabs; a page revived by a notification-tap
/// focus() or a bfcache restore has a dead socket, and per the Page Lifecycle
/// spec `resume` is dispatched BEFORE `visibilitychange` — so at this moment
/// `document.visibilityState` may still read 'hidden' even though the user is
/// foregrounding the app. Do NOT gate on visibility here: the caller runs the
/// socket-recovery half unconditionally and leaves the visible-flag flip to
/// the visibilitychange listener (field bug, Aug 2026).
///
/// - `pageshow` on window, only with `persisted == true` (bfcache restore —
///   a normal load must not double-fire the recovery path);
/// - `resume` on document (Page Lifecycle API, Chrome unfreezing the page).
StreamSubscription<web.Event>? registerPageResumeListener(
  void Function() onRevived,
) {
  void pageShowHandler(web.Event event) {
    if (!(event as web.PageTransitionEvent).persisted) return;
    onRevived();
  }

  void resumeHandler(web.Event _) {
    onRevived();
  }

  final jsPageShowHandler = pageShowHandler.toJS;
  final jsResumeHandler = resumeHandler.toJS;
  web.window.addEventListener('pageshow', jsPageShowHandler);
  web.document.addEventListener('resume', jsResumeHandler);
  return _PageResumeSubscription(() {
    web.window.removeEventListener('pageshow', jsPageShowHandler);
    web.document.removeEventListener('resume', jsResumeHandler);
  });
}

class _PageResumeSubscription implements StreamSubscription<web.Event> {
  _PageResumeSubscription(this._onCancel);

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
