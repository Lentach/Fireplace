# Message Editing — Design Spec

**Date:** 2026-06-22
**Status:** Design approved (direction); implementation pending its own feature branch + PR.
**Scope:** Let a user edit a TEXT message they already sent, E2E-safe, mirroring the
existing delete-for-everyone flow. No production code in this pass.

---

## 1. Decisions (approved)

| # | Decision | Choice |
|---|---|---|
| a | v1 scope | **Text only** (no media/caption editing) |
| b | Edit window | **15 minutes**, server-enforced from `createdAt` |
| c | History policy | **Replace-in-place + `editedAt` flag** (no prior versions stored) |
| d | Platform parity | **Web + mobile** (shared Flutter codebase) |
| e | Disappearing timer on edit | **Do not reset** — `expiresAt`/`disappearAfterSeconds` untouched |

Rationale: 15 min is the industry floor (WhatsApp/iMessage); replace-in-place retains the
least ciphertext at rest (E2E-friendly) and is the simplest model; not resetting the timer
preserves expiry integrity (an edit must never extend a message's lifetime).

---

## 2. Research summary (cited)

| App | Window | Max edits | "Edited" label | History | Editable | Notify on edit |
|---|---|---|---|---|---|---|
| WhatsApp | 15 min (resets per edit) | unlimited in-window | always, no history | replaced silently | **text only** | none |
| Telegram | 48 h | unlimited | always | none | text **and** media/captions | none |
| Signal | 24 h (Note-to-Self forever) | **10** | "Edited", tappable → history | **kept** | text | tracks edit delivered/read |
| iMessage | 15 min (+2 min unsend) | **5** | "Edited", tappable → history | **kept** | text | iMessage-only |

Sources:
- WhatsApp — https://techcrunch.com/2023/05/22/whatsapp-now-lets-you-edit-messages-with-a-15-minute-time-limit/ ,
  https://www.aljazeera.com/news/2023/5/23/whatsapp-to-allow-users-to-edit-messages-within-a-15-minute-limit
- Telegram — https://x.com/telegram/status/1168523951695437824 ,
  https://www.ticktechtold.com/how-to-edit-telegram-sent-message/
- Signal — https://support.signal.org/hc/en-us/articles/6255134251546-Edit-Message ,
  https://signal.org/blog/new-features-fall-2023/
- iMessage — https://appleinsider.com/articles/22/06/06/new-imessage-edit-and-unsend-features-have-15-minute-time-limit ,
  https://www.macworld.com/article/821268/ios-16-imessage-editing-unsending-restrictions.html ,
  https://www.iphonelife.com/content/how-to-edit-messages-iphone-view-edit-history

Dominant patterns: a hard time window (15 min is the common floor); an always-visible
"edited" marker; text-only is the safe default (only Telegram edits media); edits never push
a new notification; history splits into silent-replace (WhatsApp/Telegram) vs kept+tappable
(Signal/iMessage). For an E2E app, "keep history" = more retained ciphertext per message,
which cuts against minimizing data at rest — hence replace-in-place for v1.

---

## 3. Current-state map (verified against source)

Edit mirrors **delete-for-everyone**. Confirmed flow:

- **DTO** — `backend/src/chat/dto/delete-message.dto.ts`: `@IsIn(['for_me','for_everyone']) mode`.
- **Gateway** — `backend/src/chat/chat.gateway.ts:205-218`: `@SubscribeMessage('deleteMessage')`
  + `@Throttle({ default:{ limit:60, ttl:900000 } })` → `chatMessageService.handleDeleteMessage(
  client, data, this.server, this.onlineUsers)` (pure delegation).
- **Service** — `backend/src/chat/services/chat-message.service.ts:372-462` `handleDeleteMessage`:
  `validateDto` → `findByIdWithConversation` → membership (`conv.userOne.id|userTwo.id === userId`)
  → `for_everyone`: media cleanup + `deleteById(messageId, userId)` (**sender-only**, false otherwise)
  → clears pin via `conversationsService.clearPinnedMessage` → emits `messageDeleted
  {messageId, conversationId, forEveryone}` to `client` **and** `server.to(onlineUsers.get(otherUserId))`.
- **Send / E2E envelope** — `handleSendMessage` (`chat-message.service.ts:32-137`):
  `messagesService.create(data.encryptedContent ? '[encrypted]' : data.content, …, { encryptedContent })`
  — server stores `content='[encrypted]'` + ciphertext, never sees plaintext/keys. Broadcasts via
  `MessageMapper.toPayload`: `client.emit('messageSent')`, `server.to(recipientSocketId).emit('newMessage')`.
  Server-side link preview **skipped when `encryptedContent` present** (`backend/CLAUDE.md`).
- **Entity** — `backend/src/messages/message.entity.ts`: `content`, `encryptedContent`,
  `messageType`, `expiresAt`, `disappearAfterSeconds`, `replyToMessageId`/`replyTo`, `reactions`,
  `linkPreviewUrl/Title/ImageUrl`. **No `editedAt`.**
- **Mapper** — `backend/src/messages/message.mapper.ts`: `toPayload` (no `editedAt`); reply
  snapshot uses `'Encrypted message'` placeholder for E2E rows (never plaintext).
- **Frontend model** — `frontend/lib/models/message_model.dart`: `fromJson` (`:118-151`),
  `copyWith` (`:195-238`, `??`-merge so a field can't be nulled). **No `editedAt`.**
  `mediaKey/mediaIv` are client-only (not in `fromJson`).
- **Frontend wiring** — emit `frontend/lib/services/socket_service.dart:110` +
  `frontend/lib/providers/messaging/messaging_provider.actions.dart:19` `deleteMessage`;
  listener `frontend/lib/providers/connection_provider.dart:449` `on('messageDeleted') → onMessageDeleted`;
  handler `frontend/lib/providers/messaging/messaging_provider.events.dart` `onMessageDeleted →
  _handleMessageDeleted`; late-history guard via `_deletedMessageIds` (`messaging_provider.dart:174`).
  Status-patch precedent `_handleMessageDelivered` (`messaging_provider.events.dart:154-203`) patches
  the in-chat row **and** the conversation-list `lastMessages` preview — the shape an edit needs.
- **Existing stub** — `frontend/lib/widgets/message/message_context_menu_overlay.dart:397-399`:
  `showTopSnackBar(l10n.messageEditComingSoon)`; ARB keys `messageEditComingSoon` exist
  (`app_en.arb:276`, `app_pl.arb:258`). Edit affordance already in the long-press menu; only the body
  is a placeholder.
- **Prod schema** — `synchronize` off in prod (`backend/CLAUDE.md`, root `CLAUDE.md`) ⇒ new column
  needs **manual SQL**.

---

## 4. Wire contract (new `editMessage` WS event)

Mirrors `deleteMessage`/`sendMessage`. Server stays blind to plaintext/keys.

- **Client → server** `editMessage`: `{ messageId: number, encryptedContent: string }`
  — a **new ciphertext over the existing Signal session** (`"{type}:{base64}"`); stored `content`
  stays `'[encrypted]'`.
- **Server → clients** `messageEdited`: `{ messageId, conversationId, content, encryptedContent,
  editedAt }` to `client` **and** `server.to(onlineUsers.get(otherUserId))`.

The edit ciphertext is just another ratchet message; it advances the Double Ratchet exactly like
a normal send. The server only swaps the stored `encryptedContent` and stamps `editedAt`.

---

## 5. Edge-case decisions

1. **Edited message quoted in a reply** — leave the stored reply snapshot (E2E `'Encrypted message'`
   placeholder server-side). Frontend reply previews resolve **live** via `findMessageById`
   (`frontend/CLAUDE.md`), so they reflect the new text automatically. No propagation code.
2. **Edit a pinned message** — pin stores only `pinnedMessageId`; on `messageEdited`, if it equals
   the pinned id, refresh the pinned-banner preview client-side. Small UI task.
3. **Edit an expiring message** — **do not reset** `expiresAt`/`disappearAfterSeconds`.
4. **Recipient offline** — replace-in-place: the DB row carries the new ciphertext + `editedAt`;
   recipient gets it via `messageHistory` on reconnect (no live broadcast needed). **E2E risk to
   validate:** the edit ciphertext sits at a later ratchet step; libsignal's skipped-message-key
   tolerance must cover the gap when the original ciphertext was replaced/never delivered — add an
   explicit offline-edit decrypt test.
5. **Edit vs delete-for-everyone race** — `handleEditMessage` emits an error on message-not-found;
   client treats `messageEdited` for a missing/`_deletedMessageIds` row as a no-op. Delete wins.
6. **Edit after read** — allowed within window; **do not touch `deliveryStatus`** (never downgrades).
   v1 does not track per-edit read state (unlike Signal).
7. **Link preview on edited URL** — content changed ⇒ existing `linkPreview*` is stale; clear it on
   edit and let the normal preview path regenerate. **Needs verification:** who populates
   `linkPreview*` for E2E rows (server skips it) — confirm the client-side owner before wiring.
   Acceptable v1 fallback: just clear the preview on edit.
8. **Search / client-side text** — on edit, update the decrypted-plaintext cache
   (`EncryptionProvider.saveDecryptedContent`; safe for TEXT — no media keys to clobber).
9. **Last vs older message** — if edited id == `lastMessages[conv].id`, also `updateLastMessage`
   (mirror `_handleMessageDelivered`); otherwise patch only the in-chat row + cache.

---

## 6. Phased implementation outline (no code)

- **P0 — schema + contract:** add `editedAt timestamp NULL` to `Message`; **manual prod SQL**
  `ALTER TABLE messages ADD COLUMN "editedAt" timestamp NULL;`; add `editedAt` to
  `MessageMapper.toPayload`; `messages.service.editMessage(messageId, userId, { encryptedContent })`
  (sender-only, sets ciphertext + `editedAt=now`, returns row|null). New `chat/dto/edit-message.dto.ts`.
- **P1 — backend handler:** `chat-message.service.handleEditMessage` (validateDto →
  `findByIdWithConversation` → membership → sender-only → 15-min window check on `createdAt` →
  update → clear `linkPreview*` → emit `messageEdited` to client + other socket; leave
  expiry/`deliveryStatus` untouched); `chat.gateway.ts` `@SubscribeMessage('editMessage')` +
  `@Throttle` (mirror delete 60/15min) → delegate.
- **P2 — frontend model + wiring:** `MessageModel.editedAt` (+ ctor/`fromJson`/`copyWith`);
  `socket_service` emit + `messaging_provider.actions.editMessage`; `connection_provider`
  `on('messageEdited')`; `messaging_provider.events.onMessageEdited → _handleMessageEdited`
  (patch row, decrypt if encrypted, update cache + `lastMessages`, refresh pin, guard deleted rows).
- **P3 — send/encrypt reuse:** encrypt new plaintext via existing `EncryptionService` session →
  `editMessage` emit; optimistic local update (sender has plaintext) + reconcile on echo +
  revert/snackbar on reject (retain original to revert).
- **P4 — UI:** replace the `messageEditComingSoon` snackbar in `message_context_menu_overlay.dart`
  with edit-mode entry (gate: own + TEXT + within window); composer "editing" banner (mirror
  `reply_preview_bar.dart`); "edited" label in `ChatMessageBubble` meta (new ARB `messageEditedLabel`);
  pinned-banner refresh.
- **P5 — tests:** backend spec (happy path, non-sender reject, expired-window reject, not-found,
  pin refresh, expiry untouched, **offline-edit decrypt/ratchet**); frontend (`onMessageEdited`
  row+last+cache, optimistic+revert, `fromJson`/`copyWith` round-trip, context-menu eligibility).
- **P6 — deploy:** feature branch + PR (substantial); patch version bump; **run manual SQL first**,
  then `git pull && docker compose restart backend` / `deploy-backend.sh`; frontend via `deploy-web.ps1`.

---

## 7. Constraints honored

- E2E: edit = new ciphertext over the existing Signal session; envelope stays metadata-only; server
  never sees plaintext or keys.
- Mirrors the delete-for-everyone event pattern (no parallel mechanism).
- Prod `synchronize` OFF → manual SQL spelled out (P0).
- Adjacent ideas flagged, not folded in: edit history (kept versions), media/caption editing,
  per-edit read tracking, group-chat semantics.
