# Settings About Fireplace link

**Date:** 2026-07-22

## What was done
- Added a compact footer action immediately above the Settings app-version block.
- Added a restrained FIREPLACE wordmark, localized “About” / “O projekcie” label, and external-link arrow without adding another settings tile.
- Wired the action to `https://fireplace.ignorelist.com/welcome/` with `LaunchMode.externalApplication` so the installed PWA is not replaced.
- Added a focused widget test with a fake URL launcher that verifies the exact URL and external launch mode.

## Key files
- `frontend/lib/screens/settings_screen.dart`
- `frontend/lib/l10n/app_en.arb`
- `frontend/lib/l10n/app_pl.arb`
- `frontend/test/screens/settings_screen_scroll_physics_test.dart`
- `frontend/pubspec.yaml`

## Verification
- `flutter test test/screens/settings_screen_scroll_physics_test.dart`: 2 passed.
- `flutter test test/screens/settings_screen_version_footer_test.dart`: 1 passed.
- `flutter analyze --no-fatal-infos`: 0 issues.
- Rendered and inspected the footer at 390×844 in Cosmic, Blue, Dark, Light, and Teal themes; also checked Light at 320×700.
- `graphify update .`: 9089 nodes, 12992 edges, 518 communities.

## Notes for next session
- Bumped the frontend from 0.0.124 to 0.0.125 and merged PR #94 into `master` via merge commit `eb4ba89`.
- CI passed backend tests and the full Flutter analyze/test job.
- Deployed the resulting `master` bundle and reran the production smoke checks successfully.
