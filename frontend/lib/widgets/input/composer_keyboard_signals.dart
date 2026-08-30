import 'dart:async';

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

/// True while the paperclip has a native file surface up (the in-app door
/// sheet, the OS chooser, the iOS file popover, a camera app). A keyboard
/// drop in that window is CAUSED by the surface, not by the user dismissing
/// the keyboard, so [ChatComposerViewport] must collapse layout immediately
/// and silently — never run the dismiss ease-down. A timed guard cannot do
/// this job: the drop arrives whenever the OS gets around to it
/// (emulator-measured 2026-08-21: 1.6 s after the paperclip tap, past any
/// sane debounce window). Depth-counted because the Android sheet and the
/// door it opens overlap.
///
/// [MainShell] also suppresses the 0.1.19 frozen-page reload while this is
/// true (a reload destroys the pending file input). That makes a STUCK span
/// dangerous — an engine that never fires 'cancel' would pin the flag and
/// kill freeze recovery for the whole session — so the span self-caps at
/// [_kNativePickerSpanCap]: past it, the depth force-clears and the worst
/// case degrades to the pre-picker behavior (reload on freeze-resume, pick
/// lost), never to a dead recovery path.
final ValueNotifier<bool> composerNativePickerActive = ValueNotifier<bool>(
  false,
);

const Duration _kNativePickerSpanCap = Duration(minutes: 3);

int _nativePickerDepth = 0;
Timer? _nativePickerCapTimer;

void beginComposerNativePicker() {
  _nativePickerDepth++;
  composerNativePickerActive.value = true;
  _nativePickerCapTimer?.cancel();
  _nativePickerCapTimer = Timer(_kNativePickerSpanCap, () {
    _nativePickerDepth = 0;
    composerNativePickerActive.value = false;
  });
}

void endComposerNativePicker() {
  if (_nativePickerDepth > 0) _nativePickerDepth--;
  if (_nativePickerDepth == 0) {
    _nativePickerCapTimer?.cancel();
    _nativePickerCapTimer = null;
    composerNativePickerActive.value = false;
  }
}

// 2026-07-07 device-probe verdicts (see the composer-viewport session
// summary): the DOM focus guard is LOAD-BEARING (FG-OFF made every send tap
// dismiss the keyboard) — never remove it. The `_sendJustFired` fast-refocus
// machinery stays deleted (proven unobservable). The flash-fix predicted-inset
// pre-arm is DELETED FOR GOOD (2026-07-09): resurrected default-OFF for the
// action-panel flash A/B, but the flash died from the H1/H2/H3 transition
// fixes alone (0.0.99 device-confirmed) and the toggle was never needed. Do
// not reintroduce it without new device evidence.
