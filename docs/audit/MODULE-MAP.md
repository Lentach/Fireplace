# Fireplace — Module Map & Trust-Boundary / Data-Flow Overview

Companion to `AUDIT-PROGRESS.md` and `FINDINGS.md`. Describes the system's components, where
trust boundaries sit, and where plaintext vs ciphertext lives. Verified against source.

## 1. Topology (trust boundaries)

```
 ┌─────────────────────────── UNTRUSTED CLIENT ───────────────────────────┐
 │ Flutter app (Android / web-PWA / iOS-PWA)                               │
 │  • Signal Double Ratchet E2E (libsignal_protocol_dart) — keys on device │
 │  • AES-256-GCM media encryption (in isolate)                            │
 │  • Plaintext + private keys exist ONLY here                             │
 └───────────┬───────────────────────────────────┬────────────────────────┘
   REST (HTTPS, Bearer JWT)            Socket.IO (handshake.auth.token = JWT)
             │                                     │
 ════════════╪═════════════ TRUST BOUNDARY (network) ═══════════════════════
             ▼                                     ▼
 ┌────────────────────────────── NestJS backend (:3000) ───────────────────┐
 │  HTTP controllers (JwtAuthGuard)      ChatGateway (verifies JWT on conn) │
 │  auth / users / media / messages      → 10 chat-*.service delegates      │
 │  / secret-notes / health / version    push coalescing → FCM + Web Push   │
 │  Sees: ciphertext, metadata (graph, timestamps, types), media blobs,     │
 │        bcrypt hashes, refresh-token SHA-256, Signal PUBLIC keys.          │
 │  Never sees: message plaintext, private keys, media AES keys.            │
 └───────────┬───────────────────────┬────────────────────┬────────────────┘
             ▼                        ▼                    ▼
     PostgreSQL 16 (:5433)   Local disk /app/media   External push services
     (ciphertext+metadata)   (encrypted .bin blobs,  (FCM/Google, Apple,
                              public avatars)          browser push — see §4)
```

Reverse proxy: `frontend/nginx.conf` serves the built Flutter web bundle and proxies
`/media/* /health /version` to the backend; production media served via nginx `X-Accel-Redirect`
(`/internal/media/...`). Deploy: GCP VM pulls `master`, `deploy.sh` builds.

## 2. Where untrusted input enters (attack surface)

| Surface | Entry | AuthN | Notes |
|---|---|---|---|
| REST `/auth/*` | register/login/refresh/logout | none (pre-auth) | throttled; DTO-validated |
| REST `/users/*` | profile pic, password, delete, fcm/webpush tokens | JWT | whitelist ValidationPipe |
| REST `/media/upload` | multipart file (≤21MB) | JWT | avatar magic-bytes; blobs opaque |
| REST `/media/avatars/:f` | filename | **none** (public) | `path.basename` guard |
| REST `/media/msgs/:f` | filename | JWT | **no ownership check** (L-07) |
| REST `/messages/link-preview` | `{text}` | JWT | **server-side fetch (SSRF, M-04)** |
| REST `/notes`, `/note/:token*` | ciphertext / token | mixed (create=JWT, read=public) | read-once, hex token |
| WS handshake | `auth.token` | JWT verify | **no pwChangedAt check (M-05)** |
| WS events (~35) | JSON bodies | `client.data.user.id` | per-handler `validateDto` |

## 3. E2E crypto data flow (verified in backend; frontend pending F6/F7)

1. **Keygen (client):** identity key, signed pre-key, 20 one-time pre-keys. Private keys stay on
   device (DualStorage: secure storage + SharedPreferences; web = localStorage only).
2. **Publish (WS, self-scoped):** `uploadKeyBundle` (1/user upsert), `uploadOneTimePreKeys`
   (`{keys:[...]}`). Backend stores **public** keys only (`key_bundles`, `one_time_pre_keys`).
3. **Session build:** `fetchPreKeyBundle(userId)` — public bundle, atomic OTP claim
   (`UPDATE … RETURNING`), 750ms/pair throttle. Bundles public by Signal design (L-05 depletion).
4. **Encrypt (client):** envelope `{content, messageType, mediaUrl, mediaKey, mediaIv, …}` →
   `encryptedContent = "{type}:{base64}"` (3=PreKey, 2=Signal).
5. **Transport:** `sendMessage` stores `content='[encrypted]'` + `encryptedContent`; server can't
   read body. Media: AES-GCM blob uploaded to `/media/msgs`; keys travel only in the envelope.
6. **Decrypt (client):** Double Ratchet consumes the message key; decrypted content persisted to a
   local cache (the only surviving copy of one-shot media keys).
7. **Failure/rebuild:** centralized in `decideDecryptionFailure` (Duplicate/BadMac→terminal,
   no reset; NoSession→retry+rebuild request; identityReset→`requestSessionRebuild`). WS
   `requestSessionRebuild`/`sessionRebuildNeeded` relay (L-06).

Plaintext/keys NEVER cross the trust boundary; push payloads are **metadata-only** (§4).

## 4. Push pipeline (metadata only)

`chat-message.service` → (skip if focused, freshness-guarded) → `PushNotificationCoalescingService`
(2.5s debounce / 10s max, dup-count suppression) → `PushNotificationsService.notify`:
- **Web Push:** payload `{type, conversationId, unreadCount, unreadTotal, unreadConversationIds,
  senderName}` JSON, **VAPID-encrypted to the subscription** (push service can't read it).
- **FCM (android/ios):** same fields as `data` (Google FCM sees `senderName`+counts — metadata leak,
  acknowledged). Silent `contentAvailable` on iOS. No message text, no keys, ever.
- Service worker `web/web-push-sw.js` renders one card per conversation (tag `conversation-<id>`),
  writes the PWA badge (single-writer), handles deep-link via IndexedDB handoff.

## 5. Backend module inventory (domain → responsibility → trust note)

| Module | Files | Responsibility | Trust note |
|---|---|---|---|
| `auth` | controller/service/jwt strategy+guard/refresh-tokens/password | register/login/JWT/refresh | refresh hashed; pwChangedAt (REST only) |
| `users` | controller/service/entity/dto | profile, password, account delete, push-token reg | manual delete cascade |
| `chat` | gateway + 10 `chat-*.service` + dto/validator/guards/mappers | all realtime events | authz per handler via `client.data.user.id` |
| `key-bundles` | service + 2 entities | Signal public keys + OTP claim | public keys only |
| `messages` | service/controller/entity/mapper/cleanup/expiry | message store, history, expiry cron | **H-01 IDOR**, **H-02 traversal sink trigger** |
| `conversations` | service/entity | 1:1 conversation lifecycle | membership-checked |
| `friends` / `blocked` | service/entity | graph + block | caller-scoped |
| `media` | controller/local-storage/magic-bytes/cleanup/dto | upload + serve + GC | **H-02 traversal**, L-07 |
| `secret-notes` | controller/service/entity | self-destruct notes | E2E (fragment key), public read |
| `push-notifications` / `fcm-tokens` / `web-push-subscriptions` | services/entities | push fan-out | metadata-only |
| `health` / `version` / `config` | controllers + env.validation | ops | no-auth by design |

## 6. Frontend layers (from inventory; audited in F1–F17)

7 providers (`Auth`, `Connection`, `Conversations`, `Messaging` [core + 5 part-files],
`Friends`, `Encryption`, `Settings`) · services (`Socket`, `Api`, `Encryption`,
`MediaCrypto`, `EncryptedMediaUpload`, `LinkPreview`, push/badge stack) · screens · widgets
(message/input/audio/dialogs) · `utils/*` conditional stub/io/web platform shims ·
service worker `web/web-push-sw.js`. Plaintext + Signal private keys live only in this layer.
