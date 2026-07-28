# Agent tooling audit — inventory, tier list, S+A tier install, two key rotations

**Date:** 2026-07-27 — a tooling/security session. **No Fireplace app source was touched** (zero files under `frontend/lib`, `frontend/test`, `backend/src`, `backend/test` — verified). 6 commits, all docs/config/CI. Nothing deployed; live stays **0.0.132 / `05fc423`**. One production op: the standalone `fireplace-inbox` service was recreated to pick up a rotated key.

## What was done

1. **Audited the whole agent toolbelt.** 164 candidates surveyed across 7 parallel research slices, **25 rejected on recency/archival**, 31 ranked S/A/B/C/F. Deliverables are **local-only** in `.planning/tooling-audit/` (gitignored, `.gitignore:54`): `inventory.md`, `findings.md`, `TIER-LIST.md`, `WORKFLOW.md`, `progress.md`, plus `raw/` holding all 8 verbatim scout reports (170 KB) that existed only as in-memory artifacts and would have died with the session.

2. **🔴 Found a SECOND live secret in git.** `.claude/settings.local.json` was **tracked and pushed** carrying `CONTEXT7_API_KEY` (`ctx7sk-…`) in cleartext, introduced by `fdd3aa2` — an unrelated feature commit. Untracked + gitignored. **Confirmed live** (HTTP 200 vs 401 for a bogus key), then **revoked by the owner at context7.com and verified dead (401)**.

3. **Rotated `CONTACT_INBOX_KEY`** (issue **#100, CLOSED**). New key generated with `openssl rand -hex 32` **on the VM** — it never entered a transcript, a PC file, or a summary. Pre-check answered the issue's open question: the var is **vestigial for the main backend** (`git grep` finds nothing in `backend/src`; `docker-compose.prod.yml:74` uses `${CONTACT_INBOX_KEY:-}`, optional). Rotated in both `.env` files to avoid drift; **did not restart the main backend**.

4. **Installed the S tier (4) and A tier (3).**
   - **S1 `gitleaks` v8.30.1** → `~/.local/bin` (issue **#101 CLOSED**)
   - **S2** untrack `.claude/settings.local.json`
   - **S3 `dart mcp-server` 1.1.0** → project-scoped `.omp/mcp.json`
   - **S4 `osv-scanner` v2.4.0** → `~/.local/bin`
   - **A1** `deploy-web.ps1` now RUNS the post-deploy smoke and **FAILS the deploy** on a bundle-sha mismatch
   - **A3** `scripts/lint-ratchet.mjs` + `npm run lint:check` + a CI step
   - **A4 `trivy` v0.72.0** → `~/.local/bin`

5. **Proved the gitleaks gap precisely instead of assuming it.** Pulled `config/gitleaks.toml` (3,209 lines, **222 rules**), confirmed **no context-free entropy rule exists**, extracted `generic-api-key` (`entropy = 3.5`) and ran it with a Shannon calculation against the real strings:
   - `?key=<64 hex>` → **CAUGHT** (entropy 3.966) — the known `CONTACT_INBOX_KEY` miss is genuinely fixed.
   - `"Bash(CONTEXT7_API_KEY=\"ctx7sk-…\")"` **as stored** → **MISSED**. The JSON-escaped `\"` falls outside the rule's `[\x60'"\s=]{0,5}` class. **No scanner would have caught leak #2** — untracking the file was the actual fix.

6. **Measured the state of two things the docs were stale on.** Backend lint is **1,603 problems / 1,320 errors** — up from 726 on 2026-07-08, ~+30/day, because nothing ran it. And `npm run lint` is `eslint --fix`, so the obvious command **silently rewrites ~510 files** rather than reporting. Separately, GitHub **code scanning is 403 "not enabled"** and **secret scanning is 404 "disabled"** — three secret-scanning layers, all off or blind before this session.

7. **Scanned the production container for the first time.** 1 CRITICAL + 5 HIGH — and then chased them to ground (§ below). All six are in **npm's bundled dependencies**, not the app.

## Key files

- `deploy-web.ps1` (+39) — post-deploy stale-build gate
- `scripts/lint-ratchet.mjs`, `scripts/lint-baseline.json` — new
- `backend/package.json` — one line: `lint:check`. **No dependency or version lines touched.**
- `.github/workflows/ci.yml` (+15) — "Backend lint ratchet" step
- `.gitignore` — `.claude/settings.local.json*` (glob; a `.bak-*` copy carries the same secrets)
- `frontend/CLAUDE.md` §1 — the measured test-run cost curve (below)
- `.cursor/session-summaries/2026-07-22-session-inbox-extraction.md:63` — cleartext bearer key redacted to `<ROTATED-2026-07-27>`
- `.omp/mcp.json` — **new**, project-scoped, gitignored
- `.planning/tooling-audit/**` — six deliverables + `raw/` (local-only)
- VM: `~/fireplace-inbox/.env`, `~/fireplace/.env` (backups `*.bak-20260727-233049`, both re-`chmod 600`)

## Verification

- **Keys:** `CONTACT_INBOX_KEY` new → 200, old → **404**, bad → 404. Context7 leaked key → **401** (was 200). Inbox healthy in 7 s. Main stack untouched — `fireplace-backend-1` still on its pre-change `20:19:09Z` start, `/health` ok, `/version` + `/version.json` both `0.0.132 / 05fc423`.
- **gitleaks:** sha256 matched `d29144de…afc4e`. **Smoke: the real hook BLOCKED a synthetic 64-hex `?key=` at entropy 3.965826**, matching the 3.966 predicted before install. Full-tree scan: 22 findings, 13 tracked, all triaged (1 was the real inbox leak; 2 Polish `.env` doc templates; 1 Firebase key public by design; 9 test fixtures). After redaction: **no leaks across 986 KB of session summaries.**
- **A1 falsified BOTH ways** against live prod: matching sha → **exit 0** (5/5 checks); bogus sha → **exit 1** on the bundle-commit check. PowerShell parse-checked, 0 errors.
- **A3 falsified:** injected a floating promise + an unsafe `any` → 1320 → **1322, failed**; removed → passed. **CI green on all 3 jobs.**
- **osv-scanner** answered #102 in 2 s: **4 of 8** `brace-expansion` copies vulnerable. `frontend/pubspec.lock` **clean**, proving Dart coverage end to end.
- **dart_mcp_server:** real MCP handshake against the exact configured argv → `v1.1.0`, proto `2025-06-18`, **10 tools**, all three `--disable` flags effective. **Mount NOT proven** — needs an OMP reload.
- Full suites: backend **541 passed / 21 s**, frontend **903 passed + 4 skipped / 127 s**.

## The `node:22-alpine` CVEs — resolved, no action needed

`trivy` on the real prod image: **1 CRITICAL + 5 HIGH** (`tar` 7.5.11, `brace-expansion` 2.0.2, `picomatch` 4.0.3, `sigstore` 3.1.0). Traced every one inside the image:

- `tar`, `brace-expansion`, `sigstore` live **only** in `/usr/local/lib/node_modules/npm/node_modules/` — npm's own bundled tree. **Not app dependencies.**
- `picomatch` appears in both, but `/app/node_modules/picomatch` is **4.0.4 — already the patched release**. Trivy flagged npm's 4.0.3.

The container runs `node dist/main.js` as user `node`; **npm is never invoked at runtime**, and every one of these CVEs needs npm run against hostile input. **Not exploitable here.** Fix arrives upstream when Docker rebuilds `node:22-alpine`; `docker compose build --pull` picks it up free. Optional hardening: `rm -rf /usr/local/lib/node_modules/npm` in the runtime stage removes all six and shrinks the image (a `backend/Dockerfile` change, not done).

**Do not confuse these with #102** — the `brace-expansion` in npm's bundle is a different copy from the 4 vulnerable ones in `backend/package-lock.json`.

## Things I got WRONG and corrected by measuring

Recorded so nobody re-proposes them:

1. **A2 (`dart format --set-exit-if-changed` CI gate) — WITHDRAWN.** It reformats **146 of 368 files**; red on day one, and the only fix is the whole-tree reformat `LATEST.md:49` bans. **P5 stays unsolved.**
2. **"Docker Scout is already installed, zero cost" — WRONG.** It requires a Docker Hub login. Used `trivy` instead (no account).
3. **`dart mcp-server` context cost — overstated.** 10 tools, not the ~24 in `--help`. Roughly half my estimate.
4. **"`impact.mjs` has a blind spot" — WRONG, my probe path didn't exist.** Correct path returns 19 direct / 5 indirect / **45 tests**. The tool is sound.
5. **A "run only affected tests" runner — DISPROVEN, do not build it.** See the cost curve.
6. **My own backup leaked.** The first `settings.local.json` backup landed **inside the repo**, unmatched by the exact-path ignore rule — the exact failure this audit exists to stop. Fixed twice: widened to a glob **and** moved the file out of the repo.

## Notes for next session

- **`dart mcp-server` mount is UNVERIFIED.** Run `/mcp list` at OMP start; expect a `dart` entry from `.omp/mcp.json`. If absent, the config is one line to fix.
- **`impact.mjs` FOOTGUN, unfixed:** a path that does not exist returns **exit 0** with *"No dependents (entry point or dead code)"* — it cannot distinguish "no dependents" from "no such file". One typo and it reports your change as safe. Worth a two-line fix.
- **Lint ratchet gates a SPLIT count** (corrected after review — the first version was buggy). `nonPrettier` = **839**, AST-derived and **proven platform-identical** (CI Linux prints 839, same as Windows), enforced strictly. `prettier` = 481 formatting, tolerance ±5, which absorbs the CRLF delta (Windows 481 / Linux 479) without leaving it ungated. `--update` is safe from either platform. **The earlier "pin to the higher Windows number" rule was the bug** — it left 2 errors of free headroom at the CI enforcement point. Do not reinstate it.
- **#102 still open** and legitimately so: root `brace-expansion@1.1.16` + `2.1.2` under `@jest/reporters`, `jest-config`, `jest-runtime`. Dev-only, not deploy-blocking.
- **The cull was proposed and the owner declined it** — the 8 plugins and 39 skills stay. The one I would still remove is **`ralph-loop`**: 0 uses in 226 sessions and the only installed plugin registering a **Stop hook**, i.e. it can re-drive an agent past a finish on a repo whose rules forbid unasked scope. Not raising it again unasked.
- **Remaining A/B items, all needing approval:** modernise `.githooks/pre-commit`'s deprecated `gitleaks protect --staged` → `gitleaks git --staged`; the backup restore-to-scratch-container test; `very_good_analysis` **with a baseline**.
- **Two latent backend findings, deliberately NOT fixed** (out of scope for a tooling session): `chat.gateway.ts:126` — `client.join()` unawaited before `socketReady` is emitted at `:134`; harmless with the in-memory Socket.IO adapter, a real race the day a Redis adapter appears. And `message.mapper.ts:44-54` — six enum-vs-string comparisons; **not a bug today** (`MessageType` members are all `X = 'X'`), but rename any value and reply previews silently degrade to `''`.
- **Do not re-raise either key as a live leak.** Both are rotated and verified dead; the values in git history are inert by decision, no scrub planned.
- ➡ Full evidence, tier list and install/rollback commands: **`.planning/tooling-audit/`** (local-only, not in the repo).
