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
final ValueNotifier<bool> composerBottomPanelPinned = ValueNotifier<bool>(
  false,
);

// 2026-07-07 device-probe verdicts (see the composer-viewport session
// summary): the DOM focus guard is LOAD-BEARING (FG-OFF made every send tap
// dismiss the keyboard) — never remove it. The `_sendJustFired` fast-refocus
// machinery and the flash-fix predicted-inset pre-arm were proven
// unobservable and DELETED; do not reintroduce them without new device
// evidence.
