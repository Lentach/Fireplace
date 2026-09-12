# Composer no longer drops on focus — the ergonomic bottom buffer is resting clearance, not keyboard state

**Date:** 2026-09-12 · **Version:** 0.2.40 → 0.2.41 · **Tiers deployed:** none (web deploy owed)

## What was done
- `chat_input_bar.dart` `build()`: `keyboardVisible` (drives `bottomInteractivePadding`) no longer folds in `_focusNode.hasFocus` — it is now `viewInsets.bottom > 0 || sharedInset > 0`. Focus alone can no longer collapse the buffer, so the bar cannot travel down on a tap.
- Removed the now-dead `_onComposerFocusChangedRebuild` listener (`initState`, `dispose`) — nothing else in `build` reads focus.
- Owner report (screenshots, desktop web + phone): tapping the composer moved the input row DOWN and out of view. Cause was H1 from 0.0.99: the buffer is the composer's RESTING clearance (home indicator, and inside `MainShell`'s `extendBody: true` Scaffold the bottom nav height arrives as `MediaQuery.padding.bottom`), so collapsing it on focus shrank the bar with nothing lifting it — on desktop web no soft keyboard ever arrives, so the row simply parked behind the bottom nav.
- H1's original concern (buffer resizing an OPEN action panel mid-keyboard-animation) is now bounded to the frame where a real inset appears — the same frame `ChatComposerViewport` lifts the composer to `bottom: effectiveInset`.
- Doc + trap: new first-class bullet in `frontend/docs/composer-media.md`, one line under `## Composer / attachments / media` in `docs/agents/traps.md`.
- Rewrote the H1 test into the inverse contract: `composer focus leaves the bar geometry untouched` (ChatInputBar height must not change on focus).

## Key files
- Edited: `frontend/lib/widgets/input/chat_input_bar.dart`, `frontend/test/widgets/input/chat_input_bar_send_test.dart`, `frontend/docs/composer-media.md`, `docs/agents/traps.md`, `frontend/pubspec.yaml` (0.2.41).
- New: none (throwaway probe `test/tmp_composer_nav_probe_test.dart` written, run, deleted).
- Read only (load-bearing): `widgets/input/chat_composer_viewport.dart`, `utils/keyboard_inset_math.dart`, `utils/web_keyboard_inset_web.dart`, `screens/main_shell.dart` (`extendBody: true` + `bottomNavigationBar`), `screens/conversations_screen.dart` `_buildDesktopLayout`, `screens/chat_detail_screen.dart` (embedded vs non-embedded body).

## Verification
- Throwaway probe reproducing the owner's desktop geometry (ChatInputBar in a `Scaffold(extendBody: true, bottomNavigationBar: 56px)`, screen 600dp, nav top 544): PRE-FIX the input row bottom went 519 → 591 on focus (delta **+72 px**, i.e. 47 px below the nav top = buried); POST-FIX 519 → 519 (delta 0, stays 25 px above the nav). Probe deleted after the run.
- Kept regression `composer focus leaves the bar geometry untouched`: RED on stashed pre-fix `chat_input_bar.dart` (height assertion, line 468), green after.
- `flutter test test/widgets/input` → 102 passed, incl. the untouched `a raised web keyboard inset removes the ergonomic bottom buffer` (a real inset still collapses it).
- `cd frontend && flutter test` → **2109 passed, 14 skipped** (matches root `CLAUDE.md` §3, no count file to update).
- `flutter analyze --no-fatal-infos` → 3173 issues, ALL `info`, all from the concurrent `very_good_analysis` adoption (commit 3874af1); zero `error -`/`warning -` lines. Nothing new from this change.
- NOT verified: real iOS PWA and Android PWA devices, and prod. No browser drive (no live backend/login this session); the geometry proof is the widget-level probe above, which goes through the real `Scaffold` `extendBody` plumbing that injects the nav height into `MediaQuery.padding.bottom`.

## Notes for next session
- **Owner owes the web deploy** for 0.2.41 (`git pull ; .\deploy-web.ps1` from the PC, CI green first via `gh api repos/Lentach/Fireplace/commits/master/check-runs`), then a phone check: tap the composer — the bar must not move, and the keyboard must still lift it with no dead strip underneath.
- Watch for H1's original symptom returning in ONE narrow case: action panel open + keyboard rising on iOS (the shared inset flips past the 80 px noise floor mid-pan, so the panel relayouts once there). If the owner reports a flash there, fix it by holding the panel's padding while an inset transition is in flight — do NOT re-add focus to `keyboardVisible`.
- Traps appended: composer focus must never move the bar.
