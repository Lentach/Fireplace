# Split root CLAUDE.md into nested backend/ + frontend/ files

**Date:** 2026-06-21

## What was done
Executed the approved plan to split the single 316-line root `CLAUDE.md` (marked `alwaysApply: true`, so its whole bulk loaded every session) into three files: a slim root holding only cross-cutting content, plus tier-specific `backend/CLAUDE.md` and `frontend/CLAUDE.md` (Claude Code auto-loads a directory's `CLAUDE.md` when working under it). Move-verbatim operation — no rewording except the agreed drift fixes and cross-file ref edits.

- **`frontend/CLAUDE.md`** (new, 158 lines): H1 + `../CLAUDE.md` pointer block, then §1 Critical Rules & Gotchas (`### Frontend`, `### E2E Encryption (client)`), §2 Architecture (providers & services), §3 File Location Map (frontend), §4 Runtime Behaviors (Optimistic/Blocking/Navigation), §5 Screens & Widgets, §6 Known Limitations (8 client bullets + Android 16KB + split send.dart bullet, `~1052` LOC dropped).
- **`backend/CLAUDE.md`** (new, 86 lines): H1 + pointer block, then §1 (`### TypeORM`, `### Backend`), §2 Architecture (backend; `~489 LOC` dropped from ChatGateway), §3 File Location Map (backend), §4 Database Schema, §5 Known Limitations (secret_notes NODE_ENV + large backend files). Reactions bullet's dangling `(§7)` → `(see frontend/CLAUDE.md)`.
- **Root `CLAUDE.md`** (316 → 114 lines): frontmatter (verbatim, load-bearing), Rules block, new tier-pointer block, §0 Quick Start (contains the load-bearing `307 unit tests, 40 suites` line — kept in root for CI), §1 Architecture Topology, §2 How-To, §3 Shared Wire Contracts (E2E envelope + Delete actions table), §4 Environment & Config, maintenance footer (extended to cover the new files).
- **`.cursor/rules/On-every-check.mdc`**: pointer line updated so Cursor (no nested auto-discovery) reads the tier files too.

## Key files
- `CLAUDE.md` (rewritten slim)
- `backend/CLAUDE.md` (new)
- `frontend/CLAUDE.md` (new)
- `.cursor/rules/On-every-check.mdc` (one-line edit)

## Verification
- **No content lost:** `search` confirmed each load-bearing string present once in its expected file — frontend (`Media keys are one-shot`, `visualViewport`, `DualStorage`, `Decrypt ordering`, `Context menu (long-press)`, `Optimistic messaging`), backend (`MEDIA_URL_REGEX`, `guarded disconnect`, `Delete account cascade`, `friend_requests.status`, `Pre-key anti-depletion`), root (`E2E envelope`, `Delete Conversation`, `Quick Start`, `307 unit tests, 40 suites`, `Environment & Config`).
- **No dangling cross-file refs:** `search` `§` across all three files → only `(see §1)` in backend §4, which resolves to backend §1 (Delete account cascade). Zero `§7` remaining.
- **CI gate green:** `node scripts/verify-claude-backend-test-counts.mjs` → `OK: CLAUDE.md matches Jest (307 tests, 40 suites)` (37s; runs backend `npm test`). Count unchanged; script still reads the root file.
- **Line counts:** root 114 (was 316), backend 86, frontend 158.

## Notes for next session
- Both nested files are plain `CLAUDE.md` (no frontmatter) — Claude Code auto-discovers them; Cursor relies on the On-every-check pointer.
- Maintenance contract: tier-specific gotchas now go in `backend/CLAUDE.md` / `frontend/CLAUDE.md`; the `307 unit tests, 40 suites` string MUST stay in root §0 or CI breaks.
- Two volatile LOC counts were intentionally dropped (ChatGateway ~489, send.dart ~1052) rather than maintained.
- Docs-only change — no version bump (per version-bump rule; trivial/non-code). Not yet committed.
