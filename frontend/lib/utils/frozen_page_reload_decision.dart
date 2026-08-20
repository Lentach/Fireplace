/// Pure policy for what to do when a page RESUMES after a Chrome tab freeze.
///
/// Field bug (users 48/90, Aug 2026, on 0.1.18): Android Chrome freezes a
/// backgrounded PWA after ~5 min; a notification-tap `focus()` revives the
/// frozen window, and the thawed Flutter/CanvasKit engine is untrustworthy —
/// stale viewport/keyboard-inset state (composer painted mid-screen), degraded
/// rendering ("lag"), dead-feeling chat. Users' own workaround — swipe-close +
/// relaunch from the icon — is a cold boot, and it always works. This policy
/// converts the broken revived-window path into that working path: a page that
/// was frozen gets REPLACED (full reload) instead of repaired.
///
/// Kept pure and platform-free so the branching is unit-testable without web
/// interop: `page_lifecycle_web.dart` owns the events and applies the verdict.
library;

/// Minimum spacing between forced reloads. A reload loop (freeze/resume storm,
/// or a future browser quirk firing `resume` repeatedly) must degrade to soft
/// recovery, never to a reload cycle the user experiences as a crash loop.
const int kFrozenReloadMinIntervalMs = 30000;

enum FrozenResumeAction {
  /// Not frozen, or reloaded too recently: run the soft foreground recovery
  /// (reconnect + resync), touch nothing else.
  softRecover,

  /// Page was frozen and is visible: replace it now.
  reloadNow,

  /// Page was frozen but is still hidden (`resume` is dispatched BEFORE
  /// `visibilitychange`, and Chrome can also unfreeze in the background):
  /// arm the reload and fire it when the page actually becomes visible.
  armReload,
}

FrozenResumeAction decideOnFrozenResume({
  required bool wasFrozen,
  required bool isVisible,
  required int? lastForcedReloadAtMs,
  required int nowMs,
  int minIntervalMs = kFrozenReloadMinIntervalMs,
}) {
  if (!wasFrozen) return FrozenResumeAction.softRecover;
  if (lastForcedReloadAtMs != null &&
      nowMs - lastForcedReloadAtMs < minIntervalMs) {
    // Loop guard tripped — a second freeze/resume within the window rides the
    // existing soft recovery instead of reloading again.
    return FrozenResumeAction.softRecover;
  }
  return isVisible
      ? FrozenResumeAction.reloadNow
      : FrozenResumeAction.armReload;
}

/// Pure state machine tracking whether a frozen-page reload MAY still happen.
///
/// Why it exists: the push SW's queued `push-notification-click` message
/// flushes on the SAME thaw that fires `resume`, in unspecified order relative
/// to it. The live click handler (push_service.dart) normally deletes the
/// IndexedDB deep-link record the SW stored before focus() — but when a
/// frozen-page reload is coming, that record is the ONLY carrier of the tapped
/// conversation across the reload. So the click handler must consult
/// [reloadImminent] and skip the delete while a reload may follow. The flag is
/// raised at `freeze` time (not at `resume`) precisely because the click can
/// flush BEFORE `resume` runs.
///
/// When the loop guard downgrades the resume to soft recovery, the flag drops
/// and clears behave normally again. A record left behind by a suppressed
/// clear is bounded: it is consumed (and deleted) by the next drain, and
/// records older than 5 minutes are discarded on read.
class FrozenPageReloadState {
  bool _frozen = false;
  bool _reloadImminent = false;

  /// True from the `freeze` event until the resume decision downgrades to
  /// soft recovery. While true, the live click handler must NOT delete the
  /// pending deep-link record.
  bool get reloadImminent => _reloadImminent;

  void onFreeze() {
    _frozen = true;
    _reloadImminent = true;
  }

  FrozenResumeAction onResume({
    required bool isVisible,
    required int? lastForcedReloadAtMs,
    required int nowMs,
    int minIntervalMs = kFrozenReloadMinIntervalMs,
  }) {
    final action = decideOnFrozenResume(
      wasFrozen: _frozen,
      isVisible: isVisible,
      lastForcedReloadAtMs: lastForcedReloadAtMs,
      nowMs: nowMs,
      minIntervalMs: minIntervalMs,
    );
    _frozen = false;
    if (action == FrozenResumeAction.softRecover) {
      // No reload will follow this resume — deep-link clears are safe again.
      _reloadImminent = false;
    }
    return action;
  }
}
