# T5 research — self-sync, lost-ack, `senderListInfo` (spec §5.4 + §5.2 layer 2)

**Date:** 2026-08-21 · **Branch:** `feat/takeover-alarm-0a` @ `88636f7` · **Status:** research complete,
**pre-code**. Compiled from 6 agents in one batch (4 librarians on primary sources, 2 read-only
scouts on our own code) plus 3 independent reviewers of the T1–T4 work this ticket builds on.

Every claim below carries its source. Where an agent could not verify something from source it is
marked UNVERIFIED and must not be relied on.

---

## 0. The headline: T5 is smaller and different than the handoff said

Two corrections that change the shape of the ticket:

1. **The send half of self-sync is ALREADY SHIPPED (T4), on both tiers.** The client already
   fans out to the sender's own other devices (`messaging_provider.send.dart:1247-1257`, excluding
   `ownDeviceId`); the server already ACCEPTS an envelope addressed to the sender's own other
   device and refuses only the origin device (`chat-message.service.ts:157-165`
   `self_envelope_for_origin_device`); delivery maps every envelope including self ones
   (`:454-472`); per-device history already serves device 2 its own real envelope (`:585-596`).
   A test already asserts it: `messaging_provider_fanout_test.dart:201-221` "own other devices get
   a self-sync envelope; the origin device never does" — green today.
   **T5 is therefore almost entirely a RECEIVE-side ticket.**

2. **The "five own-sender guards" list is INCOMPLETE — the decisive one is missing.** All five named
   sites exist verbatim at the handoff's line numbers, but they are all downstream of one master
   gate the handoff never mentions:

   ```dart
   // frontend/lib/models/message_model.dart:100-103
   bool needsDecryption(int? currentUserId) =>
       encryptedContent != null && encryptedContent!.isNotEmpty && senderId != currentUserId;
   ```

   It feeds ~12 callsites (`events.dart:77,101`; `decrypt.dart:70,228,416,512,553,881,913,930`) and
   decides whether a row is decrypted **at all**. Flipping the five downstream guards without this
   one leaves every own-other-device row filtered out before it reaches any of them — a red
   falsification-6 run with no obvious cause. Real count on the decrypt/receipt/record-consumption
   surface is **8+, not 5** (full map in §3).

Net effect today on a live two-device account: device 2 **receives** a real self-sync envelope,
routes it into the own-row reconcile branch, computes `recordKey = msg.encryptedContent ?? msg.sendToken`
= the served ciphertext, misses (the pending record lives only on device 1), and the row stays
`[encrypted]` **forever**. That is the bug T5 fixes.

---

## 1. Prior art — self-sync (`local://t5-self-sync.md`)

1. **Signal ships a `SyncMessage.Sent` "sent transcript", not the recipient's ciphertext.**
   `Signal-Desktop/protos/SignalService.proto` `SyncMessage.Sent` (549-580): `timestamp`(2),
   `destinationServiceId`(7), `message`(3), `editMessage`(10). A sibling recognises it by
   **envelope shape**, never by a `senderId == me` guess.
2. **The ORIGIN device never gets its own copy — the server excludes it.**
   `MessageController.java:239-241,402-411` detects a self-send and passes
   `syncMessageSenderDeviceId = sender.deviceId()`; `MessageSender.java:327-333,391-392` sets
   `excludedDeviceId` and filters the device set. So no echo can ever collide with the origin's
   live pending-send record. **Fireplace already matches this** (`self_envelope_for_origin_device`).
3. **Stable cross-device message identity is `(timestamp, authorServiceId)`** — a client-minted
   millisecond send timestamp plus the author account. Edits point back via
   `EditMessage.targetSentTimestamp`. Fireplace's `(senderId, originDeviceId, sendToken)` is the same
   idea with the device axis made explicit.
4. **Each sibling's ciphertext is DISTINCT** — one envelope per `destinationDeviceId`
   (`Map<Byte,Envelope> messagesByDeviceId`), each a separate pairwise Double Ratchet session
   (Double Ratchet §2.2/§3.4). A self-copy is N distinct ciphertexts, never a shared blob.
5. **A sender structurally cannot decrypt its own ciphertext** — encrypt advances the sending chain
   and discards the key; decrypt needs a receiving chain the origin never populates for its own
   output (Double Ratchet §2.2/§3.4/§3.5). This is why the plaintext pending record is mandatory.
6. **Matrix contrast:** the sender sees its own event through the room timeline and matches it by
   `transaction_id` (`unsigned.transaction_id`); if the txn id is lost the message shows twice and is
   later de-duplicated by `event_id`. That lost-txn duplicate is exactly the hazard T5 must make a
   no-op.

UNVERIFIED: the Signal client function that ingests an incoming `Sent` transcript (files moved);
the libsignal Rust paths in that report (covered instead by §2, which read them directly).

## 2. Prior art — libsignal self-session feasibility (`local://t5-self-session.md`)

The crypto-level go/no-go, read from `signalapp/libsignal` source:

- **A self-device is just another `ProtocolAddress`** — `{name: ServiceId, device_id: NonZeroU8 ∈ 1..=127}`
  (`rust/core/src/address.rs`). No protocol-level special case.
- **The identity key is per-ACCOUNT by design.** `IdentityKey::is_same_account`
  (`rust/protocol/src/identity_key.rs:76`) returns true iff the public keys are equal AND both
  addresses parse to the same ServiceId. libsignal **expects** two devices of one account to share
  one identity key — exactly fixture 193's shape (two devices, one IK). It does not break identity
  trust.
- **Two devices sharing ONE identity key CAN establish a session.** `process_prekey_bundle`
  (`rust/protocol/src/session.rs:171`) has **no branch rejecting a bundle whose identity key equals
  the local identity**; sameness is passed through as the `self_session` flag into
  `AliceSignalProtocolParameters` (`:244-250`), mirrored on the recipient side (`:150-158`).
  This was the one hard feasibility question. **Answer: yes, supported deliberately.**
- **`self_session` only relaxes forward-jump limits** (`max_jump = u32::MAX`, `ratchet.rs:29`), so a
  long-offline own device can still catch up. The ratchet is otherwise identical.
- **Decrypt is not idempotent:** `consume_message_key` removes the key; a replay raises
  `SignalProtocolError::DuplicatedMessage`, treated as terminal by `try_decrypt_from_record`.
- **Exact skipped-key bounds** (`rust/protocol/src/consts.rs:9-13`): `MAX_FORWARD_JUMPS = 25_000`,
  `MAX_MESSAGE_KEYS = 2000`, `MAX_RECEIVER_CHAINS = 5`, `ARCHIVED_STATES_MAX_LENGTH = 40`. Beyond
  that window a key is gone for good — so a very stale self-copy may be unrecoverable and must
  surface a benign state, never an alarm.
- **A sender cannot decrypt its own output, structurally:** `SenderChain::to_pb` always writes
  `message_keys: vec![]` — sending chains never cache keys.
- **Per-`(peerId, deviceId)` serialization is EXACTLY right.** `message_encrypt` does
  load → advance sender chain → `store_session` on `&mut SessionRecord` with **no internal lock**;
  one `ProtocolAddress` = one session record. Two concurrent encrypts on one session reuse a
  counter/message key and one store clobbers the other. Per-account is needlessly coarse; anything
  narrower is unsafe. Our C1 keying is confirmed correct.

## 3. Our own guard surface (scout `OwnSenderGuardScout`, verified at HEAD)

| # | Site | What it protects | T5 verdict |
|---|---|---|---|
| 0 | `models/message_model.dart:100-103` `needsDecryption` | any row with `senderId == me` is treated as already-plaintext and never decrypted | **MUST FLIP — the decisive one** |
| 1 | `decrypt.dart:668` own-message branch | re-hydrates our optimistic plaintext for own rows returned as `[encrypted]` | **MUST FLIP** (only the origin device holds that plaintext) |
| 2 | `decrypt.dart:1002` `_decryptMessageAsyncQueued` | never run the ratchet on a message we sent | **MUST FLIP** to origin-device scoping |
| 3 | `decrypt.dart:1014` `_decryptMessageAsync` | same, defence in depth at the inner entry | **MUST FLIP** |
| 4 | `decrypt.dart:1339` `_evaluateTerminalDuplicate` | own rows never enter terminal-duplicate retire logic | **FLIP** (a foreign-origin own row IS a genuine inbound envelope) |
| 5 | `history.dart:536` optimistic-replace + record consume | the `messageSent` ack replaces our optimistic bubble | **FLIP, but naturally origin-safe** — `tempId` is minted only on the sending device, so a self-sync row cannot match; keep `tempId != null` |
| 6 | `history.dart:636` **receipt emit** (`messageDelivered` + `markConversationRead`) | we never send a receipt for a message we authored | **MUST NOT FLIP — stays account-scoped.** Device-scoping this is falsification 19 (a receipt for the account's own message) |
| 7 | `events.dart:439` edit-echo `_pendingEdits` consume | our own edit echo reconciles the optimistic edit | **MUST NOT FLIP** — an edit is authored by the account |
| — | `actions.dart:43` edit eligibility | who may edit | MUST NOT FLIP (account-scoped) |
| — | `isMine` in bubbles/theme; ping sounds (`events.dart:138,147`, `decrypt.dart:629,1164`) | colour/alignment/sound only | out of scope |

**Startup hazard (new finding).** `EncryptionProvider._ownDeviceId` defaults to **1**
(`encryption_provider.dart:270`) and is corrected only when `socketReady` lands
(`connection_provider.dart:231-234`). It is never null, so a device-scoped guard cannot
null-misfire — but between connect and `ready` a real device 2 **believes it is device 1**, so any
self-sync predicate evaluated in that window mis-scopes. Prefer the server-asserted
`envelopeStatus == 'own_origin'` discriminator, or gate on `socketReady`.

**Field inventory — no new wire fields are needed.** `originDeviceId` (nullable; NULL = legacy =
device 1), `envelopeStatus` (`own_origin` | `none_for_device`), `hasNoEnvelopeForThisDevice`, and
`sendToken` all already exist on `MessageModel` and are already populated from the wire.

## 4. Prior art — lost-ack / exactly-once (`local://t5-lost-ack.md`)

| System | Idempotency key | Scope | Retention | On ambiguity |
|---|---|---|---|---|
| Matrix | client-minted `txnId` | **(endpoint path + sending DEVICE)** since MSC3970/v1.7 — Synapse `transactions.py:_get_transaction_key` returns `(path, "user", user, device_id)` | in-memory, `CLEANUP_PERIOD = 30 min` → entries live 30–60 min | exact-key lookup: one cached response or re-execute. **Failures are never cached** (`remove_from_map`), so a lost ack stays retryable |
| Signal-Server | **server**-minted `serverGuid` | store key = partition `(destinationAccountUuid, deviceId)` + sort `serverTimestamp‖serverGuid` | TTL | no client dedup at all — a retransmit becomes a duplicate row |
| XMPP | client-minted `<origin-id>` (XEP-0359), plus the XEP-0198 `h` counter | per generating entity | — | XEP-0198 §4 **admits** duplicates ("no way to prevent such a result in this protocol"); dedup by id, and §6 warns `origin-id` **is spoofable** |

**The crux: no surveyed system heuristically matches a local record to server rows.** Matrix keys
exactly; XMPP tolerates a duplicate rather than guess. Signal-Server shows the cautionary case —
server-minted identity gives no sender-side exactly-once, which is precisely why Fireplace needs a
client token.

**Recommended law for Fireplace:** client-minted token; scope per sender account **and originating
device** (Matrix's device scope); if `(senderId, originDeviceId, sendToken)` does not resolve to
**exactly one** row → **NO-OP, never consume the pending record**; bound the token index with a TTL
sweep rather than growing forever; and never let a client-minted token drive a security decision
(XEP-0359 §6).

**What we already have** (scout `SendPathScout`): `UQ_messages_sender_send_token` on
`(sender, sendToken) WHERE sendToken IS NOT NULL` (`message.entity.ts:34-37`, migration
`0015:120-122`) makes "two candidate rows" structurally impossible per sender; `findBySendToken`
(`messages.service.ts:144-152`) keys on `(sender.id, sendToken)`; `includeSendToken` is gated on
`own && isSessionOwner` (`message.mapper.ts:73-75`), so **the token never reaches a non-origin
device**.

**Consequence — the disambiguation is already structural, per device:**

| Row as seen by | `senderId` | `originDeviceId` | `sendToken` | ciphertext | `envelopeStatus` |
|---|---|---|---|---|---|
| device 1 (origin) | me | 1 | **echoed** | NULL | `own_origin` |
| device 2 (self-sync) | me | 1 | **absent** | real, device-2-addressed | none |

So device 2 **cannot** consume device 1's in-flight record (it never sees the token, and the record
store is device-local). The remaining hazard is the **inverse**: if the origin device were ever let
into the decrypt pass for its own `own_origin` row it would try to Signal-decrypt a ciphertext it
authored — impossible — and mark `[Decryption failed]`, destroying the only plaintext.
**`own_origin` → reconcile by token, never decrypt** is a load-bearing rule.

## 5. Prior art — `senderListInfo` and split-view detection (`local://t5-split-view.md`)

1. **Sesame never trusts a peer's claim about your devices** (§3.3, §6.5): the server reconciles and
   returns the signed truth; the sender re-runs a **bounded** loop. There is no in-band device claim
   in Sesame at all.
2. **Matrix draws the load-bearing line:** a device **addition** signed by the same self-signing key
   is trusted silently; only a **master/identity-key change** alerts (`end_to_end_encryption.md`,
   MSC4153). So an "older than mine" list is at most a *candidate* freeze signal, never an alarm.
3. **Rate-limit precedent is explicit:** Matrix requires "only one request to `/keys/query` in
   flight at a time for each user, by queuing additional requests" — otherwise a stale response
   clobbers a fresh one. Refresh is event-driven (`device_lists.changed`), not per-message polling.
4. **Minimum evidence for an alarm = two conflicting SIGNED views.** CONIKS proves equivocation only
   via non-repudiable signed tree roots (eprint 2014/1004). Apple's iMessage CKV states the goal as
   "detect split views … Notify users only when an unexpected security condition occurs. Warnings
   must be rare and accurate."
5. **In-band hash gossip has direct precedent:** iMessage KT gossips log hashes "in the encrypted
   part of a small percentage of messages" — exactly `senderListInfo`'s shape. MLS carries
   `tree_hash` + `confirmed_transcript_hash` in `GroupContext`, SHA-256 over a recursive
   `TreeHashInput` for the default suite (RFC 9420 §7.8/§7.9). Matrix carries **no** in-band
   device-set hash (it signs canonical JSON instead).
6. **MLS shows what a pairwise design must emulate:** membership is explicit and agreed every epoch.
   A pairwise pair has no shared transcript — that gap *is* the split view, and our DAK-signed,
   version-monotonic list is the pairwise stand-in, closed only by an independent cross-check.
7. **Own-device skew is shown as a benign "syncing" state**, never a red alarm (iMessage KT).
8. **Traps:** alarming on a bare peer claim is weaponisable (self-DoS, warning fatigue); parallel
   re-fetch races overwrite fresh data with stale; conflating benign own-skew with attack trains
   users to ignore real warnings; **first-contact TOFU is unclosable in-band** (MSC4153 security
   note) so the check must not be oversold; non-canonical hashing yields phantom mismatches
   (Matrix signs canonical JSON precisely to avoid this — our `listCanonical` is already byte-exact
   opaque base64, so hash *it*, never a re-serialization).

**Recommended shape:** `{ownVersion, ownListHash, peerVersion, peerListHash}` in the E2E plaintext,
hash = **SHA-256 over the DAK-signed `listCanonical` bytes**; compare only against your own verified
signed lists; newer-than-mine → at most ONE rate-limited re-fetch, then discard; older-than-mine →
candidate freeze, alarm only after independent confirmation against DAK-signed data; own-device skew
→ benign "syncing devices…".

## 6. Change surface T5 must touch

- `frontend/lib/models/message_model.dart` — loosen `needsDecryption` so an own row that is **not**
  this device's origin is decryptable.
- `frontend/lib/providers/messaging/messaging_provider.decrypt.dart` — split the own-row branch:
  `own_origin` → token reconcile (never decrypt); foreign-origin own row → ratchet decrypt keyed by
  `originDeviceId` (the session addressing at `:1100-1118` is already correct); assert that an
  absent/ambiguous pending match is a no-op instead of relying on it.
- `frontend/lib/providers/messaging/messaging_provider.history.dart` — make sure a self-sync row (no
  `tempId`) reaches state and is not short-circuited by the optimistic-replace path; keep the
  receipt guard at `:636` account-scoped.
- `+ senderListInfo`: `frontend/lib/utils/e2e_envelope.dart` (parse tolerates unknown keys — the
  `linkPreview` precedent), the encrypt-time writer, the receive-time escalation logic, l10n en+pl.
- **Verify-only (already correct):** `send.dart`, `chat-message.service.ts`, `messages.service.ts`,
  `message.mapper.ts`, `message.entity.ts` + migration 0015.
- **Tests:** extend `messaging_provider_fanout_test.dart` (keep the self-sync assertion green),
  `messaging_provider_envelope_status_test.dart` (+ foreign-origin own row decrypts),
  `messaging_provider_lost_ack_test.dart` (+ an own foreign-origin row does NOT consume a record;
  + the missing token-keyed round trip, see §7), `full_stack_e2e_test.dart`
  (+ device-1-sends / device-2-decrypts).
- **Doc fix found in passing:** root `CLAUDE.md` §7 documents `socketReady` as `{serverTime}` but the
  code also emits `deviceId` (`chat.gateway.ts:175`).

## 7. Pre-T5 review of T1–T4 (three independent reviewers, read-only, 2026-08-21)

All three: **no P0, no GATE FAIL.**

- **Spec conformance — PASS WITH CONCERNS.** Amendments (v), (vi), (viii), (x) FULLY landed; (ix)
  half-landed exactly as the settlement said; (vii) `senderListInfo` genuinely absent (honest
  deferral). Falsification 19 and I9 verified intact. I6 SILENCE is absent but **inert** — no
  revocation handler exists yet to produce a revoked device (T6). No scope creep found.
- **Backend invariants — PASS WITH CONCERNS**, one P3. Atomicity, the CAS, entity/index/module
  registration, `[rows, rowCount]` unpacking, column casing, JWT-sourced `deviceId`, per-device
  ciphertext isolation and the column-scoped delivery projection all verified against the live
  schema. **P3:** `SendMessageDto.envelopes` has `@ArrayMinSize(1)` but no `@ArrayMaxSize`, so
  nested validation runs on an arbitrarily long array before any refusal — bounded by the socket
  buffer, so cost hygiene rather than a correctness break.
- **Client crypto/durability — PASS WITH CONCERNS.** The lost-ack mirror holds at every site; buffer
  copies honoured at every `Curve`/`verify` callsite; `(userId, deviceId)` keying everywhere.
  - **P1 (security; fix before self-sync leans on the own list):**
    `device_list_cache.dart:122-126` `adopt()` early-returns `notEnrolled` (device 1 only) for an
    `authorization: null` answer **without consulting `_pinnedVersion[userId]`**. Enrollment is
    durable per §5.2, so enrolled → not-enrolled is never legitimate; today a forged or stale null
    silently narrows the fan-out to device 1 — and once T5 lands, silently kills self-sync. Fix:
    reject a null authorization as `version_rollback` when a pin exists.
  - **P2:** the token-keyed (fan-out) lost-ack reconcile has **no** end-to-end regression test —
    every case in `messaging_provider_lost_ack_test.dart` drives the legacy ciphertext shape. A
    precedence inversion on the fan-out branch would ship green.
  - **P3:** `_trackedEvents` (closed allow-list) + cursorless `EventLog.next` will make
    T5-added-event assertions hang or pass vacuously.

## 8. Open questions for settlement (spec §12 amendment, BEFORE code)

1. **Predicate authority.** Split the own-row branch on the server-asserted
   `envelopeStatus == 'own_origin'` or on the client-derived `originDeviceId == ownDeviceId`? They
   agree today, but a legacy row has `originDeviceId` NULL (→1) and no `envelopeStatus`, and
   `ownDeviceId` is wrong until `socketReady`. Pick ONE source of truth so no row is both
   "decryptable" and "reconcilable".
2. **Token index hardening.** Add `originDeviceId` to `UQ_messages_sender_send_token`, or document
   the client-side global-uniqueness invariant? Not required for correctness today (tokens embed the
   user id and a microsecond suffix), but the index would otherwise let a future device re-ack
   another device's row.
3. **Reinstall gap.** A device that reinstalls holds no pending record and receives no token; its
   own old rows stay `none_for_device` forever. Accept (Matrix's "sent before we joined" analogue)
   or require a cross-device backfill?
4. **`senderListInfo` shape + hash.** Confirm `{ownVersion, ownListHash, peerVersion, peerListHash}`
   with SHA-256 over `listCanonical` bytes; decide whether it rides EVERY message or a sample
   (iMessage KT gossips a small percentage).
5. **Escalation surface.** How does "syncing devices…" render, and what is the re-fetch rate limit
   (Matrix's rule is one in-flight per account, queue the rest)?
6. **Terminal-duplicate scope** (guard 4): should a foreign-origin own row be eligible for the
   retire rule, or excluded to keep the destruction-adjacent path as narrow as possible?
7. **Ordering of the P1 above:** fold the `DeviceListCache` downgrade fix into T5 stage 0 (self-sync
   depends on the own device list) or carry it as its own commit first?

## 9. Traps to carry into implementation

- Flipping the five documented guards but not `needsDecryption` = self-sync silently dead.
- Flipping `history.dart:636` = falsification 19 red (a receipt for our own message).
- Letting the origin device decrypt its own `own_origin` row = the only plaintext destroyed.
- Evaluating any device-scoped predicate before `socketReady` = device 2 acting as device 1.
- Reusing one ciphertext across devices or delivering it twice = `DuplicatedMessage`, permanently
  undecryptable.
- Skipped keys are bounded (2000 keys / 5 chains): a very stale self-copy may be unrecoverable —
  render a benign state, never an alarm.
- Alarming on a bare peer `senderListInfo` claim = weaponisable false alarm (I7).

## 10. Sources

Session-local primary-source reports (not committed):
`local://t5-self-sync.md`, `local://t5-lost-ack.md`, `local://t5-split-view.md`,
`local://t5-self-session.md`.

External primary sources cited: `signalapp/libsignal`
(`rust/protocol/src/{session,identity_key,ratchet,double_ratchet,consts}.rs`, `rust/core/src/address.rs`);
`signalapp/Signal-Server` (`MessageController.java`, `MessageSender.java`, `MessagesDynamoDb.java`);
`Signal-Desktop/protos/SignalService.proto`; Signal Double Ratchet spec §2.2/§3.4/§3.5; Sesame spec
§3.3/§6.1/§6.5; `matrix-spec` client-server API (transaction identifiers, `end_to_end_encryption.md`,
local echo) and `element-hq/synapse` `synapse/rest/client/transactions.py`; MSC3970; MSC4153;
XEP-0198 §4-5; XEP-0359 §2.2/§6; RFC 9420 §7.8/§7.9/§12.1/§12.4; CONIKS (eprint 2014/1004);
Apple iMessage Contact Key Verification.
