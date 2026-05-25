# Metadata Privacy — Design Options

**Date:** 2026-03-11  
**Status:** Approach A implemented

## Problem

E2E encryption protects **message content**. The server still sees **metadata**:
- **Who** — sender_id, recipient (from conversation)
- **With whom** — conversation participants (user_one_id, user_two_id)
- **When** — createdAt, deliveryStatus timestamps
- **Structure** — conversation list, message ordering

## Current Architecture Constraints

Fireplace is a **centralized** chat app. The server must:
1. **Route messages** — know recipient to deliver
2. **Store messages** — for offline/history (sender_id needed for display)
3. **Manage conversations** — know participants for access control
4. **Authenticate** — JWT identifies sender on every request

**Fundamental:** Routing requires (sender → recipient). A server cannot deliver a message without knowing where to send it.

---

## Approach A: Pragmatic — Minimize & Document (Recommended First Step)

**Scope:** Reduce metadata footprint and be transparent. No protocol changes.

| Action | Effort | Impact |
|--------|--------|--------|
| **Metadata retention policy** | Low | Don't keep logs longer than needed; document retention |
| **Timestamp precision** | Low | Round createdAt to nearest minute (optional) |
| **Privacy policy / docs** | Low | Document exactly what metadata is stored and why |
| **Audit logging** | Medium | Ensure we don't log sensitive metadata (conversation IDs, etc.) |
| **Data export** | Medium | Let users see their metadata (GDPR-style) |

**Pros:** Low risk, incremental, improves transparency.  
**Cons:** Server still has full metadata; doesn't hide who-with-whom.

---

## Approach B: Sealed Sender (Signal-Style)

**Scope:** Hide **sender** from server. Server knows recipient only.

**How it works (Signal):**
1. Sender gets short-lived **sender certificate** from server (proves identity without revealing on each message)
2. Recipient has **delivery token** (derived from profile key, registered with server)
3. Message sent **without auth** — encrypted envelope with (sender cert + ciphertext), addressed by delivery token
4. Server stores message for recipient; cannot decrypt envelope → doesn't know sender
5. Recipient fetches, decrypts envelope, learns sender from cert

**Requirements for Fireplace:**
- Profile keys (we don't have; would need new key type)
- Delivery tokens table + registration flow
- Unauthenticated message submission endpoint (abuse risk)
- DB schema change: messages stored by recipient_id only; sender_id derived client-side after decrypt
- Conversation threading becomes client-side (or we store conversation_id but not sender_id — server could infer from message ordering)

**Effort:** High (2–4 weeks). Requires new crypto, new endpoints, schema migration.  
**Pros:** Server no longer knows who sent each message.  
**Cons:** Complex; abuse/rate-limiting harder; server still knows recipient and conversation structure.

---

## Approach C: P2P / Decentralized

**Scope:** No central server holds metadata. Messages routed via DHT, mixnet, or similar.

**Effort:** Very high. Effectively a rewrite.  
**Pros:** Maximum metadata privacy.  
**Cons:** Out of scope for current MVP.

---

## Recommendation

1. **Start with Approach A** — implement metadata minimization and documentation. Quick wins, no breaking changes.
2. **Evaluate Approach B** later — if metadata privacy becomes a priority, Sealed Sender is the next step. It fits our existing Signal Protocol stack but needs design and testing.

---

## Proposed Implementation: Approach A

### 1. Metadata Inventory (Document)

Add `docs/METADATA.md`:

```markdown
# Metadata Stored by Fireplace

## Server (PostgreSQL)

| Table | Fields | Purpose |
|-------|--------|---------|
| users | id, username, tag, ... | Account identity |
| conversations | id, user_one_id, user_two_id, createdAt | Conversation membership |
| messages | id, sender_id, conversation_id, createdAt, ... | Message routing & display |
| friend_requests | sender_id, receiver_id, status, ... | Social graph |
| key_bundles | userId, ... | E2E key distribution |

## What the server CANNOT see
- Message content (E2E encrypted)
- Reply-to content for encrypted messages

## What the server CAN see
- Who is in each conversation
- When messages were sent
- Delivery status (sent/delivered/read)
```

### 2. Retention & Logging

- Ensure backend logs don't include conversation_id, message content, or user IDs in error logs (or redact in production)
- Add `METADATA_RETENTION_DAYS` env var (optional) for future auto-purge of old data

### 3. User-Facing Transparency

- In Settings → Privacy & Safety: add "What we store" section linking to METADATA.md or in-app summary

### 4. Optional: Timestamp Coarsening

- Store `createdAt` with minute precision (truncate seconds) — reduces timing correlation. **Trade-off:** less precise "sent at" display.

---

## Open Questions

1. **Approach A vs B:** Do you want to start with A (pragmatic) or invest in B (Sealed Sender)?
2. **Timestamp precision:** Keep millisecond precision or coarsen to minutes?
3. **Data export:** Should users be able to download their metadata (conversation list, timestamps) as JSON?
