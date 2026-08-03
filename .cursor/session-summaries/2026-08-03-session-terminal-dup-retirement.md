# Terminal-duplicate retirement + DECRYPT_DECISION durable dedupe — released 0.1.6

**Date:** 2026-08-03 (late night)

## What was done

Queue item 4 (promoted the same night after the B2a field verification), both halves, full
gauntlet, released **`0.1.6 / 0014684`** (frontend only; backend stays `0.1.2 / ded8e1a2`) on
explicit owner OK. Smoke 5/5, CI 4/4 green on the feature commit `0fd624c` (incl. e2e-wire).

**Half A — the retire rule (destruction-adjacent).** A HISTORY row failing `duplicate` with
(a) no ledger entry, (b) `recordExists == false` and (c) `rawReplayExists == false` — both
DEFINITE, `null` strictly inert — observed in **3 distinct boot-nonce-gated process lifetimes**
renders retired (`kRetiredMessageLabel`) instead of retrying the consumed ratchet key forever.
Nothing is deleted; a resend recovers. Any DEFINITE readable source resets the counter; retire
drops it. Counter: `e2e_<uid>_dupterm_v1`, cleartext control record, `{"<id>": {"n", "b"}}`,
cap 64 highest-ids-kept, lockless (cross-engine last-write-wins CLOBBERS increments —
under-count, the safe direction). New rule lives in `_evaluateTerminalDuplicate`
(messaging_provider.decrypt.dart, end of file), called only from the duplicate-failure catch.

**Half B — the dedupe (observability-only).** `E2ePersistentDiag.recordDeduped`: a repeat
`(msgId, kind)` `DECRYPT_DECISION` routes to the ring only (full payload). The cap-80 durable
log was ~90% known-terminal repeats — noise evicts evidence. Dedupe state IS the cache:
eviction past cap-80 or a manual clear re-arms the event; nothing is permanently suppressed.
Match substrings carry trailing delimiters (`'{msgId: 1910,'`) so an id can never prefix-match
a longer one; the real call-site line format is pinned by a test.

**Gauntlet:** design doc `docs/design/terminal-duplicate-retirement.md` (now carries all
verdicts) → independent design review (`DupRetireDesignReview`, REVISE — R1 defeatable RAM
session guard → persisted boot nonce; R2 the guard-(a) partition is jurisdictional, guard (b)
carries the safety through the edit-stale fall-through; R3 prefix-collision red test; R4
falsification gaps; R5 accepted (msgId,kind)-only narrowing — all folded in) → implementation
→ **11 falsification mutations, each run RED then reverted** (guard-b, guard-c, tri-state
collapse, nonce gate, reset removal, kind substring, dedupe permanence, delimiter, null-resets,
cap direction) → parallel reviews: data-loss **SHIP** (no loss vector), spec **SHIP-WITH-FIXES**
(one deviation: §3.1 drop-counter-on-retire was missing; without it a boot whose retired-set
load transiently fails would re-retire and burn a SECOND `DUP_TERMINAL_RETIRED` durable —
fixed same session with a pinning assertion) → owner OK → deploy.

## Key files

- `frontend/lib/providers/messaging/messaging_provider.decrypt.dart` — recordDeduped call site
  + guard-(a) condition + `_evaluateTerminalDuplicate`.
- `frontend/lib/services/encryption_service.dart` — counter section (`noteTerminalDuplicate`,
  `clearTerminalDuplicate`, boot nonce + `debugDupTermBootNonce` test seam, cap 64),
  `terminalDuplicateRetireSessions = 3`.
- `frontend/lib/utils/e2e_persistent_diag.dart` — `recordDeduped`.
- `frontend/lib/providers/encryption_provider.dart` — delegates.
- Tests: `test/services/encryption_service_dup_term_test.dart` (8),
  `test/providers/messaging_provider_dup_terminal_test.dart` (9),
  `test/utils/e2e_persistent_diag_test.dart` (+5).
- Spec: `docs/design/terminal-duplicate-retirement.md`.

## Verification

- Flutter **1196 + 10 skipped** (was 1174, +22), analyze clean, count verifier OK, CLAUDE.md §3
  synced same commit.
- CI run 30836810217: 4/4 green (backend, frontend, session-lock, e2e-wire) on `0fd624c`.
- Deploy: `/version.json` 0.1.6, bundle contains `0014684`, smoke 5/5.
- 11 falsification mutations each proven RED (list above), all reverted; restore verified by
  hash-tag match + green re-runs.

## Notes for next session

- **Field expectations (owner's install):** first 3 boots emit `DUP_TERMINAL_SEEN {msgId, n}`
  ring entries for the ~14 rows (peers 49/52/60/83); then ≤14 one-time `DUP_TERMINAL_RETIRED
  {msgId, senderId, sessions}` durables; the rows flip from `[Decryption failed]` to the
  retired label; `duplicate/persist:false` durable noise stops immediately (Half B).
- **Watch item:** a `DUP_TERMINAL_RETIRED` for an id OUTSIDE the known ~14 set means the class
  is still growing — investigate the producer (why do `persist:false` duplicates keep
  appearing?).
- Owner must fully close + reopen the PWA (never uninstall/clear site data).
- Next queue: **B2b `sig_*` sealing — design doc FIRST, own gauntlet** (identity blast radius).
  Then delete-for-me hard-delete (backend), expiry-sweep success diags.
- Owner blockers unchanged (nag): keystore backup; `FIREBASE_SERVICE_ACCOUNT` + real push
  verification; fingerprint-verify peers 54 AND 90.
- Trap paid: an `edit` auto-repair silently swallowed a test fake's `retireLostMessage`
  override — the "impossible" empty-retired failure was a missing override, not async timing.
  Grep the fake for the override before debugging timing.
