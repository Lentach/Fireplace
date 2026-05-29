# Chat Composer — iOS WebKit Focus Guard + Send-Button Affordance — Design

**Date:** 2026-05-29
**Status:** Approved for implementation
**App version at spec time:** `0.0.18` (`frontend/pubspec.yaml`)
**Platform scope:** iOS WebKit **only** (iPhone Safari + iPhone Chrome — both are WebKit). No effect on Android, desktop web, or native.
**Related:** `2026-05-24-trailing-send-button-spec.md`, `2026-05-23-chat-composer-viewport-design.md`, `2026-05-28-composer-send-mic-lockup-design.md`

---

## 1. Problem

On iPhone (Safari **and** Chrome — both WebKit), after typing a message and tapping the **on-screen send arrow** (the control that replaces the mic while text is present):

1. The message sends, but the **soft keyboard dismisses**.
2. The user taps the text field again to keep writing. Flutter still considers the field focused, so `_focusNode.requestFocus()` is a no-op and `_onComposerFocusForWebViewport` never re-fires.
3. WebKit scrolls the page to "reveal" the native input; nothing resets the document scroll, so the Flutter canvas is pushed up, leaving a large **black void above the keyboard** (the "jump").

**Confirmed by the user:** sending via the **virtual keyboard's own send key keeps the keyboard up perfectly** — only the in-app arrow breaks. iOS-WebKit-only.

### Root cause (one cause, two symptoms)

Flutter web keeps a single hidden DOM editable element for the focused field; the iOS keyboard is bound to *that element being focused*.

- The **keyboard send key** acts on the focused input itself, inside WebKit's editing session → focus retained → keyboard stays.
- The **on-screen arrow** is a tap on Flutter's **canvas**, outside the input. The browser's default `touchstart`/`mousedown` action moves focus **off** the input → WebKit blurs it → keyboard closes (symptom 1) and the later re-tap triggers the scroll/jump (symptom 2).
- iOS only **opens** the keyboard from a genuine user gesture on the input, so the existing post-send `requestFocus()` + `TextInput.show()` running in a `postFrameCallback` (outside the user-activation window) are silently ignored — which is why prior "revive" fixes never worked.

Every prior fix fought a symptom (revive / reposition / scroll-lock). This spec fixes the cause: **never let the input blur when an in-app composer control is tapped while editing.**

### Ruled out: the "invisible mic" theory

A plain tap on the mic runs **no** keyboard code: the mic's `GestureDetector` handles long-press only, and a quick tap hits `Listener.onPointerUp → _onPointerRelease()` which returns early when not recording (`recording_controller.dart:562-566`). The send overlay also sits on top with `HitTestBehavior.opaque`. The blur is WebKit's native focus-steal on a canvas tap, not our mic logic.

---

## 2. Goals & non-goals

### Goals

| # | Goal |
|---|------|
| G1 | Tapping the in-app **text-send arrow** while editing **keeps the soft keyboard open** on iOS WebKit — same behavior as the keyboard's own send key. |
| G2 | The post-send re-tap **jump** disappears, because the keyboard never drops in the first place. |
| G3 | Same focus-preserving guard also covers the **voice "send locked recording" arrow** and the **action-panel ⌄ toggle** (both are canvas taps that blur the input while editing). |
| G4 | **Send-button affordance:** the text-send arrow is **centered** and **larger** with a **full 48×48 tap target** (currently a left-nudged 22×22 target that is easy to miss). |
| G5 | **Zero effect off iOS WebKit:** Android, desktop web, and native builds are byte-for-byte unchanged (stub no-ops, passthrough widget). |
| G6 | No global scroll-lock, no keyboard "revive", no fixes-on-fixes. |

### Non-goals

| Item | Notes |
|------|-------|
| Mic icon placement | **Unchanged** — keeps its −6px left nudge (`kMicTrailingRestingOffsetX`) and 22px size, intentionally clear of the OS edge-back gesture. |
| Voice "send" arrow geometry | Stays the existing 48×48 `IconButton`; only the **text-send** arrow is re-centered/enlarged per G4. |
| Guarding the **text field** itself | Deliberately not guarded — it must take focus and place the caret normally. |
| `visualViewport`-based keyboard inset | Out of scope; follow-up only if QA still shows residual jump. |
| Version bump | Bump PATCH to **0.0.19** when implementation ships (production-worthy UX fix). |

---

## 3. Design

### 3.1 Mechanism

Install a **capture-phase `window` listener** for `touchstart` and `mousedown` (— **not** `pointerdown`). On each event, call `event.preventDefault()` (and **never** `stopPropagation()`) when **all** are true:

1. Platform is iOS WebKit (`isIOSWebKit()`), **and**
2. `document.activeElement` is an editable element (`INPUT` / `TEXTAREA` / `isContentEditable`) — i.e. the composer is focused and the keyboard is up, **and**
3. the event's `clientX/clientY` falls inside a **registered guard rect**.

`preventDefault` blocks WebKit's focus-steal default action; omitting `stopPropagation` lets the event continue into Flutter's pointer pipeline, so the existing tap handlers (`_send()`, `sendLockedRecording()`, `_toggleActionPanel()`) **still fire**. The input never blurs → keyboard stays → no scroll/jump.

**Why `touchstart` + `mousedown` only, not `pointerdown`:** the focus-steal is the default action of `touchstart`/`mousedown`. On iOS WebKit the **`touchstart`** listener is load-bearing (it fires first and carries the blur); `mousedown` is synthesized late and is only belt-and-suspenders (see the §4 fallback). Flutter web's tap detection is driven by **pointer** events, so leaving `pointerdown` untouched keeps Flutter's gesture arena intact while still cancelling the blur.

**Why check `document.activeElement` instead of piping Dart focus state:** self-contained and reliable. If no editable is focused there is no keyboard to protect, so the guard simply does nothing — it can never block legitimate first-focus on the field.

### 3.2 Coordinate space

Flutter `RenderBox.localToGlobal` returns **logical** pixels; DOM `clientX/clientY` are **CSS** pixels. On Flutter web these are the same unit, so guard rects and touch points compare directly with no devicePixelRatio conversion.

### 3.3 Components

**1. `frontend/lib/utils/web_focus_guard.dart`** — conditional-import facade:
```
ensureFocusGuardListenerInstalled();          // idempotent; installs window listeners once
registerFocusGuardRect(String id, Rect rect); // upsert a guard rect
unregisterFocusGuardRect(String id);          // remove a guard rect
```
- `web_focus_guard_stub.dart` — all no-ops (non-web / non-iOS use this path).
- `web_focus_guard_web.dart` — `package:web` + `dart:js_interop`. Guarded by `isIOSWebKit()` (early-returns to no-op on other browsers). Holds an `id → Rect` map; `ensure…` attaches the two capture-phase listeners exactly once.

**2. `frontend/lib/widgets/input/focus_guard_area.dart`** — `FocusGuardArea({required String id, required Widget child})`:
- On `kIsWeb && isIOSWebKit()` only: schedule **one** `addPostFrameCallback` **per `build` pass** (i.e. per rebuild — **not** a self-rechaining per-frame loop) that measures the child's global `Rect` via its `RenderBox` and calls `registerFocusGuardRect(id, rect)`; `unregisterFocusGuardRect(id)` in `dispose`.
- This is correct and sufficient because the composer's position only changes when `MediaQuery.viewInsets` changes (keyboard up/down), which always triggers a parent rebuild → `FocusGuardArea.build()` → exactly one re-measurement. Reply-bar / action-panel growth likewise rebuilds the composer. **Do not** re-register inside the post-frame callback to "keep it fresh every frame" — that would create a chained callback loop and burn a frame's work continuously.
- Otherwise a pure passthrough returning `child` (no RenderBox math, no cost).

**3. Wiring in `frontend/lib/widgets/input/chat_input_bar.dart`:**
- `initState` (web): `ensureFocusGuardListenerInstalled()`.
- Wrap the trailing 48×48 slot (`_buildTrailingSlot`) in `FocusGuardArea(id: 'composer_trailing')` — covers text-send + voice-send + mic (all share the slot).
- Wrap the action-panel toggle `IconButton` in `FocusGuardArea(id: 'composer_action_toggle')`.

### 3.4 Send-button affordance (G4)

In `_buildTrailingSlot` (`chat_input_bar.dart`):
- **Decouple offsets:** keep `kMicTrailingRestingOffsetX` (−6) for the **mic** and the **voice-send** layers; introduce a separate **centered** offset (`0.0`) for the **text-send** layer only.
- **Enlarge the icon:** text-send `Icons.send_rounded` size `22 → 26`.
- **Full-size tap target:** grow `_ComposerTapSendOverlay`'s hit `SizedBox` from `22×22` to fill the 48×48 slot (e.g. `Positioned.fill` / `SizedBox.expand` inside the existing `composer_text_send_layer`). With `HitTestBehavior.opaque` this also closes the current bug where outer-ring taps fall through to the hidden mic.
- The overlay stays a **tap-only `Listener`** (not `IconButton`) so it never wins the gesture arena — but this is moot for recording, since the send layer is only interactive when text is present (`showTextSend`) and recording requires an empty composer.

The enlarged button sits entirely inside the `'composer_trailing'` guard rect, so the focus guard already covers it.

**Geometry refactor note:** today the send icon paint **and** `_ComposerTapSendOverlay` are both children of a **single** `Transform.translate(offset: kMicTrailingRestingOffsetX)` inside `composer_text_send_layer` (`chat_input_bar.dart:336-361`). G4 requires **splitting** that single transform:
- the **send icon** keeps its own `Transform.translate(0,0)` (centered — was −6) wrapped in `IgnorePointer` (paint only);
- the **`_ComposerTapSendOverlay`** becomes a `Positioned.fill` (or `SizedBox.expand`) with **no** translation, so its 48×48 opaque hit area is centered in the slot.

The mic and voice-send layers keep `kMicTrailingRestingOffsetX`; only the text-send layer is decoupled.

### 3.5 Relationship to existing focus code (G6)

This spec adds **no new** "revive the focus" layer. Existing focus code is evaluated, not blindly kept:

- **`setComposerFocusRequest` / `_requestComposerFocus` (chat_input_bar.dart:120/147, messaging_provider.dart:592-599) — KEEP.** It is the **reply-flow** focus hook: `setReplyingTo()` calls it so tapping "reply" focuses the composer **within the reply tap's user-gesture turn**. That is a legitimate, cross-platform, gesture-driven focus — not the broken post-send revive. Removing it would break reply-focus on all platforms.
- **`_send()` post-frame refocus (chat_input_bar.dart:173-179) — KEEP, unchanged.** It is still needed on **Android**, where the IME "Send" action can unfocus the field. With the focus guard in place the input no longer blurs on **iOS WebKit** send, so on iOS this block becomes a harmless no-op (focus already held) rather than the load-bearing fix. We are not adding to it.

Net for G6: the only new mechanism is the DOM focus guard; the retained focus code serves Android/reply flows and is not symptom-fighting the iOS send-blur.

---

## 4. Testing & verification

### Automated (widget tests)
- `FocusGuardArea` registers a rect on mount, updates it on a layout/size change, and unregisters on dispose — verified via a test seam over the registry (an injectable register/unregister recorder). Note: under `flutter test` (VM) the conditional import resolves to the **stub**, so the test seam must sit at the `FocusGuardArea` boundary (recording the calls it *would* make) rather than relying on the web registry.
- The stub (`web_focus_guard_stub.dart`) is a verified no-op on non-web.
- **Not unit-testable:** the listener + hit-test + `preventDefault` logic in `web_focus_guard_web.dart` cannot be reached under `flutter test` (stub resolves on VM). This is intentional and consistent with the codebase's other stub/web pairs — that logic is covered **only by manual iPhone QA** below.
- Existing composer regression tests still pass: `chat_input_bar_disappearing_banner_test.dart`, plus the send/mic/lock tests referenced in CLAUDE.md.
- `flutter analyze` clean.

### Manual (required — cannot be unit-tested)
The native focus-steal only reproduces on a real device. **Manual iPhone QA on Safari AND Chrome** (consistent with CLAUDE.md "Manual iPhone QA required"):
1. Type → tap the in-app send arrow → **keyboard stays up**; can send several messages without re-tapping.
2. No black-void jump at any point.
3. Tapping the message list / leaving the chat tab still dismisses the keyboard (unchanged).
4. Action-panel toggle and voice-send arrow do not dismiss the keyboard while editing.
5. Android + desktop web composer behavior unchanged.

### The one on-device risk to confirm first
That `_send()` **still fires** after `preventDefault()` (it should, since we don't `stopPropagation`). The focus-steal default action on iOS WebKit fires on **`touchstart`**, so `touchstart` is the load-bearing event and `mousedown` is only belt-and-suspenders (synthesized late on iOS). Confirm send firing on the first device test before broader QA.

**Fallback if send is swallowed:** narrow the guard to **`touchstart` only** (drop the `mousedown` listener) — *not* mousedown-only, which would remove the event that actually prevents the blur. A reasonable alternative is to ship **`touchstart`-only first** and add `mousedown` only if a device needs it.

---

## 5. Files

| Action | File |
|--------|------|
| New | `frontend/lib/utils/web_focus_guard.dart` (facade) |
| New | `frontend/lib/utils/web_focus_guard_stub.dart` (no-ops) |
| New | `frontend/lib/utils/web_focus_guard_web.dart` (listener + registry) |
| New | `frontend/lib/widgets/input/focus_guard_area.dart` |
| Edit | `frontend/lib/widgets/input/chat_input_bar.dart` (wiring + send affordance) |
| New | `frontend/test/.../focus_guard_area_test.dart` |
| Edit | `frontend/pubspec.yaml` (version `0.0.18 → 0.0.19`) |
| Edit | `CLAUDE.md` (Frontend gotchas: focus guard + iOS WebKit composer notes) |

---

## 6. Rollback

The entire feature is gated behind `isIOSWebKit()` and a stub conditional import. Reverting the `chat_input_bar.dart` wiring (the two `FocusGuardArea` wraps + `ensureFocusGuardListenerInstalled()`) fully disables it; the send-affordance geometry change is independent and can be reverted separately.
