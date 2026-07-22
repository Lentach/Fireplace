# Session — landing contact form ("Transmission · to the builder"), cross-repo

**Date:** 2026-07-22
**Repos:** monorepo `fireplace-ping-deploy` (backend) + `Lentach/fireplaceWebsite` (landing, local clone `Desktop/fireplace-landing`)

## What was done
Owner picked option A (self-hosted form; alternatives B mailto-only and C third-party
form were rejected — C clashes with the page's "no third party" pitch).

### Backend (`8fe4951`, deployed to prod)
- **`POST /contact`** (public, `@Throttle` 5/15min per IP): new `contact` module —
  `CreateContactDto` (message 1–2000, optional replyTo ≤320, declared honeypot field
  `website` so `whitelist:true` doesn't strip it), controller trims + rejects
  whitespace-only messages (400), silently 204s honeypot fills without saving.
- **`contact_messages` table** via migration `0009_contact_messages.sql`
  (id/message/"replyTo"/"createdAt"; entity registered in AppModule).
- **Owner ping**: `PushNotificationsService.notifyContact(userId)` sends Web Push
  `{type:'contact', senderName:'Contact form'}` to `CONTACT_NOTIFY_USER_ID`'s devices.
  The DEPLOYED SW already renders conversationId-less payloads as a generic
  "Contact form / New message" card (no deep-link) — ZERO frontend/SW changes, no
  version bump. No FCM on purpose (typed new_message tap-routing contract). Push
  failure never fails the submission (fire-and-forget with catch). Env unset =
  store-only. `.env.example` documents it. **`CONTACT_NOTIFY_USER_ID` is NOT yet set
  on the VM** — waiting for the owner to name their account (users table has ~90 real
  accounts; guessing risks pinging a stranger).
- Web Push send loop extracted to `sendWebPushToUser()` (notifyWebPush behavior
  unchanged).
- Tests: contact controller/service specs, +10 → **544 tests / 49 suites**, root
  CLAUDE.md count updated, `verify-claude-backend-test-counts.mjs` OK. (While editing
  CLAUDE.md §3 a swap ate the "Phone on WiFi" line — restored.)
- **nginx**: `location = /contact` proxy added to repo template (`frontend/nginx.conf`,
  backend:3000) AND the VM host config (127.0.0.1:3000; first sed attempt mangled
  `$host` via ssh-escaping — nginx -t caught it BEFORE reload, repaired via
  base64→python rewrite, `nginx -t` + reload OK).
- **Deploy**: `./deploy-backend.sh` on VM → healthy, `/version` = `8fe4951`,
  migration 0009 applied. NOTE: deploy also shipped owner-merged dependabot backend
  bumps (typeorm 1.0.0→1.1.0 MINOR, fast-xml-parser, fast-uri) — full 544-test suite
  passed on that exact tree; the live contact write/read exercised real TypeORM SQL.

### Landing (`12eb949`, deployed: JS `C9gKtxdl`, CSS `BytA_mRv`)
- `.contact` section between outro and footer: terminal-styled panel (mirrors `.enc`
  tokens) — mono label `TRANSMISSION · TO THE BUILDER`, status dot (Ready/Sending/
  Sent · sealed away ✓/Too many/Failed), textarea + optional reply-to + SEND pill,
  offscreen honeypot input, honesty note ("straight to our own server…"), a11y
  focus rings. `contact.ts` posts same-origin `/contact`; blurs fields inside the
  tap gesture (mobile keyboard drops on send); 429 → dedicated message; 6s status
  revert.

## Verification
- Backend: `npm test` 544/49 green; count verifier OK.
- Live smoke (curl): valid → 204 + row in `contact_messages`; honeypot → 204 + NO
  row; whitespace message → 400.
- Live e2e (headless browser on PROD page): typed message, clicked Send →
  network 204, UI "Sent · sealed away ✓", row landed in Postgres. Smoke rows deleted
  afterwards (table left empty).
- Preview interception test verified exact POST body shape (empty honeypot omitted).

## Key files
- `backend/src/contact/*` (module/controller/service/entity/DTO/specs)
- `backend/src/push-notifications/push-notifications.service.ts` (notifyContact + extract)
- `backend/migrations/0009_contact_messages.sql`, `backend/.env.example`
- `frontend/nginx.conf` (+ VM `/etc/nginx/sites-enabled/fireplace`)
- landing repo: `src/pages/index.astro`, `src/scripts/contact.ts`, `src/scripts/main.ts`,
  `src/styles/landing.css`

## Notes for next session
- **Set `CONTACT_NOTIFY_USER_ID=<owner's user id>` in VM `~/fireplace/.env`** once the
  owner names their username#tag (look up id via psql), then re-run
  `./deploy-backend.sh` (or restart backend) to activate the Web Push ping.
  Until then messages are stored only: read with
  `docker compose -f docker-compose.prod.yml exec db psql -U postgres -d chatdb -c 'select * from contact_messages order by id desc'`.
- Contact throttle is per-IP 5/15min; global 100/15min still applies.
- Landing repo owns the form UI; backend owns the endpoint — cross-repo feature.

## Addendum — owner inbox page with account-independent push (same day)

Owner: notification arrived (after the compose-env fix `63490d8` — CONTACT_NOTIFY_USER_ID
was in .env but NOT in docker-compose.prod.yml's explicit environment list, so the container
never saw it; both earlier pings were silent no-ops. compose passthrough + prod-visible
log line added). Owner then rejected the account tie ("what if I delete this acc") →
built the inbox (commits `cce9fb8`, `5aaa71c`):

- **`GET /contact/inbox?key=<CONTACT_INBOX_KEY>`** — key-guarded server-rendered inbox
  (dark mono, CSP nonce, X-Robots noindex; 404 on bad key = invisible without the
  bookmark). Lists newest-first (take 200), escaped HTML.
- **Own push channel, no user account**: `contact_push_subscriptions` (migration 0010,
  upsert on endpoint), `POST /contact/subscribe` (key-gated), SW at `/contact/sw.js`
  (scope /contact/), manifest at `/contact/manifest.webmanifest?key=` (standalone —
  iOS 16.4+ delivers Web Push only to home-screen web apps; apple meta tags on page).
  Pushes carry a ~120-char message preview + deep-link URL back to the inbox.
  `PushNotificationsService.sendRawWebPush()` primitive; stale subs pruned on send.
- **CSP bug caught live**: script-src nonce blocked SW registration → added
  `worker-src 'self'` (`5aaa71c`). Verified live: SW registers scope /contact/.
- nginx `/contact` exact→prefix (template + VM). `CONTACT_INBOX_KEY` generated on VM
  (openssl rand -hex 32, in ~/fireplace/.env + compose passthrough).
- Tests → **555 / 49 suites** (CLAUDE.md + verifier OK).
- Verified live: bad key 404, good key 200 page with all messages, sw.js 200,
  manifest 200, form POST still 204, icons 200. Headless CANNOT prove the
  subscribe→push loop on iOS — owner must Add to Home Screen + Enable notifications
  on device (same iOS caveat as every push feature).
- Both doorbells now active: account ping (CONTACT_NOTIFY_USER_ID=37) + inbox subs.
  Owner can unset the account one whenever after confirming inbox push works.
