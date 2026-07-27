# Composer keyboard/viewport review → single inset truth + Android panel-tap fix + flash A/B + dead-weight probes (0.0.92, PR #32)

**Date:** 2026-07-07

## What was done

**Review first (user: "pile of fixes on fixes — tackle it").** 3 parallel audit agents (source map / git+session delta since the 2026-06-24 audit @814c820 / test coverage) + synthesis in `.planning/composer-viewport-review/findings.md`. Verdict: the pile was already pruned (every failed hypothesis deleted/reverted: dual-space guard geometry, pin pre-arm, focus mask, font-16, jump probes, Android inset machinery); the surviving trunk is coherent and each layer defends a commit-documented device bug. **NOT a rewrite candidate.** But three real defects found — all one class: *"is the keyboard visible" had no single source of truth*; `ChatComposerViewport` computed the correct `max(viewInsets, visualViewport)` while three siblings trusted raw `MediaQuery.viewInsets` (reads 0 on iOS WebKit while the keyboard is up).

**Branch `refactor/composer-keyboard-viewport` (0.0.92, PR #32 — https://github.com/Lentach/Fireplace/pull/32), 4 commits:**

1. **Phase A — shared inset truth.** New pure `utils/keyboard_inset_math.dart` (running-max layout height, orientation reset >1px, 80px floor) — first unit coverage of the vv arithmetic. `sharedKeyboardInsetSource()` app-wide singleton (facade, never disposed) + `setSharedKeyboardInsetSourceForTest` seam + `lastKnownKeyboardInset()` persisted to localStorage (`composer_kb_inset_v1`, width-tagged, bounds- and NaN-checked). Fixes: **D2** `ChatInputBar.keyboardVisible` (ergonomic bottom buffer rendered under the raised iOS keyboard), **D4** `PortraitLockShell` keyboard guard (was inert on iOS — the platform it was written for), **D3** keyboard-open autoscroll (dead on iOS web; now fed by both signals via max-of-both so the idle signal's zero-write can't reset the edge detector).
2. **Phase B — TEMP dead-weight probes.** Diagnostics overlay (long-press chat app-bar title, iOS) gained tappable toggles: `FG-OFF` (DOM focus guard passthrough), `RF-OFF` (send refocus machinery + collapse-guard arming off). Device session flips them; if sends survive, ~150 lines of post-0.0.64 machinery (`web_focus_guard_web.dart` + `_sendJustFired`/`_onFocusLostAfterSend`/guard) get DELETED. Signals in `composer_keyboard_signals.dart`, marked TEMP.
3. **Phase C — flash fix, default OFF.** `predictedComposerKeyboardInset`: pointer-DOWN on the field pre-arms the persisted last-known keyboard height so the composer + engine-synced DOM editing element already sit above the incoming keyboard when iOS decides whether to pan (removes the flash *cause*; pure Flutter layout, NO DOM writes — the banned 0.0.69 toolbar-bounce mode cannot recur). Release: real-inset handoff (instant when real≥predicted, 300ms tail when shorter), 1200ms safety, deferred dispose reset. **Default OFF** (`FLASH` toggle for A/B): mid-session the user reported the flash GONE on the 0.0.91-era build — which has zero frontend delta vs master, so most plausibly the 0.0.88 panel-pin fixed it and nobody had re-tested. If the device session confirms, DELETE the mechanism instead of shipping it dormant.
4. **User-reported Android PWA bug (mid-session):** chat-surface tap with the lower action panel open left the keyboard up. `dismissForChatSurfaceTap` now unfocuses even with the panel open (panel survives) — **gated to non-iOS**: iOS keeps the 07-03 keep-focus contract until a device session proves the blur can't retrigger the lower-panel tap loop. `frontend/CLAUDE.md` §7 contract line synced.
5. **Review pass** (reviewer agent; `code-reviewer` type has no model configured in this env — fell back to `reviewer`): verdict merge-ready-after-device-session, 3 P3 nits, all applied (NaN storage guard; cached `_sharedInsetSource`/`_sharedInset` fields so dispose removes from the same instance; max-of-both-signals edge detector).

**Multi-agent collision (lesson):** another session worked the SAME working tree on `feat/metadata-privacy-hardening` and switched HEAD mid-flight — my first checkpoint commit landed on their branch. Recovered: cherry-picked to my branch inside a dedicated **git worktree** (`../fireplace-composer`), `git reset --keep` restored their branch to its exact prior tip (verified nothing built on top; uncommitted files preserved), all subsequent work isolated in the worktree. Worktree removed at session end; main tree now on `refactor/composer-keyboard-viewport`.

## Key files
- `frontend/lib/utils/keyboard_inset_math.dart` (new), `web_keyboard_inset{,_web,_stub}.dart` (shared singleton, persistence, NaN guard)
- `frontend/lib/widgets/input/composer_keyboard_signals.dart` (predicted inset, FLASH/FG-OFF/RF-OFF signals), `chat_composer_viewport.dart`, `chat_input_bar.dart`, `composer_diagnostics_overlay.dart` (toggle UI)
- `frontend/lib/widgets/portrait_lock_shell.dart`, `frontend/lib/screens/chat_detail_screen.dart`, `frontend/lib/utils/web_focus_guard_web.dart` (probe gate)
- Tests: `test/utils/keyboard_inset_math_test.dart` (new, 9), `test/widgets/portrait_lock_shell_test.dart` (new, 3), extended `chat_composer_viewport_test.dart` (+3) and `chat_input_bar_send_test.dart` (contract update +2)
- `frontend/CLAUDE.md` (§7 chat-surface-tap contract), `frontend/pubspec.yaml` (0.0.92), `.planning/composer-viewport-review/` (task_plan, findings)

## Verification
- `flutter analyze --no-fatal-infos` clean on all touched files
- 41–49 tests green across affected suites (`keyboard_inset_math`, `chat_composer_viewport{,_pin}`, `chat_input_bar_send`, `portrait_lock_shell`, `portrait_lock_policy`, `focus_guard_area`, `fireplace_app_portrait_lock`, `chat_detail_scroll_badge`)
- `graphify update .` run; branch pushed; PR #32 open
- **NOT device-verified** — merge gate below

## Notes for next session
- **MERGE GATE: device session owed** (do NOT merge PR #32 on unit-green): (1) iOS — D2 buffer gone under keyboard, portrait guard sane, nothing regressed in normal typing/send; (2) iOS probes — flip `FG-OFF` then `RF-OFF` (long-press chat title → toggles), send messages, note whether keyboard survives → verdict deletes or keeps the machinery; (3) `FLASH` toggle A/B only if the flash ever reappears — user reports it gone on 0.0.91-era; if confirmed dead, DELETE the pre-arm mechanism (predicted inset + Listener + release logic) before merge; (4) Android PWA — chat-surface tap with lower panel open now dismisses keyboard; decide whether iOS should adopt the same (currently gated off pending the 07-03 tap-loop check).
- Version note: branch is 0.0.92 because 0.0.91 is `feat/metadata-privacy-hardening` (finished per user, merge order TBD — whoever merges second reconciles pubspec if both bumped).
- Deploy for the device test from the PC: this branch is checked out in the main tree → `cd frontend && flutter clean && cd .. && .\deploy-web.ps1`, verify Settings footer `gitCommit` == `1b9a234` (or newer).

## Device-session results (same day, 0.0.92 build) → cleanup shipped as 0.0.93

- **FG-OFF:** every send-button tap dismissed the keyboard; FG-ON = correct behavior. **Focus guard is LOAD-BEARING** — verdict documented in `web_focus_guard_web.dart`, `composer_keyboard_signals.dart`, `frontend/CLAUDE.md` §7. Never remove without device re-proof.
- **RF-OFF vs ON:** no difference → `_sendJustFired`/`_onFocusLostAfterSend` + iOS arming blocks DELETED. Non-iOS post-frame refocus fallbacks KEPT (guard is iOS-only; probe evidence iOS-scoped). Collapse guard KEPT (edit/staged/action-toggle paths not isolated).
- **FLASH on/off:** no visible difference; flash dead regardless → entire predicted-inset pre-arm DELETED (signal, Listener wrapper, release state machine, localStorage persistence, overlay toggles). Overlay back to readout-only.
- **Android panel-tap fix: device-CONFIRMED** (keyboard drops, panel stays).
- Cleanup commit `699b671` (12 files, +121 −429); 47 tests green; deployed to prod (`/version.json` = 0.0.93).

**Still open before merge:** user ruling on whether iOS should adopt chat-tap keyboard dismissal with the lower panel open (currently gated off), and the explicit merge OK for PR #32.
