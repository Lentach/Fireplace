# Session summaries — how to read this directory

225 dated files plus `LATEST.md`. All of them are tracked as of 2026-07-27.

## Read this first

- **`LATEST.md` is the skim layer.** Read it at session start. It holds at most the 5
  newest entries, ≤2600 words total and ≤700 per entry, enforced by `.githooks/pre-commit`.
  It is deliberately compressed — the dated file next to it has the full account.
- **Dated files are the archive.** `YYYY-MM-DD-session-<topic>.md`. Never delete one to
  "clean up"; the point of the archive is that a trap written down in April still applies
  in July.
- Root `CLAUDE.md` §1 is authoritative for workflow. Where a summary and `CLAUDE.md`
  disagree, `CLAUDE.md` wins. Where `CLAUDE.md` and the source disagree, the SOURCE wins
  and you fix the doc in the same commit.

## Two corrections that invalidate old text in here

Both were verified on 2026-07-27 and both contradict things written across many of these
files. Historical narrative is left intact; the INSTRUCTIONS it implies are void.

1. **This repo is PRIVATE.** `gh repo view --json isPrivate` → `true`. Numerous summaries
   assert "the repo is PUBLIC" and reason from it. That was wrong. (The landing-page repo
   `Lentach/fireplaceWebsite` IS public — that is probably where the belief came from.)
2. **Dated summaries ARE committed.** Until 2026-07-27, `.gitignore` kept everything except
   `LATEST.md` out of git, so anything written after 2026-07-22 existed only on the owner's
   machine. Summaries that tell you not to commit them, to use `git add -f`, or that a
   fresh clone will not have them are describing the OLD policy. Ignore that instruction.

Anything still stating otherwise is a historical record of a policy that no longer holds.
`2026-07-26-HANDOFF-START-HERE.md` carries an explicit correction banner over its version
of this claim.

## Handoffs

Files named `*handoff*` are pickup briefs written for a specific in-flight branch. They go
stale the moment that branch merges. Three banner-marked-SUPERSEDED ones were deleted on
2026-07-27 after one of them was nearly followed by mistake — **a warning banner only works
if the reader obeys it, so prefer deleting a dead handoff over marking it.** If you write
one, delete it when its branch lands.

## Writing a new summary

Required sections (root `CLAUDE.md` §1): `# title`, `**Date:**`, `## What was done`,
`## Key files`, `## Verification`, `## Notes for next session`. Write the dated file AND
add an entry on top of `LATEST.md`, rotating the oldest out past 5.

Keep credentials and third-party PII out. Private is not an excuse; the pre-commit secret
scan runs on these, and `gitleaks` is NOT installed on the owner's machine, so what
actually executes is a weaker regex fallback.
