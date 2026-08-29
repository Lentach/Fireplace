# 2026-08-29 — D1/D2: a reset peer becomes recoverable, and the verify ceremony stops adopting a key nobody saw

**Commit `c33c3b3` on `feat/takeover-alarm-0a`, pushed.** Spec §12 amendment **(xlvii)**, ratified
before the code. Nothing merged, nothing deployed — the merge is still the owner's.

## What was wrong

Two defects, both found in the previous session by following (xlvi)'s own acknowledgement path out
the far side, and both left blocked on an owner decision until the owner said *"proceed with D1 and
D2 and whatever needs to be done to finish whole multidevice topic."*

**D1 (P0) — a completed §6.2 reset left the peer unreachable in BOTH directions, and the only action
offered to the user destroyed the warning while repairing nothing.** The chain, every link read in
source: the peer's re-enrolled list cannot verify against our stale account anchor → the accept gate
withholds their rows *before* Signal decrypt runs → `isTrustedIdentity` never runs → the pending
candidate (whose only writer lives inside it) is never recorded → `promotePendingAccountIdentity`
returns false. And `acknowledgePeerIdentity` had already removed the peer from the alarm set on its
**first line, unconditionally**. The user lost the single persisted notice of a real event and got
nothing back. The nastiest part: **(xlv) clause 1 SUCCEEDING is what made (xlvi)'s recovery
unreachable** — a peer who has *not* re-enrolled still sends a legacy row that takes the device-1
escape hatch, decrypts, and alarms correctly.

**D2 (P1) — worse than the "stale fingerprint" it was filed as.** `getPeerIdentityFingerprint` read a
fixed `(peer, device 1)` address while the confirm button promoted a *different, never-displayed*
candidate. **The ceremony verified one number and adopted another.** For any real rotation the
number on screen cannot match what the peer reads out, so a careful user refuses a legitimate change
and a careless one accepts a key they never compared. That is an inverted defence, not a degraded
one.

## The fix — (xlvii), four clauses

1. **Acknowledgement is atomic with adoption.** The warning clears only if the anchor advanced.
2. **The user sees the key adoption will pin**, and adoption pins exactly that key.
3. **Recovery must not depend on a path that fail-closed.** The client fetches the peer's
   currently-served account identity on explicit user request, shows its fingerprint for out-of-band
   comparison, and pins it only on human confirmation — then drops the state the stale anchor
   poisoned (cached device list + sessions), because the anchor alone is necessary and not
   sufficient.
4. **A per-device row lagging the accepted anchor is not news**, or clause 3's adoption re-alarms on
   the peer's very next message and trains dismissal.

Recovery is proven end to end with real production objects, from the diagnostic trace:

```
DEVICE_LIST_REJECTED  | {userId: 42, reason: invalid_enrollment_signature}   <- unreachable
PEER_IDENTITY_SERVED  | {peerId: 42, deviceId: 5}                            <- key obtained
PEER_IDENTITY_ADOPTED | {peerId: 42, rebuiltAddresses: [1]}                  <- human confirmed
DEVICE_LIST_VERIFIED  | {userId: 42, enrolled: true, version: 2, liveDevices: [5]}  <- REACHABLE
```

The two D1 baseline assertions were **inverted, not deleted**, exactly as that file's own inline
directives demanded.

**Deliberately NOT fixed, and now written into the spec:** a withheld row still raises no *local*
alarm. The only signal at the gate is "this peer's list will not verify", which a server produces at
will by serving garbage; alarming on it would let the server fabricate warnings for any peer and
train dismissal — the harm (xlvi) clause 2 refused in the other direction.

## Seven two-way falsifications, and one of them found a missing test

Each reverts one line and observes a specific red: D2 fingerprint, clause 1, clause 3, clause 4, the
cache invalidate, the rebuild marking, and the offer-equals-pin case.

**F4 initially found nothing.** Clause 4 was implemented and *unproven* — no test covered it — so two
tests were written before it could be falsified. **That is the fourth time in this programme that
writing the falsification exposed a missing test rather than confirming an existing one.**

## E3 phase gate — three reviewers, three lenses

| Lens | Verdict | Findings |
|---|---|---|
| Spec conformance | correct | 0 P0/P1/P2, one P3 |
| Test integrity | **incorrect** | one **P2** |
| Security / crypto | SHIP WITH FIXES | 0 P0/P1, four P2, three P3 |

Every P2 and P3 folded. The two that mattered:

- **The programme's signature failure mode, again.** The clause-3 test asserted the anchor advance
  and the list re-verify but **never the poison-clearing** the spec makes load-bearing:
  `markSessionRebuild` was unasserted, and the cache invalidate was a *proven no-op in that test*
  because nothing was ever cached. Both lines could have been deleted with the suite green.
- **A real regression introduced by this change.** The new identity probe registered in the same
  `_pendingPreKeyFetches` map `ensureSession` uses. `ensureSession` drops the force-rebuild flag on
  its first line, then joins an in-flight fetch and returns early *because the fetch's owner builds
  the session* — which a probe never does. Split into `_pendingIdentityProbes`.

Also folded: **adoption is structural, not conventional.** `adoptIdentityBase64` was opaque caller
input, so "the pinned key is the key the human was shown" rested on one call site behaving. A served
offer is now staged as the pending candidate, and adoption accepts only a key matching the stored
candidate or the current pin; anything else is refused.

The security review's verdict on clause 3 is recorded in the spec rather than buried: making
recovery possible **necessarily** makes the ceremony server-summonable, and the out-of-band
comparison is the whole defence — as it always has been on first contact.

## Also closed

- **Q6a: a throttled `setDisappearingTimer` no longer strands optimistic state**, in the ratified
  (xxxvii) shape — a dedicated `disappearingTimerFailed` answer plus a client pre-change snapshot.
  A refused device used to keep showing a timer the server and the peer never had: a user believing
  messages will vanish when they will not.
- **Q6b: `updateDeviceList`/`deviceListUpdated` verified from source and correctly left alone** —
  zero production listeners *and* zero production emitters; harness-only, and the harness awaits its
  own answer. Still a Phase 3 prerequisite.
- **Both CI count verifiers were failing before this session, in both directions.** `CLAUDE.md`
  claimed 1569 Flutter tests and 1029 backend; actual 1584 and 1042 — the backend number was stale
  by 12 independently of this work. Corrected; both verifiers pass.

## ⚠ The finding that changes the merge conversation: CI has been blind since 2026-08-19

The standing note said CI does not run on this branch because `ci.yml`'s `push` trigger is
`branches: [master]`. **That diagnosis is wrong, and the truth is worse.** PR **#144** is open from
this branch and `pull_request` carries no branch filter, so every push here *did* run the full
workflow — until 2026-08-19, when master diverged and the PR became `CONFLICTING`/`DIRTY`. GitHub
cannot compute `refs/pull/144/merge` for a conflicting PR, so it schedules **nothing**: no run, no
failure, no annotation. Silence that looks like health.

**T9, T10, T11 and this commit have therefore never been CI-tested.** Do not "fix" it by adding the
branch to the `push` trigger — it was never the cause, and it would bill every push against an
allowance the workflow header documents as already blown once.

Re-measured against current master (which has renamed the brand to Umbra and is 28 commits ahead of
the branch's base): **2 conflicts, both docs — `CLAUDE.md` and this directory's `LATEST.md` — and
zero code conflicts** across all 20 changed code files. Resolve `CLAUDE.md` with care: the
`verify-claude-*-test-counts.mjs` scripts gate exactly the lines that conflict, and the correct
post-merge values are the branch's (**1584 Flutter / 10 skipped**, **1042 backend / 62 suites**).

Unblocking CI means bringing master into the branch, which changes the merge candidate the owner is
about to review — so it is **asked, not done**.

## Verified first-hand at `c33c3b3`

```
frontend:  flutter analyze --no-fatal-infos  -> No issues found
           flutter test                      -> 1584 passed / 10 skipped
backend:   npm test                          -> 1042 passed / 62 suites
counts:    verify-claude-frontend-test-counts.mjs -> OK (1584 / 10)
           verify-claude-backend-test-counts.mjs  -> OK (1042 / 62)
```

Full detail: `.planning/multi-device/progress.md` (2026-08-29) and `FINISH-HERE.md` §6a.
