# 2026-08-26 — the T1–T8 phase gate, and T9 (the four security defects it found)

Branch `feat/takeover-alarm-0a`. **Nothing merged. Nothing deployed.**
Spine: `4c0e0bf` gate fold → `27acd86` T9 settlement → `290cacc` T9 build.

## What happened

The programme's last owed item before Phases 3–4 was the phase gate. It ran, it found real
defects, and the biggest one was in a layer nobody had reviewed hard.

**Three reviewers, three lenses** (spec conformance, test integrity, security/crypto) over
`bf11861...b048ec9` — 103 commits, 197 files, +38341/−1828. Distinct lenses on purpose: three
identical passes find one thing three times. Verdicts SHIP WITH FIXES ×3, one of them with a P0.

Every serious finding was confirmed first-hand before being acted on. That mattered: over this
session several advisories asserted things that were already true or already fixed, and acting on
report rather than on evidence would have duplicated work or "fixed" the wrong thing.

## The gate fold (`4c0e0bf`) — tests that could not fail

Four guards were vacuous under the exact mutation they existed to catch:

- **§6.2 teardown atomicity was half-pinned.** The roster spec proved a `manager` is PASSED; nothing
  proved `RefreshTokensService` HONOURS it. Dropping the `manager ? … : this.refreshRepo` branch left
  both specs green while the session wipe silently returned to the autocommit connection — it could
  then commit while the roster mutation rolled back, the exact false guarantee (xxviii) denies.
- **The login-lockout guard survived its own inversion.** `toHaveProperty('revokedAt')` passes under
  `IsNull()` → `Not(IsNull())`, which resolves login onto a REVOKED device — the T6 defect `43cdc67`
  closed, silently reintroduced. Now asserts the value.
- **The `sendToken` reconcile's refusal path was untested** — `findBySendToken` was not even in the
  mock, which is *why* nothing could reach it. Cross-conversation refusal and sender scoping now
  covered (an unscoped lookup reconciles one account onto another's row).
- **Nothing asserted `devicesSyncing` is ever RAISED.** Every assertion in the suite was `isFalse`,
  so deleting `_setDevicesSyncing(true)` stayed green while the note never appeared.

Also corrected an overstated claim in the T8 closure: the audit had reported ZERO unreachable
`THROTTLE_ANSWERS` entries, but `updateDeviceList` answers `deviceListUpdated`, which has no
production listener and no production emitter — harness-reachable only.

## T9 — settled at `27acd86`, built at `290cacc`

Amendments **(xxxix)–(xliii)**, filed BEFORE the code. Owner approved each fix shape first.

- **(xxxix) THE P0.** Nothing bound a peer's per-device bundle to the one account identity key §3
  promises. TOFU is keyed `(peer, deviceId)`, so a peer's newly linked device is a FRESH address:
  nothing to compare, trusted silently. A server that cannot forge the DAK-signed list could still
  serve its own key for a device that list names. Now fails closed with `AccountIdentityMismatch`.
- **(xli)** the §6.2 teardown now evicts the devices it revokes; it was atomic in the database and
  nowhere else, and both §5.5 gates are connect-time only.
- **(xlii)** a recovery phrase must AGE before it can shorten the window; replacement restarts the
  clock; enrolment is now loud.
- **(xliii)** a device roster is served only to someone who may already message you, plus a required
  carve-out so a later block cannot make received history undecryptable.

## ⚠️ The five things worth remembering

1. **The P0's obvious anchor was the WRONG anchor.** `peerTofuIdentityBase64` reads a hard-coded
   `(peer, device 1)`. Ids are never reused, so a post-§6.2 account has NO device 1 — that slot is
   empty for exactly the accounts that just survived a takeover. Anchor from the I7-verified list.
   **`device_list_cache` still uses the device-1 form for the I7 chain itself — recorded, not fixed,
   because it is outside T9's four findings. Look at it before Phase 3.**
2. **The P0 is not cold-cache bypassable, and the reason is structural.** Reaching a peer's device >1
   requires the verified list (`_resolveFanOut`: `fanOut = recipientList != null`), and that same
   list supplies the anchor. A cold cache means there is no device-2 build to attack. Re-derive this
   before anyone "optimises" `_resolveFanOut`.
3. **Two of the gate's own premises were WRONG; the research round caught both before code.** The
   teardown does not run from a cron (it runs inside `handleUploadKeyBundle`, which already holds the
   socket server), and leaving `account_authorizations` alone is spec-MANDATED, not a bug. Likewise
   the reset was never silent — only the ENROLMENT was — and password re-auth defends nothing against
   an actor who can already run the 72 h ceremony.
4. **The first cut of the eviction would have stranded EVERY recovery.** The recovering client is
   still authenticated as its PRE-reset device id, so its own socket sits in a room the teardown just
   revoked. Evicting before the ack disconnected the caller, and socket.io marks a socket
   disconnected synchronously — so the emit carrying its reissued session silently no-ops. Caught by
   the fresh reviewer, not by me. **The test pins the ORDER; an outcome-only test passed with the bug
   present.**
5. **`createdAt` is a `@CreateDateColumn`, so an UPDATE does not move it.** An age gate that reads it
   naively is bypassed by REPLACING the phrase on a long-standing row. The gate governs the secret,
   not the row.

## ⚠️ Tooling traps paid this session

- **`trap … EXIT` does not fire in the persistent shell**, so two mutated production files survived a
  two-way proof. Restore explicitly and re-check `git status` after every mutation.
- **`set -e` aborts before the restore line** if the mutation run "fails" — which is the expected
  outcome of a two-way proof. Never guard a mutation script with `set -e`.
- **CRLF defeats `perl`/`node` regexes on Dart** (`_setDevicesSyncing(true);^M`). A whole proof ran
  green because the mutation never applied — "0 sites changed" is a FAILED proof, not a passed one.
  Check the mutation landed before believing the result.
- **Both `grep -c` in bash and the built-in grep tool returned 0 for strings that were present.**
  Verify with `sed -n 'Np'` or a direct read; trust test outcomes over grep counts.
- **A `required` named parameter is the right way to add a security check** — it forced all 27 call
  sites in 11 test files to be visited rather than silently defaulting.

## Verified at `290cacc`

backend **1029/62** · ratchet **PASS 889** real — the exact pre-change baseline, so the gate fold and
all of T9 added **zero** lint errors (the first cut added 9 and 2; both were rewritten onto the
suites' own conventions rather than lowering the floor) · analyze clean · flutter **1541/10sk** ·
both count verifiers OK.

**Wire suite: RUN LATER THE SAME DAY, once Docker was freed — see the two sections below. It found
real breakage.** The line that used to stand here ("nothing in T9 has been exercised on the wire")
is now false, and the way it became false is the lesson.

## The wire run (`a65aeff`) — what two green unit suites could not see

backend **1029/62** and flutter **1541** were both green when the wire suite came back **42 passed,
2 FAILED**. One cause, amendment (xlii): `registration_lock_test.dart` and the reset probe each
**enrol a recovery phrase and spend it on the very next line**, so the new age gate correctly
refused to shorten and `shortened` was false. The harness encoded pre-(xlii) behaviour, because T9
was built without ever running it. The second failure was pure cascade — test 1 died before its
cancel could arm the 24 h cooldown test 2 documents inheriting.

Both flows are the LEGITIMATE case (the owner's phrase predates the theft), so both now age the row
**in seconds** via `e2eSql` rather than waiting three days. **No production source changed.**

**(xli) is now proven live and two-way.** The probe had never looked at `deviceRevoked` at all —
that is how the guard stayed wrong twice. With `events.discard` + `events.none` added around the
teardown, deleting `.except(exceptSocketId)` and recompiling fails the probe with a REAL event:
`Bad state: Unexpected "deviceRevoked" …: {userId: 586, deviceId: 1}` — a live server handing the
recovering caller its own revocation, which is exactly what drives `_onOwnDeviceRevoked` into an
unconditional logout. Restored byte-identically, probe green.

> **Two-way proofs validate a test's SENSITIVITY, never its FIDELITY.** Every T9 guard was two-way
> proven against mocks and still shipped a harness that encoded the wrong contract. Only the wire
> run could tell the difference.

## (xliv) — the UX half of (xlii) (`7fffef5`)

Found by looking at what the wire failures implied for a real person. (xlii)'s `too_new` was
**silent**: it returned the same `{status:'pending', shortened:false}` as a no-phrase reset, and the
client reads only `shortened`. An owner who enrolled a phrase two days ago and then lost their
device typed a correct phrase and saw an unexplained 72 h — the natural reading is "rejected", and
the natural next action is to retype it into the five-attempt lockout that (xlii)'s gate had
deliberately left unspent.

**The apparent security tradeoff was illusory, and checking that is what unblocked the fix.** It
looked like "inform the owner = inform the thief". But a WRONG phrase already answers
`invalid_phrase` while a correct one answers `pending`, so **phrase correctness is already
observable today**; the verdict discloses nothing new. Requester-only on `identityResetStatus`; the
room-wide `identityResetPending` alarm still carries no phrase verdict. Transient by design, NOT
persisted on the ceremony row.

Wire-proven on the true path at zero extra registration cost: the ceremony that request starts is
cleared by **DELETE**ing the row, not cancelling it — cancelling is precisely what made this case
untestable here, because it arms the 24 h cooldown the rest of the flow inherits. Falsified by
removing the gateway emit (`Expected: true / Actual: <null>`), then restored. Fresh reviewer: SHIP,
no P0/P1/P2, and it independently confirmed the disclosure argument in all four masking states
(`existing` short-circuit, cooldown, race winner, lockout) plus the one weak assertion
(`identityResetAnswerIsRefusal … isFalse` is redundant but closed by its sibling message tests).

## Verified at `7fffef5`

backend **1031/62** · tsc clean · ratchet **PASS 889** (floor 906, NOT lowered) · analyze clean ·
flutter **1546/10sk** · wire **44/3sk** · opt-in reset probe **1/1**.

## Owed, carried forward

1. **The app-proof is the ONLY unproven half of T9 left, and it is now the narrow one.** Confirm
   `_adoptReboundSession` (`connection_provider.dart:783`) keeps a real browser session through a
   §6.2 recovery. The server-side cause is wire-proven gone, the pre-key partition is wire-proven,
   and production does implement the rebind itself. Needs a browser grant.
2. **(xl)** — bind the account identity key into the DAK-signed list. Durable form of the P0 fix;
   deferred because it changes (d)-governed canonical bytes and needs a list-version migration.
3. **`device_list_cache` anchors the I7 chain on a hard-coded device 1** — a post-§6.2 account has
   no device 1. Look before Phase 3.
4. **The peer-reset↔anchor interaction is reasoned, not observed** — no test covers (xxxix) refusing
   after a peer's own §6.2 key change.
5. `setDisappearingTimer` (same stranded-optimistic-state class as 14f), `updateDeviceList`'s
   unlistened `deviceListUpdated` answer, and the opt-in reset probe's CI gap — unchanged from §13.
6. **Pushes to this branch still run NO CI** — `ci.yml` `push` is `branches: [master]`. Outside a
   ticket; needs an owner ask.
