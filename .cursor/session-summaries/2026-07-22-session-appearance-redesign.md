# Appearance settings redesign

**Date:** 2026-07-22

## What was done
- Replaced the contradictory Theme / Chat background / Cosmic starfield controls with one preview-backed **Appearance** tile and a dedicated Appearance screen.
- Kept Cosmic as a color theme. The new per-user background preference is `themeDefault`, `plain`, or `glyphs`; Cosmic + Theme default resolves to the animated starfield, while every other Theme default resolves to plain.
- Added real miniature chat previews for all five themes and all three background choices. Removed generic palette/sparkle/theme-choice icons from this flow.
- Replaced `cosmicStarfield` plus `ChatWallpaper` with one per-user preference and explicit render layers (`plain`, `glyphs`, `starfield`). Auth explicitly keeps its forced Cosmic starfield and does not read chat wallpaper state.
- Migrated legacy absent/`default`/`glyphs` wallpaper values and the global `cosmic_starfield_enabled` value. New persisted values are `theme_default`, `plain`, and `hieroglyphs`; the distinct glyph value prevents old Cosmic users from skipping migration.
- Kept the inert global legacy starfield key as migration input for accounts that have not logged in on this device yet. Deleting it after the first account would corrupt later per-user migration.
- Added an opt-in `GlassTopBar.titleHorizontalInset` so Appearance remains readable at 320px without changing existing top bars.
- Added a scaffold-tinted top fade to prevent bright cross-theme previews bleeding through the floating chrome while scrolling. The Hieroglyphs thumbnail renders the real painter on a denser logical canvas so it is visibly different from Plain.
- Updated English/Polish localization and generated localization classes.
- Committed and pushed as `c11a105` on `feat/appearance-redesign`; tracked LATEST index follow-up `f5c9aa6`.
- Opened PR #94: `https://github.com/Lentach/Fireplace/pull/94`.

## Key files
- `frontend/lib/models/chat_background_preference.dart`
- `frontend/lib/providers/settings_provider.dart`
- `frontend/lib/screens/appearance_screen.dart`
- `frontend/lib/screens/settings_screen.dart`
- `frontend/lib/screens/chat_detail_screen.dart`
- `frontend/lib/screens/auth_screen.dart`
- `frontend/lib/widgets/appearance_preview.dart`
- `frontend/lib/widgets/chat_background_pattern.dart`
- `frontend/lib/widgets/glass/glass_top_bar.dart`
- `frontend/test/providers/settings_wallpaper_test.dart`
- `frontend/test/screens/appearance_screen_test.dart`
- `docs/design/cosmic/appearance-redesign-*.png`

## Verification
- `flutter analyze --no-fatal-infos` — 0 issues after final visual refinements.
- Focused appearance/background/theme tests — 22 passed.
- Final visual-refinement tests (`appearance_screen_test.dart`, `glass_top_bar_test.dart`) — 3 passed.
- Full `flutter test` — 775 passed, 4 existing skips.
- Rendered and inspected Light, Teal Stone, Wire, Blue, and Cosmic at 390×844; Cosmic also at 320×700 and in a scrolled background-choice state.
- Read-only design review: mergeable. Its top-chrome bleed and Hieroglyph-preview findings were fixed; follow-up review confirmed both resolved.
- `graphify update .` — 9081 nodes, 12983 edges, 533 communities.
- Ephemeral production frontend deploy from `f5c9aa6` succeeded. `/version.json` remains `0.0.124`; `/health` is OK; post-deploy smoke confirmed the served bundle contains `f5c9aa6` and Flutter boots.

## Notes for next session
- Work is on `feat/appearance-redesign`. Do not merge to `master` without explicit owner approval.
- The feature-branch bundle `f5c9aa6` is live at `https://fireplace.ignorelist.com` for owner testing. Fully close and reopen the PWA; do not uninstall or clear site data.
- No version bump: this is an unmerged feature branch. Bump PATCH only when approved for release/merge.
- `cosmic_starfield_enabled` is no longer runtime state. It deliberately remains in SharedPreferences only as a migration source for dormant accounts; each account gets an explicit new per-user value when loaded.
- Starfield remains unavailable as an explicit background under non-Cosmic themes; those combinations have not been contrast-tested.
