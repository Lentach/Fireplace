# iOS PWA Composer Keyboard — Focus "Flash" — Fresh-Agent Handoff Brief

**Status:** UNSOLVED (one residual bug). The persistent jump is fixed; a brief (<1s)
flash on keyboard-open remains and **must be eliminated for production.**
**Branch:** `review/frontend-prod-readiness` (current tip ~`457c339`, app `0.0.69`).
**Platform:** iOS Safari/Chrome **standalone PWA** AND plain Safari/Chrome tab. NOT Android.
**Scope:** chat composer keyboard/focus/viewport ONLY. The E2E send path is a hard
trust boundary — do not touch it.

---

## 1. The exact bug to kill

When the user taps the chat composer ("Type a message…") on iOS:
1. The keyboard animates in.
2. For **<1 second**, the whole page visibly **jumps/flips** — the AppBar ("goonboy")
   scrolls off the top, a white/blank band fills the upper half, content is shoved down.
3. It then **snaps back** to the correct layout (composer above keyboard, AppBar visible).

The **end state is correct**; the **transient flash is the bug.** It's fast and hard to
film, but clearly visible to the eye on every focus. User verdict: not acceptable in prod.

---

## 2. Root cause — CONFIRMED on device

- On an iOS standalone PWA, the keyboard **shrinks `window.innerHeight`** to the
  above-keyboard height (captured `iH == vvH == 394` in PWA; `341` in a tab).
- Flutter web's **hidden editing `<textarea>`** (the real focused element that drives the
  native keyboard/IME — probe shows `act=TEXTAREA`) is parked at the **bottom of the
  Flutter scene (~797px)**, *below the fold*, **independent of where the painted composer
  is positioned**.
- On focus, **iOS scrolls the document (`documentElement.scrollTop`) AND pans the visual
  viewport (`visualViewport.offsetTop`) by the keyboard height (~403px)** to bring that
  below-fold `<textarea>` into view. That scroll/pan is what shoves the AppBar off-screen.
- Captured invariant on every focus: **`sT == sY == vvOff`** (all ~403 PWA / 328 tab) and
  **`iH == vvH`** (both shrink). i.e. document-scroll and visual-pan move together by the
  keyboard height.

**Why the current mitigation can't fully kill it:** iOS does that scroll/pan on the **GPU
compositor thread** during the keyboard animation. Our fix (the "pin", §4b) counters it
from **JavaScript on the main thread — always ≥1 frame behind the compositor**, so it can
only **reset** the jump after it happens, never **prevent** it. That reset *is* the
"snaps back" you see; the gap before it = the flash. **You cannot cancel a
compositor-driven viewport pan from JS without lag.** The only way to remove the flash is
to remove the *cause*: stop iOS from needing to scroll/pan = make the focused editing
element **not** below the fold (or hide the transient — see §6).

---

## 3. What's been tried — DO NOT REPEAT (chronological, with results)

| Ver | Attempt | Result |
|---|---|---|
| 0.0.64 | **`onTapOutside: (_) {}`** on the composer `TextField` | ✅ Fixed a *different* bug (in-app Send button bounced the keyboard). Keep it. |
| 0.0.67 | **Keyboard-inset formula fix** (`web_keyboard_inset_web.dart`): `inset = fullLayoutHeight − vv.height`, lifting the **painted** composer above the keyboard | ❌ **No effect on the jump.** `PEAK scroll/vvOff` unchanged — iOS scrolls to the *editing* element (scene bottom), not the painted composer. Kept (harmless, lifts the painted composer into the pin's clip so it stays visible). |
| 0.0.68 | **Viewport pin** (`web_ios_viewport_pin_web.dart`): on focus, `position:fixed` on `<body>`+`<flutter-view>` + clip to `vv.height` + zero scroll, reconciled reactively on `visualViewport` `resize`/`scroll`, exact inline-style restore on blur | ⚠️ **Fixed the *persistent* jump** (settled state now `sT=0 vvOff=0`, correct), but the **transient flash remains** (`PEAK` still 403, reset to 0 after). |
| 0.0.69 | **Pre-arm the pin on pointer-DOWN** (`Listener(onPointerDown:)` wrapping the field → arm before focus/keyboard) + 700ms safety disarm | ❌ **No change to the flash** (`PEAK scroll=403` still). The pin's *reset* is still reactive (runs after iOS's compositor scroll/pan); arming earlier doesn't help because the problem is the reactive counter, not the arm timing. |

**Also tried earlier and REMOVED / REJECTED (do not revisit):**
- **Dual-space focus-guard coordinate fix** (a wrong hypothesis for the send-bounce) — removed in `e90779f`.
- **The BANNED "global scroll-lock"** — commit `21d98d7` added an always-on
  `<style> html,body{overflow:hidden} </style>` in `index.html`. It broke things and was
  reverted (`c1adde0`). **Do NOT reintroduce a global/always-on host lock.** (A *scoped*,
  iOS-only, focus-only, reverted-on-blur lock is fine — that's what the pin is.)
- **`interactive-widget` meta** — iOS WebKit does **not** support it; changing it only
  affects Android (and Android is currently fine). Don't touch it for an iOS fix.

---

## 4. Current code state (files + roles)

All under `frontend/lib/`. Conditional-import triples are `x.dart` (facade) +
`x_stub.dart` (VM/no-op) + `x_web.dart` (real, `if (dart.library.html)`).

- **`utils/web_ios_viewport_pin{,_web,_stub}.dart`** — THE PIN. `setIOSComposerViewportPin(bool)`.
  While active: snapshots inline styles of `<html>` (clip-only), `<body>` + `<flutter-view>`
  (`position:fixed`, `top=vv.offsetTop`, `left=vv.offsetLeft`, `width=vv.width`,
  `height=vv.height`, `overflow:hidden`), zeroes `documentElement`/`body` scroll, reconciles
  on `visualViewport` `resize`/`scroll`; restores exact styles on deactivate. iOS-gated.
- **`utils/web_keyboard_inset{,_web,_stub}.dart`** — iOS-only keyboard-inset source.
  `inset = fullLayoutHeight − vv.height` (fullLayoutHeight = running max of `innerHeight`,
  `documentElement.clientHeight`, `vv.height+vv.offsetTop`; reset on width/orientation
  change). Drives the composer's `Positioned(bottom:)`.
- **`widgets/input/chat_composer_viewport.dart`** — `Stack[ Positioned.fill(messageList),
  Positioned(bottom: keyboardInset, composer) ]`; `Scaffold(resizeToAvoidBottomInset:false)`
  upstream. 450ms collapse debounce gated on `composerKeyboardCollapseGuard`. **Installs the
  temp `jump_probe` in initState / removes in dispose.**
- **`widgets/input/chat_input_bar.dart`** — the composer. The `TextField` is wrapped:
  `Listener(behavior: translucent, onPointerDown: _preArmComposerViewportPin) → ConstrainedBox
  → TextField`. `onTapOutside: (_) {}`. `_onComposerFocusForWebViewport` (FocusNode listener)
  arms/disarms the pin on focus/blur. `_preArmComposerViewportPin` pre-arms on pointer-down +
  700ms safety timer. Dispose cleans up timers + pin.
- **`utils/jump_probe{,_web,_stub}.dart`** — **TEMP diagnostic.** A DOM `<div>` pinned to the
  visual viewport (so it stays readable during the jump) showing live
  `sT bT sY vvOff vvH iH act` + `PEAK scroll vvOff`. iOS-only. **Remove when the fix lands.**
- **`utils/web_viewport_scroll{,_web,_stub}.dart`** — `resetWebDocumentScroll()` (still used by
  `_toggleActionPanel`/`_onMicTap`). `setIOSWebViewportScrollLocked` was removed (cutover; pin
  subsumed it).
- **`utils/web_ios_webkit_web.dart`** — `isIOSWebKit()` gate (UA sniff; incl. iPadOS).
- **`utils/web_focus_guard{,_web,_stub}.dart` + `widgets/input/focus_guard_area.dart`** —
  pre-existing DOM focus guard (capture-phase `touchstart`/`mousedown` `preventDefault` on
  registered control rects + touchend refocus). Retained; **not** the lever for this bug.
- **`web/index.html`** — viewport meta `interactive-widget=overlays-content` (no-op on iOS).

---

## 5. Probe / how to read the live state on device

`jump_probe` shows (top of screen, pinned to the visual viewport):
```
JUMP  sT=.. bT=.. sY=..  vvOff=.. vvH=.. iH=.. act=..
PEAK  scroll=..  vvOff=..
```
- `sT/bT/sY` = `documentElement.scrollTop` / `body.scrollTop` / `window.scrollY`.
- `vvOff` = `visualViewport.offsetTop`; `vvH/iH` = `visualViewport.height`/`window.innerHeight`.
- `act` = `document.activeElement.tagName`.
- **`PEAK` persists** (max seen) — read it *after* the flash settles; no need to film the flash.

There's also `widgets/input/composer_diagnostics_overlay.dart` (toggle: long-press the chat
app-bar title) showing `mqH/mqW/dpr` + the probe + (iOS) a focus-guard event log.

**Captured numbers (evidence):**
- PWA pre-pin (0.0.66): `sT=403 vvOff=403 iH=394 vvH=394`, `PEAK 403/403`.
- PWA post-pin settled (0.0.68/69): `sT=0 vvOff=0 iH=797 vvH=394`, `PEAK scroll=403 vvOff=403`.
- Chrome tab (0.0.67): `sT=328 sY=328 vvOff=328 iH=341 vvH=341`, `PEAK 328/328`.

---

## 6. Candidate approaches for the fresh agent (none tried unless noted)

Ranked roughly by promise/risk. The agent should evaluate, prototype, and device-test.

**A. Cosmetic mask over the transient (RECOMMENDED FIRST — lowest risk, sidesteps the
compositor-lag entirely).** On focus (or pointer-down), overlay a **solid app-background-
colored `<div>`** (or a static composer mock), `position:fixed`, high z-index, covering the
content area, pinned to the visual viewport, for the ~300–450ms of the keyboard animation;
fade it out once the pin has settled (`vvOff` back to 0). The jump still happens
*underneath* but is invisible. A solid-color cover doesn't need frame-perfect tracking
(unlike countering the pan), so the compositor lag stops mattering. Does NOT touch Flutter
internals or text input. Risks: getting the mask's coverage/timing right; must not cover the
keyboard or block typing; must reveal instantly when settled. **This is the most likely
clean win.**

**B. Stop the cause — reposition Flutter's hidden editing `<textarea>` into the visible
area (HIGHEST potential, HIGHEST risk).** If the editing element isn't below the fold, iOS
has nothing to scroll/pan to → no jump at all. `document.activeElement` is the `<textarea>`.
Investigate overriding its CSS (`top`/`transform`/`position`) on focus and holding it (re-apply
on Flutter's mutations / each frame). Risks: breaks IME/caret/autofill/selection, Flutter
re-syncs it every keystroke, fragile across Flutter upgrades. Prototype carefully; test
typing, caret, autocorrect, paste, multi-line growth.

**C. Investigate WHY/WHERE Flutter parks the editing element + whether the renderer matters.**
The prod bundle ships `canvaskit` + `skwasm` + `wimp` wasm (Flutter auto-selects). The
text-input host element's position may differ per renderer / Flutter version. Read the
Flutter web engine text-input code (`flutter/engine` `lib/web_ui/.../text_editing/`), check
open issues (flutter/flutter keyboard/iOS/text-input + the ones in §9), and see if there's a
supported `TextInputType`/strategy/config or a `flutter-view` text-editing host setting that
places the element sensibly.

**D. `position:fixed` on `<html>` too (the pin currently clips `<html>` but doesn't fix it —
oracle called root `position:fixed` "fragile").** Might prevent the *document-scroll*
component (`sT`) outright. Won't fix the *pan* (`vvOff`) — so partial at best, and risky.
Lower value than A/B.

**E. Pre-empt iOS: synchronous `scrollIntoView`/`scrollTo(0,0)` + CSS `scroll-margin`/
`scroll-padding` on focus**, or a one-frame `requestAnimationFrame` loop pinning during the
animation. Note: a naive `scrollTop=0` reset alone HIDES the composer (it's bottom-anchored);
must be combined with the inset/pin. Likely same compositor-lag wall.

**F. Reconsider the layout so the editing element's natural bottom position IS the visible
composer** (the message list is already a `reverse: true` ListView). Architectural; investigate
whether the composer can be the literal scene-bottom element so "scroll to bottom" = "show
composer above keyboard" with no net jump.

---

## 7. Hard constraints (MUST hold)

- **Never reintroduce the banned global scroll-lock** (always-on `<style>` `overflow:hidden`
  in `index.html`, commit `21d98d7`). Scoped/iOS-only/focus-only/reverted-on-blur is OK.
- **Never regress Android Chrome PWA** (white-void was just fixed; keyboard works there).
  Gate everything iOS-specific behind `isIOSWebKit()`. No `index.html` meta / global-CSS change
  that affects Android.
- **Never touch the E2E send path** (`MessagingProvider.sendMessage` / `_encryptAndSend`).
  Widget/web-layer only.
- **Don't break** the already-fixed behaviors: `onTapOutside` send-bounce fix (0.0.64),
  `composerKeyboardCollapseGuard` hide-debounce (0.0.64), portrait `keyboardVisible` guard
  (0.0.63), text input/IME/autofill/caret/multiline, voice recording, image paste.
- Keep it scoped, reverted-on-blur, and analyze-clean. Don't ship the temp `jump_probe` /
  `composer_diagnostics_overlay` to prod once resolved.

---

## 8. Build / deploy / verify (frontend is built on the PC — the 2 GB VM can't compile)

```powershell
cd C:\Users\Lentach\Desktop\Fireplace ; git pull ; .\deploy-web.ps1   # build on PC → atomic-swap into VM frontend-build/
```
- Verify `/version.json` (frontend semver) and the **Settings footer** (`semver · shortSha`).
- **PWA cache is sticky on iOS**: close+reopen the PWA *twice*, or load in a private Safari
  tab, to be sure you're testing the new bundle (not the cached one). Never uninstall (wipes
  E2E keys).
- Bump `frontend/pubspec.yaml` semver (+1 patch) per build so you can tell builds apart.
- Branch `review/frontend-prod-readiness`; commit + push; do NOT merge to `master` without the
  user's OK.

---

## 9. Reference (Flutter-web keyboard/viewport issues; iOS visualViewport)

- flutter/flutter #179208 — white space after keyboard dismissal (Android web).
- flutter/flutter #178431 — keyboard dismissal doesn't restore viewport height.
- flutter/flutter #50382 — app doesn't reclaim space when keyboard dismissed.
- MDN VisualViewport API; Chrome `interactive-widget` (Android-only).
- Search Flutter engine `text_editing` host-element positioning on iOS; flutter/flutter issues
  for "iOS keyboard scroll input into view" / "visualViewport" / "text field position web".

---

## 10. Suggested first moves

1. Reproduce; read `PEAK` off the probe (no need to film). Confirm `act=TEXTAREA` and that
   `PEAK scroll/vvOff ≈ keyboard height`.
2. If a Mac is available: Safari Web Inspector → inspect `document.activeElement`'s bounding
   rect during focus → confirm the editing `<textarea>` sits at the scene bottom (the cause).
3. **Prototype approach A (cosmetic mask)** first — most likely clean, lowest risk.
4. In parallel, investigate approach B/C (editing-element position) for a true root-cause fix;
   only ship if typing/IME survive device testing.
5. Keep the pin (it fixed the persistent jump) unless a cleaner mechanism fully replaces it.

---

## 11. Session commit trail (this subsystem)

`811d2cd` 0.0.63 (A2 portrait guard + B hide-debounce + first C attempt + A1 diag) →
`cb31dbc` 0.0.64 (C real fix: `onTapOutside`) →
`e90779f` 0.0.65 (cleanup: removed wrong dual-space fix + spent A1 diag) →
`238c06b` 0.0.66 (added `jump_probe`) →
`49c0f9c` 0.0.67 (keyboard-inset fix — insufficient alone) →
`0c488f2` 0.0.68 (viewport **pin** — fixed persistent jump, flash remains) →
`457c339` 0.0.69 (pin **pre-arm** on pointer-down — flash unchanged).

The full audit + prior findings: `docs/review/composer-keyboard-audit.md`, and frontend
gotchas in `frontend/CLAUDE.md` §1 + §6 (the iOS PWA composer notes).
