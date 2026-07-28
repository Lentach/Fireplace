# Agent tooling audit — inventory, tier list, S-tier install, two key rotations

**Date:** 2026-07-27 — a tooling/security session. No Fireplace feature code touched. 3 commits (`a6ffcac`, `fc58853`, `10f733d`), all docs/config. Nothing deployed; live stays **0.0.132 / `05fc423`**. One production op: the `fireplace-inbox` service was recreated to pick up a rotated key.

## What was done

1. **Audited the whole agent toolbelt.** 164 candidates surveyed across 7 parallel research slices, 25 rejected on recency/archival, 31 ranked S/A/B/C/F. Deliverables are **local-only** in `.planning/tooling-audit/` (gitignored, `.gitignore:54`): `inventory.md`, `findings.md`, `TIER-LIST.md`, `WORKFLOW.md`, `progress.md`, plus `raw/` holding all 8 verbatim scout reports (170 KB) that would otherwise have died with the session.

2. **🔴 Found a SECOND live secret in git.** `.claude/settings.local.json` was **tracked and pushed** carrying `CONTEXT7_API_KEY` (`ctx7sk-…`) in cleartext, introduced by `fdd3aa2` — an unrelated feature commit. Untracked + gitignored (`a6ffcac`). **The key is still live** (tested: HTTP 200 vs 401 for a bogus key) and **still needs revoking at context7.com — owner action, not done.**

3. **Proved the gitleaks gap precisely instead of assuming it.** Pulled `config/gitleaks.toml` (3,209 lines, 222 rules), confirmed **no context-free entropy rule exists**, extracted `generic-api-key` (`entropy = 3.5`) and ran it with a Shannon calculation against the real strings:
   - `?key=<64 hex>` → **CAUGHT** (entropy 3.966) — the known `CONTACT_INBOX_KEY` miss is genuinely fixed by gitleaks.
   - `"Bash(CONTEXT7_API_KEY=\"ctx7sk-…\")"` **as stored** → **MISSED**. The JSON-escaped `\"` falls outside the rule's `[\x60'"\s=]{0,5}` class. **No scanner would have caught leak #2** — untracking the file was the actual fix.

4. **Installed the S tier (4 items).** `gitleaks` v8.30.1 and `osv-scanner` v2.4.0 to `~/.local/bin` (already on PATH); `dart mcp-server` wired **project-scoped** into `.omp/mcp.json`; plus the untracking above.

5. **Rotated `CONTACT_INBOX_KEY` (issue #100, CLOSED).** New key generated with `openssl rand -hex 32` **on the VM** — it never entered a transcript, a PC file, or a summary. Pre-check answered the issue's open question: the var is **vestigial for the main backend** (`git grep` finds nothing in `backend/src`; `docker-compose.prod.yml:74` uses `${CONTACT_INBOX_KEY:-}`, optional). Rotated in both `.env` files anyway to avoid drift; **did not restart the main backend**.

6. **Upgraded `dart_mcp_server` 0.1.4 → 1.1.0** via `dart pub global activate`. Pub's bin dir is **not on PATH**, so `.omp/mcp.json` references the `.bat` by absolute path, wrapped in `cmd /c` (it is a batch file — the same Windows limitation that blocks `hub start`).

7. **Measured the real state of two things the docs were stale on.** Backend lint is **1,603 problems / 1,320 errors** — up from the 726 recorded 2026-07-08, ~+30/day; 481 auto-fixable Prettier, ~839 real `no-unsafe-*`, and **3 `no-floating-promises`**. And `npm run lint` is defined as `eslint --fix`, so the obvious command **silently rewrites** rather than reporting. Separately: GitHub **code scanning is 403 "not enabled"** and **secret scanning is 404 "disabled"** — three secret-scanning layers, all off or blind before this session.

## Key files

- `.gitignore` — `.claude/settings.local.json*` (glob, not exact path; a `.bak-*` copy carries the same secrets)
- `.omp/mcp.json` — **new**, project-scoped, gitignored. `dart_mcp_server` 1.1.0, `--disable pub_dev_search,create_project,flutter_driver_user_journey_test`
- `.cursor/session-summaries/2026-07-22-session-inbox-extraction.md:63` — cleartext bearer key redacted to `<ROTATED-2026-07-27>` + note that it is dead
- `.cursor/session-summaries/LATEST.md` — #100/#101 marked resolved; now **1891 words / biggest entry 654** (was 1937 / **700**, i.e. exactly at cap)
- `.planning/tooling-audit/**` — all six deliverables + `raw/` (local-only, never committed)
- VM: `~/fireplace-inbox/.env`, `~/fireplace/.env` (backups `*.bak-20260727-233049`, both re-`chmod 600`)

## Verification

- **Key rotation:** `NEW -> 200`, `OLD -> 404`, `bad -> 404`. `fireplace-inbox` healthy in 7 s. Main stack untouched — `fireplace-backend-1` still on its pre-change `2026-07-27T20:19:09Z` start, `/health` `{"status":"ok","db":"ok"}`, `/version` and `/version.json` both `0.0.132 / 05fc423`. Inbox SQLite readable after recreate.
- **gitleaks:** installed sha256 matched the published `d29144de…afc4e`. **Smoke test: the real hook BLOCKED a synthetic 64-hex `?key=` at entropy 3.965826** — matching the 3.966 predicted analytically before install. Full-tree scan: 22 findings, 13 tracked, all triaged (1 was the real inbox leak, 2 were Polish `.env` doc templates, 1 a Firebase key public by design, 9 test fixtures). **After the redaction, `gitleaks dir .cursor/session-summaries` → no leaks found across 986 KB.**
- **osv-scanner:** answered issue #102 in 2 s — **4 of 8** `brace-expansion` copies still vulnerable (root `1.1.16` + `2.1.2` under `@jest/reporters`, `jest-config`, `jest-runtime`), all dev-only. `frontend/pubspec.lock` **clean**, which also proved the Dart-coverage claim end to end.
- **dart_mcp_server:** real MCP handshake against the exact configured argv → `dart and flutter tooling v1.1.0`, proto `2025-06-18`, **10 tools**, all three `--disable` flags confirmed effective. **Mount NOT proven** — needs an OMP reload.
- **Repo:** `git status -sb` clean after every commit. Pre-commit hook run manually against the staged docs → **exit 0**.

## Notes for next session

- **⛔ OWED: revoke the Context7 key at context7.com.** Re-tested at end of session: **still HTTP 200, still live.** Match it in the dashboard by `ctx7sk-a18dff5` … `1160` (43 chars). Nothing on this machine uses it — the plugin runs `npx -y @upstash/context7-mcp` with **no key** — so deleting it breaks nothing. Then `rm ~/.claude-backups/settings.local.json.bak-preaudit-20260727` (last local copy of the value).
- **Issue #101 (install gitleaks) is DONE but still OPEN** — close it. #102 is legitimately open.
- **`dart mcp-server` mount is unverified.** Run `/mcp list` at OMP start; expect a `dart` entry sourced from `.omp/mcp.json`. If absent, the config is one line to fix.
- **A-tier and the cull are untouched and need approval.** Highest value: **A1 — wire `post-deploy-smoke.mjs` into `deploy-web.ps1` and fail loudly on SHA mismatch.** It kills the #1 pain (deploy-truth hand-verified every time; one session ran 10 deploys and 10 manual smokes) **and** the exit-21 silent-halt bug in the same change, with no new tool. **The single thing to remove: `ralph-loop`** — 0 uses in 226 sessions and the only installed plugin registering a **Stop hook**, i.e. it can re-drive an agent past a finish on a repo whose rules forbid unasked scope.
- **Two latent backend findings, deliberately NOT fixed** (out of scope for a tooling session, worth issues): `chat.gateway.ts:126` — `client.join()` unawaited before `socketReady` is emitted at `:134`; harmless with the default in-memory Socket.IO adapter, a real race the moment a Redis adapter appears. And `message.mapper.ts:44-54` — six enum-vs-string-literal comparisons; **verified not a bug today** (`MessageType` members are all `X = 'X'`), but rename any value and reply previews silently degrade to `''`.
- **Do not re-raise the inbox key as a live leak.** It is rotated and dead; the value in git history is inert by decision, no scrub planned.
- ➡ Full detail, evidence and install/rollback commands: **`.planning/tooling-audit/`** (local-only, not in the repo).
