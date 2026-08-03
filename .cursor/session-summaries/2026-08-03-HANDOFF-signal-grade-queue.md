> **ADDENDUM 2026-08-03 (night):** §1 (B2 web sealing) is **DONE and field-verified** —
> released `0.1.5 / bf886a6`, spec + review record in `docs/design/web-content-sealing.md`,
> field proof in `2026-08-03-session-web-b2a-sealing.md` (`WEB_SEAL_OPEN sealed:179/legacy:0`,
> `WEB_SEAL_DRAIN_DONE {sealed:190}`, zero fallback/key-loss events, retired set unchanged).
> §4 (terminal duplicates) is **PROMOTED to next-up** with a new co-requirement: repeat-dedupe
> for `DECRYPT_DECISION` durables — the class grew to ~14 rows across peers 49/52/60/83 and
> now floods the cap-80 durable log (noise evicts evidence). New owner action: fingerprint-
> verify peer 54 (`PEER_IDENTITY_CHANGED` 08-03) in addition to peer 90. B2b `sig_*` sealing
> is a NEW queue item (design doc first; identity blast radius, own gauntlet).

# HANDOFF — the Signal-grade queue, ready to execute

**Written:** 2026-08-03, after shipping `0.1.4 / ca4492c`. Owner wants the items below done, in
roughly this order. **Read first:** root `CLAUDE.md`, `frontend/CLAUDE.md` (§5 above all),
`2026-08-03-session-expiry-stamp-destruction-fix.md` (the bug class you must not reintroduce),
`2026-08-02-HANDOFF-post-incident-state.md` (three deliberate asymmetries, governing rule).
Every volatile fact below — git state, versions, CI — re-verify before acting (`CLAUDE.md` §1).

## State at handoff

| | |
|---|---|
| Prod frontend | `0.1.4 / ca4492c` — expiry-stamp destruction fix, FLAG_SECURE, incognito kbd, Storage-sets panel |
| Prod backend | `0.1.2 / ded8e1a2` — unchanged by design |
| `master` | `ca4492c` + docs; CI green 4/4; prod runs current code |
| Tests | backend **578/47**; Flutter **1142 + 10 skipped**; analyze clean; count verifiers OK |
| Owner device | **iOS Safari home-screen PWA, iPhone 14, NO Mac → NO devtools ever.** The hacker-mode Storage-sets panel + diag dump are your ONLY field instruments. iOS PARTITIONS PWA storage from Safari tabs — a Safari-tab check inspects the wrong store. |
| Owner directive | **Subagents: Anthropic models ONLY** (Codex-backed `task` agents die on usage limits). Ask before the browser tool. Never deploy/merge without explicit OK. |

**Known dead rows on the owner's install (do not re-chase):** 19139/19186/19187/19189/19190
(peer 60 `maoi`) retired honestly — recoverable only by resend. 19102/19105/19106 burn `duplicate`
each boot (item 4 below). Peers 92/93/97 clusters are July damage, closed.

## 0. Owner-only blockers (nag, cannot do for him)

1. **Keystore backup** — `frontend/android/keystore/fireplace-release.jks` is SINGLE-COPY on the
   dev PC. Runbook `docs/runbooks/android-release.md` §"Backing it up": two destinations,
   read-back-verified hashes, passwords stored separately from the file.
2. **`FIREBASE_SERVICE_ACCOUNT`** in `~/fireplace/.env` on the VM + `./deploy-backend.sh`.
   Verify by REAL push delivery to a device, never by the boot warning disappearing.

## 1. Web B2 at-rest sealing — the big one (UNBLOCKED, with hard design constraints)

All Signal key material (`sig_*`) and decrypted history (`e2e_*_decrypt*`) is plaintext base64 in
localStorage on the owner's live PWA (~25 real conversations). The canary gate is now SATISFIED:
owner's dump showed `CANARY_OK {ageDays: 5}` and zero `CONTENT_KEY_CANARY_LOST` durables —
positive 5-day survival evidence for web IndexedDB+WebCrypto keys, not mere absence.

**Design constraints settled THIS session — violating any of them re-arms the exact bug class
fixed in 0.1.4:**

- **A seal/unseal failure MUST read as UNDETERMINED, never as absent.** The ledger gate retires
  PERMANENTLY on `recordExists == false && rawReplayExists == false`. A key-derivation hiccup, a
  WebCrypto transient, or a half-done migration that surfaces as "record absent" would mass-retire
  real history — the 2026-08-02 failure shape at catastrophic scale. The sealed ContentKv must
  return null (undetermined) on ANY decrypt/unwrap error, and `recordExists` must stay tri-state
  THROUGH the new layer: `true` = decrypted a real record; `false` = key VERIFIED present + slot
  verifiably empty; anything else = null.
- **Decide up front whether the retired set + ledger + purge backlog are themselves sealed.** If
  sealed: an unreadable ledger/retired set must FAIL OPEN (treat as "no ledger" → old behaviour,
  attempt decrypt; treat as "nothing retired" → rows render, worst case DuplicateMessage on a few
  rows) — NEVER as empty-and-authoritative, because an empty retired set + present records is
  survivable, while an empty LEDGER + absent records mass-retires. Recommendation: leave the
  control records (retired, ledger, backlog, markers) UNSEALED — they are ids-only metadata, the
  Android store deliberately keeps control records cleartext inside the sealed DB for the same
  reason (`frontend/CLAUDE.md` §5).
- **Migration must be resumable and never destructive:** seal-on-write + read-both, drain old
  plaintext in commit-gated batches (the Android legacy-drain at `frontend/CLAUDE.md` §5 is the
  proven template: DB wins on conflict, only String/int claimed, `E2ePersistentDiag.storageKey`
  excluded BY REFERENCE). No point where plaintext is deleted before its sealed copy is
  READ-BACK-VERIFIED.
- **Key custody mirrors Android:** armed before use (write → fresh read-back), null inventory =
  change NOTHING, loss budgeted → retired-id rendering, never `[Decryption failed]`. The web keys
  live where the canary measures: `flutter_secure_storage` web = IndexedDB + WebCrypto.
  `ContentKeyCanary` STAYS — it is the ongoing early-warning for exactly this storage.
- Reuse the `ContentKv` seam. `PrefsContentKv` is the historical behaviour and also backs
  iOS/desktop/Android-fallback — the web-sealed store must be a NEW implementation selected on
  web, not a mutation of PrefsContentKv (the `kIsWeb` gates inside it protect other platforms).
- Independent review (data-loss + spec, Anthropic reviewers) BEFORE merge; falsify every guard;
  full-suite + `test_e2e` against local backend; owner OK before deploy. First deploy is against
  his real store — same watch item as the ledger launch: any unexpected "no longer stored on this
  device" → dump FIRST.

## 2. Delete-for-me hard-delete (backend, backlog item)

`messages.service.ts` `hideMessageForUser` (~:609 pre-fix numbering) appends to `hiddenByUserIds`
and never checks whether EVERY participant is now in the set — a row both sides deleted survives
until expiry, or forever without one. Fix: hard-delete once all participants hid it.
- Cannot drop on the FIRST delete; other participant still reads it.
- Self-hosted media deleted BEFORE the row (`backend/CLAUDE.md` §8), same as delete-for-everyone.
- Check against the actual participant set, never hardcode 2.
- Reuse `MessagesService.parseHiddenIds`; raw SQL must quote `"hiddenByUserIds"`.
- Run `node scripts/lint-ratchet.mjs` before pushing backend changes.

## 3. Expiry-sweep success diagnostics (frontend, backlog item)

`sweepDestroyablePlaintext` records `PLAINTEXT_PURGE_INCOMPLETE` on failure and NOTHING on
success. Add success-side: ids destroyed, count, and "ran with zero destroyed". `E2eDiagLog`
(ring) for routine; `E2ePersistentDiag` ONLY for destructive/failure edges (cap 80 — noise evicts
evidence). Note 0.1.4 already added `EXPIRY_STAMP_MISS` (ring) and `PURGE_AMNESTY` (durable);
this item is the remaining success-path gap.

## 4. Retire the known-terminal duplicate rows (small, destruction-adjacent)

19102/19105/19106 re-attempt decrypt and fail `duplicate` on EVERY boot, forever (`persist:
false` rows never enter the ledger, so the gate cannot help them). Design sketch: when a HISTORY
decrypt fails `duplicate` for a row that (a) has no record, (b) no raw replay, (c) is NOT in the
ledger, N consecutive sessions — render retired instead of `[Decryption failed]` retry-forever.
Careful: this is a new destruction rule → fail-closed bias, falsified tests, independent review.
Alternative acceptable outcome: leave them; they are cosmetic + diag noise only.

## 5. Android release track (after owner blockers)

Real-phone smoke checklist in `docs/runbooks/android-release.md` §"Device smoke" — 6 items PLUS
new: a screenshot attempt in the RELEASE APK must be refused (FLAG_SECURE, debuggable-gated —
debug builds still allow screenshots). Then first sideload APK per runbook (GitHub Release +
SHA256). Firebase major bumps (#128) belong to the FCM session, deliberately not before.

## Parked by owner decision (do not start unbidden)

App lock (`local_auth`), cert pinning, sealed sender, encrypted cloud backups, app-wide incognito
keyboard (GIF/contact search fields still learn — composer/edit/secret-note are covered).

## Watch items (read the dump when the owner offers one)

- `EXPIRY_STAMP_MISS` entries = the 0.1.4 heal catching lost stamps — GOOD news, expect some.
- One `PURGE_AMNESTY{dropped: N}` durable possible on first 0.1.4 boot — also the fix working.
- Any NEW `LEDGER_RECORD_LOST` post-0.1.4 is a genuine unknown loss — all benign causes are fixed.
  Dump FIRST (cap 80, rotates), then Storage-sets panel (retired/ledger/stored, Copy full).
- Owner should fingerprint-verify peer 90 (`ruchens69`), identity changed 07-31.

## Traps paid for this session (beyond the standing ones in LATEST.md)

- **VM tests cannot assert `PlaintextPurgeResult.isComplete`** — no path_provider →
  `AudioCacheStore.remove` reports EVERY id by design. Assert record removal + ledger state.
- **Do not "simplify" the self-heal to an unconditional `stampRecordExpiry`** — it is
  payload-gated because the stamp does an authoritative `getAll()`: unconditional = one full
  localStorage enumeration PER ROW (the documented 65-77ms/page reload trap).
- **`messageExpiryDeadline`'s never-read fallback is DISPLAY-only.** `mayDestroyExpiredPlaintext`
  was deleted with a tombstone; never rebuild a destruction decision on that helper.
- The amnesty marker (`e2e_<uid>_purge_amnesty_v1`) is one-shot; a future backlog amnesty needs a
  `_v2` key, never reuse.
- Diag queries against prod DB: table is `messages`, columns snake_case for relations
  (`sender_id`, `conversation_id`) but camelCase-quoted for the rest (`"expiresAt"`,
  `"hiddenByUserIds"`). Read-only SELECTs over SSH are fine; anything else is not yours.
- `powershell -File .\script.ps1` from the bash tool eats the backslash — use `-File script.ps1`.
