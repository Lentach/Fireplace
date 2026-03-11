# Metadata Stored by Fireplace

This document describes what metadata the Fireplace server stores and why. It is intended for transparency and user trust.

## What the Server CANNOT See

- **Message content** — End-to-end encrypted (Signal Protocol). Server stores only ciphertext and `[encrypted]` placeholder.
- **Reply-to content** — For encrypted messages, server stores `Encrypted message` placeholder only.

## What the Server CAN See (Metadata)

The server needs certain metadata to deliver messages and manage conversations.

| Data | Stored in | Purpose |
|------|-----------|---------|
| User identity | `users` | Account (username, tag, profile picture) |
| Conversation membership | `conversations` | Who is in each chat (user_one_id, user_two_id) |
| Message routing | `messages` | sender_id, conversation_id — who sent what, to which conversation |
| Timestamps | `messages`, `conversations` | createdAt — when messages were sent |
| Delivery status | `messages` | SENT, DELIVERED, READ — for read receipts |
| Friend graph | `friend_requests` | Who is friends with whom |
| Key bundles | `key_bundles`, `one_time_pre_keys` | Public keys for E2E (no private keys) |

## Why This Metadata Is Needed

- **Routing:** The server must know the recipient to deliver a message.
- **Display:** The recipient needs to know who sent each message (sender_id).
- **Access control:** Only conversation participants can read messages.
- **Offline/history:** Messages are stored so users can fetch them when they reconnect.

## Retention & Logging

- **Data retention:** Metadata is stored for as long as the account and conversations exist. No automatic purge by default. `METADATA_RETENTION_DAYS` (optional env var) is reserved for future auto-purge.
- **Logging:** Backend logs may include userId, conversationId for debugging. In production, use appropriate log levels (e.g. `warn`/`error` only) to minimize metadata in logs.

## Key Storage (E2E)

- **Mobile:** Keys in Keychain (iOS) / Keystore (Android) — hardware-backed when available.
- **Web:** Keys in browser storage, encrypted with WebCrypto. Uses app-specific db (`FireplaceE2E`). Someone with device access could potentially extract them. Privacy & Safety screen shows a web-specific warning; mobile app recommended for maximum security.

## Future Improvements

See `docs/plans/2026-03-11-metadata-privacy-design.md` for options to reduce metadata visibility (e.g. Sealed Sender).
