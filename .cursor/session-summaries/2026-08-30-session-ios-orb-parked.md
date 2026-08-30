# 2026-08-30 — iOS orb/flash: mechanism exonerated by 9-variant device probe; canvas-hide experiment failed; ALL composer work reverted from prod and PR #151 PARKED (draft) until MacBook + Web Inspector

**Date:** 2026-08-30

## Outcome

Owner order after the last failed experiment: *"revert all changes … we are going
blind … let's leave this to the point I got a MacBook and you can examine it for
yourself."* Executed: prod redeployed from clean master (`0.1.20 · cec96f1`,
smoke rc=0), PR #151 converted to DRAFT with a full status comment, branch
`fix/composer-regression` (head `5381315`, includes the Umbra merge-up) left
intact for the future session.

## What three iPhone passes established (do NOT re-derive)

Probe page technique: static page at `frontend-build/probe/` (auto-wiped by any
deploy; masters in main-checkout `local/probe-ios/`), Added-to-Home-Screen for
standalone mode. Result matrix, all in the SAME standalone shell where the app
reproduces the bug, same phone, same session:

- **CLEAN (no orb, no flash), all nine variants:** direct finger-tap on invisible
  input; the fix's exact mechanism (synthetic click, container+input each
  opacity 0.01 → compounded ~0.0001, pointer-events:none on both); synthetic
  click on fully visible input; direct tap on opacity-1 input; input occluded by
  an opaque full-screen layer; anchor rect ×3 (off-screen); click deferred
  120 ms; main thread blocked 400 ms during presentation; click fired from a raw
  `pointerup` handler (Flutter's event type).
- **BUG (full-screen dark sheet morph + lingering orb):** the real Flutter app —
  identically on OLD code (file_picker) and on the branch's anchored input
  (same-session A/B, prod redeploys `371293c`→master→`aba224b`).
- **Chrome iOS tab + Safari tab: app is CLEAN.** The bug needs BOTH the Flutter
  app AND the standalone shell.
- **Canvas-hide experiment (`5381315`): FAILED.** Hiding
  `flutter-view`/`flt-glass-pane` during presentation did not remove the orb;
  it only made the app background visibly disappear behind the menu. The
  simple canvas-snapshot theory is dead.
- **New owner observation:** tapping the attachment icon also DISMISSES the
  lower action panel (composer tile row) — record for the next investigation.

## Standing conclusions

- The input-opening mechanism (file_picker's detached display:none input vs the
  branch's rendered anchored input) is EXONERATED for the orb — do not iterate
  on it again. The 08-21 root-cause claim "orb = degenerate detached anchor" is
  DISPROVEN by the A/B (same orb with the rendered attached anchor).
- The remaining delta is something the full Flutter app does in the standalone
  shell that a bare page cannot simulate. Next step REQUIRES macOS Safari Web
  Inspector attached to the installed PWA. No further blind iterations —
  three device passes and one shipped experiment is the cost cap already paid.
- Still true and verified (emulator end-to-end + instrumented): Android
  three-door sheet, composer-sag fix, freeze-reload pick protection. Owner
  approved the Android UX before the final frustration; if wanted, they can be
  split from the iOS work into their own PR.

## State at close

- **Prod:** master `0.1.20 · cec96f1`, smoke rc=0, backend 0.1.20/be7c0956.
  Nothing of the composer work is live. Probe page auto-wiped.
- **PR #151:** DRAFT (parked), branch head `5381315` = fix + Umbra merge-up +
  failed experiment commit. CI was 6/6 green at `aba224b`; the experiment
  commit did not run the suite (analyze clean only).
- **Main checkout:** clean on master. Worktree `fireplace-composer` on the
  branch. Owner's fp-probe home-screen icons are dead links now (harmless;
  advised to leave, not delete — same-origin deletion risk to PWA keys).
- **Owner owes when hardware exists:** MacBook + Safari → Web Inspector on the
  installed PWA → reproduce one paperclip tap → inspect the presented sheet.
