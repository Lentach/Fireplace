# 2026-08-21 — composer/attachment regression: root causes proven, fix built and emulator-verified on branch `fix/composer-regression`

**Date:** 2026-08-21

## What was done

Owner reported four composer symptoms (iOS orb + full-screen black flash on attachment
tap without keyboard; iOS mid-screen menu + keyboard dismissal with keyboard; Android
chooser listing the camera twice with no gallery door; Android "input drops a little"
around the paperclip). Ordered: investigate and PROVE first, then fix, in a fresh
worktree (`C:/Users/Lentach/Desktop/fireplace-composer`, branch `fix/composer-regression`,
pushed, NOT merged).

### Root causes — each with evidence

1. **iOS orb/black flash (no keyboard) — file_picker's anchorless input.**
   file_picker 11.0.2 web styles its `<input type=file>` `display:none` and REMOVES it
   from the DOM in the same synchronous call stack as `.click()`
   (file_picker_web.dart:65-70,175-186 — source-verified; byte-identical in 8.1.6, so
   not a lib regression). Safari's popover then morphs from a degenerate source rect.
   Corroboration: the 08-19 static-page probe got a clean anchored menu from a REAL
   visible input with keyboard down.
2. **iOS mid-screen menu + keyboard dismissal (keyboard up) — Safari-owned**, re-confirmed
   nothing new; 08-19 bare-page proof stands. Not fixable in Dart; do not chase.
3. **Android camera-twice — the dot-extension accept soup** (` .jpg, .jpeg, … .mp4, …`)
   from `FileType.custom`; mixed image+video capability makes Android offer stills-camera
   AND camcorder and no gallery door. Reproduced on the emulator (s27: Camera / Camera
   Camcorder / Media).
4. **Android "input drops a little" — the 0cbf17b keyboard-dismiss slide firing behind
   native surfaces.** Instrumented build + CDP console: `[kbprobe] SLIDE-START from=312.4,
   guard=false` EXACTLY at the paperclip tap (the native dialog's keyboard drop is a full
   one-event inset→0, which is the slide's trigger). The collapse guard cannot cover it:
   the drop arrived 1.6 s after the tap, past any debounce.
5. **Symptom K (keyboard dead after paperclip) did NOT reproduce at HEAD on Android** —
   two clean cycles, keyboard rose after the chooser every time. The 08-19 archaeology
   also proved zero focus-code changes in the video batch. Treat the 08-19 K-repro as
   possibly a mis-tap false positive (their own §7 warns tap coordinates shift).

### The fix (all frontend, wire contracts untouched)

- **`utils/web_file_input{,_stub,_web}.dart` (new):** `pickFileViaAnchoredInput` — a
  RENDERED (opacity .01, pointer-events none) input positioned at the paperclip tile
  rect, clicked synchronously in-gesture, kept ATTACHED until `change`/`cancel`, then
  removed. `cancel` (Chrome 113+/Safari 16.4+) is the only cancellation signal —
  deliberately NO window-focus timeout (on a thaw, `focus` precedes the straggling
  `change` by an unbounded gap and a timer would destroy a real pick). Stale container
  swept on next invocation.
- **`chat_action_tiles.dart`:** paperclip branches — iOS PWA: bare anchored input, full
  dot-extension accept (Safari renders its own 3-row menu); Android PWA: glass sheet
  with three doors — Galeria (`image/*,video/*`), Aparat (`image/*` +
  `capture=environment`), Plik (document extensions) — each door opens the anchored
  input in its own gesture; desktop/native: file_picker unchanged. New ARB keys
  `attachmentOptionGallery/Camera/File`.
- **`composer_keyboard_signals.dart`:** `composerNativePickerActive` (depth-counted
  begin/end, 3-min safety cap so a missed `cancel` can never pin the flag).
  `chat_composer_viewport.dart` suppresses the dismiss slide while it holds (layout
  still collapses immediately — pre-batch behavior for picker-caused drops).
- **`page_lifecycle_web.dart` / `frozen_page_reload_decision.dart` / `main_shell.dart`:**
  the 0.1.19 freeze→reload is SUPPRESSED (soft recovery instead) while the picker span
  holds — the reload was destroying the pending input + picked bytes when a camera/file
  activity froze the page (emulator-proven: camera return cold-booted to the chat list).
  +2 unit tests (suppression + reloadImminent clearing).

## Key files
`frontend/lib/utils/web_file_input_web.dart` (new mechanism),
`frontend/lib/widgets/chat_action_tiles.dart` (doors),
`frontend/lib/widgets/input/composer_keyboard_signals.dart` (span),
`frontend/lib/widgets/input/chat_composer_viewport.dart` (slide gate),
`frontend/lib/utils/frozen_page_reload_decision.dart` (+ test), `main_shell.dart`.
Investigation artifacts: `.planning/composer-regression/findings.md`, `local/inv/*`,
`local/probe/*` (worktree-local, untracked).

## Verification

Phone-free rig per the 08-19 recipe: Pixel_7 emulator + `adb reverse` + local docker
stack (`fpcomposer` project, torn down) + seeded probeA/probeB + IME oracle
(`dumpsys window InputMethod`) + CDP console/DOM probes.

- **Green, on-device:** three-door sheet renders; Gallery door → Android Photo Picker
  directly → picked photo → staged chip (name+size+thumb) → hex-send → **encrypted image
  delivered** (bubble + backend); Camera door → camera app directly (stills, single
  entry); File door → Files app directly (no camera entries); keyboard rises after the
  flow; probe log shows **no SLIDE-START** anywhere in the picker flow (red run had it
  at the tap); DOM probe shows the anchored input created at the tile rect (40×40 CSS at
  the paperclip), correct accept/capture, attached until resolution.
- **Emulator-unverifiable, honestly:** the camera/file RETURN leg — the starved 2 GB
  emulator freezes the page during any full-screen activity and Chrome then CANCELs the
  pending chooser; a BARE static `<input capture>` on a plain HTML page fails identically
  (discriminator), so it is the environment, not our path. The pre-existing file_picker
  path has the same exposure. **Needs one pass on a real Android phone.**
- **Not testable anywhere but an iPhone:** Safari's popover placement/orb with the now
  rendered+attached anchor. Mechanism is source-proven; get a screen recording from the
  owner's device before merging.
- Suite **1330 passed / 10 skipped** (+2; root §3 bumped, verifier green), analyze clean.

## Notes for next session

- **Branch is pushed, NOT merged; no version bump.** Owner must device-test on his
  iPhone (orb + placement with keyboard down) and any Android phone (camera/file door
  return leg) before merge. Never merge on red; check CI on the branch.
- iOS keyboard-up placement (menu mid-screen) and the keyboard collapsing when the menu
  opens are SAFARI behavior (08-19 bare-page proof) — the fix does not claim them.
- The emulator rig degrades after ~2 h (ANR loops, clock drift); reboot it rather than
  fight it, and mind host RAM: Docker Desktop crashed once at 0.8 GB free (Kaspersky
  note from 08-20 unrelated).
- file_picker stays for desktop/native; do NOT swap it web-wide — only the composer
  paperclip uses the anchored input.
