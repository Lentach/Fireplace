# Session 2026-05-22 — Portrait-only orientation

## Accomplished

- Locked Fireplace to portrait-up on phones/tablets (Android manifest, iOS plist, `SystemChrome`, web Screen Orientation API best-effort).
- Added `PortraitLockShell` + `PortraitRequiredOverlay` (PL/EN) when landscape and `shortestSide < 900`; desktop web wide screens unchanged.
- Spec + implementation plan in `docs/superpowers/specs/` and `docs/superpowers/plans/`.
- Version bump `0.0.2+2`; verified on Android emulator after full reinstall.

## Key files

- `frontend/lib/services/portrait_lock_service.dart`, `web_orientation_lock_*.dart`
- `frontend/lib/widgets/portrait_lock_shell.dart`, `portrait_required_overlay.dart`
- `frontend/lib/utils/portrait_lock_policy.dart`
- `frontend/android/app/src/main/AndroidManifest.xml`, `frontend/ios/Runner/Info.plist`
- `CLAUDE.md`

## Notes for next session

- Manifest/plist changes require full `flutter run` (not hot reload). Uninstall old APK if rotation persists.
- Web tabs may still rotate; overlay is the reliable UX layer.
