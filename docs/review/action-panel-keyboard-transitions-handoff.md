# Lower Action Panel × Keyboard Transitions — Fresh-Agent Handoff

**Date:** 2026-07-07/08 (end of the composer keyboard/viewport session)
**State when written:** composer work merged via PR #32; the composer input files are unchanged since `cc95e6d`. The repo has since moved on around them (0.0.95 era, **production migrated GCP → OVH VPS** — commit `793b87f`). Treat `.cursor/session-summaries/LATEST.md` and `git log` as the source of truth for prod host, deploy scripts, and current version; do NOT trust any hardcoded host/version in older docs (including the flash handoff's §8 GCP instructions).
**Prior art (read in this order):** root `CLAUDE.md`, `frontend/CLAUDE.md`, `.cursor/session-summaries/LATEST.md` + `2026-07-07-session-composer-viewport.md`, `docs/review/composer-keyboard-audit.md` (2026-06-24), `docs/review/ios-composer-keyboard-flash-handoff.md` (flash mechanics — still the best source on WHY the flash happens), `.planning/composer-viewport-review/` (task_plan + findings).

---

## 1. The bugs to fix (user-reported, 2026-07-07 evening)

**Bug A — iOS PWA focus flash, ACTION-PANEL-SPECIFIC.**
With the lower action panel open, tapping the text field → the old <1s page-jump flash while the keyboard rises. **Also flashes when hiding the lower panel.** Without the panel everything is clean ("all works as intended").

**Bug B — Android Chrome PWA white void on keyboard hide.**
On keyboard dismiss: a white band at the bottom of the screen, then the layout "fixes itself" after a fast blink/flash from the bottom. This is the **A1 white-void signature** from the 2026-06-24 audit (upstream flutter/flutter #179208 / #178431 / #50382). A1 was reported resolved-on-device at 0.0.65 **without a targeted fix** — it is back (or newly re-triggered).

## 2. What is PROVEN vs UNKNOWN (do not re-litigate the proven rows)

| Claim | Status | Evidence |
|---|---|---|
| iOS panel+focus flash is **NOT a regression** from the 0.0.92/93 changes | **PROVEN** | A/B on device: baseline `038e295` (0.0.90, pre-change tree) deployed 2026-07-07; user reproduced the flash with the panel open. Every prior "flash is gone" verdict was measured in the no-panel flow only. |
| DOM focus guard (`web_focus_guard_web.dart`) is **load-bearing** | **PROVEN** | FG-OFF device probe: every send tap dismissed the keyboard. NEVER remove it (documented in code + `frontend/CLAUDE.md` §7). |
| `_sendJustFired` refocus machinery + flash pre-arm were unobservable **in the no-panel flow** | PROVEN (that flow only) | RF/FLASH probes, 0.0.92. Deleted in `699b671`. **Caveat: the pre-arm was never A/B'd on the panel+focus path — the one place it could matter.** |
| iOS panel-**hide** flash exists on 0.0.90 | **UNKNOWN** | Baseline test only covered panel+focus. |
| Android white-void exists on 0.0.90 | **UNKNOWN** | No Android baseline run. Note 0.0.92 added a NEW dismissal trigger on Android (chat-tap with panel open now unfocuses), so the void may simply have a new, more frequent entry point even if the platform bug is old. |
| Laggy/blinky keyboard-hide is caused by D2 buffer churn | HYPOTHESIS | See §3-H1. New in 0.0.92; plausible aggravator, unproven. |

## 3. Unified working theory — the action panel is the unfinished half

The **emoji panel** got the 0.0.88 treatment: it REPLACES the keyboard, mounts **instantly** (plain `if (_showEmojiPicker)` — no animation), and `composerBottomPanelPinned` anchors the composer at `bottom:0` so the swap is seamless.

The **action panel** never got any of that. It COEXISTS with the keyboard (by design), and during every keyboard show/hide it is:
- wrapped in a **250 ms `SizeTransition`** (`_actionPanelController`, `chat_input_bar.dart` ~line 1135) that keeps relayout running through the transition window;
- **changing height mid-animation** since 0.0.92: `ChatActionTiles(bottomPadding: bottomInteractivePadding)` — the D2 fix collapses/restores the ergonomic buffer exactly while the keyboard animates (`keyboardVisible` is live-inset-derived, `chat_input_bar.dart` ~line 824);
- rebuilt on **every visualViewport event**: `_onSharedKeyboardInsetChanged` does an unconditional `setState` (~line 214), and iOS fires vv resize/scroll repeatedly during the pan.

Continuous relayout of a ~300px block during the exact window where (iOS) the viewport pin is countering the compositor pan one frame late, and where (Android) Chrome is known to leave stale composited regions, plausibly explains BOTH bugs. The iOS flash is worst with the panel because the moving/repainting surface is ~5× the bare input row.

Ranked hypotheses:
- **H1 (new, 0.0.92):** D2 buffer collapse/restore mid-animation (`bottomInteractivePadding` keyed on live inset). Explains hide-blink; aggravates everything.
- **H2 (new, 0.0.92):** per-vv-event `setState` rebuild storm in `ChatInputBar`.
- **H3 (old):** 250 ms `SizeTransition` on the action panel — relayout through the whole transition; the emoji panel deliberately has NO animation.
- **H4 (old, iOS):** the residual compositor-pan flash (see flash-handoff §2) made visible again by the tall panel block riding the inset.
- **H5 (lever, not cause):** the deleted pre-arm (`git show 699b671` has the full mechanism) might genuinely kill H4 for the panel case — it was designed for exactly this and never tested on it.

## 4. The plan that was about to start (pick this up)

Branch `fix/action-panel-transitions` off master. Version bump to **0.0.94**. All levers in ONE deployable build so a single device session can A/B everything:

1. **Focus-keyed buffer (fix H1):** derive `keyboardVisible` (for `bottomInteractivePadding` ONLY) from composer focus state (+ existing inset signals as OR), so the buffer collapses on focus — BEFORE the keyboard animation — and returns on blur at animation start, never mid-flight. Keep the viewport's inset math untouched. VM-testable.
2. **Rebuild-on-change (fix H2):** in `_onSharedKeyboardInsetChanged`, `setState` only when the derived boolean actually flips, not per vv pixel event. VM-testable.
3. **Instant action panel (test H3):** make the action panel mount/unmount instant like the emoji panel (drop the `SizeTransition` or zero its duration). Must be **unconditional**, not diag-overlay-gated — the overlay is iOS-only and Bug B is Android. Accept the cosmetic downgrade for the experiment; if it fixes the bugs, decide whether to keep it or re-add a cheaper effect (e.g. fade) later.
4. **Optional iOS lever (test H5):** resurrect the pre-arm from `699b671` behind the `FLASH` diag toggle, default OFF, for a panel+focus A/B on iOS. Only if capacity allows; H1–H3 first.

**Device protocol for the user (strict):**
- Footer gate first: Settings footer MUST show the new version+commit before ANY observation counts (SW serves stale bundles; see root `CLAUDE.md` stale-build trap).
- iOS: (a) panel open → tap field → flash? (b) panel open+keyboard → hide panel → flash? (c) normal no-panel flow unchanged?
- Android: (d) keyboard hide via chat-tap with panel open → white void? (e) keyboard hide without panel → void? (f) panel-tap dismissal still works (0.0.93 feature, device-confirmed — do not regress).
- If results are ambiguous, also baseline Android on `038e295` (same deploy-old-build trick as today) to settle the §2 UNKNOWN rows.

## 5. Constraints (inviolable)

- E2E send dispatch is a trust boundary: `_send()` → `sendMessage`/`editMessage`/`sendImage`, trim/empty guard, staged image-then-caption ordering. Do not touch.
- NEVER remove the DOM focus guard (§2). NEVER reintroduce: global scroll-lock (`21d98d7`), DOM pin pre-arm on pointer-down (0.0.69), cosmetic focus mask (0.0.70), `interactive-widget` changes for iOS reasons. See flash-handoff §3/§7.
- The 0.0.93 Android panel-tap dismissal (keyboard drops, panel stays; iOS gated off) is device-confirmed and must not regress. Contract in `frontend/CLAUDE.md` §7.
- Frontend builds on the PC only (`.\deploy-web.ps1` from repo root — verify it targets the OVH VPS post-migration; the server cannot compile Flutter web). Version = bump PATCH from current `frontend/pubspec.yaml` on master (0.0.95 at write time). Feature branch + PR; NEVER merge to master without the user's explicit OK. Never uninstall / clear site data on a device (wipes E2E keys).
- One agent per working tree: if another session is active in `C:/Users/Lentach/Desktop/fireplace`, work in a git worktree.

## 6. Key files

- `frontend/lib/widgets/input/chat_input_bar.dart` — buffer derivation (~824), vv listener (~214), action panel `SizeTransition` (~1135), `dismissForChatSurfaceTap` (~167), focus guard areas.
- `frontend/lib/widgets/input/chat_composer_viewport.dart` — inset/debounce/panel-pin layout core (leave the math alone).
- `frontend/lib/widgets/input/composer_keyboard_signals.dart` — surviving globals + 2026-07-07 verdict comment.
- `frontend/lib/utils/web_keyboard_inset{,_web,_stub}.dart`, `keyboard_inset_math.dart` — shared inset source (singleton, test seam `setSharedKeyboardInsetSourceForTest`).
- `frontend/lib/utils/web_ios_viewport_pin_web.dart`, `web_focus_guard_web.dart` — the pin and the guard (do not weaken).
- Tests: `frontend/test/widgets/input/chat_composer_viewport_test.dart`, `chat_input_bar_send_test.dart`, `test/utils/keyboard_inset_math_test.dart`, `test/widgets/portrait_lock_shell_test.dart`.
- Deleted-mechanism reference: `git show 699b671` (pre-arm, probe toggles, overlay toggle UI).

## 7. Verification bar

`flutter analyze --no-fatal-infos` clean; targeted suites green (the four test files above + `chat_composer_viewport_pin_test.dart`, `chat_detail_scroll_badge_test.dart`); Tester agent authors any new tests; reviewer agent (same model class; the `code-reviewer` agent type has no model configured in this env — use `reviewer`) before the device session; deploy + footer-gated device A/B; session summary (dated file local-only, `LATEST.md` tracked+committed).
