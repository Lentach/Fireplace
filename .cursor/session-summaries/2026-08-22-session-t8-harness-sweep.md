# 2026-08-22 — T8, the harness sweep

**T8 BUILT, REVIEWED TWICE, WIRE-PROVEN AND APP-PROVEN. Not merged, not deployed.** Seven owed items, all closed.
Closure + deviations: decision record §13. Normative settlement: spec §12 **(xxxv)–(xxxviii)**.

Spine: `343fc1a` settlement → `6f746dc` 14f → `a85129b` 14e → `543bd92` 14g → `0435ea8` 14c →
`46622dc` 14b → `af90c77` 14d+14a → `cecdf44` review fold.

## What was actually wrong with the brief

The T8 handoff said 14a (a second enrolled account in the shared wire suite) had to come first because
14c depended on it. Research contradicted that before any code was written, and the ticket is shaped by
the correction:

- **14c was never blocked.** `list_device_mismatch` needs the PRIMARY as caller and ONE live non-primary
  as target — the "second non-primary device" of the old comment is the primary caller every enrolled
  account already has. Falsification 7 already holds exactly that shape, between `beforeAuth` and the
  real revocation. The probe costs one `revokeDevice` and zero ceremony budget.
- **14b did not need a second account either**, and needed no production seam.
- **14a's real blocker is a cliff nobody had measured.** Not the ceremony budget T7 found — the REGISTER
  budget. `/auth/register` is **10 per HOUR per IP, shared by the whole `test_e2e/` directory** (no nginx
  locally, so every account lands in one bucket). The default run already spends it to the edge: adding
  a third account to `full_stack_e2e_test.dart` threw `ThrottlerException` in
  `takeover_alarm_test.dart`. **Anyone adding an account anywhere in that directory will hit this.**

So the second enrolled account lives in the opt-in reset probe, its only real consumer.

## The proofs that are new

- **A sender's second device DECRYPTS a real self-sync envelope, on the wire (14b).** Falsification 6
  only ever proved routing — its self ciphertext is a synthetic string and the server treats ciphertext
  as opaque. The obstacle was never crypto: both clients are one account, `EncryptionService` derives
  every storage key from `e2e_<userId>_`, and the mock store is one process-wide map. The two keystores
  are separated in TIME — each device acts with its own map installed, re-snapshotted at every swap —
  around the shipping `adoptProvisionedIdentity`. Device 2 publishes REAL key material on its rebound
  socket; placeholders cannot work, because `processPreKeyBundle` verifies the signed-pre-key signature.
- **A real §6.2 reset ran end to end against a live account, for the first time in this program (14d),
  and falsification 12 is proven with two real `(identityPublicKey, deviceId)` partitions.** Live
  evidence, user 537: devices 1 and 2 both `revokedAt 18:31:01.898889`, device 3 primary and live;
  `nextDeviceId` 3→4, never reusing 1; `key_bundles` reduced to device 3 under the NEW identity; every
  old-epoch pre-key gone; reset row completed `18:31:00.032053`, consumed `18:31:01.874745`,
  `shortened=t`; and `account_authorizations.listCanonical` **byte-identical across the reset**, (xxix).
- **`list_device_mismatch` on the wire (14c)**, with the stale T6 comment corrected.

## Two things the two-way proofs taught us that reasoning had not

1. **Making `adoptProvisionedIdentity` mint a foreign identity did not fail where predicted.** It died
   two steps earlier at `uploadKeyBundle` with `identity_locked` — the **§6.1 registration lock**, not
   the harness, is what makes a foreign-identity second device impossible. Amendment (xxxv) was
   corrected in place rather than left standing on a justification now known to be wrong. The
   identity-equality assertion stays, as defence in depth.
2. **The recovering device MUST rebind to the deviceId-bound token the reset teardown issues.** Without
   it, 20 fresh-epoch pre-keys landed on the **revoked** device 1's partition, unreachable behind a
   revoked row. Observed on the first probe run, not predicted by anyone.

## The pin divergence, and the fix that looked obvious and was a trap

A throttled `pinMessage` left an optimistic pin on the device forever: it is not in `THROTTLE_ANSWERS`,
so the refusal took the bare `error` fallback, and the `error` listener only sets a banner and marks
in-flight sends failed — it never touches pin state.

**Reusing `messagePinned` for the refusal is forbidden by (xxxvii).** The guard refuses PRE-handler
holding only `{conversationId, messageId}`, so it cannot author the prior state: a null id unpins a
conversation that had a DIFFERENT message pinned, and echoing the attempted id confirms a pin that never
happened. Neither party holds what a correct revert needs — that is the actual obstacle. So: a dedicated
`messagePinFailed`, and the device restores what it overwrote from a pre-pin snapshot.

`unpinMessage` is deliberately absent from the table — it stakes no optimistic state, so an entry would
be an answer no client code drives to a conclusion. **Full audit of every `@SubscribeMessage`: zero
unreachable table entries.**

## 14g closes by accepting evidence, and that is not a dodge

Per-device `deliveredAt`/`readAt` are barred from the wire by the spec's own rules (I9, §5.3, §4), and
exposing them would reveal WHICH recipient device read a message — on a repo public since 2026-08-18.
Survival is pinned by the content-only conflict clause plus the recorded SQL check, per (xxxviii). Two
real defects were fixed on the way: the old test claimed to protect **`readAt`, which is never written
by any code path** and therefore trivially "survives"; and `stampEnvelope` had no unit test at all, so
its column-scoped `set` and its WRITE-ONCE `IS NULL` predicate were unpinned.

## Traps paid this session

- **`--plain-name` on `test_e2e` invalidated a two-way proof.** It skips the group that enrolls the
  account, so the ceremony died at `openProvisioning` with a null `provisioningId`, nowhere near the
  assertion under test. The proof was redone on the full suite. Rule 7 says this; it still cost a cycle.
- **`nest --watch` recompiles without relaunching.** After a restart the container logged "Found 0
  errors" for over two hours while nothing listened on :3000 — the compile was starved by a concurrent
  `flutter test`. `/health` returned nothing and the wire run hung to a timeout. Recovery is
  `docker compose down && up` from the repo root, then wait for a real `Server running on` line. Do not
  run a heavy suite concurrently with a backend restart.
- **CRLF defeated a `node`-based codemod** on a Dart file; the `edit` tool was used instead.
- **A test-level `skip:` still runs the group's `setUpAll`.** The reset probe would have paid its whole
  registration and ceremony cost on every default run just to skip. The skip is on the GROUP.
- `registerFresh()` builds `e2e_<label>_<8hex>` against a 20-char username cap — long labels fail.

## The app-proof, which is a two-way proof at the app level

Owner granted the browser. Account 193 (device 1), conversation 92, real UI throughout.

Pinned message 649 for real, burned 193's `pinMessage` budget (60/15 min, keyed by USER) from a second
authenticated socket, then pinned a DIFFERENT message from the UI while throttled.

- **With the fix:** server refused it (`REFUSED event=pinMessage userId=193
  answeredWith=messagePinFailed`), DB stayed at 698, banner showed **698**. Converged.
- **With `onPinMessageFailed` neutered to pre-T8 behaviour and the bundle rebuilt:** same operation,
  same refusal, DB still 698 with ZERO successful pins in the window — banner showed **649**, a pin the
  server never stored. **That divergence is the defect, seen live.**

Restored, rebuilt, re-verified converged. Conversation 92 left unpinned, as found.

**⚠️ It produced a FALSE NEGATIVE first.** The budget was initially burned over a hand-rolled socket.io
v4 frame; the token never reached `handshake.auth`, the gateway disconnected the socket, and the
requests were counted under the ANONYMOUS handshake-address tracker. The log said `userId=anon`, the UI
pin then SUCCEEDED, and it looked exactly like the fix failing. **Read the tracker in the throttle log
line before believing a throttle result**, and drive the wire with a real `socket.io-client`.

Not observable by screenshot, and worth knowing: the optimistic apply and the refusal are separated by
single-digit milliseconds on loopback, so no screenshot burst catches the transient — CDP latency
emulation does not slow an already-open WebSocket either. The steady-state two-way proof above is what
makes the revert visible.

## Owed, recorded not claimed

1. **`setDisappearingTimer` is the same divergence class as 14f** — throttled 60/15 min, writes
   optimistic state, absent from `THROTTLE_ANSWERS`, not unwound by `error`. Found during the audit and
   deliberately not fixed, so the ticket stayed single-purpose.
2. The reset probe is opt-in, so it defends nothing in CI until the registration budget has room.

## Verified at `cecdf44`

backend **1007/61** · ratchet **PASS 889** real (floor 906, not lowered) · analyze clean · flutter
**1530/10sk** · wire **44/3sk** · opt-in reset probe **1/1** (`--dart-define=RESET_PROBE=true`). Both
count verifiers OK. Reviewed by a ticket reviewer (one P3, folded as `cecdf44`) and then by a fresh
reviewer on the fold (zero findings) — no P0/P1/P2 either time.
