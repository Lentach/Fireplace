# 2026-08-03 (night) — B2a web at-rest sealing: built, reviewed, RELEASED as 0.1.5

**State at end:** **prod frontend `0.1.5 / bf886a6`** (deployed on owner OK, smoke 5/5, CI
4/4 on the release commit), backend `0.1.2 / ded8e1a2` unchanged. Flutter
**1174 + 10 skipped**, analyze clean, count verifier OK. Design doc:
`docs/design/web-content-sealing.md` (the authoritative spec, including every review finding
and its resolution). Owner must fully close + reopen the PWA (never uninstall); the first
sealed-session boot runs the one-time drain — request a diag dump after.

## What shipped (code, merged to master only)

All Signal-decrypted history on web (`e2e_*_decrypted_/decrypt_raw_v1_/pendsend_v1_`) is now
sealed at rest: AES-256-GCM envelopes (`fps1:<kid>:<cid|->:<b64(iv||ct)>`) over the SAME
localStorage backing store, keys in `flutter_secure_storage` web (IndexedDB + WebCrypto — the
exact store the 5-day `CANARY_OK` measured). New `SealedWebContentKv` behind the untouched
`ContentKv` seam; web opener (`content_kv_opener_stub.dart`) memoizes and falls back to
`PrefsContentKv` + `CONTENT_STORE_FALLBACK{web-*}` on any arming failure. Android/iOS/desktop
byte-identical by construction (`_io` opener untouched). `ContentKeyManager` reused UNCHANGED.
`ContentStoreUnavailable` moved to `content_kv.dart` (web build must not import drift).

## The five rules that must never regress (each has a falsified test)

1. **Unseal failure reads UNDETERMINED, never absent.** Unsealable rows are served as their
   raw envelope string — `recordExists` decides presence on raw bytes, so the ledger gate
   never retires them. `authoritativeSnapshot()` is TOTAL: never null, never omits a key,
   enumeration failure THROWS (→ `recordExists` null). Falsified: omission flipped
   `recordExists` to false (the 0.1.4 class) — red.
2. **Proven key loss only inside the open lock** (`fireplace-e2e-content-keys`, Web Locks).
   Design-review C1: unserialized, a cold-store mint race retires readable rows (committed
   hazard test demonstrates it). Mid-session unknown kids NEVER retire — present-but-
   unreadable until the next locked open. Fold retires only ids with NO readable sibling
   source (`decrypted_` OR `decrypt_raw_v1_`) — data-loss review D2, falsified.
3. **Drain never overwrites unverified.** In-place seal: RAM round-trip verify BEFORE the
   destructive write (design-review H1, falsified: verify-after-write destroyed the only
   copy) + COMPARE-AND-SET re-read before the write (data-loss review D1, falsified: an edit
   landing mid-drain was clobbered; a purge was resurrected).
4. **Erasure completeness** (advisory): envelope `cid` is deliberately cleartext so
   user-requested conversation deletion selects sealed rows in ANY session state (fallback/
   rollback/key-loss) via a synthetic `{_cid}` record in `_messageIdsMatching` —
   AUTHORITATIVE scans only; automatic destruction still skips what it can't read.
   Falsified: skip-everything under-selected the erasure — red.
5. **Control records stay cleartext** (retired/ledger/backlog/markers/diag), read-both
   forever, migration never deletes anything (in-place replacement, resumable by
   construction, batches of 32 under the lock).

## Review record

- Design review (`SealDesignReview`): REVISE → C1 (mint race, CRITICAL), H1 (drain verify
  order), M1 (snapshot totality), M2 (durable diag churn), L1 (memo unbounded) — ALL folded
  into the design before code.
- Mid-design advisory: erasure-over-envelopes hole (delete-conversation silently selecting
  zero ids in a fallback session) → the cleartext-`cid` rule.
- Implementation reviews: `SealSpecReview` SHIP (3 LOW nits: two diag-payload parity fixes
  applied — `CONTENT_KEY_LOST{kids,rows,accounts}` with actual kid values,
  `CONTENT_RECORDS_UNREADABLE{rows,accounts}`; drain-latency-for-mid-drain-legacy-row
  accepted as designed). `SealDataLossReview` SHIP-WITH-FIXES → D1 + D2, both fixed and
  falsified same session. Headline verdict: the 0.1.4 destruction class is CLOSED.

## Diags to expect in the next dump (post-deploy)

`WEB_SEAL_OPEN{sealed,legacy,unreadable,lostRows,ms}` (ring, once per boot — the `ms` number
is the open-unseal budget check, design cap ~500ms), drain batches in ring, ONE
`WEB_SEAL_DRAIN_DONE{sealed:~140+}` durable when migration completes. NOT expected:
`CONTENT_STORE_FALLBACK{web-*}` (sealing didn't arm), `CONTENT_KEY_LOST` (proven key loss →
retired rendering), `CONTENT_RECORDS_UNREADABLE`. `PLAINTEXT_SCAN_SKIPPED` durable is now
deduped per session on automatic scans (authoritative scans always durable — those are
evidence). Watch item unchanged: unexpected "no longer stored" → dump FIRST.

## Traps paid for

- **SharedPreferences updates its RAM cache even when the commit is REFUSED** — tests
  asserting refusal must check `SharedPreferencesStorePlatform.getAll()` (the durable
  truth), not `prefs.getString`.
- **The open() auto-drain starts before the test can flip failure flags** — set fake-sealer/
  refusal flags BEFORE `openStore()`, or the drain races them (was a real flaky).
- The drain CAS window is same-engine only; cross-engine same-key writes remain last-write-
  wins, exactly the status-quo prefs semantics.
- `_view` stores the ORIGINAL raw envelope string for unreadable rows (not a re-encode) so
  presence checks compare byte-identical values.
- Kid marker `fp_content_active_kid_v1` is device-wide and OUTSIDE `e2e_<uid>_` so
  `clearAllKeys` can't sweep it (mirrors Android's meta row / key custody rule).

## Deferred (design §6, owner-visible)

Rotation/shredding (envelope carries `kid` from day one — code-only later), B2b `sig_*`
sealing (own design doc; different seam, identity blast radius), lazy open-unseal (only if
the measured `ms` blows the budget on the iPhone).

## Next

1. **Owner OK → deploy** (`deploy-web.ps1` from the PC after CI green). First boot on his
   install runs the one-time drain over ~138 stored records; then request a dump and check
   the §Diags list above.
2. Owner blockers unchanged: keystore backup, `FIREBASE_SERVICE_ACCOUNT`.
3. Queue: delete-for-me hard-delete (backend), sweep success diags (small), Android track.
