# Own-message "[encrypted]" field report — triaged, reviewed, and FIXED (0.0.102, lost-ack pending-send reconcile)

**Date:** 2026-07-09

## What was done

Owner reported: mid-conversation, their OWN sent message shows `[encrypted]` — sender side only; recipient (52/Princepolo) read everything fine. Screenshot + full durable/live diag dump provided. Triage only — owner explicitly held implementation ("wait before you implement any changes, be careful editing e2e stuff").

### Verdict 1 — screenshot bug = lost `messageSent` ack (NOT E2E, NOT version skew)

- Log smoking gun: `18:59:15 SEND_EMIT temp_1783616355860_37` → `18:59:18 SOCKET_DISCONNECT {intentional:false}` → **no RECV_MSG echo ever** for that send; the two neighboring sends (18:59:38/55) echoed instantly (14668/14669). Server saved the message (recipient read it; history count 33→34; it's msg ~14667).
- Mechanism: plaintext lives in `_pendingSendContent[tempId]` until the `messageSent` ack maps tempId→realId and persists plaintext under the real id. Ack lost to the socket drop → mapping never happens → history refetch replaces the optimistic row with the server's `[encrypted]` shell → a Signal sender CANNOT decrypt its own ciphertext → stays `[encrypted]` forever on the sender. Recipient unaffected by construction.
- Happened on the owner's newest build (0.0.95/28cd685 at the time); needs only a socket drop inside the ack window (owner's LTE log is reconnect churn wall-to-wall).
- **HEAD-validity check (0.0.101):** `git diff 283ecb7..HEAD` over `frontend/lib/providers/messaging*`, `socket_service.dart`, `encryption_service.dart` = one dead-method deletion only; socket_io_client 3.1.6 bump is transport-only. Diagnosis + fix design valid at HEAD.
- **Fix designed (NOT built, awaiting owner go):** provider-layer only, zero crypto surface — durable pending-send map; on history merge, own `[encrypted]` row with no persisted plaintext reconciles against unacked pending sends (conversation + tempId-timestamp proximity), restores + persists under real id. Regression test simulating the lost ack.

### Verdict 2 — 07-08 duplicates (senders 63, 62): dating DONE — both POST-fix; stale-sender-bundle is the leading hypothesis, tripwire not excluded

- Hypothesis: peer PWAs still running cached ≤0.0.93 bundles minted poisoned wires post-deploy (a PWA runs the old bundle until fully closed+reopened — days, possibly).
- **NOT yet confirmed:** DECRYPT_DECISION timestamps are decrypt-attempt times, not send times (the msg-14149 lesson, nearly repeated). The discriminating SQL could not be run — VM SSH from the PC timed out (prod itself healthy; 0.0.98/d8cf61c live). Owner should run:
  `docker compose -f docker-compose.prod.yml exec db psql -U postgres -d chatdb -c 'SELECT id, "senderId", "createdAt" FROM messages WHERE id IN (14389,14390,14391,14423,14594,14595,14596,14597,14598);'`
- **RESOLVED (same session, on the OVH VPS — prod moved off GCP 07-08, `ubuntu@51.68.138.13`, repo at d8cf61c):** the flagged rows are already expired/deleted; bracketed via neighbors (14382 = 07-08 04:22 UTC, 14395 = 09:09 UTC, 14438 = 13:53 UTC): 14389-91 sent 04:22-09:09 UTC, 14423 sent 09:09-13:53 UTC — ALL after the 00:00 UTC fix deploy. Pre-fix-damage classification dead. Leading: senders on stale cached bundles; decider = their footers after a full close+reopen; any duplicate minted from a confirmed-≥0.0.94 sender = runbook Step 3A alarm. Peer-58 badMac batch dated too: 07-08 22:30 UTC, post-fix but badMac (identity-regen mismatch), not the race. NOTE: messages FK columns are snake_case (`sender_id`) while plain columns are camelCase (`createdAt`) — adjust ad-hoc SQL.
- (superseded framing) Any duplicate with `createdAt` after 07-08 02:00 CEST from a **confirmed-updated** sender = the `_sessionTails` tripwire fires → runbook Step 3A. Otherwise: expected decay, no action.

### Verdict 3 — badMac ×5 from peer 58 (07-09 00:31) = incident leftover, self-healing

- 58 is one of the 07-07 identity-regeneration accounts. Existing machinery responded correctly (`SESSION_RESET trigger:badMac`; 58's rebuild request re-delivered on every hub connect until the hub next sends to them). Watch only; investigate only if it loops after a fresh exchange.

### Docs shipped (this session's only changes — docs-only)

- Runbook `docs/runbooks/e2e-decryption-failed.md`: new signature row (own-message `[encrypted]` = lost ack, with fix design) + **dating rule** (never classify duplicates by DECRYPT_DECISION timestamp; SQL + sender-version check; stale-sender decay vs real tripwire).

## Key files

- `docs/runbooks/e2e-decryption-failed.md` — new signature + dating rule
- `frontend/lib/providers/messaging_provider.dart:144-148` — `_pendingSendContent` (the map the fix makes durable)
- `frontend/lib/providers/messaging/messaging_provider.history.dart:466-472` — tempId→realId plaintext handoff (the path that needs the reconcile)

## Verification

- Triage evidence: owner's diag dump (durable + live log) + screenshot; DB createdAt check for msgs 14149/14154 pattern established previously; HEAD-diff check proving the analyzed code is current.
- No code changed; no tests to run.

## Notes for next session

- **GATED:** lost-ack reconcile fix — owner said hold; design in the runbook signature row. If approved: provider-layer only, regression test, send-path suites.
- **OWED (owner):** the dating SQL above for msgs 14389–14598 + sender footer versions; decides tripwire-vs-decay for verdict 2.
- **VM SSH from PC timed out** (worked earlier same day for the 0.0.95 deploy; prod healthy throughout) — if it persists, check VM external IP / plink path before the next deploy-from-PC.
- Prod at triage time: backend 0.0.98/d8cf61c, master 0.0.101+ — three releases (typeorm 1.0, socket_io 3.1.6, file_picker 11, composer fixes) shipped by other sessions between my 0.0.95 deploy and this triage.

## BUILT (same session, after owner go)

- Implementation on `fix/lost-ack-pending-send-reconcile` (0.0.102): `EncryptionService.savePendingSendRecord/peekPendingSendRecord/takePendingSendRecord` (per-ciphertext SP keys, TTL 72h/cap 40, wiped by clearAllKeys + clearDecryptedContentCache), recorded at SEND_EMIT in `_encryptAndSend`, consumed on ack in `_addMessageToState`, reconciled in the history-decrypt own-message branch via peek → persist → read-back verify → take with durable `SEND_ACK_RECONCILED{persistVerified}`.
- Two advisory catches during build: (1) first store draft was a shared-JSON-blob RMW — the exact `_sessionTails` lost-update shape — restructured to per-ciphertext keys; (2) first reconcile draft consumed before persisting — flipped to peek/persist/verify/take so a failed persist keeps the record for the next pass.
- Tests: 13 green by the Tester agent across `encryption_service_pending_send_test.dart` (9) and `messaging_provider_lost_ack_test.dart` (4, incl. the verified:false branch with mutation-proven teeth). Full suite 625/625, analyze clean.
- Docs: runbook lost-ack row → FIXED; frontend/CLAUDE.md §5 invariant bullet; pubspec 0.0.102.
