# Web at-rest content sealing (B2) — design

**Status:** DESIGN, revised. Written 2026-08-03 against `master e876056` (prod frontend
`0.1.4 / ca4492c`). Independent design review (`SealDesignReview`, Anthropic reviewer)
returned REVISE with findings C1/H1/M1/M2/L1 — all folded in below (§3.2a, §3.4 step 3,
snapshot totality, diag hygiene, memo pruning), plus the erasure-completeness advisory
(§3.1 "Erasure completeness").
**Prereqs read:** root `CLAUDE.md`, `frontend/CLAUDE.md` §5,
`.cursor/session-summaries/2026-08-03-HANDOFF-signal-grade-queue.md` §1 (the settled
constraints), `2026-08-03-session-expiry-stamp-destruction-fix.md` (the bug class this design
must not re-arm).

## 1. Problem

On web (the owner's production surface: iOS Safari home-screen PWA), every persisted plaintext
artifact of `EncryptionService` is base64/JSON **cleartext in localStorage**:

| Family (per `encryption_service.dart`) | Content |
|---|---|
| `e2e_<uid>_decrypted_<id>` | decrypted message records — the ONLY surviving copy of consumed-ratchet plaintext and of one-shot `mediaKey`/`mediaIv` |
| `e2e_<uid>_decrypt_raw_v1_<id>` | raw replay cache (cap 40) |
| `e2e_<uid>_pendsend_v1_<ct>` | pending-send plaintext snapshots |

A copy of the browser profile / device backup / disk image yields the full readable history.
Android fixed this in Phase 2 (SQLCipher + per-row AES-GCM sealing behind the `ContentKv` seam);
web was deliberately deferred behind the `ContentKeyCanary` durability gate. That gate is now
**satisfied**: the owner's dump showed `CANARY_OK {ageDays: 5}` and zero
`CONTENT_KEY_CANARY_LOST` durables — positive multi-day survival evidence for
`flutter_secure_storage` web (IndexedDB + WebCrypto) on the exact production device.

### Threat model (honest scope)

Protects: at-rest disk forensics, browser-profile copies, device backups, localStorage dumps —
the sealed values are AES-256-GCM ciphertext whose keys live in the origin's IndexedDB-backed
secure store (WebCrypto), not beside the data.
Does NOT protect: an attacker running JS in the origin (XSS), a compromised device at runtime,
or the server. Same posture as the Android store: at-rest protection, not an offline cache and
not runtime hardening.

### Scope split

- **B2a (this design): the three `ContentKv` plaintext families above.** Largest data mass,
  proven seam, proven template.
- **B2b (separate, later): `sig_*` Signal key material.** Different seam
  (`signal_stores.dart` / DualStorage), and the blast radius is the identity itself —
  a sealing bug there is unrecoverable-by-design. Needs its own design doc. Not started here.

## 2. Governing rules (from the handoff, restated as acceptance criteria)

1. **A seal/unseal failure MUST read as UNDETERMINED, never as absent.** The ledger gate
   (`messaging_provider.decrypt.dart`) retires permanently on
   `recordExists == false && rawReplayExists == false`. Any transient that surfaces as
   "record absent" mass-retires real history — the 2026-08-02 shape at scale.
2. **Control records stay UNSEALED**: `e2e_<uid>_retired_v1`, the decrypt ledger, the purge
   backlog, retention/reconcile stamps, amnesty markers, `E2ePersistentDiag.storageKey`, the
   canary shadow. They are ids-only metadata and are precisely what must remain readable after
   a key loss (same deliberate choice as the Android store's cleartext control records).
3. **Migration is resumable and never destructive**: seal-on-write + read-both; plaintext is
   deleted ONLY after its sealed replacement is read-back-verified.
4. **Key custody mirrors Android**: armed before use (write → fresh read-back), null
   inventory = change NOTHING, proven loss → retired-id rendering, never `[Decryption failed]`.
5. **New implementation, not a mutation of `PrefsContentKv`** — that class is the historical
   behaviour and backs iOS-native/desktop/Android-fallback.
6. `ContentKeyCanary` STAYS — ongoing early warning for exactly this storage.

## 3. Design

### 3.1 New class: `SealedWebContentKv implements ContentKv`

New file `frontend/lib/services/encryption/sealed_web_content_kv.dart`. Wraps the SAME
backing store as `PrefsContentKv` (SharedPreferences → localStorage: synchronous JS writes,
survive tab close — the original reason the records live there, unchanged) and seals ONLY the
values of the three plaintext families. **Keys stay cleartext** (message ids were already
visible; Android likewise keeps key strings and kids cleartext).

The file stays VM-importable (no `dart:js*`/`dart:io`): dependencies are `SharedPreferences`,
`ContentSealer` (injected — VM tests use a deterministic fake; the webcrypto native is not set
up on the test VM, which is the documented reason the interface exists), `ContentKeyManager`
over `SecureKv` (already platform-agnostic), and `E2ePersistentDiag`. Only the opener is
web-only.

#### Envelope

Sealed value = `fps1:<kid>:<cid|->:<base64(12-byte IV || AES-256-GCM ct+tag)>` (string,
since the backing store is string-typed). Properties:

- The `fps1:` prefix discriminates sealed from legacy plaintext → read-both costs one
  `startsWith`. A legacy plaintext value can never collide: decrypted records are JSON
  (`{`-prefixed) or legacy raw base64; pendsend records are JSON. (Guard test anyway: the
  codec must refuse to decode an `fps1:` value as plaintext.)
- `kid` in the envelope from day one → rotation/shredding (deferred, §6) needs no format
  migration.
- **`cid` (the record's conversation id, decimal; `-` for the raw-replay and pendsend
  families, which are not conversation-erasure targets) is DELIBERATELY cleartext** — the
  erasure-completeness rule below. Metadata honesty: message id (already in the cleartext
  key), kid, and conversation grouping are visible; content, media keys, and timestamps are
  not. `cid` is fully readable in today's plaintext store, so this leaks nothing new; it
  mirrors the Android doctrine that metadata a destruction rule depends on stays readable
  without the content key. Deletion trusting a tampered cleartext `cid` is not a new power:
  an attacker who can rewrite localStorage can already delete rows outright.

#### Erasure completeness (advisory finding — user-requested deletion over unreadable rows)

`_messageIdsMatching` serves two callers with OPPOSITE failure directions
(`encryption_service.dart:1940-1948`): user-requested erasure
(`messageIdsForConversations`, `authoritative: true` — under-enumeration leaves history the
user asked to destroy readable) and automatic destruction (`destroyableMessageIds` —
over-enumeration destroys the only copy). Today both SKIP undecodable values
(`:1988-1991`). In a fallback-to-prefs session after the drain has sealed rows, every
sealed row is undecodable — so "delete this conversation" would select zero ids and
silently report success while sealed plaintext survives to the next roll-forward. The
forbidden class, inverted.

Rule: for `authoritative: true` scans ONLY, a value that parses as an `fps1:` envelope
contributes a synthetic record `{_cid: <envelope cid>}` so conversation-scoped erasure
selects it in every session state (fallback, rollback, unsealable-row, proven-key-loss —
destroying a row the user asked to destroy is correct even when it cannot be read).
Non-authoritative scans keep skipping envelopes: a synthetic record has no `_savedAt`, and
letting it default to the retention epoch would re-arm epoch-based destruction of rows a
fallback session merely cannot read. `PLAINTEXT_SCAN_SKIPPED` stays a durable on
authoritative scans (a skip there is evidence of exactly this hazard — e.g. a malformed
envelope); the per-session dedupe in §3.5 applies to the non-authoritative repeats.

#### The sync-read problem → RAM plaintext view at open

`ContentKv.getString` is synchronous by contract (every sweep/LRU/reconcile loops it over
thousands of keys); WebCrypto is async. Same resolution as Android (`AesGcmContentSealer`'s
open path unseals every row at startup): `open()` enumerates the store once, unseals every
sealed row, and serves reads from a RAM view. Memory is not a regression — SharedPreferences
already holds every value (today: the plaintexts themselves) in its RAM cache.

Unseal memo: `Map<String /*sealed string*/, String /*plaintext*/>` so `reload()` /
`authoritativeSnapshot()` re-unseal only strings not seen before (cross-engine writes),
never the whole store per pass. The memo is PRUNED to the live envelope set on every
reload diff (fresh IVs make every write a new envelope; without pruning a long-lived
home-screen PWA session accumulates one plaintext entry per envelope ever seen —
review finding L1).

#### Read paths and the tri-state guarantee (rule 1)

- Row unseals → RAM view holds plaintext; `getString` returns it. `recordExists` → `true`.
- Row FAILS unseal while its kid is PRESENT in a successfully enumerated inventory
  (corruption, tamper): the RAM view keeps the **raw sealed string**. `recordExists` decides
  presence on raw bytes BEFORE decode (`encryption_service.dart:1044-1049` — "a corrupt
  record still means the plaintext was here"), so the row reads as **present-but-unreadable**:
  `recordExists == true`, the gate never retires, `getDecryptedContent`'s decode fails →
  existing corrupt-record behaviour. Undetermined-never-absent falls out of the existing
  contract with ZERO interface change. Diag: `CONTENT_RECORDS_UNREADABLE {rows, accounts}`
  (durable, same name and field shape as Android — same semantics).
- Row's kid MISSING from a successfully enumerated inventory: **proven key loss** → at open,
  BEFORE any decrypt, ids parsed from the row keys are folded into `e2e_<uid>_retired_v1`
  (identical shape/cap-5000 as `markRetired` / the Android fold). Rows are **never deleted** —
  the key may come back. Diag: `CONTENT_KEY_LOST {kids, rows, accounts}` (kid values,
  bounded — the forensically useful part of a key-loss dump).
  **Proven loss is only provable inside the open lock (§3.2a).** Android's fold is safe
  because that store is single-isolate; this seam is multi-engine by contract. Without
  serialization, two engines racing a cold store can each mint a kid, and the slower
  engine's pre-mint inventory misses the faster engine's kid while its row scan already
  sees rows sealed under it → readable rows retired permanently (review finding C1, the
  forbidden class). Inside the lock the hazard is structurally gone: a kid observed in any
  row was persisted (armed: write + read-back) BEFORE that row was written, and the locked
  open takes its inventory AFTER acquiring the lock, so a fresh inventory that still lacks
  the kid is genuine loss, not skew.
  **And the fold is no more aggressive than the runtime gate** (data-loss review finding
  D2): the gate retires only on `recordExists == false && rawReplayExists == false`, so an
  id is folded ONLY when neither its `decrypted_` row nor its `decrypt_raw_v1_` row is
  readable from a surviving source — a message whose replay-cache entry still unseals (or
  whose record is legacy plaintext) is servable and stays live.
- Inventory returned **null** (enumeration itself failed): change NOTHING — `open()` throws
  `ContentStoreUnavailable('web-inventory')`, session falls back (below).
- Inventory enumerated successfully but EMPTY while sealed rows exist on disk:
  unavailable-not-wiped (a genuinely wiped secure store also killed the Signal identity, which
  has its own path) → throw, fall back. Mirror of the Android rule.
- `authoritativeSnapshot()` (async, so unsealing per call is fine): `getAll()` like
  `PrefsContentKv`, then map sealed values through the memoized unseal; a present-but-
  unsealable value is included AS ITS RAW SEALED STRING — never omitted (omission == absent
  == retire) and never null. **Totality is a falsified guard, not a habit** (review finding
  M1): the tri-state chain rests on it — `_rawRecord` falls back to the sync RAM view when
  the snapshot is null (`encryption_service.dart:127`), and that view can lack a row another
  engine wrote, so a null-on-enumeration-failure would read as `recordExists == false` →
  retire. Contract: (a) NEVER return a non-throwing null; (b) NEVER omit a backing-store
  key; (c) an enumeration failure PROPAGATES as a throw, so `recordExists`'s own catch
  answers null (undetermined).
- `reload()`: `prefs.reload()` then diff raw values against the last view; unseal only
  new/changed sealed strings (memo); keys removed by another engine leave the view. Cost
  stays one enumeration per pass, per the documented 65-77 ms trap budget.

#### Write path

`setString` on a sealed-family key: seal → on `null` from the sealer, return `false`
(refused write — `ContentSealer` contract; a false here is already load-bearing upstream,
see `saveDecryptedContent`) and write NOTHING; else `prefs.setString(key, envelope)` and
propagate the commit result; update the RAM view only on `true`. Same kid+key-bytes capture
BEFORE the seal await as Android gate (1) — cheap now, load-bearing when rotation lands.
The envelope `cid` is parsed by the STORE from the plaintext being sealed (`jsonDecode` →
`PlaintextRecordCodec.conversationIdKey`, `_decrypted_` family only; non-int or missing →
`-`) — no seam API change. Pre-`_cid` legacy values seal with `-`, matching their existing
documented unmatchability (`encryption_service.dart:1415`).
All other keys (control records, `setInt`, unknown prefixes) pass through verbatim.
`remove`/`containsKey`/`getKeys` operate on the backing store keys (unchanged semantics).

### 3.2 Key custody

Reuse `ContentKeyManager` UNCHANGED over
`FlutterSecureStorageKv(FlutterSecureStorage(webOptions: WebOptions(dbName: 'FireplaceE2E')))`
— the same instance/options as the Signal keys and the canary target, deliberately: failure
modes must stay correlated (if that store dies, the identity died with it). Content keys are
`fp_content_key_<kid>`, OUTSIDE `e2e_<uid>_` so `clearAllKeys` cannot sweep them. No DB key
on web (there is no SQLCipher file; `fp_content_db_key_v1` stays Android-only).

Active kid at open: successful inventory non-empty → newest kid (kids embed a mint
timestamp); empty (and no sealed rows yet) → `mintContentKey()` (armed: write → fresh
read-back → only then seal anything). Mint returning null → throw `('web-arm')`, fall back.

Two PWA engines racing first mint is handled by the §3.2a open lock; even so, duplicate kids
are individually harmless — kids are unique, both entries persist, both appear in every later
inventory, rows sealed under either unseal fine. The lock exists for the retirement fold, not
for kid uniqueness.

### 3.2a Cross-engine open lock (review finding C1)

The entire open-time critical section — inventory → mint/arm → backing-store row scan →
proven-loss retirement fold — runs under the existing cross-context lock facility
(`session_cross_context_lock.dart`, Web Locks; the same mechanism that serializes prekey
minting and the ledger), lock name `fireplace-e2e-content-keys` (its own name: it touches
no SessionRecord and no ledger, so it must not reuse those locks). Ordinary reads/writes
after open take no lock — only mint and the proven-loss fold are serialized, so the
steady-state cost is zero. The drain (§3.4) takes the same lock per batch: it re-seals
under the active kid and must not interleave with another engine's future rotation.
Falsified test: the C1 two-engine cold-store race, red without the lock.

### 3.3 Opener (web)

`content_kv_opener_stub.dart` (web build of the conditional import; MUST stay `dart:io`-free)
becomes the web twin of `content_kv_opener_io.dart`:

- Memoize the sealed path AS A FUTURE (concurrent first calls cannot race two stores; a
  session that fell back stays on prefs — no mid-session backend flip-flop).
- Any `ContentStoreUnavailable(stage)` or unexpected throw →
  `E2ePersistentDiag.record('CONTENT_STORE_FALLBACK', {'stage': 'web-<stage>'})` +
  `PrefsContentKv.open()`. Fallback is the status quo (plaintext, loudly diagnosed) — NEVER a
  store that pretends to be sealed. The `web-` stage prefix keeps the field diag stream
  separable from Android's.
- Non-web platforms: byte-identical behaviour by construction (only the stub changes; the
  `_io.dart` opener is untouched).

### 3.4 Migration (rule 3)

State lives entirely in the data (resumable by construction; no counters to corrupt):

1. **Seal-on-write from first armed session**: every new write of a sealed family is an
   envelope. No flag day.
2. **Read-both forever**: a legacy plaintext value (no `fps1:` prefix) is served as-is by the
   RAM view. Correctness never depends on the drain finishing.
3. **Background drain**, batches of 32, under the §3.2a lock: for each legacy plaintext row
   of the three families: seal in RAM → **unseal-verify IN RAM that the envelope round-trips
   to the original plaintext BEFORE any write** (review finding H1: with in-place replacement
   there is exactly one value under the key at all times, so a post-write verify would
   detect a non-round-tripping envelope only after the sole plaintext copy is already
   overwritten — and a media record's one-shot `mediaKey`/`mediaIv` with it) → **re-read the
   key and COMPARE-AND-SET** (data-loss review finding D1: the crypto awaits yield to the
   foreground; a stale write-back would clobber an edit that landed mid-drain — the
   `_sessionTails` lost-update shape — or RESURRECT a row a purge removed; no await sits
   between the re-read and the write, so the check is atomic in-isolate) → only then
   `setString(key, envelope)` → commit `true` required → post-write read-back is a
   BYTE-EQUALITY check (durability proof; it can no longer lose data). A crash at any point
   leaves either the plaintext or a pre-verified envelope under the key — both served
   correctly by read-both. A failed verify/commit aborts the drain for this session (retry
   next open); partial progress kept. Ring diag per batch; one durable
   `WEB_SEAL_DRAIN_DONE {sealed}` when a full enumeration finds zero legacy rows (one-shot
   informational, cap-80-friendly).
4. **Nothing is ever deleted by the migration.** In-place replacement under the same key
   removes the classic delete-before-verified-copy hazard, and the RAM round-trip check in
   step 3 closes the residual overwrite window: no value is replaced until its replacement
   is PROVEN readable. `remove()` semantics stay untouched.

Rollback story: a build rolled back to `PrefsContentKv` after sealing began would read
envelopes as opaque strings — records present (never retired: raw-bytes presence rule) but
unrenderable until roll-forward. Acceptable: over-retention direction, and prod rollback of
the frontend is already an owner-gated rarity.

### 3.5 Diagnostics

| Event | Channel | Meaning |
|---|---|---|
| `CONTENT_STORE_FALLBACK {stage: web-*}` | durable | sealing unavailable this session; running legacy plaintext |
| `CONTENT_KEY_LOST {kids, rows, accounts}` | durable | proven key loss → rows retired (not deleted) |
| `CONTENT_RECORDS_UNREADABLE {rows, accounts}` | durable, deduped once per open | rows present but unsealable under a present key |
| `WEB_SEAL_DRAIN_DONE {sealed}` | durable, one-shot | migration finished |
| open timing / drain batches | ring | perf + progress, no durable noise |

Durable-channel hygiene (review finding M2): the cap-80 durable log is the owner's only
field instrument and noise evicts evidence. `CONTENT_RECORDS_UNREADABLE` records at most
once per open (aggregate count). `PLAINTEXT_SCAN_SKIPPED` stays durable on
`authoritative: true` scans (a skip there means a user-requested erasure saw a value even
the envelope parser could not classify — evidence, see "Erasure completeness"); on
non-authoritative scans it gets a per-session dedupe in `encryption_service.dart` — first
occurrence durable, repeats to the ring.

`ContentKeyCanary` unchanged.

### 3.6 Performance budget

- Open: one enumeration + unseal of ≤ ~2040 sealed rows (record cap 2000 + raw cache 40).
  WebCrypto AES-GCM decrypt is native and per-row tiny; the cost is promise overhead.
  Budget: < 500 ms async at first `_sharedPrefs` use, off the first-paint path (open is lazy).
  Measured number goes in the ring diag; if a real device blows the budget, the fallback is
  lazy per-family unsealing, NOT weakening the view semantics.
- Steady state: one seal per write; `reload()`/`authoritativeSnapshot()` unseal only unseen
  strings (memo). The 65-77 ms/pass reload trap budget is unchanged.

## 4. What does NOT change

- Every semantic above the seam: purge, two-phase expiry, reconcile, retention, LRU, ledger,
  backlog, amnesty — byte-identical on every platform (the seam's whole purpose).
- `PrefsContentKv`, the `_io` opener, the Android store, iOS-native/desktop behaviour.
- Where records live (localStorage), their keys, control records, `remove()` semantics.
- The canary, `sig_*` storage (B2b), all UI.

## 5. Test plan (every guard falsified — fail-before required)

VM tests inject a deterministic fake `ContentSealer` (the interface's documented purpose) and
a fake `SecureKv`; the real-cipher round trip is covered by `AesGcmContentSealer`'s existing
coverage plus one web-targeted round-trip in the sealed store's own suite where the host
allows, `skip`ped otherwise (same pattern as the Android crypto assertions).

1. **Unseal failure ≠ absent** (rule 1, the load-bearing one): corrupt a sealed row (key
   present) → `recordExists == true`, ledger gate does NOT retire, decode-failure path taken.
   Falsification: a naive impl that drops unsealable rows from the view retires it — test
   must go red against that.
2. **Snapshot never omits unsealable rows**: `authoritativeSnapshot()` contains the raw
   sealed string for a corrupt row.
3. **Null inventory changes nothing**: enumeration failure → fallback to prefs, zero
   retirements, `CONTENT_STORE_FALLBACK{web-inventory}`.
4. **Proven kid loss retires, never deletes**: missing kid → exactly that kid's ids folded
   into `retired_v1` (cap respected), rows still on disk, other kids' rows served.
5. **Empty-but-rows-exist = unavailable, not wiped**: fallback, zero retirements.
6. **Armed gate**: mint read-back mismatch → throw, fallback, nothing ever sealed this
   session.
7. **Seal failure refuses the write**: sealer returns null → `setString` false, backing
   store untouched, RAM view untouched.
8. **Read-both**: legacy plaintext row served verbatim; sealed row served unsealed; `fps1:`
   value never decodes as plaintext.
9. **Drain never overwrites unverified**: a sealer producing a non-round-tripping envelope
   (fake sealer whose unseal disagrees) → plaintext value UNTOUCHED, batch aborted; a killed
   drain (simulated) resumes with no loss and no double-seal corruption; drain completion
   emits the one-shot durable. Falsification: a verify-after-write ordering must go red.
10. **Cross-engine coherence**: raw backing-store write of a sealed envelope by "another
    engine" → visible after `reload()`; removed key leaves the view.
11. **Control records stay cleartext**: after a full drain, raw backing values for
    `retired_v1`/ledger/backlog keys are plaintext.
12. **Opener memo + fallback stickiness**: concurrent first opens yield one store; a
    fallen-back session never flips to sealed mid-session.
13. **Non-web untouched**: `_io` opener behaviour pinned (existing tests already do).
14. **C1 cold-store mint race** (falsified): engine B opens with an inventory snapshot taken
    BEFORE engine A's mint while A's sealed row is already in the backing store → with the
    §3.2a lock, zero retirements; the unserialized ordering must retire A's row (red).
15. **Snapshot totality**: a backing-store enumeration failure inside
    `authoritativeSnapshot()` THROWS (→ `recordExists` null), never returns null and never a
    partial map. Falsification: a catch-and-return-null impl must turn `recordExists` false
    and go red.
16. **Erasure completeness over unreadable rows** (falsified, advisory finding): a
    fallback-to-prefs session (or unsealable-row state) holding `fps1:` envelopes for
    conversation X → `messageIdsForConversations({X})` selects those ids via envelope `cid`;
    ids of OTHER conversations' envelopes are NOT selected; `destroyableMessageIds` still
    skips all envelopes. Falsification: the skip-everything-undecodable behaviour must
    return an empty set and go red.
17. **Drain compare-and-set** (falsified, data-loss review finding D1): an edit landing
    during the drain's crypto awaits survives (the stale re-seal never clobbers it); a
    purge landing there stays purged (never resurrected). Falsification: the CAS removed
    must clobber/resurrect and go red.
18. **Fold respects sibling sources** (falsified, data-loss review finding D2): a lost-kid
    `decrypted_` row whose `decrypt_raw_v1_` sibling is readable (and vice versa) is NOT
    retired; only the id with no readable source is. Falsification: the unfiltered fold
    retires all three and goes red.

Full suite + `test_e2e` against local backend before merge; independent Anthropic data-loss +
spec reviews BEFORE merge; owner OK before deploy. First deploy watch item: any unexpected
"no longer stored on this device" → dump FIRST (same protocol as the ledger launch).

## 6. Deferred (explicitly out of B2a)

- **Rotation/shredding** (web twin of Android's `shred_gen` machinery): removal today is a
  localStorage delete, same as the status quo; the envelope's `kid` field means adding
  rotation later is code-only, no data migration. Honest claim until then: "sealed at rest",
  never "shredded".
- **B2b `sig_*` sealing** — own design doc.
- Lazy/partitioned open-time unsealing — only if the measured open budget fails on device.

## 7. Interface sketch

```dart
/// Web sealed backend of the ContentKv seam. Values of the three plaintext
/// families are AES-256-GCM envelopes (`fps1:<kid>:<cid|->:<b64(iv||ct)>`)
/// over the SAME localStorage-backed store; all else passes through verbatim.
class SealedWebContentKv implements ContentKv {
  /// Arms the content key (inventory/mint + fresh read-back), enumerates the
  /// backing store, unseals sealed rows into the RAM view, folds PROVEN
  /// kid-loss ids into the retired set, and schedules the legacy drain.
  /// Throws [ContentStoreUnavailable] on any condition where sealing cannot
  /// be trusted this session — the opener falls back to [PrefsContentKv].
  static Future<SealedWebContentKv> open({
    required SharedPreferences prefs,
    required ContentKeyManager keys,
    required ContentSealer sealer,
  });

  // ContentKv: reads serve the RAM plaintext view (sync); writes seal
  // families / pass through others; reload()/authoritativeSnapshot() unseal
  // incrementally via the sealed-string memo.
}
```

`ContentStoreUnavailable` moves (or is re-exported) so the stub opener can use it without
importing the drift-backed native store into the web build.
