# 2026-07-13 — User Card / My Profile implementation
**Date:** 2026-07-13


## What was done
- Added the approved User Card entry paths: contact-row opens the card; trailing Message opens or starts chat; chat-header avatar opens the card; Settings exposes My Profile.
- Added compact generated-initial identity for users without a photo; uploaded primary profile photos get a full-width hero that collapses to the stable primary circular avatar.
- Added optional 80-character About, copyable immutable `username#tag`, a static three-photo gallery with primary ordering, pager segments, owner set-main/delete actions, and asset deletion during replacement/deletion/account cascade.
- Added personal local conversation wallpaper state (`Default` plain / `Glyphs` existing pattern) persisted by viewer + conversation.
- Added private per-viewer, per-conversation timed notification mute storage/API/socket propagation and push-coalescing enforcement. Expired mute rows are treated as unmuted.
- Added `0006_conversation_notification_preferences.sql` and `0007_user_profile_about_and_photos.sql`.
- Localized the User Card controls in English and Polish.

## Key files
- Backend: `backend/migrations/0006_conversation_notification_preferences.sql`, `backend/migrations/0007_user_profile_about_and_photos.sql`, `backend/src/users/profile-photo.entity.ts`, and `backend/src/users/user.entity.ts`.
- Frontend: `frontend/lib/screens/user_card_screen.dart`, `frontend/lib/screens/contacts_screen.dart`, and `frontend/lib/services/api_service.dart`.

## Review remediation
- Removed the obsolete single-avatar replacement/deletion service path after gallery storage became the sole profile-photo source. The rebased final backend baseline is `470 tests / 47 suites`.
- Moved destructive contact operations to confirmed User Card safety actions; Contacts retains its long-press menu, preserving the existing removal/block semantics.
- The conversation list now derives and renders the muted-notifications indicator from the current viewer’s `muted` / `mutedUntil` payload, treating expired rows as unmuted.
- Deleting a gallery photo now requires explicit confirmation. Card feedback and interactive labels use localized ARB strings; `ListTile` action sections use `Material`, preserving ripple/semantic behavior.
- Added focused tests for expired/forever mute evaluation, the conversation-row muted indicator, and both card deletion confirmations.
- Fixed the review-found contact-gallery gap: `FriendsService.getFriends` now loads each friend’s `profilePhotos`, so the Contacts tab’s primary User Card route receives the gallery—not only the chat-header route.
- Added cleanup for an uploaded asset when profile-photo persistence fails, preventing an orphaned self-hosted file in a concurrent/max-gallery rejection path.
- Made profile-photo row creation and the legacy primary-avatar pointer update one transaction. A locked, in-transaction photo query now serializes uploads per user, preserving both the three-photo cap and single-primary invariant before the controller can clean up a rejected upload.

## Production deployment
- Rebased the release onto current `master`, then bumped the release from the already-released `0.0.111` to `0.0.112`.
- Backed up production PostgreSQL, media, and encrypted `.env` before deploying. The current encrypted database dump is `chatdb-20260713T202644Z.dump.gpg`.
- Renumbered the new migrations from colliding `0003`/`0004` names to `0006`/`0007`, after master already introduced migrations through `0005`.
- The first backend deploy exposed a real TypeORM metadata failure: nullable `string | null` columns emitted `Object` design metadata. Declared the profile fields explicitly as `varchar`/`text`, added a metadata-initialization regression test, and redeployed successfully.
- Production backend and PWA now serve `0.0.112` / runtime commit `a10ae1c`. Both `0006` and `0007` are recorded in production `schema_migrations`.

## Verification
- `npm run build` in `backend`: passed.
- `npm test -- --runInBand` in `backend`: 47 suites, 470 tests passed after the rebased recovery fix.
- `flutter analyze lib/models/conversation_model.dart lib/providers/conversations_provider.dart lib/providers/connection_provider.dart`: passed.
- `flutter analyze lib/screens/chat_detail_screen.dart lib/screens/contacts_screen.dart lib/screens/user_card_screen.dart`: passed.
- `flutter analyze lib/screens/user_card_screen.dart test/screens/user_card_data_test.dart`: passed after the expired-mute mapping fix.
- `flutter test test/screens/user_card_data_test.dart`: 4 focused card-data tests passed (no avatar, legacy primary, normalized gallery ordering, expired/timed mute).
- `flutter test` in `frontend`: 679 tests passed after rebasing onto current `master`.
- Complete `flutter analyze --no-fatal-infos` reports two pre-existing unrelated infos: `lib/screens/privacy_safety_screen.dart:416` and `lib/utils/jumbo_emoji.dart:24`; no User Card diagnostics.
- Focused card/model/tile tests: 13 passed.
- `node scripts/verify-claude-backend-test-counts.mjs` confirmed `CLAUDE.md` matches Jest at 470 tests / 47 suites.
- Repaired the non-production `tool/user_card_preview.dart` after its `MaterialApp` omitted generated localization delegates. `flutter analyze tool/user_card_preview.dart` passed.

## Notes for next session
- Public production checks passed: `/health` reports `{"status":"ok","db":"ok"}`; `/version` reports `0.0.112` / `a10ae1c`; `/version.json` reports `0.0.112`.
- `scripts/smoke/post-deploy-smoke.mjs --commit a10ae1c` passed health, both version surfaces, the served bundle SHA, and a fresh Chromium Flutter boot. Authenticated manual User Card paths were not exercised because this session had no production test account.
