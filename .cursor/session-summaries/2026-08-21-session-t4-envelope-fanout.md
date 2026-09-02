# 2026-08-21 — T4: send fan-out, per-device envelopes, device rooms, per-device history reads

Ticket **T4** of the Phase 2 multi-device program (frozen spec `docs/design/multi-device.md`
§5.2 + §5.3). Built, gate-reviewed (**GATE FAIL → all findings folded**), and **app-proven on
two real devices**. Branch `feat/takeover-alarm-0a`, pushed. **Nothing merged, nothing deployed.**

Closure + deviations: decision record §9. Normative settlement: spec §12, 2026-08-20 block,
items **(v)–(x)**. Research: `docs/plans/2026-08-20-t4-envelope-fanout-research.md`.

## Commit spine

```
31ce335  docs: research + pre-implementation settlement (items (v)-(ix))
98ad178  B1 backend — envelope send ingest, atomic fan-out write, deviceListStale
bbcfe8b  B2 backend — device rooms, per-device delivery/push, preKeysLow, prekey-limiter fix
80b6035  B3 backend — per-device history reads, envelopeStatus, column-scoped projection
c5ddeed  C1 client  — per-device Signal addressing
1461e9d  C2 client  — verified device-list cache (recovered from a stalled writer)
abae48c  C3 client  — fan-out send, sendToken, stale-list repair (+ NEW amendment (x))
1885038  C4 client  — envelopeStatus rendering, honest placeholder, en+pl l10n
b28d268  C5 client  — decrypt against the ORIGIN device's session
8c8b12c  test       — wire falsifications (amendment (x), 5, per-device delivery, 13)
9c42859  fix        — review fold (BLOCKER + 2 P3)
```

## 1. Research first, then settle, then code

The owner's instruction this session was explicit: maintain the planning files and **research
before implementing**. Five researchers ran in one batch — three read-only codebase scouts
(backend send path, client send path, wire harness) and two librarians against primary sources.
Output: `docs/plans/2026-08-20-t4-envelope-fanout-research.md`.

What the research changed:

- **Prior art validated the planned shapes.** Signal-Server models exactly our envelope list
  (`IncomingMessage{destinationDeviceId, destinationRegistrationId, content}`), rejects two
  messages for one device (`isNotDuplicateRecipients`), and validates BEFORE any insert. Sesame
  §3.3/§4.1 mandate a finite retry loop without fixing the number, so cap 3 is consistent.
- **Our reject payload is strictly better than Signal's** and is the Sesame shape: Signal returns
  device ids only (`MismatchedDevicesResponse`/`StaleDevicesResponse`) and forces a second
  `/keys` round trip; Sesame explicitly permits returning the key material with the ids, which is
  what our `lists[]` does — one round trip repairs everything.
- **Matrix is the prior art for the marker.** `matrix-sdk-crypto`'s `UtdCause` keeps a dedicated
  `SentBeforeWeJoined` variant distinct from generic `Unknown`, and MSC2399's
  `m.room_key.withheld` carries a machine-readable `code`. So `envelopeStatus` as an extensible
  string enum is industry-consistent, not invention.
- **Decrypt is not idempotent, at source:** libsignal removes the message key on use
  (`state/session.rs:455`) and Sesame §2.1/§3.4 discard state on a failed decrypt. No prior art
  broadcasts one ciphertext to several devices. This is why every "just fan it out" shortcut is
  forbidden.
- **The research forced amendment (ix)** before a line was written: a new-model row carries no
  ciphertext for its own origin device, so the landed exact-ciphertext lost-ack reconcile would
  silently stop matching and strand the only plaintext copy.

**Process note:** `scout` agents have NO write tool — they cannot produce `local://` files. Have
them return findings inline and persist them yourself. `librarian` agents can write.

## 2. Amendment (x) — forced during implementation

The settlement said legacy sends bypass the freshness cross-check. Building it revealed why that
cannot stand alone: making the client fetch a device list on EVERY send — to prove that a
single-device account is single-device — taxes the overwhelmingly common path, and it hung 19
existing suites on a fetch the harness never answers.

Resolution, now normative as item (x):

- The client fans out **only when it already holds a verified list for the RECIPIENT** (seeded by
  an explicit `getDeviceList`, a `deviceListChanged`, or a `deviceListStale` refusal). Otherwise
  it sends the legacy shape, which the server normalizes to a device-1 envelope at ingest.
- **The server refuses a legacy ciphertext send whenever EITHER party is enrolled**, answering
  `deviceListStale` with every enrolled party's signed list. A legacy send reaches device 1
  alone, so accepting it for an enrolled peer would silently drop that peer's other devices —
  exactly what invariant I5 forbids. I5 therefore lands **server-side, where a client cannot
  skip it**, and the refusal is what upgrades a client to fan-out.
- Corollaries, each earned by a near-miss caught mid-edit:
  - **Never fan out without the recipient's list.** Envelopes addressing own devices only would
    commit a row with a NULL legacy column whose recipient reads `none_for_device` forever — the
    message permanently invisible to the person it was sent to.
  - **The refusal handler must resolve parties ABSENT from `lists[]`.** An enrolled sender with a
    non-enrolled recipient yields a single entry; without resolving the other party the resend
    repeats the legacy shape and burns the retry budget to a hard failure.
  - **`socketReady` echoes `deviceId`.** The client cannot derive which device it is, and a
    fan-out must exclude its own origin device.
  - A ciphertext-less send (PING) is never refused — it has no envelope to fan out.

## 3. What landed

**Backend.** `SendMessageDto` grew `envelopes[]` + `senderListVersion` + `recipientListVersion`.
Legacy `encryptedContent` is normalized at ingest to a one-element device-1 envelope, so exactly
one write path exists downstream; a legacy row additionally KEEPS its column so today's clients
read it unchanged for the whole §8 rollout window, while a new-model row leaves it NULL. Message
row + N envelopes commit in ONE transaction (`msgRepo.manager.transaction`, the house pattern).
Refusals run before any persistence: `duplicate_envelope_device` (two envelopes for one device
would consume one message key twice), `unknown_envelope_user` (not in the amendment — without it
a client could have the server deliver ciphertext to a third party it never named),
`self_envelope_for_origin_device`, `unknown_recipient_device` (device 1 exempt, as the
key-material gates already are). `deviceListStale` carries `lists[]` + `tempId`.

Ciphertext is addressed per device: every socket joins `device:<uid>:<did>` as well as
`user:<uid>`, `emitToNewestTab` became `emitToDeviceNewestSocket` (newest socket WITHIN one
device), and `newMessage` is emitted once PER ENVELOPE with that device's own ciphertext. A send
with no ciphertext keeps single-target delivery to device 1 — without that fallback those sends
reached nobody. Push suppression is per device and skips only when EVERY delivered recipient
device has the conversation focused. `preKeysLow` routes to the low device's room.

History reads join envelopes on the requesting `(userId, deviceId)` and implement the §5.3
device-gated fallback: own envelope → legacy column gated to the row's session owner
(`deviceId == (originDeviceId ?? 1)` for own rows, device 1 for received rows) → the additive
`envelopeStatus` marker with a NULL ciphertext. `updateDeliveryStatus` was converted from a
full-entity `save()` to a column-scoped UPDATE with the monotonic guard in the WHERE clause.

**Client.** Per-device Signal addressing (deviceId parameterized across encrypt/hasSession/
buildSession/decrypt; `_sessionTails` and the cross-context lock re-keyed to `(userId, deviceId)`
so two devices of one peer cannot serialize onto the same lock). A verified device-list cache
whose highest-version pin survives invalidation — otherwise a server could re-serve v1 after
pushing a `deviceListChanged` — and which is fail-closed: a missing TOFU identity, a failed
chain, or a rollback throws and caches nothing. Fan-out send with one distinct ciphertext per
address, `sendToken` minted per tempId and reused by retries, and a `deviceListStale` repair that
verifies the I7 chain before adopting (an invalid chain fails the send — never the server's bare
word), capped at 3 attempts. `envelopeStatus` rendering with an honest "sent before this device
was linked" placeholder in en+pl, stamped at history ingestion.

**C5 was not in the plan.** C1 had parameterized only the send side, so every inbound decrypt
still used address `(sender, 1)`: a peer's device-2 envelope would Bad-MAC, and a PreKey message
could clobber the working device-1 session. Fan-out would have been one-directional and the
app-proof would have failed at the first inbound message.

**Two bugs the settlement had not anticipated.** `preKeyBundleResponse` echoed no `deviceId`, so
two in-flight per-device fetches for one peer were indistinguishable. And the pre-key fetch
limiter was keyed `(requester, target user)` with a 750 ms floor, which **REFUSED the second
bundle fetch of a two-device peer outright** — multi-device session establishment was impossible
as landed. Both fixed; the protected resource has been per-device since Phase 1.

## 4. Review — GATE FAIL, folded

A fresh reviewer reproduced every number independently and returned **GATE FAIL** with one
BLOCKER and two P3 notes. All folded as `9c42859`.

**BLOCKER — the lost-ack reconcile stranded the only plaintext copy on every legacy send.** The
send path saves the durable pending-send record under the CIPHERTEXT for a legacy send and under
the send TOKEN for a fan-out. But the reconcile keyed on `sendToken ?? encryptedContent`, and the
token is emitted on EVERY send (it is also the server's idempotency key), persisted, and echoed
back to the origin device on its own history rows. A legacy row therefore arrived carrying both,
the token won, the lookup missed the ciphertext-keyed record, and the plaintext — the ONLY
surviving copy, because a Signal sender cannot decrypt its own ciphertext — was permanently
stranded. Since no account is enrolled yet, **every production send is legacy**: every lost ack
would have lost its message. Fixed by mirroring the save side (`encryptedContent ?? sendToken`).
The existing suite could not catch it because its own-row helper omitted the echoed token; the
helper now takes it and a regression test pins the both-fields case.

P3: the same precedence bug in reverse on the success path (a fan-out record was never consumed
and leaked on disk). P3: `stampEnvelope` was dead code — defined, never called, so per-device
delivery stamps were never written; now wired into `handleMessageDelivered` to stamp the
REPORTING device, kept separate from the recipient-only row projection and still never feeding
expiry or the read TTL.

## 5. Verification

```
backend        920 / 57 suites      (was 885/57)
lint ratchet   PASS at 903          (baseline 906 — improved; floor NOT lowered mid-ticket)
flutter analyze  clean
flutter test   1451 / 10 skipped    (was 1424/10sk)
wire test_e2e  39 / 2 skipped       (was 35/2sk)
```
Both count verifiers OK; root `CLAUDE.md` §3 updated and §7 gained a full T4 bullet.

Four new wire falsifications, all against a real backend, ZERO new registrations: amendment (x)
(a legacy send to an enrolled account is refused with the signed list and delivers nothing),
falsification 5 (a stale version is rejected atomically, current version handed back, nothing
delivered), per-device delivery (device 1 receives ITS ciphertext once, and the recipient copy
carries no `sendToken` and no `envelopeStatus`), and falsification 13 (a device linked AFTER the
conversation existed gets `none_for_device` with a NULL ciphertext on every E2E row — never
device 1's legacy ciphertext, which is the foreign-ratchet decrypt the gate exists to prevent).

`deviceListStale` was added to the harness's `_trackedEvents`: `EventLog` records nothing that is
not listed there, so a missing entry would have made every refusal assert pass vacuously.

## 6. App-proof — two real devices

Account **193** (two live devices: 1 primary IK `BVVFJ/DuqMwR` regId 10558, 2 linked regId
13585, list v2) plus a fresh peer **297** (`t4peer0821`) on a third origin. Origins :8091
(device 1), :8093 (device 2), :8094 (peer), all serving the T4 release bundle.

One send from the peer reproduced the entire designed path live:

1. `[send] REFUSED legacy send to an enrolled party senderId=297 recipientId=193 stale=193@v2`
   — amendment (x) firing: the peer's first attempt was the legacy shape.
2. The client verified and adopted the delivered list, then resent as a fan-out:
   `[sendMessage] newMessage emitted to recipient 193`.
3. The database proves the fan-out — message 649 carries **two** envelope rows, `(193,1)` and
   `(193,2)`, with **different ciphertexts** (`3:MwgUEiEF` / `3:MwgAEiEF`), and the legacy
   column is NULL.
4. **Both devices rendered the same plaintext**, each decrypting its own envelope:
   "T4 fan-out proof: both devices should read this".

`message_envelopes` also holds the rows written by the wire runs — the table's first real write
paths, after starting empty since T1.

## 7. Traps paid this session

- **`hub jobs` status is NOT liveness.** Both dispatched writers died to the same 429, and a
  third went silent mid-stage while the broker still reported it RUNNING. The reliable test is
  the one from T3: compare the working files' mtimes against the clock (23 minutes of zero writes
  with no commit = corpse). Stand it down explicitly, verify its worktree output with full suites,
  then land it — never trust the status.
- **A foreign docker stack** (`fpcomposer-*`) held :3000/:5433. Ask before stopping someone
  else's stack; the owner cleared it.
- **After that the backend booted with `EAI_AGAIN db` and lost its host port binding.** A bare
  `docker compose restart` does not fix a stale compose network — `down` then `up` recreates it.
- **The register throttle is in-memory**, so a backend restart clears a spent 10/hr/IP budget.
  Useful when a browser proof needs a fresh account after the wire suite has run.
- **Backticks in a `git commit -m` body get shell-expanded** and silently delete words. Write the
  body to a file and use `-F`.
- **CRLF files defeat a `$`-anchored codemod** — a `sed` line-end anchor never fires after `\r`,
  which silently matched nothing across seven files.

## 8. Next

**T5** (self-sync + lost-ack + client `sendToken`) under decision-record §4 riders. It inherits a
live `sendToken` path, per-device addressing in both directions, and the own-sender guards
deliberately left untouched at `decrypt.dart:963/975/1294` and `history.dart:529` — flipping
those to origin-device scoping is T5's first job, and `frontend/CLAUDE.md` §5 is required reading
before touching the reconcile again.
