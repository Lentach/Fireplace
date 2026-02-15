# Session: 2026-02-13 — Mobile HTTP Debugging (Reverted)

## What was attempted
- Debugging why messages don't load on mobile (Android) while web works perfectly
- Created HTTP REST endpoints for conversations and messages (GET /conversations, GET /messages/:id)
- Tried multiple HTTP client strategies: per-request clients, persistent client, dart:io HttpClient
- Added WebSocket message chunking (5 messages per chunk with 200ms delays)
- Added extensive debug instrumentation (~641 lines across 16 files)

## Root cause discovered
**On this Android phone, new TCP connections to the backend CANNOT be established while a WebSocket is already active.** Evidence:
- `GET /conversations` (sent BEFORE WebSocket connects): always works in ~500ms
- `GET /messages/:id` (sent AFTER WebSocket connects): always times out (10-20s)
- Backend processes each HTTP request in 17-47ms when it arrives — the delay is entirely on the network path
- This is NOT a code issue — it's an Android WiFi/TCP stack limitation on this device

## Key findings for future reference
1. WebSocket chunking DOES work — messages load via WS chunks in ~2-3 seconds
2. The HTTP endpoints work perfectly on the backend side
3. The problem is ONLY with establishing new TCP connections while WS is active on mobile
4. Web version has no issues because browsers handle TCP multiplexing better

## Outcome
**All changes reverted** (`git checkout -- .`). The 641 lines of debug code and experimental fixes produced no lasting improvement. Clean slate for next attempt.

## Recommended approach for next session
Instead of fighting HTTP vs WebSocket, use **WebSocket chunking directly** (skip HTTP attempt). This would load messages in ~2s via WS chunks without the 10-15s HTTP timeout delay. Key: don't try to establish new TCP connections — use the existing WebSocket connection for everything.

## Files that were modified (all reverted)
- backend: main.ts, chat.gateway.ts, chat-message.service.ts, messages.controller.ts (new, deleted), messages.service.ts, conversations.module.ts
- frontend: chat_provider.dart, api_service.dart, socket_service.dart, app_config.dart, auth_provider.dart, conversations_screen.dart, chat_detail_screen.dart
