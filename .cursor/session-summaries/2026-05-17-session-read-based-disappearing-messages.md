# Session: Read-based disappearing messages

**Date:** 2026-05-17

## Accomplished

- Approved spec `docs/superpowers/specs/2026-05-16-read-based-disappearing-messages-design.md`
- Implementation plan `docs/superpowers/plans/2026-05-16-read-based-disappearing-messages.md`
- Feature branch `feature/read-based-disappearing-messages` with full backend + frontend implementation
- Tests: backend 266 pass, frontend 126 pass, `flutter analyze` clean
- Commit `ae78741` (docs/plan/graphify/CLAUDE + cleanup); core code in `419b81e`

## Key behavior

- Read-mode: `disappearAfterSeconds` at send, `expiresAt` on `markConversationRead`
- Never-read cap: 1 day from `createdAt`
- D/H/M/S timer dialog (5s–30d, all zeros = off)
- Grandfathered send-time `expiresAt` unchanged

## Manual verify

- Two users: send with timer, recipient opens chat → both see countdown after read
- Never-read message >24h removed without opening
- Old messages with send-time expiry still expire as before
- Prod DB: `ALTER TABLE messages ADD COLUMN "disappearAfterSeconds" integer NULL;`

## Notes

- Uncommitted on branch: voice recording files (`chat_input_bar`, `recording_controller`) — separate from this feature
