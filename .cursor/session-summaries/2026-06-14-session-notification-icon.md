# Notification icon — fix the white-square small icon on all push surfaces (0.0.56)

**Date:** 2026-06-14

## What was done
Root-caused and fixed the generic **white-square** notification small icon. The status-bar/small icon slot (web `showNotification` **`badge`**, native FCM/local **small icon**) is rendered by the platform using **only its alpha channel**, so it must be **white-on-transparent**. Both slots were pointing at full-colour, fully-opaque PNGs → their alpha mask is a solid block → white square:
- Web SW: `badge: '/icons/Icon-192.png'` (full-colour app icon).
- Native: `icon: '@mipmap/ic_launcher'` (full-colour launcher icon) in both `AndroidInitializationSettings` and `AndroidNotificationDetails`; no FCM default-icon meta-data in the manifest.

User supplied the real Fireplace brand artwork (campfire + shield tile). New assets generated from it:
- **Small/mono flame silhouette** (white-on-transparent, inner negative-space teardrop so it reads as fire at 24dp): Android `res/drawable-{mdpi..xxxhdpi}/ic_stat_fireplace.png` (24/36/48/72/96) + web `web/icons/notification-badge-96.png`. Verified every opaque pixel is pure white `(255,255,255)` and all else fully transparent.
- **Large full-colour icon** (notification body): the user's pre-cropped Fireplace campfire scene (no metallic frame/wordmark/white edges) → `web/icons/notification-icon-512.png` + `-192.png`. Square + circle-crop (Android) verified clean.

Wiring:
- `web/web-push-sw.js` `showNotification` (the one call): `icon` → `/icons/notification-icon-512.png`, `badge` → `/icons/notification-badge-96.png`. Same-origin absolute paths (resolve regardless of SW scope). No change to grouping/tap/deep-link/badge/clearing.
- `lib/services/android_fcm_local_notifications.dart`: both init `AndroidInitializationSettings('@drawable/ic_stat_fireplace')` (main + background isolate) and `AndroidNotificationDetails(icon: '@drawable/ic_stat_fireplace')`.
- `AndroidManifest.xml`: FCM `default_notification_icon` = `@drawable/ic_stat_fireplace`, `default_notification_color` = `@color/fireplace_notification_accent`.
- New `res/values/colors.xml` → `fireplace_notification_accent` = `#FF6A2C`.

Assets are committed PNGs (no build-time generation; a one-off Pillow script was used to draw the procedural flame + size the densities, then deleted as repo clutter on request).

CLAUDE.md: split the **Commits** rule (small/trivial → direct to `master`; bigger/substantial → feature branch + PR; feature branches do NOT auto-deploy, go live only after merge to `master`). Added a **Notification icons** gotcha documenting the white-square root cause + the monochrome-badge requirement + asset locations.

Scope kept to notifications only: PWA manifest/launcher (`ic_launcher`, `Icon-*.png`) untouched — still the old Flutter logo. iOS web push ignores `icon`/`badge` and shows the Home-Screen (manifest) icon — out of scope.

Version 0.0.55 → **0.0.56**.

## Key files
- `frontend/web/web-push-sw.js` (icon/badge)
- `frontend/lib/services/android_fcm_local_notifications.dart` (small icon ×3)
- `frontend/android/app/src/main/AndroidManifest.xml` (FCM meta-data)
- `frontend/android/app/src/main/res/values/colors.xml` (new)
- `frontend/android/app/src/main/res/drawable-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_stat_fireplace.png` (new)
- `frontend/web/icons/notification-badge-96.png`, `notification-icon-512.png`, `notification-icon-192.png` (new)
- `frontend/pubspec.yaml` (0.0.56), `CLAUDE.md`

## Verification
- `flutter analyze` → **No issues found** (full project, 31.6s).
- `flutter test test/screens/settings_screen_version_footer_test.dart` → **1 passed** (version bump clean; version is read at runtime).
- Asset audit (Pillow): mono icons = pure-white opaque pixels + fully-transparent elsewhere (alpha-only ✓); large icon circle-crop renders the campfire cleanly.
- No test references the old/new icon paths (grep `Icon-192|ic_launcher|notification-badge|notification-icon|ic_stat_fireplace|showNotification` in `test/` → none).
- **NOT YET device-verified** — see below.

## Notes for next session
- **Feature branch `fix/notification-icon` + PR — does NOT auto-deploy.** Goes live only after merge to `master` (VM pulls master). Merge, then `./deploy.sh` + `flutter clean` + verify `gitCommit` + PWA cache-bust.
- **Device matrix still owed (Untested = not done):**
  - Android Chrome PWA: status bar shows the white flame silhouette (no white square); notification body shows the full-colour campfire.
  - iOS Safari PWA: shows the Home-Screen icon (confirm it's the installed icon; `icon`/`badge` are ignored by iOS).
  - Native Android FCM (if exercised): status-bar small icon = flame; tinted with `#FF6A2C`.
  - Regression: delivery, grouping (one card/conv), tap/deep-link, badge count, clearing all unchanged.
- Optional future: rebrand the PWA/launcher app icon to the campfire too (currently still the Flutter logo) — deliberately out of scope here.
