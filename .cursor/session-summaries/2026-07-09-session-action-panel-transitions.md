# Action-panel keyboard transitions — device-verified iOS fix (0.0.99) + Android void fix (0.0.100)

**Date:** 2026-07-09

## Device A/B round 1 verdict (owner, 0.0.99) + round 2 fix (0.0.100, deployed)

**iOS PWA: FLASH GONE, lower panel behaves as intended** ("hes not feel wired to everything now") — H1/H2/H3 + bounce/ping fixes field-confirmed on iOS. **Android PWA: white void on keyboard hide REMAINED.** Owner's 4-screenshot timeline was diagnostic: the composer sits pinned to the TOP of the white band → Flutter's layout is already settled and only the CANVAS is short. Mechanism: the installed PWA's OS window grows on keyboard hide; Chrome exposes the reclaimed strip before Flutter's canvas resizes to cover it (flutter/flutter#179208) — the strip renders the HOST DOCUMENT, which was unstyled = white. The `interactive-widget=overlays-content` meta is irrelevant here (OS-level window resize, not in-page viewport behavior) and was NOT touched.

**Fix (0.0.100, `79a3cf1`, DEPLOYED + smoke ALL PASS):** paint the document. `web/index.html` ships static `html, body { background-color: #17181A }` (default dark scaffold — also kills the first-paint white flash); new `utils/web_document_background{,_stub,_web}.dart` (pure `webDocumentBackgroundCss` → `#rrggbb`, idempotent painter) wired in `MaterialApp.builder` so the ACTIVE resolved theme (light/teal/dark/blue) keeps the document in sync on theme switch. Inert CSS only — no overflow/position/viewport (banned list honored). Tester-agent test parses the LIVE index.html value against `webDocumentBackgroundCss(RpgTheme.backgroundDarkGray)` so the static CSS and default theme can never drift. **OWED: owner re-check of the Android keyboard-hide void on 0.0.100 (footer `0.0.100 · 79a3cf1`); void should now be theme-dark and invisible.**

**CLOSED (owner, same day): Android void CONFIRMED GONE on 0.0.100 — all three bug classes (iOS panel flash, chat-tap bounce + ping dismissal, Android white void) field-verified fixed.** PR #54 awaits the owner's merge OK. Follow-up candidate: the H5 pre-arm shipped dormant (FLASH default OFF, never toggled — the flash died from H1/H2/H3 alone); per the 0.0.93 no-dormant-machinery precedent it should be deleted in a follow-up unless the owner wants to keep the diagnostic lever for a while.

## What was done

Executed `docs/review/action-panel-keyboard-transitions-handoff.md` §4 on branch `fix/action-panel-transitions` (PR #54, commits `46b3dcb` + review fixes `33f060c`), version 0.0.99, **deployed to the OVH VPS and smoke-verified** (`/version.json` 0.0.99, bundle contains `33f060c`, app boots). Backend intentionally stays 0.0.98 (frontend-only).

User expanded scope mid-session with two NEW device-confirmed bugs, **both platforms** (iOS PWA + Android Chrome PWA):
- Chat-surface tap with the lower panel open closed the keyboard but it **bounced back**.
- **Ping tile tap dismissed the keyboard**; ping must be keyboard-neutral.

Levers shipped (ONE build so a single device session can A/B everything):
1. **H1 focus-keyed buffer:** `keyboardVisible` (drives `bottomInteractivePadding` only) now ORs `_focusNode.hasFocus` — the ergonomic buffer collapses at focus time, never resizing the open ~300px panel mid-keyboard-animation. Inherent tradeoff (reviewer P3, documented): hardware-keyboard focus also collapses the buffer.
2. **H2 boolean-gated rebuild:** `_onSharedKeyboardInsetChanged` setStates only when `inset > 0` flips — iOS fires vv resize/scroll through the whole pan; ChatInputBar only consumes the boolean.
3. **H3 instant action panel:** 250ms `SizeTransition` + `AnimationController` + ticker mixin deleted; plain `if (_showActionPanel)` mount, matching the emoji panel (0.0.88). Unconditional (Bug B is Android).
4. **H5 pre-arm resurrected** from `699b671` (reverse-apply) behind the diag-overlay **FLASH toggle, default OFF** — the 0.0.92 probe never covered the panel+focus path. FG-OFF/RF-OFF probes NOT resurrected (verdicts final).
5. **Bounce fix:** `dismissForChatSurfaceTap` unfocuses on iOS too (keep-focus gate removed — it made the canvas tap's DOM blur fight the still-focused framework node → close + engine-refocus bounce). 07-03 panel-survives contract preserved via the suppression flag (test-covered).
6. **Ping keyboard-neutral:** ping tile wrapped in `FocusGuardArea('action_tile_ping')` (iOS: preventDefault stops the blur outright) + `ChatActionTiles.onPingSent` → `_refocusComposerAfterPing` off iOS (the `_send` post-frame pattern), gated on focus-at-pointer-down captured by a `Listener` on the panel (so panel-open/keyboard-hidden ping never summons the keyboard).

**Adversarial review (reviewer agent) found a real P1, fixed before deploy:** the H2 gate severed the ONLY mechanism keeping the load-bearing DOM focus-guard rects tracking the composer during the iOS pan (`ChatComposerViewport` repositions per vv event but `composer` is an identical widget instance → subtree rebuild skipped → `FocusGuardArea` never re-measures → first tap after every keyboard rise would blur = FG-OFF catastrophe, and FLASH-ON would have masked it, poisoning the A/B). Fix: `FocusGuardArea` now listens to `sharedKeyboardInsetSource()` itself and re-measures post-frame per inset event — registration-only, zero rebuilds, rects track the whole pan. **P2 fixed:** `lastKnownKeyboardInset` persisted mid-hide partials (progressive hide 336→200→120→0 left 120) which would have made the FLASH lever silently inert — and plausibly explains the 0.0.92 "unobservable" verdict; now persists only new maxima since the keyboard last fully hid.

## Key files

- `frontend/lib/widgets/input/chat_input_bar.dart` — H1/H2/H5, bounce fix, ping refocus, instant panel mount
- `frontend/lib/widgets/input/focus_guard_area.dart` — P1 fix: inset-listener re-measure
- `frontend/lib/widgets/chat_action_tiles.dart` — ping `FocusGuardArea` + `onPingSent`
- `frontend/lib/widgets/input/chat_composer_viewport.dart`, `composer_keyboard_signals.dart`, `composer_diagnostics_overlay.dart`, `frontend/lib/utils/web_keyboard_inset{,_stub,_web}.dart` — pre-arm plumbing + FLASH toggle + episode-max persistence
- `frontend/test/widgets/input/chat_input_bar_send_test.dart` (+7 Tester-agent tests), `focus_guard_area_test.dart` (+1 guard-tracking test)
- `frontend/CLAUDE.md` §7 contract lines synced

## Verification

- analyze clean; **full frontend suite 609/609**; targeted composer suites green.
- Deployed via `.\deploy-web.ps1` (OpenSSH → `ubuntu@51.68.138.13`); `scripts/smoke/post-deploy-smoke.mjs` **ALL PASS** (health, both version surfaces, bundle sha `33f060c`, headless boot).
- **NOT device-verified yet — the merge gate.**

## Notes for next session

- **DEVICE A/B OWED (merge gate for PR #54).** Footer gate first: Settings must show `0.0.99 · 33f060c`. Protocol (handoff §4 + new bugs):
  - iOS: (a) panel open → tap field → flash? (b) panel+keyboard → hide panel → flash? (c) no-panel flow unchanged? (d) FLASH toggle ON (long-press chat title → overlay) → repeat (a); check `predicted/lastKnown` readout is a sane keyboard height (~300+), not a mid-hide partial.
  - Both platforms: (e) panel open + keyboard → tap chat surface → keyboard closes and STAYS closed, panel survives; (f) panel open + keyboard → tap ping → keyboard STAYS; (g) panel open, keyboard hidden → tap ping → keyboard stays HIDDEN; (h) Android keyboard hide → white void gone?
  - iOS regression canary: send-button taps must keep the keyboard (guard rects now re-measure via the inset listener — if sends start dismissing the keyboard, suspect the FocusGuardArea change first).
- If FLASH shows no effect on the panel+focus path with a sane `lastKnown`, DELETE the pre-arm for good (comment in `composer_keyboard_signals.dart`).
- Reviewer P3 (accepted): ping guard rect can go stale only if the tile row horizontally scrolls (<316px viewports), self-heals on next rebuild.
- Never merge PR #54 without explicit owner OK.
