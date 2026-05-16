# Read-Based Disappearing Messages + D/H/M/S Timer — Design Spec

**Date:** 2026-05-16  
**Status:** Approved

---

## Problem Statement

Fireplace disappearing messages today use a **fixed preset list** (30s … 1 day) and set `expiresAt` at **send time**. Users want:

- **Any duration** via days/hours/minutes/seconds (not presets only).
- **Signal-style read timer:** countdown starts when the recipient **reads** the message; the sender’s copy starts then too.
- **Changing the conversation timer** affects **only new** messages; existing messages keep the rule they were created with.
- **Never-read fallback:** messages must not live forever if the chat is never opened.

---

## Product Decisions (Locked)

| Decision | Choice |
|----------|--------|
| When timer starts | **On read** (`markConversationRead`), Signal-style **A** — not on send, not on delivery/arrival. |
| Sender vs recipient | **One shared `expiresAt` per message** in DB; set when recipient reads; both clients get it via `messageDelivered` (extend payload with `expiresAt`). |
| Per-message TTL | **`disappearAfterSeconds`** frozen at **send** from conversation `disappearingTimer`. |
| Conversation timer change | Updates `conversations.disappearingTimer` only; **new sends** copy it; old rows unchanged. |
| Grandfathering | Messages already in DB keep existing **send-time** `expiresAt`; no migration to read-based. |
| Timer UI | **D / H / M / S** numeric fields only (no preset chips). |
| Default timer | **1 day** (`1` / `0` / `0` / `0`) for new conversations. |
| Off | **All fields zero** → `disappearingTimer = null`. |
| User TTL range | **5 seconds** – **30 days** total (inclusive). |
| Never-read retention | **1 day from send** (`createdAt + 86400s`); fixed constant in v1 (not user-configurable). |
| Read TTL vs send cap | **No** “max 1 day from send even after read.” If user sets 2 days, message may live **2 days after read** (Signal-like). The 1-day rule applies **only when never read**. |

---

## Plain-Language Expiry Rules

### New read-mode messages

1. **At send:** store `disappearAfterSeconds`; leave `expiresAt = null`.
2. **When recipient opens chat** (existing `markConversationRead` batch): for each newly READ message with `disappearAfterSeconds` and `expiresAt IS NULL`, set `expiresAt = now + disappearAfterSeconds`; notify sender (and recipient) with updated `expiresAt`.
3. **If never read:** message is treated as expired when `now > createdAt + 1 day` (even if `expiresAt` is still null).
4. **After read:** message is expired when `now > expiresAt` (user-chosen TTL from read moment).

### Grandfathered messages

- Rows that already have **send-time** `expiresAt` (and no `disappearAfterSeconds` / legacy path) behave exactly as today.

### Changing conversation timer

- Only changes default for **future** sends.
- Does not recompute `expiresAt` on existing messages.

---

## Timer UI (Same Entry Point)

- Keep **Timer** action tile → dialog (`_TimerDialog` in `chat_action_tiles.dart`).
- Replace `RadioListTile` presets with four inputs: **Days, Hours, Minutes, Seconds**.
- Show localized summary (e.g. “2 days 3 minutes”).
- **Apply:** `totalSeconds = d*86400 + h*3600 + m*60 + s`; if `totalSeconds == 0` → `setDisappearingTimer(convId, null)`; else validate range and emit socket event.
- **Reopen:** split `conversation.disappearingTimer` into D/H/M/S; if null, show all zeros.
- Localize title, labels, validation errors (dialog is English-only today).

---

## Data Model

### `conversations` (unchanged)

- `disappearingTimer: number | null` — seconds; default **86400** for new conversations in entity.

### `messages` (add column)

- `disappearAfterSeconds: number | null` — TTL frozen at send; null = non-disappearing or grandfathered.

### `messages.expiresAt` (semantics)

| Message type | At send | After read |
|--------------|---------|------------|
| Grandfathered | `expiresAt` set (send + old timer) | Unchanged |
| New read-mode | `expiresAt = null` | `expiresAt = readAt + disappearAfterSeconds` |

---

## Backend Changes

### Constants

- `DISAPPEARING_MIN_SECONDS = 5`
- `DISAPPEARING_MAX_SECONDS = 2592000` (30 days)
- `DISAPPEARING_MAX_UNREAD_SECONDS = 86400` (1 day never-read retention)

### `sendMessage` / message create

- Do **not** set `expiresAt` from `expiresIn` for new read-mode messages.
- Set `disappearAfterSeconds` from `expiresIn` or conversation `disappearingTimer` when enabled.
- Align `SendMessageDto` / `setDisappearingTimer` validation: min 5, max 30 days (fix current UI/backend mismatch where UI offers 30s but DTO min is 60).

### `markConversationRead`

- After marking messages READ, for each updated message with `disappearAfterSeconds != null` and `expiresAt == null`:
  - `expiresAt = new Date(Date.now() + disappearAfterSeconds * 1000)`
  - Include `expiresAt` in `messageDelivered` payload (ISO string).

### Queries & cleanup

- **Expired filter** (history, unread counts, cleanup): message is expired if:
  - `expiresAt IS NOT NULL AND expiresAt < now`, **OR**
  - `disappearAfterSeconds IS NOT NULL AND expiresAt IS NULL AND createdAt + DISAPPEARING_MAX_UNREAD_SECONDS < now`
- `MessageCleanupService` / `MediaCleanupService`: use same effective-expiry logic for read-mode rows.

### `setDisappearingTimer`

- Validate `seconds` when not null: `@Min(5)` `@Max(2592000)`.
- `seconds: null` when client sends off (all zeros).

### Production DB

- `synchronize` off in prod: manual `ALTER TABLE messages ADD COLUMN "disappearAfterSeconds" integer NULL;` (camelCase column naming per TypeORM).

---

## Frontend Changes

### Models

- `MessageModel`: `disappearAfterSeconds` optional; handle `expiresAt` on `messageDelivered`.
- `ConversationModel`: unchanged.

### Send paths

- `MessagingProvider` / media sends: pass TTL as policy for `disappearAfterSeconds`; do not compute optimistic `expiresAt` at send (optional: show no countdown until server/read sets `expiresAt`).
- Optimistic UI may still show message immediately without expiry clock.

### Expiry sweep (`removeExpiredMessages`, `ChatDetailScreen` 1s timer)

- Remove message if `expiresAt != null && expiresAt.isBefore(now)`.
- **Or** if `disappearAfterSeconds != null && expiresAt == null && createdAt + 1 day < now`.

### `messageDelivered` handler

- When `expiresAt` present, `copyWith` on message in list + cache.

### Timer dialog

- D/H/M/S widget + validation + l10n keys in `app_en.arb` / `app_pl.arb`.

### `CLAUDE.md`

- Update disappearing-messages gotcha: read-based, `disappearAfterSeconds`, never-read 1d, D/H/M/S UI, grandfathering.

---

## Out of Scope (v1)

- Per-message TTL override in composer (per-send picker).
- Preset quick chips (30s, 5m, …) in addition to D/H/M/S.
- Arrival/delivery-based timer start.
- User-configurable never-read retention (fixed 1 day).
- “Hard cap from send” that shortens TTL after read (e.g. max 1 day total from send regardless of read).

---

## Testing

### Backend

- Send with `disappearAfterSeconds`: `expiresAt` null on create.
- `markConversationRead`: sets `expiresAt`, emits to sender socket.
- History excludes unread read-mode messages older than 1 day.
- `setDisappearingTimer(5)` and `(2592000)` ok; `4` and `(2592001)` rejected.

### Frontend

- D/H/M/S dialog: default 1d, all zero → off, 2d 3m → correct seconds.
- Expiry sweep: never-read past 1 day removed; read message uses `expiresAt`.
- Grandfathered fixture: send-time expiry unchanged.

---

## Open Questions

None for v1 — all product choices locked in chat.

---

## References

- Current UI: `frontend/lib/widgets/chat_action_tiles.dart` (`_TimerDialog`)
- Read hook: `markConversationRead` → `chat-message.service.ts` → `markConversationAsReadFromSender`
- Entity default: `conversation.entity.ts` `disappearingTimer` default 86400
