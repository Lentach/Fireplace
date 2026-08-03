# B2b web sig_* at-rest sealing — implemented, reviewed, DEPLOY HELD

**Date:** 2026-08-03 (late night, after the 0.1.6 release)

## What was done

B2b end to end through the full gauntlet, **committed to master (`13a9fd1`), CI 4/4 green,
NOT deployed** — the owner accepted the availability tradeoff conditioned on a dump proving
`CANARY_OK {ageDays > 7}` plus a fresh deploy OK.

**What it does:** all web Signal key material (`sig_e2e_<uid>_*`: `identity_record_v1` + legacy
mirrors, `session_*`, `pre_key_*`, `signed_pre_key_*`, `trusted_identity_*`) seals as
`fpsig1:<kid>:<b64(12B IV||AES-256-GCM ct+tag)>` in the same localStorage; sealing keys
`fp_sig_key_<kid>` live in the canary-measured IndexedDB+WebCrypto store, a SEPARATE namespace
from content keys (`ContentKeyManager` prefix-parameterized; a cross-family test proves content
rotation can never see or destroy a sig key). Control records (`next_pre_key_id`,
`setup_complete`, unknown keys) stay cleartext. The seam is async (`SigWebKv` →
`SealedWebSignalKv` wrapping the untouched `WebSignalKvStore`), so B2b has NO RAM view — per-op
seal/unseal, the deliberate structural divergence from B2a. Mobile byte-identical.

**The load-bearing rules (every one red-proven; do not weaken):**
- `read()` on an unsealable value THROWS `SigStoreUnreadable`, never null — absence drives
  identity regeneration (`loadFromStorage` absent → `_generateKeys`), ratchet reset
  (`loadSession` null → fresh `SessionRecord`), and prekey id reuse (`containsPreKey` false).
- `readAll()` is PRESENCE-PRESERVING, never value-throwing: every real enumeration caller is
  names-only, and two of them (`_hasPriorInstallResidue`, `_highestStoredPreKeyId`)
  catch-and-swallow throws into absent-equivalents — the design review's two destruction
  CRITICALs. Both also hardened: residue inconclusive → residue-present (blocks regen);
  highest-prekey-id null → mint aborted (`PREKEY_MINT_SKIPPED`).
- Open decision table fails closed: fallback to plaintext is legal ONLY on a SUCCESSFUL
  zero-envelope probe; probe failure or sealed-rows-present → `SigSealOpenUnavailable`
  `fallbackLegal:false` → E2E down this session (`SIG_KEY_UNAVAILABLE`), retried next boot.
  Nothing destructive at open, ever; no retirement concept for key material.
- A fallback session re-probes before EVERY write and refuses to persist plaintext beside a
  sibling's sealed rows (throws `fallback-superseded`).
- Drain: one lock per row, NEVER nested — the original reviewed design nested batch→per-peer,
  which was an ABBA deadlock against the ratchet path (per-peer → lazy open → sig-keys; Web
  Locks origin-wide, no timeout; caught by advisory mid-implementation). Session AND
  trusted-pin rows drain under the per-peer lock their writers take; RAM round-trip verify +
  CAS before every in-place overwrite; nothing deleted.

## Key files

- NEW `frontend/lib/services/encryption/sealed_sig_envelope.dart` (envelope,
  `SigStoreUnreadable`, `SigSealOpenUnavailable{fallbackLegal}`),
  `sealed_web_signal_kv.dart` (`SealedWebSignalKv` + `FallbackWebSignalKv`; five load-bearing
  rules in the class doc).
- `signal_stores.dart`: `SigWebKv` interface; DualStorage web branch through a memoized sealed
  opener (failed open keeps rethrowing = E2E down, never a mid-session flip); test seams.
- `content_key_manager.dart`: `keyPrefix` param + `sigKeyPrefix`.
- `encryption_service.dart`: `debugSetDualStorage` seam; the two §3.1a hardenings.
- Tests: `test/services/encryption/sealed_web_signal_kv_test.dart` (23),
  `encryption_service_sig_hardening_test.dart` (5); `web_signal_kv_store_test.dart` fake gained
  `throwGetAll`.
- Spec + full review record: `docs/design/web-sig-sealing.md` (§5 = 17-item falsification plan).

## Verification

- Design review (`SigSealDesignReview`): REVISE — R1 CRITICAL swallowed-throw→regeneration,
  R2 CRITICAL drain-lock→ratchet rollback, R3 HIGH prekey reuse, R4-R8 — all folded in.
- Post-review advisory: ABBA lock-order deadlock in the *reviewed* design — fixed (flat locks),
  §5.17 order pin committed.
- **15 falsification mutations, each run RED then reverted**: read→null; probe-as-none;
  write-before-verify; CAS removed; fallback guard removed; readAll value-throwing;
  residue→false; prekey default; nested locks; keys-lost→fallback; control sealed; unlocked
  open; plus re-runs proving the added §5.2/§5.3 tests and the §5.7 passthrough-lock race red.
- Implementation reviews: data-loss **SHIP** (no regeneration/reset/reuse/rollback/re-exposure/
  deadlock path; 2 LOW self-healing residuals — trusted-pin drain race fixed at source, prekey
  resurrection accepted in doc), spec **SHIP-WITH-FIXES** (diag payload aligned, 3 tests added,
  kid-sort claim softened — all fixed same session).
- Flutter **1224 + 10 skipped** (+28), analyze clean, count verifier OK, CI 4/4 on `13a9fd1`
  incl. e2e-wire.

## Notes for next session

- **DEPLOY IS HELD.** Two gates, in order: (1) owner dump showing `CANARY_OK {ageDays: >7}`
  (was 5 on 08-03 — crosses ~08-05); any `CONTENT_KEY_LOST`/`CONTENT_KEY_CANARY_LOST` before
  then is the STOP signal; (2) fresh owner deploy OK. Version bump to 0.1.7 happens at deploy
  time, not before.
- Post-deploy expectations: `SIG_SEAL_OPEN {sealed, legacy, ms}` ring per boot (`legacy` ~126
  first boot → 0); one `SIG_SEAL_DRAIN_DONE {sealed}` durable. Escalate on sight:
  `SIG_KEY_UNAVAILABLE`, `SIG_ROWS_UNREADABLE`, `SIG_STORE_FALLBACK` after first boot.
- Rollback story (pinned by tests): old code over envelopes = E2E DOWN but nothing destroyed;
  roll-forward recovers. Never treat that state as fresh-install.
- Also live this session: **0.1.6 / 0014684 deployed** (terminal-duplicate retirement +
  DECRYPT_DECISION dedupe — see `2026-08-03-session-terminal-dup-retirement.md`). Owner should
  fully close + reopen the PWA; expect ≤14 one-time `DUP_TERMINAL_RETIRED` durables over 3
  boots.
- Owner blockers unchanged (nag): keystore backup; `FIREBASE_SERVICE_ACCOUNT` + real push
  verification; fingerprint-verify peers 54 AND 90.
- Trap paid twice this session: far-from-read hashline edits on large docs corrupt sections
  (auto-repair swallowed an override once and a doc section once) — re-read the exact range
  immediately before every structural edit, and re-verify after.
