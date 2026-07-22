# 2026-07-22 — fireplace-inbox: push anti-spam cooldown + inbox Clear button

## Why
The contact form is public; per-IP throttle (5/15min) doesn't stop distributed spam — each message buzzed the subscribed iPhone. Also wanted a way to wipe the inbox from the page itself.

## Changes (`fireplace-inbox` `14e99fe`, deployed on VM, healthy)
- **Push cooldown** (`server.ts` `notifyInbox`): at most one push per 5 min (`PUSH_COOLDOWN_MS`). Suppressed messages still stored; counter carried into the next push as `(+N more)`. SW's fixed `tag: 'contact-inbox'` already collapses displayed notifications.
- **`POST /contact/clear`** (key in JSON body, 32-128 chars schema, 30/min rate limit): bad key → 404 `text/plain` (same as unknown route), good key → deletes all `contact_messages`, 204.
- **Clear button** on the inbox page (`views.ts`): red-outline pill next to "Enable notifications", `confirm('Delete ALL messages?')` → fetch POST → reload. CSP-compatible (nonce script, `connect-src 'self'`).
- `db.ts`: `Store.clearMessages(): number`.

## Local dev note
A local clone now exists at `Desktop/fireplace-inbox` (was VM-only). Windows: `npm ci --ignore-scripts` (better-sqlite3 native build needs MSVC; tsc doesn't need the binary). Deploy = commit/push, then on VM `cd ~/fireplace-inbox && git pull && docker compose up -d --build` (scp'd .sh script pattern).

## Verification (live, via public URL + VM)
- Inbox page shows Clear; bad-key clear → 404; good-key → 204.
- Two rapid POSTs → 204/204, log shows `1/1 delivered` + `suppressed (cooldown, 1 held)` — exactly one iPhone buzz.
- After clear: 0 messages; iPhone push subscription INTACT (1 row — do not delete).

## Same day, earlier
Landing iOS keyboard-bounce saga: see `2026-07-22-session-ios-kb-bounce.md`.
