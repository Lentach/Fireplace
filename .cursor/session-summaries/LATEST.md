# Latest session summary

**Date:** 2026-05-09  
**Summary:** [2026-05-09-session.md](2026-05-09-session.md) — PWA auto-logout investigated. **Phase 0 deployed:** JWT TTL `24h → 30d` in `backend/src/auth/auth.module.ts` (commit `b851b42`) — stops daily auto-logout. **Phase 1 designed and DEFERRED:** full Signal-style identity-key auth design in `docs/superpowers/specs/2026-05-09-identity-key-auth-design.md` and 30-task implementation plan in `docs/superpowers/plans/2026-05-09-identity-key-auth.md` are complete but **not** scheduled for execution. After honest re-evaluation, the marginal security gain on web was judged modest (web localStorage exposure remains, XSS gets both token and key) while refactor risk is high. Both files have "deferred" status headers; re-open when going native or when product needs Active Devices UI. Cheaper higher-ROI alternatives identified: 2FA/TOTP, RS256 JWT, audit log, per-username brute-force throttle.

**Previous:** [2026-05-07-session.md](2026-05-07-session.md)
