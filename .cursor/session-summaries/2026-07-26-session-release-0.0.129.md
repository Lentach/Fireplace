# Release 0.0.129 — contact-network merged to master + branch cleanup

**Date:** 2026-07-26

## What was done
1. Owner gave the explicit release OK ("lets clean up branches make a pr and merge it if no issueas lets start clean"). PR #97 already existed and was CLEAN with both CI jobs green.
2. Bumped `frontend/pubspec.yaml` 0.0.128 → 0.0.129 as the LAST commit on `feat/contact-network` (`1235bcb`), pushed.
3. Merged PR #97 (merge commit `9d24d7b`, 50 commits, +6177/−874 over 51 files). `feat/contact-network` deleted local + remote by the merge.
4. Deployed master from the PC via `deploy-web.ps1` — built `0.0.129`/`9d24d7b`, published by atomic swap, `/version.json` verified. Backend intentionally untouched at 0.0.127/`3861166`.
5. `post-deploy-smoke.mjs`: **5/5 PASS** (`/health`, `/version.json` 0.0.129, `/version`, bundle literally contains `9d24d7b`, app boot).
6. Branch cleanup ("start clean"): deleted all 17 fully-merged local branches (`chore/frontend-cleanup`, `docs/*` ×2, `feat/app-logo`, `feat/appearance-redesign`, `feat/landing-page`, `feat/login-cosmic`, `feat/user-card-rework`, `fix/*` ×6, `refactor/*` ×2, `work`) plus force-deleted `feat/cosmic-theme` — its single unmerged commit `1745a50` was only a `?density=` knob on the starfield preview harness (recoverable via reflog). Local branches now: `master` only.

## Key files
- `frontend/pubspec.yaml` (0.0.129)
- Everything else was already on the branch — see `2026-07-25-session-console-glyphs.md`. (`2026-07-25-HANDOFF-START-HERE.md` was deleted 2026-07-27 as banner-marked SUPERSEDED; the release it gated shipped.)

## Verification
- PR #97 pre-merge: `mergeable: MERGEABLE`, `mergeState: CLEAN`, Backend tests + Flutter analyze/tests both SUCCESS.
- Post-deploy smoke 5/5; served `main.dart.js` literally contains `9d24d7b`.
- `git branch --merged master` drove the deletions — only `feat/cosmic-theme` needed `-D`, and only after inspecting its lone commit.

## Notes for next session
- **0.0.129 / `9d24d7b` is the permanent production frontend.** Owner should fully close + reopen the PWA (never clear site data — wipes E2E keys).
- The two open questions from the branch survive the merge, unresolved by design: the `appearance` glyph renders nowhere (live preview owns the row slot), and `push` is the one glyph the owner never explicitly picked. Owner's forks; do not guess.
- Deferred, none promised: honeycomb `ListView` rewrite for >200 contacts, "sent invites as ghosts" (backend change), Chats `+` honeycomb picker, three declined Standards refactors (recorded in `85a04dc`'s message).
- Owner's next ask: help design "something else" — new design work incoming, subject unknown at time of writing.
