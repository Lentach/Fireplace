# 2026-08-19 — The OTP identity gate, landed as option A (publish first, keys after the ack)

Closes the finding proven on 2026-08-18
(`2026-08-18-session-phase1-local-verification.md` §3). Owner picked **option A**
after being shown that a bare server-side gate breaks a legitimate rotation.
Nothing merged to master, nothing deployed.

Branch `feat/takeover-alarm-0a`. `wip/otp-identity-gate` (`8d61bde`) is now
**superseded** — it holds the server half only, and its `BRANCH-NOTE` describes the
collision this session fixed.

## What the defect was

`uploadOneTimePreKeys` never checked whose identity the keys belonged to, so the
session whose bundle the registration lock had just REFUSED still upserted 20 OTPs
over the legitimate device's `keyId` 0..19 slots, stamping them with the refused
identity. Never *served* (the fetch filter pins the published identity), but the
victim's pool was emptied until a peer fetch triggered `preKeysLow`.

## What landed

**Server** (`key-bundles.service.ts`, `chat-key-exchange.service.ts`)

- `uploadOneTimePreKeys` compares the tag against the account's published identity
  (lowest-device row — every device shares one IK, §3) and throws
  `IdentityLockedError` on mismatch. Two carve-outs, both tested: nothing published
  yet (fresh registration), and an unspent **COMPLETED** ceremony (an authorized
  rotation in flight; reading the grant never spends it). A merely **PENDING**
  ceremony authorizes nothing — that countdown exists so the owner can cancel.
- The refusal logs as `warn` ("refused by registration lock"), not `error`, and
  answers `error { message: 'identity_locked' }`.

**Client** (`encryption_provider.dart`) — this is option A

- Both upload sites (connect-time `initializeE2E`, and `_runIdentityRecovery`) now
  **stash** the pre-keys and emit only `uploadKeyBundle`. `onKeyBundleUploaded`
  releases the stash on `success:true` and **drops** it on any refusal
  (`OTP_UPLOAD_DROPPED`) — an identity the account does not publish must not
  deposit key material at all.
- A `success:true` carrying `identityChanged:true` **mints a fresh pool right
  there** (`_replenishOneTimePreKeys(reason:'identity_published')`). Without it the
  recovered device published an identity with an EMPTY pool: the epoch purge drops
  the superseded rows and the ceremony-spending re-upload carries no keys of its
  own. `onPreKeysLow` now routes through the same helper.

**Tests** — backend 769→**774/52**, Flutter 1371→**1375/10sk**, wire 24→**25/2sk**

- 5 backend unit tests (refusal, published-tag accept with the account-scoped
  lookup asserted, registration-race accept, rotation-in-flight accept that does
  not spend the grant, pending-ceremony refused) + 1 handler test (warn-not-error,
  `identity_locked` answer).
- 4 client tests: stash released only by a successful ack and only once, a refusal
  drops it, a replaced identity refills its pool, a routine same-identity
  re-upload mints nothing.
- 1 wire falsification in `full_stack_e2e_test.dart` (refused under an unpublished
  identity; the published pool survives and never serves the refused epoch) plus
  `EventLog.takeError`, which consumes an EXPECTED refusal so the end-of-run "no
  unexpected socket errors" assertion keeps its teeth.
- `stale_otp_epoch_test` rewritten to the safe order (`reuploadInProductionOrder`),
  header premise updated. Its purge + identity-tagging coverage is unchanged.
- `encryption_provider_session_rebuild_test`'s fake server now ACKS the bundle —
  it drove the real `initializeE2E`, so it caught the contract change immediately.

## Proof in the real app (release build, gate verified inside the container)

| Scenario | Before | After |
|---|---|---|
| Fresh registration | bundle + 20 OTPs | identical, and the log now shows the ORDER: `Key bundle upserted` → `Uploaded 20 one-time pre-keys` (user 204) |
| Second storage mints keys, lock refuses | `REFUSED … replacement` **then** `Uploaded 20 one-time pre-keys`; pool flipped to the refused identity, later purged to 0 (user 168) | `REFUSED … replacement` and **no OTP traffic at all** — the client dropped them, so the server never had to judge; pool intact at 20 rows under the published identity (users 193, 205) |
| Normal messaging | works | works — message sent from one storage decrypted peer-side |
| **Reset ceremony completed** (backdated deadline, real per-minute sweep) | never exercised against Phase 1's per-device tables | grant consumed, `identity-churn` old→new, and **100 OTPs uploaded under the NEW identity** (user 205). Without the refill this ended with an empty pool. |

That last row also closes the readiness gap flagged yesterday: the
reset-**completion** path is now live-fired on the per-device schema.

## Rejected alternatives (all tried, all documented for the next agent)

1. **Await this socket's in-flight bundle upload** after one macrotask yield —
   proven insufficient: the trailing bundle frame is dispatched a tick later, so
   the marker is still unset when the OTP handler checks.
2. **Timed ~500 ms poll** for that marker — works, but makes a lock's verdict
   depend on wall-clock latency. Rejected deliberately.
3. **Blacklist identities the lock actually refused** — fails **open**: upload the
   OTPs *before* ever attempting a bundle and no refusal was ever recorded.

Ordering had to be fixed at the source; that is why A is a client change.

## Verification (local, this session)

`backend npm test` 774/52 · `lint-ratchet` PASS at 906 · `flutter analyze` clean ·
`flutter test` 1375/10sk · `flutter test test_e2e` 25/2sk · both count verifiers OK.
Root `CLAUDE.md` §3 counts updated, §7 gained the publish-then-keys contract.

## Still open for the owner

1. Should a password change clear the 24 h post-cancel cooldown? (§6.2 mandates the
   cooldown; the refusal copy already tells users to change their password, which
   currently does not help them.)
2. `deviceId` 1 is reused across a reset while §5.3 forbids reuse — **must be
   decided before any Phase 2 schema work**.
3. `FIREBASE_SERVICE_ACCOUNT` on the VM; `.jks` off-PC backup; owner-iPhone
   confirmation for 0.1.16.
