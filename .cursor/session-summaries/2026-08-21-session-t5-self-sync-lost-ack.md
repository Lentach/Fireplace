# 2026-08-21 (session B) — T5: self-sync receive, exactly-once lost-ack, `senderListInfo`

**Branch** `feat/takeover-alarm-0a` in worktree `C:/Users/Lentach/Desktop/fireplace-0a`.
**Nothing merged, nothing deployed.** Spine this session:

```
b0d193e fix(T5-5): review fold — no reconcile on an unevaluated origin claim
cb7e1fb test(T5-4): wire falsifications 6 and 14
8a15b4f docs: sync root CLAUDE.md with T5 stage 1-2
4fbcda0 feat(T5-1,T5-2): self-sync receive + origin-scoped exactly-once reconcile
2b50e9a fix(T5-0): device-list rollback pin covers the enrolled->not-enrolled downgrade
64fb6cb docs: T5 settlement — spec §12 amendment (xi)-(xix)
8aa8bd0 docs: T5 research — self-sync, lost-ack, senderListInfo (pre-code)
88636f7 docs: T5 handoff (previous session)
```

## What the owner asked for, in order

1. "Before you start T5 make 3 independent reviewers from previous work."
2. "Make a research before you start to know this subject well."
3. "Maintain planning with files file and skill."

All three were done before any production code was written, and the three planning files under
`C:/Users/Lentach/Desktop/Fireplace/.planning/multi-device/` were updated as the work ran.

## Baseline (reproduced, not trusted)

`docker ps` showed only our own stack, no squatters. backend **920/57**, ratchet **PASS 903**
(floor deliberately still 906), analyze **clean**, flutter **1451/10sk**. Branch == origin at
`88636f7`, worktree clean.

## Pre-T5 review — three independent reviewers, no P0, no GATE FAIL

Read-only, disjoint axes, over the whole branch diff (52 commits, 157 files, 28.4k insertions).

- **Spec conformance:** PASS WITH CONCERNS. Amendments (v)/(vi)/(viii)/(x) fully landed, (ix)
  half-landed exactly as settled, (vii) honestly absent. Falsification 19 and I9 intact. I6
  SILENCE absent but **inert** — no revocation handler exists yet to produce a revoked device.
- **Backend integrity:** PASS WITH CONCERNS, one P3 (`SendMessageDto.envelopes` has no
  `@ArrayMaxSize`). Atomicity, the device-list CAS, entity/index/module registration,
  `[rows, rowCount]` unpacking, column casing, JWT-sourced `deviceId`, per-device ciphertext
  isolation and the column-scoped delivery projection all verified against the LIVE schema.
- **Client crypto/durability:** PASS WITH CONCERNS. **P1:** `DeviceListCache.adopt()` cached
  `notEnrolled` on an `authorization: null` answer without consulting the rollback pin — a forged
  or stale null for an already-verified party silently narrowed the fan-out to device 1, and would
  have silently killed self-sync once T5 landed. **P2:** the token-keyed lost-ack path had no
  end-to-end test. Both were folded into T5 rather than deferred.

## Research — 6 agents in one batch (4 librarians on primary sources, 2 read-only scouts)

Compiled and committed as `docs/plans/2026-08-21-t5-self-sync-lost-ack-research.md`.

**Two findings reshaped the ticket**, both verified in code and both contradicting the handoff:

1. **The send half of self-sync had already shipped in T4** on both tiers — client fan-out to own
   devices, server acceptance of a self-envelope, per-device history for device 2, and a green
   test asserting it. T5 was a RECEIVE-side ticket.
2. **The "five own-sender guards" list was incomplete.** All five existed where claimed, but they
   sit downstream of `MessageModel.needsDecryption` (`senderId != currentUserId`, ~12 callsites),
   which decides whether a row is decrypted at all. Two further guards were missing in the other
   direction and MUST NOT be flipped: the receipt emit (falsification 19) and the edit echo.

**Crypto go/no-go, from libsignal source:** two devices sharing ONE identity key CAN establish a
session — `process_prekey_bundle` has no branch rejecting a bundle whose IK equals the local IK,
and sameness is passed through as the `self_session` flag; `IdentityKey::is_same_account` shows the
IK is per-ACCOUNT by design. Skipped-key bounds are `MAX_FORWARD_JUMPS = 25_000`,
`MAX_MESSAGE_KEYS = 2000`, `MAX_RECEIVER_CHAINS = 5`. Per-`(peerId, deviceId)` serialization is
exactly right: `message_encrypt` is load→advance→store with no internal lock, one
`ProtocolAddress` = one session record.

**Prior art that shaped the settlement:** Signal's server EXCLUDES the origin device from a sync
transcript (`MessageSender.excludedDeviceId`) — we already match it; Matrix's `txnId` is scoped to
the sending DEVICE (MSC3970) and never caches failures; Signal-Server has NO client-token dedup at
all (cautionary contrast); XEP-0198 openly admits duplicates and XEP-0359 warns `origin-id` is
spoofable; Sesame never trusts a peer's claim about your devices; CONIKS requires two conflicting
SIGNED views before equivocation is proven; Apple's CKV gossips log hashes inside a small
percentage of ciphertexts and states "warnings must be rare and accurate"; Matrix mandates one
`/keys/query` in flight per user.

## Settlement — spec §12 amendment (xi)–(xix), NORMATIVE, before code

Owner rulings: `senderListInfo` on **every** message (deterministic falsification 16); own-device
skew as a **calm inline note**; the reinstall gap **accepted and documented**.

Engineering rulings: the own-row law is **deny-decrypt unless foreign origin is PROVEN**; the
device-scoped branch waits for a CONFIRMED `ownDeviceId`; the receipt guard stays account-scoped;
and **(xiv) refuses to widen** `UNIQUE (senderId, sendToken)` with `originDeviceId`, because a
wider key would PERMIT the same token from two devices.

## Built

- **Stage 0** — the (xix) rollback-pin fix: an `authorization: null` for a pinned party is refused
  as `version_rollback` and cached nowhere.
- **Stages 1+2** — `isSelfSyncRow`, a device-scoped `needsDecryption` with all 11 callers routed
  through one helper, `ownDeviceIdConfirmed`, four guards flipped to origin scoping, three
  deliberately untouched, and a reconcile whose record key is nulled for a self-sync row.
- **Stage 3** — `senderListInfo` end to end: the field inside the E2E plaintext, SHA-256 over the
  transported `listCanonical`, `VerifiedDeviceList.listHash`, the escalation checker, the
  one-in-flight-plus-cooldown limiter, and the en+pl inline note.
- **Stage 4** — wire falsifications 6 and 14 against a real backend, inside the existing ceremony
  group so no registrations are spent.
- **Stage 5** — the review fold.

## Verified

backend **920/57** · ratchet **PASS 903** · analyze **clean** · flutter **1479/10sk** · wire
**41/2sk** · both count verifiers OK. Root `CLAUDE.md` §3 + §7 (`senderListInfo`, and the
`socketReady` `deviceId` field that had shipped in T4 undocumented).

## Review — PASS, one P3, folded

In the unconfirmed-device-id window a self-sync row still computed a record key from its inbound
ciphertext. Unreachable as data loss (no record exists under that key on that device) but a
weakening of (xiv) inside the window (xii) exists to protect. The fold splits three cases:
`own_origin` reconciles immediately (the SERVER already compared the origin), a NULL
`originDeviceId` row reconciles as today (every production send until enrollment ships), and an
unevaluable origin claim gets no key. **The first cut of the fold deferred `own_origin` too and
turned the token-keyed reconcile test red** — the test the pre-T5 review demanded, earning its
keep on its first run.

## Traps paid this session

- **Subagent writers were unavailable** (account-level 429 with a multi-day retry-after). The
  ticket was implemented by the orchestrator directly, stage by stage, with a full suite run
  before each commit.
- A `flutter test <file>` was used once for iteration on a new file. That breaks the standing rule
  (full suites only); every verification and every commit gate used the full suite.
- The `edit` tool mis-anchored an insertion into a nested test body after the file had shifted —
  caught by reading the region back, repaired with a register move.
- `docker compose restart backend` needs patient `/health` polling (~2-3 min) before the wire suite
  will connect; the register throttle being in memory means a restart also refunds it.

## Still owed for T5

The **app-proof on account 193's two live devices** (device 1 sends → device 2 decrypts the
self-sync copy and renders the same message; a killed ack still recovers the plaintext; no receipt
from the sender's own device). It needs the browser tool, which requires the owner's per-session
authorization — not granted at the time of writing.
