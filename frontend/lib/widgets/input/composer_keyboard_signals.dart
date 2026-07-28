import 'package:flutter/foundation.dart';

/// Set true by the composer the instant it initiates a send / deliberate refocus
/// that may briefly blur and then restore the IME (the iOS send-button bounce).
///
/// While true, [ChatComposerViewport] DEFERS collapsing the keyboard inset (the
/// 450 ms debounce) so the composer does not visibly drop during the bounce —
/// this is the flash guard. On a genuine user dismiss the flag stays false, so
/// the inset collapses immediately and there is no laggy dark gap on keyboard
/// hide (Symptom B). Singleton: only one chat composer is active at a time.
final ValueNotifier<bool> composerKeyboardCollapseGuard = ValueNotifier<bool>(
  false,
);

/// True while the composer has a bottom panel (emoji picker) open that
/// REPLACES the keyboard. While true, [ChatComposerViewport] anchors the
/// composer block at `bottom: 0` instead of the keyboard inset, so on a
/// keyboard→panel switch the panel occupies the keyboard's space from the
/// first frame and the dismissing keyboard simply reveals it (native-style
/// swap). Without this the panel mounts above the still-large inset and
/// visibly drops from the top as the inset collapses.
/// Singleton: only one chat composer is active at a time.
/// (Removed in 0.0.115 with the composer emoji button; restored 2026-07-28
/// with it — owner ruling: not every soft keyboard exposes an emoji key.)
final ValueNotifier<bool> composerBottomPanelPinned = ValueNotifier<bool>(
  false,
);

// 2026-07-07 device-probe verdicts (see the composer-viewport session
// summary): the DOM focus guard is LOAD-BEARING (FG-OFF made every send tap
// dismiss the keyboard) — never remove it. The `_sendJustFired` fast-refocus
// machinery stays deleted (proven unobservable). The flash-fix predicted-inset
// pre-arm is DELETED FOR GOOD (2026-07-09): resurrected default-OFF for the
// action-panel flash A/B, but the flash died from the H1/H2/H3 transition
// fixes alone (0.0.99 device-confirmed) and the toggle was never needed. Do
// not reintroduce it without new device evidence.
