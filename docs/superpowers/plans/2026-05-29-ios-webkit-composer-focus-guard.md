# iOS WebKit Composer Focus Guard + Send-Button Affordance — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the iOS-WebKit soft keyboard from dismissing when the in-app send arrow (and voice-send arrow / action-panel toggle) are tapped, and make the text-send arrow a centered, full-size 48×48 target.

**Architecture:** A capture-phase `window` listener for `touchstart`/`mousedown` calls `preventDefault()` when the composer input is focused and the tap lands inside a registered control rect — cancelling WebKit's focus-steal so the input never blurs. Flutter still receives the tap (no `stopPropagation`) so send still fires. iOS-WebKit-only via a conditional-import stub; a `FocusGuardArea` widget keeps each control's screen rect registered.

**Tech Stack:** Flutter (Dart), `package:web ^1.1.0`, `dart:js_interop`, existing `isIOSWebKit()` (`frontend/lib/utils/web_ios_webkit.dart`).

**Spec:** `docs/superpowers/specs/2026-05-29-ios-webkit-composer-focus-guard-design.md`

---

## File Structure

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `frontend/lib/utils/web_focus_guard_stub.dart` | No-op implementations (non-web / VM). |
| Create | `frontend/lib/utils/web_focus_guard_web.dart` | Real registry + capture-phase listener + hit-test + `preventDefault`. |
| Create | `frontend/lib/utils/web_focus_guard.dart` | Conditional-import facade + test-seam hooks. |
| Create | `frontend/lib/widgets/input/focus_guard_area.dart` | Widget that measures its child's global rect and registers/unregisters it. |
| Create | `frontend/test/widgets/input/focus_guard_area_test.dart` | Widget test for register/update/unregister via the test seam. |
| Modify | `frontend/lib/widgets/input/chat_input_bar.dart` | Install listener; wrap trailing slot + action toggle; center/enlarge text-send arrow. |
| Modify | `frontend/pubspec.yaml` | Version `0.0.18 → 0.0.19`. |
| Modify | `CLAUDE.md` | Frontend gotchas: focus guard + send-arrow geometry. |

All imports in `frontend/` use `package:fireplace/...`.

---

## Task 1: Focus-guard facade + stub (no behavior change yet)

**Files:**
- Create: `frontend/lib/utils/web_focus_guard_stub.dart`
- Create: `frontend/lib/utils/web_focus_guard.dart`

- [ ] **Step 1: Create the stub (no-ops)**

`frontend/lib/utils/web_focus_guard_stub.dart`:

```dart
import 'package:flutter/widgets.dart' show Rect;

/// Non-web / VM: focus guard is a no-op.
void ensureFocusGuardListenerInstalled() {}

void registerFocusGuardRect(String id, Rect rect) {}

void unregisterFocusGuardRect(String id) {}
```

- [ ] **Step 2: Create the facade with test-seam hooks**

`frontend/lib/utils/web_focus_guard.dart`:

```dart
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/widgets.dart' show Rect;

import 'web_focus_guard_stub.dart'
    if (dart.library.html) 'web_focus_guard_web.dart' as impl;

// Indirection so widget tests can observe register/unregister calls without the
// web implementation (which only loads under dart.library.html).
void Function(String id, Rect rect) _registerImpl = impl.registerFocusGuardRect;
void Function(String id) _unregisterImpl = impl.unregisterFocusGuardRect;

/// Installs the capture-phase touchstart/mousedown listener once (web/iOS only).
void ensureFocusGuardListenerInstalled() =>
    impl.ensureFocusGuardListenerInstalled();

/// Upserts the screen [rect] guarded under [id].
void registerFocusGuardRect(String id, Rect rect) => _registerImpl(id, rect);

/// Removes the guard rect for [id].
void unregisterFocusGuardRect(String id) => _unregisterImpl(id);

@visibleForTesting
void setFocusGuardHooksForTest({
  void Function(String id, Rect rect)? register,
  void Function(String id)? unregister,
}) {
  if (register != null) _registerImpl = register;
  if (unregister != null) _unregisterImpl = unregister;
}

@visibleForTesting
void resetFocusGuardHooksForTest() {
  _registerImpl = impl.registerFocusGuardRect;
  _unregisterImpl = impl.unregisterFocusGuardRect;
}
```

- [ ] **Step 3: Analyze**

Run: `cd frontend && flutter analyze lib/utils/web_focus_guard.dart lib/utils/web_focus_guard_stub.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/utils/web_focus_guard.dart frontend/lib/utils/web_focus_guard_stub.dart
git commit -m "feat(composer): focus-guard facade + no-op stub

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Web implementation (listener + registry)

**Files:**
- Create: `frontend/lib/utils/web_focus_guard_web.dart`

> Note: this file's listener/hit-test/`preventDefault` logic is **not** reachable under `flutter test` (the VM resolves the stub). It is covered by manual iPhone QA in Task 6. Verification here is `flutter analyze` + a web compile smoke check.

- [ ] **Step 1: Create the web implementation**

`frontend/lib/utils/web_focus_guard_web.dart`:

```dart
import 'dart:js_interop';

import 'package:flutter/widgets.dart' show Offset, Rect;
import 'package:web/web.dart' as web;

import 'web_ios_webkit.dart';

final Map<String, Rect> _rects = <String, Rect>{};
bool _installed = false;
JSFunction? _listener;

void ensureFocusGuardListenerInstalled() {
  if (_installed) return;
  if (!isIOSWebKit()) return;
  _installed = true;
  _listener = _onPointerDownCapture.toJS;
  // passive: false is required so preventDefault() is allowed on touchstart.
  final options = web.AddEventListenerOptions(capture: true, passive: false);
  web.window.addEventListener('touchstart', _listener, options);
  web.window.addEventListener('mousedown', _listener, options);
}

void registerFocusGuardRect(String id, Rect rect) {
  if (!isIOSWebKit()) return;
  _rects[id] = rect;
}

void unregisterFocusGuardRect(String id) {
  _rects.remove(id);
}

void _onPointerDownCapture(web.Event event) {
  // Only protect an active editing session; otherwise let the tap behave normally
  // (e.g. first focus on the field must still work).
  if (!_isEditable(web.document.activeElement)) return;
  final point = _eventPoint(event);
  if (point == null) return;
  for (final rect in _rects.values) {
    if (rect.contains(point)) {
      // Cancel WebKit's focus-steal so the input keeps focus and the keyboard
      // stays up. We do NOT stopPropagation, so Flutter still receives the tap.
      event.preventDefault();
      return;
    }
  }
}

bool _isEditable(web.Element? el) {
  if (el == null) return false;
  final tag = el.tagName.toUpperCase();
  if (tag == 'INPUT' || tag == 'TEXTAREA') return true;
  if (el.isA<web.HTMLElement>()) {
    return (el as web.HTMLElement).isContentEditable;
  }
  return false;
}

Offset? _eventPoint(web.Event event) {
  if (event.isA<web.TouchEvent>()) {
    final touches = (event as web.TouchEvent).touches;
    if (touches.length == 0) return null;
    final touch = touches.item(0);
    if (touch == null) return null;
    return Offset(touch.clientX.toDouble(), touch.clientY.toDouble());
  }
  if (event.isA<web.MouseEvent>()) {
    final m = event as web.MouseEvent;
    return Offset(m.clientX.toDouble(), m.clientY.toDouble());
  }
  return null;
}
```

- [ ] **Step 2: Analyze**

Run: `cd frontend && flutter analyze lib/utils/web_focus_guard_web.dart`
Expected: `No issues found!`

- [ ] **Step 3: Web compile smoke check**

Run: `cd frontend && flutter build web --no-tree-shake-icons -t lib/main.dart 2>&1 | tail -20`
Expected: build completes (`✓ Built build/web`). This proves the `package:web` / `js_interop` usage compiles for the web target. (If the project has a faster compile gate, that is acceptable instead.)

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/utils/web_focus_guard_web.dart
git commit -m "feat(composer): iOS WebKit focus-guard listener + rect registry

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: `FocusGuardArea` widget (TDD)

**Files:**
- Create: `frontend/test/widgets/input/focus_guard_area_test.dart`
- Create: `frontend/lib/widgets/input/focus_guard_area.dart`

- [ ] **Step 1: Write the failing test**

`frontend/test/widgets/input/focus_guard_area_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fireplace/utils/web_focus_guard.dart';
import 'package:fireplace/widgets/input/focus_guard_area.dart';

void main() {
  setUp(() {
    // Force the active path on the VM, where kIsWeb / isIOSWebKit are false.
    FocusGuardArea.debugForceActiveForTest = true;
  });

  tearDown(() {
    FocusGuardArea.debugForceActiveForTest = false;
    resetFocusGuardHooksForTest();
  });

  testWidgets('registers child rect on mount and unregisters on dispose',
      (tester) async {
    final registered = <String, Rect>{};
    final unregistered = <String>[];
    setFocusGuardHooksForTest(
      register: (id, rect) => registered[id] = rect,
      unregister: unregistered.add,
    );

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 48,
            height: 48,
            child: FocusGuardArea(
              id: 'composer_trailing',
              child: SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await tester.pump(); // flush the post-frame measurement

    expect(registered.containsKey('composer_trailing'), isTrue);
    expect(registered['composer_trailing']!.width, 48);
    expect(registered['composer_trailing']!.height, 48);

    // Remove the widget -> dispose -> unregister.
    await tester.pumpWidget(const SizedBox());
    expect(unregistered, contains('composer_trailing'));
  });

  testWidgets('re-registers when the child size changes', (tester) async {
    var lastRect = Rect.zero;
    setFocusGuardHooksForTest(
      register: (id, rect) => lastRect = rect,
      unregister: (_) {},
    );

    Widget build(double size) => Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: size,
              height: size,
              child: const FocusGuardArea(
                id: 'composer_trailing',
                child: SizedBox.expand(),
              ),
            ),
          ),
        );

    await tester.pumpWidget(build(48));
    await tester.pump();
    expect(lastRect.width, 48);

    await tester.pumpWidget(build(64));
    await tester.pump();
    expect(lastRect.width, 64);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd frontend && flutter test test/widgets/input/focus_guard_area_test.dart`
Expected: FAIL — `focus_guard_area.dart` / `FocusGuardArea` not found (compile error).

- [ ] **Step 3: Implement the widget**

`frontend/lib/widgets/input/focus_guard_area.dart`:

```dart
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/widgets.dart';

import '../../utils/web_focus_guard.dart';
import '../../utils/web_ios_webkit.dart';

/// Keeps [child]'s on-screen [Rect] registered under [id] with the focus guard,
/// so an iOS-WebKit tap inside it does not blur the focused composer input
/// (which would dismiss the soft keyboard). No-op passthrough off iOS WebKit.
class FocusGuardArea extends StatefulWidget {
  const FocusGuardArea({super.key, required this.id, required this.child});

  final String id;
  final Widget child;

  /// Test-only: force the register path on the VM (where [kIsWeb] is false).
  @visibleForTesting
  static bool debugForceActiveForTest = false;

  @override
  State<FocusGuardArea> createState() => _FocusGuardAreaState();
}

class _FocusGuardAreaState extends State<FocusGuardArea> {
  bool get _active =>
      FocusGuardArea.debugForceActiveForTest || (kIsWeb && isIOSWebKit());

  void _scheduleMeasure() {
    if (!_active) return;
    // One post-frame measurement per build pass. Position only changes when the
    // composer rebuilds (keyboard inset / reply bar / action panel), so this is
    // sufficient. Do NOT re-chain inside the callback (would run every frame).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      registerFocusGuardRect(widget.id, rect);
    });
  }

  @override
  void dispose() {
    if (_active) unregisterFocusGuardRect(widget.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _scheduleMeasure();
    return widget.child;
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd frontend && flutter test test/widgets/input/focus_guard_area_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Analyze**

Run: `cd frontend && flutter analyze lib/widgets/input/focus_guard_area.dart test/widgets/input/focus_guard_area_test.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add frontend/lib/widgets/input/focus_guard_area.dart frontend/test/widgets/input/focus_guard_area_test.dart
git commit -m "feat(composer): FocusGuardArea widget + tests

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Wire the guard into `ChatInputBar`

**Files:**
- Modify: `frontend/lib/widgets/input/chat_input_bar.dart`

- [ ] **Step 1: Add imports**

In the import block (near `import 'recording_controller.dart';` / `import 'reply_preview_bar.dart';`), add:

```dart
import '../../utils/web_focus_guard.dart';
import 'focus_guard_area.dart';
```

- [ ] **Step 2: Install the listener in `initState`**

In `initState()`, inside the existing `if (kIsWeb) { ... }` block (which currently adds `_focusNode.addListener(_onComposerFocusForWebViewport)`), add the install call so it reads:

```dart
    if (kIsWeb) {
      _focusNode.addListener(_onComposerFocusForWebViewport);
      ensureFocusGuardListenerInstalled();
    }
```

- [ ] **Step 3: Wrap the trailing slot**

In `build()`, the input `Row` ends with a call to `_buildTrailingSlot(context)` (the comment above it reads "Trailing 48×48 stack: mic always mounted…"). Replace that single call:

```dart
                _buildTrailingSlot(context),
```

with:

```dart
                FocusGuardArea(
                  id: 'composer_trailing',
                  child: _buildTrailingSlot(context),
                ),
```

- [ ] **Step 4: Wrap the action-panel toggle**

In `build()`, the `if (!_isRecording)` branch renders a `Focus(canRequestFocus: false, child: IconButton(...))` for the panel toggle. Wrap that `Focus(...)` widget in a `FocusGuardArea`:

```dart
                if (!_isRecording)
                  FocusGuardArea(
                    id: 'composer_action_toggle',
                    child: Focus(
                      canRequestFocus: false,
                      child: IconButton(
                        icon: Icon(
                          _showActionPanel
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                        ),
                        iconSize: 24,
                        color: isDark
                            ? RpgTheme.mutedDark
                            : RpgTheme.textSecondaryLight,
                        onPressed: _toggleActionPanel,
                      ),
                    ),
                  ),
```

- [ ] **Step 5: Analyze**

Run: `cd frontend && flutter analyze lib/widgets/input/chat_input_bar.dart`
Expected: `No issues found!`

- [ ] **Step 6: Run composer regression tests**

Run: `cd frontend && flutter test test/widgets/input/`
Expected: PASS (all existing input widget tests, including `chat_input_bar_disappearing_banner_test.dart`, plus Task 3's test).

- [ ] **Step 7: Commit**

```bash
git add frontend/lib/widgets/input/chat_input_bar.dart
git commit -m "feat(composer): guard send/voice/toggle taps from blurring input on iOS WebKit

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: Send-button affordance (center + enlarge + full hit target)

**Files:**
- Modify: `frontend/lib/widgets/input/chat_input_bar.dart`

- [ ] **Step 1: Center + enlarge the text-send icon and make the overlay fill the slot**

In `_buildTrailingSlot`, inside `composer_text_send_layer`, the inner `Stack(alignment: Alignment.center, children: [...])` currently wraps **both** the send `Icon` and `_ComposerTapSendOverlay` in `Transform.translate(offset: Offset(kMicTrailingRestingOffsetX, 0))`. Replace that inner Stack's children:

Old:
```dart
                          children: [
                            // Send icon paint only — no hit test (long-press uses mic below).
                            IgnorePointer(
                              child: Transform.translate(
                                offset: const Offset(
                                  RecordingControllerState
                                      .kMicTrailingRestingOffsetX,
                                  0,
                                ),
                                child: Icon(
                                  Icons.send_rounded,
                                  size: 22,
                                  color: RpgTheme.primaryColor(context),
                                ),
                              ),
                            ),
                            Transform.translate(
                              offset: const Offset(
                                RecordingControllerState
                                    .kMicTrailingRestingOffsetX,
                                0,
                              ),
                              child: _ComposerTapSendOverlay(
                                enabled: showTextSend,
                                onTap: _send,
                                tooltip: l10n.chatComposerSendTooltip,
                                semanticsLabel: l10n.chatComposerSendSemantics,
                              ),
                            ),
                          ],
```

New (text-send is centered — no `kMicTrailingRestingOffsetX` — icon enlarged to 26, overlay fills the 48×48 slot):
```dart
                          children: [
                            // Centered send icon, paint only — no hit test (the mic
                            // GestureDetector below handles hold-to-record).
                            IgnorePointer(
                              child: Icon(
                                Icons.send_rounded,
                                size: 26,
                                color: RpgTheme.primaryColor(context),
                              ),
                            ),
                            // Full 48×48 opaque tap target (was a left-nudged 22×22,
                            // easy to miss + leaked outer-ring taps to the mic).
                            Positioned.fill(
                              child: _ComposerTapSendOverlay(
                                enabled: showTextSend,
                                onTap: _send,
                                tooltip: l10n.chatComposerSendTooltip,
                                semanticsLabel: l10n.chatComposerSendSemantics,
                              ),
                            ),
                          ],
```

(The **mic** and **voice-send** layers keep `kMicTrailingRestingOffsetX` — do not touch them.)

- [ ] **Step 2: Make `_ComposerTapSendOverlay` fill its parent**

In `_ComposerTapSendOverlayState.build`, change the fixed 22×22 box to expand so it fills the `Positioned.fill`. Replace:

Old:
```dart
  @override
  Widget build(BuildContext context) {
    const size = 22.0;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: Tooltip(
        message: widget.tooltip,
        child: Semantics(
          button: true,
          label: widget.semanticsLabel,
          excludeSemantics: true,
          child: SizedBox(width: size, height: size),
        ),
      ),
    );
  }
```

New:
```dart
  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: Tooltip(
        message: widget.tooltip,
        child: Semantics(
          button: true,
          label: widget.semanticsLabel,
          excludeSemantics: true,
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
```

- [ ] **Step 3: Analyze**

Run: `cd frontend && flutter analyze lib/widgets/input/chat_input_bar.dart`
Expected: `No issues found!` (in particular, `kMicTrailingRestingOffsetX` is still referenced by the mic/voice-send layers, so no "unused" warning).

- [ ] **Step 4: Run composer regression tests**

Run: `cd frontend && flutter test test/widgets/input/`
Expected: PASS. If a test asserts the old 22×22 send box or the send icon's `-6` offset, update that test to the new centered 48×48 geometry (the new behavior is intended per the spec) and re-run.

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/widgets/input/chat_input_bar.dart
git commit -m "feat(composer): center + enlarge text-send arrow to full 48x48 target

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: Version bump, CLAUDE.md, full verification

**Files:**
- Modify: `frontend/pubspec.yaml`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Bump the version**

In `frontend/pubspec.yaml`, change:
```yaml
version: 0.0.18
```
to:
```yaml
version: 0.0.19
```
(Bump only the semver before any `+build`, per `.cursor/rules/version-bump.mdc`.)

- [ ] **Step 2: Update CLAUDE.md (Frontend gotchas)**

In `CLAUDE.md`, in the **Frontend** bullet list (Section 1), add a bullet after the existing iOS web-push / composer entries:

```markdown
- **iOS WebKit composer focus guard:** Tapping a canvas-painted composer control (text-send arrow, voice-send arrow, action-panel toggle) used to blur the focused input → dismiss the keyboard + cause the re-tap "jump". `utils/web_focus_guard.dart` (stub/web pair) installs a capture-phase `window` `touchstart`+`mousedown` listener that `preventDefault()`s the focus-steal when an editable is focused and the point hits a registered rect (no `stopPropagation`, so Flutter still fires the tap). `touchstart` is load-bearing; `mousedown` is belt-and-suspenders. `widgets/input/focus_guard_area.dart` registers each control's global rect (ids `composer_trailing`, `composer_action_toggle`) per rebuild; `ensureFocusGuardListenerInstalled()` called in `ChatInputBar.initState`. iOS-WebKit-only (`isIOSWebKit()`), no-op elsewhere. Manual iPhone QA (Safari + Chrome) required. Regression: `focus_guard_area_test.dart`.
- **Trailing text-send arrow:** centered (no `kMicTrailingRestingOffsetX`), icon 26, full 48×48 opaque hit target (`Positioned.fill` + `SizedBox.expand`). Mic + voice-send keep the `-6` left nudge.
```

- [ ] **Step 3: Full frontend test + analyze**

Run: `cd frontend && flutter analyze`
Expected: `No issues found!`

Run: `cd frontend && flutter test`
Expected: all suites PASS.

- [ ] **Step 4: Commit**

```bash
git add frontend/pubspec.yaml CLAUDE.md
git commit -m "chore(composer): bump 0.0.18 -> 0.0.19; document iOS WebKit focus guard

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

- [ ] **Step 5: Manual iPhone QA (required — cannot be automated)**

On a real iPhone, in **both Safari and Chrome** (both WebKit), against the running app:
1. Type a message → tap the in-app send arrow → **keyboard stays up**; send several messages without re-tapping the field. **(Primary fix.)**
2. **First, confirm the on-device risk:** the message actually **sends** after the tap (proves `preventDefault` didn't swallow it). If send does NOT fire, drop the `mousedown` listener in `web_focus_guard_web.dart` (keep `touchstart` only) and retest.
3. No black-void "jump" appears at any point.
4. Tapping the message list, or leaving the chat tab, still dismisses the keyboard (unchanged).
5. Action-panel toggle and the voice-send arrow (after locking a recording) do not dismiss the keyboard while editing.
6. The send arrow is visibly larger/centered and easy to hit; the mic sits in its usual left-nudged spot.
7. Sanity: on Android + desktop web the composer behaves exactly as before.

---

## Self-Review

**Spec coverage:**
- G1 (keyboard stays on text-send) → Tasks 2+4 (listener + `composer_trailing` wrap). ✓
- G2 (jump gone) → consequence of G1; verified in Task 6 manual QA step 3. ✓
- G3 (voice-send + toggle covered) → Task 4 wraps trailing slot (covers voice-send, same slot) + `composer_action_toggle`. ✓
- G4 (centered, larger, full 48×48 target) → Task 5. ✓
- G5 (no effect off iOS WebKit) → stub (Task 1) + `_active` gate in `FocusGuardArea` (Task 3). ✓
- G6 (no new revive layer; existing focus code decisions) → spec §3.5; this plan adds only the DOM guard and does not modify `setComposerFocusRequest` or the `_send()` refocus. ✓
- Spec §3.1 `touchstart`+`mousedown`, not `pointerdown`; `passive:false` → Task 2. ✓
- Spec §3.3 one-post-frame-per-build cadence → Task 3 (`_scheduleMeasure`, with explicit "do not re-chain" comment). ✓
- Spec §4 testability limit + `touchstart`-only fallback → Task 2 note + Task 6 step 5.2. ✓

**Placeholder scan:** No TBD/TODO/"handle edge cases"; every code step shows full code. ✓

**Type consistency:** `ensureFocusGuardListenerInstalled()`, `registerFocusGuardRect(String, Rect)`, `unregisterFocusGuardRect(String)` identical across stub, facade, web impl, and `FocusGuardArea`. Test seam `setFocusGuardHooksForTest`/`resetFocusGuardHooksForTest` match the facade. Ids `composer_trailing` / `composer_action_toggle` consistent between Task 4 and CLAUDE.md. ✓
