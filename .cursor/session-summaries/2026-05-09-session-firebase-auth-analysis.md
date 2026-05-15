# Session — Firebase Auth vs current auth (analysis)

**Date:** 2026-05-09

## What was done

- Documented how Fireplace authenticates today (JWT + bcrypt + username#tag, client token storage, REST vs WebSocket validation).
- Compared adopting **Firebase Authentication** as IdP vs staying on custom auth; listed benefits, costs, and what Firebase does **not** replace (Nest JWT bridge, Socket.IO, Postgres user model, E2E key binding).

## Key references (code)

- `backend/src/auth/auth.service.ts`, `auth.controller.ts`, `auth.module.ts`, `strategies/jwt.strategy.ts`
- `frontend/lib/providers/auth_provider.dart`, `services/api_service.dart`
- `backend/src/chat/chat.gateway.ts` (WS JWT verify path)
- Firebase today: FCM only — `frontend/lib/main.dart`, `push_service.dart`, `backend/src/push-notifications/push-notifications.service.ts`

## Project status / notes

- No code changes; research-only. Defer identity-key Phase 1 per existing spec; Firebase Auth is orthogonal (social IdP + SDK), not a substitute for device-bound session crypto on web.
