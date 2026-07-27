# HANDOFF — Terminal Rack: dense-mode presentation for the Contact Network

**For:** the next agent picking up the Contacts network feature.
**From:** the 2026-07-23 session that designed, built, and test-deployed the contact network map.
**Bootstrap first (mandatory, in order):** root `CLAUDE.md`, `frontend/CLAUDE.md`, `.cursor/session-summaries/LATEST.md`, `docs/design/flutter-ui-playbook.md` (repo-root `docs/`, NOT `frontend/docs/`). Then read this file fully.

## Goal
Replace the dense-network fallback of the Contacts map. Today, when the radial map cannot fit the viewport, it becomes a pannable 2D `InteractiveViewer` — the owner reviewed a 40-contact screenshot and rejected it as "a big mess". Build the **Terminal Rack**: above the fit limit the same visual language reorganizes into an ordered, vertically scrolling patch-panel grid. The owner explicitly approved this direction ("i was thinking about same idea of terminal rack yes").

## Current state (what is DONE and LIVE)
- Branch `feat/contact-network`, pushed. Code commit `c15d770` + docs commit `370f843`. NOT merged to master; no version bump (branch-test-deploy convention, precedent 2026-07-22 appearance-redesign).
- Production is serving bundle `c15d770` (0.0.125) as an EPHEMERAL owner test deploy — frontend only, backend untouched (0.0.123/`4609af2`). Smoke passed (`scripts/smoke/post-deploy-smoke.mjs`).
- `ContactNetworkView` (`frontend/lib/widgets/contact_network_view.dart`, ~1750 lines): map presentation of `FriendsProvider.friends`. Local user = reticle circle; contacts = clipped-corner terminals (identicon + initials + real username); PCB dogleg traces user→contact only; doubled trace = real conversation (`conversationContactIds`); sparse falloff ticks, dashed elliptical orbit guides, corner brackets, `NODES NN` caption; one-shot entrance pulse (reduce-motion aware); drag-to-pin (per-user SharedPreferences `contact_network_layout_v1_<uid>`, pins are HINTS — clamped + collision-resolved every build); header trailing toggle → classic list fallback.
- `ContactsScreen` is a StatefulWidget wiring it all; `_openContactCard`/`_openChatWithContact`/pendingOpen/`instantOpaqueRoute` untouched.
- `MainTabScreenHeader` now centers its title via Stack + `Positioned` side controls (shared-widget fix, improves Chats too).
- 10 contract tests in `frontend/test/widgets/contact_network_view_test.dart`; full suite 786 green; analyze 0 issues.
- Preview harness `frontend/test/preview/contact_network_preview.dart`: `?theme=cosmic|blue|dark|light|teal&count=0|1|3|8|15|25|40&textScale=1.6&reduceMotion=1`. All five themes captured at 390x844/320x700/1100px.

## The approved design (build exactly this)

### A. Terminal Rack (dense mode)
- Trigger: GEOMETRIC, not a count. Reuse the existing fit pipeline in `ContactNetworkLayout.resolve`: today "does not fit at floor node size" → `usesInteractiveViewer: true`. Replace that branch: does-not-fit → RACK mode. The `InteractiveViewer` pan/zoom path is DELETED (two clean modes, no in-between). In practice the switch lands around 15–18 contacts on a 390px phone and adapts to viewport + text scale for free.
- Layout: vertically scrolling grid of the SAME clipped-corner terminal cells (identicon, initials, full-size username label below). Column count measured from viewport width and the widest measured label (2–4 cols on phone, more on desktop). Fill order = the existing natural sort (`_compareByDisplayName` order) row-major, so alphabetical position is spatial position — lookup works like the list.
- Local node: docked compact header band at the top of the scroll area — reticle circle + `LOCAL NODE` caption, always visible (pinned above the scroll or as the first sliver; owner-taste call, prefer pinned).
- **CRITICAL truthfulness constraint (review-mandated):** NO shared column feed lines, NO bus/trunk wiring. A shared vertical line through many cards visually implies contacts share a channel — violates the invariant that every drawn link is one direct user→contact relationship. Instead: each card carries its OWN independent socket — a short trace stub (~8–12px) + port pad on the card's top edge, self-contained per cell (think numbered patch sockets, not a wired backplane). Doubled stub = has conversation (keeps the real-data hierarchy). Alternatively omit inter-card wiring entirely — but the per-card socket is preferred; it keeps the "connected terminal" identity.
- Chrome: keep corner brackets, `NODES NN` caption, ambient tick field (static behind the scroll or omitted if it scrolls badly — judge visually), one-shot scanner on open (reduce-motion → static).
- Drag-to-pin and Reset layout are MAP-MODE ONLY — hide both in rack mode (a rack is ordered by definition). Saved pins persist untouched for when the count drops back.
- List toggle in the header stays, unchanged, as the plain third fallback.

### B. Ordered orbits (map-mode discipline patch — do this too, it is cheap)
- In map mode, fade the per-id angle jitter out as ring occupancy rises: full jitter at sparse counts (organic look), → 0 as a ring approaches capacity (even spacing, disciplined look). Suggested: `jitter *= (1 - occupancy)` or a smoothstep — keep it deterministic from the same inputs.
- Rationale: jitter is charm at 8 nodes and noise at 15; the map's upper range (12–18) should look composed, since the rack takes over beyond that.

## Non-negotiable constraints (unchanged from the original build)
- Real data only: every visible element derives from `FriendsProvider.friends` / `ConversationsProvider`. No fake nodes, no invented status, no clustering that implies relationships between contacts.
- Usernames readable before tapping; 48dp minimum hit targets (`ContactNetworkLayoutMetrics.nodeFloorDiameter` — contract-tested).
- Theme tokens ONLY (`RpgTheme`, `FireplaceColors.of`, `GlassTheme.of`, `colorScheme`); zero `Color(0x...)` literals; derive shades via `withValues(alpha:)`.
- Glass grammar: content stays opaque; glass only on floating chrome.
- Motion: entrances 180–280ms, play once, `MediaQuery.disableAnimationsOf` → static. Flutter built-ins only, no new deps.
- Determinism: same contacts + viewport + textScale → identical layout, both modes.
- A11y is a core invariant, not a fallback: per-node `Semantics(container: true, button: true, label: username)` (container:true is LOAD-BEARING — without it all labels merge into one blob node), traversal = sorted order (`OrdinalSortKey`), keyboard Tab/Enter activates. Rack mode makes focus-reveal trivial (ensureVisible on scroll) — replace the map's `_revealFocusedNode` pan logic with scroll-to-reveal there; keep the map's version for map mode.
- Existing behavior preserved: tap → `_openContactCard`; `instantOpaqueRoute` untouched; 7-provider cap (no new provider).

## Verification contract (what "done" means)
1. Extend the preview harness with dense counts (`18|25|40|60` as CASES — counts select scenarios, never mode; the MODE each case renders is a function of viewport + text scale) and run the playbook §0 loop: `flutter run -d web-server --web-port <p> -t test/preview/contact_network_preview.dart` as a BACKGROUND process (hub/managed job, NEVER block on it), browser screenshots, judge honestly, iterate. ALL FIVE themes (cosmic/blue/dark/light/teal — do not skip blue, it was missed once), 390x844 + 320x700 + ~1100px, plus textScale 1.6. REQUIRED boundary captures: (a) a count that racks on 390px phone but still maps on ~1100px desktop (verify the SAME count renders different modes per viewport); (b) a count that maps at textScale 1.0 but racks at 1.6 (accessibility flips the mode); (c) whatever count sits just under/over the fit limit on 390px — eyeball the transition feels sane.
2. Update/extend the contract tests: mode-switch criterion expressed GEOMETRICALLY (assert fits→map / not-fits→rack by feeding viewports and label sizes, including a case where the same contact count yields map on a large viewport and rack on a small one, and a case where only textScale flips the mode — NEVER assert "count N → rack" against a single hardcoded viewport without its mirror case), rack determinism + sorted order, keyboard/scroll reveal (Tab to the last of 40 in a small viewport → its rect fully inside the viewport), 48dp floor in rack cells, reduce-motion static. Per-card socket independence (no cross-card wiring) is judged visually, not by test.
3. `flutter analyze --no-fatal-infos` 0 issues; full `flutter test` green (baseline 786).
4. `graphify update .` after code changes.
5. Session summary: dated file + LATEST.md update (LATEST hard cap: 5 entries; dated files are gitignored/local-only BY DESIGN — `git add -f` only deliberately; LATEST.md is the committed layer).
6. Do NOT merge to master, do NOT bump version, do NOT redeploy without explicit owner ask. If the owner asks to deploy the branch for testing: `powershell -ExecutionPolicy Bypass -File deploy-web.ps1` from repo root (NOT `.\` inside bash tool), verify `/version.json` + served sha, run `scripts/smoke/post-deploy-smoke.mjs`; branch test deploys do not bump semver (documented precedent).

## Traps paid for this session (do not relearn)
- `flutter run -d web-server` hot restart (`R`) does NOT recompile changes to the `-t` ENTRY file (lib/ changes recompile fine). Cold-restart the process (`hub restart`) after editing the preview harness.
- Non-positioned `Align` children inside a Stack can collapse to center (icon painted over title). Use explicit `Positioned(left/right:0, top:0, bottom:0)`.
- `Semantics` without `container: true` inside a labeled container merges all child labels into one node.
- `l10n.yaml` template is `app_pl.arb` — placeholder `@`-metadata goes THERE; en-only metadata fails gen-l10n. Run `flutter gen-l10n` after ARB edits.
- Zero-duration `TweenAnimationBuilder` (reduce-motion) fires `onEnd` during first build — defer any setState to a post-frame callback.
- `TextPainter` label widths must be ceil()+1 or glyphs clip at accessibility text scales.
- Windows: hub/pty can't spawn `flutter` (batch) directly — use `cmd /c flutter ...`.
- The Chats header (`glass_preview.dart`) shares `MainTabScreenHeader` — re-verify it visually after any header change.
- Collision resolver: ring candidates → full-bounds sweep (coarse stride, can miss narrow gaps) → least-overlap fallback. Do NOT claim "guaranteed collision-free" in docs; say "collision-free in validated layouts". (Rack mode sidesteps all of this — grid cells cannot collide.)

## Suggested first moves
1. Bootstrap reads, `git status -sb`, continue on `feat/contact-network`.
2. Sketch the rack cell + socket in the existing painter vocabulary (reuse `_clippedCornerPath`, `_IdenticonPainter`, `_TerminalChromePainter`; add a tiny socket painter or extend chrome painter with a top-edge stub).
3. Implement mode selection in `ContactNetworkLayout.resolve` (replace the `usesInteractiveViewer` branch with a `ContactNetworkMode.map|rack` result; delete the InteractiveViewer path and `_revealFocusedNode`'s pan math in favor of scroll reveal).
4. Preview → screenshots at 18/25/40/60 across themes → iterate until the 40-case looks like an instrument, not a mess.
5. Jitter fade (Option B) in map mode; re-screenshot 12–15.
6. Tests, analyze, graphify, summaries.
