# Multi-device (linked devices) — design

**Status: v5 — FROZEN 2026-08-17 after THREE review rounds + a delta micro-verification (round 1
on v2; round 2 on v3 + SAS literature check; round 3 delta-scoped termination round on v4; final
micro-check on the round-3 folds returned FREEZE with zero mechanism findings). §11 owner
questions ALL ratified. Design review is CLOSED at doc level; all further review happens at phase
gates (spec-level, with code in hand — Phase 2 mandatory). NO CODE until Phase-0a dispatch.**
Research record: `.cursor/session-summaries/2026-08-17-session-multidevice-research.md` and
`.planning/multi-device/findings.md`.

---

## 1. Goal and non-goals

**Goal:** one account usable on up to 3 concurrent devices (1 primary + 2 linked) with:
- no weakening of the E2E model (server stays blind; keys never transit the server in the clear);
- device additions impossible without physical possession of the primary (kills today's
  password-only takeover AND eprint 2021/626-class server-side device injection);
- per-device Signal sessions (compromise of one device's sessions does not expose another's);
- self-sync (a message sent on device A appears on device B).

**Non-goals (explicitly out of scope):**
- PQXDH/Kyber (separate epic: Rust-FFI lib swap; never combined with this migration).
- Sealed sender, groups, iOS native app, history-transfer-on-link (Phase 4, optional, own doc).
- Remote wipe of a revoked device's local data.
- Any change to disappearing-message semantics, the reconcile protocol's fail-closed rules, or the
  plaintext-store invariants (`frontend/CLAUDE.md` §5) beyond what §5.4/§5.6/§5.7 state explicitly.

## 2. Threat model and the invariant matrix

Actors: **P** = password thief (credential only). **S** = malicious/compromised server.
**L** = compromise of a *linked* device (incl. XSS on a linked PWA, which can read that device's
web-stored keys). **Pr** = compromise of the *primary* device.

| Capability | P | S | L | P+S | L+S |
|---|---|---|---|---|---|
| Read past messages | no | no | that device only | no | that device only |
| Read future messages | **no** (today: YES) | no | that device only | no | that device + forged-list risk¹ |
| Add/replace a device (honest server) | no | n/a | **no** | n/a | n/a |
| Add a device (server colludes) | no | no² | no² | no² | **yes¹** |
| Freeze/split a peer's view of the device list | no | bounded³ | no | bounded³ | bounded³ |
| Trigger identity reset | yes, but loud + delayed (§6.2) | no | yes, loud + delayed | yes, loud + delayed | yes, loud + delayed |

¹ L+S: a linked device holds the shared identity key IK; with a colluding server it can present a
forged enrollment to *new* peers (TOFU). Existing peers detect it: they pin the DAK (§3) and the
list version, and a DAK change or version rollback renders the loud identity-changed surface.
Accepted residual risk — deep full-compromise territory.
² Device-list mutations require a DAK signature (§3). S alone lacks IK and DAK. L alone holds IK
but not DAK; both server and peers refuse IK-signed mutations by construction.
³ S can withhold a NEWER validly-signed list (freeze), which per-peer monotonicity alone cannot
detect. Bounded by the end-to-end version cross-check in §5.2: every encrypted envelope carries the
sender's view of both list versions *inside the plaintext*, so any message from any honest device
exposes the freeze to the frozen peer. S must then also block those messages entirely — degrading
to denial of service, which S can always do anyway.

**Non-negotiable invariants** (each gets a red-first test, §10):

- **I1** — The server NEVER holds a private key: not IK, not DAK, not per-device keys. Provisioning
  transports IK device-to-device encrypted under a human-verified DH secret; the server relays
  opaque bytes. An ABORTED provisioning obliges the new device to DISCARD IK and every minted key
  (§5.1) — a failed link leaves no keyed residue anywhere.
- **I2** — Every device-list mutation carries a signature by the account's **DAK**, whose private
  half exists ONLY on the current primary, in platform Keystore. The shared identity key is NEVER a
  device-list signing authority (a linked PWA holds IK in web storage; one XSS must not mint
  devices). Primary handover ROTATES the DAK (§6.3); the private half never leaves its origin
  device, and a demoted primary's DAK has no remaining authority.
- **I3** — Linking requires possession: QR scan + DH-bound SAS confirmation + explicit approve on
  the primary, AND a valid password login on the new device. Neither alone suffices. No
  password-only fallback, ever. No secret leaves the primary before the SAS is human-confirmed.
- **I4** — Identity/DAK *reset* (all devices lost) is credential-gated, slow and loud: fixed delay,
  rate-limited, every live session AND every push endpoint notified before it takes effect; cancel
  wins any race with expiry (§6.2). The recovery key (§6.2.1) shortens the delay but is NEVER
  silent: same notifications, non-zero cancel window, slow-hashed, single-use, rate-limited.
- **I5** — Fail-closed inheritance: every existing UNKNOWN-is-not-absence rule survives per-device
  (the 0.1.10 guard's tri-state, reconcile's null-answer-purges-nothing, ledger fail-open rules).
  A device-list fetch failure means "cannot send", never "send to fewer devices".
- **I6** — A revoked device stops receiving new envelopes at revocation commit, atomically with the
  signed list mutation. Its local history remains its own; **the server answers a revoked device's
  `getServedMessageIds` with SILENCE** (a missing reply purges nothing — never an empty/partial
  answer, which would read as "destroy all"). Verified consequence: the revoked device's expiry
  sweep also fails closed forever (no fresh server clock) — over-retention on a device the user
  chose to cut off, consistent with the root §7 asymmetry. Re-linking the same physical device
  under a new deviceId is safe: the local content store keys by `(uid, msgId)`, not deviceId, and
  reconcile stays per-user (I8).
- **I7** — Peers verify the device list against the IK→DAK chain, monotonic version, AND the
  end-to-end version cross-check of §5.2; the server is untrusted for list content and freshness.
  Rollback, invalid chain, or an INDEPENDENTLY VERIFIED cross-check staleness = loud
  identity-changed surface. An unverifiable peer claim alone NEVER alarms (§5.2).
- **I8** — The reconcile contract is UNTOUCHED: "served" remains row-existence + participant based
  (per user, metadata-blind — `messages.service.ts:194-243`), independent of the envelope
  dimension. Envelopes gate realtime routing and per-device delivery stamps ONLY, never reconcile,
  never history visibility of an existing row.
- **I9** — Read-based disappearing TTL starts ONLY on the recipient user's `markConversationRead`
  over the PEER's rows (today's `markConversationAsReadFromSender` semantics). It NEVER starts from
  envelope `deliveredAt`/`readAt`, and NEVER from the sender's own device reading its self-sync
  copy. The delivery projection is decoupled from expiry by construction (§4).

## 3. Keys

| Key | Curve/API | Custody | Lifetime |
|---|---|---|---|
| **IK** — account identity | Curve25519 (existing) | every device's secure storage (Keystore on Android; sealed web KV on a linked PWA) | account lifetime; reset only via §6.2 |
| **DAK** — device authorization | Curve25519 via `Curve.generateKeyPair()`; sign/verify via `Curve.calculateSignature/verifySignature` (XEdDSA, 64B, source-verified in `libsignal_protocol_dart` 0.8.2 `src/ecc/curve.dart`) | **current primary only**, `flutter_secure_storage` (Keystore). Never provisioned, never uploaded, never derived from IK, never copied — handover = rotation (§6.3) | until rotation (§6.3) or reset (§6.2) |
| per-device `registrationId`, signed prekey (id 0), OTPs 0..N | existing | that device only | per device |

**Enrollment record** (created on the primary when multi-device is first enabled):
`E = { userId, dakPub, createdAt, sig_IK(userId ‖ dakPub ‖ createdAt) }`.
Server pins `E` first-write-wins; replacing a DAK requires `sig_oldDAK(userId ‖ newDakPub ‖
createdAt')` (rotation §6.3) or reset (§6.2). Peers cache `(dakPub, listVersion)` per contact;
verification chain is *their TOFU'd IK → E → DAK → list*.

**Signed device list**: canonical bytes of
`{ userId, version (monotonic int), devices: [{deviceId, name?, platform, addedAt, revokedAt?}] }`,
signature by DAK over the canonical serialization. **Canonical-form constraints (enforced at sign
time AND re-validated at parse time):** JSON with sorted keys, no whitespace, userId and version
first; duplicate keys REJECTED; `version`/timestamps integer-only; `name` NFC-normalized,
length-capped, control-characters rejected. `listHash = SHA-256(canonical)`.
**Transport rule:** `listCanonical` travels and is stored as OPAQUE BASE64 BYTES everywhere
(`deviceListStale`, `getDeviceList`, DB column) — never a nested JSON object a transport layer
could re-serialize; hash and signature are always computed over the decoded bytes verbatim.
(Round-2 security finding 4, folded.) `name` is user-chosen, server-readable metadata — said
plainly in UI.

Library caveats honored: `calculateVrfSignature` is stubbed — never referenced; `sign`/`verifySig`
mutate passed buffers — always pass copies of retained key/signature buffers.

## 4. Data model (backend)

New/changed tables (numbered migrations, staging rehearsal mandatory — root `CLAUDE.md` §6):

- **`devices`**: `(userId, deviceId)` PK, `name`, `platform`, `isPrimary`, `addedAt`, `revokedAt`,
  `lastSeenAt`. `deviceId` per-account small int from 1 (existing accounts = device 1 implicitly,
  §8).
- **`account_authorizations`**: `userId` PK, `dakPub`, `enrollmentSig`, `listVersion`,
  `listSignature`, `listCanonical` (opaque bytes, §3), `updatedAt`.
- **`key_bundles`**: UNIQUE becomes `(userId, deviceId)`. The **identity-epoch invariant is
  re-keyed** at all three sites (`key-bundles.service.ts:60-189`): partition dimension becomes
  `(identityPublicKey, deviceId)` — purge/claim/count operate strictly within one device's
  namespace. Under shared IK the identity half only changes on reset.
- **`one_time_pre_keys`**: unique `(userId, deviceId, keyId)`; epoch tag unchanged in meaning.
- **`message_envelopes`**: `id`, `messageId` FK CASCADE, `recipientUserId`, `recipientDeviceId`,
  `ciphertext`, `deliveredAt?`, `readAt?`, `createdAt`. Envelopes are **retained**, not
  mailbox-deleted — they live exactly as long as the message row (expiry cron, delete-for-*,
  clear-history cascade). Storage ×N accepted at cap 3.
- **`messages`**: keeps metadata; gains `originDeviceId` and `sendToken` (client-generated UUID,
  §5.4; **UNIQUE per (senderId) — server rejects a duplicate token as a duplicate send**, round-2
  data-loss finding 1). Single `deliveryStatus` stays as a **projection over RECIPIENT envelopes
  ONLY** (`recipientUserId != senderId` — self-sync envelopes NEVER count, or the sender's own
  second device would fake a read receipt; round-2 coherence finding 3): delivered = first
  recipient envelope delivered; read = any recipient envelope read. The projection is written ONLY
  as a column-scoped UPDATE of `deliveryStatus`, NEVER a full-entity save — **the existing
  `MessagesService.updateDeliveryStatus` full-entity `save()` (`messages.service.ts:319-320`) is a
  named conversion target**; the mark-read path (`:568-570`) already uses a scoped update (round-2
  coherence finding 5). Legacy `encryptedContent` retained for pre-migration rows ONLY —
  legacy-client sends are converted to a device-1 envelope at ingest (§8), so new-model rows have
  exactly one storage shape; new multi-device sends write envelopes only.
- **`refresh_tokens`**: + `deviceId`, `deviceName` — the per-device session anchor; per-device
  revoke = delete that device's rows + kick its sockets. JWT payload gains `deviceId`.
- **`fcm_tokens`** / **`web_push_subscriptions`**: + `deviceId` → per-device push targeting and
  suppression.

## 5. Protocols

### 5.1 Provisioning (linking) ceremony — two-round, DH-bound SAS, secrets last

The v3 single-shot SAS (`KDF(ephPubN ‖ provisioningId)`) was cryptographically unsound: one-party
public input, ~20-bit human comparison → offline-grindable collision (Vaudenay/ZRTP literature;
confirmed independently by round-2 security review). v4 replaces it with a two-round DH-bound
ceremony. Soundness argument: the QR is an out-of-band channel for `ephPubN` (physical scan), and
the SAS is derived from the ECDH secret — an attacker substituting either ephemeral on the relayed
leg cannot COMPUTE the honest side's SAS target (it needs a private key it doesn't have), so a
short SAS cannot be ground against, and no commitment round is required. No secret leaves the
primary before the human confirms.

```mermaid
sequenceDiagram
    participant N as New device (logged in, deviceId pending)
    participant S as Server (blind relay)
    participant P as Primary (holds DAK)
    N->>N: ephemeral pair ephN
    N->>S: openProvisioning → {provisioningId (UUID, 10 min TTL)}
    N->>N: show QR {provisioningId, ephPubN}
    P->>N: user scans QR (out-of-band ephPubN)
    P->>P: ephemeral pair ephP; S_dh = DH(ephPrivP, ephPubN); SAS = HKDF(S_dh, info="fp-link-sas", provisioningId ‖ ephPubN ‖ ephPubP)
    P->>S: provisioningHello {provisioningId, ephPubP}   — NO secrets
    S->>N: provisioningHello relay
    N->>N: S_dh = DH(ephPrivN, ephPubP); display SAS (same derivation)
    Note over N,P: HUMAN compares SAS on both screens; P user approves
    P->>S: provisionDevice {provisioningId, blob = AEAD under HKDF(S_dh, info="fp-link-blob") of {IK pair, dakPub, E, assigned deviceId}, stagedMutation = {list v+1 adding deviceId, sig_DAK}}
    S->>S: verify sig_DAK vs pinned dakPub; verify v+1; STAGE mutation (not committed)
    S->>N: provisioningBlob {blob}
    N->>N: decrypt under HKDF(S_dh, info="fp-link-blob"); store IK; mint registrationId/signedPreKey/OTPs
    N->>S: provisioningComplete {provisioningId} + per-device bundle upload (tagged deviceId) — accepted ONLY from N's originating authenticated session
    S->>S: ONE transaction: commit staged mutation + devices row + activate deviceId + bundle
    S-->>P: deviceListChanged (all own sessions; peers pick it up via §5.2)
```

Rules:
- **Secrets last (I3):** the IK-bearing blob exists only AFTER the human SAS confirmation, and it
  is encrypted under the SAS-verified DH secret itself (HKDF → AEAD, using the lib's
  `calculateAgreement` + `HKDFv3` + AES-CBC/HMAC primitives — the stock `ProvisioningCipher`
  generates its own internal ephemeral, which would bypass the verified secret, so the explicit
  construction is REQUIRED).
- **Two-phase commit:** mutation STAGED at `provisionDevice`, committed only on
  `provisioningComplete`. Until completion the blob may be re-fetched against the same
  `provisioningId`; TTL expiry or a primary-side cancel discards the stage.
  `provisioningComplete` is bound to the SAME authenticated socket session that called
  `openProvisioning` — knowledge of `provisioningId` alone drives nothing (round-2 security
  finding 6).
- **Revoke preempts linking:** a `revokeDevice` mutation AUTO-CANCELS any pending stage and takes
  the version slot — a security action never waits on a stuck link. Cancel is primary-only.
- **Abort hygiene (I1, round-2 data-loss finding 2):** on TTL expiry, cancel, or
  `provisioningComplete` failure, N MUST discard IK, all minted key material, and the assigned
  deviceId — a failed link leaves N exactly as unkeyed as before it started. The server likewise
  rejects any bundle upload tagged with a never-activated deviceId.
- Concurrent link attempts: two staged mutations both at `v+1` — the second commit loses on the
  version check; primary re-signs at `v+2` and re-submits (bounded retry, then surfaced failure).
- Both ceremony sides are new clients by definition; no legacy compat needed here.

### 5.2 Send fan-out and device-list freshness (Sesame §3.3 + E2E cross-check)

Client send: `sendMessage { conversationId, meta…, senderListVersion, recipientListVersion,
sendToken, envelopes: [{userId, deviceId, ciphertext}] }` — one ciphertext per *(recipient
device)* plus one per *(sender's other devices)* (self-sync), each from its own pairwise session
(`SignalProtocolAddress(userIdStr, deviceId)` — free int, lib-verified).

Freshness is checked at TWO layers:
1. **Server-side (liveness):** stale stamps → reject `deviceListStale { userId, version,
   listCanonical (base64), listSignature, enrollment }`; client verifies the signature chain (I7),
   updates its cache, re-encrypts, resends. Retry cap 3, then a surfaced send failure — never
   silently dropping devices (I5).
2. **End-to-end (trust):** the E2E plaintext envelope gains
   `senderListInfo: {ownVersion, ownListHash, peerVersion, peerListHash}` — the sender's view of
   BOTH lists at encrypt time. Escalation discipline (round-2 security finding 3 — the field is
   attacker-controlled plaintext):
   - Sender's view OLDER than recipient's own current list → candidate freeze signal: recipient
     re-fetches its own signed list; the alarm renders ONLY after the recipient independently
     confirms the discrepancy against DAK-signed data. A bare peer claim NEVER alarms (I7).
   - Sender CLAIMS NEWER than the recipient knows → unverifiable: triggers one rate-limited
     re-fetch; if the server confirms the recipient is current, the claim is DISCARDED as noise.
     Never a standalone alarm — a lying peer gets one bounded fetch, not an alarm oracle.
   - **Self-sync envelopes** (peer == self): both halves reference the same account list; a
     legitimate link/revoke race puts own devices briefly at different versions. Bounded own-list
     skew renders as a benign "syncing devices…" state, NEVER the identity-changed surface
     (round-2 security finding 5).
   - Older clients ignore the extra field (root `CLAUDE.md` §7 envelope-compat convention).

Version match → one message row + N envelope rows in ONE transaction, then per-device delivery
(§5.3). Sessions to a newly-seen deviceId are built lazily via `fetchPreKeyBundle {userId,
deviceId}` (per-device OTP claim; `preKeysLow {remaining}` becomes per-device, routed to that
device).

### 5.3 Realtime delivery, rooms, push, history reads

- Socket auth carries `deviceId` (JWT claim); socket joins `user:<uid>` (metadata: reactions,
  delivery, list changes, deletes) **and** `device:<uid>:<did>` (ciphertext: `newMessage`,
  `messageEdited` — each device gets *its* envelope).
- `emitToNewestTab` survives, demoted to *within one web device*: tabs of a linked PWA share one
  session store, so ciphertext to a device room targets that device's newest socket (renamed
  `emitToDeviceNewestSocket`; its documented removal condition is unchanged, now per-device).
- **Per-device history read (round-2 coherence finding 2):** `getMessages`/`findByConversation`
  joins `message_envelopes` on the REQUESTING `(userId, deviceId)` and serves that device ITS
  ciphertext. Fallback order per row is DEVICE-GATED (round-3 termination finding 1 — legacy
  ciphertext is bound to the ORIGINAL device's ratchet, so serving it to any other device yields a
  terminal `[Decryption failed]` across the entire pre-link history):
  1. this device's envelope;
  2. legacy `encryptedContent` (pre-migration rows only, §4) — served ONLY to the row's session
     owner: `deviceId == 1`, or `deviceId == originDeviceId` for own rows (backfilled rows carry
     `originDeviceId` NULL = device 1). **Load-bearing invariant: deviceIds are monotonic per
     account and NEVER reused, including across a §6.2 reset** — device 1 permanently names the
     account's original device; a reused id would resurrect the foreign-ratchet decrypt this gate
     exists to prevent;
  3. every other device falls through to the explicit `envelopeStatus: "none_for_device"` marker
     (the row predates this device's link). The marker is the discriminator that lets the client
     render the honest "sent before this device was linked" placeholder instead of
     `[Decryption failed]` or a stuck "Decrypting…" (round-2 data-loss finding 4).
- Push suppression: skip push only for the device whose own socket has the conversation focused.
  Envelope `deliveredAt`/`readAt` stamped per device; wire keeps the projected single
  `deliveryStatus` (recipient-envelopes-only projection, §4).

### 5.4 Self-sync, lost-ack, and the reconcile — coexistence rules (the danger zone)

Own-sent messages: device B receives an envelope with `senderId == me` and
`originDeviceId != myDeviceId` — decrypted like any inbound message (pairwise session between own
devices), persisted normally.

**Every own-sender guard that switches from `senderId == me` to `originDeviceId == myDeviceId`**
(round-2 coherence finding 4 — fixing only one leaves self-sync dead): the live-path queue guard
(`messaging_provider.decrypt.dart:962-963`), the decrypt guard (`:975`), the third guard
(`:1290`), and the history own-message branches (`history.dart:529`, `decrypt.dart:642`). The
Phase-2 implementation checklist enumerates all five; missing one is a red falsification-6 run.

**Rules, each with a falsification test (§10):**
- **Reconcile untouched (I8).** `getServedMessageIds` stays per-user, row-existence based. The
  origin device is served for its own rows like today. A device linked AFTER a message existed
  sees the row via the `none_for_device` marker (§5.3) — an honest placeholder, NEVER a
  destruction trigger, never `[Decryption failed]`, never retired. (Round-2 data-loss review
  verified: no path through the ledger gate, terminal-duplicate retirement, or reconcile can
  destroy on this marker — there is no ciphertext and no stored plaintext to act on.)
- **Lost-ack keyed by `sendToken`, with uniqueness law (round-2 data-loss finding 1 — the token
  guards the ONLY plaintext copy):** client mints a UUID per send; server enforces per-sender
  uniqueness (duplicate token = duplicate send, rejected); the own-message reconcile branch
  matches on `(senderId, originDeviceId, sendToken)` and MUST resolve to EXACTLY ONE row — an
  ambiguous match is a no-op that NEVER consumes the pending record. Retry of the SAME send
  (same pending record, same ciphertexts) reuses its token — same row either way. An EDIT mints
  new ciphertexts but is a mutation of an already-acked row and never touches pending-send.
  Exact-ciphertext equality remains the legacy fallback for pre-migration records.
- A self-sync row must NEVER consume a pending-send record (origin-device scoping).
- The `messageSent` ack goes only to the origin device; other own devices get envelopes.
- Own-device sessions run through the same `_sessionTails` serialization, keyed
  `(peerId, deviceId)` — own devices are just another peer address to the ratchet layer.

### 5.5 Revocation

Primary-only action (DAK-signed mutation, `revokedAt` set, version+1, one transaction; preempts
any pending provisioning stage — §5.1):
- server stops routing envelopes to the device, deletes its refresh tokens + push rows, kicks its
  sockets; its still-valid access JWT gets SILENCE from `getServedMessageIds` (I6) and rejection
  from mutating handlers until natural expiry;
- peers drop the device from fan-out on the next staleness bounce (worst case one rejected send),
  and the §5.2 cross-check exposes any server attempt to keep serving the pre-revocation list;
- the revoked device's local data is NOT remotely wiped (logout semantics; non-goal, stated in UI);
- the revoked device's OTPs are purged (only that device could complete those handshakes; it is no
  longer served envelopes).

### 5.6 Disappearing messages — deliberate ruling

Row-level expiry is RETAINED: the read-based TTL starts ONLY per invariant **I9** — the recipient
user's `markConversationRead` over the PEER's rows, exactly today's
`markConversationAsReadFromSender` semantics. It never starts from envelope stamps and never from
the sender's own device reading its self-sync copy (round-2 data-loss finding 3). At the deadline
the row + ALL envelopes are destroyed — including an envelope a linked device never fetched.
**Disappear means disappear, on every device, at one deadline.** Per-envelope expiry was
considered and rejected: it would keep "disappeared" content alive on idle devices past the
deadline. Consequence, stated honestly in docs and UI: a linked device offline past the deadline
never shows that message (same behavior as Signal). Falsification 11 asserts no error artifact is
produced; client-side destruction rules (server-clock gating, root §7) are unchanged and
per-device.

### 5.7 Edit under envelopes (round-2 coherence finding 1)

Editing is sender-only, any of the sender's devices (they all hold the plaintext via self-sync),
within the existing 15-minute window checked server-side against the row. The inbound wire becomes
`editMessage { messageId, envelopes: [{userId, deviceId, ciphertext}] }` — a full re-fan: one new
ciphertext per recipient device AND per sender's other devices. The server verifies sender + window
 + device-list coverage (same staleness bounce as §5.2), then writes each device's edited
 ciphertext in one transaction — **UPSERT semantics** (round-3 termination finding 2): an existing
 `message_envelopes` row is replaced **content-only — `deliveredAt`/`readAt` stamps SURVIVE the
 replacement** (an edit is not an un-delivery; the §4 projection must never regress on edit); a
 recipient device that linked AFTER the original send (and therefore had no row,
 `none_for_device`) gets a row INSERTED and renders the edited message with its edited marker —
 the sender's client deliberately encrypted to the CURRENT device list, so the edit is delivered
 like any current send; the placeholder upgrades, never the reverse. Legacy
 `encryptedContent` is updated too while mixed-model rows exist. The server stamps `editedAt` and
 fans each device its own edited envelope via `messageEdited`. Reject paths
(`editMessageFailed`) unchanged. An edit never mints or consumes a `sendToken` (§5.4).

## 6. Registration lock and reset (Phase 0, ships before any device work)

### 6.0 Phase 0a — takeover alarm (days, no protocol change)
Promote the existing `[identity-churn]` branch (`key-bundles.service.ts:46-53`) to: durable
server-side audit row; WS + push notice to the account's other sessions/endpoints ("your security
identity was replaced from a new sign-in"); peer-visible flag corroborating the client's
`PEER_IDENTITY_CHANGED` state; **in-conversation timeline row on peer clients** (owner-ratified
2026-08-17, explicitly superseding the 2026-08-15 banner-removal ruling for this narrower
event-driven row). Wording follows the 08-16 consented-recovery framing.

### 6.1 Single-device registration lock (pre-multi-device)
`upsertKeyBundle` with a DIFFERENT `identityPublicKey` than stored requires
`sig_oldIK(newIdentityPublicKey ‖ userId ‖ serverNonce)`. Same-identity re-uploads (today's
every-connect re-upload) pass unchanged. Genuine loss → §6.2.
**Nonce spec:** CSPRNG-generated (unpredictable, never counter/timestamp), single-use, TTL ≤ 5 min,
bound to the issuing authenticated socket session. Scope honesty: defends against **P** under an
HONEST server; a colluding **S** can issue chosen nonces — that threat is handled by the peer-side
chain (I7), not by §6.1.

### 6.2 Reset ceremony (all devices / identity lost)
Credential login → `resetIdentityRequest` → server starts a **72 h** timer, immediately notifying
every live session AND every registered push endpoint (FCM + Web Push; this app has no email —
push is the only offline channel, which is WHY the delay is 72 h and not 24). Any session can
CANCEL with one tap (no key required). Peers' conversations are marked pending-reset.
Hardening:
- **Rate limit**: one pending request per account; a new request while one is pending is a no-op
  returning the existing deadline; after a cancel, cooldown 24 h before the next request.
- **Cancel/expiry serialization**: expiry-commit runs in one transaction that re-checks
  not-cancelled; states are terminal (`completed` / `cancelled`) — a late cancel after commit is a
  no-op, never an identity rollback; a cancel that wins the race aborts the commit.
On expiry the server accepts a fresh IK + fresh enrollment; peers get the loud identity-changed
surface.

#### 6.2.1 Recovery key (owner-ratified for 0b; spec per round-2 security finding 2)
Generated client-side on demand: **12-word BIP39-style phrase from ≥128 bits CSPRNG**, shown once,
never stored on-device or transmitted except as a verifier. Server stores an **Argon2id** hash
(memory-hard parameters pinned at implementation; NEVER a fast hash — a DB dump must not make the
phrase brute-forceable). Semantics:
- **Shortens, never silences:** presenting the phrase reduces the reset delay from 72 h to a
  **1 h cancel window** with the SAME notifications to every session and push endpoint (I4). There
  is no zero-delay path — a stolen phrase still rings every bell and leaves an hour to cancel.
- **Single-use:** invalidated on use AND on any completed reset; a new phrase must be generated
  afterward.
- **Online guessing bounded:** attempts rate-limited with lockout/cooldown per account.
- Users without a phrase: exactly the 72 h path, unchanged.

### 6.3 Primary migration (planned handover) — ROTATION, never copy
New primary candidate generates a fresh **DAK′** in its own Keystore; old primary signs the
replacement enrollment `E′ = sig_oldDAK(userId ‖ dakPub′ ‖ createdAt′)` after the same QR + SAS
ceremony as §5.1; server pins `E′`; peers re-pin on next fetch via the E→E′ chain (old DAK
authority dies at that instant); a DAK′-signed mutation flips `isPrimary`. The DAK private half
never leaves the device that minted it, ever. Old primary lost → reset §6.2 (the DAK is gone —
that is the designed outcome).

## 7. Wire-contract deltas (root `CLAUDE.md` §7 — every line re-ratified at Phase 2 review)

| Surface | Today | After |
|---|---|---|
| `sendMessage` | one `encryptedContent` | `envelopes[]` + `sendToken` (unique per sender) + two list-version stamps; reject path `deviceListStale` (listCanonical as base64) |
| `editMessage` | one new `encryptedContent` | `envelopes[]` full re-fan; per-device envelope-row replacement; window/sender checks unchanged (§5.7) |
| E2E plaintext envelope | `{content, messageType?, media…}` | + `senderListInfo {ownVersion, ownListHash, peerVersion, peerListHash}` (older clients ignore; escalation discipline §5.2) |
| `newMessage` / `messageEdited` | newest tab of user | device room, newest socket within device; payload + `originDeviceId` |
| `getMessages` history rows | `encryptedContent` echo | requesting device's envelope ciphertext → legacy fallback GATED to the session-owner device → `envelopeStatus: "none_for_device"` marker (§5.3); own rows + `originDeviceId`, `sendToken` |
| `uploadKeyBundle` / `fetchPreKeyBundle` / `uploadOneTimePreKeys` / `preKeysLow` / `checkOwnKeyBundle` | per user | per `(user, device)`; bundle mutation rules of §6.1; uploads for never-activated deviceIds rejected (§5.1) |
| `messageDelivered` / read events | per message | unchanged shape; server projects from RECIPIENT envelopes only, column-scoped UPDATE (§4) |
| `getServedMessageIds` | per user, row-existence | **UNCHANGED (I8)**; SILENCE to revoked devices (I6) |
| NEW | — | `openProvisioning`, `provisioningHello`, `provisionDevice`, `provisioningBlob`, `provisioningComplete` (session-bound), `deviceListChanged`, `getDeviceList`, `revokeDevice` (preempts stages), `resetIdentityRequest/Cancel` |
| `socketReady`, `getServerTime`, delete/clear/unfriend, reactions | per user | unchanged (delete fan-out cascades envelopes) |

## 8. Compatibility and rollout

- Existing accounts become `devices(userId, 1, isPrimary=true)` implicitly (migration backfill). No
  DAK until the user enables linking; until then §6.1 governs.
- **Only a Keystore-capable device may become primary** (I2) — in practice the Android APK. A
  PWA-only account (today's iOS users) stays single-device until an iOS app exists; the web client
  can be a *linked* device only. Stated to the user at enable time.
- **Reconcile safety across the mixed model (I8):** "served" is row-existence based for every row
  shape — pre-migration rows, legacy-client sends (stored as a device-1 envelope), and new
  envelope-only rows reconcile identically. No first-launch mass-purge shape exists by
  construction; falsification 13 pins it.
- Legacy client → new server: single-ciphertext sends accepted, stored as a device-1 envelope.
  Window kept small by rollout ORDER: server first (accepts both), clients next (send envelopes),
  linking UI enabled LAST, gated on min-client-version per account.
- New client → old server: capability-probed (no `getDeviceList` answer = legacy server); client
  stays single-device, fail-closed.
- **Phase-1 migration transactionality (round-2 data-loss finding 5):** the schema+backfill
  migration runs as ONE Postgres transaction with PLAIN (non-CONCURRENTLY) index creation — the
  runner's abort-on-boot then guarantees clean rollback and idempotent re-run; table sizes here do
  not justify `CONCURRENTLY`'s non-transactional risk (an INVALID index blocking bundle upserts =
  key-delivery outage).
- e2e-wire harness grows the two-devices-one-account suite BEFORE Phase 1 merges (§10). Staging
  dress rehearsal for every schema phase (root §6).

## 9. Phase plan (each phase independently shippable, reviewed, and behind the previous)

| Phase | Content | Ships value alone? | Acceptance |
|---|---|---|---|
| **0a** | churn alarm: audit row + session/push notify + peer timeline row | YES — takeover detection | live-fire: bundle replace on a test account alerts second session + peer within 5 s |
| **0b** | registration lock §6.1 + reset ceremony §6.2 + recovery key §6.2.1 | YES — takeover prevention | red-first: password-only bundle replace rejected; reset honors 72 h/rate limit/serialization; recovery path slow-hashed, single-use, still-loud (falsification 21) |
| **1** | schema: `devices`, `(userId,deviceId)` bundles/OTPs, re-keyed 3-site epoch, JWT `deviceId`, refresh/push device columns, `originDeviceId`+`sendToken` (unique); single-transaction migration | invisible; unblocks all | full suites + wire harness green single-device; falsifications 1, 13 |
| **2** | provisioning §5.1, DAK + signed list + cross-check §5.2, envelopes + history reads §5.3, self-sync §5.4, revocation §5.5, edit re-fan §5.7 | the feature | two-device harness: link → both receive → self-sync → edit re-fan → revoke → stale bounce; ALL §10 falsifications green; own Phase-2 spec review first |
| **3** | device management UI (list, rename, revoke, last-seen), migration comms | usability | device-proven on owner's hardware |
| **4** | history-on-link via sealed-store archive (own design doc) | optional | — |

## 10. Falsification test plan (fail-before, then fix — repo tradition)

1. Two devices upload OTPs keyId 0..99 → OLD schema: device B overwrites device A's rows; peer
   draws A's slot → bad MAC (red). New schema: no collision (green).
2. Device-list mutation signed by **IK** (not DAK) → server rejects; peer client rejects.
3. Unsigned / wrong-version / replayed mutation → rejected; version rollback at a peer → loud flag.
4. `deviceListStale` answer with an INVALID signature chain → client refuses the list and fails the
   send (I7 — never the server's bare word).
5. Send addressed to a stale list → rejected atomically; zero envelopes written.
6. Self-sync: EVERY own-sender guard (`decrypt.dart:962, :975, :1290`, `history.dart:529`,
   `decrypt.dart:642`) switched to origin-device scoping — a self-sync row decrypts AND must not
   consume a pending-send record; red if any single guard is missed.
7. Concurrent send + revoke: revoked device receives no envelope for a message committed after the
   revocation transaction.
8. Provisioning blob replayed to a different ephemeral key → undecryptable; expired TTL → rejected;
   `provisioningComplete` one-shot AND rejected from any session other than the opener's.
9. Fail-closed inheritance: device-list fetch timeout on send → send FAILS; per-device
   `checkOwnKeyBundle` UNKNOWN → no key generation (0.1.10 invariant).
10. Reset: cancel halts; cancel racing expiry-commit serialized (terminal states); repeated
    requests rate-limited; peers never see identity-changed on a cancelled reset.
11. Expiry: at deadline row + ALL envelopes destroyed; a device that never fetched its envelope
    shows NO error artifact (row absent, §5.6); devices that decrypted destroy plaintext per
    existing clock rules.
12. Per-device epoch: post-reset, all three re-keyed sites purge/claim/count strictly within
    `(identity, deviceId)`.
13. **Reconcile mass-purge guard (I8):** origin device's own new-model sends, pre-migration rows,
    and legacy-client rows ALL reconcile as served; a revoked device's reconcile gets SILENCE and
    purges nothing; a `none_for_device` row is never a destruction trigger; **a linked non-owner
    device on a legacy row gets the marker, never the legacy ciphertext — it must NOT attempt (and
    terminally fail) a foreign-session decrypt; the session OWNER is positively served and
    decrypts its legacy row; after revoke/re-link leaves the account with no device 1, EVERY
    device gets the marker** (round-3 finding 1/4 + micro-check).
14. **Lost-ack via `sendToken`:** drop the ack → recovery by token match, read-back verified.
    COLLISION case: a duplicate token is rejected server-side; an artificially ambiguous match is
    a no-op that does NOT consume the pending record (round-2 data-loss finding 1).
15. **SAS grinding (rewritten):** an adversary substituting an ephemeral on the relayed leg cannot
    produce a COLLIDING SAS — the test derives both honest SAS values and asserts the adversary,
    holding only public transcript values plus its own private keys, cannot compute either target
    (DH-bound SAS; not the v3 naive-swap test).
16. **Split-view/freeze:** server serves peer A a frozen validly-signed old list (v3) after B
    revoked a device (v5) → first message from any of B's devices exposes v5 via `senderListInfo`;
    A re-fetches, independently confirms, alarms. Red without the E2E cross-check.
17. **DAK rotation:** after §6.3 handover, a mutation signed by the OLD DAK → rejected by server
    AND peers.
18. **Two-phase provisioning:** kill N between blob and `provisioningComplete` → no device row, no
    list mutation, blob re-fetchable until TTL; AND **N discards IK + minted keys + deviceId on
    abort** — post-abort N's keystore is empty and its bundle upload is rejected (I1).
19. **Projection safety:** delivery projection changes ONLY `deliveryStatus` via scoped UPDATE
    (incl. the converted `updateDeliveryStatus`); `expiresAt`/`disappearAfterSeconds`
    byte-identical; **self-sync envelopes never flip the projection** (a sender's second device
    reading its copy produces no DELIVERED/READ receipt); **read-TTL never starts from envelope
    stamps or self-sync reads (I9)**.
20. **Concurrent double-link:** two staged mutations at v+1 → second rejected; primary re-signs at
    v+2; exactly one device added per ceremony. Revoke PREEMPTS a pending stage.
21. **Recovery key:** verifier is Argon2id (fast-hash red test); phrase single-use; attempts
    rate-limited; the shortened path still notifies every session + push endpoint and honors the
    1 h cancel window.
22. **False-alarm discipline:** a malicious peer sending bogus `senderListInfo` (older AND newer
    claims) produces at most one rate-limited re-fetch and NO alarm when the server's signed list
    confirms the recipient is current; own-device bounded skew renders "syncing devices", never
    identity-changed.
23. **Canonical bytes:** `listCanonical` survives transport byte-exact (re-serialization must not
    change `listHash`); duplicate-key / ambiguous canonical bytes rejected at parse.
24. **Edit re-fan (§5.7):** an edit UPSERTs EVERY current device's envelope in one transaction; a
    device offline during the edit receives the edited ciphertext on next history read; **a device
    that linked AFTER the original send gets an INSERTED envelope and upgrades its placeholder to
    the edited message; replacing an already-delivered/read envelope preserves its
    `deliveredAt`/`readAt` stamps — the projection never regresses on edit** (round-3 finding 2/4
    + micro-check); edit from a non-origin own device succeeds;
    `editMessageFailed` paths unchanged; no `sendToken` minted.

## 11. Open questions (owner) — ALL RATIFIED 2026-08-17

1. In-conversation identity-changed timeline row — **YES** (supersedes the 2026-08-15
   banner-removal ruling for this narrower event-driven row; 0a ships it).
2. Recovery key — **YES, in 0b** (spec §6.2.1).
3. Device cap 3 — **CONFIRMED.**
4. Reset delay 72 h — **CONFIRMED.**
5. iOS-PWA users cannot be primaries until an iOS app exists — **CONFIRMED.**
6. Disappear-at-one-deadline (§5.6) — **CONFIRMED.**

## 12. Review record

- **Round 1 (2026-08-17, on v2):**
  - Data-loss review (reviewer subagent): REVISE — 6 findings folded into v3 (I8 origin, SILENCE
    rule, sendToken concept, column-scoped projection, §5.6 ruling, mixed-model reconcile).
  - Security review (reviewer subagent; first spawn refused by a content filter, re-dispatched
    defensively framed): SHIP-WITH-FIXES — 6 findings folded into v3 (SAS concept, E2E list
    cross-check, DAK rotation, two-phase commit, reset hardening, nonce spec).
- **Round 2 (2026-08-17, on v3 — three fresh reviewers + independent SAS literature check):**
  - Coherence + feasibility review: REVISE — 5 findings, all folded into v4: edit-under-envelopes
    was unspecified (§5.7 + falsification 24); per-device history read path missing (§5.3 +
    `none_for_device` marker); projection counted self-sync envelopes → false read receipts
    (recipient-only rule, §4); only 1 of 5 own-sender guards named (§5.4 enumeration +
    falsification 6); existing `updateDeliveryStatus` full-entity save named as conversion target.
    Also re-verified v3's code claims against source — all accurate.
  - Security review: SHIP-WITH-FIXES leaning REVISE — 6 findings, all folded: **v3's SAS was
    offline-grindable** (single-party public input; independently confirmed against
    Vaudenay/ZRTP literature) → two-round DH-bound SAS with secrets-last ordering (§5.1 +
    falsification 15 rewritten); recovery key was adopted but unspecified → §6.2.1 (Argon2id,
    single-use, still-loud, 1 h window; falsification 21); `senderListInfo` false-alarm/claims-
    newer discipline (§5.2 + falsification 22); `listCanonical` byte-exact transport + canonical
    constraints (§3 + falsification 23); self-sync listInfo skew (§5.2); revoke-preempts-stage +
    session-bound `provisioningComplete` (§5.1/§5.5 + falsifications 8, 20).
  - Data-loss review (first spawn failed before emitting; re-run): SHIP-WITH-FIXES — 5 findings,
    all folded: sendToken uniqueness/ambiguity law (P1 — sole-plaintext-copy misbinding; §4/§5.4 +
    falsification 14); abort-discard of IK on failed provisioning (I1/§5.1 + falsification 18);
    I9 read-TTL start conditions (§5.6 + falsification 19); `none_for_device` discriminator
    (§5.3); Phase-1 single-transaction migration, no `CONCURRENTLY` (§8). Verified clean: SILENCE
    fail-closed semantics; re-link of same physical device.
- **Round 3 (2026-08-17, on v4 — delta-scoped TERMINATION round: §5.1/§5.7/§6.2.1/I9/§5.3 marker
  only; stopping rule = zero mechanism findings ⇒ freeze):** DO-NOT-FREEZE — 2 MECHANISM + 1
  SPEC-WORDING + 1 TEST-GAP, all folded same day: (MECH) legacy `encryptedContent` fallback
  preceded `none_for_device` unconditionally, so a linked device would terminally
  `[Decryption failed]` its entire pre-link history → fallback now DEVICE-GATED to the session
  owner (§5.3, falsification 13 extended); (MECH) edit re-fan was ambiguous for a device linked
  after the send → UPSERT semantics, placeholder upgrades to the edited message (§5.7,
  falsification 24 extended); (WORDING) distinct HKDF info labels `fp-link-sas` / `fp-link-blob`
  for domain separation (§5.1); (TEST-GAP) both mechanism cases added to the falsification plan.
  Round 3 also verified: the two-round DH-bound SAS is sound incl. the blind-approve case (blob
  stays encrypted to the authentic ephPubN), and the 1 h recovery window is consistent with I4.
- **Micro-verification (2026-08-17, on the two round-3 folds only): FREEZE — zero MECHANISM
  findings.** Verified the device-gated fallback resolves every §8 mixed-model case (incl.
  reset/re-link with no device 1 → marker everywhere) and UPSERT edit is consistent with §5.2/§4/
  I8/I9. Four non-blocking items folded same day: deviceIds-never-reused invariant stated at the
  §5.3 gate; legacy-client sends pinned to device-1-envelope-at-ingest (dead branch removed,
  §4/§8 wording unified); edit UPSERT preserves delivery stamps (§5.7); falsifications 13/24
  extended (positive owner-serve, no-device-1 case, stamp preservation). **Doc frozen at v5.**
- **Owner ratification: §11 items 1–6 ALL CONFIRMED 2026-08-17.**
- **Amendment 2026-08-19 (owner-ratified decision record; doc remains frozen — this adds
  mechanism to an existing invariant, changes no protocol):** the §5.3 deviceIds-never-reused
  invariant is implemented by a **per-account allocator column `users.nextDeviceId`**
  (migration `0016`, `int`, default 2; allocation = one atomic
  `UPDATE users SET "nextDeviceId" = "nextDeviceId" + 1 WHERE id = $1 RETURNING …`).
  Deriving ids from `MAX(deviceId)+1` over `devices` is REJECTED: it silently converts a row-
  retention convention into a cryptographic invariant (any future purge of a `devices` row
  re-enables reuse). Grounded in prior-art research
  (`docs/plans/2026-08-19-multi-device-prior-art-research.md` §2): Signal's lowest-free reuse is
  survivable only via per-device registrationId disambiguation + total per-id purge on relink +
  a stale-session bounce, none of which exist here, and §5.3's device-gated legacy fallback makes
  a reused id actively dangerous; Matrix (Synapse #17375) documents reuse reattaching stale
  id-keyed attestations; WhatsApp/MLS allocate monotonically.
- **Amendment 2026-08-19 (§6.2 cooldown carve-out; owner-ratified):** the 24 h post-cancel
  cooldown is VOID if the account's password changed after the cancel: the cooldown predicate
  additionally requires `(u."passwordChangedAt" IS NULL OR r."cancelledAt" > u."passwordChangedAt")`.
  Rationale: the cooldown refusal's own copy directs a user whose ceremony was cancelled by an
  intruder to change their password; once they have (which revokes every refresh token and
  invalidates every prior JWT), the attacker-authored cancel must not keep the owner locked out
  of starting a legitimate ceremony. Deliberately narrow: a pending ceremony is NEVER cancelled
  by a password change (rows carry no requester attribution, so cancelling could discard the
  owner's own in-flight 72 h wait), and a cooldown armed AFTER the password change still binds.
  A cooldown refusal now logs a `warn` (previously the branch logged nothing).
- **Phase 2 Stage 0 review (2026-08-19, three independent reviewers: coherence + §7
  re-ratification / protection / data-durability): PASS-WITH-AMENDMENTS.** Every §7 delta
  re-ratified against the landed handlers; §8 compat re-verified under the landed OTP gate
  ordering; the DH-bound §5.1 SAS CONFIRMED to subsume an m.sas.v1-style commitment round
  (no /prototype needed for security — the argument rests on `ephPubN` being QR-only, see
  amendment c); the cooldown carve-out CONFIRMED to grant an attacker nothing new. Full
  finding-to-ticket map: `docs/plans/2026-08-19-phase2-stage0-decision-record.md`. The
  following NORMATIVE amendments bind Phase 2 (doc remains frozen; amendments complete
  mechanisms, none contradicts a frozen ruling):
  - **(a) §5.1 allocator ordering + idempotency.** The SERVER runs the `nextDeviceId`
    allocator exactly ONCE per `provisioningId` (memoized on the stage, allocated at
    `openProvisioning`) and delivers the assigned id to the primary BEFORE the primary signs
    `provisionDevice` — as drawn, the primary had no way to learn the id it must sign. The
    allocated id is the PRE-increment value (`RETURNING "nextDeviceId" - 1`). A duplicated or
    retried `provisionDevice` re-uses the memoized id, never re-allocates.
    `provisioningComplete` consumes the stage via an atomic compare-and-set inside the ONE
    commit transaction (two concurrent duplicates commit exactly one device row) and RETIRES
    the `provisioningId` (no blob refetch after commit). An aborted ceremony does NOT
    decrement the counter: gaps in the id space are expected and safe — the invariant is
    monotonic-never-reused, not dense.
  - **(b) §5.1 session rebind.** At `provisioningComplete` the server re-issues N's access +
    refresh tokens BOUND to the assigned deviceId (`refresh_tokens.device_id`,
    `createToken(userId, deviceId)` plumbing already landed in Phase 1); N MUST NOT upload key
    material until its socket is authenticated under that id (every per-device wire path keys
    off the JWT deviceId on the socket — a bundle uploaded before rebind would land on
    device 1 and overwrite the primary's). `uploadKeyBundle`/`uploadOneTimePreKeys` for a
    never-activated deviceId are rejected (§7 row already says so; this names it a T3
    deliverable — today `DevicesService.touch` auto-inserts any presented id).
  - **(c) §5.1 ephPubN is QR-only.** `ephPubN` MUST NEVER transit the server: not echoed in
    the `openProvisioning` response, not in any relayed frame, not logged. The
    no-commitment-round SAS soundness argument rests on the QR channel giving BOTH
    authenticity AND confidentiality of `ephPubN`; a leak reopens the offline grind and would
    force an m.sas.v1-style commitment round. `provisioningHello` pins the FIRST `ephPubP`
    received (later hellos for the same stage rejected) and is accepted only from an
    authenticated session of the account.
  - **(d) Signature domain separation (§3/§6.1).** Every NEW signature construction carries an
    explicit ASCII context prefix whose first byte ≠ 0x05, keeping it provably disjoint from
    the FROZEN §6.1 registration-lock layout (`newIK(33, leading 0x05) ‖ utf8(userId) ‖ nonce`,
    which stays byte-exact as landed): enrollment `E` signs
    `"fp-enroll-v1\0" ‖ userId ‖ dakPub ‖ createdAt` under IK; the signed device list signs
    `"fp-list-v1\0" ‖ listCanonical` under DAK; DAK rotation signs
    `"fp-dak-rotate-v1\0" ‖ …` under the old DAK. Rationale: enrollment and §6.1 share sig_IK,
    list and rotation share sig_DAK — without contexts, a signature minted for one
    construction could reinterpret as another (the Matrix CVE-2022-39250 class). NEW
    falsification 25: a signature minted for any one construction is REJECTED by every other
    construction's verifier.
  - **(e) §5.5 accept-side revocation.** Revocation is bidirectional: at decrypt time a peer
    (and an own device, for self-sync envelopes) MUST verify the inbound envelope's
    `originDeviceId` is present-and-not-revoked in the CURRENT DAK-signed device list and
    FAIL CLOSED on absent/revoked; the revoked device's inbound pairwise session state is
    dropped on the next staleness bounce. Falsification 7 extended: a message SENT by a
    revoked device after revocation is refused at receive time, not just unrouted.
  - **(f) §6.2 reset × device roster.** A completed reset (i) allocates the recovering
    device's id from `users.nextDeviceId` — it NEVER re-mints device 1 (a fresh IK under a
    reused id 1 would be positively served the old device 1's legacy ciphertext by the §5.3
    fallback — the exact foreign-ratchet decrypt L269-272 forbids; post-reset pre-reset
    history is `none_for_device` markers everywhere, per falsification 13's no-device-1
    case); (ii) marks every surviving `devices` row revoked so the fresh device is the only
    live one; (iii) replaces `account_authorizations` with the fresh enrollment, the list
    version CONTINUING monotonically (never restarting at 1); (iv) leaves `users.nextDeviceId`
    untouched. The `purgeSupersededDevices` widening that implements (ii)/(iii) belongs to
    T6 (it is a device-list mutation), blocked on T1's columns — do NOT widen it inside T1.
  - **(g) Migration `0016` determinism.** `message_envelopes` starts EMPTY — NO backfill of
    pre-migration rows (they are served by the §5.3 device-gated legacy fallback; a backfilled
    device-1 envelope would change which device fallback order 1 serves).
    `account_authorizations` is NOT backfilled — rows appear lazily at enrollment,
    first-write-wins. `message_envelopes.messageId` FK is `ON DELETE CASCADE` — this cascade
    is the SOLE mechanism destroying never-fetched envelopes at the §5.6 deadline (every
    landed destruction path is a DB DELETE on `messages`); `(recipientUserId,
    recipientDeviceId)` carries NO FK to `devices` (envelopes outlive device-row lifecycle).
    Single transaction, plain indexes, no `CONCURRENTLY` (§8), like `0015`.
  - **(h) List freshness TTL: DEFERRED past Phase 2** (recorded so it is not silently
    forgotten). A WhatsApp-style signed-list TTL only bounds a silent server-freeze window
    while no honest message flows; §5.2's cross-check + I7 already collapse that window to
    the first honest message, and sustaining a freeze degrades to plain DoS. At the ratified
    cap-3 scale, version-stamp divergence detection suffices.
- **Amendment 2026-08-20 (T3 pre-implementation settlement, per the Stage-0 "settle before
  code" rule; doc remains frozen — these pin byte layouts and transport for mechanisms §5.1
  already mandates, changing no protocol):**
  - **(i) OOB payload + manual-code equivalence.** The §5.1 QR payload is the exact ASCII
    string `fp-link.v1.<provisioningId>.<base64url(ephPubN), no padding>.<platform>` (the
    trailing segment is N's self-reported platform label, ≤32 chars, informational metadata
    for the signed list entry). N renders it BOTH as a QR code and as a copyable text code;
    the primary MAY ingest it by camera scan or by manual paste — both are the same
    out-of-band channel (N's screen → human → primary), preserving amendment (c)'s
    authenticity AND confidentiality of `ephPubN`, which still never transits the server.
    T3 ships the manual path (required; it is also the only app-provable path on two web
    origins); camera scanning is Phase 3 UI. The new device's list entry is written with
    this platform label and NO `name` — user-chosen names arrive with the Phase 3 rename UI
    (which is where the client-side NFC-normalization rider lands, since T3 writes no name).
  - **(ii) SAS + blob derivations (byte-exact).** Ephemerals are Curve25519 pairs
    (`Curve.generateKeyPair()`); public keys travel in the 33-byte type-prefixed libsignal
    encoding everywhere (QR and `provisioningHello`). `S_dh =
    Curve.calculateAgreement(theirEphPub, ownEphPriv)` (32 B).
    `transcript = utf8(provisioningId) ‖ ephPubN(33) ‖ ephPubP(33)`.
    SAS bytes = `HKDF(ikm = S_dh, info = utf8("fp-link-sas") ‖ transcript, len = 32)`;
    the human code is the first 4 SAS bytes read as a big-endian uint32,
    mod 10^6, zero-padded to 6 decimal digits, displayed as two groups of three (`XXX XXX`
    — ~20-bit comparison, §5.1). Blob keys = `HKDF(ikm = S_dh, info =
    utf8("fp-link-blob") ‖ transcript, len = 64)`: bytes 0–31 = AES-256-CBC key, bytes
    32–63 = HMAC-SHA-256 key. Blob = `0x01 ‖ IV(16) ‖ AES-CBC ciphertext ‖
    HMAC(macKey, 0x01 ‖ IV ‖ ciphertext)(32)` — encrypt-then-MAC, MAC verified in constant
    time BEFORE any decrypt. Blob plaintext is UTF-8 JSON `{userId, deviceId, ikPub(b64),
    ikPriv(b64), dakPub(b64), enrollmentCreatedAt, enrollmentSig(b64)}`. The two HKDF info
    labels are distinct from each other (round-3 domain-separation ruling) and disjoint
    from every (d) signature context by construction (KDF inputs, not signature messages;
    first byte `f` ≠ 0x05 regardless).
    HKDF here is RFC-5869 HKDF-SHA256 with `salt = 32 zero bytes`, implemented locally
    over `package:crypto` (byte-identical to libsignal's HKDFv3 with null salt — that
    class is NOT exported from the `libsignal_protocol_dart` 0.8.2 barrel, and a `src/`
    implementation import is forbidden).
  - **(iii) Rebind delivery.** The (b) re-issued access + refresh tokens travel in the
    `provisioningCompleted` success answer on N's opener socket — TLS-protected and
    authenticated, the same trust surface as login's answer. N then disconnects, reconnects
    under the deviceId-bound access token, and only THEN uploads its per-device bundle/OTPs.
  - **(iv) Stage residency.** The provisioning stage (memoized deviceId, pinned `ephPubP`,
    staged blob + list mutation, 10-min TTL, consumed flag) lives in server-process memory
    keyed by `provisioningId` and bound to the opener socket — the durable §4 data model
    deliberately has NO stage table, because §5.1 already binds the stage to a socket
    session that cannot outlive the process. A backend restart drops every pending stage,
    indistinguishable from TTL expiry and handled by I1 abort hygiene; nothing durable
    leaks (counter gaps are safe per (a)).
- **Amendment 2026-08-20 (T4 pre-implementation settlement, per the Stage-0 "settle before
  code" rule; doc remains frozen — these pin wire shapes, ingest ordering and marker
  vocabulary for mechanisms §5.2/§5.3 already mandate, changing no protocol). Grounded in
  `docs/plans/2026-08-20-t4-envelope-fanout-research.md` (three codebase scouts + two
  primary-source librarians):**
  - **(v) Send DTO growth + legacy normalization AT INGEST.** `SendMessageDto` grows three
    OPTIONAL fields: `envelopes: [{userId, deviceId, ciphertext}]` (non-empty when present;
    each ciphertext individually bound by the existing 65536 limit), `senderListVersion`,
    `recipientListVersion`. A send is NEW-MODEL iff `envelopes` is present and non-empty,
    else LEGACY. Before any persistence a legacy send carrying `encryptedContent` is
    NORMALIZED into the one-element list `[{userId: recipientId, deviceId: 1, ciphertext:
    encryptedContent}]`, so exactly ONE downstream write path exists (Signal-Server keeps a
    single normalized `messagesByDeviceId` map regardless of count —
    `push/MessageSender.java`); a send carrying neither ciphertext (PING and today's
    ciphertext-less shapes) writes NO envelope and keeps today's behavior. NEW-MODEL rows
    NEVER write `messages.encryptedContent` — it stays NULL, retained per §4 for
    pre-migration rows only. Exactly one envelope per `(userId, deviceId)`: a duplicate pair
    is REFUSED (`duplicate_envelope_device`), mirroring Signal-Server's
    `IncomingMessageList.isNotDuplicateRecipients()` (last-wins would brick a device's
    ratchet). An envelope addressed to a recipient device that is not live
    (`DevicesService.isActive`) is REFUSED (`unknown_recipient_device`) — fail-closed; the
    full falsification-7 revocation case remains T6. A self-sync envelope addressed to the
    ORIGIN device itself is REFUSED (`self_envelope_for_origin_device`). Envelope COVERAGE is
    not otherwise server-enforced: the server cannot know which devices the client could
    build sessions to, so I5's never-silently-drop-a-device duty stays with the client.
    Version cross-check applies per party ONLY when that party has an
    `account_authorizations` row: an enrolled party's stamp MUST equal the stored
    `listVersion` (absent stamp counts as mismatch); a non-enrolled party is single-device by
    construction (rows ≥ 2 are minted solely by the provisioning commit) and carries no
    stamp. Legacy normalized sends carry no stamps and bypass the cross-check entirely — the
    §8 rollout window, whose cost is that a legacy client reaches device 1 only.
  - **(vi) `deviceListStale` refusal payload.** The stale-send refusal is a response-event in
    house style (`{success:false, error}` per `chat-device-list.service.ts`, NOT the send
    path's bare `error` emit), emitted to the CALLER socket only:
    `deviceListStale {success:false, error:"device_list_stale", tempId?, lists:[{userId,
    version, listCanonical(base64), listSignature, enrollment:{dakPub, enrollmentSig,
    enrollmentCreatedAt}}]}`. §5.2's singular payload becomes an ENTRY in `lists`, one per
    party whose stamp mismatched (recipient first when both are), so ONE round trip repairs
    both views — Signal-Server returns device IDs only
    (`MismatchedDevicesResponse`/`StaleDevicesResponse`) and forces a second `/keys` trip,
    while Sesame §3.3 explicitly permits returning the key material with the ids; ours is the
    Sesame shape and is self-verifying. `tempId` is REQUIRED for correlation when several
    sends are in flight. The check runs BEFORE any write: zero message rows, zero envelope
    rows (falsification 5; prior art is validate-then-insert,
    `MessageSender.validateIndividualMessageBundle` throwing before
    `messagesManager.insert`). The client MUST verify the I7 chain on a delivered list before
    adopting it and MUST fail the send on an invalid chain (falsification 4 — never the
    server's bare word), then retry at most 3 times before surfacing a hard send failure
    (Sesame §3.3/§4.1 mandate a finite cap without fixing the number).
  - **(vii) `senderListInfo` DEFERS to T5.** The §5.2 layer-2 field lives in E2E plaintext
    inside the ciphertext; the server never sees, stores, or validates it, so it is purely a
    client concern. Its falsifications (16 split-view, 22 false-alarm discipline) are both
    recipient-side escalation tests, and the receive-side guards they interact with are
    exactly the ones T5 flips to origin-device scoping. Landing the field alone in T4 would
    be dead weight; `E2eEnvelope.parse` ignores unknown keys, so adding it later costs
    nothing (the `linkPreview` precedent, root `CLAUDE.md` §7 envelope-compat).
  - **(viii) Per-device history reads + `envelopeStatus` vocabulary.** `getMessages` /
    `findByConversation` join `message_envelopes` on the REQUESTING `(recipientUserId,
    recipientDeviceId)` taken from the socket's JWT (legacy JWTs default to device 1, so
    addressing is uniform). The served ciphertext continues to ride the EXISTING
    `encryptedContent` wire field — no new ciphertext field, so older clients are untouched.
    Per-row fallback, device-gated: (1) this device's envelope → serve its ciphertext, NO
    `envelopeStatus`; (2) legacy `messages.encryptedContent` → served ONLY to the row's
    session owner, i.e. `deviceId == (originDeviceId ?? 1)` for the requester's OWN rows and
    `deviceId == 1` for rows it received; (3) otherwise the additive string marker. Two
    marker values, both carrying NO ciphertext: `"none_for_device"` (the row predates this
    device's link — the §5.3 honest placeholder) and `"own_origin"` (the requester's own row
    on its origin device: no envelope exists for the origin device BY DESIGN, since self-sync
    envelopes address the sender's OTHER devices). The second value is REQUIRED — without it
    the origin device would render "sent before this device was linked" over every message it
    ever sent. An extensible string code set is the industry-consistent shape (Matrix
    MSC2399's `m.room_key.withheld` `code`; `matrix-sdk-crypto`'s `UtdCause` keeps a dedicated
    `SentBeforeWeJoined` variant distinct from generic `Unknown`). Client rules: a marker row
    is EXCLUDED from the decrypt pass (it can never become `[Decryption failed]`), NEVER
    overwrites locally stored plaintext (it joins `placeholderContents`), and is NEVER a
    destruction trigger (I8, falsification 13); `own_origin` renders from the local plaintext
    store exactly as today and has no placeholder copy of its own.
  - **(ix) Lost-ack continuity under fan-out (forced by (v)+(viii); T5 keeps the rest).**
    Because a new-model row carries no ciphertext for its origin device, the landed
    exact-ciphertext pending-send reconcile (`frontend/CLAUDE.md` §5) would silently stop
    matching — a data-loss regression in the path that guards the ONLY plaintext copy.
    Therefore T4 lands the §5.4 key itself: the client MINTS `sendToken` for every new-model
    send and stores it IN the pending-send record; the server echoes `sendToken` on
    `messageSent` and on history rows served to that row's origin device; the reconcile
    matches `(senderId, originDeviceId, sendToken)` and MUST resolve to EXACTLY ONE row, an
    ambiguous match being a no-op that never consumes the record. Exact-ciphertext equality
    REMAINS the fallback for legacy and pre-existing records. The own-sender guard flip,
    self-sync consumption rules, and re-ack-without-re-fan under envelopes stay T5.
  - **(x) Legacy sends are refused once either party is enrolled; the client
    fans out only from a list it already holds (forced during T4 implementation;
    amends (v)'s "legacy normalized sends bypass the cross-check entirely").**
    Requiring the client to fetch a device list on EVERY send — to prove that a
    single-device account is single-device — taxes the overwhelmingly common
    path for nothing. So the client fans out only when it ALREADY holds a
    verified list for the RECIPIENT (seeded by an explicit `getDeviceList`, a
    `deviceListChanged`, or a `deviceListStale` refusal) and otherwise sends the
    legacy single-ciphertext shape, which (v) normalizes to a device-1 envelope
    at ingest. That is only safe because the SERVER now refuses a legacy
    ciphertext-bearing send whenever EITHER party has an `account_authorizations`
    row, answering `deviceListStale` with every enrolled party's signed list:
    a legacy send reaches device 1 alone, so accepting it for an enrolled peer
    would silently DROP that peer's other devices, exactly what invariant I5
    forbids. I5 therefore lands where it cannot be skipped — server-side — and
    the refusal is what upgrades a client to fan-out. Corollaries: a
    ciphertext-less send (PING) is never refused, since it has no envelope to
    fan out; a client MUST NOT fan out when the recipient's list is unknown
    (envelopes addressing own devices only would commit a row with a NULL legacy
    column whose recipient reads `none_for_device` forever — the message
    permanently invisible to the person it was sent to); and the refusal handler
    MUST explicitly resolve any party ABSENT from `lists[]` (an enrolled sender
    with a non-enrolled recipient yields a single entry, and without resolving
    the other party the resend would repeat the legacy shape until the retry cap).
    The server tells the client which device it is by echoing `deviceId` on
    `socketReady`: it cannot be derived client-side, and a fan-out must exclude
    its own origin device.
- **Amendment 2026-08-21 (T5 pre-implementation settlement, per the Stage-0 "settle before
  code" rule; grounded in `docs/plans/2026-08-21-t5-self-sync-lost-ack-research.md`, which
  cites libsignal, Signal-Server, Sesame, Matrix/Synapse, XEP-0198/0359, RFC 9420, CONIKS and
  Apple CKV from primary source). Items (xi)–(xviii) are NORMATIVE for T5. Two facts found by
  the research amend §5.4's own account of the work: the SEND half of self-sync already shipped
  in T4 on both tiers, and §5.4's list of own-sender guards is INCOMPLETE — the decisive gate is
  `MessageModel.needsDecryption`, and the receipt-emit guard must NEVER be device-scoped.**
  - **(xi) The own-row decision law — deny-decrypt unless PROVEN foreign-origin.** For a row
    with `senderId == me`, exactly one branch applies, evaluated in this order: (1)
    `envelopeStatus == 'own_origin'` → this device is the origin; NEVER decrypt (a Signal sender
    cannot decrypt its own output, and a failed attempt renders `[Decryption failed]` over the
    ONLY plaintext copy); reconcile via the pending-send record. (2) `(originDeviceId ?? 1) ==
    ownDeviceId` → the legacy shape of the same case (a legacy own row is served its own
    ciphertext with no marker); NEVER decrypt; reconcile. (3) `(originDeviceId ?? 1) !=
    ownDeviceId` → SELF-SYNC; decrypt as an ordinary inbound message against the session keyed
    `(myUserId, originDeviceId)`, and NEVER touch the pending-send record. The default is
    branch (1)/(2) behaviour: a row is decrypted only when its foreign origin is proven.
  - **(xii) The device-scoped branch requires an AUTHORITATIVE `ownDeviceId`.** `ownDeviceId`
    defaults to 1 and becomes authoritative only when `socketReady` echoes it, so a real device 2
    believes it is device 1 in that window. Until it is authoritative, an own row takes branch
    (1)/(2) — it stays `[encrypted]` and is retried once `socketReady` lands. Deferring the
    render is acceptable; guessing is not, because branch (3) on a wrongly-scoped row would
    attempt to decrypt this device's own ciphertext.
  - **(xiii) The five guards of §5.4 are eight, and one of them must NOT be flipped.** Flip to
    origin scoping: `MessageModel.needsDecryption` (**the master gate — omitted from §5.4; every
    other flip is dead code without it**), the history own-message branch, the live-path queue
    guard, the decrypt guard, and the terminal-duplicate guard (a foreign-origin own row IS a
    genuine inbound envelope and is eligible for that rule). The optimistic-replace branch keeps
    `tempId != null`, which already makes it origin-safe because a `tempId` exists only on the
    device that minted it. **The receipt-emit guard (`messageDelivered` + read-marking) stays
    ACCOUNT-scoped**: device-scoping it would make the sender's own second device emit a receipt
    for the account's own message, which §4 and falsification 19 forbid. The edit-echo reconcile
    and edit-eligibility checks likewise stay account-scoped — an edit is authored by the account.
  - **(xiv) `sendToken` uniqueness is enforced SENDER-scoped, which is strictly stronger than
    (ix)'s tuple.** The existing `UNIQUE (senderId, sendToken) WHERE sendToken IS NOT NULL`
    already makes "two candidate rows" structurally impossible; adding `originDeviceId` to that
    index would WIDEN the key and thereby PERMIT the same token from two devices, so it MUST NOT
    be added. (ix)'s `(senderId, originDeviceId, sendToken)` remains the CLIENT-side match law;
    the server contributes the uniqueness and the rule that the token is echoed ONLY to the row's
    origin device — so a non-origin device never holds the key that could consume another
    device's record. An ambiguous or absent match stays a no-op, asserted rather than assumed.
  - **(xv) `senderListInfo` shape and cadence (settles the (vii) deferral).** The field is
    `senderListInfo: {ownVersion, ownListHash, peerVersion, peerListHash}` inside the E2E
    plaintext; the server never sees, stores or validates it. Each hash is SHA-256 over the
    byte-exact DAK-signed `listCanonical` of that party's list as the SENDER knows it — never a
    re-serialization, since a non-canonical encoding yields phantom mismatches (Matrix signs
    canonical JSON for exactly this reason). Versions are the monotonic list versions. **Owner
    ruling 2026-08-21: it rides EVERY message**, not a sample: detection is immediate on the
    first message, and a sampled gossip (Apple CKV's approach) would make falsification 16 and
    the app-proof non-deterministic. A party the sender holds no verified list for is reported as
    absent, never as version 0.
  - **(xvi) Escalation discipline — a bare claim NEVER alarms (I7).** `senderListInfo` is
    untrusted peer-supplied data and may only be compared against the receiver's OWN verified,
    DAK-signed lists. A claim OLDER than what the receiver knows is a candidate freeze signal
    that renders only after the receiver independently confirms it against signed data. A claim
    NEWER than the receiver knows triggers AT MOST ONE re-fetch, rate-limited to one in flight
    per account with the rest queued (Matrix's rule — a parallel re-fetch lets a stale answer
    clobber a fresh one), and is then DISCARDED. Skew between the receiver's OWN devices is
    benign. First-contact TOFU stays unclosable in-band and MUST NOT be presented as if it were
    closed.
  - **(xvii) Own-device skew surfaces as a calm inline state (owner ruling 2026-08-21).** A small
    inline "syncing devices…" note in the conversation, en+pl, that clears itself once the lists
    agree. It MUST NOT reuse the identity-changed surface, and no security colour, icon or sound
    is permitted on this path — conflating a benign sync with an attack trains the user to ignore
    real warnings (Apple CKV: "warnings must be rare and accurate").
  - **(xviii) The reinstall gap is ACCEPTED, not repaired (owner ruling 2026-08-21).** A device
    that reinstalls holds no pending-send record and is echoed no `sendToken`, and the server
    never had the plaintext, so that device's own older rows render the honest
    `none_for_device`/own-origin placeholder permanently. This matches Signal's and Matrix's
    behaviour for messages predating the current install. A cross-device plaintext backfill would
    be a new plaintext-moving path and belongs to §9's Phase 4 if ever, NOT to T5.
  - **(xix) The device-list rollback pin covers the enrolled→not-enrolled transition.** An
    `authorization: null` answer for a party the client has already verified as enrolled at some
    version MUST be refused as a version rollback, not cached as "not enrolled". Enrollment is
    durable per §5.2, so the transition is never legitimate; caching it would silently narrow a
    fan-out to device 1 and, once (xi) lands, silently kill self-sync. This fix is T5's first
    stage because self-sync depends on the client's own device list being trustworthy.
  - **(xx) Three refinements forced by T5's post-build reviews (2026-08-21; three fresh
    reviewers, no P0). All NORMATIVE.**
    1. **The confirmed device id is SESSION state, never install state.** It MUST be reset to
       "device 1, unconfirmed" on logout/account switch, and a `socketReady` that carries NO
       `deviceId` MUST leave it unconfirmed rather than assert device 1. Both were latent
       violations of (xii) across sessions: this client is a process singleton, so a device id
       confirmed as N for one account survived into the next login, where an own row of a
       device-1 account looks foreign-origin — and the self-sync branch would then hand this
       device's OWN ciphertext to the ratchet. Unreachable while enrollment is unshipped
       (`ownDeviceId` is always 1), and fixed before it could ship.
    2. **The calm skew state of (xvii) is bounded to the re-fetch window.** The peer controls the
       version it claims about us, so raising the note on every mismatching claim let a hostile
       peer pin "syncing devices…" on permanently. It is now raised only when a re-fetch actually
       begins (same one-per-cooldown limiter) and cleared when that fetch settles.
    3. **The durable split-view record is DEDUPED per sender.** The claimed version and hash are
       peer-supplied and NOT DAK-signed, so a peer forging a mismatch on every message could
       append a durable row per message and FIFO-evict every other piece of forensic evidence
       (`CONTENT_KEY_LOST`, `OWN_IDENTITY_REPLACED`, …) from the 80-entry ring. One surviving row
       per peer is what an operator needs; per-message detail stays in the ring-only flow log.
- **Amendment 2026-08-21 (T6 pre-implementation settlement, per the Stage-0 "settle before
  code" rule; doc remains frozen — these pin the enforcement points and refusal codes for
  mechanisms §5.5, §5.1 and amendments (e)/(f) already mandate, changing no protocol law).
  Owner-ratified 2026-08-21. All NORMATIVE:**
  - **(xxi) Revocation refuses the primary and refuses self-revoke.** `revokeDevice` is
    accepted only for a device that is NOT the caller's own (`cannot_revoke_self`) and NOT the
    account's primary (`cannot_revoke_primary`); the caller's own row must be `isPrimary`
    (`not_primary`). The cryptographic gate remains the DAK signature on the list mutation —
    only the primary holds the DAK private key (§3), so the server-side `isPrimary` check is
    defence in depth, not the authority. Rationale for the two refusals: a primary that
    revoked itself would leave the account with NO device able to sign any future list
    version, which no in-band path can repair — the recovery for a lost primary is the §6.2
    reset, and a non-primary "sign me out" would need a server-signed list version, which §3
    forbids. A DAK-signed list whose canonical bytes revoke a different set than the request
    names is not reconciled: the request's `deviceId` MUST appear revoked in the submitted
    canonical list (`list_device_mismatch`), so the signed bytes and the teardown always agree.
  - **(xxii) The revoked-session predicate is "EXPLICITLY revoked", never "not active".** Both
    new gates — the socket connect gate and the HTTP gate — deny only when the `devices` row
    EXISTS and `revokedAt IS NOT NULL`. A MISSING row must never deny: every pre-Phase-1
    account has no row until its first connect writes one (§8), so denying on absence would
    lock out the entire legacy install base. This is deliberately the inverse polarity of
    `DevicesService.isActive`, which gates key-material UPLOADS and must fail closed on
    absence; a session gate that fails closed on absence is a mass lockout. Both predicates
    stay, each at its own call sites.
  - **(xxiii) I6 SILENCE is a separate rule from rejection, because silence is not an error.**
    A revoked device's still-valid access JWT is REJECTED by mutating handlers, but
    `getServedMessageIds` gets NO REPLY AT ALL — never an error answer, never an empty list.
    An empty `messageIds` is a legitimate "destroy all of them" instruction (I6), so a
    refusal shaped like an answer would remotely wipe the local history that §5.5 and §1
    guarantee stays. The revoked device therefore keeps every message it holds and its expiry
    sweep fails closed forever, which is the accepted over-retention I6 already records.
  - **(xxiv) The HTTP surface learns `deviceId`, and per-device push becomes real.**
    `JwtStrategy` now reads the `deviceId` claim (absent ⇒ device 1 per §8, exactly as the
    socket path already does), applies (xxii), and exposes it on the request principal. That
    unblocks the §5.5 clause that was unimplementable: the push-registration endpoints persist
    the caller's `deviceId`, so revocation can delete that device's rows. Rows registered
    BEFORE this ticket carry `deviceId IS NULL` and cannot be attributed to a device, so
    revocation deletes the revoked device's rows AND every NULL-`deviceId` row of the account:
    ambiguity resolves toward cutting the revoked device off, and a surviving device
    re-registers its endpoint on its next start (self-healing, at most one missed push
    window). Deleting nothing would keep pushing to the device the user just cut off.
  - **(xxv) Revocation preempts EVERY pending provisioning stage of the account**, not only a
    stage holding the revoked id (§5.1 "a security action never waits on a stuck link"). Every
    live stage carries a list mutation signed against the pre-revocation list, so revocation's
    version+1 makes all of them stale by construction; discarding them turns a guaranteed
    `stale_version` at commit into an immediate, honest `unknown_stage`. Stages are in-memory
    and keyed by `provisioningId` (amendment (iv)), so this is an iteration over the account's
    stages — nothing durable is touched.
  - **(xxvi) The kicked device is TOLD before it is dropped, and keeps its data.** The server
    emits `deviceRevoked { userId, deviceId }` to the revoked device's room and THEN
    disconnects its sockets. The client treats it as a logout with a stated reason (en+pl):
    session tokens cleared, local plaintext store and Signal key material UNTOUCHED — which is
    already what every existing logout path does, and is the §1 non-goal "no remote wipe" held
    intact. The event is best-effort (an offline device gets nothing); the (xxii) connect gate
    is the durable enforcement, so the UX must never depend on the event having arrived. A
    device that reconnects and is refused shows the same stated reason rather than the generic
    connection-lost banner.
  - **(xxvii) Accept-side (e) fails closed on VERIFIED data, and a cache miss is not a
    verdict.** At decrypt time, after the (xi) own-row branches have run, a genuine inbound
    row's `(senderId, originDeviceId ?? 1)` MUST be present-and-not-revoked in the receiver's
    verified list for that sender. The client's verified-list cache is memory-only, so a miss
    is the NORMAL state after every reload: a miss MUST trigger the ordinary rate-limited
    verified fetch and leave the row RETRYABLE (`[encrypted]`, no ledger consumption, no
    terminal failure), never refuse it permanently. Only a list that positively shows the
    origin device absent or revoked refuses the decrypt — and that refusal is silent (I7: it
    is a decrypt refusal, never an alarm surface). A sender that is not enrolled verifies as
    the synthesized single device 1, so an inbound `originDeviceId >= 2` from a non-enrolled
    account is refused, which is the correct fail-closed reading of §5.2.
    **Rider, forced by implementation (2026-08-21):** when the verified fetch itself FAILS
    (timeout, no pinned identity, broken chain), the withholding applies to
    `originDeviceId >= 2` only; a device-1 row keeps its pre-T6 behaviour and decrypts. A
    strict reading would let one withheld or broken `getDeviceList` answer silence EVERY
    conversation of a single-device account — a server-side off switch for reading mail — while
    buying almost nothing: §5.5 refuses to revoke a primary at all, and the one path that
    revokes device 1 is the §6.2 reset, which also replaces the account identity, so that
    device's ciphertext stops decrypting for every peer regardless of this check. A list the
    client DOES hold still refuses a revoked device 1, so the teardown case stays covered.
  - **(xxviii) The §6.2 reset roster teardown (amendment (f)) is ONE transaction at the
    authorized identity change**, which is the moment a reset actually completes (the
    ceremony's consumption point, not the request). In that transaction: the recovering device
    is ALLOCATED a fresh id from `users.nextDeviceId` and is re-issued its tokens with that
    claim (the shape `provisioningCompleted` already uses — a reset must never re-mint device
    1, per (f)(i)); every surviving `devices` row is stamped `revokedAt` (f)(ii); each revoked
    device's key bundle and OTPs are purged strictly inside its own `(userId, deviceId)`
    namespace; `users.nextDeviceId` is left untouched (f)(iv). Falsification 12 is precisely
    the assertion that this teardown cannot reach a surviving device's key material.
  - **(xxix) The `account_authorizations` row is REPLACED, never dropped, and its version
    never restarts** (f)(iii). Dropping it would destroy the `listVersion` that (f)(iii)
    requires be carried forward, contradict the entity's own law ("monotonic — never restarts,
    even across a §6.2 reset") and make the account read as not-enrolled, which (xix) correctly
    refuses as a rollback. So the reset transaction leaves the row ALONE: its DAK is now
    orphaned, because the enrollment record `E` was signed by the identity key the reset just
    replaced, so no peer can verify the chain and every peer FAILS CLOSED — the honest state
    for an account whose identity just changed, and one the takeover alarm already surfaces.
    Recovery is a REPLACEMENT enrollment, admitted by exactly one new rule: an enrollment whose
    STORED `enrollmentSig` no longer verifies under the account's CURRENT published identity
    MAY be replaced by a fresh IK-signed enrollment whose list version is strictly GREATER than
    the stored version (`enrollment_version_must_be_1` continues to govern a genuine first
    enrollment; first-write-wins is otherwise untouched). The predicate is self-verifying —
    only an identity change can orphan a stored enrollment, and the fresh `E` must verify under
    the identity the server currently serves — so no flag, no nullable state and no new
    trust input is introduced. The recovering device re-enrolls immediately as part of recovery
    (it holds the fresh IK, mints a fresh DAK, and signs a list naming only its newly allocated
    deviceId); it needs no new wire field to do so, because `getDeviceList` already serves the
    stored version it must exceed.
- **Next gate:** per-ticket implementation reviews (T1–T8); Stage 0 is CLOSED 2026-08-19.
