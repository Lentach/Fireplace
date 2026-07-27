# E2E "[Decryption failed]" — cross-race root-caused, reproduced deterministically, FIXED (0.0.94)

**Date:** 2026-07-07 (evening; follow-up to the quantum-note session's round 7 incident)

## What was done

Owner challenged the previous round-7 verdict ("not a code regression") because users kept reporting `[Decryption failed]` right after that session. Re-investigated from scratch; the verdict was **incomplete**: a real, reproducible race survived the 0.0.90 fix.

### Root cause (CONFIRMED by deterministic repro — the exact field error)

- `EncryptionService.encrypt` (0.0.90) and the provider's decrypt chain are **two separate locks** (`_encryptTails` per recipient vs `_decryptChainBySender` per sender), while **encrypt and decrypt both do load→mutate→store on the SAME Signal SessionRecord**. Nothing serialized them against each other; `EncryptionService.decrypt`, `buildSession`, `deleteSession` had **no service-level lock at all**.
- Lost-update mechanics: an encrypt loads the session; a concurrent decrypt loads the same record; the decrypt's store lands **after** the encrypt's store and writes back a record whose **sender chain is rolled back** → the next encrypt **reuses a chain counter** → receiver throws `DuplicateMessageException ('old counter')` on a **brand-new** message → policy brands it terminal + persists → permanent `[Decryption failed]`.
- Reproduced deterministically in `test/services/encryption_encrypt_decrypt_race_probe_test.dart` via a gated SessionStore (hold the decrypt's `storeSession`, run an encrypt, release): pre-fix it fails with `DuplicateMessageException - Received message with old counter: 1, 0` — **verbatim the field error**. A naive concurrent-loops probe does NOT collide (Dart's deterministic microtask scheduling lands in a benign phase — why the previous session's probe found nothing).
- Real-world trigger: replying while a history/resume decrypt pass runs (iOS PWA resume churn), or receiving live mid-send.

### Why "months fine, broke after that session" (timeline, honest)

- The race is ancient, but until 07-07 web sends were accidentally **staggered**: `sendMessage` awaited a link-preview POST (of the full plaintext — the E2E leak) before encrypting. PR #30 (0.0.89) rightly removed that for most messages → sends got tight enough to overlap decrypts; quantum-note bursts + incident-driven resume churn multiplied the overlap.
- PR #31 (0.0.90) fixed only **half** the race (encrypt-vs-encrypt) and was declared receiver-safe; the encrypt-vs-decrypt half kept corrupting sender chains on prod 0.0.93.
- Also that morning: first real prod **backend** deploy since the dev-mode regression (`/version` now `0.0.89/dacdd85`, buildTime 03:54Z). Audited `b055724..master` backend E2E surface (key-exchange pending-rebuild buffering, gateway) — no backend mechanism producing duplicate counters found; the frontend cross-race is the proven one.
- So: not "new broken code", but the session's changes DID surface the latent race, and round 7's "not a regression" missed it. The spoke identity regenerations (accounts 43/58/81) remain a separate, real phenomenon layered on top.

### Fix (branch `fix/e2e-encrypt-decrypt-cross-race`)

- `encryption_service.dart`: ONE tail-chained per-peer queue `_sessionTails` + `_runSessionSerialized`; **all four session mutators** — `encrypt`, `decrypt`, `buildSession`, `deleteSession` — now run through it. `ENCRYPT_OVERLAP` probe + in-flight bookkeeping preserved. NOT reentrant: guarded methods stay leaf-level (documented; nesting = self-deadlock).
- Test seam: `debugWrapSessionStore(...)` + `_cipherSessionStore` (prod: same object as `_sessionStore`; diagnostics keep reading the concrete store).
- New probe file: 3 tests (concurrent loops canary, sequential control, GATED deterministic lost-update).

## Key files

- `frontend/lib/services/encryption_service.dart` — unified `_sessionTails` lock, seam
- `frontend/test/services/encryption_encrypt_decrypt_race_probe_test.dart` — deterministic repro/regression
- `frontend/CLAUDE.md` §5 — invariant rewritten (all mutators on one lock, leaf-level rule)
- `frontend/pubspec.yaml` — 0.0.94

## Verification

- Pre-fix: gated probe FAILS with `DuplicateMessageException - Received message with old counter: 1, 0` (exact field signature). Post-fix: passes.
- `encryption_send_race_probe_test.dart` (0.0.90 behavior incl. ENCRYPT_OVERLAP) still green; roundtrip + provider race + failure-policy (38), encryption/media/envelope/send suites (68) green; full `flutter test` run; `flutter analyze` clean.

## Notes for next session

- **Honest scope:** this prevents NEW race-made failures. Rows already branded+persisted `[Decryption failed]` during the broken window are **cryptographically unrecoverable** (receiver ratchet consumed those counters; for regenerated identities the old identity is gone) — affected users must **resend**. Nothing clears the stale persisted entries; they linger by design (terminal skip guard).
- **Confirm coverage in the field:** after deploy, pull one affected device's E2ePersistentDiag dump (Privacy & Safety → hacker mode → Durable failures → Copy). `kind:duplicate` events should stop appearing for NEW messages; `identityReset` events would indicate the separate regeneration problem, not this race.
- **Still open (unchanged from round 7):** regeneration guard (gated on the 2-min normal-profile close+reopen key-persistence test — still not run); "clear local message cache" shows scary `[Decryption failed]` for by-design-unreadable old messages (UX copy, could differentiate); stop incognito/clear-data testing advice stands.
- Deploy: frontend from PC `.\deploy-web.ps1` after merge (0.0.94); no backend change in this fix.
- **Recurrence runbook (owner asked "what do I do when it happens again"):** `docs/runbooks/e2e-decryption-failed.md` — stale-build check first, then E2ePersistentDiag dump, then a signature table: `kind:duplicate` on NEW messages = a session-record writer escaped `_sessionTails` (grep for raw `SessionCipher`/`SessionBuilder` outside the serialized bodies; gated-probe repro pattern, naive concurrent probes don't collide); **hang with NO diag events** = the lock deadlocked (a guarded method awaited another guarded method for the same peer — hoist to provider layer; emergency `git revert` of the lock is data-safe); old rows only = pre-fix damage (resend); `identityReset` = regeneration problem, run the 2-min persistence test.

## Post-deploy field verdict (07-08, same session)

- **Merged as PR #33 (`fac70f4`, 07-08 01:57 CEST), deployed to prod; `/version.json` = 0.0.94, tree-verified identical to the built commit `585c96d`.**
- First post-deploy field report classified via the runbook: friend of owner (user 54) sent his E2ePersistentDiag dump — ONE durable entry, msg 14149 from the owner (37), `kind:duplicate, isHistory:true, idReset:false, hadSession:true`. DB `createdAt` = 07-07 18:46 UTC (20:46 CEST) — **~5h BEFORE the fix existed** (commit 01:45 CEST 07-08); failure branded 9 min after send, first attempt via history pass. Friend confirmed the content was **never visible** → H1: **pre-fix sender-side damage** (wire poisoned at encrypt time), NOT the 3C persist-gap. Owner told to resend that one message.
- Post-deploy telemetry clean: same device, two overlapping history passes (incl. resume churn double-reconnect), zero new failures; messages sent after the poisoned one (14154/14166/14177, still pre-fix) decrypt fine — the lost-update fires intermittently and self-heals, exactly the fixed mechanism's signature.
- 3C (persist-gap re-decrypt → spurious terminal) remains **theoretical, no field evidence yet** — build the decrypted-once marker only if a `kind:duplicate` shows up for a message the receiver had actually read, or for anything sent after 07-08 02:00 CEST.
- `feat/metadata-privacy-hardening` (0.0.91) verified **NOT in master, never deployed** — provably unrelated to the incident; E2E-adjacent hunks are log-level-only; safe to merge later (bump its stale 0.0.91 pubspec; needs a backend deploy to take effect).
