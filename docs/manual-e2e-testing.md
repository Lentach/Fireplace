# Manual E2E Encryption Testing Guide

This guide helps you verify that end-to-end encryption works correctly in Fireplace — that messages are actually encrypted in transit and the server never sees plaintext.

---

## Prerequisites

1. **Backend + DB running:** `docker-compose up`
2. **Frontend running:** `cd frontend && flutter run -d chrome`
3. **Two user accounts** (e.g. `alice` and `bob`) — both must be friends
4. **Both users must have opened the app at least once** so their key bundles are uploaded to the server

---

## Test 1: Database Verification (Server Never Sees Plaintext)

**Goal:** Confirm that the server stores only ciphertext, not your message content.

### Steps

1. Log in as **User A** in Chrome.
2. Open a chat with **User B** (friend).
3. Send a **unique test message**, e.g. `TajnaWiadomosc123!@#`.
4. Connect to PostgreSQL and inspect the latest message:

```bash
# From project root. Replace CONTAINER with your postgres container name (docker ps)
docker exec -it CONTAINER psql -U postgres -d chatdb -c "
  SELECT id, content, 
         LEFT(\"encryptedContent\", 50) AS encrypted_preview,
         LENGTH(\"encryptedContent\") AS encrypted_len
  FROM messages 
  ORDER BY id DESC 
  LIMIT 3;
"
```

**Expected result:**
- `content` = `[encrypted]` (placeholder, NOT your plaintext)
- `encryptedContent` = non-null base64 string prefixed as `"{type}:{base64}"` (type `3` = PreKeySignalMessage, type `2` = Signal/whisper message)
- `encrypted_len` > 100 (ciphertext is much longer than plaintext)

**If you see your plaintext in `content`** → encryption is NOT being used (bug).

---

## Test 2: Network Inspection (What Goes Over the Wire)

**Goal:** Verify that the client sends ciphertext, not plaintext, to the server.

### Steps

1. Open Chrome DevTools (F12) → **Network** tab.
2. Filter by **WS** (WebSocket) or type `socket` in the filter.
3. Click the WebSocket connection → **Messages** sub-tab.
4. Log in and send a message like `TestSzyfrowania456`.
5. Find the `sendMessage` emit — click it and inspect the payload.

**Expected payload:**
```json
{
  "recipientId": 2,
  "content": "[encrypted]",
  "encryptedContent": "{type}:base64encodedciphertext...",
  "messageType": "TEXT",
  ...
}
```

- `content` must be `[encrypted]`, never your actual message text.
- `encryptedContent` must be present and look like `{type}:{base64}` (`3` for first PreKey messages, commonly `2` once a session exists).

**If you see your plaintext in `content` or no `encryptedContent`** → encryption is not applied.

---

## Test 3: Two-User Round Trip (Encrypt → Decrypt)

**Goal:** Confirm that User B can decrypt and read User A’s message.

### Steps

1. **User A (Chrome):** Log in, open chat with User B, send: `Wiadomosc tylko dla Ciebie!`
2. **User B (Chrome Incognito or another browser):** Log in as User B, open the same chat.
3. **Verify:** User B sees the decrypted message: `Wiadomosc tylko dla Ciebie!` (not `[encrypted]` or gibberish).

**If User B sees:**
- `[encrypted]` or "Encrypted message" forever → decryption failed.
- Gibberish → decryption error or key mismatch.
- Correct plaintext → E2E works end-to-end.

---

## Test 4: Debug Console Logs (Optional)

In debug mode, the app logs E2E flow to the console. Run:

```bash
cd frontend && flutter run -d chrome
```

Then open DevTools → **Console** and watch for:

- `[E2E-FLOW] E2E_INIT_DONE` — encryption initialized
- `[E2E-FLOW] E2E_KEYS_UPLOADED` — key bundle uploaded
- `[E2E-FLOW] SEND_ENCRYPT_DONE` — message encrypted before send
- `[E2E-FLOW] RECV_DECRYPT_DONE` — received message decrypted

If you see `SEND_FAIL` or `DECRYPT_FAIL`, check the error message for the cause.

---

## Quick Reference: SQL Queries

```sql
-- Last 5 messages with encryption status
SELECT id, content, 
       CASE WHEN "encryptedContent" IS NOT NULL THEN 'YES' ELSE 'NO' END AS encrypted,
       LENGTH("encryptedContent") AS cipher_len
FROM messages 
ORDER BY id DESC 
LIMIT 5;

-- Count encrypted vs plaintext text rows
SELECT 
  COUNT(*) FILTER (WHERE "encryptedContent" IS NOT NULL) AS encrypted,
  COUNT(*) FILTER (WHERE "encryptedContent" IS NULL AND "messageType" = 'TEXT') AS plaintext
FROM messages;
```

---

## Troubleshooting

| Symptom | Possible cause |
|--------|----------------|
| `content` contains plaintext in DB | E2E not used — check if `encryptedContent` is sent from frontend |
| User B sees "Encrypted message" forever | Decryption failed — check console for `DECRYPT_FAIL` |
| "Recipient has no key bundle" | User B has not opened the app — they must log in once to upload keys |
| "Timed out waiting for recipient keys" | Pre-key fetch failed — ensure backend is running and key-bundles table is populated |

---

## Scope Reminder

- **Encrypted:** TEXT payloads and media envelopes (`IMAGE`, `VOICE`, `GIF`, `FILE`) carry Signal ciphertext in `encryptedContent`; self-hosted media blobs are additionally AES-GCM encrypted client-side via `mediaKey`/`mediaIv`.
- **Not E2E content:** `PING` carries no plaintext message body.
