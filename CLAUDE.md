---
description:
alwaysApply: true
---

# CLAUDE.md — Fireplace

**Source of truth = this root file + the two tier files.** Root is cross-cutting and stays in context — read it before any Fireplace work. The tier files hold the detailed traps and are **not** auto-injected. Read the matching one **once, before your first change in that tier**, then keep it in context — do not re-read it on every edit:

- Changing anything under `frontend/` (Flutter/PWA/client) → read `frontend/CLAUDE.md` first.
- Changing anything under `backend/` (NestJS/Postgres/server) → read `backend/CLAUDE.md` first.
- Cross-tier or infra/deploy/docs → this root file is enough.

Keep root cross-cutting: if a fact only matters while editing Flutter or NestJS code, it belongs in the tier file, not here. Do not turn root back into a junk drawer.

## 1. Non-negotiable workflow

- Read this root file before any Fireplace app work, and the matching tier file before your first change in that tier (see the header rule). Main agents and spawned subagents both treat these three files as the project source of truth. When delegating, explicitly tell the subagent to read them — subagents do not inherit your loaded context.
- **`C:/Users/Lentach/Desktop/Fireplace` is THE working copy, on `master`** (worktree zoo consolidated 2026-07-22: five stale worktrees incl. `fireplace-ping-deploy` removed; all their branches were fully pushed/merged first). Still check `git status -sb` before assuming a clean master. The landing page lives in its own repo: `Desktop/fireplace-landing` (`Lentach/fireplaceWebsite`).
- **PRIVATE repo** — `Lentach/Fireplace` is private (`gh repo view --json isPrivate` → `true`, verified 2026-07-27; docs long claimed "public", which was wrong). The landing repo `Lentach/fireplaceWebsite` IS public — do not confuse them. A pre-commit hook scans staged changes for secrets and enforces the LATEST budget; activate once per clone with `git config core.hooksPath .githooks`. Bypass only in emergencies (`--no-verify`).
- At session start: read `.cursor/session-summaries/LATEST.md`.
- At task end: write/update `.cursor/session-summaries/YYYY-MM-DD-session.md` and `.cursor/session-summaries/LATEST.md`. Required summary sections: `# title`, `**Date:**`, `## What was done`, `## Key files`, `## Verification`, `## Notes for next session`. New LATEST entry goes on top; older entries shift to `Previous`/`Earlier`.
- **Dated summaries ARE committed** (since 2026-07-27; all 226). A fresh clone sees the full history. **`gitleaks` IS installed on the dev PC** (`gitleaks version` → 8.30.1, verified 2026-07-29), so `.githooks/pre-commit` takes its entropy+rule branch (`gitleaks protect --staged --redact`) and the prefix-only regex is only the fallback for a machine without it — an older note here claimed the opposite. It is still not a substitute for care: a `?key=<64 hex>` bearer token sat in a tracked summary for days under the old regex-only hook. Keep credentials and third-party PII out by hand; write `<REDACTED>` when pasting a URL or curl. A key-NAME constant that trips a rule (e.g. a storage key literal) gets `// gitleaks:allow` on the line, never `--no-verify` on the commit.
- **LATEST.md rotates: ≤5 dated entries, newest on top, and the agent adding one DELETES THE OLDEST** — the single rule `.githooks/pre-commit` enforces. Nothing is lost: each entry links its dated per-session file, which holds the full account. **The word budgets are gone** (owner decision 2026-08-14, ≤3900 total / ≤700 per entry): the shared banner counted as an "entry", so adding a genuinely new binding fact to it got you BLOCKED, and the cheapest escape was always deleting evidence from a summary written minutes earlier — three sessions in a row burned time on the arithmetic instead of the handoff. **NEVER trim a fresh summary to fit a budget; rotate instead.** Keep entries skimmable because every agent and subagent reads them at session start, not because a counter says so.
- For multi-step/debug/deploy-sensitive work, use persistent planning files in `.planning/<task>/` — `task_plan.md`, `findings.md`, `progress.md` live INSIDE that directory, never at the repo root. Re-read before decisions; log failed attempts. Delete `.planning/.active_plan` when the plan it names is finished, or it silently points the next session at completed work.
- Before any change: read the files you touch and trace the code paths. Code/source beats docs and old summaries.
- **Re-verify VOLATILE claims; never inherit them.** Git/branch state, what is live, versions and commits, CI or Dependabot status, test counts, generated-artifact freshness — all must come from a command you ran THIS session. This repo has been confidently wrong on exactly these (a graph reported fresh but built from a stale commit; an alert recorded as fixed when the lockfile was half-upgraded; a handoff pointing at a file whose first line reads SUPERSEDED). Stable facts — architecture, wire contracts, documented traps — can be trusted as written; when source and doc conflict, source wins and you fix the doc in the same commit.
- Scope: change only what was asked. Fix obvious bugs in edited paths; do not add unasked features, abstractions, or cleanup crusades.
- Code, comments, commit messages, logs: English. UI strings may stay localized.
- Tone: brutally blunt — lead with the verdict, no hedging, no flattery ("great question" / "you're absolutely right" are banned). Roast bad code and time-wasting rabbit holes; speak the truth even when inconvenient.
- Auto-review/code-review subagents must use the same model class as the primary session unless the user explicitly asks for a cheaper model.
- Commits: commit at natural checkpoints and `git push` in the same checkpoint (the VM deploys via `git pull`; local-only commits block it). Small/trivial fixes can go straight to `master`; bigger/riskier work uses a feature branch + PR. Feature branches do NOT auto-deploy — the VM pulls `master`, so work goes live only after PR merge. Never merge to `master` without explicit user OK.
- **`node scripts/impact.mjs` is the inner-loop impact hint** — who depends on what you changed, plus the tests that import it, in ~0.6s. `--ref <ref>` for a branch, `--json` for machine use. Import resolution is exact (1639 specifiers, 0 unresolved; conditional Dart imports, bare same-dir specifiers, untracked files, deletions). **Reachability is NOT coverage:** 3 hops, static imports only, blind to NestJS DI, the §7 wire contracts and assets. Running the full tier suites before a commit or PR is required by project policy; nothing enforces it mechanically.
- **Never run `dart format lib/`** (or any whole-tree formatter): format only the lines you edited, or the diff drowns the review and the blame. Same reason `node scripts/lint-ratchet.mjs` exists — it runs ONLY in CI, so run it yourself before pushing backend changes; it fails the build when the warning count rises above the recorded floor.
- `graphify update .` is **no longer a manual step** — `.githooks/post-commit` rebuilds the graph in the background after every commit (`graphify hook status` to verify; needs `git config core.hooksPath .githooks`, same one-time setup as the secret-scanning pre-commit hook).

## 2. Architecture map

Fireplace is a production E2E encrypted chat app:

```text
Flutter web/mobile client ⇄ NestJS backend (:3000) ⇄ PostgreSQL 16 (:5433 host)
                         REST + Socket.IO         self-hosted media volume
```

- Client: `AuthGate` → `AuthScreen` or `MainShell` → `ChatDetailScreen`; state is provider-driven. See `frontend/CLAUDE.md`.
- Backend: `AppModule` wires ~15 domain modules (auth, users, chat, messages, media, key-bundles, push, …) — authoritative full map in `backend/CLAUDE.md` §2; `ChatGateway` authenticates sockets and delegates to chat services.
- Media: current media storage is self-hosted under `/app/media` (`avatars/`, `msgs/`). Cloudinary URLs remain accepted only as legacy/backward-compatible media URLs.
- Landing page (`https://fireplace.ignorelist.com/welcome/`): **separate PUBLIC repo `Lentach/fireplaceWebsite`** (extracted from `landing/` 2026-07-22 with git history; owner renamed it from `fireplace-landing` the same day; local clone `C:/Users/Lentach/Desktop/fireplace-landing`). Astro static site, own `CLAUDE.md` + `deploy-landing.ps1`, deploys independently to `~/fireplace/landing-build/` on the same VM. Not part of this repo's CI/deploys.
- Graph context: `node scripts/impact.mjs` (§1) is the first stop for "what does this change affect". `graphify-out/GRAPH_REPORT.md` is a secondary whole-repo view — its per-file symbol inventory is sound and its backend TS import edges measure **86.6% precision / 90.7% recall**, but its **Dart import edges are 0.5% precision / 1.5% recall** (measured 2026-07-27: it collapses every relative specifier such as `../../theme/rpg_theme.dart` into one node attributed to an arbitrary file). Never answer a Flutter dependency question from it. No `graphify-out/wiki/index.md` exists; the ~508 `[[_COMMUNITY_*]]` wikilinks in the report are dead.

## 3. Local commands

```bash
# Terminal 1: backend + DB for local dev
docker-compose up

# Terminal 2: Flutter web
cd frontend && flutter run -d chrome
```

- Ports: backend `:3000`, DB host `:5433 -> :5432`, Flutter web random unless specified.
- Before local start on Windows if stale node processes bite: `taskkill //F //IM node.exe`.
- Phone on WiFi: `cd frontend && .\run_web_for_phone.ps1`, or `flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080 --dart-define=BASE_URL=http://YOUR_PC_IP:3000`.
- Tests: `cd backend && npm test` (768 unit tests, 52 suites; verified by `node scripts/verify-claude-backend-test-counts.mjs`). Frontend: `cd frontend && flutter analyze --no-fatal-infos && flutter test` (1370 Flutter tests, 10 skipped; verified by `node scripts/verify-claude-frontend-test-counts.mjs`). Full-stack E2E wire harness (needs `docker-compose up` first, NOT in the fast lane): `cd frontend && flutter test test_e2e` — 24 tests / 2 skipped; see `frontend/CLAUDE.md` §1 and the `e2e-wire` CI job. Origin-wide Web Lock probe: `node scripts/session-lock-probe.mjs` (also a CI job).
- CI: `.github/workflows/ci.yml` — `backend` (impact self-test, jest, backend count verifier), `frontend` (analyze, flutter test, frontend count verifier), `session-lock` (Web Lock probe in headless Chrome), and `e2e-wire` (full-stack harness against a real backend + Postgres). `e2e-wire` is the only automated check on the §7 wire contracts; it caught two disaster-recovery bugs on its first two runs and its `continue-on-error` was removed after 5 consecutive greens, so a wire regression now **fails the CI run**.
- **CI is DETECTION, not prevention — there is no gate.** Branch protection is a paid feature and the API returns 403 on this private free-plan repo, so nothing mechanically blocks a push or a merge, and §1 still permits small fixes straight to `master`. The rule is procedural and on you: **check the run and never merge or deploy on red.** `gh run list --branch master --limit 1` after pushing. If `e2e-wire` turns flaky, restore `continue-on-error: true` deliberately and record it — never silently disable it.

## 4. Production deploy and safety

Production: `https://fireplace.ignorelist.com`, **OVH VPS** `ubuntu@51.68.138.13` (Warszawa, key-only SSH), repo `~/fireplace`. GCP was fully decommissioned 2026-07-14 — treat any `gcloud` instruction in older docs as historical.

**Deploy is SPLIT** because the VM cannot compile Flutter web without OOM:

- Frontend, from the PC: `git pull ; .\deploy-web.ps1`
- Backend, on the VM: `cd ~/fireplace && ./deploy-backend.sh`
- Verify: `cd scripts/smoke && node post-deploy-smoke.mjs`

**➡ Everything else — script internals, staging rehearsal, backups/restore, the env-var table, branch testing, VM logs — is in `.cursor/rules/production-vm-deploy.mdc`. Read it before any non-trivial prod op.**

Non-negotiable, because each one is silent or irreversible:

- **Trust `gitCommit`, never semver alone.** Flutter happily serves cached code under a bumped version. `/version.json` (frontend) and `/version` (backend) are the truth; `git log` is not.
- **After a frontend deploy the user must fully close + reopen the PWA. NEVER uninstall or clear site data** — that destroys local E2E Signal keys with no recovery.
- **Never run `docker compose down -v`, `docker volume rm`, or `prune --volumes` on prod.** `pgdata` and `media_storage` are user data.
- **Never run a bare `docker compose -f docker-compose.prod.yml up -d`** — without the exported `APP_VERSION`/`GIT_COMMIT` it silently recreates the backend as `0.0.1/unknown`.
- **Never build Flutter web on the VM**, and never use the legacy all-in-one `deploy.sh`.

## 5. Version contract

- The user-visible version is semver from `frontend/pubspec.yaml` ONLY: `0.0.x`, **never** a `+build` suffix anywhere. "Bump by +1" means the PATCH segment (`0.0.1` → `0.0.2`), not `+1` appended. Production releases bump PATCH and state the new version in the commit message; docs/session-only edits do not bump. Minor/major only on explicit ask.
- Settings footer shows `version · gitCommit · buildTime`; backend `GET /version` returns the same triple from `APP_VERSION`/`GIT_COMMIT`/`BUILD_TIME` injected by the deploy scripts.
- Android `versionCode` is internal packaging only — it is NOT the user-facing string, and `+N` never belongs in `pubspec.yaml`. `build-android.ps1` derives it as `major*1_000_000 + minor*10_000 + patch` and passes `--build-number`; Android release gates + keystore setup live in `docs/runbooks/android-release.md`.
- Env vars (incl. the `JWT_SECRET` rotation rule and the VAPID key-match footgun): see the runbook's env table.

## 6. Database and E2E safety

- Dev `docker-compose.yml`: bind-mounted backend, `NODE_ENV=development`, relaxed CORS, TypeORM auto-DDL. Prod `docker-compose.prod.yml`: `NODE_ENV=production`, restricted CORS, `synchronize` **OFF**.
- **Prod schema changes are numbered SQL files in `backend/migrations/`**, applied exactly once at boot by the migration runner; a failed migration aborts boot. Entities define the dev shape, the migration files are prod truth — full contract in `backend/CLAUDE.md` §4. Applied files are IMMUTABLE.
- Risky deploys get a staging dress rehearsal first; the canonical trigger list lives in the runbook ("Staging dress rehearsal") — do not restate it here, or the two copies drift. Skip rehearsal for UI work.
- Raw SQL must quote camelCase columns: `"deliveryStatus"`, `"createdAt"`. Casing is per entity — check, never guess.
- Backups (`./backup-db.sh`, `./setup-backup-cron.sh`, `./restore-db.sh`) are in the runbook. Dumps hold ciphertext, public keys, usernames/contact graph and password hashes — they cannot decrypt messages but are sensitive.
- **E2E invariant: the server stores Signal ciphertext and metadata, NEVER device private keys.** Device keys live in web localStorage / mobile secure storage. What actually destroys them: clearing site data, a browser-profile reset, iOS storage eviction, or uninstalling the **mobile** app. **Uninstalling the PWA generally does NOT** — it removes the shortcut, not the origin's storage, and `navigator.storage.persist()` (`main.dart`) asks the browser to exempt that origin from eviction. Deleting the account does not wipe local keys either; it only makes them useless. **Never tell a user to uninstall or clear site data as a fix** — that is the action that loses their history, and the previous wording here pointed straight at it (#105).

## 7. Shared wire contracts

- E2E envelope: `{ content, messageType?, mediaUrl?, mediaDuration?, mediaKey?, mediaIv?, linkPreview? }`. Ciphertext format is `"{type}:{base64}"` (`3` PreKey, `2` Signal/whisper). Server stores `[encrypted]` plus metadata.
- Socket readiness clock: after socket auth completes, server emits `socketReady` with `{ serverTime: string }`; `serverTime` is an ISO-8601 UTC instant stamped at that completion.
  - Why: this is the client's only trustworthy clock reference for gating destruction of expired message plaintext. Destruction requires a fresh observation (never extrapolated past 30 minutes) and `expiresAt` plus a 5-minute grace for the backend's per-minute cleanup cron.
  - Missing, stale, or unparseable `serverTime` fails silently closed: the client holds and never destroys expired plaintext — no error or log, while plaintext accumulates. This deliberate asymmetry accepts over-retention rather than permanent data loss: the server holds only ciphertext, which the client cannot decrypt after the Signal ratchet consumed the key.
  - Compatibility: older clients ignore the extra field; newer clients against older servers receive no usable clock and therefore never destroy plaintext on expiry.
  - In-session refresh: client emits `getServerTime` (no payload); server replies `serverTime` with `{ serverTime: string }`, same ISO-8601 UTC semantics. The client's sweep timer asks only when its last observation aged past the 30-minute extrapolation bound (floor-limited to one unanswered request per 5 minutes), so a connection that outlives the socketReady observation can still destroy expired plaintext instead of holding it until the next reconnect. An older server simply never answers and the client stays fail-closed.
- Local-plaintext reconciliation: client emits `getServedMessageIds` with `{ requestId: string, messageIds: number[] }` (≤500 ids); server replies `servedMessageIds` with `{ requestId, messageIds }` — the subset it would still serve that account through the history read path (row exists, caller is a participant, not hidden by them, not expired).
  - Why: the client DESTROYS the local plaintext of every id it asked about that is absent from the reply. That is the only mechanism that reaches messages deleted or expired before the metadata stamps existed — those records match no local rule and their server row is already gone, so nothing else would ever revisit them.
  - The reply is authoritative, so the server MUST stay silent on failure rather than answer with an empty list: an empty `messageIds` legitimately means "destroy all of them" (a fully cleared history). A missing reply purges nothing. `requestId` is echoed verbatim so a late or foreign answer cannot be applied to the wrong batch.
  - The existence check MUST remain at least as permissive as the history read path. A false "not served" is irreversible loss; a false "served" only defers cleanup. In particular it carries no `sender != me` or `deliveryStatus` predicate — either would report the caller's own outgoing history as gone.
  - Client throttles to one completed pass per 6 hours per account and only stamps completion when every batch was answered.
- Delete semantics:
  - Delete conversation: messages + conversation removed, friendship kept, WS `deleteConversationOnly`.
  - Unfriend: friend request + conversation + messages removed, friendship removed, WS `unfriend`.
  - Clear history: messages removed, friendship kept, WS `clearChatHistory`.
  - Delete for me: hidden for caller only, WS `deleteMessage mode=for_me`.
  - Delete for everyone: sender-only hard delete for both sides, clears pin, WS `deleteMessage mode=for_everyone`.
- Edit message: sender-only text edit within 15 minutes. Client sends a new ciphertext over the existing Signal session via WS `editMessage`; backend stays blind, replaces `encryptedContent`, stamps `editedAt`, emits `messageEdited`, rejects via `editMessageFailed` (`not_sender`, `window_expired`, `not_text`, `not_found`).
- Takeover alarm (Phase 0a, spec `docs/design/multi-device.md` §6.0): `uploadKeyBundle` that REPLACES the stored `identityPublicKey` writes a durable `identity_change_audit` row, emits `ownIdentityReplaced` `{ occurredAt }` to the account's OTHER sockets (uploader excluded), sends a content-free `{ type: 'identity_changed' }` push to every endpoint, and emits `peerIdentityChanged` `{ userId, occurredAt }` to every conversation peer's room. Same-identity re-uploads (the every-connect path) stay silent. The branch fires on legitimate reinstalls too — client copy must say "new device/browser sign-in", never "hacked".
- Registration lock (Phase 0b, spec §6.1): `uploadKeyBundle` that replaces the stored `identityPublicKey` is REFUSED unless it carries `identitySignature` + `nonce` (XEdDSA by the previous identity key over `newIdentityPublicKey ‖ userId ‖ nonce`, verified server-side with `curve25519-js`) or the account has a completed reset ceremony, which the upload SPENDS. Refusal emits `keyBundleUploaded { success:false, error:'identity_locked' }` — nothing written, no audit row, no alarm. Nonces come from `getRegistrationLockNonce` → `registrationLockNonce { nonce }`: 32 CSPRNG bytes, TTL 5 min, bound to the issuing socket, consumed by ONE upload attempt. Same-identity re-uploads and first-ever uploads are unaffected.
- Reset ceremony (Phase 0b, spec §6.2/§6.2.1): `resetIdentityRequest { recoveryPhrase? }` → `identityResetStatus { status: pending|existing|cooldown|invalid_phrase|locked, deadlineAt?, shortened? }`; a NEW ceremony also broadcasts `identityResetPending { deadlineAt, shortened, occurredAt }` to the whole user room plus a content-free `{ type: 'identity_reset_pending' }` push. `resetIdentityCancel` → `identityResetCancelResult { cancelled }`, and on a real cancel `identityResetCancelled { occurredAt }` room-wide plus `{ type: 'identity_reset_cancelled' }` push. Delay is 72 h, or 1 h when a valid recovery phrase is presented — the phrase SHORTENS, never silences, and is single-use. `setRecoveryKey { phrase }` → `recoveryKeySet { success }` stores an Argon2id verifier only (19 MiB / t=2 / p=1). Tables `identity_reset_requests` (terminal states; a partial unique index enforces one pending per account) and `recovery_keys`, migration `0014`. A completed ceremony stays spendable for 24 h — an unused grant lapses, because `cancelReset` cannot reach a row that already left `pending`.
- `checkOwnKeyBundle` → `ownKeyBundleStatus` now carries `{ exists, identityReset: {status, deadlineAt} | null, identityReplacedAt: string | null }`. The extra fields are additive; a missing or malformed payload still means UNKNOWN and MUST NOT authorize key generation. `identityReplacedAt` is what lets a session that was offline during a replacement raise its banner at connect time.
- Per-device key material (Phase 1, spec §4/§8): `uploadKeyBundle`, `uploadOneTimePreKeys` and `fetchPreKeyBundle` all take an OPTIONAL `deviceId` (1..100). Absent means device 1, so a client that predates devices keeps working — the rollout order is server first, clients later. Key bundles are unique per `(userId, deviceId)` and one-time pre-keys per `(userId, deviceId, keyId)`, so two devices may both hold keyId 0; the identity-epoch invariant is re-keyed to `(identityPublicKey, deviceId)` at all three sites (purge / claim / count). A device with no bundle of its own is served NOTHING — never a sibling's bundle, which would build a session it cannot decrypt. `keyBundleUploaded` gained `identityChanged: boolean` so the uploading device can tell its own replacement from someone else's. JWTs carry `deviceId`, refresh rows remember it, and `messages` gained `originDeviceId` (echoed in every message payload) plus a client-generated `sendToken`, UNIQUE per sender: a retry carrying the same token re-acks the committed row instead of writing a second message.

## 8. Adding cross-tier features

- New WS event: backend DTO + service handler + `@SubscribeMessage` in `chat.gateway.ts`; frontend `SocketService` emit/listen + `ConnectionProvider` routing + provider/model updates.
- New REST endpoint: backend controller/service with `JwtAuthGuard` where needed; frontend `ApiService` call + provider/screen wiring.
- New DB column: backend entity + numbered migration in `backend/migrations/` + mapper payload + frontend model `fromJson`/`copyWith` + tests. Dev auto-DDL does not mean prod is done. Rehearse the migration on the staging stack first (§6).

## 9. Agent skills

### Issue tracker

Issues live in GitHub Issues (`Lentach/Fireplace`) via the `gh` CLI; external PRs are not a triage surface. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Multi-context: `CONTEXT-MAP.md` at the root points to `backend/CONTEXT.md` and `frontend/CONTEXT.md`; system-wide ADRs go in `docs/adr/`, context-scoped ones in `backend/docs/adr/` and `frontend/docs/adr/`. **All of these are created LAZILY by `/domain-modeling` — their absence is normal, not a gap to fix or flag.** See `docs/agents/domain.md`.

Maintain this file by pruning. If a fact only matters while editing Flutter or NestJS code, put it in the tier file. After adding/removing backend tests, update the count in §3 so `node scripts/verify-claude-backend-test-counts.mjs` stays green.