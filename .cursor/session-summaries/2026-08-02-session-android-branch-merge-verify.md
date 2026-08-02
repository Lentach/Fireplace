# Android branch levelled with master, and verified rather than assumed

**Date:** 2026-08-02

## What was done

Owner asked for a clean merge plus proof that the merges already done had not broken
anything. Both delivered on `feature/android-encrypted-store`.

- **Found the gap the previous session's handoff missed.** The handoff claimed a fresh agent
  "hits the pointer on their mandatory LATEST.md read". That was true only in the master
  worktree. `2026-08-02-HANDOFF-post-incident-state.md` existed solely in `70eff73` on master
  and was **absent from the Android branch entirely** (`git cat-file -e 9c1d476:<path>` → not
  in tree), while the owner's main copy sat 13 commits behind its own remote at `a2e94ee`,
  whose `LATEST.md` still opened with `⚠ P0 INCIDENT OPEN … Step 0 is a frontend rollback to
  a00ab0f` — a live rollback instruction for a fix that had shipped and been confirmed.
- **Merged master `70eff73` into the branch** (clean fast-forward of the branch ref). One
  conflict, `LATEST.md`, resolved to master's rewrite: master had already folded the 0.0.139
  release facts into the 0.0.140 entry, so keeping both sides would have meant six entries and
  two copies of the same incident narrative. Every other file auto-merged.
- **Corrected three now-false verified-state claims in the same commit** (root `CLAUDE.md` §1:
  source wins, fix the doc alongside). The handoff table said `master = 3a33bf9` and
  `feature/android-encrypted-store = 9c1d476, 0 commits behind`; `LATEST.md` L11 pinned the
  same dead SHA. Both now pin **master** and instruct the reader to re-derive the branch tip,
  because a tip SHA cannot be recorded inside the commit that creates it.

## Key files

- `.cursor/session-summaries/LATEST.md` — conflict resolved to master's rewrite; L11 restated
  against `70eff73`. Ended at **2572 words / 5 entries / max 632 per entry** (caps: 2600 / 5 /
  700). An intermediate draft landed at exactly 2600 — passing, with zero headroom for the
  next session. Trimmed deliberately.
- `.cursor/session-summaries/2026-08-02-HANDOFF-post-incident-state.md` — arrives on the branch
  for the first time; state table corrected.
- `frontend/test/services/encryption_service_reload_race_test.dart` — line 107 flipped to
  `false` and back for the falsification run. **Reverted; the committed tree is unchanged.**

## Verification

Everything below was run this session on the merged tree, nothing inherited.

| Check | Result |
|---|---|
| `flutter test` (full) | **1115 passed, 10 skipped, exit 0** |
| `flutter analyze --no-fatal-infos` | **No issues found** (9.1 s) |
| `node scripts/verify-claude-frontend-test-counts.mjs` | **OK — CLAUDE.md matches** |
| Backend suite | **Not re-run, deliberately.** `git diff origin/master...HEAD -- backend/` is **empty** — the branch's backend is byte-identical to master, and master's CI ran it green on `70eff73` (4/4 jobs). |
| Master CI on `70eff73` | success, 4/4 |
| **PR #111 CI on the merged tree** | **success, 4/4** — `pull_request` run `30725976087`, headSha `8d9bc20`. Backend tests, Flutter analyze+tests, Web Lock probe, E2E wire harness. This is the real gate; local green is not the same thing. |
| Merge scope | `git diff --cached --stat 9c1d476 -- ':!*.md'` **empty** — docs-only, so the merge itself cannot have broken code |

**The reload-race suite was falsified, not just run green.** With
`PrefsContentKv.debugForceAuthoritative = false`, exactly the three predicted tests went red,
with the incident's own symptoms:

```
a record dropped from the reload cache is still readable     Expected: 'hello'  Actual: <null>
the batched history read sees a record the cache lost        Expected: 'world'  Actual: <null>
a user-requested delete still finds a record the cache lost  Expected: contains <18611>  Actual: Set:[]
```

Nine tests in the file; the other six stayed green, including `off web, reads stay on the cache`
which sets the flag false on purpose. A different failure set would have meant harness drift,
not health.

**The three deliberate asymmetries were re-checked in source, not taken on trust:**
`messageIdsForConversations` → `authoritative: true` (`encryption_service.dart:1372`),
`destroyableMessageIds` → `authoritative: false` (`:1420`), `storedMessageIds()` reads the cache
with no authoritative path (`:1434`), LRU prune counts via `_cachedContentEstimate` (`:1296`).
All four still carry their explanatory comments.

## Notes for next session

- **Tell the owner to `git pull`.** His main copy is still behind; nothing about this merge
  reaches him until he does. That is the only remaining half of the stale-banner problem.
- Branch is level with master and green. **PR #111 is still open and still needs explicit owner
  OK** — do not merge it.
- Pre-APK gate unchanged: check `CONTENT_KEY_CANARY_LOST` in field diags before shipping the
  encrypted store on any storage.
- Ranked open work is unchanged and lives in the handoff: ledger → encrypted at-rest store →
  note-expiry cron (`secret-notes.service.ts:48`, daily → per-minute) → both-sides-deleted
  server rows → silent expiry sweep.
- Trap confirmed again: a bare `git diff --stat` in this harness hangs on the pager. Use
  `git --no-pager`.
