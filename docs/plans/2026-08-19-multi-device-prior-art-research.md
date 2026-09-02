# Multi-Device / Multi-Session Prior Art — Research (2026-08-19)

How production E2EE messengers (Signal, Matrix, WhatsApp, iMessage) and MLS handle
multi-device, researched against primary sources (specs, whitepapers, RFCs, actual server/client
source code) to inform Fireplace Phase 2. Full source-cited reports are Appendices A-D;
this synthesis maps every finding onto the frozen spec (`docs/design/multi-device.md` v5)
and the Phase-2 tickets T1-T8.

Method: four parallel research agents, primary sources only, every claim cited
(Signal-Server @2f482f68, libsignal v0.101.0, matrix-spec main, vodozemac, WhatsApp
whitepaper v9 Feb-2026, Apple Platform Security + CKV blog, RFC 9420, EuroS&P'18 /
S&P'23 / EUROCRYPT'25 papers). Unverified claims are marked in the appendices.

---

## 1. Where Fireplace sits in the design space

Identity model (Appendix D, Part 4): **one account IK shared by every device** (transported
device-to-device in the §5.1 provisioning blob) + a **separate DAK signing key** (primary-only
custody) that signs the device list, bound to the IK by enrollment `E`.

| Lever | Signal | Matrix | WhatsApp | iMessage+CKV | MLS | **Fireplace (frozen v5)** |
|---|---|---|---|---|---|---|
| Identity key | ONE per account (ACI+PNI), cloned to linked devices via provisioning cipher | Per-device keys; identity emerges from cross-signing MSK | Per-device identity keys | Per-device keys + synced account ECDSA key | Per-leaf keys | **ONE shared IK** (Signal-style) |
| Who signs the device list | Nobody (server-asserted; Sesame 409-dance only) | Server controls raw list; SSK optionally attests devices | Primary signs list (`0x0602‖ListData`) + bidirectional per-device sigs | Account key + Key Transparency log | Membership welded into transcript hash + key schedule | **DAK signs list; peers verify IK→E→DAK chain (I7)** |
| Peers pin & diff | No (lazy 409/410) | Warn-on-unverified; split-view defeats it | Verify sigs at every fan-out, abort on failure; ICDC TTL 48h/35d | Self-audit + gossip | Confirmation MAC fails on divergence | **`senderListInfo` E2E cross-check (§5.2)** |
| Device-id lifecycle | **Reused** (lowest-free) | Client random string; reuse allowed but hazardous | Composite `Epoch(4B)‖DeviceID(2B)`, epoch monotonic | Opaque; KT log append-only | Epochs strictly increase | **Monotonic, NEVER reused (§5.3 L269-272)** |
| Fan-out | Pairwise per device | Megolm sender-key (fan the session key once) | Pairwise per device | Pairwise per device | One group key schedule | **Pairwise per device** |

Fireplace = Signal's identity/fan-out model + a WhatsApp-grade signed device list +
an MLS-flavored (lightweight) agreement check via `senderListInfo`. That combination is
coherent: each piece has a production precedent, and the pieces we added (DAK, cross-check)
are exactly what the attack literature says Signal's bare model lacks.

## 2. The headline finding: Signal REUSES device ids — and why that does NOT transfer

`Account.getNextDeviceId()` (Signal-Server `storage/Account.java:315-328`) scans from 2 upward
and returns the **lowest unused id** — an id freed by unlinking is handed to the next device.
Reuse is expected and defended: `AccountsManager.addDevice` proactively purges leftover
prekeys + queued messages for the reused id (`AccountsManager.java:667-676`). (Appendix A §2.)

Signal can afford this ONLY because of machinery Fireplace does not have:

1. **Per-device random `registrationId`** disambiguates a reused id: peers holding the old
   session hit **410 staleDevices** on next send and re-run X3DH (Appendix A §8). Fireplace
   has no registrationId-mismatch bounce in the wire contract.
2. **Purge-on-reuse** of ALL per-id server state. Fireplace's `purgeSupersededDevices` drops
   only `key_bundles` + `one_time_pre_keys` (known Phase-2 landmine).
3. **No device-gated legacy history fallback.** Fireplace §5.3 serves legacy
   `encryptedContent` to the session owner keyed BY deviceId (`deviceId==1` or
   `==originDeviceId`) — a reused id would be handed pre-reset ciphertext it cannot decrypt
   (or worse, that its holder should not have). This is the exact "foreign-ratchet decrypt"
   the frozen invariant names.

Matrix documents the failure mode of reuse directly: cross-signing signatures are keyed by
`(user_id, device_id)` and **persist server-side after device deletion**; a reused id makes
stale attestations reattach to the new keys (Synapse issue #17375, Appendix B §1). Fireplace's
DAK-signed list mutations and `identity_change_audit` are the analogous persistent,
id-keyed artifacts.

WhatsApp and MLS both chose monotonic (epoch-based) ids; the cross-cutting recommendation of
the attack literature is "monotonic, authority-anchored ids; treat account reset as a new
orbit, never silently reuse an old id under a new key" (Appendix C §5, rec 7).

**Consequence for owner decision 1:** the frozen spec's never-reuse invariant is the
right call and is cheap to honor. Prior art narrows the open question to allocator shape only:
a per-account counter (`users.nextDeviceId`, atomic `UPDATE … RETURNING`) is the boring,
race-safe implementation; deriving `MAX(deviceId)+1` from `devices` silently converts a
retention rule into a crypto invariant (Signal-style reuse-by-accident the moment any row is
purged). Signal's 6-device cap (`DeviceController.MAX_DEVICES=6`) vs our ratified cap of 3:
both are independent of the id space.

## 3. Findings mapped to Phase-2 tickets

### T1 — migration 0016 (DAK, enrollment, list version, id allocation)
- Monotonic allocator per §2 above. Signal's id space is 1..126 with a hard cap 6; ours can be
  a plain int with cap 3 enforced at enrollment (Appendix A §2).
- WhatsApp's app-state KeyID is `Epoch(4B)‖DeviceID(2B)` with epoch bumped on every
  unregister — precedent for keying material by (epoch, deviceId) if we ever need it
  (Appendix C §1.7).

### T2 — signed device list + E2E cross-check
- **Domain separation is the #1 lesson.** WhatsApp uses explicit prefix bytes per signature
  type (`0x0600` account-sig, `0x0601` device-sig, `0x0602` list-sig). Matrix's CVE-2022-39250
  happened precisely because device ids and cross-signing key ids shared a namespace; the spec
  now mandates: refer to keys by public key, fix keys at verification start, refuse on id
  collision (Appendix B §4, C §4.2). Our `sig_IK` / `sig_DAK` payloads must carry distinct
  context labels — verify the spec's canonical bytes do this before implementing.
- WhatsApp verifies BOTH signatures **at every session setup and aborts fan-out on failure**
  (whitepaper p.14) — the enforcement point that actually stops silent device injection.
  Matches our I7 chain-verify-on-`deviceListStale`; keep it fail-closed (falsification 9).
- The 2022 Matrix attacks prove the server WILL show **different device lists to different
  users** (split view). Our §5.2 `senderListInfo` cross-check is the counter; falsification 16
  is the test that matters most. MLS transcript hashes are the gold standard if we ever want
  full agreement (Appendix C §3.3).
- WhatsApp adds freshness: signed lists expire ≤35 days; in-chat consistency data (ICDC)
  shrinks a stale sender's list TTL to ≤48h. Our spec has version stamps but no TTL — worth a
  Stage-0 note (not necessarily Phase 2 scope).

### T3 — provisioning SAS
- Matrix `m.sas.v1` is the reference flow and matches our two-round shape: **commitment**
  (hash of responder's ephemeral + full `.start` content) sent BEFORE keys are exchanged →
  attacker gets exactly one guess; SAS derived via HKDF whose info string binds BOTH ephemeral
  pubkeys, BOTH user+device ids, and the transaction id (Appendix B §4). Our
  `SAS = HKDF(S_dh, info="fp-link-sas", provisioningId‖ephPubN‖ephPubP)` binds the same
  material through the DH secret; the ZRTP-style commitment is the piece to compare against
  during Stage-0 review of §5.1.
- Emoji/decimal derivation if we want it: 42 bits → 7×6-bit emoji indexes, or 3×13-bit
  decimals +1000 (vodozemac-confirmed).
- Matrix shipped a broken MAC base64 and had to mint `hkdf-hmac-sha256.v2` — version-tag any
  MAC/KDF construction from day one.
- Signal's provisioning cipher (ephemeral-static ECDH → HKDF label
  "TextSecure Provisioning Message" → AES-256-CBC + HMAC, version byte) ships the ENTIRE
  account identity (ACI+PNI private keys) to the secondary — precedent for our IK-bearing
  blob; but Signal has NO SAS (trust = scanning the QR). Our secrets-last + SAS is strictly
  stronger (Appendix A §5).
- Transport pitfalls (Matrix to-device): at-least-once delivery, duplicates after crash,
  arrival-order only — provisioning state machines must be idempotent, one-shot commits
  (our falsification 8/18 already cover this).

### T4 — envelopes + device rooms + history reads
- Signal is the model: per-device ciphertexts, server rejects sends whose device list is
  stale — 409 missing/extra, 410 registrationId-stale — client repairs and resends
  (Appendix A §8; Sesame §3.3). Our `deviceListStale` bounce with retry cap 3 is the same
  dance with the list signature added.
- Megolm's deprecation note is a good invariant: never trust sender-asserted
  `device_id`/`sender_key` on an incoming envelope; authenticity comes from the session it
  arrived on (Appendix B §5).

### T5 — self-sync + lost-ack + sendToken
- Signal `SyncMessage.Sent`: the server **excludes the sending device** and requires every
  OTHER own device covered, else 409; a self-addressed non-sync message is rejected outright
  (`MessageSender.java:308-353`). Mirrors our origin-device scoping (§5.4's five own-sender
  guard switches) and "self-sync row never consumes pending".
- Matrix lesson (semi-trusted impersonation, CVE-2022-39249): **verify who you accept
  self-sync/forwarded material FROM**, not just who you send to — accept own-device envelopes
  only from sessions bound to our own attested device set (Appendix B §6 lesson 6).

### T6 — revocation + stale bounce
- All three production systems revoke **lazily**: Signal peers learn via the next 409
  (`extraDevices`); Megolm rotates the session and simply never shares with the revoked
  device; WhatsApp re-signs the list and lets TTL/ICDC expire stragglers. Our
  "worst case one rejected send" (§5.5) matches Signal exactly.
- EUROCRYPT 2025 found WhatsApp clients **fail to delete inbound sessions of removed
  members** — a removed device could still SEND. Our §5.5 covers server-side silence (I6);
  Stage 0 should confirm peers also drop the revoked device's inbound session material
  (falsification 7 covers receive; check the send direction).
- Megolm's rotate-on-ANY-observed-leave (even transient join/leave in a gappy sync) is the
  paranoia level required when a key, once shared, cannot be unshared.

### T7 — edit re-fan
- No primary source specifies edit re-fan semantics anywhere (explicitly UNVERIFIED in both
  A and C). Signal's `EditMessage` rides the normal send path (same 409/410 fan-out) —
  consistent with our §5.7 "edit is a full re-fan against the CURRENT device list". Our UPSERT
  + stamp-preservation rules are ahead of documented prior art; the falsification-24 suite is
  the only safety net. Inference, treat accordingly.

### T8 — harness sweep
- The bugs that actually shipped in production systems were **client-side check omissions**,
  not crypto breaks: keys accepted over the wrong channel type, unsolicited forwards accepted,
  ids confused across namespaces, checks done at display-time instead of decrypt-time
  (Appendix B §6). The harness should falsify checks at RECEIVE time.

## 4. Bearing on the two open owner decisions

**Decision 1 (deviceId reuse):** research strengthens the frozen invariant. Signal — the one
system that reuses — pairs reuse with registrationId disambiguation + total per-id state
purge + a stale-session bounce, none of which we have; Matrix documents reuse breaking
attestation state; WhatsApp/MLS/academia all recommend monotonic. Remaining choice is
allocator mechanics only (counter column vs MAX+1 tombstones), which is a §2-of-this-doc /
Stage-0 item, not a spec question.

**Decision 2 (password change vs 24h cooldown):** no analogue exists. WhatsApp's identity
reset (reinstall primary) has no cooldown and **clients do not even warn on server-initiated
identity reset by default** (EUROCRYPT 2025 §1.2); Signal re-registration is immediate with
only the safety-number banner after the fact. Our 72h ceremony + cancel + cooldown is already
stricter than the industry; whether a password change voids the cooldown is a pure product
tradeoff (attacker-cancelled-ceremony recovery speed vs an attacker who knows the password
clearing their own cooldown). Prior art neither forces nor forbids it. One relevant data
point: every production system treats "proof of account control" (re-registration w/ SMS,
reinstall) as sufficient to rebuild identity immediately — our cooldown is the conservative
outlier, and the proposed carve-out (void only cooldowns armed BEFORE the last password
change, never touching pending ceremonies) keeps it conservative.

## 5. Stage-0 agenda additions surfaced by this research

1. Domain-separation audit of every signature/KDF context string in §3/§5 canonical bytes
   (Matrix CVE-2022-39250 class). Verify no two constructions share a context.
2. Confirm revocation drops the revoked device's INBOUND session material on peers
   (EUROCRYPT 2025 "unclear enforcement" bug class).
3. Consider (note, not necessarily adopt) WhatsApp-style list TTL / in-chat consistency
   freshness — our version-stamp cross-check detects divergence but has no time bound.
4. §5.1 SAS vs m.sas.v1: compare our DH-bound derivation against ZRTP commitment shape;
   decide whether a commitment round is needed or the DH binding subsumes it (candidate for
   the `/prototype` the owner flagged).
5. Idempotency of provisioning/verification socket events under duplicate delivery
   (Matrix to-device redelivery lesson).

---



# Appendix A — Signal (Sesame, Signal-Server, libsignal)

# Signal Multi-Device Architecture — Research (Primary Sources)

Scope: How Signal handles multi-device / multi-session, to inform Fireplace Phase 2.
Sources investigated (pinned commits / revisions):
- **Sesame spec** — signal.org/docs, Revision 2, 2017-04-14.
- **Signal-Server** — github.com/signalapp/Signal-Server @ `2f482f68` (2026-08-18).
- **libsignal** — github.com/signalapp/libsignal @ v`0.101.0`.
- **Signal-Android** (libsignal-service module) — github.com/signalapp/Signal-Android (HEAD of default branch, cloned 2026-08-19).

---

## ⭐ HEADLINE ANSWER: Device IDs ARE REUSED (not monotonic)

**Signal-Server assigns the LOWEST unused device ID starting at 2, so a device ID freed by unlinking WILL be handed to the next device that links.** Device IDs are NOT monotonic and NOT globally unique over time within an account.

- `Account.getNextDeviceId()` linearly scans from `PRIMARY_ID + 1` (=2) upward and returns the first ID for which `getDevice(candidateId)` is empty. Unlinking device 2 then linking a new device reuses ID 2. (Signal-Server `storage/Account.java:315-328`)
- Because IDs are reused, on link the server **proactively clears any residual per-device state for that ID** (single-use prekeys + queued messages) before installing the new device — see `AccountsManager.addDevice` at `storage/AccountsManager.java:667-676`. This is direct evidence that ID reuse is expected and defended against.
- Consequence for peers: a reused ID is only distinguishable from the old device by its **registrationId** (random per device, see topic 8) and by the identity key / session mismatch. Sessions must be re-established because the Double Ratchet state differs.

**Design implication for Fireplace:** if you also reuse device IDs, you MUST (a) key sessions by `(accountId, deviceId, registrationId)` or force session reset on registrationId change, and (b) purge old prekeys/queued messages for a deviceId when it is reassigned.

---

## 1. Sesame algorithm — device records, sessions, fan-out, device-ID lifecycle

- **Device state model:** each device stores a set of `UserRecord`s indexed by `UserID`; each `UserRecord` holds `DeviceRecord`s indexed by `DeviceID`; each `DeviceRecord` may hold one **active session** and an ordered list of **inactive sessions**. A device keeps a `UserRecord` for its *own* UserID (to fan out to its own other devices) but does **not** store a DeviceRecord for itself. (Sesame §3.1)
- **Active/inactive convergence:** sending always uses the active session. Receiving on an inactive session activates it; an inserted (new) session becomes active and the old active moves to head of the inactive list. Devices thereby converge on a single session per remote device. (Sesame §2.1, §3.2)
- **Stale records:** a `UserRecord`/`DeviceRecord` for a deleted user/device is marked **stale** (kept to decrypt delayed messages), and may be deleted after `MAXLATENCY`. (Sesame §3.1)
- **Fan-out on send (§3.3):** input is plaintext + a set of recipient UserIDs, **including the sender's own UserID**. For each recipient UserID, for each non-stale DeviceRecord with an active session, encrypt the plaintext with that active session; send the list of `(DeviceID, ciphertext)` pairs to the server. This is per-device fan-out: one ciphertext per recipient device.
- **Server device-set enforcement (§3.3):** if the sender's DeviceID list is not current for the recipient, the server **rejects** and returns the *old* DeviceIDs and *new* DeviceIDs (plus identity public keys for new devices). The sender marks old DeviceRecords stale, "preps for encrypting" each new device (fetching a prekey bundle, creating an initiating session), and restarts the loop. This is exactly the 409/410 dance implemented in Signal-Server (topic 8).
- **DeviceID lifecycle per Sesame:** "A device will always have the same DeviceID and identity key pair (to change these for some physical device the device must be logically deleted and then added with new values)." I.e., within its lifetime a device's DeviceID is immutable; changing identity/DeviceID requires delete+re-add. Sesame also states **UserIDs may be reused** after deletion ("After a user is deleted, its UserID can be taken by a new user"). Sesame does **not** forbid DeviceID reuse; it treats a changed DeviceID/key as a delete+add. (Sesame §2.2 Devices, §3.1)
- **Per-user vs per-device identity keys:** Sesame explicitly supports both. With per-user keys all devices share one key pair (stored in UserRecords); with per-device keys each device has its own (stored in DeviceRecords). Signal uses **per-user (per-account) identity keys** — see topic 4. (Sesame §3.1)
- **X3DH/Double Ratchet instantiation (§5.2):** prekey bundle = recipient device's identity public key + signed prekey + (optional) one-time prekey. The X3DH initial message rides on every initiation message until a reply is received.
- **Simultaneous initiation:** if both sides create sessions at once, convergence takes a few messages (handled by active/inactive activation). (Sesame §2.1, §6.2)

## 2. Device ID allocation in Signal-Server (CRITICAL)

- **Constants** (`storage/Device.java:29-33`):
  - `PRIMARY_ID = 1` (the primary/first device is always id 1).
  - `MAXIMUM_DEVICE_ID = Byte.MAX_VALUE` (=127).
  - `ALL_POSSIBLE_DEVICE_IDS = [1 .. 126]` (`IntStream.range(PRIMARY_ID, MAXIMUM_DEVICE_ID)` — end-exclusive).
- **Allocation** (`storage/Account.java:315-328`):
  ```java
  public byte getNextDeviceId() {
    requireNotStale();
    byte candidateId = Device.PRIMARY_ID + 1;      // starts at 2
    while (getDevice(candidateId).isPresent()) {   // lowest UNUSED id
      candidateId++;
    }
    if (candidateId <= Device.PRIMARY_ID) { throw new RuntimeException("device ID overflow"); }
    return candidateId;
  }
  ```
  → **Lowest-free allocation ⇒ device IDs are reused after unlink, not monotonic.**
- **Where it's called (link flow):** `AccountsManager.addDevice(...)` at `storage/AccountsManager.java:660-676`:
  - `final byte nextDeviceId = account.getNextDeviceId();`
  - clears leftover prekeys + queued messages for that id (lines 667-674) — proof reuse is expected,
  - `account.addDevice(deviceSpec.toDevice(nextDeviceId, clock, account.getAccountIdentityKey()));`
- **Max device count:** `DeviceController.MAX_DEVICES = 6` (`controllers/DeviceController.java:91`). Enforced both when minting a link token (`createDeviceToken`, lines 201-203) and at link time (`linkDevice`, lines 274-276), throwing `DeviceLimitExceededException`. So even though the ID space is 1..126, an account may hold **at most 6 devices** (primary + 5 linked).
- **Primary device id:** `Device.PRIMARY_ID = 1`; `Device.isPrimary()` returns `getId() == PRIMARY_ID` (`storage/Device.java:221-223`). Every account "must have a primary device" (`Account.getPrimaryDevice`, `storage/Account.java:294-296`). Only the primary (deviceId 1) may mint link tokens (`DeviceController.createDeviceToken` line 205 rejects non-primary) and only primary (or the device itself) may unlink (topic 9).
- **Linking is token-gated:** primary calls `POST` to get a `linkDeviceToken` (HMAC over `aci + "." + timestamp` with server secret, `AccountsManager.generateLinkDeviceToken` lines 757-772); secondary presents it to `PUT /v1/devices/link` (`DeviceController.linkDevice` lines 231-297). Token is single-use (transactional condition, `LinkDeviceTokenAlreadyUsedException`).

## 3. deviceId across re-registration / identity-key change

- **Re-registration RESETS the device set to just the primary and rotates the identity key.** In `AccountsManager` "reclaim account" path (`storage/AccountsManager.java:525-560`): a brand-new `Account` object is built reusing the same ACI/PNI identifiers but:
  - `account.setIdentityKey(aciIdentityKey)` — a **new** ACI identity key,
  - `account.addDevice(primaryDeviceSpec.toDevice(Device.PRIMARY_ID, ...))` — **only the primary device (id 1)** is added; all previously linked devices are dropped.
  - `reclaimAccount(...)` (lines 603-622) first `keysManager.deleteSingleUsePreKeys(aci)`, clears PNI prekeys, `messagesManager.clear(aci)`, `profilesManager.deleteAll(...)`, then `requestDisconnection(existingAccount)` and `accounts.reclaimAccount(...)`.
  → So after re-registration, deviceId 1 persists (always primary) but every linked deviceId is gone; next links start again at 2.
- **How OTHER clients detect the change:** two independent mechanisms in the server + protocol:
  1. **Identity key (safety number) change.** The recipient's ACI identity key changed. When a peer next fetches a prekey bundle (`KeysController` returns `PreKeyResponse(identityKey, ...)`, topic 6) or receives a message header, libsignal's identity store sees a different `IdentityKey` → Sesame/`IdentityKeyStore` flags a key change and (per Sesame §6.1) the client surfaces a **safety-number change** and requires re-authentication; the old session is untrusted/replaced.
  2. **registrationId change ⇒ 410 stale.** Re-registration mints a new random `registrationId` for the primary. On the peer's next send, the server compares the client-supplied registrationId to the stored one and returns **410 staleDevices** (topic 8), forcing the peer to drop the session and re-fetch a bundle.
- Net effect: existing sessions to that account become unusable; peers must re-run X3DH after the user acknowledges the safety-number change.

## 4. Identity keys — per-account, not per-device (ACI + PNI)

- **One identity key pair per account, shared by all devices** (Sesame "per-user identity keys"). Server model: `Account` stores a single ACI identity key and a single PNI identity key, not per-device:
  - `Account.getAccountIdentityKey()` → the account's ACI `IdentityKey` (`storage/Account.java:339-342`).
  - `Account.getPhoneNumberIdentityKey()` → `Optional<IdentityKey>` PNI key (`storage/Account.java:346-349`).
  - When a device links, it is stamped with the account identity key: `deviceSpec.toDevice(nextDeviceId, clock, account.getAccountIdentityKey())` (`AccountsManager.java:676`). Devices do **not** get their own identity key.
- **Two identities per account:** ACI (account identity, `aci...`) and PNI (phone-number identity, `pni...`), each with its own identity key pair and its own per-device registrationId (`Device.getAccountRegistrationId()` vs `getPhoneNumberIdentityRegistrationId()`, used in `KeysController` lines 389-391).
- **How linked devices obtain the identity PRIVATE key:** the primary sends **both** ACI and PNI identity key pairs (public + private) to the secondary inside the encrypted provisioning message. `ProvisionMessage` proto fields (`Provisioning.proto:27-49`): `aciIdentityKeyPublic=1`, `aciIdentityKeyPrivate=2`, `pniIdentityKeyPublic=11`, `pniIdentityKeyPrivate=12`, plus `aci`, `pni`, `number`, `provisioningCode`, `profileKey`, `accountEntropyPool`, etc. So the whole account identity is cloned to the new device over the provisioning channel (topic 5).

## 5. Provisioning flow (QR-code linking)

Roles: **primary** = already-registered device; **secondary** = new device to be linked.

1. **Secondary opens a provisioning WebSocket** and generates an ephemeral `IdentityKeyPair` (its provisioning key pair). The server assigns an opaque ephemeral provisioning address (`ProvisioningAddress.address`). (`ProvisioningSocket.kt`; `Provisioning.proto:15-21`)
2. **Secondary displays a QR code** encoding the link URI:
   `sgnl://linkdevice?uuid=<ephemeralProvisioningAddress>&pub_key=<secondaryEphemeralPublicKey>[&capabilities=backup5]`
   (`ProvisioningSocket.kt:255`, `Mode.Link` at line 296).
3. **Primary scans** it, extracting `uuid` and the secondary's ephemeral public key.
4. **Primary builds a `ProvisionMessage`** containing the account's ACI+PNI identity key pairs (public+private), aci, pni, number, a `provisioningCode` (obtained from the server for that ephemeral address), profileKey/accountEntropyPool, etc. (`Provisioning.proto:27-49`)
5. **Primary encrypts it** with `PrimaryProvisioningCipher.encrypt(ProvisionMessage)` (`internal/crypto/PrimaryProvisioningCipher.java:40-56`):
   - generate ephemeral `ECKeyPair ourKeyPair`,
   - `sharedSecret = ourKeyPair.privateKey.calculateAgreement(theirPublicKey)` (ECDH with the secondary's QR public key),
   - `derivedSecret = HKDF.deriveSecrets(sharedSecret, "TextSecure Provisioning Message", 64)` → split into `cipherKey[0..32]`, `macKey[32..64]`,
   - `ciphertext = IV || AES-256-CBC/PKCS5(cipherKey, message)`,
   - `mac = HMAC-SHA256(macKey, version(0x01) || ciphertext)`,
   - `body = version(0x01) || ciphertext || mac`,
   - wrap in `ProvisionEnvelope { publicKey = ourEphemeralPublicKey, body }` and POST to the secondary's provisioning address.
6. **Secondary decrypts** with `SecondaryProvisioningCipher.decrypt` (`internal/crypto/SecondaryProvisioningCipher.kt:81-118`): checks version==1, splits `version(1) || IV(16) || ciphertext || mac(32)`, `sharedSecret = secondaryPrivateKey.calculateAgreement(primaryEphemeralPublicKey)`, same HKDF/label, verifies HMAC (constant-time `MessageDigest.isEqual`), AES-CBC-decrypts, parses `ProvisionMessage`.
7. **Secondary registers** itself as a new device via `PUT /v1/devices/link` with the `provisioningCode`/link token, uploading its own prekeys and registrationId (topic 6). Server assigns `getNextDeviceId()` (topic 2). It now holds the shared account identity private key.

Crypto summary: **ephemeral-static ECDH (Curve25519) → HKDF(label "TextSecure Provisioning Message", 64B) → AES-256-CBC + HMAC-SHA256; version byte 0x01.** There is a parallel `RegistrationProvisionMessage`/`RegistrationProvisionEnvelope` for the newer "link-and-sync during registration" flow using the identical cipher.

## 6. Per-device sessions & prekeys; multi-device bundle fetch

- **Prekeys are per (account, deviceId, identity-type).** The server stores single-use EC prekeys, a signed EC prekey, and a Kyber (KEM) prekey per device. On link, `KeysManager.buildWriteItemsForNewDevice(...)` writes the new device's keys (`AccountsManager.java:678`).
- **Bundle fetch** `GET /v2/keys/{identifier}/{device_id}` (`KeysController.getPreKeys`, lines 350-411):
  - `device_id` may be a specific byte **or `"*"` for all devices** (`parseDeviceId`, lines 413-428: `"*"` → all devices).
  - For each targeted device it calls `keysManager.takeDevicePreKeys(deviceId, targetIdentifier, ...)` and returns a `PreKeyResponseItem { deviceId, registrationId, ecSignedPreKey, ecPreKey (one-time, may be null), kemSignedPreKey }` (`entities/PreKeyResponseItem.java:36-42`).
  - `registrationId` is chosen by identity type: `case ACI -> device.getAccountRegistrationId(); case PNI -> device.getPhoneNumberIdentityRegistrationId()` (lines 389-392).
  - **Top-level identity key is the account's** (one per response, not per item): `PreKeyResponse(identityKey, responseItems)` where `identityKey` = ACI or PNI account identity key (lines 400-411). Confirms per-account identity key + per-device prekeys/registrationId.
  - A one-time EC prekey is consumed ("take") if available; otherwise only the signed prekey is returned (nullable `preKey`). Kyber last-resort prekey (`pqLastResortPreKey`) provided at device activation (`DeviceController.linkDevice` passes `aciSignedPreKey` + `aciPqLastResortPreKey`, lines 303-306).
- So a multi-device `"*"` bundle fetch returns one `PreKeyResponseItem` per device, each with that device's own signed/one-time/Kyber prekeys and registrationId, under a single shared account identity key. The sender then creates one X3DH session per device.

## 7. Sync messages (sent-sync) & note-to-self

- **Sender fans a copy of every outgoing message to its own other devices** via a `SyncMessage.Sent`. Proto `SyncMessage.Sent` (`SignalService.proto`): `destinationServiceId`, `timestamp`, `message` (the `DataMessage`), `unidentifiedStatus[]`, `isRecipientUpdate`, `editMessage` (field 10), `storyMessage`, etc. The primary/other devices apply the `Sent` as the outgoing record.
- **Server-side self-send handling:** when a client sends to its own account, it passes a `syncMessageSenderDeviceId` (its own device id). In `MessageSender.validateIndividualMessageBundle` (`push/MessageSender.java:308-353`):
  - if `syncMessageSenderDeviceId` present, it asserts every message's `sourceServiceId` is the sender's own identity, then sets `excludedDeviceId = syncMessageSenderDeviceId`;
  - `getMismatchedDevices(account, ..., excludedDeviceId)` (lines 385-426) removes `excludedDeviceId` from the account's device set, so the sender is **not required to (and must not) encrypt to itself**, but **must** cover all *other* linked devices — otherwise 409 missing/extra (topic 8).
  - Conversely, for a non-sync message addressed to the sender's own account the server rejects it (`IllegalArgumentException`, line 337) — self-messages must be flagged as sync.
- **Note-to-self** is just a conversation whose recipient is the user's own ACI; the message is encrypted to all of the user's *other* devices (sender device excluded) and rendered locally on the sending device. There is no special server primitive beyond the sync-sender exclusion above.

## 8. Stale-device handling — 409 / 410 mismatch dance

Computed in `MessageSender.getMismatchedDevices` (`push/MessageSender.java:384-426`) from the account's current device set vs the `registrationIdsByDeviceId` map the sender supplied:
- **`missingDeviceIds`** = account devices not covered by the sender's list.
- **`extraDeviceIds`** = device ids the sender addressed that the account no longer has.
- **`staleDeviceIds`** = addressed devices whose supplied `registrationId != device.getAccountRegistrationId()` (or PNI reg id) — i.e., the device re-registered/relinked.
Result carried by `MismatchedDevices(missingDeviceIds, extraDeviceIds, staleDeviceIds)` (`controllers/MismatchedDevices.java:10`).

**HTTP status mapping** (`controllers/MessageController.java:189-194, 413-431`):
- **409 Conflict** → `MismatchedDevicesResponse { missingDevices, extraDevices }` when any missing/extra (but no stale). Client must add sessions for missing devices (fetch bundles) and drop sessions for extra devices, then resend.
- **410 Gone** → `StaleDevicesResponse { staleDevices }` when any registrationId mismatch. Client must **archive/delete the stale session, re-fetch the prekey bundle, and re-encrypt** to that device, then resend.
- Multi-recipient send mirrors this: 409 `AccountMismatchedDevices[]`, 410 `AccountStaleDevices[]` per recipient (`MessageController.java:460-465, 661-688`).
- gRPC transport returns the same info via `MismatchedDevices`/`StaleDevices` messages (`grpc/MessagesGrpcHelper.buildMismatchedDevices`, lines 28-30).
This is the concrete implementation of Sesame §3.3's "old DeviceIDs / new DeviceIDs" server rejection.

## 9. Revocation (unlink) — server + client, and how fast peers stop

- **Endpoint:** `DELETE /v1/devices/{device_id}` (`DeviceController.removeDevice`, lines 149-163). Authorization: only the **primary** device, or the **device removing itself**, may unlink (`auth.deviceId() != PRIMARY_ID && auth.deviceId() != deviceId → 401`). The primary device (id 1) **cannot** be removed (`AccountsManager.removeDevice` throws `IllegalArgumentException("Cannot remove primary device")`, lines 844-847). `@ChangesLinkedDevices` bumps the account's device-list state.
- **Server-side effects** (`AccountsManager.removeDevice`, lines 858-899, under a single-account lock):
  - `keysManager.deleteSingleUsePreKeys(aci, deviceId)` and PNI equivalent — its prekeys are destroyed,
  - `messagesManager.clear(accountIdentifier, deviceId)` — its queued/undelivered messages are dropped,
  - `account.removeDevice(deviceId)` — removed from the device list (`Account.removeDevice` filters it out, `storage/Account.java:279-283`),
  - `keysManager.buildWriteItemsForRemovedDevice(...)` persists the removal transactionally,
  - `disconnectionRequestManager.requestDisconnection(accountIdentifier, List.of(deviceId))` — force-disconnects that device's live WebSocket.
- **How fast do peers stop encrypting to it?** Not instantly and not by push — it's **lazy, driven by the 409 dance**:
  - The server no longer lists the removed device. The **next time any peer sends**, its device list is stale → server returns **409 with the removed id in `extraDevices`** (topic 8) → the peer drops that session and stops encrypting to it.
  - Peers with no pending send keep a dead session until their next send attempt; there is no proactive "device revoked" broadcast to arbitrary peers. (The account's *own* other devices learn via sync/`@ChangesLinkedDevices` and updated device lists.)
- **Re-link reuses the freed id** immediately (topic 2); the new device gets a fresh registrationId, so any peer still holding the old session hits **410 stale** on next send and re-establishes.

---

## Unverified / caveats

- **UNVERIFIED (client UX specifics):** the exact client-side handling of a safety-number change (auto-reset vs. block-until-acknowledged) is asserted from Sesame §6.1 + libsignal `IdentityKeyStore` semantics, not from a specific quoted Signal-Android line in this pass. The *server* mechanisms (410 on registrationId change, new identity key in bundle) are verified.
- **UNVERIFIED (edit re-fanning end-to-end):** confirmed at the data-shape level that message edits ride as `EditMessage { targetSentTimestamp, dataMessage }` and that `SyncMessage.Sent.editMessage` (field 10) carries the sync copy; the *client* re-encrypts an edit to the same recipient device set exactly like an original message (same 409/410 fan-out). The claim that an edit is fanned identically is inferred from the shared send path + the presence of `editMessage` in `Sent`, not from a quoted client send routine.
- **UNVERIFIED (exact provisioning HTTP choreography):** the `provisioningCode` acquisition and the precise ordering of WebSocket frames were read at the cipher/proto/socket level (`ProvisioningSocket.kt`), not traced through every server endpoint. The crypto (ECDH→HKDF→AES-CBC+HMAC) is fully verified from both cipher classes.
- Sesame allows per-device OR per-user identity keys; Signal's choice of **per-user (per-account)** is verified from Signal-Server (`Account.getAccountIdentityKey` stamped onto every device) and the provisioning message shipping the account identity private key to secondaries.
- Device ID space is `1..126` (`ALL_POSSIBLE_DEVICE_IDS`), but a hard cap of **6 devices** (`MAX_DEVICES`) applies per account; the two limits are independent.

## Sources
- Sesame spec — https://signal.org/docs/specifications/sesame/ (Rev 2, 2017-04-14): §2.1, §2.2, §3.1, §3.2, §3.3, §3.4, §4.1, §5.2, §6.1, §6.2.
- Signal-Server @ 2f482f68:
  - `service/src/main/java/org/whispersystems/textsecuregcm/storage/Device.java:29-33, 221-223`
  - `service/src/main/java/org/whispersystems/textsecuregcm/storage/Account.java:272-302, 315-328, 339-349`
  - `service/src/main/java/org/whispersystems/textsecuregcm/storage/AccountsManager.java:445-446, 525-560, 603-622, 660-676, 757-772, 844-899`
  - `service/src/main/java/org/whispersystems/textsecuregcm/controllers/DeviceController.java:91, 149-163, 193-211, 231-306, 413-428`
  - `service/src/main/java/org/whispersystems/textsecuregcm/controllers/KeysController.java:350-411`
  - `service/src/main/java/org/whispersystems/textsecuregcm/controllers/MessageController.java:189-194, 413-431, 460-465, 661-688`
  - `service/src/main/java/org/whispersystems/textsecuregcm/controllers/MismatchedDevices.java:10-16`
  - `service/src/main/java/org/whispersystems/textsecuregcm/push/MessageSender.java:80, 296-353, 384-426`
  - `service/src/main/java/org/whispersystems/textsecuregcm/entities/PreKeyResponseItem.java:36-62`
  - `service/src/main/java/org/whispersystems/textsecuregcm/grpc/MessagesGrpcHelper.java:28-30`
- Signal-Android (libsignal-service):
  - `lib/libsignal-service/src/main/java/org/whispersystems/signalservice/internal/crypto/PrimaryProvisioningCipher.java:31-56`
  - `lib/libsignal-service/src/main/java/org/whispersystems/signalservice/internal/crypto/SecondaryProvisioningCipher.kt:44-118`
  - `lib/libsignal-service/src/main/java/org/whispersystems/signalservice/api/provisioning/ProvisioningSocket.kt:255, 296`
  - `lib/libsignal-service/src/main/protowire/Provisioning.proto:15-49`
  - `lib/libsignal-service/src/main/protowire/SignalService.proto` — `SyncMessage.Sent`, `EditMessage`.
- libsignal @ v0.101.0 — `rust/protocol/src/` (X3DH/PQXDH/Double Ratchet primitives; provisioning cipher lives in libsignal-service, not rust/protocol); `rust/net/src/proto/chat_provisioning.proto` (provisioning WebSocket address wrapper).



# Appendix B — Matrix (spec, vodozemac, 2022 vulnerabilities)

# Matrix Multi-Device / Multi-Session Model — Research for Fireplace Phase 2

Scope: how Matrix handles multi-device E2EE, drawn from primary sources — the
Matrix Client-Server API spec (`spec.matrix.org` / `matrix-org/matrix-spec`
source markdown), the vodozemac Rust reference source, the 2022 matrix.org
security disclosure, and the academic paper *Practically-exploitable
Cryptographic Vulnerabilities in Matrix*.

All spec quotes below are taken verbatim from the canonical spec source
(`github.com/matrix-org/matrix-spec`, `main` branch), which renders to
`spec.matrix.org/latest`. Section anchors are given for cross-reference.

Key architectural contrast with Fireplace/Signal: **In Matrix every device has
its own independent Ed25519 + Curve25519 key pair. There is NO shared account
identity key.** A "user identity" only exists as an emergent property of
cross-signing (the master key), which is layered *on top of* per-device keys.
This is the opposite of Signal's single long-term identity key shared across a
registration. This shapes every downstream decision (device lists, fan-out,
revocation).

---

## 1. Device identity & `device_id` generation / reuse

### Per-device keys (no shared identity)
- Each device has **its own Ed25519 signing key** ("This key is used as the
  fingerprint for a device by other clients, and signs the device's other keys.
  ... the private part of the key should never be exported from the device")
  and, for Olm v1, **a single Curve25519 identity key**.
  (E2EE module → *Device keys*.)
- `ed25519` + `curve25519` keys are the device keys; `signed_curve25519` keys
  are one-time / fallback keys signed by the device's Ed25519 key.
  (E2EE module → *Key algorithms*.)
- Devices upload public keys via `POST /_matrix/client/v3/keys/upload` as a
  JSON object signed by the device's Ed25519 key. (*Uploading keys*.)

### How `device_id` is generated
- Legacy Login/Registration: the homeserver **auto-generates** a new `device_id`
  unless the client supplies one. OAuth 2.0 API: the **client** always allocates
  the `device_id`.
  Verbatim (CS-API §*Relationship between access tokens and devices*):
  > "During login or registration, the generated access token should be
  > associated with a `device_id`. The legacy Login and Registration processes
  > auto-generate a new `device_id`, but a client is also free to provide its
  > own `device_id`. With the OAuth 2.0 API, the `device_id` is always provided
  > by the client. The client can generate a new `device_id` or, provided the
  > user remains the same, reuse an existing device. **If the client sets the
  > `device_id`, the server will invalidate any access and refresh tokens
  > previously assigned to that device.**"
- OAuth device-id allocation guidance (CS-API §*device_id allocation* scope
  token `urn:matrix:client:device:<device_id>`):
  > "When generating a new `device_id`, the client SHOULD generate a random
  > string with enough entropy. It SHOULD only use characters from the
  > unreserved character list defined by RFC 3986 section 2.3:
  > `unreserved = a-z / A-Z / 0-9 / \"-\" / \".\" / \"_\" / \"~\"`.
  > Using this alphabet, a 10 character string is enough to stand a sufficient
  > chance of being unique per user. The homeserver MAY reject a request for a
  > `device_id` that is not long enough or contains characters outside the
  > unreserved list."
- `device_id` scope (top-level spec §*Devices*):
  > "Devices are identified by a `device_id`, which is unique within the scope
  > of a given user."

### Reuse is explicitly allowed — but discouraged with new keys
- Reuse is **explicitly permitted** by the spec. Verbatim (older wording,
  `spec.matrix.org/v1.11`, quoted in Synapse issue #17375):
  > "A client is also free to generate its own device_id or, provided the user
  > remains the same, reuse a device: in either case the client should pass the
  > device_id in the request body."
- The **anti-reuse guidance** appears in the top-level *Devices* concept
  section — the canonical verbatim warning:
  > "When a user first uses a client, it registers itself as a new device. The
  > longevity of devices might depend on the type of client. **A web client will
  > probably drop all of its state on logout, and create a new device every time
  > you log in, to ensure that cryptography keys are not leaked to a new user.**
  > In a mobile client, it might be acceptable to reuse the device if a login
  > session expires, provided the user is the same."
- On **soft logout** the spec is emphatic that state must NOT be reused unless
  `soft_logout: true` (CS-API §*Soft logout*):
  > "If the `soft_logout` parameter is omitted or is `false`, this means the
  > server has destroyed the session and the client should not reuse it. That
  > is, **any persisted state held by the client, such as encryption keys and
  > device information, must not be reused and must be discarded.** If
  > `soft_logout` is `true` the client can reuse any persisted state."

### WHY reusing a `device_id` with *different* keys is dangerous
The spec does not contain a single dedicated "do not reuse device_id with
different keys" warning box; the concrete failure mode is documented in the
Matrix issue tracker (Synapse issue #17375, *"self_signing signatures are not
deleted when their device is deleted"*, verbatim):
> "Once a device has been signed with the self_signing key (i.e. verified),
> that signature persists even after the device has been deleted (e.g. forcibly
> logged out from another client). If the deleted device id is then reused when
> logging in a new device, the old signature will reappear on the new device.
> Consequently, **any client that performs validation on the new device's
> signatures will find at least one bad one made by that account's own keys.
> This can generate warnings, errors, or unexpected verification/trust status
> indicators targeting the new device.**"

**Design lesson for Fireplace:** because cross-signing signatures are keyed by
`(user_id, device_id)` and persist server-side after device deletion, reusing a
`device_id` with fresh keys causes *stale attestations to reattach* to the new
keys, producing bad-signature / trust warnings. Matrix's own practical advice is
to **mint a fresh, high-entropy `device_id` on every new login/session** rather
than reuse one across an account reset. If Fireplace reuses `deviceId` across
resets it MUST also purge every server-side signature/attestation bound to that
id, or verifiers will reject the new device.

---

## 2. Device lists: `/keys/query`, `/keys/changes`, `changed`/`left` tracking

### Endpoints
- `POST /_matrix/client/v3/keys/query` — fetch a user's devices + their identity
  keys (and cross-signing keys). Pass target user IDs in the `device_keys`
  request parameter. This is the authoritative source of a user's device set.
- `POST /_matrix/client/v3/keys/claim` — claim a one-time key for a specific
  device to bootstrap an Olm session. Servers MUST ensure each OTK is claimed at
  most once.
- `GET /_matrix/client/v3/keys/changes?from=&to=` — list users whose device
  lists changed between two sync tokens; used after client restart to catch up.

### The tracking algorithm (E2EE module → *Tracking the device list for a user*)
Verbatim procedure:
1. Client sets a persistent "tracking Bob" flag and a separate persistent
   "outdated" flag. "Both flags should be in storage which persists over client
   restarts."
2. Calls `/keys/query` for Bob, stores the device list, clears "outdated".
3. "During its normal processing of responses to `/sync`, Alice's client
   inspects the `changed` property of the `device_lists` field. If it is
   tracking the device lists of any of the listed users, then it marks the
   device lists for those users outdated, and initiates another request to
   `/keys/query` for them."
4. Periodically persists `next_batch`; after a restart calls `/keys/changes`
   with the stored token as `from` to find users changed while offline, marks
   them outdated, and re-queries.

### `device_lists` in `/sync` (E2EE module → *Extensions to /sync*)
```json
"device_lists": { "changed": ["@alice:example.com"], "left": ["@bob:example.com"] }
```
- `changed`: "List of users who have updated their device identity or
  cross-signing keys, or who now share an encrypted room with the client since
  the previous sync response."
- `left`: "List of users with whom we do not share any encrypted rooms anymore
  since the previous sync response." (Client should stop tracking them.)
- Only populated on **incremental** sync (`since` present); after an initial
  sync clients use `/keys/query` or `/keys/changes`.
- Re-sharing edge case (spec note): when Alice leaves then re-joins a shared
  room after adding a device, "Bob's homeserver will add Alice's user ID to the
  `changed` property" so Bob refreshes.

### Concurrency hazard (verbatim warning box)
> "Bob may update one of his devices while Alice has a request to `/keys/query`
> in flight ... **Clients MUST guard against these situations.** For example, a
> client could ensure that only one request to `/keys/query` is in flight at a
> time for each user, by queuing additional requests until the first
> completes." (Two failure modes: clearing 'outdated' after a stale first
> response, and out-of-order completion overwriting newer results.)

### What stops a malicious homeserver adding a device? — **Nothing, without cross-signing.**
- The homeserver is the sole transport for `/keys/query` results, so a malicious
  server can inject a device it controls into a user's device list. The E2EE
  §*Recommended client behaviour* states plainly:
  > "Non-cross-signed devices don't provide any assurance that the device
  > belongs to the user, and **server admins can trivially create new devices
  > for users.**"
- Mitigation is behavioural, not structural: clients SHOULD NOT send room keys
  or secrets to non-cross-signed devices, and SHOULD NOT display messages from
  non-cross-signed devices:
  > "Clients SHOULD NOT send encrypted to-device messages, such as room keys or
  > secrets, to non-cross-signed devices by default. ... messages sent from
  > non-cross-signed devices cannot be trusted and SHOULD NOT be displayed to
  > the user."
- The academic paper confirms the homeserver can even show **different device
  lists to different users** ("When a user requests their own device list, the
  homeserver does not include the unverified device. When a different user
  requests the list, the homeserver includes an unverified device that they
  control."). See §6.

**Design lesson:** a signed device list on the server is only as trustworthy as
the signature chain rooted in a key the *user* controls (cross-signing master
key). The transport (homeserver) must be assumed hostile and cannot be the
root of trust.

---

## 3. Cross-signing (master / self-signing / user-signing)

(E2EE module → *Cross-signing*.)

### Three Ed25519 key pairs per user
- **Master signing key (MSK / `master_key`)** — "serves as the user's identity
  in cross-signing and signs their user-signing and self-signing keys." Rarely
  used → minimal attack surface. May also be signed by the user's own device
  keys to migrate from device-level verification.
- **User-signing key (USK)** — "only visible to the user that it belongs to —
  that signs other users' master signing keys." (Signatures made by USK are
  hidden from everyone else, to avoid leaking social graphs.)
- **Self-signing key (SSK)** — "signs the user's own device keys."

### Upload & attestation
- Uploaded via `POST /_matrix/client/v3/keys/device_signing/upload`.
- New-device attestation chain — Alice trusts Bob's device iff:
  1. Alice's MSK has signed her USK,
  2. Alice's USK has signed Bob's MSK,
  3. Bob's MSK has signed Bob's SSK,
  4. Bob's SSK has signed Bob's device key.
- When a new device logs in, an existing device signs it with the **SSK** (after
  the user unlocks/holds the SSK private part, typically via Secret Storage);
  that single signature makes it trusted by everyone who already trusts the MSK.
  No pairwise re-verification is needed — that is the entire point of
  cross-signing.
- On upload, "Alice's user ID will appear in the `changed` property of the
  `device_lists` field of the `/sync` response of all users who share an
  encrypted room with her", triggering a `/keys/query`.

### Private-key storage / sharing
- Private halves may be stored server-side (encrypted) via the **Secrets**
  module, or shared to other devices via **Secret Sharing**, under names
  `m.cross_signing.master`, `m.cross_signing.user_signing`,
  `m.cross_signing.self_signing` (base64 before encryption).

### Key/signature security (verbatim, relevant to §4 and §6 attacks)
- "A user's master signing key could allow an attacker to impersonate that user
  ... clients must ensure that the private part of the master signing key is
  treated securely. If clients do not have a secure means of storing the master
  signing key ... clients must not store the private part."
- "If a user's client sees that any other user has changed their master key,
  that client must notify the user about the change before allowing
  communication between the users to continue."
- USK/SSK are "easily replaceable if they are compromised by re-issuing a new
  key signed by the user's master signing key" — the split exists so a
  compromised SSK/USK can be rotated without discarding identity (the MSK).

### "Unverified device" meaning
An **unverified device** is a device whose device key is **not** covered by a
valid SSK→device signature chain rooted in a trusted MSK (either because
cross-signing signatures are absent, or the MSK itself was never verified /
TOFU-trusted). Clients warn on these because there is no cryptographic assurance
the device belongs to the claimed user — the server could have injected it (§2,
§6).

---

## 4. SAS verification (`m.sas.v1`) — full message sequence & anti-MITM binding

(E2EE module → *Key verification framework* + *Short Authentication String
(SAS) verification*.) Modeled on ZRTP; the hash-commitment gives the attacker
"essentially only one attempt to attack the Diffie-Hellman exchange."

### Framework handshake (before SAS-specific messages)
`m.key.verification.request` → `.ready` → `.start` (method `m.sas.v1`) →
… method messages … → `.done` (both sides). Cancel any time via `.cancel`.
- Session ID = event ID (in-room) or shared `transaction_id` (to-device).
- **Self-verification of one's own devices uses to-device messages**;
  cross-user verification uses in-room messages. (Directly relevant to Fireplace
  provisioning between a user's own devices → to-device transport, see §7.)
- To-device to unknown device: Alice sends `request` to **all** of Bob's
  devices with one shared `transaction_id`; when one accepts, others are
  cancelled with code `m.accepted` (accept) / `m.user` (reject).
- Glare rule: if both send `.start` with the same method, the message from the
  **lexicographically larger user ID** (or device ID for self-verify) is
  ignored.

### SAS-specific message sequence (verbatim step order)
Two phases: (1) key agreement (ZRTP-style), (2) key verification (HMAC).
```
 AliceDevice                         BobDevice
   | -- m.key.verification.start ------> |   (Alice; has Bob's device key)
   | <-- m.key.verification.accept ----- |   (Bob picks protocol/hash/MAC/SAS;
   |                                     |    sends COMMITMENT hash)
   | -- m.key.verification.key --------> |   (Alice's ephemeral pubkey K_A^pub)
   | <-- m.key.verification.key -------- |   (Bob's ephemeral pubkey K_B^pub)
   | -- m.key.verification.mac --------> |   (MACs of keys + key-id list)
   | <-- m.key.verification.mac -------- |
   | -- m.key.verification.done -------> |
   | <-- m.key.verification.done ------- |
```
Detailed steps (spec, condensed verbatim):
1. Establish secure out-of-band channel (in person / video); "secure" = cannot
   be impersonated.
2–3. Alice `.start`; ensures she has Bob's device key.
4. Bob selects key-agreement protocol, hash, MAC, SAS method.
5–6. Bob ensures he has Alice's device key; creates ephemeral Curve25519 pair
   (K_B^priv, K_B^pub); **computes the hash of K_B^pub**.
7–8. Bob `.accept` carrying the **commitment** = hash(K_B^pub ‖ canonical JSON
   of Alice's `.start` body). Alice stores commitment.
9. Alice creates ephemeral pair; `.key` with K_A^pub.
10. Bob `.key` with K_B^pub.
11. **Alice verifies the stored commitment matches hash of the just-received
    K_B^pub and the content of her own `.start`** ← anti-MITM binding; a MITM
    that swapped K_B could not have precomputed a matching commitment.
12. Both compute ECDH: `ECDH(K_A^priv, K_B^pub)` = `ECDH(K_B^priv, K_A^pub)` =
    shared secret.
13. Both derive the SAS (emoji/decimal) from the shared secret via HKDF and
    display it.
14. Users compare strings out-of-band; tell devices match/mismatch.
15–17. On match, each side computes MACs over (a) each key they want verified
    (device Ed25519 key **and master signing key** — MSK SHOULD be included for
    cross-user), and (b) the sorted list of key IDs; exchange `.mac`; each side
    recomputes and compares.
18. Both `.done`.
SAS-specific cancel codes: `m.unknown_method`, `m.mismatched_commitment`,
`m.mismatched_sas`. Timeout 10 min.

### SAS HKDF derivation (info string) — verbatim
HKDF (RFC 5869), agreed hash, **shared secret as IKM, no salt**. For
`key_agreement_protocol = curve25519-hkdf-sha256`, the info is the
concatenation of (each `|`-separated):
- `MATRIX_KEY_VERIFICATION_SAS|`
- Matrix ID of the `.start` sender + `|`
- Device ID of the `.start` sender + `|`
- `.start` sender's `.key` public key (unpadded base64) + `|`
- Matrix ID of the `.accept` sender + `|`
- Device ID of the `.accept` sender + `|`
- `.accept` sender's `.key` public key (unpadded base64) + `|`
- the `transaction_id`.

**Anti-MITM binding note:** the info string binds the SAS to *both* ephemeral
public keys, *both* user+device IDs, and the transaction ID. Combined with the
commitment (step 11), a MITM cannot substitute keys without changing the
displayed SAS. The deprecated bare `curve25519` method omits the public keys
from the info and is discouraged.

### `decimal` SAS
Generate 5 bytes via HKDF; take three 13-bit sequences → three numbers 0–8191;
add 1000 each. Bit ops (B0..B4):
- 1st: `(B0<<5 | B1>>3) + 1000`
- 2nd: `((B1&0x7)<<10 | B2<<2 | B3>>6) + 1000`
- 3rd: `((B3&0x3F)<<7 | B4>>1) + 1000`

### `emoji` SAS
Generate 6 bytes via HKDF; split first **42 bits into 7 groups of 6 bits**;
each 6-bit number indexes the 64-entry SAS emoji table
(`data-definitions/sas-emoji.json`). Confirmed in vodozemac
(`src/sas.rs` `bytes_to_emoji_index`: "Split the first 42 bits of our 6 bytes
into 7 groups of 6 bits", masking with `& 63`), and `bytes_to_decimal` ignores
the 6th byte.

### MAC calculation (`hkdf-hmac-sha256.v2`) — verbatim
HMAC key via HKDF-SHA256 (shared secret as IKM, no salt), info =
concatenation of:
- `MATRIX_KEY_VERIFICATION_MAC`
- Matrix ID of the user whose key is being MAC-ed
- Device ID of the device **sending** the MAC
- Matrix ID of the other user
- Device ID of the device **receiving** the MAC
- the `transaction_id`
- the Key ID being MAC-ed, or the literal string `KEY_IDS` for the key-id list.
Then HMAC-SHA256 over the unpadded-base64 public key (or the sorted,
comma-separated `{algorithm}:{keyId}` list, e.g.
`ed25519:Cross+Signing+Key,ed25519:DEVICEID`), base64-encoded into `.mac`.
- **Gotcha (verbatim):** "The MAC method `hkdf-hmac-sha256` used an incorrect
  base64 encoding, due to a bug in the original implementation in libolm. To
  remedy this, `hkdf-hmac-sha256.v2` was introduced ... `hkdf-hmac-sha256` is
  deprecated ... if both parties support `hkdf-hmac-sha256.v2`, then
  `hkdf-hmac-sha256` MUST not be used." **Fireplace SAS design should implement
  v2 only.**

### Cross-signing key IDs collide with device IDs (critical anti-MITM rule — see §6)
> "While servers MUST not allow devices to have the same IDs as cross-signing
> keys, a malicious server could construct such a situation, so clients must not
> rely on the server being well-behaved and should take the following
> precautions: 1. Clients MUST refer to keys by their public keys during the
> verification process, rather than only by the key ID. 2. Clients MUST fix the
> keys that are being verified at the beginning of the verification process, and
> ensure that they do not change in the course of verification. 3. Clients
> SHOULD also display a warning and MUST refuse to verify a user when they
> detect that the user has a device with the same ID as a cross-signing key."

---

## 5. Megolm sender-key model vs pairwise fan-out; revocation & rotation

(E2EE module → `m.megolm.v1.aes-sha2`, *Sharing keys between devices*,
`m.olm.v1.curve25519-aes-sha2`.)

### The two-layer model (Olm pairwise + Megolm group)
- **Olm** (`m.olm.v1.curve25519-aes-sha2`) is the pairwise Double-Ratchet
  channel between two *devices*. Encrypted to-device `m.room.encrypted` payload
  keys ciphertext by the **recipient device's Curve25519 key**:
  ```json
  { "algorithm":"m.olm.v1.curve25519-aes-sha2","sender_key":"<curve25519>",
    "ciphertext": { "<device_curve25519_key>": { "type":0|1, "body":"<olm msg>" } } }
  ```
- **Megolm** (`m.megolm.v1.aes-sha2`) is a *sender-key* group ratchet: the
  sender creates one outbound session per room and distributes the inbound
  session key **once per recipient device** via an Olm-encrypted `m.room_key`
  to-device message. Actual room messages are then a single Megolm ciphertext
  posted to the room (not fanned out).
- This is the key difference from Fireplace's per-message pairwise fan-out:
  Matrix fans out only the **session key** (O(devices)) via Olm, then room
  messages are **one** Megolm ciphertext for the whole room. Fireplace's Signal
  pairwise model instead re-encrypts each message per recipient device.

### Room-key sharing to each device
- `m.room_key` (Olm/to-device) delivers the Megolm session. Spec: "When creating
  a Megolm session in a room, clients must share the corresponding session key
  using Olm with the intended recipients." **"When a client receives a Megolm
  session, the client MUST ensure that the session was received via an Olm
  channel"** (this exact check is what matrix-js-sdk failed → §6 Trusted
  Impersonation).
- `m.room_key_request` / `m.forwarded_room_key` — on-demand key backfill to a
  new device. Spec warning: "Clients should only send keys requested by the
  verified devices of the same user, and should only request and accept
  forwarded keys from verified devices of the same user."
- `m.room_key.withheld` — signal to a device *why* it is not getting the key
  (e.g. code `m.unverified` for a non-cross-signed device).
- The room ID is embedded inside every Megolm plaintext ("otherwise the
  homeserver would be able to change the room a message was sent in").
- **Deprecation (v1.3):** `sender_key` and `device_id` on Megolm events are
  deprecated and "MUST NOT be used to verify the message's source"; lookups must
  key on the globally-unique `session_id` only. Sender authenticity comes from
  the Olm channel the key arrived on + validation checks (see below).

### Self-sync to own devices
- Same mechanism: a user's own devices are just other recipients of the
  `m.room_key` Olm messages and of key backup / secret sharing. New devices
  recover history via `m.room_key_request` to the user's other **verified**
  devices, or via server-side key backup (`m.megolm_backup.v1.curve25519-aes-sha2`),
  or via encrypted key export files. `m.dummy` re-establishes a broken Olm
  session.

### Incoming-event validation (v1.15/v1.19 — MUST checks)
After Olm decryption clients MUST verify: `sender` matches, decrypted
`keys.ed25519` matches the sending device's Ed25519 key, `recipient` = local
user, `recipient_keys.ed25519` = local device key, and if `sender_device_keys`
is present it must be self-consistent **and carry a valid signature from the
sending device's Ed25519 key**. "Any event that does not comply with these
checks MUST be discarded." Ownership of the Curve25519 key is established via
cross-signing (SSK-signed device keys, MSK trusted) or explicit verification.

### Device/user revocation → Megolm rotation (verbatim triggers)
Clients MUST rotate (discard + create + re-share a new outbound Megolm session)
whenever any of:
- The session exceeds `rotation_period_ms` from the room's `m.room.encryption`
  state event (or a default), **or**
- The session has encrypted `rotation_period_msgs` messages (or a default),
  **or**
- "**A user or device that was previously participating in the room, and may
  have received a copy of the decryption keys for the session, is seen to leave
  the room.**" (v1.19) Clients MUST watch state changes; on a `limited` sync any
  membership `!= join` must be treated as a possible join-then-leave and trigger
  rotation. **or**
- (v1.19) history-visibility change affecting the `shared_history` flag.

`m.room.encryption` fields: `rotation_period_ms`, `rotation_period_msgs`.
**Per-device forwarding rule:** a new session is Olm-shared only to the
*current* device set; a revoked device simply never receives the new session
key, so it can decrypt history it already has but nothing after rotation. There
is no cryptographic "delete key from a device" — revocation = rotate-and-don't-
share.

**Design lesson for Fireplace:** if adopting a Megolm-style sender-key group
session (instead of per-message pairwise fan-out), revocation MUST force a
session rotation on membership/device-list changes, and MUST rotate on *any*
observed leave (even transient join/leave in a gappy sync), or a departed device
retains the ability to decrypt future traffic. New sessions must only be shared
to correctly cross-signed / verified devices.

---

## 6. The 2022 vulnerabilities — lessons for ANY signed-device-list design

Sources: matrix.org disclosure (2022-09-28) and *Practically-exploitable
Cryptographic Vulnerabilities in Matrix* (Albrecht, Celi, Dowling, Jones;
eprint 2023/485). All attacks **require a malicious/colluding homeserver**.

### The two attacks most relevant to a signed-device-list design
- **Homeserver Control of Room Membership / device lists** (design flaw, "not
  fixed at disclosure"; accepted risk + partial mitigation): The homeserver
  controls the device list returned by `/keys/query` and room membership events,
  neither of which are authenticated. It can (a) add a homeserver-controlled
  user to a room, or (b) add a homeserver-controlled **device** to a victim's
  account; existing members share inbound Megolm sessions with it, breaking
  confidentiality. Crucially, the paper shows the server can present **divergent
  device lists to different users** to suppress the victim's own
  new-device-verification prompt: "When a user requests their own device list,
  the homeserver does not include the unverified device. When a different user
  requests the list, the homeserver includes an unverified device that they
  control." Only defense is cross-signing + strict "don't send/accept to
  non-cross-signed devices" enforcement.
- **Semi-trusted Impersonation** (CVE-2022-39249 / -39257 / -39246, moderate):
  matrix-js-sdk *accepted forwarded room keys it never requested*. No
  verification of *who keys are accepted from* (only who they're sent to). An
  attacker could push attacker-controlled Megolm sessions to a device claiming
  they belong to an impersonated device; messages then authenticate as the
  impersonated sender (behind the generic "authenticity can't be guaranteed"
  warning). Root cause: "lack of guidance on the processing of incoming key
  shares in spec." Fix: reject unsolicited/unsafe key forwards (except the
  invite-time history-sharing bundle); Olm/Megolm v2 will "link key-sending
  events to the underlying recipient Olm identity."

### The other three (context)
- **Key/Device Identifier Confusion in SAS** (CVE-2022-39250, critical,
  matrix-js-sdk only): device IDs and cross-signing key IDs share a namespace;
  the client confused them so a malicious server could get a target to sign a
  server-controlled cross-signing identity, enabling MITM. → This is exactly why
  the spec now mandates the §4 rules: refer to keys by public key, fix keys at
  the start, refuse if a device ID equals a cross-signing key ID.
- **Trusted Impersonation** (CVE-2022-39251/-39255/-39248, critical): the client
  accepted to-device room keys encrypted with **Megolm instead of Olm**,
  attributing them to the Megolm sender. → Spec now: "the client MUST ensure
  that the session was received via an Olm channel." A "Malicious key backup"
  variant leveraged the same bug to set a victim's backup key.
- **IND-CCA break** (theoretical): AES-CTR IV not covered by the MAC in SSSS /
  key backups / attachments.

### Distilled design lessons for Fireplace's signed device list
1. **The transport/server is untrusted and is not the root of trust.** A device
   list signed by the *server* proves nothing. Root trust in a **user-held**
   key (cross-signing master equivalent) and verify the full signature chain
   client-side.
2. **A device is only usable once its key is attested by that chain.** Do not
   send room/session keys to, nor render messages from, un-attested devices.
   "Server admins can trivially create new devices for users."
3. **Assume the server shows different views to different clients.** Do not rely
   on the victim's own client seeing an injected device. TOFU-pin identities and
   surface any master-key change loudly ("must notify the user about the change
   before allowing communication to continue").
4. **Enforce domain separation of identifiers.** Never let a device ID and an
   identity/cross-signing key ID be interchangeable; bind verification to
   **public keys**, fix them at session start, and abort on collision.
5. **Authenticate the channel a key arrives on, not just that it is encrypted.**
   Check the *type* of channel (pairwise-authenticated) — "no check is performed
   to check whether Olm is used for encryption or not" was the critical bug.
6. **Verify who you accept keys FROM, not only who you send to.** Only accept
   forwarded/self-sync keys from verified devices of the same user.
7. **Check crypto at receive/decrypt time, not display time.** Element's
   check-at-display design enabled the trust-upgrade confusion.
8. **Authenticate membership/device-list mutations cryptographically.** Matrix's
   unauthenticated room-management + device-list messages are the unfixed design
   flaw; the planned fix is "cryptographic signatures to membership events." A
   signed-device-list design should sign membership/device changes with a
   user-controlled key so the server cannot forge additions.

---

## 7. To-device messages — provisioning/verification transport

(CS-API §*Send-to-Device messaging* + E2EE usage.)

### Purpose & shape
- `PUT /_matrix/client/v3/sendToDevice/{eventType}/{txnId}` sends signalling
  messages that are **not** persisted in room history — "one-time authentication
  tokens or key data." Explicitly "not intended for conversational data."
- Delivered **exactly once** per device. One message per device per transaction,
  all with the same event type. `device_id` may be `*` = broadcast to all
  known devices of the target user(s).
- Received via the `to_device.events` array in `/sync`. Each event carries
  `sender`, `type`, `content`. Clients must ignore unknown `type`s.

### Ordering & delivery semantics (server behaviour — verbatim)
- "Servers should store pending messages for local users until they are
  successfully delivered to the destination device."
- **Ordering is arrival-order, best-effort:** "the server should list the
  pending messages, **in order of arrival**, in the response body."
- **At-least-once → exactly-once via ack:** "When the client calls `/sync`
  again with the `next_batch` token from the first response, the server should
  infer that any send-to-device messages in that response have been delivered
  successfully, and delete them from the store." (So if the client dies before
  advancing the token, messages are **redelivered** — clients must be
  idempotent.)
- "If there is a large queue ... the server should limit the number sent in each
  `/sync` response. 100 messages is recommended." (Large key dumps get
  paginated across syncs.)
- Cross-domain messages are relayed via federation
  (`server-server-api#send-to-device-messaging`).

### Encryption
- To-device messages are **not encrypted by the transport**. Sensitive payloads
  (room keys, secrets, some verification content) are wrapped in **Olm**
  (`m.room.encrypted` with `m.olm.v1.curve25519-aes-sha2`) end-to-end before
  being sent to-device. Verification handshake messages are typically sent
  **unencrypted** to-device (they are protected by the SAS commitment + MAC, not
  by transport encryption).

### Verification / provisioning use
- Verifying **a user's own devices** MUST use to-device messages (in-room is for
  cross-user). This is the transport Fireplace provisioning SAS should use for
  device-to-device pairing.
- When Alice doesn't know which of Bob's devices to verify, she sends the
  to-device `m.key.verification.request` to **all** his devices with one shared
  `transaction_id`; non-accepting devices are cancelled (`m.accepted`/`m.user`).

### Known pitfalls
- **Redelivery / idempotency:** because deletion is tied to `/sync` token
  advancement, a client crash re-receives messages; verification/provisioning
  state machines must tolerate duplicates and out-of-window `transaction_id`s
  (spec: expire an unused `transaction_id` after 10 min; cancel unknown ones).
- **No transport authentication:** the server sees sender/type metadata and can
  drop, reorder (within arrival batching), or inject to-device messages ⇒
  payload-level Olm + the §6 "must be an Olm channel" check are mandatory.
- **Ordering is not causal**, only arrival-order best-effort and possibly
  reordered across sync pages ⇒ do not assume strict ordering for multi-message
  protocols; carry explicit sequence/step identifiers.
- Synapse prioritises outbound to-device over device-list updates
  (matrix-org/synapse PR #13922) — a real-world scheduling nuance, not a spec
  guarantee.

---

## UNVERIFIED / caveats
- The exact **default** values for `rotation_period_ms` / `rotation_period_msgs`
  when absent from `m.room.encryption` are described in spec only as "an
  appropriate default"; commonly-cited values (1 week / 100 msgs) come from
  Element/implementation config, **not** normative spec text — treat as
  implementation-defined. [UNVERIFIED against a normative spec constant.]
- The claim that reusing a `device_id` with different keys triggers verification
  warnings is grounded in Synapse issue #17375 (a defect report about persistent
  self-signing signatures), not in a dedicated spec warning box. The spec's
  normative guidance is the softer "create a new device every time you log in
  to ensure that cryptography keys are not leaked to a new user" (§Devices) and
  the soft-logout "must not be reused and must be discarded." [Behaviour
  verified via the issue; a single canonical spec warning sentence does not
  exist.]
- vodozemac code was read from `main` (not a pinned release tag); line-level
  behaviour (`bytes_to_emoji_index`, `bytes_to_decimal`) matches the spec but
  exact line numbers may drift across commits.

---

## Sources
- Matrix Client-Server API — End-to-End Encryption module (source of truth):
  https://raw.githubusercontent.com/matrix-org/matrix-spec/main/content/client-server-api/modules/end_to_end_encryption.md
  (renders at https://spec.matrix.org/latest/client-server-api/#end-to-end-encryption)
  Anchors used: `#device-keys`, `#tracking-the-device-list-for-a-user`,
  `#e2e-extensions-to-sync`, `#device-verification`, `#key-verification-framework`,
  `#short-authentication-string-sas-verification`, `#sas-hkdf-calculation`,
  `#mac-calculation`, `#cross-signing`, `#key-and-signature-security`,
  `#sharing-keys-between-devices`, `#mmegolmv1aes-sha2`,
  `#molmv1curve25519-aes-sha2`, `#recommended-client-behaviour`.
- Matrix top-level spec — *Devices* concept:
  https://raw.githubusercontent.com/matrix-org/matrix-spec/main/content/_index.md (lines 181–207)
  (https://spec.matrix.org/latest/#devices)
- Matrix CS-API — *Relationship between access tokens and devices*, *Soft
  logout*, OAuth *device_id allocation* scope:
  https://raw.githubusercontent.com/matrix-org/matrix-spec/main/content/client-server-api/_index.md
  (lines ~610–617, ~660–671, ~2371–2390)
- Matrix CS-API — Send-to-Device messaging module:
  https://raw.githubusercontent.com/matrix-org/matrix-spec/main/content/client-server-api/modules/send_to_device.md
- Keys API definitions (`/keys/upload`, `/keys/claim`, `/keys/changes`,
  `device_keys`):
  https://raw.githubusercontent.com/matrix-org/matrix-spec/main/data/api/client-server/keys.yaml
  https://raw.githubusercontent.com/matrix-org/matrix-spec/main/data/api/client-server/definitions/device_keys.yaml
- vodozemac (Rust reference for Olm/Megolm/SAS) — SAS derivation:
  https://raw.githubusercontent.com/matrix-org/vodozemac/main/src/sas.rs
  (`bytes_to_emoji_index` ~lines 169–190, `bytes_to_decimal` ~line 197)
- MSC1756 (cross-signing proposal):
  https://github.com/matrix-org/matrix-spec-proposals/blob/old_master/proposals/1756-cross-signing.md
- Synapse issue #17375 — device_id reuse / stale self_signing signatures:
  https://github.com/element-hq/synapse/issues/17375
- matrix.org disclosure (2022-09-28) — "Upgrade now to address E2EE
  vulnerabilities in matrix-js-sdk, matrix-ios-sdk and matrix-android-sdk2":
  https://matrix.org/blog/2022/09/28/upgrade-now-to-address-encryption-vulns-in-matrix-sdks-and-clients/
- Academic paper — *Practically-exploitable Cryptographic Vulnerabilities in
  Matrix* (Albrecht, Celi, Dowling, Jones):
  https://nebuchadnezzar-megolm.github.io/  ·  https://eprint.iacr.org/2023/485.pdf
- CVEs: CVE-2022-39250 (SAS id confusion), CVE-2022-39251/-39255/-39248 (Trusted
  Impersonation), CVE-2022-39249/-39257/-39246 (Semi-trusted Impersonation).



# Appendix C — WhatsApp, iMessage+CKV, MLS, attack literature

# Multi-Device E2EE Beyond Signal/Matrix — Industry & Attack-Literature Research

Scope: WhatsApp multi-device, iMessage + Contact Key Verification, MLS (RFC 9420) membership model, and the academic attack literature on device lists / sender keys. Prepared to inform Fireplace Phase-2 multi-device design (per-device identity keys, signed device lists, provisioning/SAS, per-device envelopes & fan-out, self-sync, revocation, edit re-fanning).

All claims cite primary sources (whitepaper page numbers, RFC section numbers, paper titles/venues). Items I could not verify against a primary source are marked **[UNVERIFIED]**.

---

## 1. WhatsApp Multi-Device — Account Signature / Device Signature scheme

Primary source: **WhatsApp Encryption Overview, Technical White Paper, Version 9 (updated Feb 25, 2026)**, https://www.whatsapp.com/security/WhatsApp-Security-Whitepaper.pdf (page numbers below refer to that PDF's printed page markers).

### 1.1 Per-device identity keys (the multi-device change)
- Pre-multi-device, "everyone on WhatsApp was identified by a single identity key from which all encrypted communication keys were derived." With multi-device, **each device has its own Identity Key Pair (long-term Curve25519), generated at install/link time** (p.3 "Messaging Security"; p.4 "Public Key Types"). The server maintains the mapping between an account and all its device identities.
- Device roles: a **Primary device** registers the account with a phone number; **Companion devices** are linked by the primary. Each account has exactly one primary (p.3 "Device Types").
- Each device registers: public Identity Key, public Signed Pre Key (Curve25519, signed by the Identity Key), and a batch of One-Time Pre Keys (p.5 "Client Registration").

### 1.2 The two signatures (exact byte constructions)
When linking a companion (p.4–6):
- **Account Signature** — primary signs the companion's identity key:
  `Asignature = CURVE25519_SIGN(Iprimary, ACCOUNT_SIGNATURE_PREFIX || Lmetadata || Icompanion)`
  where `ACCOUNT_SIGNATURE_PREFIX = 0x0600` (or `0x0605` if the companion is Cloud API).
- **Device Signature** — companion signs the primary's identity key (plus itself):
  `Dsignature = CURVE25519_SIGN(Icompanion, DEVICE_SIGNATURE_PREFIX || Lmetadata || Icompanion || Iprimary)`
  where `DEVICE_SIGNATURE_PREFIX = 0x0601` (or `0x0606` if the companion is Cloud API).
- `Lmetadata` = "Linking Metadata", an encoded blob assigned to the companion at linking time; used together with `Icompanion` to identify the linked companion (p.4 "Companion Linking").
- The construction is a **bidirectional cross-signature**: primary attests "this companion key belongs to my account"; companion attests "I acknowledge this primary." Both must exist before E2EE sessions can be established with the companion (p.5).

### 1.3 Signed Device List
- **Signed Device List Data** = "an encoded list identifying the currently linked companion devices at the time of signing," signed by the primary's Identity Key with the `0x0602` prefix (p.4 "Companion Linking"):
  `ListSignature = CURVE25519_SIGN(Iprimary, 0x0602 || ListData)` (p.6 step 6).
- On linking, the primary sends `ListData` + `ListSignature` to the server, which **stores them**; and forwards the linking payload (`Ldata`, `PHMAC`) to the companion (p.6 steps 9–10). The companion later uploads `Lmetadata, Asignature, Dsignature, Icompanion`, its Signed Pre Key and One-Time Pre Keys (p.6 step 14).

### 1.4 How a sender verifies a companion belongs to the account (fan-out time)
WhatsApp uses **client-side fan-out**: the sender transmits one individually-encrypted copy per recipient device, over a pairwise Signal session (p.13 "Initiating Session Setup"). Crucially:
- On session setup the sender requests, for each recipient device **and each of its own other devices**, the Identity Key, Signed Pre Key, one One-Time Pre Key, **plus** the companion's `Lmetadata`, `Asignature`, `Dsignature` (p.14 step 2).
- For **every companion key set** the initiator MUST verify (p.14 step 3):
  - `CURVE25519_VERIFY_SIGNATURE(Iprimary, 0x0600 || Lmetadata || Icompanion)` (the Account Signature), and
  - `CURVE25519_VERIFY_SIGNATURE(Icompanion, 0x0601 || Lmetadata || Icompanion || Iprimary)` (the Device Signature).
  - "If any of the verification fails for a companion device, the initiator terminates the encryption session building process immediately and will not send any messages to that device." (p.14).
- This is the design element that stops a malicious/compromised server from silently injecting a companion: the server cannot forge `Asignature` without the primary's private identity key. (Cross-referenced to Meta Engineering, "How WhatsApp enables multi-device capability," Jul 14 2021, which states the goal is "preventing a malicious or compromised server from eavesdropping … by surreptitiously adding devices.")

### 1.5 Self-sync to own devices
- The sender "also establishes a pairwise encrypted session with all other devices associated with the sender account" and fans a copy of every message to its own other devices (p.13). Message history transferred to a newly-linked device is itself E2EE ("Message History Syncing," p.2 TOC / p.3 intro).
- **App State Syncing** (contacts, chat metadata) is E2EE-synced between a user's devices via encrypted "Mutations"/"Patches" with LtHash integrity (pp.25–31).

### 1.6 Device linking methods (provisioning / OOB channel)
- **Option 1 — QR code**: companion shows `Icompanion` + an ephemeral 32-byte **Linking Secret Key `Lcompanion`** in a QR; `Lcompanion` is never sent to the server; primary scans it; an HMAC (`PHMAC = HMAC-SHA256(Lcompanion, Ldata)`) binds the linking payload so the companion can authenticate the primary's `Ldata`/`Asignature` (p.5–6). The QR (out-of-band, human-mediated) is the trust anchor that authenticates the primary→companion channel.
- **Option 2 — 8-character code**: companion shows a 40-bit Base32 `linkCodePairingSecret`; an authenticated ECDH exchange (PBKDF2-HMAC-SHA256 with 2^17 iterations over the low-entropy secret, then AES-CTR/GCM wrapped ephemeral keys) mutually derives `Lcompanion` and cross-checks both identity keys; wrong code → key agreement fails and pairing aborts (p.6–13, steps 1–27).
- **Option 3 — Cloud API network call** (business only): a variant of Option 1 (p.13).

### 1.7 Companion device removal / revocation
- Removal can be initiated by the companion (self-logout), the primary, or the server (p.33 "Companion Device Removal").
- On removal (or detected removal) with companions remaining, the **primary re-generates and re-uploads Signed Device List Data** excluding the removed device: `ListSignature = CURVE25519_SIGN(Iprimary, 0x0602 || ListData)` (p.33–34 steps 1–4).
- **Automatic re-verification / expiry** (the "automatic re-verification story"):
  - Signed Device Lists carry a **Time-To-Live of ≤35 days**. After expiry, senders will only send/receive with the account's **primary** device until a fresher signed list arrives (p.34 "Signed Device List Expiry"). Even absent any removal, primaries periodically re-upload a list with an updated timestamp.
  - **In-Chat Device Consistency (ICDC)**: when a receiver sees in-chat device-consistency data with a newer timestamp for the sender's device list, it reduces the sender list's TTL to **≤48 hours** (p.34). This is how peers automatically re-tighten trust when a device set changes.
  - **Companion compromise**: because of these TTLs, a removed/compromised companion is automatically revoked after 35 days (list expiry) / 48 hours (ICDC). A compromised device "should no longer be used, and removed." Immediate revocation of *all* companions is achieved by **deleting+reinstalling WhatsApp on the primary, which regenerates the primary identity key pair** and invalidates every companion and every existing Signal session (p.34 "Companion Device Compromise"; same effect noted for linking Cloud API, p.5).
- **App-state key rotation on removal**: the KeyID is composite `4-byte Epoch || 2-byte DeviceID`; the Epoch is chosen randomly (1..65536) at first companion registration and incremented on each rotation; "The key must be rotated whenever a device is being unregistered," and a removing device submits a Patch marking all current keys with `epoch ≤ provided` as expired so other devices stop using them (pp.30–32 "Key Rotation").

### 1.8 Key verification (manual OOB)
- Users may verify by scanning a QR or comparing a **60-digit number** (two concatenated 30-digit fingerprints). Fingerprint = lexicographically sort all of a user's device identity keys (excluding Cloud API), then **iteratively SHA-512 hash (5200 iterations)** the sorted keys + user id, take first 30 bytes, split into six 5-byte chunks each reduced mod 100000 (p.32 "Verifying Keys"). The QR encodes version, both user ids, and the full 32-byte identity key (or SHA-512 hash) for **all devices** of both parties.
- WhatsApp additionally runs **Key Transparency** (Auditable Key Directory / AKD, based on PARAKEET) to make the directory auditable — see "Deploying key transparency at WhatsApp," Meta Eng., Apr 13 2023, and the WhatsApp Key Transparency Whitepaper (Aug 2023). Referenced by the WhatsApp EUROCRYPT analysis §1.2, which cautions it has not been independently formally analysed.

---

## 2. iMessage Multi-Device — IDS fan-out and Contact Key Verification (CKV)

Primary sources: **Apple Platform Security guide** (support.apple.com/guide/security) — "How iMessage sends and receives messages securely" (sec70e68c949) and "Apple Identity Service (IDS)" (secf752dc2e2); and **Apple Security Research blog, "Advancing iMessage security: iMessage Contact Key Verification," Oct 27 2023** (security.apple.com/blog/imessage-contact-key-verification/).

### 2.1 IDS directory of per-device keys
- **IDS = Apple's directory of iMessage public keys, APNs addresses, and the phone numbers/emails used to look them up** ("Apple Identity Service (IDS)"). Each device in an account generates its own key set; private keys never leave the device (CKV blog, ¶2).
- Two key types per device: an **encryption public key** (RSA-OAEP historically; **ECIES** on iOS 13+/iPadOS 13.1+) and an **ECDSA signing key** ("How iMessage sends…").

### 2.2 Fan-out encryption to every registered device
- Sender enters an address → device queries IDS for **the public keys + APNs addresses of ALL devices associated with the addressee** ("How iMessage sends…").
- The message is **individually encrypted per receiving device**: per device, generate a random 88-bit value used as an HMAC-SHA256 key to derive a 40-bit value from sender+receiver public keys and plaintext; concatenate → 128-bit AES key; encrypt with **AES-CTR**; wrap the per-message AES key with the device's public key via **RSA-OAEP (or ECIES)**; hash (SHA-1) the ciphertext+key and **sign with the sender device's ECDSA private key**. One message per receiving device is dispatched via APNs. "For group conversations, this process is repeated for each recipient and their devices." ("How iMessage sends…").
- Large payloads/attachments: AES-CTR with a random 256-bit key, uploaded to iCloud; the AES key + URI + SHA-1 of the ciphertext travel inside a normal iMessage.

### 2.3 What historically protected the device list: nothing client-verifiable
- The CKV blog states plainly: "While a key directory service like Apple's Identity Directory Service (IDS) addresses key discovery, **it is a single point of failure in the security model**. If a powerful adversary were to compromise a key directory service, the service could start returning compromised keys … allowing the adversary to intercept or passively monitor encrypted messages." I.e., **pre-CKV, clients had no cryptographic means to detect a device the IDS silently added to a user's account** — the trust was entirely in Apple's directory. (Confirmed by Matrix/Rösler literature framing the same class of "malicious key-directory" attack.) **[Verified via Apple's own admission in the CKV blog.]**

### 2.4 What CKV added (2023 whitepaper/blog)
CKV augments IDS with:
- **An account-level ECDSA signing key**, generated on-device and stored in **iCloud Keychain** (itself E2EE, so available only to the user's trusted devices). **Each device signs its iMessage public keys with this synchronized account key.** The account keys + signatures + the user's CKV opt-in state are added to the IDS entry (CKV blog, "Automatic verification").
- **Key Transparency (KT)**: a CONIKS-style verifiable **log-backed map**, indexed by SHA-256 of a **VRF** of the iMessage identifier (privacy), producing **Signed Mutation Timestamps (SMTs)** — auditable promises to merge a change (giving instant usability). Devices verify inclusion proofs against the KT map; unique to Apple, **user devices themselves verify consistency proofs** rather than relying solely on third-party auditors, and enforce a **48-hour Maximum Merge Delay** on SMTs (CKV blog, "Key Transparency").
- **Self-verification / split-view detection**: each of a user's devices periodically queries IDS for the user's *own* records, verifies them against KT, and compares against an **E2EE CloudKit container** the devices maintain (not readable/writable by Apple). This "prevents IDS from presenting different data about Alice's devices to Alice than it presents to Bob." **Gossip**: clients include KT log hashes in the encrypted part of a small % of messages to detect split views by a compromised KT service (CKV blog, "Automatic verification").
- **Manual contact verification via the Vaudenay SAS protocol** (CRYPTO 2005): users compare short codes to verify they share the same view of each other's **account key**. On verify, the peer's account-key hash is saved to the E2EE CloudKit container and linked to the contact card; this now **covers future signed-in devices** (because devices sign their per-device keys with the synced account key). If the account key later changes (e.g., identifier moves to another account), Messages shows an error. Public-persona users can publish a public verification code encoding the account-key hash (CKV blog, "Contact verification").
- Availability: developer previews of iOS 17.2 / macOS 14.2 / watchOS 10.2 (CKV blog header).

### 2.5 Device removal (iMessage)
- APNs deletes messages on delivery but queues for offline devices; messages stored ≤30 days ("How iMessage sends…"). The Platform Security guide does not specify a cryptographic device-revocation ceremony beyond IDS registration state; **the account-key + KT machinery is what now makes an added/removed device detectable.** **[Device-removal cryptographic detail beyond "IDS updates the registered device set" is UNVERIFIED against a primary Apple source.]**

---

## 3. MLS (RFC 9420) — the membership-agreement concepts transferable to a signed-device-list design

Primary source: **RFC 9420, "The Messaging Layer Security (MLS) Protocol," July 2023** (datatracker/rfc-editor). Section numbers below.

### 3.1 Each device = a leaf / member
- MLS defines a **Client** purely "by the cryptographic keys it holds," and a **Member** as a client included in the group's shared state (§2 Terminology). A user's multiple devices are therefore naturally modeled as **distinct members/leaves**. The academic device-oriented literature (Cohn-Gordon et al. ART, and Albrecht–Dowling–Jones DOGM) explicitly suggests using **subtrees per user** to represent a user's device set (WhatsApp EUROCRYPT §1.3, ref [26]).
- Group membership is "represented directly by its **ratchet tree**, since each member's **LeafNode** contains members' cryptographic keys, a credential that contains information about the member's identity, and possibly other identifiers." (§16.4.3).

### 3.2 Add / Remove / Update proposals + Commit
- **Proposal**: "A message that proposes a change to the group, e.g., adding or removing a member." **Commit**: "A message that implements the changes … proposed in a set of Proposals." (§2). A Commit "initiates a new epoch" (§12.4).
- The membership-changing proposals (§12.1): **Add** (§12.1.1, introduces a new member via their KeyPackage), **Update** (§12.1.2, a member rotates its own leaf keys — the primitive for PCS), **Remove** (§12.1.3, evicts a member). Others: PreSharedKey, ReInit, ExternalInit, GroupContextExtensions.
- A **KeyPackage** is "a signed object describing a client's identity and capabilities, including an HPKE public key" — the credential another member uses to Add a client (§2). This is the direct analogue of a signed device record.

### 3.3 What MLS guarantees that pairwise designs lack: cryptographic membership agreement
- **GroupContext** "summarizes the shared, public state of the group," distributed in a **signed GroupInfo** to new members (§2, §8.1).
- **Transcript hashes** (§8.2): MLS keeps a **running hash over all Proposal and Commit messages ever sent** — a `confirmed_transcript_hash` (over the whole Commit history up to the latest Commit signature) and an `interim_transcript_hash` (adds the latest Commit's `confirmation_tag`). Each Commit's `confirmation_tag` is a MAC keyed from the epoch secret over the confirmed transcript hash. **Consequence: every member cryptographically confirms the entire history of membership changes; a member with a divergent view of who was added/removed derives a different epoch secret and its confirmation MAC fails.** This is the key property a signed-device-list design usually lacks: **agreement on membership is enforced by the key schedule itself, not merely by a per-message signature.**
- **Authentication** (§16.5): two levels — (a) a message came from *some* group member (AEAD key / `membership_tag` MAC derived from group secrets), and (b) from a *particular* member (per-message signature under the sender's signature key). §16.5 warns that a compromised signature key lets an attacker forge LeafNodes/KeyPackages and, if external commits are enabled, insert or "resync"-replace the member — mitigable with **PSKs**.
- **Sequencing** (§14): Commits are premised on a specific starting epoch; the server may order concurrent commits but cannot fabricate membership because each new epoch's secrets depend on the prior epoch and the committed proposals.

### 3.4 Transferable levers for Fireplace
- Represent each device as a leaf/member with a **signed KeyPackage-style record** (credential binds device key ↔ account identity).
- Maintain a **transcript/running hash of device-list changes** so peers (and a user's own devices) reach cryptographic *agreement* on the device set — turning "the server could show different lists to different peers" from an undetectable attack (WhatsApp/iMessage pre-CKV/Matrix) into a MAC/hash mismatch.
- Distinguish **membership authentication** (who is in the set) from **message authentication** (who sent this) — pairwise sender-keys designs give the latter but not the former.

---

## 4. Academic attacks on device-list / multi-device designs

### 4.1 Rösler, Mainka, Schwenk — "More is Less: On the End-to-End Security of Group Chats in Signal, WhatsApp, and Threema," **IEEE EuroS&P 2018**, pp.415–429, DOI 10.1109/EuroSP.2018.00036 (full version: IACR ePrint 2017/713).
- **Core thesis**: group *closeness* (who controls membership) and *communication integrity* are **not end-to-end protected** in Signal/WhatsApp/Threema group chats; none achieve *Future Secrecy* for groups (Abstract; §2.4 defines Additive/Subtractive Closeness, No Creation, Traceable Delivery).
- **WhatsApp server-controlled group membership** (§5.2): "The content of messages is protected on the end-to-end layer while **group modification messages are only protected on the transport layer**. As a result, the WhatsApp server is mainly responsible for the distribution of group messages based on the group management." Because add/remove are not E2E-authenticated, **a malicious WhatsApp server can add an arbitrary user to a group**; existing members' clients will distribute their Sender Key to the injected member, breaking confidentiality. **Precondition**: control of (or MITM on) the server-mediated group-management channel; knowledge of the target group id. **Defeated by**: cryptographically authenticating group-management operations (which WhatsApp still does not do for *group* membership — see §4.3).
- **Signal "burgle into the group"** (§4.3.1): Signal groups are non-administered (every member is admin). **Precondition**: attacker knows the group id `IDgr` (e.g., ex-member with modified client, or via session-state compromise) and the phone number of one member. The attacker sends a *group update* `(B, t, DRE_{A,B}(IDgr, t, ({A}, info)))` over the normal pairwise channel; B's client adds A to its member set. Once any legitimate member issues the next update (e.g., icon change), all members adopt the set including A → A receives all traffic. **Breaks**: No Creation, Additive Closeness, Future Secrecy. **Defeated by**: server/client-enforced admin authorization + authenticated membership (a signed device/member list with an authority key).
- **Forging acknowledgments** (§4.3.2): acks are not E2E-encrypted, so a malicious server forges delivery receipts → **Traceable Delivery** broken (double-checkmark lies). Relevant to fan-out designs relying on server-reported delivery.
- **Takeaway for device lists**: the same "the transport-layer-only membership message is server-forgeable" flaw applies equally to a *device* list if the list is not signed by an account authority key.

### 4.2 Albrecht, Celi, Dowling, Jones — "Practically-exploitable Cryptographic Vulnerabilities in Matrix," **IEEE S&P 2023**, pp.164–181 (IACR ePrint 2023/485).
- **Threat model**: malicious/colluding **homeserver**; strongest-protection setting (encryption + cross-signing verification enabled) (§I.C, §I.E).
- **§III.B Device-list injection (the device-list attack)**: "Each user has a list of devices … **This list is controlled by the homeserver**." It exists in parallel to, and independently of, the cross-signing/verification system. "**A malicious homeserver may create their own device that can then be added to the device list of an existing user in a room.**" When any device in the room next sends, it shares its Megolm session with the homeserver-controlled device → server decrypts future messages. **Precondition**: homeserver control; the injected device is *unverified*. **Partial mitigations exhibited by Element**: adding an unverified device raises a warning — but the homeserver can serve a **split view** ("When a user requests their *own* device list, the homeserver does not include the unverified device. When a *different* user requests the list, the homeserver includes an unverified device that they control."), so the target's own devices never prompt verification. **Defeated by**: the planned per-room "never send to unverified sessions" setting, and long-term **mandatory verification + TOFU pinning of the user's master cross-signing key so the homeserver cannot overwrite it** (§III.C Remediation). CVEs: e.g., CVE-2022-39257 cluster.
- **§III.A Room-membership control**: room management messages are "neither encrypted, checked for integrity nor cryptographically authenticated," so the homeserver forges membership events and adds users → confidentiality break. Matrix devs initially **accepted this risk**; long-term fix = **signed membership**: "the inviting user must include the master cross-signing key of the new user in a signed message … the transcript of invites form a **tree of signatures**, rooted in the room's creation event" (§III.C) — i.e., converging toward an MLS-transcript-like design.
- **§IV Out-of-band verification attack**: lack of **domain separation** between device identifiers and users' master signing keys lets an attacker get a target to sign/verify an attacker-controlled cross-signing identity → MITM on Olm/Megolm (CVE-2022-39250). **Lesson**: sign device records and identity keys in **separated, labeled** contexts (cf. WhatsApp's explicit `0x0600/0x0601/0x0602` prefixes, which provide exactly this domain separation).
- **§V–VI Impersonation via Key-Request/forwarded-session and Olm/Megolm protocol confusion**: no verification on which key-shares to accept, and message types expected over Olm are accepted over Megolm → semi-trusted then "trusted" impersonation, and a confidentiality break by hijacking the server-side backup key. **Lesson for self-sync/history-share**: authenticate *who* forwarded a session and enforce channel/type separation.

### 4.3 Albrecht, Dowling, Jones — "Formal Analysis of Multi-Device Group Messaging in WhatsApp," **EUROCRYPT 2025**, pp.242–271 (IACR ePrint 2025/794). The only academic, source-level analysis of WhatsApp's *multi-device* design.
- **Method**: reverse-engineered the WhatsApp Web client (archived May 3 2023) + whitepaper v6; WhatsApp engineers confirmed the protocol description is correct (Remark 1). Modeled in an extended **Device-Oriented Group Messaging (DOGM)** model with added **device revocation** (§1.1).
- **"Public key orbits"** (§4): their formalism for WhatsApp device management — "a hierarchy of keys, with the **primary key being an authority over which devices may be linked (or unlinked)**." Compared to Keybase sigchains / Zoom / ELEKTRA; less flexible (strict primary→companion hierarchy). Because WhatsApp **reuses the identity key** for key exchange *and* signatures, they must prove security under a **restricted signing oracle** (§4; §8 "Lack of domain separation" — implications "unknown").
- **What WhatsApp DOES get right (proved)**:
  - Messages are confidential to, and accepted only from, **verified devices** of members; guarantees are maintained across group-membership and per-member device changes (§8 "Confidentiality and authentication").
  - **Users control their own device lists** (unlike group membership): "When our device is notified that a member has revoked a device, the revoked device will not have access to future messages." **In-Chat Device Consistency (ICDC)** in pairwise messages "guarantees that device revocation can be detected if our device is able to securely communicate with at least one honest device of the other user," and device-list expiry bounds detection time (§8).
  - **Device revocation enables recovery from a detected compromise**: a user removing, say, a compromised laptop via their phone sends a *direct* message whose ICDC info alerts peers' devices that a new multi-device generation exists; if blocked, list expiry eventually makes the primary the only verified device (§8 "Device revocation").
- **What WhatsApp does NOT protect (the critical caveats)** — directly relevant to Fireplace:
  - **Group membership is NOT cryptographically authenticated**; "group membership is controlled by the server." Modeled as a **trivial win** for the adversary: "If WhatsApp addresses this issue then the protocol achieves the stated security guarantees." A correctly-implemented client blocks *invisible* ("ghost") members, but an adversary named "Alice" in a 1024-member group is "reasonably well hidden." **No consistency of group-membership view across users or even across a single user's devices** (§1.2, §8 "Adversarially-controlled group management").
  - **The server can reset a user's cryptographic identity**, and "**Clients default to not displaying such a change to users.**" Possibly mitigated by Key Transparency, but that composition is unanalyzed (§1.2 Scope).
  - **Unclear enforcement of removal**: they found no evidence clients delete inbound Sender Keys sessions of removed group members — so a removed participant might still be able to *send* (§8 "Unclear client enforcement").
  - **Weak/absent PCS in the multi-session setting** (§5, §8 "Lack of post-compromise security"): libsignal allows **multiple parallel Signal sessions between one pair of devices**; an adversary who compromises identity/session state can spin up a new compromised session later, and WhatsApp keeps the **5 most recent inbound Sender Keys sessions** per device, capping group-chat PCS. Recovery after identity-key compromise essentially requires device **revocation**, not ratcheting. (Builds on Cremers–Fairoze–Kiesl–Naska CCS 2020 "clone detection" and Cremers–Jacomme–Naska USENIX 2023 session-handling.)

### 4.4 Related device-linking / multi-device analyses (pointers to primary sources)
- **Dimeo, Gohla, Goßen, Lockenvitz — "SoK: Multi-Device Secure Instant Messaging," IACR ePrint 2021/498** — systematization of multi-device deployments/approaches.
- **Campion, Devigne, Duguey, Fouque — "Multi-Device for Signal," ACNS 2020**, LNCS 12147, pp.167–187 — a per-device-key multi-device design over Signal.
- **Cremers, Fairoze, Kiesl, Naska — "Clone Detection in Secure Messaging," ACM CCS 2020** and **Cremers, Jacomme, Naska — "Formal Analysis of Session-Handling in Secure Messaging," USENIX Security 2023** — show multiple-parallel-sessions undermine PCS (the mechanism §4.3 relies on). *(The "Careful with MAc-then-SIGn"/Kessem items named in the brief were not located as distinct primary papers; the substantive WhatsApp multi-device cryptanalysis is the EUROCRYPT 2025 paper above.)* **[The specific titles "Careful with MAc-then-SIGn" and a Kessem WhatsApp paper are UNVERIFIED — no primary source found; treat as not-corroborated.]**

---

## 5. Cross-cutting synthesis — design levers for silent device add/replace

The question "can a server silently add or replace a device?" is decided by five levers. Rating each messenger:

| Lever | WhatsApp (MD) | iMessage pre-CKV | iMessage + CKV | Matrix/Element | MLS (RFC 9420) |
|---|---|---|---|---|---|
| **(i) Who signs the device list** | Primary device signs Signed Device List (`0x0602 \|\| ListData`) + per-companion Account/Device cross-signatures | **Nobody client-verifiable** — IDS asserts it | Per-device keys signed by an **account ECDSA key** in iCloud Keychain; anchored in **KT log** | Homeserver controls raw device list; cross-signing (self-signing key) *optionally* signs devices — but list itself is server-controlled | Each leaf = signed **KeyPackage/LeafNode**; membership bound into **transcript hash** + key schedule |
| **(ii) Per-device vs shared identity key** | **Per-device** identity keys (post-MD) | Per-device keys | Per-device keys | Per-device Olm/fingerprint keys + user cross-signing keys | Per-member (per-device) leaf keys |
| **(iii) Stable/monotonic device ids** | Composite `Epoch(4B)‖DeviceID(2B)` KeyIDs; Epoch monotonic; Signed-list timestamps monotonic with TTL | Opaque IDS device ids; no monotonic guarantee | KT log is append-only/monotonic; SMTs timestamped, 48h merge delay | Homeserver-assigned `D_{A,i}`; server can vary | Epoch numbers strictly increase; each Commit chains to prior epoch |
| **(iv) Peers pin & diff the list** | Senders re-verify Account/Device sigs every session; **ICDC** shrinks TTL to 48h on change; lists expire ≤35d | **No** — no client pinning | Devices self-audit own record vs KT + E2EE CloudKit; **gossip** detects split views | Element warns on unverified device, but **split-view defeats own-device prompt**; planned TOFU-pin of master key | Transcript hash + confirmation MAC force **cryptographic agreement**; divergent view → MAC failure |
| **(v) Out-of-band verification** | 60-digit / QR fingerprint over all device keys; KT (AKD) | Manual safety-number style only | **SAS (Vaudenay CRYPTO 2005)** over account key; covers future devices | SAS / QR cross-signing (but §IV domain-separation bug) | Application-supplied OOB + PSKs; credentials in leaves |

**Overall "can the server silently inject a device?" rating:**
- **iMessage pre-CKV** — **Yes, silently and undetectably.** Directory is the sole authority (Apple's own "single point of failure" admission).
- **Matrix/Element (pre-fix)** — **Yes**, via device-list split view; only a room-level warning, and only if the injected device is surfaced to peers (S&P 2023 §III.B).
- **WhatsApp** — **Not silently for *devices*** (Account Signature is unforgeable without the primary's identity key; failed verification aborts the session). **But** the server *can* silently reset a user's *primary identity key* (clients don't warn by default) and **fully controls *group* membership** (EUROCRYPT 2025 §1.2/§8). So device injection is defended; the residual holes are identity reset and group membership.
- **iMessage + CKV** — **Detectable**: KT + on-device consistency + self-audit + gossip turn a silent injection into a user-visible error, for CKV-opted-in conversations.
- **MLS** — **Strongest**: membership is welded into the key schedule; a server cannot present divergent membership without breaking the confirmation MAC (subject to a trusted Authentication Service for credential↔identity binding, §16.10).

**Concrete recommendations for Fireplace Phase 2 (derived from the above):**
1. **Per-device identity keys** with an **account-authority signature** over the device list (WhatsApp `0x0602`-style, with explicit domain-separation prefixes to avoid Matrix's §IV bug). Verify these signatures at fan-out time and **abort** on failure (WhatsApp p.14 model).
2. **Bidirectional device linking signatures** (Account + Device) so both the account authority and the new device attest the link (WhatsApp §1.2).
3. **Pin + diff device lists on peers** and add an **in-chat consistency beacon with TTL/expiry** (WhatsApp ICDC: 48h/35d) so a changed device set is auto-detected and re-verified, not trusted forever.
4. **Prefer a transcript-hash/agreement mechanism** (MLS §8.2) if you want cross-device/cross-peer *agreement* on the device set — the property both WhatsApp and pre-CKV iMessage lack.
5. **SAS provisioning** (Vaudenay) over an **account key** rather than per-device keys, so verification survives future device additions (iMessage CKV §2.4).
6. **Revocation must propagate to key state**: on device removal, rotate/expire keys and destroy the removed device's send/receive sessions (WhatsApp key-rotation p.30–32; note EUROCRYPT §8 "unclear enforcement" warns clients may fail to delete removed-member sessions — do not repeat that bug).
7. **Device-id allocation/reuse across account resets**: use **monotonic, authority-anchored ids** (WhatsApp Epoch is monotonic; MLS epochs strictly increase). Regenerating the account/primary identity key is the clean "revoke everything" reset (WhatsApp p.34) — treat account reset as a new orbit, never silently reuse an old device id under a new key without a visible identity-change signal.
8. **Message-edit re-fanning**: an edit is just another fan-out; it MUST re-resolve the current signed device list (respecting TTL/ICDC) so an edit is not delivered to a since-revoked device nor withheld from a newly-added one. **[No primary source specifies edit re-fanning semantics for these messengers; this is an inference from the fan-out + device-list-TTL mechanics above — treat as design guidance, not cited fact.]**

---

## Sources

Primary specifications & whitepapers:
- WhatsApp LLC. *WhatsApp Encryption Overview — Technical White Paper*, Version 9 (Feb 25 2026). https://www.whatsapp.com/security/WhatsApp-Security-Whitepaper.pdf — pp.3–6 (identity keys, Account/Device Signatures, linking), p.13–14 (fan-out, session setup, per-companion signature verification), pp.30–34 (key rotation, verifying keys, companion device removal, expiry/ICDC, compromise).
- Meta Engineering. *How WhatsApp enables multi-device capability* (Jul 14 2021). https://engineering.fb.com/2021/07/14/security/whatsapp-multi-device/
- Meta Engineering / Lawlor & Lewi. *Deploying Key Transparency at WhatsApp* (Apr 13 2023). https://engineering.fb.com/2023/04/13/security/whatsapp-key-transparency/ ; WhatsApp Key Transparency Overview whitepaper (Aug 2023).
- Apple. *Apple Platform Security* — "How iMessage sends and receives messages securely" (sec70e68c949) https://support.apple.com/guide/security/how-imessage-sends-and-receives-messages-sec70e68c949/web ; "Apple Identity Service (IDS)" (secf752dc2e2) https://support.apple.com/guide/security/apple-identity-service-ids-secf752dc2e2/web
- Apple Security Engineering & Architecture. *Advancing iMessage security: iMessage Contact Key Verification* (Oct 27 2023). https://security.apple.com/blog/imessage-contact-key-verification/
- IETF. RFC 9420, *The Messaging Layer Security (MLS) Protocol* (Jul 2023). https://www.rfc-editor.org/rfc/rfc9420 — §2 (terminology), §3.1 (state/evolution), §8.1–8.2 (GroupContext, transcript hashes), §12.1/§12.4 (proposals, commit), §14 (sequencing), §16.4.3 (group membership), §16.5 (authentication).

Academic (primary):
- P. Rösler, C. Mainka, J. Schwenk. *More is Less: On the End-to-End Security of Group Chats in Signal, WhatsApp, and Threema.* IEEE EuroS&P 2018, pp.415–429. DOI 10.1109/EuroSP.2018.00036. Full version: IACR ePrint 2017/713, https://eprint.iacr.org/2017/713.pdf — §4.3 (Signal burgle-into-group, ack forging), §5.2 (WhatsApp server-controlled group membership).
- M. R. Albrecht, S. Celi, B. Dowling, D. Jones. *Practically-exploitable Cryptographic Vulnerabilities in Matrix.* IEEE S&P 2023, pp.164–181. IACR ePrint 2023/485, https://eprint.iacr.org/2023/485.pdf — §III.A (room membership), §III.B (device-list injection / split view), §III.C (remediation: signed membership tree, TOFU), §IV (domain-separation SAS attack), §V–VI (impersonation, backup-key hijack).
- M. R. Albrecht, B. Dowling, D. Jones. *Formal Analysis of Multi-Device Group Messaging in WhatsApp.* EUROCRYPT 2025, pp.242–271. IACR ePrint 2025/794, https://eprint.iacr.org/2025/794.pdf — §1.1–1.2 (contributions, scope: server can reset identity, group membership unauthenticated), §4 (public key orbits), §5 (multi-session PCS), §8 (interpretation: device revocation recovery, ICDC, caveats).
- M. R. Albrecht, B. Dowling, D. Jones. *Device-Oriented Group Messaging: A Formal Cryptographic Analysis of Matrix' Core.* IEEE S&P 2024 (DOGM model). DOI 10.1109/SP54263.2024.00075.
- A. Dimeo, F. Gohla, D. Goßen, N. Lockenvitz. *SoK: Multi-Device Secure Instant Messaging.* IACR ePrint 2021/498. https://eprint.iacr.org/2021/498
- S. Campion, J. Devigne, C. Duguey, P.-A. Fouque. *Multi-Device for Signal.* ACNS 2020, LNCS 12147, pp.167–187.
- C. Cremers, J. Fairoze, B. Kiesl, A. Naska. *Clone Detection in Secure Messaging.* ACM CCS 2020, pp.1481–1495. / C. Cremers, C. Jacomme, A. Naska. *Formal Analysis of Session-Handling in Secure Messaging.* USENIX Security 2023.
- S. Vaudenay. *Secure Communications over Insecure Channels Based on Short Authenticated Strings (SAS).* CRYPTO 2005, LNCS 3621, pp.309–326.

Unverified / not corroborated:
- "Careful with MAc-then-SIGn" and a "Kessem" WhatsApp multi-device paper (named in the task brief) — no primary source located; **UNVERIFIED**, not cited as authority.
- iMessage cryptographic device-*removal* ceremony details beyond IDS registration state — **UNVERIFIED** (not specified in the Platform Security guide sections read).
- Message-edit re-fanning semantics — **[INFERENCE]** from fan-out + device-list-TTL mechanics; no primary source states edit-specific behavior.



# Appendix D — Fireplace frozen spec map (v5)

# Fireplace Multi-Device Spec — Faithful Map (frozen v5)

Source: `docs/design/multi-device.md` (Status: v5 FROZEN 2026-08-17, header lines 3-11). All line refs are into that file.

---

## Part 1 — §5.1–§5.7 mechanisms

### §5.1 Provisioning — two-round DH-bound SAS, secrets-last (lines 164-218)
Linking is a two-round ECDH-bound SAS ceremony replacing the v3 single-shot `KDF(ephPubN‖provisioningId)` SAS, which was offline-grindable (single-party public input, ~20-bit compare; lines 166-168). New device N opens a `provisioningId` (UUID, 10-min TTL), shows QR `{provisioningId, ephPubN}`; primary scans it (OOB channel for ephPubN), sends `provisioningHello {ephPubP}` with NO secrets, both derive `SAS = HKDF(S_dh, info="fp-link-sas", provisioningId‖ephPubN‖ephPubP)` (lines 176-190). Only AFTER human SAS compare + primary approve does the primary send the IK-bearing AEAD blob under `HKDF(S_dh, info="fp-link-blob")` plus a staged DAK-signed list mutation v+1 (secrets-last, I3; lines 191-201). Two-phase commit: STAGED at `provisionDevice`, committed at `provisioningComplete`, bound to the same socket that called `openProvisioning` (lines 205-210). Abort/TTL/cancel → N discards IK + all minted keys + assigned deviceId (I1; lines 213-216); `revokeDevice` auto-cancels a pending stage (lines 211-212).

### §5.2 Send fan-out + signed device list + E2E cross-check (lines 220-251)
One ciphertext per recipient device + one per sender's OTHER devices (self-sync), each from its own pairwise session `SignalProtocolAddress(userIdStr, deviceId)` (lines 222-227). TWO freshness layers: server-side liveness (stale stamps → `deviceListStale` reject carrying base64 `listCanonical`+signature+enrollment; client verifies IK→DAK chain per I7, re-encrypts, resends, retry cap 3 then surfaced failure; lines 229-234); end-to-end trust via `senderListInfo {ownVersion, ownListHash, peerVersion, peerListHash}` in the E2E plaintext (lines 235-244). Escalation treats the field as attacker-controlled: sender-older only alarms after recipient INDEPENDENTLY re-fetches DAK-signed data; claims-newer gets one rate-limited fetch then discarded; self-sync skew → benign "syncing devices…", never identity-changed (lines 237-249). Match → 1 message row + N envelope rows in one txn; new sessions built lazily via `fetchPreKeyBundle` (lines 250-251).

### §5.3 Envelopes, device rooms, history reads, deviceIds-never-reused (lines 253-280)
Socket auth carries `deviceId`; joins `user:<uid>` (metadata) AND `device:<uid>:<did>` (ciphertext); `emitToNewestTab` demoted to `emitToDeviceNewestSocket` within one web device (lines 255-261). Per-device history read joins `message_envelopes` on requesting `(userId, deviceId)`, DEVICE-GATED fallback per row: (1) this device's envelope; (2) legacy `encryptedContent` served ONLY to session owner (`deviceId==1` or `deviceId==originDeviceId`); (3) all others → `envelopeStatus:"none_for_device"` marker → honest placeholder, never `[Decryption failed]` (lines 262-276).

> Verbatim lines 269-272:
> `originDeviceId` NULL = device 1). **Load-bearing invariant: deviceIds are monotonic per
>      account and NEVER reused, including across a §6.2 reset** — device 1 permanently names the
>      account's original device; a reused id would resurrect the foreign-ratchet decrypt this gate
>      exists to prevent;

Push suppression skips only the focused device; `deliveredAt`/`readAt` stamped per device but wire keeps single projected `deliveryStatus` (recipient-envelopes-only; lines 277-280).

### §5.4 Self-sync, lost-ack, sendToken (lines 281-312)
Own-sent arrives on device B as envelope `senderId==me`, `originDeviceId != myDeviceId`, decrypted via pairwise own-device session, persisted normally (lines 283-285). EVERY own-sender guard switches `senderId==me` → `originDeviceId==myDeviceId` — five sites: `decrypt.dart:962-963`, `:975`, `:1290`, `history.dart:529`, `decrypt.dart:642` (lines 287-291). Lost-ack keyed by client-minted `sendToken` UUID with uniqueness law: server enforces per-sender uniqueness (dup = rejected); own-message reconcile matches `(senderId, originDeviceId, sendToken)` → exactly one row, ambiguous match is a no-op never consuming pending (lines 302-309). Reconcile untouched (I8); self-sync row never consumes pending; `messageSent` ack goes only to origin device (lines 296-312).

### §5.5 Revocation + stale bounce (lines 313-325)
Primary-only DAK-signed mutation sets `revokedAt`, version+1, one txn; preempts pending provisioning stage (lines 315-316). Server stops routing, deletes refresh tokens + push rows, kicks sockets; still-valid JWT gets SILENCE from `getServedMessageIds` (I6) + rejection from mutating handlers until expiry (lines 317-319). Peers drop device on next staleness bounce (worst case one rejected send); §5.2 cross-check exposes any server attempt to keep serving pre-revocation list (lines 320-321). Local data NOT wiped; revoked device's OTPs purged (lines 322-324).

### §5.6 Disappearing messages (lines 326-339)
Row-level expiry retained; read-based TTL starts ONLY per I9 (recipient's `markConversationRead` over peer's rows), never from envelope stamps or sender's self-sync read (lines 328-333). At deadline row + ALL envelopes destroyed incl. one a linked device never fetched — "disappear means disappear, on every device, at one deadline" (lines 333-335). Per-envelope expiry rejected (lines 335-337).

### §5.7 Edit re-fan (lines 340-357)
Sender-only from any of the sender's devices (all hold plaintext via self-sync), within existing 15-min server-checked window (lines 342-343). `editMessage {messageId, envelopes:[{userId, deviceId, ciphertext}]}` full re-fan; server verifies sender + window + device-list coverage, writes each device's edited ciphertext in one txn with UPSERT: existing envelope replaced CONTENT-ONLY, `deliveredAt`/`readAt` SURVIVE (projection never regresses); a device linked after original send gets a row INSERTED, upgrades `none_for_device` placeholder to edited message (lines 344-354). Server stamps `editedAt`, fans `messageEdited`; edit never mints/consumes `sendToken` (lines 355-357).

---

## Part 2 — §7 wire-contract deltas (lines 412-426)
- `sendMessage` (416): was one `encryptedContent`; now `envelopes[]` + `sendToken` (unique/sender) + two list-version stamps (`senderListVersion`,`recipientListVersion`); reject `deviceListStale` (listCanonical base64).
- `editMessage` (417): was one new `encryptedContent`; now `envelopes[]` full re-fan; per-device row replacement; window/sender checks unchanged.
- E2E plaintext envelope (418): was `{content, messageType?, media…}`; now + `senderListInfo {ownVersion, ownListHash, peerVersion, peerListHash}` (older clients ignore).
- `newMessage`/`messageEdited` (419): was newest tab of user; now device room, newest socket within device; payload + `originDeviceId`.
- `getMessages` rows (420): was `encryptedContent` echo; now requesting device's envelope ciphertext → legacy fallback gated to session-owner → `envelopeStatus:"none_for_device"`; own rows + `originDeviceId`,`sendToken`.
- `uploadKeyBundle`/`fetchPreKeyBundle`/`uploadOneTimePreKeys`/`preKeysLow`/`checkOwnKeyBundle` (421): was per user; now per `(user, device)`; §6.1 mutation rules; never-activated deviceId uploads rejected.
- `messageDelivered`/read (422): unchanged shape; server projects from RECIPIENT envelopes only, column-scoped UPDATE.
- `getServedMessageIds` (423): UNCHANGED (I8); SILENCE to revoked devices (I6).
- NEW (424-425): `openProvisioning`, `provisioningHello`, `provisionDevice`, `provisioningBlob`, `provisioningComplete` (session-bound), `deviceListChanged`, `getDeviceList`, `revokeDevice` (preempts stages), `resetIdentityRequest/Cancel`.
- `socketReady`,`getServerTime`,delete/clear/unfriend,reactions (426): unchanged (delete fan-out cascades envelopes).

---

## Part 3 — §10 falsification tests (lines 462-531)
1. Two devices upload OTPs 0..99 — old schema collision/bad MAC (red); new `(userId,deviceId)` no collision (464-466).
2. Mutation signed by IK not DAK → server+peer reject (467).
3. Unsigned/wrong-version/replayed mutation rejected; version rollback → loud flag (468).
4. `deviceListStale` invalid signature chain → client refuses, fails send (I7) (469-470).
5. Send to stale list → rejected atomically, zero envelopes (471).
6. Self-sync: every own-sender guard switched to origin-device scoping; red if any missed (472-474).
7. Concurrent send+revoke: revoked device gets no envelope for a message committed after revocation (475-476).
8. Blob replayed to different ephemeral undecryptable; expired TTL rejected; `provisioningComplete` one-shot + rejected from non-opener session (477-478).
9. Fail-closed: device-list fetch timeout → send FAILS; per-device UNKNOWN → no key generation (479-480).
10. Reset: cancel halts; cancel-vs-expiry serialized (terminal states); repeats rate-limited; cancelled reset never shows peers identity-changed (481-483).
11. Expiry: at deadline row + ALL envelopes destroyed; never-fetched device shows NO error artifact (484-485).
12. Per-device epoch: post-reset all three re-keyed sites purge/claim/count within `(identity, deviceId)` (486-487).
13. Reconcile mass-purge guard (I8): origin/pre-migration/legacy rows reconcile served; revoked → SILENCE; `none_for_device` never destruction trigger; non-owner on legacy row gets marker not ciphertext; no-device-1 → marker everywhere (488-495).
14. Lost-ack via `sendToken`: dropped ack recovers by token match; dup rejected; ambiguous match no-op not consuming pending (496-498).
15. SAS grinding (rewritten): adversary substituting an ephemeral cannot compute a colliding SAS (DH-bound) (499-502).
16. Split-view/freeze: frozen old signed list exposed by first message's `senderListInfo`; recipient re-fetches, confirms, alarms; red without cross-check (503-505).
17. DAK rotation: post-handover mutation signed by OLD DAK rejected by server AND peers (506-507).
18. Two-phase provisioning: kill N between blob and complete → no device row/mutation, blob re-fetchable till TTL; N discards IK+keys+deviceId on abort (508-510).
19. Projection safety: delivery projection changes ONLY `deliveryStatus` via scoped UPDATE; `expiresAt`/`disappearAfterSeconds` byte-identical; self-sync never flips projection; read-TTL never from envelope stamps/self-sync (I9) (511-515).
20. Concurrent double-link: two staged mutations at v+1 → second rejected; primary re-signs at v+2; exactly one device added; revoke preempts stage (516-517).
21. Recovery key: verifier Argon2id (fast-hash red); single-use; rate-limited; shortened path still notifies every session+push, honors 1h cancel window (518-520).
22. False-alarm discipline: bogus `senderListInfo` (older AND newer) → ≤1 rate-limited re-fetch, NO alarm; own-device skew → "syncing devices" (521-523).
23. Canonical bytes: `listCanonical` survives transport byte-exact; duplicate-key/ambiguous canonical rejected at parse (524-525).
24. Edit re-fan: UPSERTs every current device's envelope in one txn; offline device gets edited ciphertext next read; after-send-linked device gets INSERTED envelope, upgrades placeholder; replacing delivered/read envelope preserves stamps; non-origin own-device edit succeeds; `editMessageFailed` unchanged; no `sendToken` minted (526-531).

---

## Part 4 — Identity model: ONE shared account IK (Matrix/Sesame-style analogue)
Confirmed: all devices share ONE account identity key (IK); per-device keys are only Signal session/prekey material, not identity.
- §3 keys table: IK = "account identity", curve25519, custody "every device's secure storage", lifetime "account lifetime; reset only via §6.2" (§3 IK row, lines 100-125).
- IK transported device-to-device at link time (blob carries the IK PAIR): §5.1 blob = AEAD of `{IK pair, dakPub, E, assigned deviceId}` (line ~191); I1 "Provisioning transports IK device-to-device" (lines 58-61).
- Signing authority is a SEPARATE per-account key DAK, custody "current primary only", explicitly NOT IK (I2, lines 62-66; §3 DAK row).
- Enrollment `E = {userId, dakPub, createdAt, sig_IK(...)}` binds the single IK to DAK (§3 ~116-120); peer chain = "TOFU'd IK → E → DAK → list" (I7, lines 85-88).
- Per-device material only: `registrationId`, signed prekey, OTPs, pairwise Signal sessions (§3 third row; §5.2 lines 222-227). `key_bundles` UNIQUE → `(userId, deviceId)`; "under shared IK the identity half only changes on reset" (§4).
- Threat matrix footnote ¹: "a linked device holds the shared identity key IK" (lines ~44-48) — confirms IK shared across devices.
Analogue: shared-IK + separate device-signing-key + DAK-signed device list = Matrix cross-signing / Signal-Sesame device-management shape (ONE identity certifying a device set), NOT a per-device-identity model. Sesame §3.3 cited as fan-out basis (§5.2 header, line 220).

---

## Part 5 — §6 reset ceremony vs device set (lines 358-410)
- §6.2 reset (all devices/identity lost): credential login → `resetIdentityRequest` → server starts 72h timer, immediately notifying every live session AND every push endpoint (FCM+Web Push; no email → 72h not 24) (lines 377-380). Any session CANCELs with one tap, no key; peers' conversations marked pending-reset (380-381).
- Hardening: one pending request/account (new returns existing deadline; 24h cooldown after cancel); cancel/expiry serialized in one txn, terminal `completed`/`cancelled` states, cancel that wins aborts commit (I4; 382-389).
- On expiry server accepts fresh IK + fresh enrollment; peers get loud identity-changed surface (390). Reset mints fresh IK/DAK/enrollment invalidating old device set authority — but deviceIds are NEVER reused across a §6.2 reset (lines 269-272), so device 1 permanently names the original device even post-reset; no-device-1 case (after revoke/re-link) → `none_for_device` marker everywhere (falsification 13, 493-495).
- Recovery key §6.2.1: 12-word BIP39 (≥128-bit CSPRNG), Argon2id server hash; SHORTENS 72h → 1h cancel window but never silences, single-use, rate-limited (391-402).
- §6.3 primary migration = ROTATION not reset: new primary mints DAK′ in own Keystore, old primary signs `E′` after §5.1 QR+SAS, old DAK authority dies at re-pin; old-primary-lost → falls back to §6.2 (404-410).

---

## Part 6 — Open questions / TODO / Phase flags
All §11 owner open questions RATIFIED (lines 533-542):
1. In-conversation identity-changed timeline row — YES, 0a ships it (535-536).
2. Recovery key — YES, in 0b (537).
3. Device cap 3 — CONFIRMED (538).
4. Reset delay 72h — CONFIRMED (539).
5. iOS-PWA cannot be primaries until iOS app — CONFIRMED (540-541).
6. Disappear-at-one-deadline — CONFIRMED (542).
Design review CLOSED at doc level (header 3-8); remaining work deferred to phase gates, not open questions: "NO CODE until Phase-0a dispatch" (line 8); "Next gate: Phase-2 spec-level review round at implementation time" (final review-record line ~591); Phase 2 requires ALL §10 falsifications green + own Phase-2 spec review first (458); Argon2id memory-hard params "pinned at implementation" — deferred (~397).
Explicit non-goals deferred (not TODOs), §1 lines 22-28: PQXDH/Kyber (separate epic); sealed sender, groups, iOS native app, history-transfer-on-link (Phase 4, own doc); remote wipe of revoked device's local data.
No TODO/FIXME/unresolved markers remain — every finding across 3 review rounds + micro-verification folded; frozen v5 (review record lines 543-591).

---

## Sources
- `docs/design/multi-device.md` v5 (2026-08-17): §1 lines 13-28; §2 + I1-I9 lines 29-96; §3 keys 98-125; §4 data model 127-160; §5.1-5.7 protocols 162-357; §6 reset/lock/migration 358-410; §7 wire deltas 412-426; §8 compat 427-450; §9 phases 451-460; §10 falsifications 462-531; §11 open questions 533-542; §12 review record 543-591.
- `frontend/CLAUDE.md` §5 lines 111-113 (plaintext-store invariants).
- `backend/src/key-bundles/` directory listing (code sites named by §4/§6).
