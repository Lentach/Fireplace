# Latest session summary

**Date:** 2026-07-22 — GIPHY attribution mark added to the GIF picker + web redeployed to **0.0.124** with a fresh, valid Giphy client key (GIF search restored on prod).

## What was done
1. **Official GIPHY attribution mark** in the GIF picker (`frontend/lib/widgets/gif_picker_sheet.dart`) — replaced plain `Text('Powered by GIPHY')` with `Powered by` + GIPHY's official logo image, theme-aware (white on dark / black on light via `Theme.of(context).brightness`); `errorBuilder` falls back to bold `GIPHY` text. Needed for the Giphy API **Beta→Production** upgrade (form requires the mark + a demo video).
2. **Bundled assets** `frontend/assets/giphy/giphy_logo_{white,black}.png` (registered in pubspec) — derived from GIPHY's own official logo (`Giphy/GiphyAPI` → `logo_buildtext_white_forever.gif`, last frame, white-bg keyed to alpha, mono-recolored). **CAVEAT**: self-composed lockup (label + official logo), NOT the exact Giphy attribution-pack PNG — drop-in swap path in the session file.
3. **Version 0.0.123 → 0.0.124** (`frontend/pubspec.yaml`); committed `462c797`, pushed to master. Backend untouched (still 0.0.123 / `4609af2`).
4. **Web redeployed** via `deploy-web.ps1` after owner added `$GiphyApiKey` (valid, 32-char) to gitignored `deploy-web.config.ps1`.

## Verification
- `dart analyze` clean; `flutter build web` → `commit=462c797, version=0.0.124`, published (atomic swap).
- Prod `/version.json` = **0.0.124**; served `main.dart.js` contains `462c797` (not stale); mark PNGs `/assets/assets/giphy/*` → 200.
- **Giphy key valid**: `api.giphy.com` trending `status:200/OK`, real `search?q=hello` → 200 → **GIF search restored** (was dead since the old key was revoked).

## Notes for next session
- **Giphy Production upgrade still pending OWNER action**: record the demo video from the LIVE app (Beta key works, ~42/hr) showing GIF search + a GIF being sent + the "Powered by GIPHY" mark, then submit via the dashboard. **Production-upgrade the key** or it 429s under real traffic.
- **Exact-mark swap (optional)**: overwrite `giphy_logo_black.png` (dark lockup → light theme) + `giphy_logo_white.png` (white → dark theme) with the official "Powered By GIPHY" PNGs from the form's download link — same filenames, zero code change; if they bake in "Powered by", also drop the separate `Powered by` Text.
- After deploy: fully close+reopen the PWA (never uninstall — wipes E2E keys). Deploy is single-worktree now (`Desktop/Fireplace` on master holds `deploy-web.ps1` + gitignored config).
- Full write-up: `2026-07-22-session-giphy-attribution-web-deploy.md`.

---
### Prior latest ↓

**Date:** 2026-07-22 (contact form + inbox EXTRACTED to standalone service `Lentach/fireplace-inbox` (PRIVATE), deployed; monorepo contact module removed; then security-hardened (`9efae5c`) after an independent review; Anti-Quantum Notes added to the landing site; iOS journey-DONE keyboard-bounce fixed on the landing — ALL LIVE)

## What was done
1. **New repo `Lentach/fireplace-inbox` (PRIVATE)** — tiny self-hosted service owning all of `/contact*`: Fastify 5 + `better-sqlite3` + `web-push`, TS→dist, one Docker container on the VM at `127.0.0.1:3001`. Endpoints byte-compatible with the old NestJS ones (landing form + bookmarked inbox URL unchanged): `POST /contact` (honeypot, 5/15min throttle, trim, 400 empty), `GET /contact/inbox?key=` (key-guarded, 404 bad, CSP nonce), `/contact/sw.js`, `/contact/manifest.webmanifest?key=`, `/contact/icons/:name` (icons bundled → self-contained), `POST /contact/subscribe`. No account doorbell (standalone has no accounts). `/healthz`.
2. **Deployed on VM** — repo-scoped read-only deploy key (`~/.ssh/fireplace_inbox` + `Host github-inbox` alias; the old `id_ed25519` is locked to Fireplace and GitHub blocks key reuse). Cloned `~/fireplace-inbox`; `.env` built on the box by copying `WEB_PUSH_VAPID_*` + `CONTACT_INBOX_KEY` from `~/fireplace/.env` (**reuse same VAPID**) + PORT/DB_PATH. `docker compose up -d --build` → healthy. **nginx flip** host `/contact` `proxy_pass` 3000→3001 (+`X-Forwarded-For`) via python replace (not sed → dodges `$host` mangling), backup + `nginx -t` + rollback. Reloaded OK.
3. **Monorepo cutover (`4609af2`, deployed v0.0.123)** — deleted `backend/src/contact/` + `notifyContact`/`sendRawWebPush` + app.module wiring; `frontend/nginx.conf` template `/contact` → pointer comment; migrations `0009`/`0010` LEFT (immutable; tables now orphaned/harmless). Tests **555/49 → 534/47** (CLAUDE.md §3 + verifier OK). Deploy rule updated with the inbox-service runbook.

## Verification
- Local docker smoke (16 endpoints incl. path-traversal 404, trim/honeypot/empty, 6th POST=429, doorbell path).
- VM-direct + public sweeps: inbox 200/404, sw/manifest/icon 200, e2e POST through `https://fireplace.ignorelist.com` → 204 → rendered → deleted (owner inbox back to 0).
- Backend-direct `127.0.0.1:3000/contact/inbox` → **404** (route gone). Both containers healthy; `/version`=`4609af2`, frontend `/version.json` 0.0.122 unchanged.

## Notes for next session
- **Owner inbox URL unchanged**: `https://fireplace.ignorelist.com/contact/inbox?key=547ac8b6927b2c42969c6478cc3cde1054a93d2d3a244280d1f1d0226d071d95` (same key, now the new service). **iPhone is SUBSCRIBED ✓** — a real `web.push.apple.com` row sits in the inbox DB (created 2026-07-22T04:20Z): the owner completed Add-to-Home-Screen + Enable notifications, and it survives container rebuilds via the `inbox-data` volume. The previously-"unproven" iOS-push link is now proven.
- **Account doorbell is GONE** with the cutover (it lived in the removed module). `CONTACT_NOTIFY_USER_ID` in `~/fireplace/.env` is now a no-op — deletable anytime, no redeploy.
- **Update the inbox service**: on VM `cd ~/fireplace-inbox && git pull && docker compose up -d --build` (`.env` gitignored, holds reused secrets). Fresh SQLite (no data carried; old rows sit in orphaned Postgres tables if ever needed).
- **Security hardening (`fireplace-inbox` `9efae5c`, after independent reviewer pass)**: `trustProxy: true`→`1` (per-IP throttle now keys on real client IP, not a spoofable XFF left entry); request-log serializer strips the `?key=` from app logs + nginx `location /contact` now `access_log off` + scrubbed 27 historical key lines from `access.log` (key absent from all logs); icon allowlist `in`→`hasOwnProperty.call` (no prototype-key bypass); `setNotFoundHandler` so a bad key 404 is byte-identical to an unknown route; `POST /contact/subscribe` now rejects non-https / private-host endpoints (key-gated SSRF hardening). Reviewer confirmed clean: key compare (constant-time), XSS/CSP, SQLi (parameterized), traversal, honeypot, input caps, Docker (non-root, no baked secrets).
- **Landing site** (`fireplaceWebsite` `fa1a922`, live at `/welcome/`): added an "Anti-Quantum Notes" feature card (4th in the grid: Sealed/Blind/Ephemeral/**Vanishing**) + a "secret notes burn on read" ledger line. Copy grounded in the app's own privacy description. HTML-only change (asset hashes unchanged).
- Three working areas now: `Desktop/Fireplace` (app monorepo, master), `Desktop/fireplace-landing` (repo `Lentach/fireplaceWebsite`), and the VM-only `~/fireplace-inbox` service (repo `Lentach/fireplace-inbox`, PRIVATE — no local Desktop clone yet).
- Full write-up: `2026-07-22-session-inbox-extraction.md`.
- **iOS keyboard bounce fixed** (`fireplaceWebsite` `52c74e1`→`9dc31db`→`ef42561`, live bundle `BBgyupuP`): journey DONE dismissed but keyboard bounced back on iOS. Fix layers: deferred blur in the suppress window, one-shot touchend `preventDefault` on the dismiss gesture (disarmed on touchcancel), and the decisive **readonly hammer** — `releaseKb()` sets both composers `readOnly` for 700ms (kb-lift-gated, desktop unaffected) so iOS cannot reopen the keyboard whatever refocuses. Details: `2026-07-22-session-ios-kb-bounce.md`. Awaiting owner iPhone confirm.

## Previous
- 2026-07-22: Landing CONTACT FORM (cross-repo): backend `POST /contact` module (`contact_messages` mig 0009, throttle+honeypot, `notifyContact` account ping) + "Transmission · to the builder" panel on `/welcome`. Both LIVE (backend `8fe4951`, landing `12eb949`). **NOTE: this whole feature has since been extracted to `fireplace-inbox` (above) and removed from the monorepo.** Full: `2026-07-22-session-contact-form.md`.
- 2026-07-22: Landing Rev 16 (hero `.enc-done` → pointerdown pattern) + landing EXTRACTED to standalone **PUBLIC** repo `Lentach/fireplaceWebsite` (subtree split, 67 commits; business-card README with live-shot gallery; regenerated 1200×630 og.png; monorepo `landing/` removed, CLAUDE.md §2 pointer). Accepted exposure: deploy script publishes VM SSH login (key-only). Full: `2026-07-22-session-landing-extraction.md`.
- 2026-07-21: Pre-release audit-fix on branch `fix/audit-bugs`, v0.0.123 — R2 chat-detail dedup, backend branch cleanup, FULL test-suite audit (backend 474→534, frontend 727→770), link-preview ULA regex fix, MainShell nav-policy extraction. R1/R3 skipped per owner. Full: `2026-07-21-session-audit-fix-refactors.md`.
- 2026-07-20 (+07-22 Rev 16): Landing `/welcome` Rev 7-16 — reduced-motion + rAF pause + SEO meta + a11y + skip bookends; `.kb-done` journey pill dismisses+hides on **pointerdown** (Rev 15); Rev 16: hero `.enc-done` same pattern. Astro 7.x (dependabot). Full: `2026-07-20-session-landing-nits.md`.
- 2026-07-20: Landing six owner nits + on-device Revisions 2-6. Committed `7aabcea`. Full: `2026-07-20-session-landing-nits.md`.
