# Session summary — contacts/conversations vanish on network handoff

**Date:** 2026-05-17

## Accomplished

- Root cause: reconnect/socket replacement could apply **empty** `conversationsList` / `friendsList` over populated local state; old socket `disconnect` during `connect()` could schedule extra reconnects with **stale JWT**; delayed empty retry only refetched conversations, not friends.
- Fixes in `ConnectionProvider`, `ConversationsProvider`, `FriendsProvider`; regression tests; `CLAUDE.md` updated.

## Key files

- `frontend/lib/providers/connection_provider.dart`
- `frontend/lib/providers/conversations_provider.dart`
- `frontend/lib/providers/friends_provider.dart`
- `frontend/test/providers/conversations_provider_test.dart`
- `frontend/test/providers/friends_provider_test.dart`
- `CLAUDE.md`

## Tests

- `flutter test test/providers/conversations_provider_test.dart test/providers/friends_provider_test.dart test/providers/connection_provider_socket_ready_test.dart` — 23 passed

## Manual verification

- Wake device, switch WiFi ↔ cellular while app backgrounded, resume — Chat + Contacts lists should stay populated; messages still send.
