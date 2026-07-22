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
