# HANDOFF — Honeycomb Core: header-search integration + release path

**For:** the next agent picking up the Contacts honeycomb feature.
**From:** the 2026-07-23/24 session that brainstormed, built, and owner-iterated the Honeycomb Core.
**Bootstrap first (mandatory, in order):** root `CLAUDE.md`, `frontend/CLAUDE.md`, `.cursor/session-summaries/LATEST.md`, `docs/design/flutter-ui-playbook.md` (repo-root `docs/`). Then this file fully. Session detail: `2026-07-23-session-honeycomb-core.md` (local-only).

## Where things stand (ALL owner-approved and LIVE as ephemeral test deploy)
- Branch `feat/contact-network`, tip `a8473b6`, pushed, NOT merged, no version bump. Production frontend serves `a8473b6` / 0.0.128 (ephemeral branch deploy, smoke passed); backend untouched 0.0.127/`3861166`. Master tip `5a757d3` (0.0.128 banner-nudge removal).
- The old radial map / Terminal Rack plan are DEAD (owner rejected pre-build). The shipped design is the **Honeycomb Core**, owner verdict: "i have no words all is perfect".
- `frontend/lib/widgets/contact_network_view.dart` (~1140 lines, full rewrite): reticle core top-center (LOCAL NODE caption below, current user's avatar inside — accent ring ON the circumference per owner nit `a8473b6`), fixed-width staggered hex field below (pure `ContactHexLayout`: 4-3 rows on phones, adaptive to 8-7 on ≥~1000px, partial last row self-centers, natural-sort order = spatial order), vertical scroll only.
- Hexes: contact avatar covers the WHOLE hex (`_HexAvatar`, AvatarCircle URL resolution, initial fallback; identicons were built and removed on owner review). Socket stubs on top vertex: **one pin = no conversation, two pins = active chat — owner explicitly KEPT this real-data semantic after initially flagging it ("i didnt know that i like that keep it"). Do NOT unify.**
- Tap = signature interaction: route fills with accent from the contact's hex UP to the core, **480ms easeInOut + bright head dot** (owner slowed from 260ms), card opens on dock. Reduce-motion: instant. Blue strip NEVER on bare keyboard focus (focus = hex halo; Enter activates).
- Search: capsule field under the header filters BOTH network and classic list live (owner: "chef kiss"); hidden on empty accounts; `contactsSearchHint`/`contactsSearchNoResults` ARB en+pl.
- ContactsScreen: `_showList` toggle kept; `_applyQuery` shared filter; `_searchClearance = 54` band constant.

## THE NEXT TASK — DONE (2026-07-24)
Owner picked **Idea 2**: "i would go with option 2 lets see serchbar in the header". Shipped — the 54px band is deleted, search lives in the header capsule row (bare magnifier LEFT / list-toggle RIGHT; tap → full-width `GlassPill` input with inner magnifier and ×; the toggle KEEPS its slot so the query survives a view switch; Escape closes). `MainTabScreenHeader` gained `.custom(child:)` + `leadingGlass` (default true) so Chats/Settings are byte-identical. Details, traps (themed `focusedBorder` leaking through `InputDecoration.collapsed`) and verification: `2026-07-24-session-honeycomb-header-search.md`.

Remaining: owner review of the header search on device, then the release path below.

## After owner accepts the whole feature
PR `feat/contact-network` → master, PATCH bump 0.0.128 → **0.0.129** (in `frontend/pubspec.yaml`, no `+N` ever), merge on explicit owner OK only, then normal master deploy (`deploy-web.ps1` from repo root) + `scripts/smoke/post-deploy-smoke.mjs`. Branch test deploys do NOT bump semver (documented precedent).

## Verification state (baselines)
- Full suite **801 passed / 4 skips** (analyze 0). Contract tests: `test/widgets/contact_network_view_test.dart` (14 — determinism, natural sort, pairwise non-overlap across widths 296/366/1076 × labelHeights 15/24 × counts 3-40, in-bounds, 4-3 fill + centered partial row, 48dp floor, route bounds + pad terminus, semantics, sync tap under reduce-motion, animated-tap ordering vs 480ms, Tab×40 scroll reveal + Enter, positional scroll assert). Search: `test/screens/contacts_screen_search_test.dart` (4 — network filter, list filter carry-over, clear restores, hidden-when-empty).
- Preview harness `test/preview/contact_network_preview.dart`: `?theme=cosmic|blue|dark|light|teal&count=N&textScale=&reduceMotion=1&avatars=1` renders the bare view; **`&screen=1` renders the REAL ContactsScreen** against seeded providers (FriendsProvider().onFriendsList JSON; AuthProvider().setAccessTokenForTest with an unsigned base64url JWT; ConversationsProvider() default; AppLocalizations delegates are wired in the harness MaterialApp — they were the "Unexpected null value" red screen).
- Visual loop covered: all five themes at 390×844, 320×700, 1100px desktop, textScale 1.6, avatars on/off.

## Constraints (unchanged, non-negotiable)
- Real data only; no bus/trunk wiring, no contact-to-contact links; every drawn line = one user→contact relationship. Count never lies: `NODES NN` reflects what's rendered.
- Theme tokens only (`RpgTheme`, `FireplaceColors.of`, `GlassTheme.of`, colorScheme); zero `Color(0x...)`; content opaque.
- Determinism: same contacts + width + labelHeight → identical slots (this is why live search re-sorting looks composed).
- A11y: per-node `Semantics(container: true)` (load-bearing), sorted traversal, Tab reveal by scroll, 48dp floor, reduce-motion static/instant.
- 7-provider cap; `instantOpaqueRoute` chat entry untouched; never merge/bump/deploy without explicit owner OK.
- Design decisions belong to the OWNER — he drives, rejects fast, reverses himself when shown meaning (socket pins). Show real renders, not ASCII, once a direction exists. Informal English, e.g. "go idea 2".

## Traps paid for (do not relearn)
- Hot restart `R` does NOT recompile files under `test/preview/` — always cold `hub restart` (`cmd /c flutter run -d web-server --web-port 8127 -t test/preview/contact_network_preview.dart`, ready log "is being served", PTY can't spawn flutter batch directly).
- Adjacent slot rects share edges — overlap asserts need 0.01 epsilon (float assoc).
- `find.text` sees offscreen widgets (field is non-lazy) — assert positions, not existence, for scroll tests.
- Row-0 routes must reuse the straight feed geometry (the generic weave dips below the pad).
- Route strip direction: path is built core→pad; `extractPath(total*(1-p), total)` reveals pad-end first = strip travels node→core. Don't "fix" it backwards.
- Headless Chromium won't deliver synthetic keystrokes to the Flutter canvas TextField — verify input behavior with widget tests, screenshots only for looks.
- Zero-duration TweenAnimationBuilder `onEnd` fires during build — the post-frame `_entranceCompleted` guard in `_buildField` is load-bearing.
- l10n template is `app_pl.arb`; run `flutter gen-l10n` after ARB edits.
- Windows deploys: `powershell -ExecutionPolicy Bypass -File deploy-web.ps1` from repo root; verify via `/version.json` + served sha; owner PWA = full close/reopen, NEVER clear site data.
- LATEST.md hard cap 5 entries — the pre-commit hook BLOCKS commits at 6 (hit it once this session; drop the oldest, dated files are the archive).
- Root-dir stray jpg/mp4 files are the owner's screenshots — never add/delete them.

## Suggested first moves
1. Bootstrap reads; `git status -sb` (expect `feat/contact-network` = `a8473b6`, clean except owner's stray media files).
2. Ping the owner for the Idea 1/2 verdict if the conversation didn't carry it; then build per the Idea-2 notes above (or scroll-hide if he overrules).
3. Preview loop with `&screen=1`; extend `contacts_screen_search_test.dart` for the new entry point; analyze + full suite + graphify.
4. Summaries (dated file + LATEST edit-in-place of the honeycomb entry; mind the cap), push branch, deploy only on owner ask.
