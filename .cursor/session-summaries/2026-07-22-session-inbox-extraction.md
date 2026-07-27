# 2026-07-22 — Contact form + inbox extracted to a standalone service

Owner ask: "extract the whole contact inbox thing to a fresh repo." Chose a
**lightweight standalone service** in a **private** repo, clean cutover, deployed.

## What shipped

### New repo: `Lentach/fireplace-inbox` (PRIVATE)
Tiny self-hosted service that owns everything under `/contact*`:
- **Stack**: Fastify 5 + `better-sqlite3` + `web-push`, TypeScript → `dist/`, one
  Docker container (multi-stage `node:22-bookworm-slim`, non-root, build tools in
  build stage so better-sqlite3 compiles if no prebuilt), `docker-compose.yml`
  (localhost `127.0.0.1:3001`, `inbox-data` volume, node-fetch healthcheck).
- **Endpoints** (byte-compatible with the old NestJS ones so the landing form +
  bookmarked inbox URL keep working): `POST /contact` (honeypot `website`, 5/15min
  per-IP throttle, trim + 400 empty, JSON `{message,replyTo?,website?}` → 204);
  `GET /contact/inbox?key=` (key-guarded, 404 on bad key, CSP nonce, message list +
  "Enable notifications"); `GET /contact/sw.js`; `GET /contact/manifest.webmanifest?key=`;
  `GET /contact/icons/:name` (bundled the two PNGs → fully self-contained, no dep on
  the Flutter asset host); `POST /contact/subscribe` (key-gated upsert). `GET /healthz`.
- Files: `src/{config,db,push,views,server}.ts`, `assets/icons/*`, Dockerfile,
  compose, README, `.env.example`. Inbox key ≥32 chars; sha256+timingSafeEqual guard.
- **No account doorbell** (the standalone has no user accounts) — inbox push only.
- `key is string` type guard + `Record<string,true>` icon table (harness TS rules).

### Deploy (VM `ubuntu@51.68.138.13`)
- Repo-scoped **read-only deploy key** (VM `~/.ssh/fireplace_inbox`, `Host github-inbox`
  alias in `~/.ssh/config`) — the existing `id_ed25519` is a deploy key locked to
  `Fireplace`, and GitHub blocks reusing one key across repos.
- Cloned to `~/fireplace-inbox`; `.env` built on the VM by copying
  `WEB_PUSH_VAPID_*` + `CONTACT_INBOX_KEY` straight from `~/fireplace/.env`
  (**reuse the same VAPID pair** so subscriptions/landing stay valid) + `PORT=3001`,
  `DB_PATH=/app/data/inbox.db`. Values never left the box.
- `docker compose up -d --build` → healthy, Web Push enabled.
- **nginx flip**: host `/etc/nginx/sites-enabled/fireplace` `location /contact`
  `proxy_pass` `127.0.0.1:3000` → `127.0.0.1:3001` (+ `X-Forwarded-For` for the
  Fastify `trustProxy` per-IP throttle). Done via a python replace (NOT sed — avoids
  the `$host` mangling), backup + `nginx -t` + rollback-on-fail. Reloaded OK.

### Monorepo cutover (`Lentach/Fireplace` master, commit `4609af2`, deployed v0.0.123)
- Deleted `backend/src/contact/` (controller, service, module, 2 entities, 2 DTOs,
  2 specs). Removed `notifyContact` + `sendRawWebPush` from
  `push-notifications.service.ts` (contact-only; `sendWebPushToUser` stays for chat).
  Removed the 3 `app.module.ts` wirings (2 entities + ContactModule).
- `frontend/nginx.conf` template `/contact` block → comment pointing to the external
  service (it can't `proxy_pass` by compose service name).
- **Migrations `0009`/`0010` LEFT in place** (immutable applied history); the
  `contact_messages` / `contact_push_subscriptions` tables stay orphaned in the
  Fireplace Postgres — harmless (synchronize OFF, nothing maps them).
- Tests **555/49 → 534/47** (CLAUDE.md §3 line updated, verifier OK). `nest build` clean.
- `./deploy-backend.sh` → healthy, `/version` = `4609af2`.

## Verification (all live)
- Local docker smoke: 16-endpoint sweep + path-traversal 404 + trim/honeypot/empty +
  throttle 6th=429 + doorbell push path + stale logic.
- VM-direct (`127.0.0.1:3001`) + public (`https://fireplace.ignorelist.com`) sweeps:
  inbox 200/404, sw 200, manifest 200/404, icon 200 (241279 B), e2e POST through the
  real domain → 204 → rendered → deleted (owner inbox back to 0).
- Backend-direct `127.0.0.1:3000/contact/inbox` → **404** (route gone). Both
  containers healthy. `/health` ok, `/version.json` frontend 0.0.122 unchanged.

## Notes for next session
- **Owner's inbox URL**: `https://fireplace.ignorelist.com/contact/inbox?key=<ROTATED-2026-07-27>`
  **The key that was pasted here in cleartext was ROTATED on 2026-07-27 and is DEAD** (verified:
  old key → 404, new key → 200). Issue #100, closed. The dead value survives in git history — that
  is accepted, not an open leak; do not re-raise it and do not scrub history. Read the current key
  with `ssh ubuntu@51.68.138.13 'grep CONTACT_INBOX_KEY ~/fireplace-inbox/.env'`; keep it in a
  password manager and **never** paste it into a summary again. iPhone setup still pending
  (Safari → Add to Home Screen → open from icon → Enable notifications).
- **Two doorbells still ring**: the new inbox service AND the old `bob208 (id 37)`
  account ping — WAIT, the account ping lived in the removed backend module, so it is
  now GONE with the cutover. `CONTACT_NOTIFY_USER_ID` in `~/fireplace/.env` is now a
  no-op (nothing reads it) — can be deleted anytime, no redeploy needed.
- **Update the fireplace-inbox service**: on the VM `cd ~/fireplace-inbox && git pull
  && docker compose up -d --build`. `.env` is gitignored (holds the reused secrets).
- Data does NOT carry over: the new service started on a fresh SQLite file (no real
  messages existed; test rows were deleted). Old rows remain in the orphaned Postgres
  tables if ever needed.
- Full deploy runbook for the inbox service: `.cursor/rules/production-vm-deploy.mdc`
  (added). Repo has its own README with the same steps.
