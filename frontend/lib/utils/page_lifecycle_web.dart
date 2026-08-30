import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'frozen_page_reload_decision.dart';

/// Web page-lifecycle hooks for the PWA (field bugs, Aug 2026, users 48/90).
///
/// Two distinct revival paths, two distinct treatments:
///
/// 1. **bfcache restore** (`pageshow` with `persisted == true`): the browser
///    restored a fully coherent snapshot — the page is trustworthy, it just
///    has a dead socket. Soft recovery is enough → [registerPageShowRecoveryListener].
/// 2. **Tab freeze → resume** (Page Lifecycle `freeze`/`resume`): Android
///    Chrome freezes a backgrounded PWA after ~5 min; a notification-tap
///    `focus()` thaws it, and the revived Flutter/CanvasKit engine is
///    UNTRUSTWORTHY — stale viewport/keyboard-inset state (composer painted
///    mid-screen), degraded rendering ("lag"), no live messages. Users' own
///    workaround (swipe-close + icon relaunch = cold boot) always works, so a
///    frozen page is REPLACED, not repaired → [installFreezeReloadGuard].
///    The pending notification deep-link survives the reload: the push SW
///    writes it to IndexedDB BEFORE calling focus(), main.dart drains it on
///    boot, AND the live click handler (push_service.dart) consults
///    [frozenPageReloadImminent] before deleting the record — the SW's queued
///    click message flushes on the SAME thaw as `resume`, in unspecified
///    order, so without that gate the record could be deleted right before
///    the reload that needs it.

/// sessionStorage key holding the epoch-millis of the last forced reload.
/// Doubles as the loop guard and the cross-reload evidence (E2eDiagLog is
/// RAM-only and dies with the reload). sessionStorage scopes to the tab, so a
/// fresh launch never inherits a stale marker.
const String _kFrozenReloadMarkerKey = 'fp_frozen_reload_at_v1';

/// How fresh the marker must be for [consumeFrozenReloadMarker] to report a
/// frozen-reload boot. Older markers are stale leftovers, not evidence.
const int _kFrozenReloadMarkerFreshMs = 60000;

/// Fires [onRevived] on a bfcache restore (`pageshow` + `persisted`). A normal
/// load must not double-fire the foreground path, hence the `persisted` gate.
/// Do NOT gate on visibility: a bfcache-restored page is being shown.
StreamSubscription<web.Event>? registerPageShowRecoveryListener(
  void Function() onRevived,
) {
  void pageShowHandler(web.Event event) {
    if (!(event as web.PageTransitionEvent).persisted) return;
    onRevived();
  }

  final jsHandler = pageShowHandler.toJS;
  web.window.addEventListener('pageshow', jsHandler);
  return _CancelOnlySubscription(() {
    web.window.removeEventListener('pageshow', jsHandler);
  });
}

/// Installs the freeze-reload guard:
/// - `freeze` flips [FrozenPageReloadState] (the JS heap survives a tab
///   freeze, so the state survives to `resume` — this is what distinguishes a
///   true thaw from any other event storm);
/// - `resume` applies [decideOnFrozenResume]: reload now when visible, ARM the
///   reload when still hidden (`resume` is dispatched BEFORE `visibilitychange`,
///   and Chrome can unfreeze a page that stays in the background — a hidden
///   page must never be reloaded, only a shown one);
/// - `visibilitychange` → visible fires an armed reload;
/// - the loop guard falls back to [onFallbackRecover] (soft reconnect/resync)
///   instead of reloading again within [kFrozenReloadMinIntervalMs].
///
/// Accepted tradeoffs (owner-approved 2026-08-20): a composer draft typed
/// before the freeze is lost (the user has been away ≥ ~5 min), and without a
/// pending deep-link the reload lands on the conversations list — identical to
/// the icon relaunch users already prefer over the broken revived window.
StreamSubscription<web.Event>? installFreezeReloadGuard({
  required void Function() onFallbackRecover,
  bool Function()? suppressReload,
}) {
  var reloadArmed = false;

  void forceReload() {
    try {
      web.window.sessionStorage.setItem(
        _kFrozenReloadMarkerKey,
        DateTime.now().millisecondsSinceEpoch.toString(),
      );
    } catch (_) {
      // Marker is diagnostics + loop guard; a blocked sessionStorage must not
      // block the replacement of a degraded page.
    }
    web.window.location.reload();
  }

  void freezeHandler(web.Event _) {
    _reloadState.onFreeze();
  }

  void resumeHandler(web.Event _) {
    final action = _reloadState.onResume(
      isVisible: web.document.visibilityState == 'visible',
      lastForcedReloadAtMs: _readMarkerMs(),
      nowMs: DateTime.now().millisecondsSinceEpoch,
      nativeSurfaceActive: suppressReload?.call() ?? false,
    );
    switch (action) {
      case FrozenResumeAction.reloadNow:
        forceReload();
      case FrozenResumeAction.armReload:
        reloadArmed = true;
      case FrozenResumeAction.softRecover:
        onFallbackRecover();
    }
  }

  void visibilityHandler(web.Event _) {
    if (!reloadArmed) return;
    if (web.document.visibilityState != 'visible') return;
    reloadArmed = false;
    // Re-check at fire time: the picker surface may have opened between the
    // hidden resume that armed this and the visibility flip.
    if (suppressReload?.call() ?? false) {
      onFallbackRecover();
      return;
    }
    forceReload();
  }

  final jsFreeze = freezeHandler.toJS;
  final jsResume = resumeHandler.toJS;
  final jsVisibility = visibilityHandler.toJS;
  web.document.addEventListener('freeze', jsFreeze);
  web.document.addEventListener('resume', jsResume);
  web.document.addEventListener('visibilitychange', jsVisibility);
  return _CancelOnlySubscription(() {
    web.document.removeEventListener('freeze', jsFreeze);
    web.document.removeEventListener('resume', jsResume);
    web.document.removeEventListener('visibilitychange', jsVisibility);
  });
}

/// Page-scoped reload state, shared with the live notification-click handler
/// via [frozenPageReloadImminent].
final FrozenPageReloadState _reloadState = FrozenPageReloadState();

/// True while a frozen-page reload may still follow — the live click handler
/// must NOT delete the IndexedDB deep-link record while this holds, or the
/// reload cold-boots onto the conversations list instead of the tapped chat.
bool frozenPageReloadImminent() => _reloadState.reloadImminent;

/// True exactly once per frozen-reload boot: the marker exists, is fresh, and
/// has not been consumed. The timestamp itself is kept (it is the loop guard);
/// only the "already reported" bit is stamped.
bool consumeFrozenReloadMarker() {
  final at = _readMarkerMs();
  if (at == null) return false;
  const consumedKey = '$_kFrozenReloadMarkerKey.consumed';
  try {
    if (web.window.sessionStorage.getItem(consumedKey) == at.toString()) {
      return false;
    }
    web.window.sessionStorage.setItem(consumedKey, at.toString());
  } catch (_) {
    return false;
  }
  return DateTime.now().millisecondsSinceEpoch - at <=
      _kFrozenReloadMarkerFreshMs;
}

int? _readMarkerMs() {
  try {
    final raw = web.window.sessionStorage.getItem(_kFrozenReloadMarkerKey);
    if (raw == null) return null;
    return int.tryParse(raw);
  } catch (_) {
    return null;
  }
}

class _CancelOnlySubscription implements StreamSubscription<web.Event> {
  _CancelOnlySubscription(this._onCancel);

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
