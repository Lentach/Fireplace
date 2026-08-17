# Multi-device research — code impact map + external design inputs (NO CODE)

**Date:** 2026-08-17

## What was done

Owner is moving toward multi-device (Signal-style linked devices). This session was pure research —
three read-only code scouts + primary-source web research — ending in an architecture recommendation.
**No code, no deploy, no design doc yet** (doc-first rule: `docs/design/multi-device.md` is the next
artifact, on owner go).

### Decisions/direction settled in-conversation (owner-agreed unless marked)

- "No password recovery" stays. Optional client-side recovery key (random words, server stores hash
  only) noted as a zero-cost refinement — not decided.
- Multi-device direction accepted by owner after the key argument: **the feared takeover
  (password → silent bundle replacement → attacker reads all future messages) works TODAY,
  single-device** — `upsertKeyBundle` accepts any replacement with a valid JWT
  (`key-bundles.service.ts:41-58`); the 0.1.10 guard is client-honesty only.
- **Phase 0 precedes everything:** (0a) promote the existing `[identity-churn]` log branch
  (`key-bundles.service.ts:46-53`) to durable audit row + notify other sessions + peer-visible flag;
  (0b) registration lock: bundle mutations require signature by the stored identity key, with a loud
  delayed loss-override path. 0a/0b ship standalone value even if multi-device dies.

### Recommended architecture (my conclusion, not yet owner-ratified)

**Hybrid: Signal shared identity + WhatsApp-style signed device list.**
- Shared identity keypair transferred in a QR provisioning ceremony (possession-based; server is a
  blind relay) → one fingerprint per person, `trusted_identity_*` storage and peer TOFU unchanged.
- Every device-list/bundle mutation signed by a **device-authorization key held ONLY by the primary
  device (Keystore-backed; NEVER the shared identity key — linked devices hold the identity key, and
  a linked PWA keeps it in web storage per `frontend/CLAUDE.md` §5, so identity-key signing would let
  one XSS mint devices forever)**, verified server-side on write and by peers on fetch → password
  thief cannot add a device (kills eprint 2021/626-class attacks AND today's takeover). Identity
  *reset* (all devices lost) is the only password-only path left — loud + delayed by design.
- Pairwise fan-out (no sender keys), device cap 3. Per-device envelope rows; per-device delivery rows
  projected to the existing single wire enum (delivered=first device, read=any).
- Sesame adoption scoped to: send-time device-list staleness check (server rejects stale device set,
  returns delta), one active session per device. Skip retry-requests/session-expiry initially.
- History-on-link (Signal does this since 01/2025 via encrypted archive + blind relay) = Phase 4,
  optional; the sealed plaintext store is the natural archive.
- **PQXDH decoupled:** `libsignal_protocol_dart` 0.8.2 has no Kyber; official PQ = signalapp/libsignal
  (Rust FFI, heavy toolchain — the webcrypto/MSVC/16KB trap class). Multi-device ships on the current
  lib; lib swap is its own later epic; never both in one migration.

## Key files (evidence gathered, none modified)

Full scout reports: `agent://BackendKeyWireScout`, `agent://FrontendCryptoScout`,
`agent://DeliveryReadModelScout` (session-local; the facts below are the durable copy).

- **Crypto layer is half-ready:** the Dart lib models `SignalProtocolAddress(name, deviceId)` and
  `signal_stores.dart` ALREADY keys `session_<name>_<deviceId>` / `trusted_identity_<name>_<deviceId>`;
  everything above pins `_deviceId = 1` (`encryption_service.dart` ~L64, `getSubDeviceSessions→[1]`,
  `deleteAllSessions→_1`).
- **Ranked single-device assumptions:** (XL) `KeyBundle.userId UNIQUE` + OTP `(userId,keyId)` + the
  three-site identity-epoch purge that would destroy a second device's keys
  (`key-bundle.entity.ts:15`, `key-bundles.service.ts:60-189`, migrations 0003-0005); (XL) one
  `encryptedContent` per message row + single-ciphertext send path
  (`message.entity.ts:38`, `messaging_provider.send.dart:1047,1196-1215`); (L) **self-sync
  impossible today** — decrypt early-returns on own senderId, own plaintext comes only from the
  pending-send record (`messaging_provider.decrypt.dart:975,642-750`) — new decrypt path must coexist
  with the lost-ack reconcile (expected field-bug epicenter); (L) `emitToNewestTab` premise inverts
  for real devices (`user-room.ts:108-118`); (M) single deliveryStatus enum; (M) JWT/refresh have no
  device dimension (`auth.service.ts:67`, refresh rows are the natural deviceId anchor); (S) push is
  already multi-endpoint, needs endpoint→device linkage only.
- Harness seam exists: `test_e2e` `adoptAccountFrom` (used for reinstall cases) extends to a
  two-devices-one-account case; its failure mode to assert = overwritten-OTP bad MAC.

## Verification

Research only — scout claims spot-checked against source (`key-bundles.service.ts:30-130` read
directly this session; identity-churn branch, epoch three-site invariant, OTP upsert keys confirmed).
External claims from primary sources: Sesame spec (signal.org), Signal linked-devices blog (01/2025),
Meta engineering (WhatsApp multi-device + ADV), eprint 2021/626, Cremers USENIX '23, eprint 2026/484.

## Notes for next session

- Next artifact on owner go: `docs/design/multi-device.md` — Phase 0a/0b + device model + provisioning
  + wire changes. Design review gauntlet before any code (owner standing rule).
- Phase order: 0a → 0b → 1 (devices table; `(userId,deviceId)` bundles/OTPs; re-key the three-site
  epoch filter to `(identity,deviceId)`; per-device claim/count/replenish — note preKeysLow/replenish
  becomes per-device = a §7 wire change hiding in "schema") → 2 (provisioning + fan-out + self-sync)
  → 3 (device mgmt UI) → 4 (history transfer, optional).
- 0a wording trap: the churn branch also fires on legitimate reinstall/migration — use the
  consented-recovery "new device/browser sign-in" framing settled by the 08-16 churn audit.
- Under shared identity, `[identity-churn]` goes QUIET on legitimate device adds (identity constant)
  — that silence is the desired end state; device registration becomes its own notification. Record
  this in the doc so nobody "fixes" it.
- Standing blockers unchanged and prerequisite to any APK/device work: `FIREBASE_SERVICE_ACCOUNT`
  absent on the VM (Android push dead), `.jks` keystore still single-copy on the dev PC.
