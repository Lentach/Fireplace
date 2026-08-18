# Branch note — `wip/otp-identity-gate`

**Status: PARKED, awaiting an owner decision. Do NOT merge this branch as-is.**
Base: `feat/takeover-alarm-0a` at `0592946` (Phase 0a+0b+1, gate-reviewed).

## What it does

Closes the finding proven live on 2026-08-18 (root cause in
`.cursor/session-summaries/2026-08-18-session-phase1-local-verification.md` §3):
`uploadOneTimePreKeys` accepted key material tagged with an identity the
registration lock had just REFUSED, and the upsert on `(userId, deviceId, keyId)`
overwrote the legitimate device's slots 0..N.

- `key-bundles.service.ts` — `uploadOneTimePreKeys` compares the tag against the
  account's published identity (lowest-device row, the same shortcut the lock
  uses) and throws `IdentityLockedError` on mismatch. Carve-outs: nothing
  published yet (fresh registration), and an unspent COMPLETED ceremony (an
  authorized rotation). A merely PENDING ceremony authorizes nothing.
- `chat-key-exchange.service.ts` — the refusal is a `warn` (the lock working),
  not an `error`, and answers `error { message: 'identity_locked' }`.
- 5 unit tests (`key-bundles.service.spec.ts`) + 1 handler test
  (`chat-key-exchange.service.spec.ts`): refusal, published-tag accept with the
  account-scoped lookup asserted, registration-race accept, rotation-in-flight
  accept that does NOT spend the grant, pending-ceremony still refused.
- 1 wire falsification in `full_stack_e2e_test.dart` + `EventLog.takeError` in
  `test_e2e/support/e2e_test_client.dart` (consumes an EXPECTED refusal so the
  end-of-run "no unexpected socket errors" assertion stays meaningful).

## Proof it works (2026-08-19, local, real app)

Release build on `:8083`, two origins = two storages, gate confirmed running
inside the container (`grep` on `/app/src/key-bundles/key-bundles.service.ts`).

| Step | Before the gate (user 168) | With the gate (user 193) |
|---|---|---|
| Fresh registration | bundle + 20 OTPs at `deviceId=1` | identical — 20 OTPs tagged `BTKvz9Dx56yY` (the registration-race carve-out works live) |
| Second storage mints keys, lock refuses | `REFUSED unauthorized identity replacement` **then** `Uploaded 20 one-time pre-keys` — pool flipped to the refused identity `BdfLnk…`, later purged to 0 rows | `REFUSED unauthorized identity replacement` **and** `REFUSED one-time pre-keys under an unpublished identity` — pool intact: 20 rows still `BTKvz9Dx56yY`, 0 used |
| Normal messaging | works | works — message sent from one storage decrypted in the peer's (`g`, 01:33) |

Backend suite 774/52 green, ratchet PASS at 906, `flutter analyze` clean.

## Why it is parked

`stale_otp_epoch_test.dart:72,76` pins the REAL client's emit order: OTPs first,
key bundle second, neither awaited (mirrors `EncryptionProvider`'s two
consecutive emits). A rotation authorized by SIGNATURE therefore presents
new-epoch keys while the old identity is still published, so the strict gate
refuses them and the recovering device starts with an empty pool until the next
peer fetch triggers `preKeysLow`. That test fails on this branch — by design,
not by accident.

Two order-based rescues were tried and rejected:

1. Await this socket's in-flight `uploadKeyBundle` after one macrotask yield —
   **proven insufficient**: the trailing bundle frame is dispatched in a later
   tick, so the marker is still unset when the OTP handler checks.
2. A timed poll (~500 ms) for that marker — works, but makes a lock's verdict
   depend on wall-clock latency. Rejected deliberately.
3. Blacklisting identities the lock actually refused — **fails open**: an
   attacker uploads OTPs *before* ever attempting a bundle, so no refusal was
   ever recorded.

## The decision this branch is waiting on

- **Option A (recommended):** fix the client order — emit `uploadOneTimePreKeys`
  only after `keyBundleUploaded { success: true }` (two sites in
  `encryption_provider.dart`), with an ack-lost fallback (next connect /
  `preKeysLow`). Then this gate is timing-free and `stale_otp_epoch_test` should
  be rewritten to emit in the safe order, its purge+tagging coverage intact.
  Best done inside Phase 2, which rewrites that path for per-device provisioning.
- **Option B:** keep the strict gate and accept the empty-pool window on
  signature-authorized unsafe-order rotations; rewrite `stale_otp_epoch_test`'s
  premise to expect the refusal.

Either way the finding is availability-only: the refused rows were never
servable (the fetch filter pins the published identity), and the attacker needs
the account password.
