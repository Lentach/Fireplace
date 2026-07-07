import 'package:flutter/foundation.dart';

/// Set true by the composer the instant it initiates a send / deliberate refocus
/// that may briefly blur and then restore the IME (the iOS send-button bounce).
///
/// While true, [ChatComposerViewport] DEFERS collapsing the keyboard inset (the
/// 450 ms debounce) so the composer does not visibly drop during the bounce —
/// this is the flash guard. On a genuine user dismiss the flag stays false, so
/// the inset collapses immediately and there is no laggy dark gap on keyboard
/// hide (Symptom B). Singleton: only one chat composer is active at a time.
final ValueNotifier<bool> composerKeyboardCollapseGuard =
    ValueNotifier<bool>(false);

/// True while the composer has a bottom panel (emoji picker) open that
/// REPLACES the keyboard. While true, [ChatComposerViewport] anchors the
/// composer block at `bottom: 0` instead of the keyboard inset, so on a
/// keyboard→panel switch the panel occupies the keyboard's space from the
/// first frame and the dismissing keyboard simply reveals it (native-style
/// swap). Without this the panel mounts above the still-large inset and
/// visibly drops from the top as the inset collapses.
/// Singleton: only one chat composer is active at a time.
final ValueNotifier<bool> composerBottomPanelPinned = ValueNotifier<bool>(false);

/// Predicted keyboard inset, pre-armed on composer pointer-DOWN (iOS WebKit
/// only): the last known real keyboard height, applied to layout BEFORE focus
/// commits. The composer — and Flutter's hidden DOM editing element, whose
/// position the engine syncs from the field's transform at IME attach — then
/// already sits above the incoming keyboard when iOS decides whether to pan
/// the visual viewport toward the focused element. No pan = no focus flash
/// (the <1s jump the viewport pin can only reset one frame late; see
/// docs/review/ios-composer-keyboard-flash-handoff.md §2).
///
/// Pure Flutter layout — writes NO DOM styles, so the reverted 0.0.69 DOM
/// pre-arm failure mode (browser-tab toolbar bounce) cannot recur. Cleared by
/// the composer when the real visualViewport inset arrives (handoff) or by a
/// safety timer when the keyboard never shows. 0 = no prediction.
/// [ChatComposerViewport] takes `max(real, predicted)`.
final ValueNotifier<double> predictedComposerKeyboardInset =
    ValueNotifier<double>(0);

/// A/B switch for the flash-fix prediction above, toggleable on-device from
/// the composer diagnostics overlay. Default ON.
final ValueNotifier<bool> composerFlashFixEnabled = ValueNotifier<bool>(true);

/// TEMP Phase-B probe (diagnostics overlay, device sessions only): when true
/// the DOM focus guard (`web_focus_guard_web.dart`) stops intercepting pointer
/// events. Establishes whether the guard is still load-bearing after the
/// 0.0.64 `onTapOutside` fix. Delete once the device verdict is in.
final ValueNotifier<bool> composerProbeDisableFocusGuard =
    ValueNotifier<bool>(false);

/// TEMP Phase-B probe: when true the send refocus machinery is disabled —
/// `_sendJustFired` fast-refocus, the post-frame refocus fallbacks, AND
/// collapse-guard arming (the guard exists solely to mask the bounce the
/// refocus heals). If sends keep the keyboard up with this ON, the blur no
/// longer happens and the whole apparatus is deletable. Delete with verdict.
final ValueNotifier<bool> composerProbeDisableRefocusMachinery =
    ValueNotifier<bool>(false);
