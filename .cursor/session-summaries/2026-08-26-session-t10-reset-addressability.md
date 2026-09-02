# 2026-08-26 — T10: a completed §6.2 reset left the account unreachable

**Spec §12 (xlv).** Commits `75b4b7b` (fix) → `e4ee24c` (review fold). Branch
`feat/takeover-alarm-0a`. **NOT merged, NOT deployed.**

---

## How it was found — the part worth copying

Not by a suite. The owner asked what work remained, and the residual list in
`.planning/multi-device/progress.md` carried a vague item: *"`device_list_cache`
anchors the I7 chain on a hard-coded device 1 — look at it before Phase 3."*
Reading the code to write that item up accurately turned a Phase-3 cleanup note
into a bidirectional, permanent message-loss defect.

**The residual list was right that something was there and wrong about what.**
Re-read your own notes against source before believing them.

## The defect

A §6.2 reset allocates a fresh device id (amendment (a): ids are never reused)
and revokes every other device. Nothing re-established the DAK-signed list that
peers use to *address* the account. Both shapes broke:

| Shape | What peers see | Failure |
|---|---|---|
| **Never enrolled** — the majority; enrollment happens only when a second device is linked | `authorization: null` → the client synthesizes the single device 1 a non-enrolled account has *by construction* | **SILENT.** The server accepts envelopes for any device id, so every message is lost, both directions, no error anywhere |
| **Previously enrolled** | The surviving row ((xxix)) names the devices just revoked, signed by a DAK that died with the lost devices | Fails **closed** — `invalid_enrollment_signature`; peers can never send again |

§6.2 is the "I lost my only device" ceremony, so the silent shape is the common
one.

### Why nine tickets and three gate reviewers missed it

**The harness only ever reset accounts it had LINKED first**, because
falsification 12 needs two `(identityPublicKey, deviceId)` partitions to be
non-vacuous. The never-enrolled reset had therefore never once been constructed.

Confirmed against the live DB *before* writing any code: every account that has
actually completed a reset (537, 583–587) is enrolled, and the dangerous shape —
a live device ≥ 2 with no authorization row — had a population of **exactly 0**.

> **A harness only finds bugs in the shapes it builds.** Same lesson as T9's wire
> run, one level up: there, green mocks hid a wrong contract; here, a green wire
> suite hid an unbuilt one.

## The fix — the step (xxix) already reserved

(xxix)'s own text says the enrollment row is *"REPLACED later, by a fresh
IK-signed enrollment."* Nothing implemented "later".
`enrollDeviceAuthority` is emitted from exactly one place in the client: the link
ceremony. **The server has always admitted precisely this replacement** — an
enrollment that no longer verifies under the account's current published identity
is orphaned, and only an identity change can orphan it.

- **Clause 1 — the recovering device re-enrolls.** Fresh DAK, signed by the new
  identity, naming only the freshly allocated id. **It cannot live on
  `LinkCeremonyController`**: `devices_screen.dart:61` registers that as the
  provisioning sink, and a recovery runs at login with no screen mounted, so the
  sink is null. It lives in `ConnectionProvider`, which is app-lifetime.
- **Clause 2 — a roster that cannot receive is refused, in silence**, exactly as
  an entitlement refusal is. Silence is fail-closed on the client (I5: "cannot
  verify", never "no devices"). Converts the dangerous silent shape into the
  survivable visible one.

`nextListVersion` rides the recovery ack because the client cannot read a row
whose signature is orphaned, and guessing 1 against a surviving row reads as a
rollback attempt.

## Review fold — both findings were real

**P2, the good one: there was no RETRY.** A dropped socket or a 20 s ack timeout
stranded the account forever, since the teardown runs only on the upload that
consumes the ceremony. The server now re-offers the terms on **every**
authenticated upload, through **one predicate —
`DeviceListService.pendingReplacementVersion` — shared by both clauses**. That
collapse also caught a shape the first cut missed: clause 2 tested only `!row`,
so the *enrolled* orphan had no retry offer at all.

**P3 corrected an overclaim of mine.** I wrote that dictating `nextListVersion`
"grants the server no authority it lacks". True for a STALE version (refused as
`stale_version`); false for an INFLATED one — every later mutation must exceed
the stored version, so a hostile server naming a number near the integer ceiling
freezes the device list for good, and it stays frozen after the server turns
honest. The client cannot authenticate the number, so it applies a plausibility
ceiling. **The amendment now states the inflation case instead of papering over
it.**

## Falsified three ways, each restored byte-exact and re-run green

| Neutered | Result |
|---|---|
| Clause 2 guard removed | never-enrolled test fails; enrolled one passes |
| `nextListVersion` hardcoded to 1 | enrolled fails `Expected <3> / Actual <1>`; **never-enrolled STAYS GREEN, because for it 1 really is right** |
| Client trigger cut | `Expected an object with length of <1> / Actual: []` |

The middle pair is the informative one: it discriminates a *derived* version from
a hardcoded one, which a single test could not.

## Verification at `e4ee24c`

```
backend 1041/62 · ratchet PASS 889 (floor 906, NOT lowered) · analyze clean
flutter 1551/10sk · wire 44/4sk · opt-in reset probe 2/2
```

⚠️ A full `test_e2e` run straight after several probe runs throws
`ThrottlerException` in `takeover_alarm_test.dart` `setUpAll`. **Budget artifact,
not a failure** — `/auth/register` is 10/hr/IP in memory and shared by the whole
directory. Restart the backend to refund, then re-run.

## Still open

- **The app-proof** — `_adoptReboundSession` keeping a real browser session
  through §6.2. Needs a browser grant. Note it exercises an *enrolled* account,
  so it would not have surfaced this defect.
- **The owner's merge decision.** `git merge-tree`: 2 doc conflicts, zero code.
- Residuals unchanged otherwise: (xl) is its own ticket, `setDisappearingTimer`,
  `deviceListUpdated` has no production listener, and pushes to this branch still
  run no CI (`ci.yml` `push` trigger is `branches: [master]`).
