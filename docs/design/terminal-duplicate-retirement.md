# Terminal-duplicate retirement + DECRYPT_DECISION durable dedupe

**Status:** IMPLEMENTED — design review REVISE (`DupRetireDesignReview`, all five findings R1-R5
folded in below); data-loss review **SHIP** (`DupRetireDataLossReview`: no loss vector — retire is
non-destructive, tri-state definite-false-only, null inert, 3 boot-nonce-gated lifetimes);
spec review **SHIP-WITH-FIXES** (`DupRetireSpecReview`: one deviation — §3.1's drop-counter-on-
retire step was missing; fixed same session with a pinning assertion: without it, a boot whose
retired-set load transiently fails would re-retire a surviving n≥3 entry and burn a SECOND
`DUP_TERMINAL_RETIRED` durable, contradicting §3.4's once-per-id). Both reviewers 2026-08-03.
**Queue:** `2026-08-03-HANDOFF-signal-grade-queue.md` §4 (promoted to next-up 2026-08-03 night).
**Governing rule:** over-retention is recoverable, over-destruction is not; destructive rules fail
closed (`2026-08-02-HANDOFF-post-incident-state.md`).

## 1. Problem

~14 rows on the owner's install (peers 49/52/60/83: 18947, 19038, 19063, 19066, 19074, 19077,
19080, 19083, 19086, 19087, 19090, 19094, 19102, 19105, 19106, 19120) re-attempt Signal decrypt
and fail `DuplicateMessageException` on EVERY chat entry, forever. Mechanism:

1. Their plaintext was never durably persisted (`persist: false` in the duplicate policy —
   `decryption_failure_policy.dart:106-123` — deliberately never poisons the durable cache), so
   they never entered the decrypt ledger.
2. Not in ledger → `wasDecryptedBefore` is false → the pre-decrypt gate
   (`messaging_provider.decrypt.dart:984-1049`) is skipped entirely.
3. The ratchet decrypt runs, the key is long consumed → `duplicate` → terminal IN MEMORY only.
4. Next session forgets, repeats from step 2.

Two costs:

- **Evidence eviction (the real one):** each attempt burns a durable `DECRYPT_DECISION`
  (`messaging_provider.decrypt.dart:1196`) into the cap-80 `E2ePersistentDiag` log. The owner's
  dump is now ~90% this noise; a real failure event gets evicted within days.
- Cosmetic: the rows render `[Decryption failed]` (a scary label for "this is gone, resend it")
  and pay a futile ratchet attempt per pass.

## 2. Non-goals

- No change to the duplicate policy itself (`persist: false` stays — its rationale is validated:
  a transiently-unreadable plaintext must stay recoverable).
- No change to the ledger gate (`:984-1049`), `LEDGER_RECORD_LOST`, retention, reconcile, or any
  existing destruction rule.
- No deletion of anything: retirement is a render decision + a stop-retrying decision. Retired
  rows are never deleted; resend recovers the content.
- Live-path (non-history) duplicates are out of scope: they are transient event-churn, not the
  per-boot loop.

## 3. Half A — retire known-terminal duplicate rows (destruction-adjacent)

### 3.1 Rule

When a HISTORY decrypt attempt for message `M` fails classified `duplicate`, and ALL of the
following hold, record one **terminal-duplicate observation** for `M`:

- (a) `wasDecryptedBefore(M) == false` — not in the ledger (in-ledger rows are the existing
  gate's jurisdiction; see §3.5).
- (b) `recordExists(M) == false` — DEFINITE absence: tri-state, `false` only when the store
  verifiably enumerated and the slot is empty (sealed-store totality per
  `docs/design/web-content-sealing.md` §3.1). `null` (undetermined) records NOTHING.
- (c) `rawReplayExists(M) == false` — same tri-state discipline.
- (d) `M` is not already retired and not an own message.

When `M` has accumulated observations in **N = 3 distinct sessions**, retire it:
`retireLostMessage(M)` (persists into `e2e_<uid>_retired_v1`, mirrors into the RAM retired set),
record the durable diag `DUP_TERMINAL_RETIRED {msgId, senderId, sessions}`, drop `M`'s counter,
and return the retired placeholder for this row. From then on `_isRetiredMessage` short-circuits
every future pass (`messaging_provider.decrypt.dart:959,972`) — no decrypt, no diag, honest
"no longer stored on this device" render.

The observation + retire check runs in `_decryptMessageAsync`'s catch block, after
`decideDecryptionFailure` returned the duplicate decision — i.e. strictly AFTER the existing
cache / in-memory / persisted-restore attempts (`:1137-1178`) have all missed.

### 3.2 Why this cannot destroy readable data

- `duplicate` means the ratchet key for this ciphertext is consumed: re-decrypting can never
  succeed again, in any session, ever. The ONLY recoverable sources are a persisted record or
  the raw replay cache — exactly guards (b) and (c), both required DEFINITE-false.
- A plaintext copy can never appear later from our own pipeline: `_persistDecryptedContent` only
  runs after a successful decrypt, which is impossible once the key is consumed. Peer messages
  never touch pendsend (own-message machinery).
- The one genuine late-write source is ANOTHER same-origin engine that decrypted the row and
  persists it after our check. `recordExists` goes through an authoritative snapshot (fresh
  enumeration), so the stale window is a single race per check — and the N=3 distinct-sessions
  requirement means the race must recur across three separate boots while the other engine's
  write never lands in between. Additionally, any session in which guard (b) or (c) stops being
  false RESETS the counter to zero (§3.3), so a late write doesn't just pause the clock, it
  restarts it.
- Fail-closed on error: `null` from either tri-state check → no observation, no reset, change
  nothing (same discipline as the existing gate's undetermined branch `:1043-1047`).
- Retirement is reversible in effect: the row is never deleted, the label is honest, and a
  resend fully recovers the content. The failure mode of a WRONG retire is a mislabeled row —
  recoverable — not data loss.

### 3.3 Counter record

- Storage: `e2e_<uid>_dupterm_v1` — a CLEARTEXT control record (ids-only metadata, same
  convention as `retired_v1`/ledger; explicitly outside the sealed families and outside
  `_decryptedContentPrefix` so record scans/LRU never see it). Lives in `EncryptionService`
  beside `markRetired`, through the `ContentKv` seam — platform-uniform by construction.
- Shape: JSON object `{"<msgId>": {"n": <count>, "b": "<bootNonce>"}}`. Cap 64 entries; on
  overflow keep the HIGHEST ids (ids ascend with age — same convention and rationale as
  `markRetired`). A dropped entry restores the status quo (retry forever) — the safe direction.
- **Once per boot (R1, design review):** the increment is gated on a PERSISTED boot nonce, not
  a RAM set. A process-wide `static final String bootNonce` (timestamp + random, initialized at
  first access) survives provider/service re-creation — in-SPA logout→login and account switch
  A→B→A share one nonce, so three in-process re-inits still count ONCE. An id increments only
  when its stored `b != bootNonce`; the write stores the current nonce. Repeated chat entries
  in one long session count once. "N distinct sessions" therefore means N distinct PROCESS
  lifetimes.
  - Multi-engine note: two engines in the same wall-clock window hold different nonces and
    could each increment — but counter writes are last-write-wins across engines, so
    concurrent increments CLOBBER rather than sum (under-count, the safe direction), and each
    observation independently required both DEFINITE-false authoritative checks.
- **Reset:** if the duplicate-failure path runs for `M` but guard (b) or (c) answers `true`
  (a readable source EXISTS), delete `M`'s counter entry. `null` never resets (undetermined
  changes nothing, in either direction). Entering the ledger makes the rule unreachable for `M`
  (guard (a)), so no explicit hook is needed there; the stale counter entry is inert and ages
  out via the cap.
- Write is commit-gated best-effort: a refused write means the observation is lost — the safe
  direction (slower to retire, never faster).

### 3.4 Diagnostics

- Ring (`E2eDiagLog`): `DUP_TERMINAL_SEEN {msgId, n}` per recorded observation — routine, must
  not burn durable slots.
- Durable (`E2ePersistentDiag`): `DUP_TERMINAL_RETIRED {msgId, senderId, sessions}` exactly once
  per retired id — this is the feature's only destruction-adjacent act and the permanent
  evidence it happened by rule, not by loss. Expected one-time cost on the owner's install:
  ≤14 durable entries spread over the first N boots (they displace noise, not evidence — the
  log is currently ~90% the very entries this feature eliminates).
- No new diag on the reset path (ring `DUP_TERMINAL_SEEN` with a lower/absent `n` next time
  tells the story; a durable would be noise).

### 3.5 Relationship to the existing ledger gate

| Row state | Handled by | Outcome |
|---|---|---|
| In ledger, record lost, no replay | Existing gate `:1026-1042` (pre-decrypt) | `LEDGER_RECORD_LOST` + retire (0.1.3 rule, unchanged) |
| In ledger, undetermined | Existing gate `:1043-1047` | change nothing (unchanged) |
| NOT in ledger, duplicate-terminal, no sources | **This rule** (post-decrypt-failure) | retire after N=3 sessions |
| NOT in ledger, duplicate, any source readable/undetermined | Nobody retires | restore/retry (unchanged) |

**The partition is jurisdictional, not the safety mechanism (R2, design review).** Guard (a)
is NOT airtight: the edit-stale fall-through calls `invalidateDecryptionCache`
(`messaging_provider.decrypt.dart:~1003` → `encryption_provider.dart:240`), which removes the
id from the ledger BEFORE falling through to decrypt — so a formerly-in-ledger edited row that
then fails `duplicate` reaches this rule with guard (a) passing. Safety there rests on guards
(b)/(c): the stale `decrypted_` record is still on disk, so `recordExists == true` blocks the
observation. If an edited row's record AND replay are both verifiably absent for N distinct
boots while its (new) ciphertext keeps failing `duplicate` — i.e. another engine consumed the
edit's key and its persist never landed anywhere readable — retiring it IS the intended honest
outcome, identical to the unedited case. The falsification plan tests both (a)-removed-with-
record-present and the record-absent semantics separately (§5.6a/6b).

### 3.6 The 0.1.4 bug class

The 0.1.4 rule ("a fallback-derived deadline never authorizes destruction") is untouched: this
rule consumes no timestamps, no deadlines, no fallbacks. Its evidence is (1) a cryptographic
fact (consumed ratchet key — `duplicate` from libsignal), (2) two DEFINITE-false tri-state
storage answers, (3) repetition across N boots. Every `null` is inert.

## 4. Half B — DECRYPT_DECISION durable repeat-dedupe (observability-only)

### 4.1 Rule

A `DECRYPT_DECISION` durable for the same `(msgId, kind)` that is already present in the durable
cache is routed to the RING ONLY (full payload, unchanged), not appended to the durable log. A
`kind` CHANGE for the same msgId still records durably (that is new evidence). All other
`E2ePersistentDiag` events are untouched.

**Accepted narrowing (R5, design review):** a repeat with the same `(msgId, kind)` but different
OTHER fields (`isHistory`, `hadSession`, `rule` for non-duplicate kinds) is also suppressed
until cap-80 eviction re-arms it. Deliberate: the flooding class is precisely same-kind repeats,
the ring carries every full payload, and the durable budget is the scarce resource. Widening the
key to `rule` would re-admit per-boot repeats for `noSession`/`unknown` churn — the exact noise
this exists to stop.

### 4.2 Mechanism

New `E2ePersistentDiag.recordDeduped(step, data, {required List<String> matchAll})`: if any
cached durable line contains `step` and every `matchAll` substring → `E2eDiagLog.add` (+ debug
print) only; else fall through to `record`. The decrypt call site passes
`['{msgId: ${msg.id},', ' kind: ${kind.name},']` — the payload map literal's key order is fixed
at the single call site, and a test pins the line format. Trailing delimiters prevent prefix
collisions (`msgId: 1910` vs `19102`).

### 4.3 Properties

- Self-healing: dedupe state IS the durable cache. If the original entry is evicted (cap 80) or
  the owner clears the log, the next occurrence records durably again — the event can rotate
  out but never becomes permanently invisible. No second storage key, no init cost.
- Bounded regression surface: a false-positive match (substring collision) suppresses one
  durable append of an event that fired before — recoverable by construction (ring still has
  it, and eviction re-arms). A false negative just keeps today's behavior.
- Zero change to what the panel DISPLAYS for a first occurrence; repeats remain visible in the
  ring while the session lives.

## 5. Falsification plan (each must run RED first)

1. **Guard (b) removed** → a row whose record exists (but was unreadable this pass) accumulates
   observations and retires at N — destroying a readable message. Test: persisted record
   present, force duplicate failure 3 sessions, assert NOT retired; with guard removed, assert
   the test catches the retire.
2. **Guard (c) removed** → raw-replay-covered row retires. Same shape.
3. **Tri-state collapse** (`null` treated as `false`) → a throwing store retires rows in 3
   boots. Test: store that throws on enumeration, assert zero observations recorded.
4. **Same-boot re-count** → three history passes in ONE process must leave count == 1;
   removing the stored-nonce comparison must turn this red (N sessions collapses to N passes).
5. **Reset removed** → readable-again row (record appears in session 2) still retires in
   session 3+. Test: assert counter cleared when a source answers true.
6. **Partition semantics (R2, split into two cases):**
   - **6a — guard (a) is not the protector:** an in-ledger row whose stale record IS present
     (edit-stale shape) failing duplicate must record nothing — and the test must stay green
     with guard (a) removed, proving guard (b) carries the safety. A companion assertion with
     guard (b) removed (record present, ledger entry present) must go red.
   - **6b — record-absent edit semantics pinned:** an edit-stale row whose ledger entry was
     dropped by `invalidateDecryptionCache` AND whose record + replay are verifiably absent
     accumulates observations like any other row — pins the intended honest-retire outcome.
7. **Dedupe false-suppress** → a `kind` change for the same msgId must still record durably;
   remove the kind substring from `matchAll` and assert the test goes red.
8. **Dedupe self-heal** → after the original entry is evicted past cap-80, the same
   `(msgId, kind)` records durably again.
9. **Prefix collision (R3, design review)** → with the trailing-delimiter removed from the
   `msgId` match substring, a durable for id 19102 must falsely suppress a first-ever durable
   for id 1910 (same kind); with the delimiter present, both ids keep their own durable. Run
   red by removing the delimiter.
10. **Boot-nonce gate (R1)** → simulate provider re-creation WITHOUT process death (re-run the
    observation path against the same static nonce after resetting provider state): count must
    stay 1. Removing the nonce comparison (RAM-set semantics) must turn this red.
11. **Null never resets** → a store answering `null` (throwing) for guards (b)/(c) on a row
    with an existing counter entry must leave the entry UNCHANGED (no increment, no reset).
12. **Cap-64 eviction direction** → overflowing the counter map must evict the LOWEST ids and
    keep the highest; the evicted id's next observation starts from zero (status quo restored,
    never a phantom count).

Safe-direction properties accepted WITHOUT a dedicated red test (R4, design review), each
covered by existing short-circuits or characterization: guard (d) (retired/own rows never reach
the catch — `messaging_provider.decrypt.dart:959,972,962,975`; a cheap assertion that a retired
row records no observation rides along in the suite), and the commit-gated lost-write (a refused
counter write only slows retirement — characterized, not falsified).

## 6. Rollout / field expectations

- Frontend-only; version bump per policy; full gauntlet (this doc → independent design review →
  falsified tests → parallel data-loss + spec reviews → owner OK → deploy).
- First N=3 owner boots: `DUP_TERMINAL_SEEN` ring entries; then ≤14 `DUP_TERMINAL_RETIRED`
  durables; the ~14 rows flip from `[Decryption failed]` to the retired label; the durable log
  stops accumulating `duplicate/persist:false` noise immediately on deploy (Half B) and
  entirely once retired (Half A).
- Watch item: any `DUP_TERMINAL_RETIRED` for an id NOT in the known ~14 set is signal — it
  means the class is still growing and the producer (why do `persist:false` duplicates keep
  appearing?) deserves its own investigation.
- Rollback: reverting the code leaves retired ids retired (same store as every other retire
  path; recoverable by resend, or by owner-side retired-set surgery if ever needed — rows were
  never deleted). Counter records are inert under old code.
