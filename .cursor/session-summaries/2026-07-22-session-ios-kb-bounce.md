# 2026-07-22 — Landing: iOS keyboard bounce after journey "DONE" (fireplaceWebsite)

## Problem
On iOS Safari, tapping the journey DONE pill dismissed the keyboard but it immediately bounced back; user could not dismiss it at all. Android fine.

## Diagnosis (layered)
1. Dismiss runs on **pointerdown** (`journey.ts` document capture listener) → pill hides, phone unfreezes/reflows.
2. At touchend iOS synthesizes a click that hit-tests FRESH coordinates → lands on the reflowed textarea → refocus → keyboard reopens.
3. The existing 600ms `kbSuppressUntil` guard called `el.blur()` synchronously inside focus dispatch — iOS ignores that.
4. Even with the synthesized click cancelled, iOS still restored focus after the keyboard-hide animation (owner re-test) — needed a hard stop.

## Fixes (`fireplaceWebsite` commits `52c74e1`, `9dc31db`, `ef42561` — all deployed, live bundle `BBgyupuP`)
- Suppress-window blur deferred via `setTimeout(0)` (iOS ignores sync blur in focus dispatch).
- One-shot `kbSwallowTap` flag: armed on the dismiss pointerdown (touch only), the gesture's own touchend gets `preventDefault()` → synthesized click never fires. Disarmed on `touchcancel` (scroll-turned gesture must not eat the next tap). NOTE: gating touchend on target `.closest('.compose')` does NOT work — touch events keep the touchSTART target for the whole gesture; only the synthesized click retargets.
- **Readonly hammer (the decisive fix)**: `releaseKb()` sets both composer textareas `readOnly = true` for 700ms (only when a kb-lift was actually active, so desktop sends are untouched) — iOS never opens a keyboard for a readonly field, so any refocus during the window hits a wall.

## Verification
- Each step deployed via `deploy-landing.ps1`, live bundle grepped for the new code (`touchcancel`, `readOnly` present).
- Owner iPhone re-test after step 2 still bounced → step 3 shipped; awaiting owner confirmation on the readonly hammer.

## Notes
- Hero `.enc-done` (encrypt.ts) has a similar but inline dismiss; not touched (change only what was asked; separate offer still pending owner yes/no re: coarse-pointer gate at `landing.css:127`).

## UPDATE — real culprit found (`ecdda29`, live bundle `DekN37sV`)
All three earlier fixes went into the JOURNEY pill — but the owner was hitting the **HERO** Done (`.enc-done`, `encrypt.ts`), which had the identical bug and NONE of the fixes. Mechanism: Done pointerdown → blur → pill hides (`:focus-within`) → iOS synthesizes the tap's click with a FRESH hit-test → lands on the textarea → **native** refocus (the `doneAt<500ms` guard only blocks the programmatic `input.focus()` in the port click handler — it cannot stop native click-focus). Desktop Chromium can't reproduce: Blink cancels compat mouse events on pointerdown-preventDefault; WebKit doesn't — hence iOS-physical-only.
Fix in `encrypt.ts` Done pointerdown (touch only): one-shot capture `touchend` preventDefault (kills the synthesized click; disarmed on touchcancel) + `input.readOnly = true` for 700ms (keyboard physically cannot reopen). Chromium smoke: readOnly toggles true→false, no refocus after Done, normal tap afterwards refocuses fine.
Also shipped `?kbdebug` on-page tracer (`main.ts`): fixed overlay logging focusin/focusout/pointerdown/touchend/touchcancel targets + visualViewport height — for on-device diagnosis if anything still bounces (no Mac/Web Inspector available). URL: `https://fireplace.ignorelist.com/welcome/?kbdebug`.

## RESOLVED + cleanup (`4a158c8`, live bundle `RXVEr5wJ`)
Hero fix **confirmed working on the physical iPhone**. Cleanup: removed the `?kbdebug` tracer (diagnostic scaffolding). Journey-side swallow + readonly hammer KEPT deliberately — the journey pill has the identical WebKit hole (pointerdown dismiss → reflow → synthesized click → native refocus); they are the same pattern as the proven hero fix, not dead layers. Live grep: `kbdebug`=0, `readOnly`=2 (hero + journey) in `RXVEr5wJ`.

## Follow-up shipped (`ed0b003`, live CSS `DBMb6rVT`)
Hero `.enc-done` width-gate aligned with the journey pill: `landing.css` `@media (max-width: 999px)` → `and (pointer: coarse)`. Browser-verified live: 818px fine-pointer + focused → `display:none`; 390px coarse (mobile emulation) + focused → shown.
