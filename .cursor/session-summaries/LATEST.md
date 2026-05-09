# Latest session summary

**Date:** 2026-05-09  
**Summary:** [2026-05-09-session.md](2026-05-09-session.md) — PWA auto-logout investigated and fixed in two phases. **Phase 0 (deployed):** bumped JWT TTL from `24h` to `30d` (`backend/src/auth/auth.module.ts`) so PWA users stop being auto-logged-out daily. **Phase 1 (spec approved, not implemented):** Signal/Telegram-grade identity-key auth design at `docs/superpowers/specs/2026-05-09-identity-key-auth-design.md` — Ed25519 per-device keypairs + silent challenge-response refresh, 2h session JWT, `device_sessions` table for instant per-device revocation, sliding 90d expiry. Researched against WhatsApp/Telegram/Signal/Discord/Slack patterns; spec reviewed and 10 substantive fixes applied inline. CLAUDE.md updated.

**Previous:** [2026-05-07-session.md](2026-05-07-session.md)
