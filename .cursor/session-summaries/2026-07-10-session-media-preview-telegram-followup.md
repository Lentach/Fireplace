# Telegram-like media preview follow-up deployed for device testing

**Date:** 2026-07-10

## What was done

- Corrected the 0.0.103 regression reported from a production device screenshot: low-resolution GIFs rendered as tiny squares because `MediaPreviewFrame` divided intrinsic pixel width by `devicePixelRatio` and then clamped the result to 96px.
- Changed dimensioned IMAGE/GIF previews to scale ordinary and low-resolution media to the bounded chat width while preserving source aspect ratio and `BoxFit.contain`.
- Reduced tall-media geometry from a 480px / 65%-viewport cap to 400px / 52%-viewport so portrait screenshots do not dominate the chat.
- Kept the 3:1 panorama and 1:2 portrait ratio bounds, letterboxing, and 220px legacy fallback for messages lacking dimensions.
- Added a 1.25px theme-aware outline around media bubbles, matching the Telegram reference while using Fireplace sender/theme colors.
- Bumped the frontend from 0.0.103 to 0.0.104, committed as `fef8fdf`, pushed the existing `fix/media-preview-aspect-ratio` branch, and updated PR #58.
- Deployed the feature-branch frontend to production for owner device testing before merge, as explicitly requested.

## Key files

- `frontend/lib/widgets/message/media_preview_frame.dart` — full bounded-width scaling and smaller tall-media cap.
- `frontend/lib/widgets/message/chat_message_bubble.dart` — theme-aware media outline.
- `frontend/test/widgets/message/{media_preview_frame_test,bubble_redesign_test}.dart` — regression coverage for low-resolution scaling, tall bounds, and outline.
- `frontend/pubspec.yaml` — version 0.0.104.

## Verification

- Red-capable repro before the fix: `flutter test test/widgets/message/media_preview_frame_test.dart --plain-name "scales low-resolution media to the bounded chat width"` failed with expected width 320, actual width 96.
- Focused `media_preview_frame_test.dart` + `bubble_redesign_test.dart` — 16 passed after the fix.
- `flutter analyze --no-fatal-infos` — no issues.
- `flutter build web --release --no-wasm-dry-run` — succeeded.
- Independent GPT-5.5 review — PASS; no correctness, layout, privacy, accessibility, or test blocker.
- Production `/version.json` — 0.0.104.
- Production `/health` — `{status: ok, db: ok}`.
- `node scripts/smoke/post-deploy-smoke.mjs --commit fef8fdf` — health, both version surfaces, served bundle SHA, and fresh Chromium Flutter boot all passed.

## Notes for next session

- Owner must fully close and reopen the PWA without uninstalling or clearing site data, then compare the same GIF/image cases. Clearing site data would destroy local Signal keys.
- PR #58 remains open and unmerged. Production currently serves the feature-branch frontend `fef8fdf` solely for owner testing; a normal master deploy is required after merge.
- The backend was not redeployed because this follow-up is frontend-only; public backend remains healthy at 0.0.98 / `d8cf61c`.
