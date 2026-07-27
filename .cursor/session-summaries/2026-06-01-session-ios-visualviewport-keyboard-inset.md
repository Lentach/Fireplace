# iOS composer floats — root-caused via on-screen diagnostics, fixed with visualViewport inset

**Date:** 2026-06-01

## What was done

### The bug (kept being mis-diagnosed)
On iOS WebKit PWA, toggling the action panel with the keyboard up left the composer floating mid-screen / sitting under the keyboard. Previous sessions guessed at focus-guard misses, a racy `hadComposerFocus` branch, and document scroll — none fixed it.

### Diagnostics that finally exposed it
- Added an on-screen `ComposerDiagnosticsOverlay` (top-left green readout) + `web_diag_probe` (later replaced) — user couldn't see it at first because of a bad/cached build, then a clean build revealed the numbers.
- Also added an off-screen `ComposerDiagLog` ring buffer viewable via **triple-tap** the Privacy & Safety shield (long-press still = E2E log).

**On-device readout at bug time:** `viewInsets.bottom: 0`, `active: TEXTAREA`, `vv.offTop: 0`, `vv.h: 394`, `scrollY/doc.top: 0`, `innerH: 797`.

### Root cause (definitive)
iOS WebKit shrinks the **visual** viewport for the keyboard but NOT the **layout** viewport, so `MediaQuery.viewInsets.bottom` reads **0 while the keyboard is up**. Keyboard height = `innerH − vv.h − vv.offTop = 797 − 394 = 403px` that Flutter never saw. Composer is `Positioned(bottom: viewInsets=0)` → under the keyboard. `active: TEXTAREA` + all-zero scroll values ruled out the focus-guard / blur / scroll theories.

### Fix
- `utils/web_keyboard_inset.dart` (+ `_stub`/`_web`): `KeyboardInsetSource` listens to `window.visualViewport` `resize`+`scroll`, exposes `inset = max(0, innerHeight − visualViewport.height − visualViewport.offsetTop)` (threshold 80px). `isActive` only on iOS WebKit.
- `ChatComposerViewport` owns one, rebuilds via its `ValueListenable` listener (Flutter won't rebuild — never sees the inset), uses `raw = isActive ? max(flutterInset, vvInset) : flutterInset` into the existing 450ms collapse debounce.
- Off iOS web / native: inactive → falls back to `MediaQuery.viewInsets.bottom`, no behaviour change.
- Re-added `ComposerDiagnosticsOverlay` (now shows `kbInset(vv)` vs Flutter `viewInsets`) for on-device verification.

## Key files
- `frontend/lib/utils/web_keyboard_inset.dart`, `web_keyboard_inset_stub.dart`, `web_keyboard_inset_web.dart`
- `frontend/lib/widgets/input/chat_composer_viewport.dart` (visualViewport inset wired in)
- `frontend/lib/widgets/input/composer_diagnostics_overlay.dart` (verification overlay)
- `frontend/lib/utils/composer_diag_log.dart`, `composer_probe*.dart` (triple-tap log)
- `frontend/lib/screens/privacy_safety_screen.dart` (triple-tap shield → composer log)
- `frontend/pubspec.yaml` (0.0.26 → 0.0.27), `CLAUDE.md`

## Verification
- `flutter analyze` (changed files) → No issues found
- `flutter test` (viewport / composer / pinned-banner) → all passed
- **Physical iPhone 14: CONFIRMED FIXED** — action-panel-with-keyboard bug gone (v0.0.27).

## Post-fix cleanup (v0.0.28 → v0.0.29)
- Removed `ComposerDiagLog` ring buffer + the triple-tap Privacy&Safety panel + all `ComposerDiagLog.add` calls (v0.0.28, commit 7f1b0b7).
- Kept `ComposerDiagnosticsOverlay` as a dev testing tool but **gated it behind a runtime toggle** — off by default (`composerDiagOverlayEnabled`), **long-press the chat app-bar title** to show/hide (`toggleComposerDiagOverlay()`), iOS-WebKit only (v0.0.29, commit da48c74).
- Kept (user decision) the `_toggleActionPanel` keyboard-**on** branch as a harmless safety net. Analyzer found no statically-dead code elsewhere; remaining iOS keyboard workarounds (focus guard, host-scroll lock, send-bounce restore, 450ms debounce, open-from-hidden branch) are each still load-bearing and device-validated — do NOT remove without iPhone re-test.

## Notes for next session
- **Current prod-worthy state: v0.0.29 (commit da48c74).** Deploy: `./deploy.sh` + `cp -a frontend/build/web/. frontend-build/`. `/version` `gitCommit` distinguishes builds (version strings were reused after a revert).
- **Diag overlay is a kept dev tool:** long-press the chat app-bar title (iOS WebKit) to toggle the green readout. To remove entirely later: delete `composer_diagnostics_overlay.dart` + `composer_probe*` + the title long-press in `chat_detail_screen.dart` + the overlay block in `chat_composer_viewport.dart`. Keep `web_keyboard_inset.dart` (the real fix) forever.
- The real fix is `web_keyboard_inset.dart` (visualViewport-derived inset). Don't regress it back to `MediaQuery.viewInsets.bottom` for the iOS composer.
- Feedback memory: no on-screen diagnostics *by default* — overlay is now off by default (toggle-gated), consistent with that.
