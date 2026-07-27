# Code-scanning + Dependabot alert remediation

**Date:** 2026-07-10 (code-scanning triage — SSRF hardening, CI permissions, dependency bumps)

## What was done

Triaged and fixed the open GitHub security alerts on `Lentach/Fireplace`. Actual scope: **3 CodeQL
code-scanning alerts + 30 Dependabot alerts** (the "~30" from the screenshot is the Dependabot count;
all 30 are npm / `backend/package-lock.json`). Work on fresh branch `fix/code-scanning-alerts` (the
brief's "in-progress branch" had been deleted by the owner; started clean from `master`). PR #59, base
`master`, **not merged** — awaiting owner OK. CodeQL + Dependabot re-run on the PR = proof of remediation.

**CodeQL (3/3 fixed, no suppressions/dismissals):**
- `js/request-forgery` (critical), link-preview.service.ts — root-cause SSRF fix, commit `2a26bd3`.
  Replaced regex host blocklist with two enforced layers: (1) byte-parse the WHATWG-normalized hostname
  (`isPrivateIp`) so decimal/hex/octal IPv4, IPv4-mapped/NAT64 IPv6, 0.0.0.0, CGNAT, ULA, link-local are
  all rejected; (2) undici `Agent.connect.lookup` resolve-and-pin — resolves every A/AAAA record, refuses
  if any is private, dials only validated addresses → closes the DNS-rebinding gap the code previously
  carried as a documented residual. Manual per-hop redirect validation retained.
- 2× `actions/missing-workflow-permissions` (medium), ci.yml — top-level `permissions: contents: read`,
  commit `f87cc80`.

**Dependabot (29/30 fixed):** `npm audit fix` (semver-only, no --force), commit `a6ed352`. Patched
protobufjs 7.6.5 (incl. critical RCE), js-yaml 4.3.0, @babel/core 7.29.7, fast-uri 3.1.3, fast-xml-parser,
node-forge, picomatch 4.0.4, socket.io-parser, flatted 3.4.2, @tootallnate/once 2.0.1, @protobufjs/utf8
1.1.2. Post-fix `npm audit`: high=0, critical=0.

**1 Dependabot alert deferred — needs owner sign-off:** `uuid` (moderate, #65) is only reachable via
firebase-admin's transitive google-cloud chain; Fireplace never passes the vulnerable `buf` arg, so
practical exploitability is nil. Only remediation is a **firebase-admin MAJOR bump (13→14)** → flagged
for approval per the "major bumps flagged for approval" rule.

Added `undici` as a direct backend dependency (the pinned-DNS agent). Its `connect.lookup` wiring is
proven end-to-end by a test that stands up a live loopback server and asserts a fail-open would serve a
request — this catches the "undici silently ignores the option" failure mode a lookup-only unit test
would miss.

## Key files
- `backend/src/chat/services/link-preview.service.ts` — rewritten SSRF defence (`isPrivateIp`,
  `ssrfSafeLookup`, `ssrfSafeAgent`, `ssrfSafeFetch`, public `fetchImpl` test seam).
- `backend/src/chat/services/link-preview.service.unit.spec.ts` — expanded blocked-literal list,
  `isPrivateIp` byte-parser tests, live-server pinned-lookup E2E proof.
- `backend/src/chat/services/link-preview.service.spec.ts` — migrated off `global.fetch` to `fetchImpl`.
- `.github/workflows/ci.yml` — least-privilege permissions.
- `backend/package.json`, `backend/package-lock.json` — undici + audit fixes.
- `backend/CLAUDE.md` §10 — rewritten to the two-layer resolve-and-pin reality (old "known residual"
  claim removed). Root `CLAUDE.md` §3 — backend test count 416 → 452.
- `docs/audit/2026-07-10-code-scanning-triage.md` — LOCAL-ONLY full triage table (gitignored; public repo).

## Verification
- Backend `npm test`: **452 passed, 43 suites** (was 416; +36 SSRF/IP tests). Count verifier green
  (`OK: CLAUDE.md matches Jest (452 tests, 43 suites)`).
- `npx tsc --noEmit -p tsconfig.json`: clean.
- SSRF E2E proof test passes: server got 0 hits, rejection carried the pinned-lookup message.
- `graphify update .`: 8225 nodes / 11698 edges.
- No frontend files changed (all alerts backend/CI); frontend suite not re-run — nothing new to verify.

## Notes for next session
- **PR #59 is NOT merged.** Do not merge without owner OK. Watch the PR's CodeQL + Dependabot re-scan;
  those results are the remediation proof.
- **Owner decision pending:** firebase-admin 13→14 major bump to clear the last uuid alert. If approved,
  `npm i firebase-admin@^14` in backend, re-run full suite + staging rehearsal (firebase-admin touches
  push init), then update package-lock. Until then 1 moderate Dependabot alert stays open by design.
- The deleted branch's uncommitted l10n edits are unrecoverable and were unrelated to any alert.
- If anyone touches the link-preview agent, KEEP the live-server E2E test — it's the only guard against
  a silent SSRF fail-open.

---

## ADDENDUM — Node 22 upgrade + production deploy (same session, later)

### firebase-admin decision (owner approved bump, then I reversed it)
Owner approved fb 13→14. Investigated: **the bump is NOT the fix and breaks the build.** fb14.1.0's
google-cloud chain still pulls uuid@9.0.1 (alert survives), and fb14 moved to the modular SDK — it drops
the `admin.apps`/`credential`/`messaging()` namespace `push-notifications.service.ts` uses, so `tsc`/build
fails without a code migration; it also requires Node 22+. Real fix = scoped
`overrides.firebase-admin.uuid = ^11.1.1` (only patched line; our code imports uuid nowhere; chain only
calls `v4()`). Lockfile delta = uuid 9.0.1→11.1.1. firebase-admin stays 13.x. → PR #60, merged.
`npm audit` = 0.

### Node 20 → 22 LTS (PR #61, merged)
Node 20 nearing maintenance EOL. Bumped every pin: `backend/Dockerfile` (builder+runtime),
`backend/Dockerfile.dev`, `docker-compose.yml`, `.github/workflows/ci.yml` `setup-node`; added
`engines.node >=22`. `@types/node` kept `^22` (tracks runtime). In-range `npm update` refresh
(@eslint/js, @types/node, prettier — no manifest ranges changed). Majors left for separate decisions:
typescript 7, undici 8 (load-bearing for the SSRF agent — verify `connect.lookup` before bumping),
firebase-admin 14, @nestjs/schedule 6, dotenv 17, globals 17, @types/supertest 7. Dated design doc
`docs/futures/source-of-truth/2026-02-04-*.md` still shows `node:20` in a code snapshot — left as a
historical artifact, not live config.

### Production deploy (all 3 PRs live)
VM was behind at `356cf4a`, so deploying master (`b7708ed`) took SSRF hardening + uuid override + Node 22
live together. Local Docker was DOWN → staging rehearsal (CLAUDE.md §6) could not run; substituted:
(1) build the Node 22 image ON the prod host (proves native `bcrypt`/`pg` compile on node:22-alpine)
without recreating the container; (2) `deploy-backend.sh` health-gated cutover; (3) functional smoke.
Verified: container `node --version` = **v22.23.1**, health `healthy` @10s, public `/version` = commit
`b7708ed`, `/health` `{status:ok,db:ok}`, Socket.IO handshake ok, logs clean (only pre-existing benign
`FCM disabled` warning). No rollback needed. Backend only — frontend untouched. No version bump (still
0.0.104); `pubspec.yaml` left alone (owner's uncommitted ping/0.0.105 WIP in the tree).

### State at handoff
- **0 open code-scanning alerts, 0 open Dependabot alerts.** Prod healthy on Node 22.
- Owner has uncommitted frontend "ping" work in the tree (ping_glyph, sounds, overlay, pubspec 0.0.105,
  LATEST.md ping entry) — NOT touched by me. My LATEST.md UPDATE-3 deploy note was added additively and
  left uncommitted so it commits alongside the owner's ping work.
- Optional future currency work (own PR + validation each): a real firebase-admin 14 migration (modular
  SDK + live FCM device smoke test), undici 8, typescript 7.
