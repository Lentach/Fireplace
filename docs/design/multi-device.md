# Multi-device (linked devices) — design

**Status: DRAFT v3 — first internal review round DONE (security + data-loss, 2026-08-17, both
blocking; all findings folded below, see §12). Awaiting owner ratification + second review pass at
Phase-2 spec level. NO CODE until the gauntlet passes.**
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
  plaintext-store invariants (`frontend/CLAUDE.md` §5) beyond what §5.4/§5.6 state explicitly.

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
to denial of service, which S can always do anyway. (Security review finding 2, folded.)

**Non-negotiable invariants** (each gets a red-first test, §10):

- **I1** — The server NEVER holds a private key: not IK, not DAK, not per-device keys. Provisioning
  transports IK device-to-device encrypted to an ephemeral key; the server relays opaque bytes.
- **I2** — Every device-list mutation carries a signature by the account's **DAK**, whose private
  half exists ONLY on the current primary, in platform Keystore. The shared identity key is NEVER a
  device-list signing authority (a linked PWA holds IK in web storage; one XSS must not mint
  devices). Primary handover ROTATES the DAK (§6.3); the private half never leaves its origin
  device, and a demoted primary's DAK has no remaining authority.
- **I3** — Linking requires possession: QR scan + SAS confirmation + explicit approve on the
  primary, AND a valid password login on the new device. Neither alone suffices. No password-only
  fallback, ever.
- **I4** — Identity/DAK *reset* (all devices lost) is the only credential-only path, and it is slow
  and loud: fixed delay, rate-limited, every live session AND every push endpoint notified before
  it takes effect; cancel wins any race with expiry (§6.2).
- **I5** — Fail-closed inheritance: every existing UNKNOWN-is-not-absence rule survives per-device
  (the 0.1.10 guard's tri-state, reconcile's null-answer-purges-nothing, ledger fail-open rules).
  A device-list fetch failure means "cannot send", never "send to fewer devices".
- **I6** — A revoked device stops receiving new envelopes at revocation commit, atomically with the
  signed list mutation. Its local history remains its own; **the server answers a revoked device's
  `getServedMessageIds` with SILENCE** (a missing reply purges nothing — never an empty/partial
  answer, which would read as "destroy all"). (Data-loss review finding 3, folded.)
- **I7** — Peers verify the device list against the IK→DAK chain, monotonic version, AND the
  end-to-end version cross-check of §5.2; the server is untrusted for list content and freshness.
  Rollback, invalid chain, or a cross-check mismatch = loud identity-changed surface.
- **I8** — The reconcile contract is UNTOUCHED: "served" remains row-existence + participant based
  (per user, metadata-blind — `messages.service.ts:194-243`), independent of the envelope
  dimension. Envelopes gate realtime routing and per-device delivery stamps ONLY, never reconcile,
  never history visibility of an existing row. (Data-loss review finding 1/6 — the v2 per-device
  predicate would have mass-destroyed senders' own plaintext; reverted.)

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
signature by DAK over the canonical serialization (byte layout fixed in Phase 1 spec: JSON, sorted
keys, no whitespace, userId and version first). Every mutation increments `version`. `listHash =
SHA-256(canonical)` is the compact reference used in the §5.2 cross-check. `name` is user-chosen,
length-capped, server-readable metadata — said plainly in UI.

Library caveats honored: `calculateVrfSignature` is stubbed — never referenced; `sign`/`verifySig`
mutate passed buffers — always pass copies of retained key/signature buffers.

## 4. Data model (backend)

New/changed tables (numbered migrations, staging rehearsal mandatory — root `CLAUDE.md` §6):

- **`devices`**: `(userId, deviceId)` PK, `name`, `platform`, `isPrimary`, `addedAt`, `revokedAt`,
  `lastSeenAt`. `deviceId` per-account small int from 1 (existing accounts = device 1 implicitly,
  §8).
- **`account_authorizations`**: `userId` PK, `dakPub`, `enrollmentSig`, `listVersion`,
  `listSignature`, `listCanonical` (the exact signed bytes — peers verify what was signed, never a
  re-serialization), `updatedAt`.
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
  §5.4). Single `deliveryStatus` stays as a **projection** (delivered = first envelope delivered;
  read = any envelope read — wire shape unchanged), written ONLY as a column-scoped UPDATE of
  `deliveryStatus`, NEVER a full-entity save — a hydrated re-save would clobber
  `expiresAt`/`disappearAfterSeconds` and break read-based TTL (data-loss finding 5, folded).
  Legacy `encryptedContent` retained for pre-migration rows and legacy-client sends (§8); new
  multi-device sends write envelopes only.
- **`refresh_tokens`**: + `deviceId`, `deviceName` — the per-device session anchor; per-device
  revoke = delete that device's rows + kick its sockets. JWT payload gains `deviceId`.
- **`fcm_tokens`** / **`web_push_subscriptions`**: + `deviceId` → per-device push targeting and
  suppression.

## 5. Protocols

### 5.1 Provisioning (linking) ceremony

Transport: existing socket + relay events; envelope crypto: the lib's `ProvisioningCipher`
(X25519 ECDH → HKDFv3 → AES-CBC+HMAC-SHA256, `src/provisioning_cipher.dart`; the Mixin info label
is fine — no interop with Signal's wire).

```mermaid
sequenceDiagram
    participant N as New device (logged in, deviceId pending)
    participant S as Server (blind relay)
    participant P as Primary (holds DAK)
    N->>N: ephemeral keypair ephN
    N->>S: openProvisioning → {provisioningId (UUID, 10 min TTL)}
    N->>N: show QR {provisioningId, ephPubN}; display SAS = KDF(ephPubN ‖ provisioningId)
    P->>N: user scans QR (camera = possession)
    P->>P: recompute SAS from the SCANNED ephPubN; user compares digits shown on BOTH screens, then approves
    P->>S: provisionDevice {provisioningId, blob = ProvisioningCipher(ephPubN).encrypt({IK pair, dakPub, E, assigned deviceId}), stagedMutation = {list v+1 adding deviceId, sig_DAK}}
    S->>S: verify sig_DAK vs pinned dakPub; verify v+1; STAGE mutation (not committed)
    S->>N: provisioningBlob {blob}
    N->>N: decrypt; store IK; mint registrationId/signedPreKey/OTPs
    N->>S: provisioningComplete {provisioningId} + per-device bundle upload (tagged deviceId)
    S->>S: ONE transaction: commit staged mutation + devices row + activate deviceId + bundle
    S-->>P: deviceListChanged (all own sessions; peers pick it up via §5.2)
```

Rules (security findings 1 and 4, folded):
- **The SAS is never transmitted.** Both sides derive it independently from `(ephPubN,
  provisioningId)`; an ephPub substitution changes P's SAS and the human comparison fails. The QR
  carries only `{provisioningId, ephPubN}` — no secrets.
- **Two-phase commit.** The list mutation is STAGED at `provisionDevice` and committed only on N's
  `provisioningComplete` (which requires successful blob decryption — it carries the assigned
  deviceId). No state exists where a device is listed/active but keyless. Until completion the blob
  MAY be re-fetched against the same `provisioningId`; TTL expiry or a P-side cancel discards the
  stage. `provisioningComplete` is the one-shot consumer of the id.
- Concurrent link attempts: two staged mutations both at `v+1` — the second commit loses on the
  version check; primary re-signs at `v+2` and re-submits (bounded retry, then surface failure).
- Both ceremony sides are new clients by definition; no legacy compat needed here.

### 5.2 Send fan-out and device-list freshness (Sesame §3.3 + E2E cross-check)

Client send: `sendMessage { conversationId, meta…, senderListVersion, recipientListVersion,
sendToken, envelopes: [{userId, deviceId, ciphertext}] }` — one ciphertext per *(recipient
device)* plus one per *(sender's other devices)* (self-sync), each from its own pairwise session
(`SignalProtocolAddress(userIdStr, deviceId)` — free int, lib-verified).

Freshness is checked at TWO layers:
1. **Server-side (liveness):** stale stamps → reject `deviceListStale { userId, version,
   listCanonical, listSignature, enrollment }`; client verifies the signature chain (I7), updates
   its cache, re-encrypts, resends. Retry cap 3, then a surfaced send failure — never silently
   dropping devices (I5).
2. **End-to-end (trust — security finding 2, folded):** the E2E plaintext envelope (the existing
   `{content, …}` JSON that gets Signal-encrypted) gains
   `senderListInfo: {ownVersion, ownListHash, peerVersion, peerListHash}` — the sender's view of
   BOTH lists at encrypt time. Each receiving device compares `peerVersion/peerListHash` (the
   sender's view of the RECIPIENT's list) against its own current list: if the sender was fed an
   older version than the recipient knows to be current, the recipient renders the stale-list
   alarm — a server freezing a peer at an old list is exposed by the first message from any honest
   device, and can only stay hidden by blocking messages entirely (plain DoS). Same check on
   `ownVersion` guards the reverse direction. Older clients ignore the extra field
   (root `CLAUDE.md` §7 envelope-compat convention).

Version match → one message row + N envelope rows in ONE transaction (no crash window stranding
envelopes vs rows), then per-device delivery (§5.3). Sessions to a newly-seen deviceId are built
lazily via `fetchPreKeyBundle {userId, deviceId}` (per-device OTP claim; `preKeysLow {remaining}`
becomes per-device, routed to that device).

### 5.3 Realtime delivery, rooms, push

- Socket auth carries `deviceId` (JWT claim); socket joins `user:<uid>` (metadata: reactions,
  delivery, list changes, deletes) **and** `device:<uid>:<did>` (ciphertext: `newMessage`,
  `messageEdited` — each device gets *its* envelope).
- `emitToNewestTab` survives, demoted to *within one web device*: tabs of a linked PWA share one
  session store, so ciphertext to a device room targets that device's newest socket (renamed
  `emitToDeviceNewestSocket`; its documented removal condition is unchanged, now per-device).
- Push suppression: skip push only for the device whose own socket has the conversation focused.
  Envelope `deliveredAt`/`readAt` stamped per device; wire keeps the projected single
  `deliveryStatus` (no client change for peers).

### 5.4 Self-sync, lost-ack, and the reconcile — coexistence rules (the danger zone)

Own-sent messages: device B receives an envelope with `senderId == me` and
`originDeviceId != myDeviceId` — decrypted like any inbound message (pairwise session between own
devices), persisted normally. The existing early-return on own senderId
(`messaging_provider.decrypt.dart:975`) becomes: skip ONLY when `originDeviceId == myDeviceId`.

**Rules, each with a falsification test (§10):**
- **Reconcile untouched (I8).** `getServedMessageIds` stays per-user, row-existence based. The
  origin device is served for its own rows like today (the row exists; envelopes are irrelevant).
  A device linked AFTER a message existed sees the row in history (metadata; content shows as
  undecryptable-by-absence-of-envelope → rendered as "sent before this device was linked", a new
  honest placeholder — NOT `[Decryption failed]`, NOT retired, and NEVER a destruction trigger).
- **Lost-ack keyed by `sendToken`** (data-loss finding 4, folded): the client mints a UUID per
  send, stores it in the durable pending-send record, and the server echoes it on own-message
  history rows. The own-message reconcile branch matches by `sendToken` (exact-ciphertext equality
  retained as the legacy fallback for pre-migration records). This survives the envelope model,
  where the origin's own row carries no origin-readable ciphertext.
- A self-sync row must NEVER consume a pending-send record (origin-device scoping).
- The `messageSent` ack goes only to the origin device; other own devices get envelopes.
- Own-device sessions run through the same `_sessionTails` serialization, keyed
  `(peerId, deviceId)` — own devices are just another peer address to the ratchet layer.

### 5.5 Revocation

Primary-only action (DAK-signed mutation, `revokedAt` set, version+1, one transaction):
- server stops routing envelopes to the device, deletes its refresh tokens + push rows, kicks its
  sockets; its still-valid access JWT gets SILENCE from `getServedMessageIds` (I6) and rejection
  from mutating handlers until natural expiry;
- peers drop the device from fan-out on the next staleness bounce (worst case one rejected send),
  and the §5.2 cross-check exposes any server attempt to keep serving the pre-revocation list;
- the revoked device's local data is NOT remotely wiped (logout semantics; non-goal, stated in UI);
- the revoked device's OTPs are purged (only that device could complete those handshakes; it is no
  longer served envelopes).

### 5.6 Disappearing messages — deliberate ruling (data-loss finding 2, resolved by ruling)

Row-level expiry is RETAINED: the read-based TTL starts when the recipient USER first reads
(any device), and at the deadline the row + ALL envelopes are destroyed — including an envelope a
linked device never fetched. **Disappear means disappear, on every device, at one deadline.**
Per-envelope expiry was considered and rejected: it would keep "disappeared" content alive on idle
devices past the deadline, trading a privacy guarantee for sync completeness. Consequence, stated
honestly in docs and UI: a linked device offline past the deadline never shows that message (same
behavior as Signal). Falsification 11 asserts no error artifact is produced — the row is simply
absent; client-side destruction rules (server-clock gating, §7 root) are unchanged and per-device.

## 6. Registration lock and reset (Phase 0, ships before any device work)

### 6.0 Phase 0a — takeover alarm (days, no protocol change)
Promote the existing `[identity-churn]` branch (`key-bundles.service.ts:46-53`) to: durable
server-side audit row; WS + push notice to the account's other sessions/endpoints ("your security
identity was replaced from a new sign-in"); peer-visible flag corroborating the client's
`PEER_IDENTITY_CHANGED` state; **in-conversation timeline row on peer clients** (restores the
takeover alarm removed 2026-08-15 — re-raised on new evidence, owner may re-overrule). Wording
follows the 08-16 consented-recovery framing ("new device/browser sign-in", wipe variant).

### 6.1 Single-device registration lock (pre-multi-device)
`upsertKeyBundle` with a DIFFERENT `identityPublicKey` than stored requires
`sig_oldIK(newIdentityPublicKey ‖ userId ‖ serverNonce)`. Same-identity re-uploads (today's
every-connect re-upload) pass unchanged. Genuine loss → §6.2.
**Nonce spec** (security finding 6, folded): CSPRNG-generated (unpredictable, never
counter/timestamp), single-use, TTL ≤ 5 min, bound to the issuing authenticated socket session —
a nonce issued to one session is invalid on any other. Scope honesty: this measure defends against
**P** (password thief) under an HONEST server; a colluding **S** can issue chosen nonces — that
threat is handled by the peer-side chain (I7), not by §6.1.

### 6.2 Reset ceremony (all devices / identity lost)
Credential login → `resetIdentityRequest` → server starts a **72 h** timer, immediately notifying
every live session AND every registered push endpoint (FCM + Web Push; this app has no email —
push is the only offline channel, which is WHY the delay is 72 h and not 24). Any session can
CANCEL with one tap (no key required). Peers' conversations are marked pending-reset.
Hardening (security finding 5, folded):
- **Rate limit**: one pending request per account; a new request while one is pending is a no-op
  returning the existing deadline; after a cancel, cooldown 24 h before the next request (a
  credentialed attacker cannot spam notification fatigue).
- **Cancel/expiry serialization**: expiry-commit runs in one transaction that re-checks
  not-cancelled; states are terminal (`completed` / `cancelled`) — a late cancel after commit is a
  no-op, never an identity rollback; a cancel that wins the race aborts the commit.
On expiry the server accepts a fresh IK + fresh enrollment; peers get the loud identity-changed
surface. Optional recovery key (owner-undecided, §11) shortcuts the timer.

### 6.3 Primary migration (planned handover) — ROTATION, never copy
(Security finding 3, folded — a copied DAK would leave the demoted primary with permanent minting
authority.) New primary candidate generates a fresh **DAK′** in its own Keystore; old primary signs
the replacement enrollment `E′ = sig_oldDAK(userId ‖ dakPub′ ‖ createdAt′)` after the same
QR + SAS ceremony as §5.1; server pins `E′`; peers re-pin on next fetch via the E→E′ chain (old DAK
authority dies at that instant); a DAK′-signed mutation flips `isPrimary`. The DAK private half
never leaves the device that minted it, ever. Old primary lost → reset §6.2 (the DAK is gone —
that is the designed outcome).

## 7. Wire-contract deltas (root `CLAUDE.md` §7 — every line re-ratified at Phase 2 review)

| Surface | Today | After |
|---|---|---|
| `sendMessage` | one `encryptedContent` | `envelopes[]` + `sendToken` + two list-version stamps; reject path `deviceListStale` |
| E2E plaintext envelope | `{content, messageType?, media…}` | + `senderListInfo {ownVersion, ownListHash, peerVersion, peerListHash}` (older clients ignore) |
| `newMessage` / `messageEdited` | newest tab of user | device room, newest socket within device; payload + `originDeviceId` |
| own-message history rows | ciphertext echo | + `originDeviceId`, `sendToken` (lost-ack match key) |
| `uploadKeyBundle` / `fetchPreKeyBundle` / `uploadOneTimePreKeys` / `preKeysLow` / `checkOwnKeyBundle` | per user | per `(user, device)`; bundle mutation rules of §6.1 |
| `messageDelivered` / read events | per message | unchanged shape; server projects from envelopes (column-scoped UPDATE only) |
| `getServedMessageIds` | per user, row-existence | **UNCHANGED (I8)**; SILENCE to revoked devices (I6) |
| NEW | — | `openProvisioning`, `provisionDevice`, `provisioningBlob`, `provisioningComplete`, `deviceListChanged`, `getDeviceList`, `revokeDevice`, `resetIdentityRequest/Cancel` |
| `socketReady`, `getServerTime`, delete/clear/unfriend, reactions | per user | unchanged (delete fan-out cascades envelopes) |

## 8. Compatibility and rollout

- Existing accounts become `devices(userId, 1, isPrimary=true)` implicitly (migration backfill). No
  DAK until the user enables linking; until then §6.1 governs.
- **Only a Keystore-capable device may become primary** (I2) — in practice the Android APK. A
  PWA-only account (today's iOS users) stays single-device until an iOS app exists; the web client
  can be a *linked* device only. Stated to the user at enable time.
- **Reconcile safety across the mixed model (I8, data-loss finding 6):** "served" is row-existence
  based for every row shape — pre-migration rows (legacy `encryptedContent`, no envelopes),
  legacy-client sends (stored as a device-1 envelope), and new envelope-only rows all reconcile
  identically. No first-launch mass-purge shape exists by construction; falsification 13 pins it.
- Legacy client → new server: single-ciphertext sends accepted, stored as a device-1 envelope. A
  legacy sender cannot encrypt to linked devices — window kept small by rollout ORDER: server first
  (accepts both), clients next (send envelopes), linking UI enabled LAST, gated on
  min-client-version per account.
- New client → old server: capability-probed (no `getDeviceList` answer = legacy server); client
  stays single-device, fail-closed.
- e2e-wire harness grows the two-devices-one-account suite BEFORE Phase 1 merges (§10). Staging
  dress rehearsal for every schema phase (root §6).

## 9. Phase plan (each phase independently shippable, reviewed, and behind the previous)

| Phase | Content | Ships value alone? | Acceptance |
|---|---|---|---|
| **0a** | churn alarm: audit row + session/push notify + peer timeline row | YES — takeover detection | live-fire: bundle replace on a test account alerts second session + peer within 5 s |
| **0b** | registration lock §6.1 + reset ceremony §6.2 | YES — takeover prevention | red-first: password-only bundle replace rejected; reset honors 72 h, rate limit, cancel/expiry serialization |
| **1** | schema: `devices`, `(userId,deviceId)` bundles/OTPs, re-keyed 3-site epoch, JWT `deviceId`, refresh/push device columns, `originDeviceId`+`sendToken`; every account = device 1 | invisible; unblocks all | full suites + wire harness green single-device; falsifications 1, 13 |
| **2** | provisioning §5.1, DAK + signed list + cross-check §5.2, envelopes, self-sync §5.4, rooms §5.3, revocation §5.5 | the feature | two-device harness: link → both receive → self-sync → revoke → stale bounce; ALL §10 falsifications green; own Phase-2 spec review first |
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
6. Self-sync row must NOT consume a pending-send record (origin-device scoping) — red if the
   `originDeviceId` guard is removed.
7. Concurrent send + revoke: revoked device receives no envelope for a message committed after the
   revocation transaction.
8. Provisioning blob replayed to a different ephemeral key → undecryptable; expired TTL → rejected;
   `provisioningComplete` is one-shot.
9. Fail-closed inheritance: device-list fetch timeout on send → send FAILS; per-device
   `checkOwnKeyBundle` UNKNOWN → no key generation (0.1.10 invariant).
10. Reset: cancel from a live session halts the timer; cancel racing expiry-commit is serialized
    (terminal states; late cancel = no-op, never rollback); repeated requests rate-limited; peers
    never see identity-changed on a cancelled reset.
11. Expiry: at deadline row + ALL envelopes destroyed; a device that never fetched its envelope
    shows NO error artifact (row absent, §5.6); devices that decrypted destroy plaintext per
    existing clock rules.
12. Per-device epoch: post-reset, all three re-keyed sites purge/claim/count strictly within
    `(identity, deviceId)`.
13. **Reconcile mass-purge guard (I8):** origin device's own new-model sends, pre-migration rows,
    and legacy-client rows ALL reconcile as served; a revoked device's reconcile gets SILENCE and
    purges nothing; a device linked after a message existed never treats that row as a destruction
    trigger.
14. **Lost-ack via `sendToken`:** drop the `messageSent` ack on an envelope-model send → history
    pass recovers plaintext by token match, persists under real id, read-back verified (mirror of
    `messaging_provider_lost_ack_test.dart`).
15. **ephPub substitution:** swap ephPub in the QR relay while keeping all other fields → P's
    recomputed SAS differs (human check fails); assert SAS derivation binds ephPub AND
    provisioningId.
16. **Split-view/freeze:** server serves peer A a frozen validly-signed old list (v3) after B
    revoked a device (v5) → the first message A receives from any of B's devices carries
    `senderListInfo` exposing v5; A renders the stale-list alarm. Red without the E2E cross-check.
17. **DAK rotation:** after §6.3 handover, a mutation signed by the OLD DAK → rejected by server
    AND peers (proves rotation, not copy).
18. **Two-phase provisioning:** kill N's socket between blob relay and `provisioningComplete` →
    no device row, no list mutation, blob re-fetchable until TTL; peers never see the device.
19. **Projection safety:** delivery projection updates change ONLY `deliveryStatus`;
    `expiresAt`/`disappearAfterSeconds` byte-identical before/after (data-loss finding 5).
20. **Concurrent double-link:** two staged mutations at v+1 → second rejected on version; primary
    re-signs at v+2; exactly one device added per ceremony.

## 11. Open questions (owner)

1. Restore the in-conversation identity-changed timeline row (0a includes it; prior ruling removed
   the banner — this is a narrower, event-driven row, re-raised on takeover-alarm evidence). Y/N?
2. Optional recovery key (client-generated words, hash-only server-side) to shortcut the 72 h reset
   — adopt in 0b, later, or never?
3. Device cap 3 (1 primary + 2 linked) — confirm.
4. Reset delay 72 h (push-only offline channel; no email exists in this app) — confirm or adjust.
5. Accept "iOS-PWA users cannot be primaries / cannot link until an iOS app exists"? (Web-held DAK
   is rejected under I2.)
6. §5.6 ruling — disappear-at-one-deadline beats per-device retention. Confirm.

## 12. Review record

- **2026-08-17 — data-loss review (reviewer subagent): REVISE (blocking).** 6 findings, all folded:
  (P0) v2's per-device "served" predicate would have destroyed senders' own plaintext on every send
  — reverted to row-existence reconcile, now invariant **I8** + falsification 13; (P1) row expiry
  cascading away an unfetched envelope — resolved by explicit §5.6 ruling (disappear-at-deadline is
  the product semantic) + falsification 11; (P1) revoked device's reconcile would mass-purge its
  local history — server SILENCE rule in I6/§5.5 + falsification 13; (P1) lost-ack exact-ciphertext
  match cannot fire under the envelope model — `sendToken` match key, §5.4 + falsification 14;
  (P2) delivery projection could clobber expiry stamps — column-scoped UPDATE rule, §4 +
  falsification 19; (P2) mixed-model reconcile mass-purge on migration — I8/§8 + falsification 13.
- **2026-08-17 — security review (reviewer subagent, defensive framing; first spawn was refused by
  a content filter and re-dispatched): SHIP-WITH-FIXES leaning REVISE.** 6 findings, all folded:
  (MAJOR) SAS digits carried in the QR don't bind ephPub → SAS now derived both sides from
  `(ephPubN, provisioningId)`, never transmitted, §5.1 + falsification 15; (MAJOR) list freshness
  verified only by the untrusted server → end-to-end `senderListInfo` cross-check inside the E2E
  envelope, §5.2/I7 + falsification 16, threat-matrix row³; (MAJOR) §6.3 DAK copy left demoted
  primary with permanent authority → rotation-only handover, §6.3/I2 + falsification 17;
  (MINOR) keyless-listed-device on post-commit blob loss → two-phase staged commit on
  `provisioningComplete`, §5.1 + falsification 18; (MINOR) reset DoS/races/offline notification →
  rate limit + cancel/expiry serialization + push channel + delay rationale, §6.2/I4 +
  falsification 10; (MINOR) §6.1 nonce underspecified → CSPRNG/TTL/session-bound spec + honest-
  server scope note, §6.1.
- **Owner ratification: PENDING** (§11 questions). Phase 2 gets its own spec-level review round
  before implementation, per phase plan.
