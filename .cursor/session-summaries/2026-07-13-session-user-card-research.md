# User-card research and design brainstorm

**Date:** 2026-07-13

## What was done

- Researched the proposed Telegram-like user/contact card without changing application code, then closed the product decisions with the owner.
- Mapped current constraints: Fireplace exposes only `id`, `username`, immutable `tag`, and one `profilePictureUrl`; chat-header avatar taps currently reveal `username#tag` for five seconds; contact-row taps open or create a chat; the one-avatar upload path replaces and deletes the prior asset; per-conversation mute does not exist.
- Approved direction: normal Contact-tile tap opens User Card and trailing Message opens/starts chat; no-photo users get compact initial-avatar identity state; real photos get an image hero that collapses to primary avatar; `username#tag` is the sole identity; optional 80-character About; personal Default/plain or Glyphs wallpaper; private timed mute; later three-photo static gallery with top segmented indicator.

## Key files

- `frontend/lib/screens/chat_detail_screen.dart` — header avatar is the current contact-entry point.
- `frontend/lib/screens/contacts_screen.dart` — contact-row interaction currently opens chat.
- `frontend/lib/models/user_model.dart` — current minimal user payload.
- `frontend/lib/widgets/avatar_circle.dart` — current single-avatar renderer.
- `backend/src/users/user.entity.ts` — current single-avatar columns.
- `backend/src/users/users.controller.ts` — JPEG/PNG, 5 MB replacement-only avatar upload.

## Verification

- Planning/research only: no application source, tests, configuration, dependencies, or production environment changed.
- Confirmed no per-conversation mute implementation exists in frontend or backend source.

## Notes for next session

- Contact wallpaper is a per-user, per-conversation client preference: Default is plain and Glyphs renders the existing pattern. It never affects the peer or needs backend sync.
- Mute must not be faked locally: background Web Push/FCM requires a server-side per-user-per-conversation preference to suppress notification delivery.
- Gallery migration must preserve existing primary assets, delete removed old assets, and cleanly migrate every caller to the primary-photo model.
- Fresh-agent handoff now has a hard design gate: inspect and present route/UI/state/data/edge-case/test design, then stop for explicit owner approval before any implementation edit. Prompt research is at `docs/agents/implementation-agent-prompt.md`.
