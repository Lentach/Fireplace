# Dependabot #119 closed by dismissal, not by an override — csv-parse v7 removes artillery entirely

**Date:** 2026-09-12 · **Version:** unchanged (0.2.41) · **Tiers deployed:** none

## What was done
- Open-alert count went **1 → 0**. `#119` (medium, `csv-parse < 7.0.2`, "prototype replacement still reachable via the columns path", manifest `scripts/smoke/package-lock.json`) is **dismissed `not_used`**, with the reasoning in the dismissal comment (GitHub caps it at 280 chars — two longer drafts were rejected 422).
- Grounds: `csv-parse@4.16.3` reaches us ONLY through `artillery 2.0.34` in `scripts/smoke`, a manual post-deploy harness — never shipped, never fed untrusted CSV. The vulnerable `columns` path needs an artillery `payload:` CSV, and `artillery-socket.yml` defines none.
- The clean fixes do not exist: `npm view artillery version` = **2.0.34 is the latest release** and it still depends on `csv-parse ^4`, so there is no upstream version to upgrade into.
- `overrides: {"csv-parse": "^7.0.2"}` was applied and **reverted on evidence** — see Verification. Working tree ends clean; `scripts/smoke/package.json` + lock are back at HEAD with `csv-parse@4.16.3`.
- De-staled `traps.md` § Owner-owed: dropped "deploy backend (multer 2.3.0 override pending since 0.2.35)" — that shipped in `49c77c10`, prod `/version` = `0.2.41 / 49c77c10`.

## Key files
- Edited: `docs/agents/traps.md` (new csv-parse/artillery trap; owner-owed line de-staled + socket-smoke 4/5 recorded).
- Touched then reverted: `scripts/smoke/package.json`, `scripts/smoke/package-lock.json`.
- Read only (load-bearing): `scripts/smoke/artillery-socket.yml` (no `payload:` block), `scripts/smoke/node_modules/artillery/lib/cmds/run.ts` + `lib/util/prepare-test-execution-plan.ts` (both `import _csv from 'csv-parse'`).

## Verification
- **Override resolves but destroys the tool.** After `npm install`, `npm ls csv-parse --all` → `artillery@2.0.34 └── csv-parse@7.0.2` (looks clean). `npm run socket` then died BEFORE running anything: `The requested module 'csv-parse' does not provide an export named 'default'`, repeated for `findCommand (run)`, `(quick)`, `(run-aci)`, `(run-lambda)`, ending `» Warning: run is not a artillery command.` Cause: artillery's ESM build default-imports `csv-parse`; v7 exports `{ parse }`. This is LOAD-time, not a degraded payload loader — `npm ls` alone would have shipped a broken harness.
- **Revert proven:** `git checkout HEAD -- scripts/smoke/package.json scripts/smoke/package-lock.json` + `npm install` → tree back to `csv-parse@4.16.3`; `npm run socket` runs the scenario again (5 emits, p95 77.5 ms).
- **Alert state:** `gh api -X PATCH …/dependabot/alerts/119` → `119  dismissed  not_used`; `gh api …/dependabot/alerts --jq '[.[]|select(.state=="open")]|length'` → **0**.
- **Incidental finding, NOT mine to fix:** the artillery socket smoke is **4/5 locally on `e5cd287`** — `vusers.failed: 1`, one `errors.response timeout`, `ensure` check `vusers.failed == 0` RED, reproduced twice against a healthy local backend with the tree at HEAD. This contradicts batch 8.8's "artillery Socket.IO smoke 5/5 locally". Not caused by the override or its revert (both runs were post-revert).
- Local stack: Docker Desktop's engine was DOWN at session start (containers had been up 17 h); restarted it, `docker compose up -d`, `/health` → `{"status":"ok","db":"ok"}`. Left running.

## Notes for next session
- **Do not re-attempt the csv-parse override** (trap recorded). It only becomes fixable if artillery ships a `csv-parse` v5+ compatible release; then drop the dismissal and bump.
- **Re-open #119** if a `payload:` CSV is ever added under `scripts/smoke`, or if artillery starts being run against untrusted CSV — both premises of the dismissal are falsifiable by design.
- **Owner/batch-8 owner owes** the socket-smoke 4/5 verdict: fix or delete. Cheapest discriminator is whether the failing vuser is the FIRST (cold-backend `socketReady` race) or a random one (five connections share ONE JWT, so device/takeover semantics — `docs/contracts/wire.md` §6.0 — may drop a socket before it answers).
- `backend/package-lock.json` carries a 96-line deletion from a concurrent session; untouched and unstaged here.
