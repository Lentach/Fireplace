# Phase 0b — registration lock, reset ceremony, recovery key

**Date:** 2026-08-18

## What was done

Built Phase 0b of the multi-device program (spec `docs/design/multi-device.md`
§6.1 / §6.2 / §6.2.1) on `feat/takeover-alarm-0a`, in worktree
`C:/Users/Lentach/Desktop/fireplace-0a`. Three commits: `07c4a39` (backend),
`321f530` (frontend), `4475e0f` (wire harness + a recovery-flow fix 0b exposed).
Nothing merged, nothing deployed — the branch keeps accumulating per the owner's
2026-08-18 single-branch ruling.

**Owner decisions taken this session (all four asked before any code):**
`curve25519-js` for server-side signature verification (the backend image is
`node:22-alpine`, and `@signalapp/libsignal-client` ships no musl prebuild);
Argon2id at the OWASP profile 19 MiB / t=2 / p=1; true BIP39 for the recovery
phrase; the peer-visible pending-reset surface DEFERRED (0b notifies the
account's own sessions only).

**Registration lock (§6.1).** `upsertKeyBundle` no longer replaces a stored
identity key on a valid session alone. A replacement needs either an XEdDSA
signature by the PREVIOUS identity key over
`newIdentityPublicKey ‖ userId ‖ serverNonce`, or a completed reset ceremony,
which the upload spends. A refusal writes nothing at all — no bundle, no OTP
purge, no audit row, no alarm — and answers
`keyBundleUploaded { success:false, error:'identity_locked' }`. Nonces are 32
CSPRNG bytes on the socket session, TTL 5 min, consumed by ONE attempt whether
or not that attempt was valid. Same-identity re-uploads and first-ever uploads
are untouched.

**Reset ceremony (§6.2).** New table `identity_reset_requests` (migration
`0014`), terminal states, 72 h delay, one pending per account enforced by a
PARTIAL UNIQUE INDEX rather than a read-then-write check, 24 h cooldown after a
cancel, and a per-minute expiry sweep whose `status='pending'` predicate is the
serialization point against a racing cancel. Every start notifies all live
sessions plus every push endpoint; any session can cancel with one tap and no
key.

**Recovery key (§6.2.1).** New table `recovery_keys`. The server stores only an
Argon2id verifier, never the phrase. Valid presentation shortens the delay to
1 h — it never silences the notifications and never grants an instant
replacement. Single-use, spent inside the same transaction that creates the
ceremony, invalidated by any completed reset, rate-limited with a lockout after
5 failures.

**Frontend.** Countdown banner above the fold in the shell with a one-tap
cancel; both new push types render in the PWA service worker and the Android
FCM handler (the cancelled notice replaces the pending one rather than leaving
a stale "act now" card); client state mirrors the server and re-hydrates from
`ownKeyBundleStatus` on every connect.

**Closed the 0a reviewer gap.** `ownKeyBundleStatus` now carries
`identityReplacedAt`, so a session that was offline when its identity was
replaced still raises the banner at connect time. Two suppressions keep that
from becoming noise: a dismissal watermark (the same replacement never returns
after being dismissed; a newer one still alarms), and a self-publish watermark
— without it the device that just completed a ceremony and re-published its
keys would be warned, on its very next connect, about the recovery it had just
performed, on a fresh install with no dismissal history to suppress it. The
self-publish watermark carries a 10-minute clock-skew allowance because the
audit row is stamped by the server and the watermark by the device, so a
replacement by another session inside that window is not surfaced by THIS path
(it is still refused by the lock unless signed or ceremony-backed).

## Two defects found and fixed during the build

1. **Permanent standing grant.** `cancelReset` only touches a `pending` row, so
   once the sweep flipped a ceremony to `completed` nothing could ever clear it
   — an account whose owner recovered their device and simply stopped would keep
   an indefinite, un-cancellable instant-replacement grant, which is exactly the
   zero-delay path §6.2.1 rules out. A completed ceremony is now spendable for
   24 h only; an unused grant lapses and a fresh ceremony is required. Pinned by
   tests.
2. **The consented-recovery flow was silently broken by 0b.**
   `_runIdentityRecovery` cleared the damaged-identity state and reported
   success BEFORE its fire-and-forget upload — which 0b refuses. A user who lost
   their keys would be told they recovered while the server still served their
   previous bundle, so peers keep encrypting to keys that device cannot read,
   with no indication. The refusal is now recorded durably and the reset banner
   covers that state with the only action that resolves it.

## Key files

- `backend/migrations/0014_identity_reset.sql` — both tables + the partial
  unique index enforcing one pending ceremony per account.
- `backend/src/key-bundles/identity-signature.util.ts` — XEdDSA verification,
  fails closed on every malformed input; copies buffers because the verifier
  clears sign bits in place.
- `backend/src/key-bundles/identity-reset.service.ts` — ceremony state machine,
  Argon2id verifier, expiry cron.
- `backend/src/key-bundles/key-bundles.service.ts` — the gate, before any write.
- `backend/src/chat/services/chat-key-exchange.service.ts` — nonce lifecycle,
  ceremony handlers, extended `ownKeyBundleStatus`.
- `frontend/lib/widgets/identity_reset_pending_banner.dart` — countdown +
  cancel, and the refused-publication state with its "start reset" action.
- `frontend/test_e2e/registration_lock_test.dart` — the wire proof.

## Verification

- **Cross-language signature proof.** A vector produced by the REAL Flutter
  client (`Curve.calculateSignature`) verifies under `curve25519-js`; tampered
  message, tampered signature and wrong key all fail; the 33-byte key throws
  unless the `0x05` prefix is stripped. The vector is pinned as a backend
  regression test, so a future dependency swap fails loudly instead of silently
  refusing every legitimate rotation.
- **Red-first, demonstrated rather than claimed.** Against pre-0b code an
  upload carrying an attacker-chosen identity with no authorization was
  ACCEPTED (`identityChanged: true`, bundle written); with 0b in place the same
  attempt throws `IdentityLockedError`. Captured by reverting the gate file and
  re-running.
- Backend **762 tests / 51 suites** (was 685/49), `tsc --noEmit` clean, lint
  ratchet held at the 906 baseline (formatting improved 154 → 147). Getting
  there meant writing the new code and its specs to a stricter standard than the
  file it sits in — typed socket-data accessor, typed mock-call helpers — rather
  than raising the floor.
- Frontend **1343 tests / 10 skipped** (was 1318/10), analyze clean.
- Migration applied cleanly in the REAL boot path (`applying` → `applied`), and
  the partial unique index was behaviourally proven against live Postgres: a
  second pending row is rejected, and a new one is allowed after a cancel.
- **Wire harness 19 passed / 2 skipped** (was 16/2sk) against a real backend and
  real Postgres.
- **Completed-ceremony live-fire.** Started a ceremony (deadline +72 h),
  backdated the row in Postgres, let the REAL per-minute cron commit it
  (`pending` → `completed`), then an unsigned replacement was ACCEPTED, a second
  one was REFUSED, and `consumedAt` was set. **The probe was a throwaway and is
  deleted** (it backdates a row via `docker compose exec`, which does not belong
  in CI), so that end-to-end path — cron commit feeding the gate — now has NO
  automated coverage. What remains is unit coverage of `consumeCompletedReset`
  (spends once, filtered on completed + unconsumed + inside the grace window)
  and of the gate's fallback to it. Re-run the probe from this summary if the
  ceremony or the sweep is touched.

## Notes for next session

- **Two harness tests now carry a rotation proof** (`takeover_alarm`,
  `stale_otp_epoch`, plus `e2e_incident_regression`). That is the intended
  consequence of 0b: unannounced replacements no longer exist, so the 0a alarm
  covers AUTHORIZED ones and `registration_lock_test` covers the refusal.
- **⚠️ Registration ceiling.** `/auth/register` is throttled 10/hour per IP and
  the harness now spends exactly 10. Adding an account to ANY harness file trips
  the suite. The 0b file deliberately runs its whole ceremony on one account and
  reuses the second session it already had.
- **Not built (deliberate, owner-deferred or unreachable):** the recovery-key
  ENROLMENT UI (settings screen + BIP39 generation) — the wire contract and the
  server side are done and proven, but no screen offers the phrase yet, so users
  cannot enrol one and every reset today takes the full 72 h. That is the top
  0b follow-up. Also deferred: the peer-visible pending-reset surface.
- The client never signs a rotation in production: `_generateKeys()` only runs
  on an EMPTY keystore, so a real client that changes identity never holds the
  old key. The signature path exists for spec compliance, the harness, and §6.3
  primary rotation in Phase 2.
- CI on PR #144 is still phantom-red repo-wide (instant fail, no logs, all
  branches) while githubstatus is green — most likely an Actions minutes or
  spending limit; the owner needs to check billing.
