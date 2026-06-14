# Fireplace — Audit Review & Fix Recommendation

**Reviews:** `docs/audit/FINDINGS.md` (audit by Claude Opus 4.8, 2026-06-14)
**Reviewer:** Claude (Opus 4.8) · **Date:** 2026-06-15 · **Branch:** `audit/full-review`
**Verdict:** Audit confirmed accurate on independent verification. **Implement H-04, H-01, H-02 now; defer the rest.**

---

## 1. Independent verification

I re-read the cited source for the four Highs plus the most severe Medium rather than trusting the
report. Every one behaves as described, at the stated `file:line`:

| ID | Claim | Verified mechanism | Status |
|---|---|---|---|
| H-01 | `getMessages` IDOR | `handleGetMessages` passes `userId` only as the `hiddenByUserId` filter; no participant predicate in `findByConversation` | ✅ Real |
| H-02 | mediaUrl path traversal → arbitrary delete | `MEDIA_URL_REGEX` `…/media/.+` allows `../`; `extractPublicId` bare `.replace` + `deleteFile` `path.join` with no `normalize`/containment | ✅ Real |
| H-03 | No E2E identity pinning | `isTrustedIdentity` unconditionally calls `saveIdentity` and returns `true` (blind TOFU) | ✅ Real (design) |
| H-04 | JWT exfil via media URL | `fetchMediaBytes` attaches `Authorization: Bearer <jwt>` on any host whose path contains `/media/msgs/`; envelope `mediaUrl` is never server-validated | ✅ Real |
| M-07 | prod runs `synchronize:true` | `synchronize: NODE_ENV !== 'production'` + `docker-compose.yml` `NODE_ENV: development` | ✅ Real (with caveat, §3) |

Severities are appropriate. The Mediums/Lows I did not re-derive line-by-line; given the Highs held
up exactly, I take the rest on the report's demonstrated rigor.

---

## 2. Implement now — one fix PR (`fix/audit-highs`)

All three are small (1–few lines), independent, verified, and pure upside. Order by real-world blast
radius:

### H-04 — JWT exfiltration (do first)
- **Why first:** worst impact — a *contact* harvests your access token (account takeover), triggered
  merely by opening a chat. The injection point is the **E2E-envelope `mediaUrl`, which the server
  never validates**, so the attacker fully controls the host.
- **Fix:** in `fetchMediaBytes` ([api_service.dart:355](../../frontend/lib/services/api_service.dart)),
  attach the `Authorization` header only when the *resolved host* equals the backend authority —
  a same-origin check, **not** the current `/media/msgs/` path-substring test.
- **Test:** foreign-host media URL → no auth header sent; own-host `/media/msgs/` → header sent.

### H-01 — conversation-history IDOR
- **Why:** any authenticated user can read any `conversationId` (sequential PK). E2E keeps message
  *bodies* safe, but participants/timing/counts/`mediaUrl`/reactions leak for the whole user base —
  and any non-E2E content is fully readable (the server doesn't enforce encryption).
- **Fix:** enforce membership in `handleGetMessages`
  ([chat-message.service.ts:139](../../backend/src/chat/services/chat-message.service.ts)) — mirror
  the `markConversationRead`/`deleteMessage` membership check, or push a participant predicate into a
  `findByConversationForParticipant(...)` so future callers can't forget it.
- **Test:** non-member `getMessages` returns empty / unauthorized.

### H-02 — path traversal → arbitrary file deletion
- **Why:** a crafted `mediaUrl` (passes the regex) unlinks arbitrary files on delete/block/expiry,
  as root in the container.
- **Fix (defense in depth, both):** tighten `MEDIA_URL_REGEX`
  ([chat.dto.ts:24](../../backend/src/chat/dto/chat.dto.ts)) to forbid `..` (e.g. a bounded
  `[A-Za-z0-9._/-]+` with no `..`), **and** `path.normalize` + containment-assert (resolved path
  starts with `mediaDir`) in `deleteFile` ([local-storage.service.ts:84](../../backend/src/media/local-storage.service.ts)).
- **Test:** `mediaUrl` with `../` is rejected at the DTO and cannot escape `mediaDir` in `deleteFile`.

**Deploy:** substantial/security → feature branch + PR, **test on the VM before merging to `master`**
(H-04 is device-dependent — verify on iPhone/Android; H-01/H-02 are backend). H-04 also needs a PWA
cache-bust on test devices.

---

## 3. Defer — track, don't rush

- **M-07 (`synchronize:true` in prod):** real, but **not the clean one-liner the report implies** —
  there is no migration system, so flipping `NODE_ENV=production` disables auto-schema-sync with
  nothing to replace it. It matches how prod schema changes are already applied (manual `ALTER
  TABLE`), so it's safe — *after* confirming the live schema is complete. Pair it with a planned
  deploy, not the quick-win PR.
- **H-03 (identity pinning):** genuine gap, but the fix is a **feature** — pin-and-warn on key
  change + safety-number verification UI. Scope separately; do not let it gate the quick wins.
- **M-02 (unscoped fcm-token delete), M-05 (WS skips `passwordChangedAt`):** worth doing and likely
  cheap, but not yet independently verified — verify, then fix.
- **Remaining Mediums + 14 Lows:** batch after the Highs land. Nothing urgent enough to interrupt
  the security fixes.
- **I-03 (dependency audit):** run `npm audit` / `flutter pub outdated` outside the sandbox to close
  the one open dependency-vuln question.

---

## 4. Sequencing

1. `fix/audit-highs` PR — H-04, H-01, H-02 + regression tests → VM test → merge to `master`.
2. Separate scheduled change — M-07 (with a schema-completeness check at deploy).
3. Backlog — H-03 feature, verify+fix M-02/M-05, then the Low/Info sweep, plus I-03 dep audit.
