# Composer no longer drops on focus — the ergonomic bottom buffer is resting clearance, not keyboard state

**Date:** 2026-09-12 · **Version:** 0.2.40 → 0.2.41 · **Tiers deployed:** web (`0.2.41 / 9d13d25`, smoke PASSED)

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
- **LIVE BROWSER A/B (owner asked for it; local dev stack, Chrome, `flutter run -d web-server` on 127.0.0.1:8097, backend `docker-compose` :3000, two seeded users `uiprobe_a1`/`uiprobe_b1` + a conversation row in the dev DB).** Desktop split layout at 1500x980: focused DOM `TEXTAREA` rect (Flutter web's real editing host) `top` = **936.5 pre-fix vs 834.5 post-fix**, `innerHeight` 980 → the pre-fix row sits INSIDE the bottom-nav band; the pre-fix screenshot reproduces the owner's img 4 exactly (only the mic glyph peeking over the nav, chat content shifted down), post-fix frames before/after focus are pixel-identical. Compact/touch at 412x915 (non-embedded route, `ChatComposerViewport`): focused rect `top` 855.5 of 915, frames identical before/after focus — no drop, buffer retained. Pre-fix build was the true parent file (`git checkout 3874af1 -- …`), not a hand-reverted predicate, so the deleted `_onComposerFocusChangedRebuild` listener was present.
- **INCIDENT: `eec7d98` (a concurrent session's docs commit) swept the temporarily reverted `chat_input_bar.dart` onto master**, un-shipping the fix for ~20 min; restored verbatim from `8ec7dff` in `a3efb73` and re-verified live after the restore (same 834.5 rect). Never leave a tracked file reverted in this shared worktree.
- **DEPLOYED (web only, this session):** `.\deploy-web.ps1` → `PUBLISHED_OK`, exit 0, no Kaspersky exit-21. `/version.json` = `0.2.41 / 9d13d25`, `/version` = `0.2.41 / 49c77c10`, `/health` = `{"status":"ok","db":"ok"}`. `post-deploy-smoke.mjs` **SMOKE PASSED** 5/5 including the stale-build gate (served `main.dart.js` literally contains `9d13d25`) and a headless app boot. Code gate: `a3efb73` CI run 34710950813 green 6/6; head `9d13d25` is docs-only, so only `Analyze` reports on it.
- NOT verified: real iOS PWA and Android PWA devices (no real soft keyboard in headless Chrome — the keyboard-up half of the contract still rests on the widget test), and no behavioural drive against PROD (no prod account; would mean registering on the live DB).

## Notes for next session
- **Owner's remaining check:** fully close + reopen the PWA (never uninstall / clear site data), Settings footer must read `0.2.41 · 9d13d25`, then tap the composer on the phone — the bar must not move, and the keyboard must still lift it with no dead strip underneath.
- Watch for H1's original symptom returning in ONE narrow case: action panel open + keyboard rising on iOS (the shared inset flips past the 80 px noise floor mid-pan, so the panel relayouts once there). If the owner reports a flash there, fix it by holding the panel's padding while an inset transition is in flight — do NOT re-add focus to `keyboardVisible`.
- Traps appended: composer focus must never move the bar.
