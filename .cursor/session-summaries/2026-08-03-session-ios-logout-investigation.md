# Ketokeczup iOS logout — investigation + account recovery (no code changes)

**Date:** 2026-08-03 — Second PWA-logout incident (first: 2026-07-24, Android). Victim `Ketokeczup` (user 54), iPhone iOS 18.5. Investigation read-only against prod (DB + nginx + backend logs); recovery = manual password reset. **No repo code touched.**

## Root cause (device-side storage loss, server exonerated)

- His session was HEALTHY and sliding daily: refresh row created 06-30, last slide 08-02 08:00:48 UTC (matches nginx hit to the second, IP 37.248.220.119).
- 08-02 16:25 UTC: fully cold boot (every asset 200, no SW, no cache) with **no refresh attempt** → token gone from device storage. 08-03 06:14 UTC: cold again + **8× login 401** = `login failed identifier=ketokeczup` — **wrong password** (username lookup is case-insensitive, `users.service.ts:74`; no `(multiple users)` suffix → user found, bcrypt failed).
- **Every alternative excluded by evidence:** zero `/auth/refresh` non-201s in the whole Aug 1–3 nginx window; zero `/auth/logout` POSTs; his refresh row survived (→ no password-change revocation); all six `_clearLocalAuthState` callsites require either an HTTP round-trip (none happened) or the token already missing. Falsified the "deploy explains cold boot" theory: `main.dart.js` fetches are a flat 1–6/hr trickle Aug 1–3, no rollout wave — and a SW update wouldn't delete localStorage anyway.
- Signal keys NOT yet regenerated as of investigation (all 7 one_time_pre_keys xmin=802, ancient) — only because he hadn't logged back in. **Expect identity reset + peer banners on his next successful login; the OTP-upload fingerprint will confirm the keys died with the storage.**

## ⚠ Retraction worth remembering

- I claimed "UA contains `Version/18.5 … Safari/604.1` → Safari tab, not installed PWA". **Could not substantiate for modern iOS** — the token-stripping is documented for WKWebView/SFSafariViewController embeds and OLD home-screen apps; current sources (web.dev, firt.dev) say UA does NOT reliably distinguish standalone and recommend `navigator.standalone` / `display-mode: standalone`. Owner says he's on the installed PWA. **Do not use the UA heuristic again; browser-tab vs standalone is UNKNOWN for this incident.**
- Consequence tree: standalone-wipe → httpOnly cookie lives in the SAME partition and dies with it (buys ~nothing); durable answers are E2E key backup / server-side session recovery. Browser-tab-wipe → Home-Screen-install banner + httpOnly cookie are the right medicine. **Telemetry must decide before either ships.**

## Recovery performed (prod, 15:27 UTC)

- Mirrored `usersService.resetPassword` manually: bcrypt cost 10 hash computed INSIDE the backend container, `UPDATE users SET password, "passwordChangedAt"=now() WHERE id=54`, `DELETE FROM refresh_tokens WHERE user_id=54`.
- Temp password `Ognisko-Sowa-4821` — handed to owner to relay; user should change it in-app after login.
- Verified live: `POST /auth/login` (lowercase identifier) → 201; test session revoked via `/auth/logout` → 204; zero refresh rows left.

## Confusion resolved

- "He logged on and messaged me" — the message came from a DIFFERENT app (owner confirmed). Server state was unambiguous: no login success, no message from account 54 since 07-25.

## OWNER DECISION (end of session): ALL hardening DROPPED — do not build any of it unprompted

Owner's call, accepted: the wipe is OS-side and unpreventable; no beacon, no banner, no httpOnly cookie, no password-recovery work was authorized. The analysis below is preserved ONLY so a future session doesn't re-derive it — none of it is queued work.

1. **Client-mode beacon** (would decide everything): on login/refresh POST `{ standalone (navigator.standalone || display-mode), storagePersisted, sessionEndReason|null, platform }` → one backend `[Audit]` line. Note: `lastSessionEndReason` is in-memory only (`auth_provider.dart:169`) and already rendered on the login screen (`auth_screen.dart:209`) — after a wipe it is empty BY CONSTRUCTION, so only server-side telemetry can diagnose this class. Absence-of-reason on a fresh login = wipe fingerprint.
2. **iOS install banner** — only meaningful if browser-tab usage exists; must be gated on the client's own display-mode check (never UA) and worded per the iOS 16.4+ partition caveat: installing does NOT migrate the session. Never blast it at authenticated users (identityReset wave).
3. httpOnly refresh cookie — only helps tab-context ITP purges; dies with a PWA partition wipe.
4. Password recovery flow — the standing product gap (third incident where it bit); key backup remains on the Signal-grade queue independently.

## Traps for the next agent

- `refresh_tokens` columns are snake_case (`user_id`, `created_at`); `users`/`messages` are camelCase quoted (`"createdAt"`, but `messages.sender_id` IS snake). Check `\d` first.
- Multi-statement psql over `ssh` from Windows = quoting hell; stage a `.sql`/`.sh` file and `scp` it.
- `key_bundles.updatedAt` is reconnect-upsert NOISE, not a regeneration signal; OTP-row xmin is the real discriminator (unchanged rule from 07-24).
