# Read-Based Disappearing Messages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Signal-style read-based disappearing messages with D/H/M/S conversation timer UI, never-read 1-day cap, and grandfathering of send-time `expiresAt` rows.

**Architecture:** New `disappearAfterSeconds` column on messages; `expiresAt` null at send for read-mode; set on `markConversationRead`. Shared `isMessageExpired()` helper drives history filter, unread counts, cleanup cron, and frontend sweep. Timer dialog replaces presets with localized D/H/M/S fields.

**Tech Stack:** NestJS 11 + TypeORM, Flutter 3.x, Socket.IO, class-validator

**Spec:** `docs/superpowers/specs/2026-05-16-read-based-disappearing-messages-design.md`

---

## Self-Review (risks)

| Risk | Mitigation |
|------|------------|
| Unread SQL only checked `expiresAt` | Centralize expiry SQL fragment in `MessagesService` |
| Reader never gets `expiresAt` in UI | Emit `messageDelivered` with `expiresAt` to reader socket too |
| Optimistic send showed send-time countdown | Stop setting optimistic `expiresAt`; use `disappearAfterSeconds` only |
| Cleanup cron missed never-read rows | Extend `MessageCleanupService` query with OR branch |
| `copyWith` drops new field | Add `disappearAfterSeconds` to `MessageModel.copyWith` |
| Prod DB | Document manual `ALTER TABLE` in CLAUDE.md (synchronize off in prod) |

**Spec coverage:** All locked decisions mapped to Tasks 1–8. No open questions.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `backend/src/messages/disappearing-messages.constants.ts` | MIN/MAX/UNREAD constants |
| `backend/src/messages/message-expiry.util.ts` | `isMessageExpired`, SQL fragment |
| `backend/src/messages/message.entity.ts` | `disappearAfterSeconds` column |
| `backend/src/messages/messages.service.ts` | create, read-mark expiry, unread SQL |
| `backend/src/chat/services/chat-message.service.ts` | send, getMessages filter, markRead emit |
| `backend/src/chat/dto/set-disappearing-timer.dto.ts` | Min(5) Max(2592000) |
| `backend/src/chat/dto/chat.dto.ts` | expiresIn Min(5) |
| `backend/src/messages/message.mapper.ts` | payload field |
| `backend/src/messages/message-cleanup.service.ts` | effective expiry delete |
| `frontend/lib/models/message_model.dart` | field + expiry helper |
| `frontend/lib/widgets/chat_action_tiles.dart` | D/H/M/S dialog |
| `frontend/lib/providers/messaging_provider.dart` | send, sweep, messageDelivered |

---

### Task 1: Backend constants and expiry utility

**Files:**
- Create: `backend/src/messages/disappearing-messages.constants.ts`
- Create: `backend/src/messages/message-expiry.util.ts`
- Create: `backend/src/messages/message-expiry.util.spec.ts`

- [ ] **Step 1: Write failing tests**

```typescript
// message-expiry.util.spec.ts
import { isMessageExpired } from './message-expiry.util';
import { Message } from './message.entity';

describe('isMessageExpired', () => {
  const now = new Date('2026-05-17T12:00:00Z');

  it('expires when expiresAt is in the past', () => {
    const m = { expiresAt: new Date('2026-05-17T11:00:00Z'), disappearAfterSeconds: null, createdAt: now } as Message;
    expect(isMessageExpired(m, now)).toBe(true);
  });

  it('never-read read-mode expires after 1 day from createdAt', () => {
    const m = {
      expiresAt: null,
      disappearAfterSeconds: 3600,
      createdAt: new Date('2026-05-15T12:00:00Z'),
    } as Message;
    expect(isMessageExpired(m, now)).toBe(true);
  });

  it('never-read read-mode not expired within 1 day', () => {
    const m = {
      expiresAt: null,
      disappearAfterSeconds: 86400,
      createdAt: new Date('2026-05-17T10:00:00Z'),
    } as Message;
    expect(isMessageExpired(m, now)).toBe(false);
  });

  it('grandfathered with future expiresAt is active', () => {
    const m = {
      expiresAt: new Date('2026-05-18T12:00:00Z'),
      disappearAfterSeconds: null,
      createdAt: now,
    } as Message;
    expect(isMessageExpired(m, now)).toBe(false);
  });
});
```

- [ ] **Step 2: Run test** — `cd backend && npm test -- message-expiry.util.spec.ts` — FAIL

- [ ] **Step 3: Implement constants + util**

- [ ] **Step 4: Run test** — PASS

---

### Task 2: Entity, create path, mapper

**Files:**
- Modify: `backend/src/messages/message.entity.ts`
- Modify: `backend/src/messages/messages.service.ts` (create options)
- Modify: `backend/src/messages/message.mapper.ts`
- Modify: `backend/src/messages/message.mapper.spec.ts`

- [ ] Add column `disappearAfterSeconds int nullable`
- [ ] `create()` accepts `disappearAfterSeconds`
- [ ] `MessageMapper.toPayload` includes `disappearAfterSeconds`

---

### Task 3: Send + getMessages + markConversationRead

**Files:**
- Modify: `backend/src/chat/services/chat-message.service.ts`
- Modify: `backend/src/chat/dto/chat.dto.ts` (`@Min(5)` on expiresIn)
- Modify: `backend/src/chat/dto/set-disappearing-timer.dto.ts`
- Test: `backend/src/chat/services/chat-message.service.spec.ts`

- [ ] **sendMessage:** `ttl = data.expiresIn ?? conversation.disappearingTimer`; if ttl > 0 → `disappearAfterSeconds = ttl`, `expiresAt = null`
- [ ] **getMessages:** filter with `!isMessageExpired(m, now)`
- [ ] **markConversationRead:** after READ batch, set `expiresAt` per read-mode row; emit `messageDelivered` to sender **and** `client.emit` to reader with `expiresAt` ISO

---

### Task 4: Unread counts + cleanup + media

**Files:**
- Modify: `backend/src/messages/messages.service.ts` (countUnread*, batch)
- Modify: `backend/src/messages/message-cleanup.service.ts`
- Modify: `backend/src/media/media-cleanup.service.ts`
- Test: `backend/src/messages/message-cleanup.service.spec.ts`

- [ ] Replace `(expiresAt IS NULL OR expiresAt > now)` with `NOT <effective-expiry-sql>`
- [ ] Cleanup finds rows matching `isMessageExpired` via query builder

---

### Task 5: markConversationAsReadFromSender in MessagesService

**Files:**
- Modify: `backend/src/messages/messages.service.ts`
- Test: new cases in `chat-message.service.spec.ts` or `messages.service` unit test

- [ ] After status update, for each `toUpdate` with `disappearAfterSeconds && !expiresAt`, set and save `expiresAt = now + seconds`
- [ ] Return messages with updated fields

---

### Task 6: Frontend model + provider

**Files:**
- Modify: `frontend/lib/models/message_model.dart`
- Modify: `frontend/lib/providers/messaging_provider.dart`
- Modify: `frontend/lib/providers/conversations_provider.dart`
- Create: `frontend/test/utils/message_expiry_test.dart`

- [ ] `kNeverReadRetentionSeconds = 86400`
- [ ] `MessageModel.isExpired(DateTime now)` static/instance helper
- [ ] Optimistic sends: `disappearAfterSeconds: ttl`, `expiresAt: null`
- [ ] `removeExpiredMessages` / `removeExpiredLastMessages` use helper
- [ ] `_handleMessageDelivered`: apply `expiresAt` from payload

---

### Task 7: D/H/M/S timer dialog + l10n

**Files:**
- Modify: `frontend/lib/widgets/chat_action_tiles.dart`
- Modify: `frontend/lib/l10n/app_en.arb`, `app_pl.arb`
- Run: `flutter gen-l10n`
- Create: `frontend/test/widgets/chat_action_tiles_timer_test.dart`

- [ ] Stateful `_TimerDialog` with 4 `TextFormField`s, validation 5–2592000, all-zero → null
- [ ] Split/join seconds for display

---

### Task 8: CLAUDE.md + verification

- [ ] Update CLAUDE.md disappearing-messages gotcha
- [ ] `cd backend && npm test`
- [ ] `cd frontend && flutter analyze && flutter test`
- [ ] `graphify update .`
- [ ] Single commit: `feat: read-based disappearing messages with D/H/M/S timer`

---

## Execution

Implement Tasks 1–8 sequentially on branch `feature/read-based-disappearing-messages`.
