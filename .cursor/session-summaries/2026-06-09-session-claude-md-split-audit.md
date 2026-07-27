# CLAUDE.md split — tier-read rule + accuracy audit (docs/claude-rebuild)

**Date:** 2026-06-09

## What was done
Working tree switched to branch **`docs/claude-rebuild`** mid-session, which carries the **already-split** CLAUDE.md (root + `frontend/CLAUDE.md` + `backend/CLAUDE.md`) and newer code (328 tests/41 suites, message editing shipped, Web Audio voice path). This supersedes the monolithic root CLAUDE.md on `master`.

1. **Injection behaviour confirmed empirically:** only the **root** CLAUDE.md is auto-injected each prompt (the harness loaded root only at session start; tier files were absent until read). Tier files load on demand. So "don't inject big files every prompt" is already satisfied.
2. **Root hard-rule (commit `49253c7`):** header now states source-of-truth = root + 2 tier files, with an explicit rule: *read the matching tier file once before your first change in that tier, then keep it in context — do not re-read every edit.* Agent-agnostic (works for Claude Code / Cursor / Codex regardless of any tool's implicit nested-load).
3. **Tier-file audit vs this branch's source** — sampled ~30 falsifiable claims; all accurate **except one**:
   - **BUG (fixed, `49253c7`):** `frontend/CLAUDE.md` referenced `utils/instant_opaque_route.dart` (§2 nav) and `test/utils/instant_opaque_route_test.dart` (§1) — **neither exists** anywhere in the repo. Actual chat nav is a plain `MaterialPageRoute → ChatDetailScreen(conversationId:)` from Conversations/Contacts/MainShell. Corrected both.
   - Verified accurate: 7 providers; message editing (`editedAt` col, `editMessage`, `EditPreviewBar`, `messageEditEligible`, reasons `not_sender`/`window_expired`/`not_text`/`not_found`); Web Audio voice files (`ping_sound_web.dart`, `voice_player_web.dart`); `sig_` key prefix + `SharedPreferencesAsync`; main.dart init order; all PS scripts; `main.ts` helmet/ValidationPipe(whitelist)/trust-proxy/CORS; reactions throttle 120/15min; media upload 20/min + 21 MiB; push coalescer `DEBOUNCE_MS=2500`/`MAX_WAIT_MS=10000`; 10 `chat-*.service.ts` (9 domain + `chat-validation`); `WsThrottlerGuard`; `MEDIA_URL_REGEX`; backend test count 328/41 (verifier passes).

## Key files
- `CLAUDE.md` (root) — source-of-truth header + workflow rule
- `frontend/CLAUDE.md` — instant_opaque_route fix (§1, §2)

## Verification
- `node scripts/verify-claude-backend-test-counts.mjs` → `OK: CLAUDE.md matches Jest (328 tests, 41 suites)`
- Grep/Glob sweep across `frontend/lib`, `frontend/test`, `backend/src` — every cited symbol/file/number confirmed except instant_opaque_route (fixed).

## Notes for next session
- **Branch story:** `docs/claude-rebuild` is the intended future (split + current). My 3 earlier `master` commits (`6e47353`, `c4284df`, `282ddc2`) edited the old monolithic root file and are **orphaned/redundant** — everything they added already exists (usually better) in the split tier files. When `docs/claude-rebuild` merges, it replaces the monolithic file; the master docs commits can be discarded. Nothing unique to port.
- Not exhaustively re-verified on this branch: `LocalStorageService` path-containment check, exact push payload field list, a few §-level prose claims — all plausible, symbols exist, low risk.
- Docs-only; no code touched, no version bump, no `graphify update` needed.
