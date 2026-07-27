# Honeycomb Core — Contacts network redesign (owner-driven brainstorm → build)

**Date:** 2026-07-23 (second session of the day, continues `feat/contact-network`)

## What was done
1. **Owner rejected the Terminal Rack direction before build** ("boring tiles") and drove a live brainstorm instead. Rounds: compass slots (8+4) → geometry disproven for portrait; tile grid variants → rejected; Banks/Motherboard/Die-map/Honeycomb pitched → owner picked **Honeycomb Core**.
2. **Approved design (built for real):** local reticle core top-center; fixed-width staggered hex field (4-3-4-3 on phones, adaptive up to 8-7 on desktop) growing straight down, vertical scroll; alphabetical natural order = spatial order; partial last row centers itself. Per-hex socket stub + pad (doubled = real conversation); core visibly feeds row 1 only; **tap fills the contact's route with accent from their hex UP to the core (260ms), then the user card opens** (reduce-motion: instant open, no strip). No shared bus wiring anywhere. Pure alphabetical — hold-and-swap explicitly dropped by owner ("A for now").
3. **Full rewrite of `contact_network_view.dart`:** elliptical-ring engine, drag-to-pin store (`contact_network_layout_v1_<uid>`), InteractiveViewer path, dogleg traces, Reset button all DELETED. New pure `ContactHexLayout` (deterministic: width + labelHeight → slots), `_HexNodePainter`, `_HexFieldPainter`, route weaving through lattice gaps (`routePath`, row-0 uses straight feed geometry). Keyboard focus reveals via scroll (`_revealSlot`), Enter/Space activates. Entrance = single 280ms envelope with row stagger + socket sweep.
4. `ContactsScreen`: dropped `storageUserId`/`resetLayoutLabel`/`dragHint` params. ARB: removed `contactNetworkReset`/`contactNetworkDragHint` (en+pl), regenerated l10n. Preview harness rewired (throwaway `hex_core_prototype.dart` + rack prototypes created for the brainstorm, then deleted).
5. Mid-session interruptions handled: owner demanded prod deploy twice — (a) branch bundle `1f987f1` (0.0.127 + network) as ephemeral test deploy, later superseded by (b) `master` `5a757d3` (0.0.128 banner-nudge removal, deployed and current). Merged master into the branch twice (LATEST cap conflict resolved; second merge clean).

## Key files
- `frontend/lib/widgets/contact_network_view.dart` (full rewrite, ~1130 lines)
- `frontend/lib/screens/contacts_screen.dart`, ARBs + generated l10n
- `frontend/test/widgets/contact_network_view_test.dart` (14 contract tests, rewritten)
- `frontend/test/preview/contact_network_preview.dart` (params unchanged: theme/count/textScale/reduceMotion)

## Verification
- Contract tests 14/14: determinism, natural sort = slot order, pairwise non-overlap across widths 296/366/1076 × labelHeights 15/24 × counts 3-40, in-bounds slots, 4-3 fill + centered partial row, 48dp floor, route bounds + pad terminus, semantics per node, sync tap under reduce-motion, animated tap fires only after fill docks, Tab×40 scroll-reveal + Enter opens, positional scroll assert (field is not lazy — find.text sees offscreen).
- Full suite **797 passed / 4 skips** (was 786; −10 old map tests, +14 hex, +7 from master merges). Analyze 0 issues. `graphify update .` done.
- Visual loop (playbook §0): cosmic 27+8, blue/dark/light/teal 27 at 390×844; 320×700; 1100px desktop (adaptive 8-7 columns, 40 nodes one screen); textScale 1.6 (rows auto-spread, ellipsis works). Route strip too fast for browser screenshot cadence — timing proven by widget test, appearance by the pre-build mock captures.

## Notes for next session
- Branch `feat/contact-network`, NOT merged, no version bump. Production currently serves master `5a757d3` / 0.0.128 (Contacts tab = classic list there). Owner has NOT yet seen the built honeycomb on device — next step is likely an ephemeral branch deploy on request, then PR + PATCH bump on approval.
- Owner interaction contract (do not regress): blue strip = activation animation ONLY (never on bare keyboard focus — focus gets the hex halo); every hex must always show its own socket; no contact-to-contact or bus wiring, ever.
- Traps this session: hot-restart `R` does not recompile preview-side files either (cold `hub restart` always); adjacent slot rects share edges — overlap tests need 0.01 epsilon; `find.text` finds offscreen widgets in the non-lazy field (assert positions); route for row-0 nodes must reuse the feed geometry or the path dips below its pad.
- Owner style note: informal, wants to drive design personally, rejects tile-like layouts on sight. Show real renders, not ASCII, once a direction is picked.

## Iteration 2 (owner device review of 8582c07)
- Verdict: "hooly that looks good daim" + three changes, all shipped as `30f79b5` (deployed, smoke 5/5):
  1. Route fill 260ms -> **480ms easeInOut + bright head dot** ("animation going too fast, user does not see what's going on"). Deliberate override of the 400ms entrance cap — user-triggered feedback, not chrome.
  2. **Identicons deleted** ("weird symbols... must be gone").
  3. **Avatars fill the whole hex** (owner asked; old "no avatars on nodes" rule overridden by owner). `_HexAvatar`: AvatarCircle's URL resolution (absolute or BASE_URL-prefixed, no cache-bust), BoxFit.cover under `_HexClipper`, fallback surface+initial on null/empty/error/loading. Preview harness: `&avatars=1` renders picsum placeholders (1 in 3 left avatar-less to check the mix).
- Full suite 797/4 skips, analyze 0 after each change.

## Iteration 3 (owner: search + local avatar)
- Shipped as `fe48ce4` (deployed, smoke passed): one search field under the header filters BOTH the honeycomb network and the classic list (opaque capsule, convItemBg/convItemBorder tokens, clear button, `contactsSearchNoResults` empty copy, hidden when the account has zero contacts). Local core reticle shows the current user's avatar (`localNodeAvatarUrl` -> shared `_HexAvatar`, initial fallback).
- Preview harness: `screen=1` renders the REAL ContactsScreen against seeded providers (FriendsProvider.onFriendsList JSON + unsigned preview JWT via `setAccessTokenForTest`; needed AppLocalizations delegates in the harness MaterialApp). Headless canvas would not accept synthetic text input — filter behavior verified by 4 new widget tests (`test/screens/contacts_screen_search_test.dart`) instead.
- Owner asked about "some hexes have 1 connector, some 2": explained doubled socket = real conversation (kept; real-data grammar).
- Full suite 801 passed / 4 skips; analyze 0.
