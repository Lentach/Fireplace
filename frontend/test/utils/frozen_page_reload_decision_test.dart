import 'package:fireplace/utils/frozen_page_reload_decision.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression for the frozen-window revival bug (users 48/90, Aug 2026, on
/// 0.1.18): a notification tap `focus()`ing a Chrome-frozen PWA revived an
/// untrustworthy engine (mid-screen composer, lag, no live messages). Policy:
/// a page that was frozen is REPLACED (reload), not repaired — but never while
/// hidden, and never in a loop.
void main() {
  const t0 = 1000000;

  test('not frozen → soft recovery, never a reload', () {
    expect(
      decideOnFrozenResume(
        wasFrozen: false,
        isVisible: true,
        lastForcedReloadAtMs: null,
        nowMs: t0,
      ),
      FrozenResumeAction.softRecover,
    );
  });

  test('frozen and visible → reload now', () {
    expect(
      decideOnFrozenResume(
        wasFrozen: true,
        isVisible: true,
        lastForcedReloadAtMs: null,
        nowMs: t0,
      ),
      FrozenResumeAction.reloadNow,
    );
  });

  test(
    'frozen but still hidden → arm the reload (resume fires BEFORE '
    'visibilitychange; a background unfreeze must not reload a hidden page)',
    () {
      expect(
        decideOnFrozenResume(
          wasFrozen: true,
          isVisible: false,
          lastForcedReloadAtMs: null,
          nowMs: t0,
        ),
        FrozenResumeAction.armReload,
      );
    },
  );

  test('loop guard: a reload within the interval degrades to soft recovery',
      () {
    expect(
      decideOnFrozenResume(
        wasFrozen: true,
        isVisible: true,
        lastForcedReloadAtMs: t0 - kFrozenReloadMinIntervalMs + 1,
        nowMs: t0,
      ),
      FrozenResumeAction.softRecover,
    );
  });

  test('an old reload outside the interval does not block the next one', () {
    expect(
      decideOnFrozenResume(
        wasFrozen: true,
        isVisible: true,
        lastForcedReloadAtMs: t0 - kFrozenReloadMinIntervalMs,
        nowMs: t0,
      ),
      FrozenResumeAction.reloadNow,
    );
  });

  group('FrozenPageReloadState.reloadImminent — deep-link record survival', () {
    // The SW's queued push-notification-click flushes on the SAME thaw as
    // `resume`, in unspecified order. While reloadImminent holds, the live
    // click handler must NOT delete the IndexedDB deep-link record — it is the
    // only carrier of the tapped conversation across the forced reload.
    test('freeze raises the flag BEFORE any resume decision '
        '(click can flush first)', () {
      final s = FrozenPageReloadState();
      expect(s.reloadImminent, isFalse);
      s.onFreeze();
      expect(s.reloadImminent, isTrue);
    });

    test('reloadNow keeps the flag: the record must survive up to the reload',
        () {
      final s = FrozenPageReloadState()..onFreeze();
      final action = s.onResume(
        isVisible: true,
        lastForcedReloadAtMs: null,
        nowMs: t0,
      );
      expect(action, FrozenResumeAction.reloadNow);
      expect(s.reloadImminent, isTrue);
    });

    test('armReload keeps the flag while the page waits to become visible',
        () {
      final s = FrozenPageReloadState()..onFreeze();
      final action = s.onResume(
        isVisible: false,
        lastForcedReloadAtMs: null,
        nowMs: t0,
      );
      expect(action, FrozenResumeAction.armReload);
      expect(s.reloadImminent, isTrue);
    });

    test('loop-guarded soft recovery drops the flag: clears are safe again',
        () {
      final s = FrozenPageReloadState()..onFreeze();
      final action = s.onResume(
        isVisible: true,
        lastForcedReloadAtMs: t0 - 1,
        nowMs: t0,
      );
      expect(action, FrozenResumeAction.softRecover);
      expect(s.reloadImminent, isFalse);
    });

    test('a resume without a preceding freeze never claims imminence', () {
      final s = FrozenPageReloadState();
      final action = s.onResume(
        isVisible: true,
        lastForcedReloadAtMs: null,
        nowMs: t0,
      );
      expect(action, FrozenResumeAction.softRecover);
      expect(s.reloadImminent, isFalse);
    });
  });
}
