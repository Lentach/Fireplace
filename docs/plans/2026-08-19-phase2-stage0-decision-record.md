# Phase 2 Stage 0 — Spec review decision record (2026-08-19)

**Verdict: PASS-WITH-AMENDMENTS. Stage 0 is CLOSED; T1 may start.**
Three independent reviewers (coherence + §7 re-ratification / protection / data-durability), all
read-only, all grounded in the worktree at `94d030d`. The normative amendments are §12 of
`docs/design/multi-device.md` (Stage 0 block, items a–h); this file is the full finding-to-ticket
map and the record of what was CONFIRMED (so nobody re-reviews it).

Inputs: frozen spec v5 + two 2026-08-19 §12 amendments; prior-art research
(`2026-08-19-multi-device-prior-art-research.md`); Phase-2 handoff
(`.cursor/session-summaries/2026-08-19-HANDOFF-phase2-start-here.md`).

## 1. Independent convergence (the strongest signal)

Two mechanism gaps were found independently by two reviewers each:
1. **§5.1 allocator ordering** — the primary must sign the assigned deviceId but the ceremony as
   drawn never tells it the id (coherence F2; protection item 5). → amendment (a).
2. **§6.2 reset vs the device roster** — a completed reset re-minted device 1 and left stale
   `devices` rows + a dead DAK-signed list (protection 6A; durability F10/F11). → amendment (f).

## 2. Blocking findings, all resolved by amendment

| Finding | Reviewer | Resolution |
|---|---|---|
| §5.1 never rebinds N's session to its assigned deviceId — bundle upload would land on device 1 and OVERWRITE the primary (`auth.service.ts:74` hardcodes 1; all per-device paths key off the socket JWT) | Coherence F1 | Amendment (b): token re-issue at `provisioningComplete`; no key upload before rebind |
| Allocator has no call site/ordering; duplicated `provisionDevice` would re-allocate; concurrent duplicate completes could double-commit | Coherence F2 + Protection 5 | Amendment (a): allocate once per `provisioningId` at `openProvisioning`, memoized; pre-increment RETURNING; atomic CAS one-shot complete; stage retires at commit |
| Domain separation: enrollment E and §6.1 lock share sig_IK; list and DAK-rotation share sig_DAK; byte layouts unspecified → CVE-2022-39250-class cross-construction replay | Protection 1 (BLOCKER) | Amendment (d): ASCII context prefixes `fp-enroll-v1\0`, `fp-list-v1\0`, `fp-dak-rotate-v1\0` (first byte ≠ 0x05, disjoint from the FROZEN §6.1 layout); NEW falsification 25 |
| §5.5 revocation is send-direction only; a revoked device retains IK + live ratchets and its messages would still be ACCEPTED (EUROCRYPT'25 WhatsApp bug class) | Protection 2 | Amendment (e): receive-time origin-device check, fail closed; falsification 7 extended |
| §6.2 reset re-mints device 1 under a fresh IK → §5.3 fallback serves it the OLD device 1's ciphertext (the exact L269-272 foreign-ratchet decrypt) + stale roster under a dead DAK | Protection 6A + Durability F10 | Amendment (f): reset allocates from `nextDeviceId`, revokes surviving rows, fresh enrollment, list version monotonic, counter preserved |
| 0016 ambiguity: envelope/authorization backfill unstated; CASCADE FK unstated (it is the SOLE §5.6 destruction mechanism); allocator off-by-one | Durability F1/F2/F3/F4 | Amendment (g) |

## 3. CONFIRMED — do not re-review

- **§5.1 SAS needs NO commitment round and NO security /prototype** (protection 4): `ephPubN` is
  QR-only (authentic AND confidential), so a MITM can never compute either side's SAS and gets one
  blind ~2^-20 online attempt. HARD DEPENDENCY → amendment (c): `ephPubN` must never transit the
  server. The owner-flagged /prototype remains optional for the ~20-bit comparison UX only.
- **Cooldown carve-out grants an attacker nothing** (protection 6B): a password-knowing attacker
  could already change it (revoking all refresh tokens), start and cancel ceremonies; the two
  narrowings (pending never cancelled; post-change cooldowns bind) hold.
- **List freshness TTL deferred past Phase 2** (protection 3) → amendment (h), recorded not dropped.
- **Every §7 wire delta composes with a named landed handler** (coherence item 2 table): key
  exchange is already per-device since Phase 1; `checkOwnKeyBundle` payload is a superset of §7's.
- **§8 compat holds under the landed OTP gate ordering** (coherence item 5): legacy re-upload of
  the SAME identity passes the gate regardless of bundle/OTP race; fresh legacy registration passes
  by the nothing-published carve-out.
- **All five §5.4 own-sender guards exist at the spec's named semantics** (durability item 3; paths
  drifted to `frontend/lib/providers/messaging/messaging_provider.decrypt.dart:962/975/1290/642`
  and `messaging_provider.history.dart:529`).
- **sendToken law composes with the landed re-ack** (durability item 3): per-sender partial unique
  index + same-conversation re-ack-without-re-fan match §4/§5.4 exactly.
- **I9/expiry hold in landed code; the sweep needs ZERO changes** once the (g) CASCADE FK exists
  (durability item 5). **Falsification 24 covers stamp-preservation + placeholder-upgrade** (item 4).
- **`nextDeviceId` amendment composes with §4** (coherence item 3): metadata-only column add,
  default 2 correct for every existing (single-device) account.

## 4. Ticket riders (implementation guidance — bind these to the ticket briefs)

| Ticket | Riders |
|---|---|
| **T1** (0016) | Amendment (g) verbatim; allocator returns PRE-increment (durability F4); do NOT widen `purgeSupersededDevices` here (F11); pin context prefixes (d) wherever T1 stores signature inputs |
| **T2** (signed list) | Context prefixes (d); falsification 25 |
| **T3** (provisioning) | Amendments (a)(b)(c); never-activated-deviceId upload rejection is a NAMED deliverable (coherence F4 — `DevicesService.touch` auto-inserts today); optional SAS-UX /prototype; **T2-review riders:** land client-side NFC normalization of device names alongside the rename UI (the Dart canonical parser deliberately accepts non-NFC today — server is the sole storage gate and only stores NFC, so the client accepted-set is a safe superset until T3 writes names); DAK Keystore persistence (the T2 engine keeps the DAK pair in memory only); wire the T2 `DeviceAuthorityEngine` to the real enable-linking UI |
| **T4** (envelopes/rooms) | `preKeysLow` is counted per-device but ROUTED per-user — route to `device:<uid>:<did>` (coherence F5); legacy fallback treats `originDeviceId IS NULL` as device 1 (durability F5a); red test that a device-2 bundle upload under the shared IK does not trip `[identity-churn]` (landmine 2, coherence F7); envelope stamps never enter expiry/read-TTL (durability F9); `updateDeliveryStatus` full-entity `save()` → column-scoped UPDATE (coherence F6, falsification 19); **T1-review rider:** `message_envelopes.recipientUserId` carries NO FK to `users` — when the T4 write path lands, confirm recipient-user deletion cannot orphan envelopes (their messages must cascade via the `messageId` FK) or add the FK then |
| **T5** (self-sync/lost-ack) | Preserve `tempId != null` in the `history.dart:529` guard flip — dropping it lets a self-sync row consume a pending-send record (durability F6, falsification 6); keep re-ack-WITHOUT-re-fan when the retry path goes envelope-shaped (durability F7, falsification 14) |
| **T6** (revocation) | Amendment (e) receive-time check + falsification 7 send-direction case; reset teardown widening of `purgeSupersededDevices` lands HERE, blocked on T1 columns (durability F11); I6 SILENCE is not yet in `handleGetServedMessageIds` (`chat.gateway.ts:223`) (durability F5b) |
| **T7** (edit re-fan) | Envelope UPSERT is content-only — never a full-row replace that zeroes `deliveredAt`/`readAt`; new envelope-only rows do not write a stale `encryptedContent` (durability F8) |
| **T8** (harness sweep) | Falsify checks at RECEIVE time (the production-bug class everywhere else); falsifications 25, 7-extended, 6-predicate, 8/18/20-idempotency extensions land here if not in their tickets |

## 5. Reviewer outputs

- Coherence: `agent://Stage0Coherence` (full report also at its local file).
- Protection: findings preserved in this record + `agent://Stage0Protection` (its local file write
  failed; the agent output carries the complete findings).
- Durability: `agent://Stage0Durability`.

## 6. T1 closure (2026-08-19/20)

T1 landed at `584f2d3` and passed its per-ticket review (one reviewer, GATE PASS, zero
BLOCKER/FIX; the single NOTE became the T4 rider above). Verified by the orchestrator:
backend **780/52** (+4 allocator specs, red-first), ratchet **PASS 906**, backend count
verifier OK, full wire suite **26/2sk** against the 0016 schema, migration exercised in the
REAL boot path across three backend restarts (indexes survive `synchronize`, both tables
empty, cascade proven live, concurrent allocations distinct, allocator returns the
pre-increment value). Declared deviation accepted: `account_authorizations.enrollmentCreatedAt`
stores the signed `createdAt` so peers can re-verify enrollment `E`. Next ticket: **T2**
(signed device list + E2E cross-check) under its riders.

## 7. T2 closure (2026-08-20)

T2 landed at `6101774` (21 files, +3439). The implementing agent was killed by a rate limit
after backend-green; the orchestrator finished the remainder (analyzer fixes, full suites,
counts, formatting, commit). Per-ticket review: GATE PASS, zero BLOCKER/FIX, three P3 NOTEs
(NFC asymmetry → T3 rider above; redundant double parse in `device-list.service.ts`
enroll/apply — informational; falsifications 16/22 deferral CONFIRMED spec-justified — both
consume `senderListInfo`/`deviceListStale`, which exist only with envelope sends, T4/T5).
Delivered: enrollment (first-write-wins via `userId` PK INSERT + 23505 → `already_enrolled`),
byte-exact `listCanonical` storage with parse-then-reencode ambiguity rejection, version law
with atomic CAS (`stale_version`), wire surface `enrollDeviceAuthority`/`updateDeviceList`/
`getDeviceList` → `deviceAuthorityEnrolled`/`deviceListUpdated`/`deviceList` +
`deviceListChanged` broadcast, cross-construction rejection pinned BOTH directions against the
frozen §6.1 layout with real-Dart vectors (falsification 25), client I7 chain verifier with
buffer-copy discipline, `DeviceAuthorityEngine` (harness-driven, no UI, DAK in-memory — T3
persists it). Verified by the orchestrator: backend **850/55**, flutter **1405/10sk**, wire
**32/2sk**, ratchet 906, analyze clean, both verifiers OK. New flake sighting (2nd class):
`test/services/unread_badge_sync_test.dart` "falls back to the window Badging API" failed once
under back-to-back suite load, green on two other full runs — pre-existing, not T2's.
Next ticket: **T3** (provisioning two-round DH-bound SAS) under amendments (a)(b)(c) + riders.

## 8. T3 closure (2026-08-20)

T3 landed across `69200b2` (settlement amendment) + `f56347b` (backend) + `2ccc76e` (client
crypto/DAK store) + `8dc9d20` (controller/UI/wire tests) + `ca9c6ff` (review fold). Executed
under the T2 rate-limit-recovery precedent TWICE: the writer died on a 429 before any code,
was revived and delivered Stages 1–2 committed, then stalled ~3 h mid-Stage-3 — the
orchestrator recovered the uncommitted Stage 3 from the worktree, verified it, and built
Stage 4 (wire tests) itself.

**Pre-code settlement (spec §12, 2026-08-20, items (i)–(iv)):** OOB payload
`fp-link.v1.<id>.<b64url ephPubN>.<platform>` with manual-code equivalence (camera = Phase 3;
T3 writes NO device names, deferring the NFC rider to the Phase 3 rename UI); byte-exact
`fp-link-sas`/`fp-link-blob` derivations — local RFC-5869 HKDF-SHA256, salt 32 zero bytes
(libsignal 0.8.2 does NOT export HKDFv3 from its barrel; src/ implementation imports
forbidden), SAS = first 4 bytes BE uint32 mod 10^6 as `XXX XXX`, blob =
`0x01‖IV16‖AES-256-CBC‖HMAC32` encrypt-then-MAC with constant-time verify BEFORE decrypt;
rebind tokens travel in `provisioningCompleted` on the opener socket; stage is in-memory,
socket-bound (restart = TTL-equivalent abort, NO table/migration).

**Delivered:** `ProvisioningStagesService` (memoized allocator at open — the FIRST
`allocateDeviceId` caller; synchronous CAS consume / restore / retire-drops-blob);
`ChatProvisioningService` wire surface (`openProvisioning`/`provisioningHello`/
`provisionDevice`/`fetchProvisioningBlob`/`provisioningComplete`/`cancelProvisioning`, T2
refusal conventions, ONE commit transaction incl. `applySignedListUpdate(manager)` +
`createToken(userId, deviceId)` + login-shape JWT); never-activated-upload rejection in BOTH
key-exchange handlers (`device_not_active`) + `DevicesService.touch` hardened to insert only
device 1; client `link_crypto.dart` (spec-exact, stock ProvisioningCipher unused),
`dak_store.dart` (armed write-then-read-back gating the enroll emit),
`LinkCeremonyController` (screen-scoped sink behind ConnectionProvider's single routing
seam), `EncryptionService.adoptProvisionedIdentity`/`discardProvisionedIdentity` (atomic
identity record; enumerated abort discard; service-level invariant locks from the review
fold), DevicesScreen + LinkDeviceScreen + LinkThisDeviceScreen (RpgTheme, l10n en+pl,
`qr_flutter` resolved cleanly so the QR ships alongside the required manual code).

**Falsification → test map (all green):** 8 → wire `full link` (foreign-session complete
`not_opener`, duplicate `already_completed`, post-commit refetch `no_blob`) + link_crypto
unit (wrong-ephemeral blob dies `bad_mac` before decrypt); 15 → link_crypto unit (equal
honest SAS, substituted-ephemeral mismatch, transcript-bound); 18 → wire `two-phase kill`
(nothing committed, opener-only refetch, cancel → opener notice → stage gone) + unit
abort-discard; 20 → wire `concurrent double-link` (loser `stale_version`, SAME stage
re-signed v+2 lands, exactly one device per ceremony); amendment (a) idempotency → duplicate
hello idempotent-if-identical / `ephemeral_already_pinned`, retried provisionDevice
overwrites the stage re-using the memoized id.

**Per-ticket review: GATE PASS** (zero BLOCKER/FIX; one P3 NOTE — service-level keyless
assertion on adopt/discard — FOLDED as `ca9c6ff` rather than ridden, since T4–T8 add callers
near that surface).

**Verified by the orchestrator:** backend **885/57**, ratchet PASS 906, analyze clean,
flutter **1424/10sk**, wire **35/2sk** (restart + ≥20 s settle + alone), both count
verifiers OK; root `CLAUDE.md` §3 + §7 updated (new provisioning contract bullet).

**App-proven (owner-granted blanket tool access), three web origins, account 193:** primary
:8091 (held the account identity) enabled linking → enrollment v1 live; new device :8093
(keyless banner) opened the ceremony → QR + copyable `fp-link.v1.…` code → manual entry on
the primary → **both screens displayed SAS `041 588`** → approve → commit
(`[provisioning] committed userId=193 deviceId=2 version=2`) → N rebound and its
session-bound upload landed the bundle + 20 OTPs at `(193, 2)` under the shared identity
`BVVFJ/DuqMwR`, device 1's bundle byte-untouched (regId 10558, 100 OTPs), `nextDeviceId`=3.
Refusal path on a third keyless origin :8094: ceremony to the SAS step (`865 298`) →
primary CANCEL → opener showed "Łączenie anulowano…", stage discarded, list stayed v2, NO
device 3 row, `nextDeviceId`=4 (gap only), N2 storage held zero identity/DAK/prekey keys
(abort discard). Bonus: a mangled code hit the strict parser's `invalid_code` failure state.

**Deviations / notes for the record:** (1) cancel is accepted from ANY authenticated session
of the account — the server cannot cryptographically identify "the primary" (documented in
code; opener-cancel harmless, third-session cancel is self-DoS). (2) The wire-unreachable
half of never-activated rejection (a live session bound to a non-live deviceId) is covered
by backend unit specs; it becomes wire-reachable when T6 revocation lands. (3) I2 UI gating
(web must not become primary in prod) is Phase 3 comms/UI, per §8's "stated at enable time".
(4) Flutter web a11y tree lags behind navigation in release builds — screenshots are ground
truth for browser proofs; snapshot-then-click in one step is the reliable ref pattern.

Next ticket: **T4** (envelopes + device rooms + per-device history reads) under its §4
riders.
