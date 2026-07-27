# Remove "update available" stale-bundle nudge

**Date:** 2026-07-24

## What was done
User: the top-of-screen "Update available — fully close and reopen the app."
banner shown on app entry is annoying; delete it, commit, push, deploy to master.

1. `frontend/lib/screens/main_shell.dart`: removed the stale-bundle nudge —
   the `_staleNudgeShown` static flag + doc comment, the `kIsWeb` post-frame
   `addPostFrameCallback(_nudgeIfBundleStale)` hook in `initState`, the
   `_nudgeIfBundleStale()` method, and the `services/update_check.dart` import.
   `showTopSnackBar` import kept (still used by the friend-accepted toast).
2. Deleted orphaned service (only the nudge called `isServedBundleNewer`):
   `frontend/lib/services/update_check.dart`, `update_check_stub.dart`,
   `update_check_web.dart`.
3. Removed the now-unused l10n key `updateAvailableCloseReopen` from
   `app_en.arb` + `app_pl.arb`, then `flutter gen-l10n` regenerated
   `app_localizations*.dart` (getter gone from all three).
4. `docs/ISSUE-BOARD.md`: removed the resolved `In-app "update available /
   reload" banner` row.
5. Bumped `frontend/pubspec.yaml` 0.0.127 → 0.0.128 (production release, §5).
6. `graphify update .` after the code changes (§30).

Work was redone directly on `master` (the working copy had been left on
`feat/contact-network`, whose l10n additions were entangled with these files).

## Key files
- `frontend/lib/screens/main_shell.dart`
- `frontend/lib/services/update_check{,_stub,_web}.dart` (deleted)
- `frontend/lib/l10n/app_en.arb`, `app_pl.arb`, `app_localizations*.dart`
- `frontend/pubspec.yaml`, `docs/ISSUE-BOARD.md`

## Verification
- `flutter analyze lib/screens/main_shell.dart lib/l10n` → No issues found.
- `git grep updateAvailableCloseReopen|update_check|isServedBundleNewer` over
  `frontend/lib` → no matches.
- `graphify update .` → 9218 nodes.
- Production deploy via `deploy-web.ps1` + post-deploy smoke.

## Notes for next session
- Reverts PR #96's stale-bundle nudge only. Underlying stale-PWA reality
  unchanged — users still must fully close + reopen after a deploy to activate a
  new service worker. Never uninstall / clear site data (wipes E2E keys).
- Live frontend now 0.0.128; backend unchanged (0.0.127).
