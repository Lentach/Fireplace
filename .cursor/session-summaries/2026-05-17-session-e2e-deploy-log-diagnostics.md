# Session 2026-05-17 — E2E / deploy log diagnostics

## What was done

- Investigated `[Decryption failed]` and sender-side `[encrypted]` after production deploy.
- Reviewed VM `docker compose logs backend` (Marzen userId=58, bob208 userId=37).
- Confirmed backend health: `GET /health` → `{"status":"ok","db":"ok"}`.
- Verified live messaging OK after using a single client session (22:07 `newMessage emitted to recipient 37`).

## Root cause (operational, not server bug)

1. **Reconnect storm** (~21:49–21:51): Marzen disconnected/reconnected every 1–2s while sending. Client clears `_pendingSendContent` on reconnect → sender loses plaintext backup → UI shows `[encrypted]` from server payload.
2. **Dual sessions**: same account in browser tab + PWA amplified socket churn and key bundle re-uploads.
3. **`[encrypted]` in DB/API is expected** for E2E (`chat-message.service.ts` stores placeholder content).

## Backend log patterns

- **OK**: one `connected` → `sendMessage emitted` → one `disconnected` on app exit.
- **NOT ONLINE**: recipient not on socket; message still saved; push scheduled.
- **Bad (fixed operationally)**: dozens of `connected`/`disconnected` per minute during send.

## Code already shipped (prior commit)

- `fix(reconnect): preserve chat and contacts on empty socket snapshots` (941f01f): intentional disconnect on socket replace, `tokenForReconnect`, ignore empty list snapshots when local data exists.

## Recommendations for users

- Use **one** session per account (PWA **or** browser, not both).
- After deploy: single login, test new message; old broken rows may stay `[encrypted]`.

## Follow-up (optional code hardening)

- Do not clear `_pendingSendContent` for in-flight `sending` messages on reconnect.
- Debounce/limit full `connect()` if socket already healthy.
