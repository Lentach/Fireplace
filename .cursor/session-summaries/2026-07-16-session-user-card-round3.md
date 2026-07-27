# Session 2026-07-16 — User card ROUND 3 (adaptive full-bleed hero + bigger manage-photos sheet)

Branch `feat/user-card-rework` (PR #84, unmerged). Commit `219dcaa`, branch-deployed to prod.

## Owner feedback (round 3)

1. Hero photo must "stretch on all sides like previous, not with spaces left and right … but not be cropped, if it's a possibility" — the round-2 contain-over-blur pillarboxing was rejected.
2. Manage-photos sheet "is small, it needs rework".

## What was done

### 1. Adaptive-height full-bleed hero

- "Previous" = round-1 plain `BoxFit.cover` (full-bleed, cropped). Fixed-height box + arbitrary aspect + full-bleed + no-crop is geometrically impossible, so the hero now **sizes itself to the active photo's aspect**: `photoExtent = (width / aspect).clamp(220, max(260, min(width*4/3, height*0.62)))`. Within the clamp: full width, zero crop, zero bars. Outside it (panoramas, very tall portraits): modest Telegram-style cover crop.
- Aspects resolved async per URL via `NetworkImage(url).resolve` + `ImageStreamListener` (`_photoAspects` map in `_UserCardScreenState`; failed loads keep the 300px default and never retry). `info.dispose()` + `removeListener` on both paths; `onError` handler REQUIRED or widget tests explode.
- `_ProfileHeroDelegate`: `static const _photoExtent = 300` → constructor param `photoExtent` (in `shouldRebuild`). Height changes (page switch / aspect resolves) animate via `TweenAnimationBuilder<double>` (260ms easeOutCubic) wrapping the `CustomScrollView` builder — no sliver snap.
- **Pager simplification**: blurred `ImageFiltered` backdrop + `contain` layer + morphT crossfade DELETED — a single `BoxFit.cover` image per page (box matches aspect ⇒ cover shows the whole photo). morphT endpoint snapping kept (still gates the tap-zone layer unmount + rect exactness).
- Considered and rejected: `BoxFit.fill` (distorts faces), `fitWidth` (letterboxes landscape). Adaptive height dominates both; no owner ask needed.

### 2. Manage-photos sheet rework

- `showGlassSheet(isScrollControlled: true)`; "Manage photos" title added above the PHOTO N OF M caption.
- Tray: fixed 64px strip → responsive 3-column tiles via `LayoutBuilder`: `tile = ((maxWidth - 3*12)/3).clamp(84, 148)` (~105px on a 390 phone). `_PhotoSlot` takes `size`; radius 18, star badge 22px, add-icon 30.
- `_ActionRow` gained `large` flag (non-dense, minVerticalPadding 10, fontSize 16) used only by the sheet's three rows. Reorder/set-main/add/delete + optimistic-order pattern unchanged.
- Trap fixed: `LayoutBuilder`'s `context` param shadowed the State's `context` inside the reorder rollback closure → `use_build_context_synchronously` lint (the `mounted` guard no longer matched). Param renamed to `_`.

## Tests

- Collapse test rewritten: asserts a SINGLE `BoxFit.cover` pager image (contain layer + backdrop must stay gone) expanded AND collapsed, bar-title fade unchanged. Test images never resolve (test HttpClient 400s) so the adaptive extent deterministically stays 300 — the adaptive path itself is verified visually, not by widget tests.
- Reorder test: drag distance now measured (`tester.getSize(slot).width + 12` pitch) since tiles are responsive (148px in the 800-wide test viewport — M3 sheet maxWidth 640 − padding).
- `flutter analyze` 0 issues; **full suite 729 passed**.

## Visual verification (harness, 390×844)

- Preview photos changed to mixed aspects (900/900, 800/1200, 1200/700) to exercise the adaptive hero. Square → 390px hero, portrait → clamped 520px (slight crop, full-bleed), landscape → 228px uncropped. Sheet rendered dark + light, both correct (primary selected hides "Set as main", shows main-photo hint).

## Deploy

- `deploy-web.ps1` ran CLEAN end-to-end for the first time (no exit-21 — owner's Kaspersky exclusions likely fixed it). `/version.json` 0.0.120, bundle contains `219dcaa`, `post-deploy-smoke.mjs` PASSED. Version deliberately NOT bumped: 0.0.120 is the PR's unreleased version until merge (prior owner-session decision); footer sha disambiguates builds.
- Prod backend still master 0.0.118 — drag-reorder still fails loudly on prod until merge (known).

## Still open

- Owner device confirmations: round-3 hero feel, sheet size, bug-3 keyboard, tap zones. Then merge PR #84 (explicit OK) → master deploy web + backend (migration 0008 + reorder endpoint).
- Before merge if styles are settled: strip `UserCardStyle.glassPanels`/`auroraTint`, `?style=` switch, `_StyledPanel` dead branches.
- Reviewer nit: card block-path could also pop the underlying chat (`chat_detail_screen.dart:781` area).
- `docs/design/landing-prototype/` remains untracked (other session's prototypes — never commit to this PR).

## ROUND 4 (same day, commit `c505049`, branch-deployed + smoke PASSED)

Owner: round-3 hero approved; sheet alright but three nits.

1. **Drag proxy white box**: `ReorderableListView`'s default proxy paints an opaque elevated Material behind the lifted tile → `proxyDecorator` returning `Material(type: transparency)`.
2. **Header avatar "halo not equal / circle is not a circle"** (image was a pinch-zoomed screenshot of OUR chat header): trailing r18 avatar sat inside a 48w×52h GlassPill — non-circular ring, off-center avatar. Fix: new `GlassTopBar.avatar` slot rendered BARE at 52px (photo fills the whole circle, Telegram-style); `chat_detail_screen.dart` moved from `trailing:` to `avatar:` with `radius: capsuleHeight/2`. [INFERENCE] surface identified by geometry match, not reproduction — if owner still sees a halo, re-check with them which screen produced the screenshot.
3. **Chats-tab plus halo bigger than "usertab"**: `MainTabScreenHeader` trailing GlassCircle 52 → 44 (matches user card's 44px action circles). Leading avatar circle stays 52.

Verified: analyze 0, suite 729 green, mid-drag harness screenshot shows no white box. Header/plus changes are deterministic size swaps (not visually rendered locally — chat screens aren't in the card harness).
