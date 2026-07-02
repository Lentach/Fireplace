# CLAUDE.md — Fireplace Backend (NestJS)

Root rules, production safety, shared wire contracts, version policy, and env overview live in `../CLAUDE.md`. This file is for NestJS/PostgreSQL/server-specific facts only.

## 1. Commands

```bash
cd backend
npm ci
npm run build        # nest build
npm run start:dev    # nest start --watch
npm run start:prod   # node dist/main
npm test             # jest --config jest.config.json
```

Other scripts: `npm run test:watch`, `npm run test:cov`, `npm run test:debug`, `npm run lint` (fixing), `npm run format`.

Backend test count is documented in root `CLAUDE.md`, not here. CI captures backend Jest output and runs `node scripts/verify-claude-backend-test-counts.mjs --log backend/test-output.txt`.

Production backend deploy, on VM only:

```bash
cd ~/fireplace
./deploy-backend.sh
```

`deploy-backend.sh` does `git pull --ff-only`, derives `APP_VERSION` from `frontend/pubspec.yaml`, validates `.env`, builds/up's `docker-compose.prod.yml`, waits for Docker health, curls local `/version` and `/health`.

## 2. Runtime architecture

- `AppModule` imports Config, Schedule, Throttler, TypeORM, and domain modules: auth, media, users, conversations, messages, friends, blocked, FCM tokens, web push subscriptions, key bundles, push notifications, chat, secret notes, health, version.
- `main.ts` sets trust proxy, helmet, global `ValidationPipe({ whitelist:true })`, CORS, and listens on `PORT || 3000` at `0.0.0.0`.
- Production logger omits debug/verbose. Production CORS is restricted to `ALLOWED_ORIGINS`; dev allows localhost/127.0.0.1/192.168/10.*.
- `ChatGateway` authenticates Socket.IO with `handshake.auth.token`, rejects stale JWTs after password change, joins `user:<id>` room, tracks `onlineUsers: Map<userId, socketId>`, and delegates event handlers.
- Chat service map: `chat-message`, `chat-friend-request`, `chat-conversation`, `chat-key-exchange`, `chat-presence`, `chat-block`, `chat-search`, `chat-reaction`, `chat-link-preview`; shared `ChatValidationService` lives in `ChatValidationModule`.
- DTO validation uses `validateDto()` and class-validator decorators. Do not bypass it with ad hoc object checks.

## 3. Docker and environment

- Local `docker-compose.yml`: dev only, Node 20 bind mount, `NODE_ENV=development`, command `npm install && npm run start:dev`, Postgres 16 exposed at host `5433`, TypeORM auto-sync enabled by source.
- Prod `docker-compose.prod.yml`: built image from `backend/Dockerfile`, backend and DB bound to localhost only, `NODE_ENV=production`, persistent `pgdata` and `media_storage`, healthcheck on `http://127.0.0.1:3000/health`.
- `backend/Dockerfile`: multi-stage build, runtime installs prod deps only, copies `dist`, sets `NODE_ENV=production`, runs `node dist/main.js`. No `USER` directive; container runs as image default/root.
- `deploy.sh` is legacy/all-in-one; do not use it as backend production deploy path.

Backend env source:

| Var | Notes |
|---|---|
| `NODE_ENV`, `PORT` | `production` changes logger, CORS, TypeORM sync. |
| `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASS`, `DB_NAME` | Postgres; prod DB name is `chatdb`. |
| `JWT_SECRET` | Required; validation requires at least 32 chars. |
| `ALLOWED_ORIGINS` | Required in prod. |
| `MEDIA_BASE_URL`, `MEDIA_DIR` | Self-hosted media URLs and filesystem root. |
| `MEDIA_CLEANUP_GRACE_MS` | Used by orphan cleanup; default 15 min. Not class-validator validated. |
| `MEDIA_X_ACCEL_REDIRECT` | Use only when nginx has matching internal media route. |
| `FIREBASE_SERVICE_ACCOUNT` | Optional FCM; absent means FCM disabled. |
| `WEB_PUSH_VAPID_PUBLIC_KEY`, `WEB_PUSH_VAPID_PRIVATE_KEY`, `WEB_PUSH_VAPID_SUBJECT` | Web Push. Public key must match frontend build. |
| `APP_VERSION`, `GIT_COMMIT`, `BUILD_TIME` | `/version`; set by deploy script. |

## 4. Database and schema rules

Entities in `backend/src/**/*.entity.ts` are the source of truth. There are no real TypeORM migrations in this repo.

- TypeORM `synchronize` is `process.env.NODE_ENV !== 'production'`. Dev restart may create columns; prod will not. Every prod schema change needs manual SQL.
- Manual SQL notes currently relevant:
  - `messages.disappearAfterSeconds`: `ALTER TABLE messages ADD COLUMN "disappearAfterSeconds" integer NULL;`
  - message edit: `ALTER TABLE messages ADD COLUMN "editedAt" timestamp NULL;`
  - pinned messages: `ALTER TABLE conversations ADD COLUMN "pinnedMessageId" integer NULL;` plus `"pinnedAt" timestamp NULL`, `"pinnedByUserId" integer NULL`.
  - message index exists in entity as `@Index('idx_messages_conv_created', ['conversation', 'createdAt'])`; if prod needs a descending concurrent index, treat `CREATE INDEX CONCURRENTLY ... "createdAt" DESC` as manual DBA/perf work, not generated entity truth.
- Raw SQL must quote camelCase: `"deliveryStatus"`, `"hiddenByUserIds"`, `"expiresAt"`, `"createdAt"`.
- `users` unique key is `(username, tag)`, not username alone.
- `friend_requests.status` stores lowercase values (`pending`, `accepted`, `rejected`), unlike uppercase message enums.
- No FK to `users`: `key_bundles.userId`, `one_time_pre_keys.userId`, `fcm_token.userId`, `web_push_subscription.userId`, `secret_notes.creatorId`. Manual account-delete cleanup is required.
- Cascades present: friend request sender/receiver FKs, blocked blocker/blocked FKs, refresh token `user_id`. Conversations/messages do not cascade from users in entities.
- `messages.reactions` is nullable text containing JSON string `{ emoji: [userId] }`, not a JSON column.
- `messages.hiddenByUserIds` is comma-separated text for delete-for-me.

## 5. Auth and sessions

- JWT TTL is 24h. Refresh tokens are 365-day rolling, rotation on each refresh, SHA-256 stored in `refresh_tokens`.
- `POST /auth/logout` revokes the current refresh token. Password reset sets `passwordChangedAt`, revokes all refresh tokens, and `JwtStrategy.validate()` rejects old tokens with `iat <= passwordChangedAt`.
- Register/login use username#tag model; tag is a 4-digit string.
- Delete account deletes profile avatar, FCM tokens, Web Push subscriptions, key bundles/OTPs, conversation media, messages/conversations/friend requests, then user. Refresh tokens are removed by FK cascade.

## 6. Socket.IO contracts and rate limits

- Guarded disconnect is load-bearing: only delete `onlineUsers[userId]` if the disconnecting socket id still matches. iOS resume can connect a new socket before the old one times out.
- `ChatValidationService.validateCanMessage(senderId, recipientId)` is the shared blocked+friendship gate for messaging/start conversation.
- `handleStartConversation` requires friendship; emits `openConversation` only to caller and `conversationsList` updates as needed.
- `handleGetMessages` must load the conversation and verify caller membership before querying history. Non-members receive empty `messageHistory`.
- `handleMessageDelivered` must verify caller is the recipient, not sender.
- `handleMarkConversationRead` verifies membership, marks peer-sent messages read, stamps read-based disappearing expiry, and emits `messageDelivered` to sender and reader.
- `conversationsWithUnread` batches unread, last message, and pinned-message reads; do not reintroduce N+1 list queries.

Gateway throttles are source-truth in `chat.gateway.ts`:

- `sendMessage`, `getMessages`, list fetches: high-volume 300/15min where annotated.
- Mutating chat actions like clear/delete/edit/pin/timer/start are mostly 60/15min.
- Reactions: 120/15min. Search/friend/block/key-rebuild actions have lower limits.
- `messageDelivered`, `markConversationRead`, typing, voice-recording, upload key bundle, accept/reject friend request, and unblock are not all throttled. Do not document a blanket “read events throttled” rule.
- `WsThrottlerGuard` adapts Nest throttler to sockets with a no-op `res.header()` mock and user-id tracker.

## 7. Messages, disappearing, edit, pin, reactions

- Server never sees plaintext for encrypted messages. Stored `content` is `[encrypted]`; `encryptedContent` holds Signal ciphertext.
- E2E envelope metadata (`messageType`, `mediaUrl`, `mediaDuration`, `mediaKey`, `mediaIv`) is needed for media cleanup and client display; do not strip it because “server is blind”.
- Read-based disappearing messages: send stores `disappearAfterSeconds`, leaves `expiresAt=null`; `markConversationRead` sets `expiresAt = now + disappearAfterSeconds`. Never-read fallback expires at `createdAt + DISAPPEARING_MAX_UNREAD_SECONDS`.
- Expired-message cleanup runs every minute and deletes media files before removing rows.
- Delivery status never downgrades; enforced via `DELIVERY_STATUS_ORDER`.
- Delete-for-everyone deletes media before row removal and clears pin if the deleted message was pinned.
- Edit message: sender-only, TEXT-only, 15-minute window from `createdAt`; stores new ciphertext, stamps `editedAt`, leaves expiry/status untouched; rejects with `editMessageFailed` reason `not_sender`, `window_expired`, `not_text`, or `not_found`.
- Reactions: WS `addReaction` / `removeReaction` `{ messageId, emoji }`; DTOs accept one emoji grapheme (basic emoji, VS16, skin tones, ZWJ sequences, flags, keycaps) with a 32-code-unit cap, not the old six-emoji allowlist. Participant-checked in `ChatReactionService`; `MessagesService` JSON-parse/stringifies the text column; emits `reactionUpdated` to both sides.
- Pin/unpin validates conversation membership and message state; delete-for-everyone clears the pin.

## 8. Media and cleanup

- `POST /media/upload`: JWT-guarded, 20/min, 21 MiB limit; handles `image`, `voice`, `gif`, `file`, `avatar`. Voice returns `mediaDuration`; file returns `fileName`; avatar validates magic bytes.
- Avatars are public. `GET /media/msgs/:filename` is JWT-guarded. Filename must be a basename; no path traversal.
- `LocalStorageService` writes avatars to `avatars/<uuid>.(jpg|png)` and encrypted message blobs to `msgs/<uuid>.bin` under `MEDIA_DIR`.
- `MEDIA_URL_REGEX` allows either legacy Cloudinary HTTPS upload URLs or exact self-hosted `${MEDIA_BASE_URL}/media/(avatars|msgs)/<filename>.<ext>` with one path segment. This prevents SSRF/path traversal because URLs later become unlink targets.
- `LocalStorageService.deleteFile()` has a resolved-path containment check against `MEDIA_DIR`. Keep it even if DTO validation looks strict.
- `MEDIA_X_ACCEL_REDIRECT=true` only works with nginx internal `/internal/media/`; otherwise media responses can become empty 200s.
- Orphan/expired cleanup runs daily at 03:00. It scans `msgs`, compares non-expired references vs all references, skips files newer than `MEDIA_CLEANUP_GRACE_MS` (default 15 min), logs `scanned/deleted/orphan/expired/graceSkipped`.
- Block user / delete conversation / clear history delete self-hosted media before deleting DB rows; do not rely on daily cleanup for user-visible destructive actions.

## 9. Push notifications

- Push is dual-channel: FCM for native android/ios tokens, Web Push for PWA subscriptions.
- Payload is metadata-only: `type`, `conversationId`, `unreadCount`, `unreadTotal`, `unreadConversationIds`, `senderName`. Never include message text or keys.
- FCM initializes from `FIREBASE_SERVICE_ACCOUNT`; absent means disabled. Web Push initializes from VAPID env; absent means disabled.
- Coalescer buckets by `(recipientUserId, conversationId)`, debounce 2500 ms, max wait 10000 ms, latest `senderName` wins, and suppresses identical count repeat within 10000 ms.
- Push scheduling is skipped only when recipient socket exists and `client.data.pushClientState` says client visible + active conversation matches.
- `pushClientState` is set by WS event and stored on `client.data`; frontend should set `clientVisible=false` on inactive/background.
- Web Push subscriptions: `POST /users/web-push-subscription`, `DELETE /users/web-push-subscription`.
- FCM token endpoints: `POST /users/fcm-token`, `DELETE /users/fcm-token`.

## 10. Link previews and SSRF

- `ChatLinkPreviewService` skips encrypted messages and non-TEXT messages.
- Link preview fetching accepts only http/https public hosts; private/loopback/link-local ranges are blocked by `PRIVATE_IP_RE`.
- Redirects are manual (`redirect:'manual'`, max 5); every hop is revalidated. Do not switch to default fetch follow.
- `og:image` must be HTTPS and non-private; relative image URLs are resolved against page URL.
- Known residual: a public hostname resolving to a private IP is not pinned/blocked by DNS resolution. Do not claim it is.

## 11. Secret Notes

- Secret Notes (“Anti-Quantum Note”) are separate from chat E2E.
- `POST /notes` (JWT) stores ciphertext and returns a random 16-byte hex token. `expiresIn` is constrained to 2h/6h/12h, default 6h. Ciphertext max 65536 chars.
- `GET /note/:token` is public server-rendered HTML. AES-GCM key is in URL fragment (`#key`), never sent to server.
- `POST /note/:token/reveal` is public read-once: atomic `DELETE ... WHERE token AND expires_at > NOW() RETURNING ciphertext`.
- Expired notes are lazy-deleted on reveal and daily at 03:00.

## 12. REST/media/auth additions checklist

- New REST endpoint: DTO if input is non-trivial, service method, controller route, `JwtAuthGuard` unless deliberately public, throttle if user-triggered, frontend `ApiService` update.
- New WS event: DTO + service handler + gateway `@SubscribeMessage`, throttle decision, frontend socket emit/listener, provider state update, regression test.
- New DB field: entity + mapper payload + frontend model + manual prod SQL + test-count update if backend tests change.
- Any destructive path involving media must delete self-hosted files before row deletion or explicitly rely on the orphan cleanup grace logic.
