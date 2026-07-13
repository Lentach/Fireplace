# Latest session summary

**Date:** 2026-07-13 (User Card / My Profile — production release `0.0.112`)

## What was done
- Delivered the approved User Card / My Profile vertical slice: Contact-row card entry with direct Message action, chat-header card entry, My Profile, compact no-avatar identity, photo hero/collapse, immutable copyable `username#tag`, optional About, and three-photo gallery.
- Added local per-viewer/per-conversation Default/Glyphs wallpaper and private timed mute preferences that suppress server-side push coalescing.
- Rebased onto current `master`, fixed migration-number collisions by using `0006` and `0007`, and released `0.0.112`.
- Recovered the first production backend deploy after TypeORM rejected reflected `Object` metadata for nullable profile strings. All affected profile columns now declare explicit PostgreSQL types; `profile-photo.entity.spec.ts` makes metadata initialization a regression contract.

## Key files
- `backend/migrations/0006_conversation_notification_preferences.sql`
- `backend/migrations/0007_user_profile_about_and_photos.sql`
- `backend/src/users/profile-photo.entity.ts`
- `backend/src/users/profile-photo.entity.spec.ts`
- `frontend/lib/screens/user_card_screen.dart`

## Verification
- Backend: `npm run build`; full Jest **47 suites / 470 tests**; documented-count verifier passed.
- Frontend: full `flutter test` **679 tests**; analyze reports only two pre-existing non-User-Card infos at `privacy_safety_screen.dart:416` and `jumbo_emoji.dart:24`.
- Production: encrypted PostgreSQL/media/`.env` backup completed before release; both new migrations are recorded in production `schema_migrations`.
- Public `/health` is `{"status":"ok","db":"ok"}`; frontend `/version.json` is `0.0.112`; backend `/version` is `0.0.112` / runtime commit `a10ae1c`.
- `scripts/smoke/post-deploy-smoke.mjs --commit a10ae1c` passed endpoint checks, served-bundle SHA, and a fresh Chromium Flutter boot.

## Notes for next session
- Authenticated manual User Card actions were not exercised in production because no production test account was available. The deployed unauthenticated PWA boot and all server/schema contracts passed.
- The detailed dated handoff remains local-only by repository policy; this tracked summary is the public cross-session record.

## Previous
- 2026-07-12: stale-OTP identity-epoch hardening, cache durability, and diagnostics landed before this release. The merged wallpaper glyph work and its migration sequence are already included in `0.0.112`.
- Production VM previously tracked `fix/stale-otp-epoch`; this release restored `~/fireplace` to `master` before deployment. Do not switch it back to a stale feature branch.
