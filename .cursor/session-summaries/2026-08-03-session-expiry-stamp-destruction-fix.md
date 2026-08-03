# Session 2026-08-03 (later) — the expiry-stamp destruction bug: root cause, fix, release

Direct continuation of `2026-08-03-session-audit-and-screen-security.md`. The owner ran the new
Storage-sets panel; its output settled the LEDGER_RECORD_LOST question and exposed a live
data-destruction bug, fixed and released here.

## Root cause (every link verified in code, timing fits to the minute)

1. A read-mode disappearing message that arrives LIVE is persisted at decrypt time with
   `expiresAt: null` (server assigns the deadline at read).
2. The ONLY upgrade path was one unacked socket event: `messageDelivered` → `stampRecordExpiry`
   (`messaging_provider.events.dart:188-190`, sole callsite). The stamp was silently lossy twice:
   arriving before the persist commits → no-op with no trace; missed socket window → never
   re-delivered.
3. Unstamped record → never-read fallback deadline `createdAt + 1 day`
   (`_recordExpiryDeadlineMs`).
4. The per-minute sweep destroyed the ONLY plaintext copy of READ messages the server serves for
   4 more days — without `markRetired`, without ledger cleanup.
5. The decrypt ledger caught it: `LEDGER_RECORD_LOST` ×5 (msgIds 19139/19186/19187/19189/19190,
   peer 60 `maoi`, conv 75; server rows confirmed intact/unhidden/expiring 08-05). **The ledger's
   first real catch — it worked exactly as designed.** The 5 messages are recoverable only by
   resend (consumed ratchet keys). Owner's wipe ruled out: retired set contained ONLY the 5 gate
   entries. The other 20 ledger-orphans were server-deleted rows (legitimate).

## The fix (released 0.1.4)

Load-bearing rule at the SWEEP (advisory-driven: the sweep can run before any history pass, so a
heal alone is a race): **a fallback-derived deadline never authorizes destruction.**

1. `_recordExpiryDeadlineMs` returns only a REAL server stamp; unstamped records do not expire
   locally. Residue is reconciliation's job (≤6h after server hard-delete) + the 30-day retention
   bound. Worst-case retention rose 1d → 30d for the lost-stamp case — the recoverable direction.
2. Self-heal: `_restoreFromPersistedPayload` (the single point every served row meets its record —
   fast hydrate, main pass, ledger gate) re-stamps from the server-carried `expiresAt`,
   payload-gated so the common case costs one map lookup. `stampRecordExpiry` is now idempotent
   (skip-if-equal) and LOUD on a miss (`EXPIRY_STAMP_MISS`, ring).
3. Ledger hygiene: deliberate destruction drops ledger entries — `forgetDecryptedMany` (same
   authoritative-read/unconditional-write discipline as `forgetDecrypted`), wired into `_runPurge`
   (confirmed disk removals only) and the wipe.
4. Wipe memory sync: `LocalHistoryWipeResult.wipedIds` mirrored into the provider's `_retiredIds` /
   `_decryptedLedger` — a same-session wipe can no longer masquerade as LEDGER_RECORD_LOST.
5. **Purge-backlog amnesty** (data-loss reviewer's P2): builds ≤0.1.3 could durably enqueue a
   fallback-expired purge whose replay would bypass the new sweep rule. One-time, marker-guarded
   (`e2e_<uid>_purge_amnesty_v1`), drops ONLY obligations for live UNSTAMPED records; stamped and
   record-absent entries and all ciphertexts kept. `PURGE_AMNESTY{dropped}` durable diag.
6. Deleted `mayDestroyExpiredPlaintext` (spec reviewer): destruction-facing helper carrying the
   fallback, zero production callers — a re-introduction trap. Tombstone comment in
   `message_expiry.dart` says why. `messageExpiryDeadline`'s fallback is DISPLAY-only and stays.

## Verification

- Fail-before PROVEN: the old test `expiry sweep honors grace and never-read fallback` pinned the
  destructive behavior and went red against the fix before being rewritten.
- New/rewritten tests: sweep real-stamp rule, self-heal wiring (ledger-gate harness), stamp
  miss-diag + idempotence, forgetDecryptedMany, wipe wipedIds/ledger/memory-sync, purge ledger
  hygiene, amnesty (drop/keep/once). Net +8 tests → **1142 + 10 skipped**, CLAUDE.md §3 synced,
  verifier OK, analyze clean.
- Two independent Anthropic reviewers (data-loss, spec/standards): both SHIP, no CRITICAL/HIGH.
  Their two residuals were both addressed (amnesty; helper deletion). Accepted P3: wipe `wipedIds`
  is a cross-prefix union, so a raw-key removal failure still retires the id while raw bytes
  linger — matches wipe intent, surfaced via `isComplete=false`.

## Traps / notes for the next session

- `purgeLocalPlaintext` tests on the VM cannot assert `isComplete`: path_provider is absent, so
  `AudioCacheStore.remove` reports every id by design. Assert record removal + ledger instead.
- The stamp self-heal is payload-gated on `PlaintextRecordCodec.expiresAtKey` — do not "simplify"
  to an unconditional `stampRecordExpiry` call: that is one authoritative getAll PER ROW, the
  documented 65-77ms/page reload trap.
- The amnesty marker means the filter never runs again; if a future bug class needs another
  backlog amnesty, mint a `_v2` key, do not reuse.
