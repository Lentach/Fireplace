# Metadata Privacy Audit + Hardening Roadmap (research only, no code)

**Date:** 2026-07-07

## What was done
Security research + audit session on Fireplace **metadata** leakage (content E2E is solid,
out of scope). Produced a file:line-verified leak inventory, a Signal/SimpleX/Threema/Matrix
comparison, and a feasibility-ranked roadmap. **No code changed.** Report is local-only
(gitignored `docs/audit/`) because the repo is public and the inventory is an attacker map.

Threat-model framing up front: **single self-hosted server, operator = owner.** So the real
adversaries are **server breach / seizure / backup theft / third-party push (Google/Apple/
Mozilla)** — NOT "the operator" (measures that only hide from the operator are theater here,
and are rejected explicitly).

Key verified findings:
- DB persists the full contact graph (`conversations` user_one/two), per-message
  sender+conversation+createdAt (indexed), deliveryStatus/editedAt/expiresAt, messageType/
  mediaUrl/mediaDuration, ciphertext length (no padding), and **reactions = emoji+userIds in
  cleartext** (content, not just metadata). Push tokens/endpoints/userAgent + per-session
  refresh rows (device count visible).
- Prod logs (`log`/`warn`) leak recipient userId + timing per message and a full online-user
  roster dump; docker-compose.prod has **no log rotation** (unbounded); nginx access_log
  logs client IPs (repo config may be stale vs VM).
- **FCM payload carries `senderName`+`conversationId`+counts readable by Google**; web-push
  body is encrypted but `topic: conv-<id>` header is cleartext to the relay.
- pushClientState reports the on-screen conversation to the server (in-memory).
- Backups are gpg-AES256 (only if passphrase set) but were not yet enabled on the VM.
- Good news: no persisted lastSeen, no presence fan-out, user search is exact-match (no
  enumeration), media blobs are UUID-named + encrypted, refresh tokens hashed.

Top-5 roadmap: (1) enable encrypted backups ~1h; (2) log minimization + docker/nginx
retention caps 2-4h; (3) content-free push (drop senderName, strip web-push topic) 3-6h;
(4) opt-in receipts/typing + purge rejected friend requests 1-2d; (5) pad ciphertext to size
buckets 2-4d. Bigger track: ephemeral-by-default server storage (delete-on-delivery, client
owns history) = strongest breach/seizure win but weeks + product change. Rejected: sealed
sender (pointless in 1:1 on a trusted-operator box), SGX/mixnets/second-server (need non-
colluding parties — impossible on one self-hosted box).

## Key files
- `docs/audit/2026-07-07-metadata-privacy-audit.md` — full report (gitignored, DO NOT COMMIT/PUSH).
- Audited (read-only, no edits): `backend/src/**/*.entity.ts`, `backend/src/main.ts`,
  `backend/src/chat/chat.gateway.ts`, `chat-presence.service.ts`, `chat-message.service.ts`,
  `chat-link-preview.service.ts`, `chat-search.service.ts`,
  `push-notifications.service.ts`, `push-notification-coalescing.service.ts`,
  `common/http-throttler.guard.ts`, `chat/guards/ws-throttler.guard.ts`,
  `media/local-storage.service.ts`, `frontend/nginx.conf`, `docker-compose.prod.yml`,
  `backup-db.sh`.

## Verification
Research/audit session — no code, no build/test run. Every "Fireplace does X" claim carries a
file:line read this session; every "Signal/SimpleX/Threema/Matrix does Y" claim carries a
cited URL (see report Phase 2 sources). Uncertainties labeled in-report: live VM nginx config
may differ from repo copy; host logrotate for nginx not in repo; backup-enabled status on VM
to be confirmed on the box.

## Notes for next session
- Report ends with 6 batched owner questions (receipts/typing on-off, strip push senderName,
  strip conversationId/topic, timestamp coarsening appetite, ephemeral-by-default appetite,
  purge rejected requests). Each roadmap item is its own future prompt — do not implement
  until the relevant question is answered.
- Do NOT commit `docs/audit/` (public repo).
