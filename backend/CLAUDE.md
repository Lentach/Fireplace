# CLAUDE.md — Fireplace Backend (NestJS)

Cross-cutting rules, Quick Start, shared wire contracts, and env/config live in
the root `../CLAUDE.md` (always loaded). This file is auto-loaded by Claude Code
when you work under `backend/`.

---

## 1. Critical Rules & Gotchas

### TypeORM
- Always `relations: ['sender', 'receiver']` on friendRequestRepository — without: empty objects/crash
- Use find-then-remove for friend_requests delete — `.delete()` can't use nested relation conditions
- Always `new Date(val).getTime()` for expiresAt comparisons — TypeORM returns string or Date
- **Read-based disappearing messages:** Sends store `disappearAfterSeconds` with `expiresAt = null`. On `markConversationRead`, backend sets `expiresAt = now + disappearAfterSeconds` and emits on `messageDelivered`. Never-read fallback: expire after `createdAt + 86400s`. Grandfathered rows: send-time `expiresAt` only. Shared expiry: `backend/src/messages/message-expiry.util.ts`, frontend `lib/utils/message_expiry.dart`. Hearth Fade UI: `disappearing_timer_sheet.dart`, `hearth_fade_arc.dart`. Ephemeral accent: `RpgTheme.ephemeralAccent` (ember/light, teal/teal). Prod SQL: `ALTER TABLE messages ADD COLUMN "disappearAfterSeconds" integer NULL;`
- `deliveryStatus` never downgrades — enforced via `DELIVERY_STATUS_ORDER` map
- `synchronize` enabled only when `NODE_ENV !== 'production'` — no migrations

### Backend
- `ChatValidationService.validateCanMessage(senderId, recipientId)` — shared blocked+friends check
- `mediaUrl` must match `MEDIA_URL_REGEX` in `chat.dto.ts` — a Cloudinary upload URL **or** `${MEDIA_BASE_URL}/media/(avatars|msgs)/<file>.<ext>` (anchored, single segment, **no `..`/extra slashes**). Prevents SSRF **and path traversal (H-02, security)**: `mediaUrl` is later turned into a filesystem path and `unlink`ed (delete-for-everyone / block / expiry cron), so the old `…/media/.+` allowed `../../etc/passwd`. Defense in depth: `LocalStorageService.deleteFile` also runs a resolved-path containment check (`path.relative` vs `MEDIA_DIR`) and refuses anything escaping the root. The container also still runs as root (audit L-11). Regression: `chat.dto.spec.ts`, `local-storage.service.spec.ts`.
- **`getMessages` membership (H-01, security):** `handleGetMessages` loads the conversation and verifies the caller is `userOne`/`userTwo` before serving history (mirrors `handleMarkConversationRead`); non-members get an empty `messageHistory` and the query never runs. `findByConversation`'s `userId` arg is ONLY the deleted-for-me filter, never an authz check — without the membership gate any authenticated user could read any (sequential-id) `conversationId`. Regression: `chat-message.service.spec.ts`.
- Delete account cascade: key bundles → OTPs → msgs → convs → friend_reqs → user (no entity cascade)
- `conversationsService.delete()` deletes msgs first (no cascade)
- Skip server-side link preview when `encryptedContent` present
- `handleMessageDelivered` verifies caller is recipient (not sender)
- `handleStartConversation` requires friendship; emits `conversationsList` + `openConversation` to caller only
- OTP claim atomic: `UPDATE ... WHERE id = (SELECT ... LIMIT 1) RETURNING *`
- `isBlockedByEither` uses single OR query
- `_conversationsWithUnread` uses batch (2 queries total, not 2N)
- `og:image` validated via `isSafeImageUrl` (HTTPS + non-private); IPv6 brackets stripped; relative URLs resolved
- **Link-preview SSRF:** `fetchPreview` follows redirects **manually** (`redirect: 'manual'`, max 5 hops) and re-runs `isFetchableUrl` (http/https + non-private host) on **every** hop — `fetch`'s default `redirect: 'follow'` would chase a 3xx into a private/metadata host unchecked. Residual (known): a public host whose DNS resolves to a private IP isn't caught — needs resolve-and-pin; tracked for later.
- WS rate limiting: `WsThrottlerGuard`; `sendMessage` 300/15min; read events 300/15min; `searchUsers` 30/60s. Mock `res` with no-op `header()` for Socket.
- **Online-socket map (guarded disconnect):** `ChatGateway.onlineUsers` is `Map<userId, socketId>` (one socket/user); `newMessage` delivery is `server.to(onlineUsers.get(recipientId)).emit(...)`, else push fallback. `handleDisconnect` MUST only `onlineUsers.delete(userId)` when `onlineUsers.get(userId) === client.id` — on iOS suspend/resume the device reconnects with a NEW socket while the abandoned OLD socket lingers until its server-side ping timeout (~20s); an **unconditional** delete then evicts the live socket → `onlineUsers.get(recipientId)` is `undefined` → peers' messages silently fall back to push (**"notification arrives but the message never appears live"**, ~20s after each resume). Own sends still echo via `client.emit('messageSent')` (live socket), so only *peer* messages vanish. Regression: `chat.gateway.spec.ts` (stale-socket guard).
- Pre-key anti-depletion: same requester→target limited to 750ms min interval; tracker pruned TTL 10min + capped 10k entries
- JWT invalidation after password change: `passwordChangedAt` in `resetPassword`; `JwtStrategy.validate()` rejects `iat <= passwordChangedAt`. Also revokes all refresh tokens.
- **Pinned message:** `conversations.pinnedMessageId/pinnedAt/pinnedByUserId`. WS `pinMessage/unpinMessage` → `messagePinned/messageUnpinned`. Delete-for-everyone clears pin. Prod SQL: `ALTER TABLE conversations ADD COLUMN "pinnedMessageId" integer NULL;` / `"pinnedAt" timestamp NULL;` / `"pinnedByUserId" integer NULL;`
- **Reactions:** WS `addReaction`/`removeReaction` `{ messageId, emoji }` (participant-checked in `chat-reaction.service.ts`) → `messagesService.addOrUpdateReaction`/`removeReaction` (stores `messages.reactions` JSON `{emoji:[userId]}`) → emits `reactionUpdated` `{ messageId, conversationId, reactions }` to **both** caller and peer. Frontend: `MessagingActions.addReaction/removeReaction`; listener `ConnectionProvider.on('reactionUpdated')`; driven by the context-menu emoji bar (see frontend/CLAUDE.md).
- **Secret Notes ("Anti-Quantum Note"):** self-destructing note shared via link, separate from chat E2E (`secret-notes/`). `POST /notes` (JWT) `{ ciphertext, expiresIn }` → `{ token }` (16-byte hex); `expiresIn` ∈ `{7200,21600,43200}`s (2h/6h/12h, default 6h); `ciphertext` ≤ 65536. `GET /note/:token` (public) → server-rendered HTML landing page; `POST /note/:token/reveal` (public) is **read-once** — atomic `DELETE … WHERE token AND expires_at > NOW() RETURNING ciphertext`. AES-GCM **key lives in the URL fragment** (`#<key>`, never sent to server); server stores only `ciphertext` = `iv_b64:enc_b64`; client decrypts in-browser via WebCrypto. Lazy-delete on expiry + daily 3 AM `deleteExpiredNotes` cron.
- **Sessions:** JWT TTL 24h. Refresh tokens: 365-day rolling, rotation on each refresh, SHA-256 stored. `POST /auth/logout` revokes token.
- `GET /media/msgs/:filename` JWT-guarded; avatars public
- Daily cleanup: expired media deleted before rows removed. `cleanupOrphanedFiles()` daily safety net. **Grace period (I1):** before deleting an unreferenced file the cron `fs.stat`s it and SKIPS any whose mtime is within `MEDIA_CLEANUP_GRACE_MS` (default 15 min) — protects an in-flight upload whose `sendMessage` emit/persist hasn't landed (the 03:00 run can overlap a send); such a file is swept on a later run once it ages past the window and is still unreferenced. Returns a `MediaCleanupSummary` (`scanned/deleted/orphan/expired/graceSkipped`) and logs it: **ORPHAN** = no row references the file (the upload-ok/send-failed gap) vs **EXPIRED** = a row exists but is expired — two queries (non-expired set + all-referenced set) classify each delete. Grace uses **file mtime, not message timestamps**. Regression: `media-cleanup.service.spec.ts`.
- **E2E upload gap (I1):** upload success + sendMessage failure → orphaned `.bin`. Mitigated, not closed: cron now has a grace period (won't delete in-flight uploads — see above) + per-run orphan/expired/skipped counts to stdout (`docker logs`). Client side: `_encryptAndSend` logs `MEDIA_ORPHAN_LIKELY{tempId}` to `E2eDiagLog` when a send fails AFTER a successful upload (`mediaUrl` obtained, gated non-empty so text/ping never log) — id-only. Ordering (upload→send) + E2E envelope unchanged. **Retry does NOT re-upload** (verified): `retryFailedMessage` reuses the model's `mediaUrl`+`mediaKey`+`mediaIv` and re-runs the E2E send only; the re-upload branch fires only when the original upload never produced a URL (no orphan to multiply).
- Block user: deletes self-hosted media before conversation/messages (no wait for daily sweep)
- `GET /health`: `SELECT 1`, returns 503 on failure — no version fields (healthcheck contract)
- `GET /version` (no auth): `{ version, gitCommit, buildTime }` from env
- Raw SQL: use `"deliveryStatus"` quoted — PostgreSQL column is camelCase
- Composite index `idx_messages_conv_created` on `(conversation_id, createdAt DESC)` — manual in prod: `CREATE INDEX CONCURRENTLY idx_messages_conv_created ON messages (conversation_id, "createdAt" DESC);`
- SSRF: `PRIVATE_IP_RE` blocks 169.254.x, fe80:, RFC-1918, loopback
- Push: dual-channel FCM + Web Push. Coalesced per `(recipientUserId, conversationId)` ~2.5s debounce, ~10s max. Metadata-only payload: `conversationId`, `unreadCount` (per-conv), `unreadTotal`, `unreadConversationIds`, `senderName` (sender display name for the card title — approved; passed at schedule time from `chat-message.service`, latest wins per burst). Never message text or keys. **Duplicate-count suppression:** flush deletes its bucket BEFORE awaiting the unread summary, so a message landing in that await window is counted in flush #1 yet opens bucket #2 → second card with identical counts ("5 then 5"). `lastSent` tracker skips the send when `(unreadCount, unreadTotal)` are unchanged within 10s (server-side skip is safe — no push ⇒ nothing must be shown); TTL-pruned + 10k cap.
- `pushClientState` `{ activeConversationId, clientVisible }` — skip push when client visible + active matches. Set `clientVisible=false` on `AppLifecycleState.inactive` (not just paused). `ChatDetailScreen.dispose` clears active id.
- **Live-receive resume re-assert (iOS PWA):** on background→resume, iOS can dispose `ChatDetailScreen` and/or reconnect the socket while the chat is still on screen; `dispose` → `closeConversation` + `clearMessages` null `activeConversationId`/`_paginationConversationId`, so incoming messages land while no conversation is "active" and `_addMessageToState`'s gate (`msg.conversationId == (activeConversationId ?? _paginationConversationId)`) **drops** them — `updateLastMessage` still runs unconditionally, so the conv list updates but the open chat doesn't; recovery otherwise hinges on a race in `_onSocketReady` (re-fetches only if `activeConversationId != null`). Fix: `ChatDetailScreen.didChangeAppLifecycleState(resumed)` calls `reassertOpenConversationOnResume` (`utils/chat_resume_reassert.dart`) → `openConversation` + `loadCachedMessages` + `getMessages`, restoring active id (+ `pushClientState`) and refetching deterministically. Diagnosed via the temp `E2eDiagLog` `RECV_MSG`/`RECV_QUEUED`/`ADD_TO_STATE{appendedToOpenChat}` entries (in `messaging_provider.events.dart`/`.history.dart`) — **remove those once the fix is confirmed on-device**. Regression: `chat_resume_reassert_test.dart`.
- Web Push subscriptions in `web_push_subscription`. REST: `POST /users/web-push-subscription`, `DELETE /users/web-push-subscription`.

---

## 2. Architecture (backend)

**Backend:** `ChatGateway` (pure delegation) → 9 domain chat services (+ shared `ChatValidationService`; 10 `chat-*.service.ts` files total). Mappers: `UserMapper`, `MessageMapper`, `ConversationMapper`, `FriendRequestMapper` (all `toPayload()`). DTOs validated by `chat/utils/dto.validator.ts`.

---

## 3. File Location Map

Most files are discoverable by Glob; this section captures only grouping and the non-obvious locations.

**Backend (`backend/src/`):** one folder per domain — `auth/`, `users/`, `conversations/`, `messages/`, `media/`, `friends/`, `blocked/`, `key-bundles/`, `fcm-tokens/`, `web-push-subscriptions/`, `push-notifications/`, `secret-notes/` — each with `*.entity.ts` + `*.service.ts` (+ `*.controller.ts` for REST). WebSocket layer: `chat/chat.gateway.ts` (pure delegation) → `chat/services/chat-{message,conversation,friend-request,key-exchange,presence,block,search,reaction,link-preview}.service.ts`. DTOs `chat/dto/chat.dto.ts`; validation `chat/utils/dto.validator.ts` + `chat/services/chat-validation.service.ts`. Auth extras: `refresh-token.entity.ts`, `strategies/jwt.strategy.ts`, `password.constants.ts`. Wiring: `app.module.ts`.

---

## 4. Database Schema

Entities (`backend/src/**/*.entity.ts`) are the source of truth — only non-obvious facts live here.

**Relations:** `users`→`conversations` (userOne/userTwo), `users`→`messages` (sender), `users`→`friend_requests` (sender/receiver), `users`→`blocked_users` (blocker/blocked), `conversations`→`messages`. `messages.replyTo` self-references `messages` (`replyToMessageId`, `eager: false`). `key_bundles` (1/user) + `one_time_pre_keys` (many/user) hold Signal keys. **No FK to `users`:** `key_bundles`/`one_time_pre_keys`/`fcm_tokens`/`web_push_subscription`/`secret_notes` store a plain `userId`/`creatorId` int (no FK) — which is why account-delete cascade is manual (see §1).
**Eager loading:** `conversations.userOne/userTwo`, `messages.sender`, `friend_requests.sender/receiver`, `blocked_users.blocked` are `eager: true`; `messages.conversation` is `eager: false`.
**Enums:** `messages.deliveryStatus` `SENDING|SENT|DELIVERED|READ` (never downgrades) and `messages.messageType` `TEXT|PING|IMAGE|VOICE|GIF|FILE` store UPPERCASE values; `friend_requests.status` `PENDING|ACCEPTED|REJECTED` stores **lowercase** (`'pending'`/`'accepted'`/`'rejected'`) — raw-SQL trap.
**Non-obvious columns:** `messages.hiddenByUserIds` comma-separated string (default `''`); `reactions` nullable JSON `{emoji: [userId]}`; `linkPreviewUrl`/`linkPreviewTitle`/`linkPreviewImageUrl` flat columns (not JSON); `encryptedContent`/`expiresAt`/`disappearAfterSeconds`/`mediaUrl`/`mediaDuration` (int seconds)/`replyToMessageId` nullable. `conversations.disappearingTimer`/`pinnedMessageId`/`pinnedAt`/`pinnedByUserId` nullable. `web_push_subscription.expirationTime` bigint, stringified.
**Constraints:** `users` unique on `(username, tag)` (username not unique alone). No cascade on User entity. `friend_requests` unique on `(sender, receiver)` (no duplicate A→B); its sender/receiver + `blocked_users` blocker/blocked FKs are CASCADE. `secret_notes.token` unique. `blocked_users` unique on `(blocker_id, blocked_id)`. `refresh_tokens`: UUID PK, unique `token_hash`, FK `user_id` CASCADE.

---

## 5. Known Limitations

- `secret_notes` table auto-creation requires `NODE_ENV !== 'production'`
- Large files: `chat-message.service.ts`, `chat-friend-request.service.ts`.
