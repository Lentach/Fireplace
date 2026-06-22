# Message Editing Implementation Plan

> **For agentic workers:** implement task-by-task; each task is TDD (failing test → minimal code → green → commit). Steps use `- [ ]`.

**Goal:** Let a user edit a TEXT message they already sent — E2E-safe (new ciphertext over the
existing Signal session), 15-min window, replace-in-place + `editedAt`, web + mobile.

**Architecture:** Mirror the delete-for-everyone WS flow. New `editMessage` event carries
`{ messageId, encryptedContent }`; server (sender-only, in-window) swaps stored `encryptedContent`,
stamps `editedAt`, broadcasts `messageEdited`. Recipient decrypts the new ciphertext (live for the
active conversation; deferred + cache-invalidated otherwise, including offline reconnect via an
`editedAt`-stamped plaintext cache).

**Tech Stack:** NestJS 11 + TypeORM + Socket.IO (backend), Flutter 3.x + Provider + libsignal (frontend).

**Spec:** `docs/plans/2026-06-22-message-editing-design.md`.

---

## File structure

**Backend**
- `backend/src/messages/message.entity.ts` — add `editedAt` column.
- `backend/src/messages/message.mapper.ts` — add `editedAt` to payload.
- `backend/src/messages/messages.service.ts` — `editMessage(messageId, userId, { encryptedContent, content })`.
- `backend/src/chat/dto/edit-message.dto.ts` — **new** DTO.
- `backend/src/chat/services/chat-message.service.ts` — `handleEditMessage`.
- `backend/src/chat/chat.gateway.ts` — `@SubscribeMessage('editMessage')`.
- Tests: `message.mapper.spec.ts`, `messages.service.spec.ts`, `chat-message.service.spec.ts`.

**Frontend**
- `frontend/lib/models/message_model.dart` — `editedAt`.
- `frontend/lib/services/socket_service.dart` — `editMessage` emit.
- `frontend/lib/providers/messaging/messaging_provider.actions.dart` — `editMessage` + edit-state.
- `frontend/lib/providers/messaging_provider.dart` — `_editingMessage` field + getters.
- `frontend/lib/providers/connection_provider.dart` — `messageEdited` listener.
- `frontend/lib/providers/messaging/messaging_provider.events.dart` — `onMessageEdited` + `_handleMessageEdited`.
- `frontend/lib/providers/messaging/messaging_provider.send.dart` — `_encryptAndEmitEdit`.
- `frontend/lib/providers/messaging/messaging_provider.decrypt.dart` — `editedAt`-stamped cache staleness.
- `frontend/lib/providers/messaging/messaging_provider.history.dart` — merge staleness on `editedAt`.
- `frontend/lib/providers/encryption_provider.dart` — `invalidateDecryptionCache(id)`.
- `frontend/lib/widgets/message/message_context_menu_overlay.dart` + `chat_message_bubble.dart` — eligibility + onEdit.
- `frontend/lib/widgets/input/chat_input_bar.dart` (+ editing banner) — composer editing state.
- `frontend/lib/widgets/message/chat_message_bubble.dart` — "edited" label.
- `frontend/lib/l10n/app_en.arb` + `app_pl.arb` — `messageEdited` label string (+ regen).
- Tests: provider + widget.

---

## Wire contract

- `editMessage` (client→server): `{ messageId: int, content: '[encrypted]', encryptedContent: string }`.
- `messageEdited` (server→both): `{ messageId, conversationId, content, encryptedContent, editedAt }`.
- `editMessageFailed` (server→editor only): `{ messageId, reason }` (window expired / not found / not sender).

---

## Backend tasks

### Task B1: `editedAt` column + mapper
**Files:** `message.entity.ts`, `message.mapper.ts`, `message.mapper.spec.ts`.
- [ ] Test: mapper includes `editedAt` ISO when set, `null` when not.
- [ ] Entity: `@Column({ type: 'timestamp', nullable: true }) editedAt: Date | null;`
- [ ] Mapper: `editedAt: message.editedAt ? new Date(message.editedAt as Date).toISOString() : null`.
- [ ] Green + commit.
- **Manual prod SQL:** `ALTER TABLE messages ADD COLUMN "editedAt" timestamp NULL;`

### Task B2: `editMessage` service method
**Files:** `messages.service.ts`, `messages.service.spec.ts`.
- [ ] Test: `editMessage` on non-sender returns null (no write); on sender sets `encryptedContent`+`content`+`editedAt` and returns row.
- [ ] Impl:
```ts
async editMessage(
  messageId: number,
  userId: number,
  fields: { encryptedContent?: string | null; content?: string },
): Promise<Message | null> {
  const msg = await this.msgRepo.findOne({
    where: { id: messageId },
    relations: ['sender'],
  });
  if (!msg || msg.sender?.id !== userId) return null;
  if (fields.encryptedContent !== undefined) msg.encryptedContent = fields.encryptedContent;
  if (fields.content !== undefined) msg.content = fields.content;
  msg.editedAt = new Date();
  return this.msgRepo.save(msg);
}
```
- [ ] Green + commit.

### Task B3: DTO + handler + gateway
**Files:** `chat/dto/edit-message.dto.ts` (new), `chat-message.service.ts`, `chat.gateway.ts`, `chat-message.service.spec.ts`.
- [ ] Test (spec): edit by sender within window → row updated + `messageEdited` to both sockets; non-sender → `editMessageFailed`; expired window → `editMessageFailed`; not-found → `editMessageFailed`; **expiry/deliveryStatus untouched**.
- [ ] DTO:
```ts
import { IsInt, IsOptional, IsString, MaxLength } from 'class-validator';
export class EditMessageDto {
  @IsInt() messageId: number;
  @IsOptional() @IsString() content?: string;
  @IsOptional() @IsString() @MaxLength(20000) encryptedContent?: string;
}
```
- [ ] `handleEditMessage` (mirror `handleDeleteMessage` head): validateDto → `findByIdWithConversation`
  → membership → **sender-only** (`message.sender.id === userId` else `editMessageFailed`) →
  **window** (`Date.now() - new Date(message.createdAt).getTime() <= 15*60*1000` else `editMessageFailed`,
  reason `'window_expired'`) → `messagesService.editMessage(...)` → emit `messageEdited` to client +
  `onlineUsers.get(otherUserId)`. Do NOT touch `expiresAt`/`disappearAfterSeconds`/`deliveryStatus`.
  Const: `EDIT_WINDOW_MS = 15 * 60 * 1000`.
- [ ] Gateway: copy the delete `@SubscribeMessage`/`@Throttle({ default:{ limit:60, ttl:900000 } })`
  block → `editMessage` → `chatMessageService.handleEditMessage(client, data, this.server, this.onlineUsers)`.
- [ ] Green + commit. Update `backend/CLAUDE.md` test count.

---

## Frontend tasks

### Task F1: `MessageModel.editedAt`
**Files:** `message_model.dart`, `test/models/message_model_test.dart` (or existing).
- [ ] Test: `fromJson` parses `editedAt`; `copyWith(editedAt:)` round-trips; absent → null.
- [ ] Add `final DateTime? editedAt;` to fields + ctor (`this.editedAt`); `fromJson`:
  `editedAt: json['editedAt'] != null ? DateTime.parse(json['editedAt'] as String) : null`;
  `copyWith` param `DateTime? editedAt` → `editedAt: editedAt ?? this.editedAt`.
- [ ] Green + commit.

### Task F2: socket + actions + edit-state
**Files:** `socket_service.dart`, `messaging_provider.actions.dart`, `messaging_provider.dart`.
- [ ] Core: `MessageModel? _editingMessage;` + `MessageModel? get editingMessage => _editingMessage;`
  `void beginEditMessage(MessageModel m){ _editingMessage=m; notifyListeners(); }`
  `void cancelEditMessage(){ if(_editingMessage!=null){_editingMessage=null; notifyListeners();} }`
- [ ] `socket_service.dart`: `void editMessage(int messageId, String encryptedContent){ _socket?.emit('editMessage', {'messageId':messageId,'content':'[encrypted]','encryptedContent':encryptedContent}); }`
- [ ] actions: `void editMessage(int messageId, String newContent)` → resolve recipient from active
  conv → optimistic: update row content+editedAt(now), re-enrich quotes, update lastMessage if last,
  store `_pendingEdits[messageId]=originalContent` → `_encryptAndEmitEdit(messageId, recipientId, newContent)`
  → `cancelEditMessage()`.
- [ ] Test (provider): `editMessage` emits `editMessage` with ciphertext and applies optimistic content+editedAt.

### Task F3: `_encryptAndEmitEdit`
**Files:** `messaging_provider.send.dart`.
- [ ] Impl (mirror `_encryptAndSend` encrypt steps; TEXT only, **no** link preview in v1 → preview cleared):
  guard `isE2EReady`; `ensureSession`; `ciphertext = encrypt(recipientId, jsonEncode(E2eEnvelope.build(newContent)))`;
  `_emit?.call('editMessage', {'messageId':messageId,'content':'[encrypted]','encryptedContent':ciphertext})`.
  On failure: revert `_pendingEdits[messageId]` into the row + snackbar via diag/log; clear pending.
- [ ] Test: covered by F2 + a failure-revert test.

### Task F4: `messageEdited` listener + `_handleMessageEdited`
**Files:** `connection_provider.dart`, `messaging_provider.events.dart`.
- [ ] `connection_provider`: `_socketService.on('messageEdited', (d)=>_messagingProvider?.onMessageEdited(d));`
  `_socketService.on('editMessageFailed', (d)=>_messagingProvider?.onEditMessageFailed(d));`
- [ ] `onMessageEdited(data)` → `_handleMessageEdited(data)`:
  - parse `messageId, conversationId, encryptedContent, editedAt`.
  - if id in `_deletedMessageIds` → return.
  - locate row in `_messages` (active) and/or `_conversationCache[conversationId]`.
  - **own** (senderId == currentUser): set `editedAt`; clear `_pendingEdits[messageId]`; row content already optimistic.
  - **peer**: invalidate caches (`_encryptionProvider?.invalidateDecryptionCache(messageId)`); build
    `candidate = row.copyWith(encryptedContent:newCipher, content:'[encrypted]', editedAt:edited)`;
    if conv active + E2E ready → `decrypted = await _decryptMessageAsyncQueued(candidate)`; apply
    `decrypted.content`+`editedAt`; `_persistDecryptedContent(decrypted)`; else store candidate in
    cache (content '[encrypted]') for decrypt-on-open.
  - update `lastMessages` if last; `_reEnrichAllReplyQuotes()`; `notifyListeners()`.
- [ ] `onEditMessageFailed(data)`: revert `_pendingEdits[messageId]` into row + snackbar flag; clear pending.
- [ ] Test: peer edit in active conv decrypts + updates; own edit reconciles editedAt; deleted-id no-op; reply quotes re-enriched.

### Task F5: offline/reconnect via `editedAt`-stamped cache
**Files:** `encryption_provider.dart`, `messaging_provider.decrypt.dart`, `messaging_provider.history.dart`.
- [ ] `EncryptionProvider.invalidateDecryptionCache(int id){ _decryptedContentCache.remove(id); }`
- [ ] `_persistDecryptedContent`: add `'editedAt': decrypted.editedAt?.toIso8601String()` into `data`.
- [ ] decrypt cache-restore (peer path): if `msg.editedAt != null` and
  (`persisted['editedAt']==null` or server `editedAt`.isAfter(persisted editedAt)) → **skip restore**,
  fall through to live decrypt.
- [ ] `_mergeMessagePreferNewer`: if `server.editedAt != null` and (`local.editedAt==null` or
  `server.editedAt!.isAfter(local.editedAt!)`) → do NOT keep local plaintext; force `content` from
  server placeholder (re-decrypt) and `invalidateDecryptionCache(server.id)`.
- [ ] Test: send A, send B, edit A offline, reconnect (history snapshot with A.editedAt newer) →
  A re-decrypts to new content, B intact (interleave assertion).

### Task F6: context-menu eligibility + onEdit
**Files:** `message_context_menu_overlay.dart`, `chat_message_bubble.dart`, `message_action_panel.dart`.
- [ ] Eligibility predicate (in `_openContextMenu` / passed to panel): show Edit only when
  `isMine && message.messageType == MessageType.text && message.id > 0 &&
   message.deliveryStatus ∈ {sent,delivered,read} && message.hasCopyablePlaintext &&
   DateTime.now().difference(message.createdAt) < const Duration(minutes:15)`.
  Pass `canEdit` to `MessageActionPanel`; hide the Edit row when false (drop `muted`).
- [ ] `onEdit`: `messaging.beginEditMessage(message)` (replaces the `messageEditComingSoon` snackbar).
- [ ] Test: Edit row hidden for unsent/old/non-text/peer messages.

### Task F7: composer editing banner + send routing
**Files:** `chat_input_bar.dart`, new `widgets/input/edit_preview_bar.dart` (mirror `reply_preview_bar.dart`).
- [ ] When `editingMessage != null`: show banner ("Editing message" + cancel) above input; prefill
  controller with `editingMessage.content` (once, on enter-edit); trailing send calls
  `messaging.editMessage(editingMessage.id, text)` instead of `sendMessage`; cancel → `cancelEditMessage()`
  + clear field.
- [ ] Test: widget — entering edit prefills field + shows banner; tapping send routes to `editMessage`.

### Task F8: "edited" label + ARB
**Files:** `chat_message_bubble.dart` (meta row), `app_en.arb`, `app_pl.arb` (regen `flutter gen-l10n`).
- [ ] ARB: `"messageEditedLabel": "edited"` (en) / `"edytowano"` (pl).
- [ ] In the bubble meta row, when `message.editedAt != null` render `l10n.messageEditedLabel` before/after time.
- [ ] Test: bubble shows the label when `editedAt` set, hidden otherwise.

---

## Verify
- `cd backend && npm test` (update CLAUDE test count).
- `cd frontend && flutter analyze` + `flutter test test/...` for touched suites.
- Bump pubspec PATCH.

## Self-review notes
- Types consistent: `editedAt` is `DateTime?` (FE) / `Date|null` (BE), wire is ISO string|null.
- No placeholders; link-preview-on-edit deliberately deferred (cleared on edit) per spec edge #7.
- Every spec section maps to a task: window→B3/F6, history(replace)→B2, editedAt→B1/F1/F8,
  wire→B3/F2/F4, edge#1→F4, edge#2 pin→F4 (lastMessage/pin refresh), edge#3 expiry→B3,
  edge#4 offline→F5, edge#5 race→F4 deleted-id, edge#6 read→B3 (no status change), edge#8 cache→F5,
  edge#9 last→F4.
