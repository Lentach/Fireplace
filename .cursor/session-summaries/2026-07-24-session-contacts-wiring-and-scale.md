# Contacts board: full wiring, and making the board cheap at scale

Round after `2026-07-24-session-contacts-core-centering.md`. Branch `feat/contact-network`,
`d18f938` → `cb10c36` → `70919c6` → `30e6b03`. No version bump — branch test deploys stay 0.0.128.

## Owner input this round

- The power-on scan pass was shown and rejected: *"its not a wow effect its just a scan… get rid of it."* Removed in `d18f938`; `MainShell` is byte-identical to master again. **Do not rebuild it.**
- He wanted the board to read as a network *at rest*, not only while a route is lit.
- On an early wiring render he called the top of the field "fat" — the traces bunched into a heavy mass near the core.

## What was done

1. **Every contact is wired** (`cb10c36`). Each hex owns a dormant trace along the exact `ContactHexLayout.routePath` the accent fill later travels, so the lit route is that same line rather than a second one drawn over it. The painter's old row-0-only feed block is deleted — one source of truth. The add cell gets no trace (it is not a person). `coreCenter.dy` 64 → 48 to buy ~1 more visible row.
2. **"Fat at the top" was alpha compounding, not geometry.** 13 traces share the rim→exit segment; drawn as 13 separate `drawPath` calls they composite 13-deep. **Fanning each trace to its own rim angle was built and REVERTED**: N rays converging on a 34px circle stay sub-pixel apart for ~180px, so at 100 contacts the fan filled into two solid grey wedges, and no alpha ramp short enough to spare row 0 could hide it. Shipped fix: `ContactHexLayoutResult.traces` builds ONE combined `Path` (memoized `Path? _traces` — the class is therefore no longer `const`/`@immutable`) and the painter strokes it ONCE, so overlaps union. Identical weight at 3 contacts and at 300.
3. **Route fill repaints, it no longer rebuilds** (`70919c6`). `AnimatedBuilder(_routeController)` wrapped the ENTIRE `Stack`, so all N nodes — Focus + Semantics + GestureDetector + ClipPath + Image each — rebuilt on every frame of the 480ms fill: ≈**6k subtree builds per tap at N=100**. It now wraps only the `Positioned.fill` CustomPaint.
4. **Avatars fetch lazily** (`30e6b03`). Rows arm as they enter the viewport plus one row of lookahead, with a high-water mark so scrolling back never reverts a loaded face to initials. Gate is `ValueNotifier<int> _armedThroughRow` + `ValueListenableBuilder` around each avatar **leaf** — deliberately NOT `setState` on the field, which would reintroduce the exact cost item 3 just removed. Every node is still BUILT, so keyboard traversal, screen readers and scroll-to-reveal still reach all N.
5. `rowPitch` hoisted onto `ContactHexLayoutResult` — the painter and the arming math were re-deriving the same formula.
6. **PR #97 opened**: https://github.com/Lentach/Fireplace/pull/97 (base `master`, head `feat/contact-network`). The three optional Standards findings were **refused** in the nit round and recorded in the PR body instead: unasked-for, zero user-visible gain, and they re-open review surface on an already-reviewed branch.

## Measured before optimizing

Throwaway `test/scale_probe_test.dart` — written, run, **deleted**. Build+layout per rebuild:

| contacts | 20 | 50 | 100 | 200 | 400 |
|---|---|---|---|---|---|
| ms | 22.3 | 28.1 | 30.5 | 40.6 | **109.0** |

Debug mode, build+layout only, no raster/GPU. `Image.network` never fires under `flutter test`, so avatars were **not** in those numbers. Linear to ~200, cliff after. That is why lazy avatars shipped and the `ListView` rewrite did not — it costs 22 layout tests and breaks focus traversal to unbuilt nodes. **Deferred on purpose until >200 contacts is real.**

Corrected mid-round and told to the owner plainly: on web the browser caps ~6 concurrent connections per origin, so 100 avatars was always a *queue*, not a request storm. Lazy avatars is bandwidth/decode hygiene, not a rescue.

## Key files

- `frontend/lib/widgets/contact_network_view.dart` — `ContactHexLayoutResult.traces`/`_traces`/`rowPitch`/`leadingSlots`, `_HexFieldPainter` (single stroked path), `_routeController` `AnimatedBuilder` narrowed to the `Positioned.fill` CustomPaint, `_armedThroughRow`/`_armedFloor`/`_lastLayout`/`_visibleThroughRow`/`_armVisibleRows`, `_buildContactNode` avatar leaf.
- `frontend/lib/screens/main_shell.dart` — reverted to byte-identical with master (`git diff --stat 5a757d3 -- …` → 0 lines).
- `frontend/test/widgets/contact_network_view_test.dart` — 23 tests; this round added route-fill widget identity and lazy-avatar arming, and `_contact()` gained `{String? avatar}`.

## Verification

- `flutter analyze --no-fatal-infos` → **No issues found**. `flutter test` → **821 passed / 4 skips** (was 819).
- **Both new perf tests were falsified.** Route-fill identity: temporarily restored the wide `AnimatedBuilder` → test went red on non-`identical()` node widgets, then restored. Lazy avatars: removed the gate → 60 of 60 rows armed, test red, then restored. The owner-facing claim depends on this, so it was done deliberately, not assumed.
- Deploys `d18f938` → `cb10c36` → `70919c6` → `30e6b03`, each an ephemeral branch build, `scripts/smoke/post-deploy-smoke.mjs` **5/5** each. Live `/version.json` → `{"version":"0.0.128","gitCommit":"30e6b03"}`; served `main.dart.js` literally contains the sha. Backend untouched at 0.0.127/`3861166`.

## Notes for next session

- **Awaiting his device pass on `30e6b03`.** One symptom was flagged to him up front: a hex that stays plain initials *after* it is clearly on screen means the arming math is one row short — `_visibleThroughRow` reads `_scrollController.position.viewportDimension`, and the 390×700 test host cannot reproduce a safe-area/keyboard viewport mismatch. That is **not** a network failure.
- Master still `5a757d3`, untouched. Release path still gated on his explicit OK: bump 0.0.128 → **0.0.129** (PATCH, never `+N`) as the last commit on the branch → merge PR #97 → `deploy-web.ps1` from master → smoke → dated summary + LATEST edit-in-place (cap 5).
- Do-not-resurrect list, now including this round's reverts: the **power-on scan pass**, the **fanned-rim traces**, the **core-docked `+` port**, unread/typing status on the Contacts board, activity-based sorting, idle ambient animation, contact-to-contact links, and any bus/shared-rail wiring. The node count must never lie.
- **The browser tool is not headless** — it pops a real window in front of him. Only render when he asks or you announce it, batch the captures, and `close`+`kill` after. Append `&cb=`+`Date.now()` to preview URLs after a harness restart or you will screenshot a stale bundle and misread it as "the change didn't work".
