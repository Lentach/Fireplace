# Liquid Glass redesign — Stage A accepted + Stage B IMPLEMENTED (PR open)

**Date:** 2026-07-10/11

## What was done

- **Stage A (design session), owner-accepted:** 3 mockup directions (real backdrop blur HTML, faithful app anatomy) at `docs/design/liquid-glass/round1/index.html`; owner accepted ALL directions mapped onto the 4 existing themes (blue→Nightfall-dark, dark→TealSmoke-dark, light→Hearthglow-light, teal→TealSmoke-light), flame wallpaper default. Spec: `docs/design/liquid-glass/SPEC.md` — glass recipe (σ22 + saturate ×1.7), per-theme values, capsule metrics, wallpaper tile, opaque fallbacks, computed WCAG 28/28 ≥4.5:1 worst-case. Disclosed deltas: blue sent bubble →`#1F74BB`, teal sent →`#0F766E`, slight base tones.
- **Package eval:** `liquid_glass_widgets 0.21.3` REJECTED (owner-approved): web needs exact composition or silently misrenders (harness observation), per-widget settings ignored in its safe mode, Impeller-only extras dead on the web-first PWA, pre-1.0 churn, slightly slower than plain BackdropFilter. Hand-rolled `GlassSurface` adopted.
- **Perf spike, GO:** desktop web release full-5-surface chrome 1.52ms raster avg / 0.1% jank; **owner's real iPhone: 0% jank** (hand5 1.08/2/2ms, 363f). Android emulator functional-only. `docs/design/liquid-glass/SPIKE.md`.
- **Stage B implemented** (branch `feat/liquid-glass-redesign`, commits `012cb45..`):
  - `GlassTheme` ThemeExtension (4 themes, field-wise lerp) + `GlassSurface`/`GlassPill`/`GlassCircle` (ClipRRect+BackdropFilter blur σ22+sat1.7, RepaintBoundary, `forceOpaque` per-surface + `MediaQuery.highContrast` reactive fallback + compile-time `--dart-define=REDUCE_TRANSPARENCY=true` kill-switch).
  - Chat list: `GlassBottomNav` (66px pill, active capsule, single-node semantics, keyboard focus, ≥48px targets), floating `MainTabScreenHeader` capsules, scroll-behind list, nav clearance in all tabs incl. empty states.
  - Chat screen: `GlassTopBar` + `extendBodyBehindAppBar` (pinned-banner/list clearance PROVEN by `chat_detail_glass_chrome_test` on the real screen), flame-doodle wallpaper (`ChatBackgroundPattern` rewrite), composer input row = floating glass pill (TapRegion/FocusGuard structure untouched), `ChatActionTiles` glass pill with hit-testing gutter (keyboard mis-tap contract kept — caught by existing test), date mini-pills.
  - Modals: `showGlassSheet` (transparent route, radius-26 glass; `opaque:` mode) — timer, contacts menu, anti-quantum glass; GIF picker opaque-by-design. Banners (reply/edit/timer) = floating rounded cards, RTL-aware accent, 48px dismiss. Popup menus/dialogs = rounded per-theme surfaces (NOT glass — framework routes; owner to ratify at PR review; status table in SPEC §9).
  - **Owner accent complaint fixed:** `ConversationTile` active row = `GlassTheme.activeCapsule`, muted = `FireplaceColors.mutedText` — orange stays in ember theme, green in teal (screenshot-verified all 4 themes).
- Version bump 0.0.106, graphify updated (8360 nodes).

## Key files

- `frontend/lib/theme/glass_theme.dart`, `frontend/lib/widgets/glass/*` (surface/nav/top-bar/sheet)
- `docs/design/liquid-glass/{SPEC.md,SPIKE.md,round1/,after/}` — spec, measurements, mockups, real-app after-screenshots (5, incl. teal accent proof)
- `frontend/test/preview/glass_preview.dart` — dev visual harness + `?bench=1` FrameTiming bench (real ChatDetailScreen)
- Tests: `test/widgets/glass/*` (15), `test/screens/chat_detail_glass_chrome_test.dart` (geometry proofs)

## Verification

- `flutter analyze --no-fatal-infos`: only the pre-existing `jumbo_emoji` info. Full suite **657 passed** (3 consecutive full runs green; timer-sheet tests now exercise the production glass opener).
- Visual: real app screenshots match accepted mockups (4 themes × list/chat; ConversationsScreen desktop branch visually checked — full MainShell desktop integration rides device QA; action panel verified via real chevron click).
- Final real-screen release scroll bench: 504 frames, raster p99 12.6ms PASS; total-span jank 5.2% = **MARGINAL FAIL vs the 5% run-adopted criterion** (recorded honestly in SPIKE.md; browser unrecorded — default system browser; phone gate 0% stands). **Owner ratification of this + the not-glass menu/dialog deviations = open PR gates.**

## Notes for next session

- PR open on `feat/liquid-glass-redesign`; NOT merged. Owner gates: (1) marginal desktop bench, (2) menus/dialogs not glass, (3) device QA via branch deploy (`flutter clean; .\deploy-web.ps1` on the branch per CLAUDE.md §4).
- PARALLEL SESSION note: an E2E incident investigation (saraLee, release-blocker fix) wrote its own LATEST entry concurrently — do not clobber; its fix outranks this redesign for release order.
- Emoji picker + settings tiles intentionally untouched (SPEC §9). `.spike/spike_glass` = reproducible perf harness (tracked sources only).
