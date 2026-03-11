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

## Future Improvements

See `docs/plans/2026-03-11-metadata-privacy-design.md` for options to reduce metadata visibility (e.g. Sealed Sender).
