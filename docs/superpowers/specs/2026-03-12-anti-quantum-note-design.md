# Anti-Quantum Note — Design Spec

**Date:** 2026-03-12
**Status:** Approved

---

## Summary

A new chat action tile that lets users create self-destructing encrypted notes accessible via a one-time URL. The key never reaches the server — the note is permanently unrecoverable after reading. Works for anyone with the link (no Fireplace account required), making it useful for sharing sensitive data with people outside the app.

**Marketing framing:** "Anti-Quantum Note" — note is client-side encrypted, key never stored on server, ciphertext deleted after reading. Even future quantum computers cannot decrypt something that no longer exists.

---

## Security Model

### Client-side encryption with key-in-fragment

1. Flutter app generates a random 256-bit AES key locally
2. App encrypts note content with that key (AES-GCM)
3. Only the **ciphertext** is sent to the backend — server never sees the key
4. Generated URL: `fireplace.ignorelist.com/note/TOKEN#KEY`
   - `TOKEN` = 32-char random hex (stored in DB, identifies the record)
   - `KEY` = base64-encoded AES key (URL fragment — **never sent in HTTP requests**)
5. Recipient opens URL → browser JS reads `#KEY` from fragment, fetches ciphertext, decrypts locally
6. Backend performs hard `DELETE` of the record after button click

### Why this is permanently unrecoverable after deletion
- Server only ever stored ciphertext — useless without the key
- Key existed only in the URL and browser RAM — gone when tab closes
- After `DELETE`: even a full DB backup only contains a ciphertext blob with no associated key
- No soft-delete, no audit log of content

### Protection against link-preview bots
WhatsApp, iMessage, Slack, Discord bots auto-visit URLs to generate previews. To prevent them from triggering destruction:
- `GET /note/:token` returns a **landing page** (HTML) that requires a manual button click
- The actual reveal + deletion only happens via `POST /note/:token/reveal` (requires JS interaction)
- Bots that simply GET the URL see only the landing page — note survives

---

## Database

New table: `secret_notes`

| Column | Type | Notes |
|---|---|---|
| `id` | int PK | auto-increment |
| `token` | varchar(64) | UNIQUE, random hex, used in URL |
| `ciphertext` | text | AES-GCM encrypted content (base64) |
| `expires_at` | timestamp | TTL set at creation |
| `creator_id` | int FK | references `users.id`, nullable |
| `created_at` | timestamp | auto |

No `content` column — server is zero-knowledge. Hard `DELETE` on reveal, no soft-delete.

---

## Backend

### New module: `secret-notes`

**Files:**
- `secret-notes/secret-note.entity.ts` — TypeORM entity
- `secret-notes/secret-notes.service.ts` — create, reveal-and-delete, cleanup
- `secret-notes/secret-notes.controller.ts` — REST routes

**Endpoints:**

| Method | Path | Auth | Description |
|---|---|---|---|
| `POST` | `/notes` | JWT | Create note — receives `{ ciphertext, expiresIn }`, returns `{ token }` |
| `GET` | `/note/:token` | None | Returns landing page HTML (3 states: landing / already-read / expired) |
| `POST` | `/note/:token/reveal` | None | Returns `{ ciphertext }` and hard-deletes record |

**Cleanup:** Check `expires_at` on every `GET /note/:token` and `POST /note/:token/reveal` — if expired, return "expired" state and delete. No cron job needed for MVP.

---

## Frontend (Flutter)

### New tile: ⚛️ AQ Note

Added as 7th tile in `chat_action_tiles.dart` after the existing GIF tile.

- **Icon:** `atom` or custom ⚛️
- **Label:** "AQ Note"
- **On tap:** opens `AntiQuantumNoteDialog`

### AntiQuantumNoteDialog

Bottom sheet / dialog with:
1. `TextField` — multiline, "Write your secret message..."
2. TTL chips — **2h / 6h / 12h**, default **6h**
3. Button — "🔗 Generate & Send"
4. Subtitle — *"Encrypted client-side · Key never leaves your device"*

**On button press:**
1. Generate random 256-bit AES key (Flutter `dart:math` / `crypto` package)
2. Encrypt content with AES-GCM
3. `POST /notes` with `{ ciphertext: base64, expiresIn: seconds }` + JWT
4. Receive `{ token }` from server
5. Build URL: `https://fireplace.ignorelist.com/note/{token}#{base64Key}`
6. Send URL as a plain text message in current conversation via existing `sendMessage` flow
7. Close dialog, show snackbar: *"Anti-Quantum Note sent"*

### Crypto implementation
Use `encrypt` Flutter package (AES-GCM support) or `pointycastle`. Key: 256-bit random. IV: 96-bit random, prepended to ciphertext before base64-encoding.

---

## Reading Page (served by backend)

The backend serves a minimal HTML page for `/note/:token`. No Flutter involved — pure HTML/CSS/JS.

### State 1 — Landing (note exists, not yet read)
- ⚛️ icon + "Anti-Quantum Note" heading
- Subtext: *"Someone sent you a self-destructing message. It will be destroyed after you read it."*
- Remaining time: *"Expires in 5h 42m"*
- Button: **"🔓 Reveal & Destroy"** → JS clicks → `POST /note/:token/reveal` → display content
- Footer: *"Powered by Fireplace"*

### State 2 — Revealed (after button click)
- 🔓 icon + *"Message revealed · Now destroyed"*
- Content displayed in a dark card
- Note: *"This note has been permanently deleted. Refreshing will show nothing."*

### State 3 — Gone (already read or expired)
- 💀 icon
- *"This note no longer exists"*
- *"It was either already read or has expired. Ask the sender to create a new one."*

---

## TTL Options

| Label | Seconds |
|---|---|
| 2h | 7,200 |
| 6h | 21,600 (default) |
| 12h | 43,200 |

---

## What This Does NOT Include (out of scope)

- "Notify me when read" — skipped for simplicity (MVP)
- "Copy link" button — link goes directly into chat; user can copy from chat message manually
- Media/file notes — text only
- In-app link interception (opening note inside Fireplace app) — opens in external browser
- Rate limiting on `/notes` endpoint — can be added later

---

## Files to Create/Modify

### Backend (new)
- `backend/src/secret-notes/secret-note.entity.ts`
- `backend/src/secret-notes/secret-notes.service.ts`
- `backend/src/secret-notes/secret-notes.controller.ts`
- `backend/src/secret-notes/secret-notes.module.ts`

### Backend (modify)
- `backend/src/app.module.ts` — import SecretNotesModule

### Frontend (new)
- `frontend/lib/widgets/anti_quantum_note_dialog.dart`

### Frontend (modify)
- `frontend/lib/widgets/chat_action_tiles.dart` — add 7th tile
- `frontend/pubspec.yaml` — add `encrypt` package if not present
