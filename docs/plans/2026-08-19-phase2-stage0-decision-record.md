# Phase 2 Stage 0 — Spec review decision record (2026-08-19)

**Verdict: PASS-WITH-AMENDMENTS. Stage 0 is CLOSED; T1 may start.**
Three independent reviewers (coherence + §7 re-ratification / protection / data-durability), all
read-only, all grounded in the worktree at `94d030d`. The normative amendments are §12 of
`docs/design/multi-device.md` (Stage 0 block, items a–h); this file is the full finding-to-ticket
map and the record of what was CONFIRMED (so nobody re-reviews it).

Inputs: frozen spec v5 + two 2026-08-19 §12 amendments; prior-art research
(`2026-08-19-multi-device-prior-art-research.md`); Phase-2 handoff
(its pickup brief was deleted when its ticket landed, per `.cursor/session-summaries/README.md` §Handoffs).

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

## 9. T4 closure (2026-08-21) — envelopes, device rooms, per-device history

**Landed** across 11 commits, `31ce335` (research + settlement) → `9c42859` (review fold):
backend `98ad178`/`bbcfe8b`/`80b6035`, client `c5ddeed`/`1461e9d`/`abae48c`/`1885038`/`b28d268`,
wire `8c8b12c`. **Per-ticket review: GATE FAIL → all findings folded → closed.**

**Settled BEFORE code** (spec §12, dated 2026-08-20, items (v)–(ix)), grounded in
`docs/plans/2026-08-20-t4-envelope-fanout-research.md` (three codebase scouts + two
primary-source librarians): the send DTO growth + legacy→device-1 normalization at ingest;
`deviceListStale` carrying a `lists[]` array + `tempId` so ONE round trip repairs both views
(Signal-Server returns device ids only and forces a second `/keys` trip; Sesame §3.3 permits
the richer answer, so ours is the Sesame shape); `senderListInfo` DEFERRED to T5 (the server is
blind to it and its falsifications 16/22 are recipient-side); the per-device history join with
an additive `envelopeStatus`; and **(ix)**, which the research itself forced — a new-model row
carries no ciphertext for its origin device, so the landed exact-ciphertext lost-ack reconcile
needed the `sendToken` key or the ONLY plaintext copy would strand.

**Amendment (x), forced during implementation.** Requiring a device-list round trip on EVERY
send to prove that a single-device account is single-device taxed the common path and hung 19
existing suites on an unanswered fetch. Resolution: the client fans out only from a list it
ALREADY holds, and the SERVER refuses a legacy ciphertext send whenever either party is
enrolled, handing back the signed lists. I5 (never silently drop a device) therefore lands
server-side where a client cannot skip it. Corollaries pinned in the amendment: never fan out
without the RECIPIENT's list; resolve parties ABSENT from `lists[]`; `socketReady` echoes
`deviceId` because the client cannot derive which device it is.

**Riders discharged.** `preKeysLow` routed to `device:<uid>:<did>`; legacy fallback treats
`originDeviceId IS NULL` as device 1; landmine-2 regression pin (a device-2 bundle under the
shared IK is not churn — it already held, the branch being identity-keyed, and the test now
prevents regression); envelope stamps never feed expiry or the read TTL; `updateDeliveryStatus`
converted from a full-entity `save()` to a column-scoped UPDATE with the monotonic guard in the
WHERE (falsification 19). **Recipient-FK rider ANSWERED, no FK added:** `deleteAccount` deletes
every message of every conversation the user participates in (`users.service.ts:371`), and the
`messageId` FK is ON DELETE CASCADE, so a recipient-user deletion cannot orphan envelopes.

**Two bugs the settlement had not anticipated, found while building:** `preKeyBundleResponse`
echoed no `deviceId`, so two in-flight per-device fetches for one peer were indistinguishable;
and the pre-key fetch limiter was keyed `(requester, target user)` with a 750 ms floor, which
REFUSED the second bundle fetch of a two-device peer outright — multi-device session
establishment was impossible as landed. Both fixed in `bbcfe8b`.

**Review (fresh reviewer, GATE FAIL → folded as `9c42859`).** One BLOCKER: the lost-ack
reconcile keyed `sendToken ?? encryptedContent`, but a legacy send saves its record under the
CIPHERTEXT while the token is emitted on every send, persisted, and echoed back to the origin
device — so a legacy row carried both, the token won, the lookup missed, and the only plaintext
copy stranded on EVERY lost ack (every production send is legacy until enrollment ships). Fixed
by mirroring the save side (`encryptedContent ?? sendToken`); the suite had missed it because
its own-row helper omitted the echoed token. Two P3s folded with it: the same precedence bug in
reverse on the success path (a fan-out record was never consumed, leaking on disk), and
`stampEnvelope` being dead code (now wired into `handleMessageDelivered`, stamping the REPORTING
device, kept separate from the recipient-only row projection).

**Verified:** backend **920/57**, ratchet **PASS 903** (improved from the 906 baseline; floor
deliberately not lowered mid-ticket), analyze clean, flutter **1451/10sk**, wire **39/2sk**
(+4 T4 falsifications: amendment (x), 5, per-device delivery, 13's marker), both count
verifiers OK.

**APP-PROVEN on account 193's two real devices** (peer 297 on a third origin). One send
reproduced the whole designed path live: `[send] REFUSED legacy send to an enrolled party
senderId=297 recipientId=193 stale=193@v2` → client adopted the list and resent as a fan-out →
`newMessage emitted to recipient 193` → message 649 carries TWO envelope rows, `(193,1)` and
`(193,2)`, with DIFFERENT ciphertexts (`3:MwgUEiEF` / `3:MwgAEiEF`) and a NULL legacy column →
**both devices rendered the same plaintext**, each decrypting its own envelope.

**Deviations recorded.** (1) A refusal code not in the amendment, `unknown_envelope_user`:
without it a client could have the server deliver ciphertext to a third party the send never
named. (2) A legacy send keeps its `encryptedContent` column as well as getting a device-1
envelope, so a legacy row stays readable to today's clients for the whole §8 rollout window.
(3) A ciphertext-less send (PING) keeps single-target delivery to device 1 — without that
fallback those sends reached nobody. (4) C5 was not in the plan: C1 parameterized only the send
side, so every inbound decrypt still used address `(sender, 1)` and a peer's device-2 envelope
would Bad-MAC — fan-out would have been one-directional.

**Process:** BOTH dispatched writers died to the same 429, and a third went silent mid-stage
while the broker still reported it RUNNING. `hub jobs` status is NOT liveness — compare
working-file mtimes against the clock. Recovered work was verified with full suites before being
committed, never trusted.

Next ticket: **T5** (self-sync + lost-ack + client `sendToken`) under its §4 riders. It inherits
a live `sendToken` path, per-device addressing on both directions, and the own-sender guards
deliberately left untouched at `decrypt.dart:963/975/1294` and `history.dart:529`.

## 10. T5 closure (2026-08-21) — self-sync receive, exactly-once lost-ack, `senderListInfo`

Spine: `8aa8bd0` research → `64fb6cb` settlement (spec §12 items **(xi)–(xix)**) → `2b50e9a`
stage 0 → `4fbcda0` stages 1+2 → `8a15b4f` docs → `cb7e1fb` wire falsifications → `b0d193e`
review fold. **Not merged, not deployed.**

**The research rewrote the ticket before a line was written.** Two findings, both verified in
code, both contradicting the handoff that opened the ticket:

1. **The SEND half of self-sync had already shipped in T4**, on both tiers — the client already
   fanned out to its own other devices, the server already accepted a self-envelope for a
   sender's other device and refused only the origin, and per-device history already served
   device 2 its own envelope. A green test already asserted it. T5 was therefore a RECEIVE-side
   ticket, which is not what its brief said.
2. **The "five own-sender guards" list was incomplete, and the missing one was decisive.** All
   five named sites existed at their claimed lines, but they all sit downstream of
   `MessageModel.needsDecryption` (`senderId != currentUserId`), which feeds ~12 callsites and
   decides whether a row is decrypted at all. Flipping the five without it would have left
   self-sync dead with no visible cause. Two more guards were missing from the list in the other
   direction: the receipt emit (`history.dart`) and the edit-echo reconcile, both of which MUST
   stay account-scoped — device-scoping the first is falsification 19 in red.

**Settled before code (§12 (xi)–(xix)).** The own-row law is **deny-decrypt unless foreign
origin is PROVEN**, ordered: `own_origin` → never decrypt, reconcile by token;
`(originDeviceId ?? 1) == ownDeviceId` → same in legacy shape; otherwise self-sync → decrypt as
inbound against the origin device's session, never touching the pending record. The device-scoped
branch waits for `socketReady` to CONFIRM `ownDeviceId`, because it defaults to 1 and a real
device 2 would otherwise treat its own sends as a sibling's and burn the only plaintext copy on
`[Decryption failed]`. Owner rulings: `senderListInfo` rides EVERY message (not a sample, so
falsification 16 is deterministic); own-device skew shows a calm inline note; the reinstall gap
is accepted and documented, matching Signal and Matrix.

**One settlement item is a deliberate REFUSAL to harden.** (xiv): the existing
`UNIQUE (senderId, sendToken)` was NOT widened with `originDeviceId`, because a wider key would
PERMIT the same token from two devices — the opposite of the intent. The tuple stays the client's
match law; the server contributes uniqueness plus the rule that the token reaches only the origin
device.

**Landed.** `isSelfSyncRow` + a device-scoped `needsDecryption` with every caller routed through
one helper; `EncryptionProvider.ownDeviceIdConfirmed`; four guards flipped to origin scoping and
three deliberately left account-scoped; the reconcile record key nulled for a self-sync row
(asserted, not left to the server withholding the token); `senderListInfo`
`{ownVersion, ownListHash, peerVersion, peerListHash}` hashed over the byte-exact transported
`listCanonical`, with a bare claim never alarming, at most ONE rate-limited re-fetch per account,
and a calm en+pl "syncing your devices" note that borrows nothing from the identity surface;
`VerifiedDeviceList.listHash`; and the (xix) rollback-pin fix from the pre-T5 review.

**Pre-T5 review (three independent reviewers, no P0).** Spec conformance, backend integrity and
client durability were each reviewed before the ticket started, on the owner's instruction. Their
actionable findings were folded INTO T5: the P1 enrolled→not-enrolled device-list downgrade
became stage 0 and amendment (xix); the P2 (no end-to-end test for the token-keyed lost-ack path)
became a test in stage 2 — and that test is what caught the first cut of the review fold.

**Ticket review: PASS, one P3, folded (`b0d193e`).** In the unconfirmed-device-id window a
self-sync row still computed a record key from its inbound ciphertext — unreachable as data loss
(no record exists under that key on that device) but a weakening of (xiv) in exactly the window
(xii) exists to protect. The fold distinguishes three cases: `own_origin` reconciles immediately
(the SERVER already compared the origin), a NULL `originDeviceId` row reconciles as it does today
(every production send until enrollment ships), and an unevaluable origin claim gets no key at
all. The first cut deferred `own_origin` too and turned the token-keyed test red.

**Verified:** backend **920/57** · ratchet **PASS 903** (floor still 906) · analyze **clean** ·
flutter **1479/10sk** · wire **41/2sk** (+ falsifications 6 and 14, zero new registrations).
Falsifications 16 and 22 landed as units. Root `CLAUDE.md` §3 and §7 updated (the §7 gap for
`socketReady`'s `deviceId`, shipped since T4 but undocumented, was closed here too).

**APP-PROVEN (browser granted for this proof only) — self-sync works on two real devices.**
Account 193, devices 1 (:8091) and 2 (:8093), peer 297, conversation 92. Device 1 sent
"T5 self-sync proof: device 2 must decrypt this". The server wrote **message 698 with TWO
envelopes and none for the origin**: `(193,2)` = `3:MwgBEiEFcS` (the self-sync copy) and
`(297,1)` = `2:MwohBY/T/9`, distinct ciphertexts, `encryptedContent` NULL. **Device 2 decrypted
it and rendered the plaintext once**, as an own-side bubble — not a duplicate, not
`[Decryption failed]`, not the `none_for_device` placeholder (screenshot
`t5-device2-selfsync.png`). That is precisely what every guard in (xi)/(xiii) exists to allow,
and it was impossible before this ticket.

**Falsification 19 verified live:** after device 2 opened the conversation and read its own copy,
message 698's `deliveryStatus` was still `SENT` and BOTH envelope rows had `deliveredAt` and
`readAt` NULL, with no `messageDelivered` in the backend log. A sender's own second device
produces no receipt.

**Origin-side own_origin verified live:** a full reload of device 1 re-served message 698 as its
own row with no ciphertext for it, and the device still rendered the plaintext — the branch-1
path (never decrypt, restore locally) surviving a cold start.

**NOT exercised live: the killed-ack reconcile.** Driving a SECOND send needed a fresh compose,
and the Flutter web release composer would not accept programmatic text after the first send
(CanvasKit re-creates its text-editing host; `Input.insertText` reached a stale `<textarea>` the
framework ignored, and `sendCharacter` reached the framework but the run was stopped before a row
committed). The path itself is covered by wire falsification 14 (a reused `sendToken` re-acks the
SAME row and re-fans nothing) and by three unit contracts including the token-keyed round trip;
what is missing is only the live keystroke path. **A future session should either drive the
composer with `sendCharacter` from a freshly reloaded page or add a test-only send hook — do not
claim this half is app-proven until it is.**

**Re-review (three fresh reviewers, 2026-08-21, on the FINAL state at `c937d18`): no P0.** One P1,
two P2, three P3 — folded as `a64fd76` and settled as spec §12 amendment **(xx)**.

- **P1, latent data loss, fixed before it could ship.** The confirmed device id was install state,
  not session state: `EncryptionProvider` is a process singleton and `clearAll()` never reset
  `_ownDeviceId`/`_ownDeviceIdConfirmed`, so a device id confirmed as N for one account survived
  into the next login. There an own row of a device-1 account looks foreign-origin, `isSelfSyncRow`
  is true, and the self-sync branch would hand this device its OWN ciphertext to the ratchet —
  `[Decryption failed]` over the only plaintext copy. The same misjudgement existed for a
  `socketReady` that carries no `deviceId` (it was treated as "device 1, confirmed"). Both fixed:
  reset on logout/account switch, and silence never confirms. Unreachable while enrollment is
  unshipped, which is exactly why it had to be caught now.
- **P2, security.** The durable split-view record used raw `record()` with peer-supplied,
  non-DAK-signed fields, on a branch reachable from every inbound message — so a peer forging a
  mismatch could evict every other forensic row from the 80-entry ring. Now deduped per sender.
- **P2, coverage.** `senderListInfo` had well-tested pure logic and untested WIRING. Added: the
  send path attaches the claim for both parties (and omits an unknown party rather than reporting
  version 0), and five receive-side cases including a claim storm that proves the re-fetch budget
  holds at exactly one.
- **P3, fixed anyway.** The calm skew note was raised on every mismatching claim, a value the peer
  controls, so it could be pinned on permanently; it is now bounded to the re-fetch window.
- **P3s accepted, not fixed, and recorded rather than claimed:** wire falsification 6 proves
  self-envelope ROUTING with a synthetic ciphertext but not decryptability (a harness self-session
  belongs to T8's sweep), and the calm note has no widget test asserting it borrows nothing from
  the identity surface.
- **Verified after the fold:** flutter **1486/10sk**, analyze clean, wire **41/2sk**, backend
  untouched at 920/57 · ratchet 903.

## 11. T6 closure (2026-08-21) — revocation and the §6.2 reset-roster teardown

Spine: `5fee421` settlement (spec §12 **(xxi)–(xxix)**) → `a72f70c` revokeDevice + the two session
gates + I6 silence → `ac1b4d9` reset roster teardown + replacement enrollment → `e17cb8b`
accept-side revocation, revoke UI, kicked-device logout → `0ef1e19` wire falsification 7 →
`b672e1d` review fold → `43cdc67` the fix the app-proof forced.

**Reviewed twice, no P0/P1 either time.** The ticket reviewer returned SHIP-WITH-FIXES with one P2
(the reset teardown's own docstring claimed "ONE transaction" while `revokeAllForUser` and
`createToken` ran on the autocommit connection) and one P3 (the revoke UI reads "primary" as device
1). A second reviewer re-read the fold whole and returned SHIP with zero findings.

**Deviations and rulings worth remembering:**

- **Two findings reshaped the ticket before code.** The push `deviceId` columns existed but were
  NEVER written, so §5.5's "deletes its push rows" was unimplementable; and `JwtStrategy` never read
  the `deviceId` claim, so a revoked device kept every guarded REST route — media upload included —
  for the life of its 24 h token. One change fixed both, which is why the owner ratified the
  full-HTTP option.
- **A lockout was found and fixed while building, not after.** Login hardcoded `deviceId = 1`. The
  moment a reset revokes device 1, that mints a token for a revoked device and both new gates
  correctly refuse it — the owner locked out with the correct password. Login now resolves the live
  primary; the regression test names the lockout.
- **The authorization row is REPLACED, never dropped** (amendment (xxix)). The first draft dropped
  it, which would have destroyed the `listVersion` (f)(iii) requires be carried forward and made the
  account read as not-enrolled — which (xix) refuses as a rollback.
- **The accept-side gate's fail-closed reading is deliberately narrowed** (spec (xxvii) rider): when
  the verified list FETCH fails, withholding applies to `originDeviceId >= 2` only. The strict
  reading let one withheld `getDeviceList` answer silence every conversation of a single-device
  account, and bought ~nothing, since §5.5 refuses to revoke a primary and the one path that revokes
  device 1 (the reset) also replaces the account identity.
- **The first version of the accept gate had a real bug the suite caught:** withheld rows were being
  stamped `[Decryption failed]` by the post-retry sweep and were arming session-rebuild requests
  against a healthy peer. Withheld ids are now tracked and both paths skip them.

**Owed, recorded rather than claimed:**

- **Falsification 12 (per-device epoch after a reset) is NOT wire-proven.** The harness has no route
  to complete a §6.2 ceremony (72 h delay, no DB access to age it), so it stays unit-proven by
  `reset-roster.service.spec.ts` and the `purgeDeviceMaterial` contracts.
- **`list_device_mismatch` is unit-proven only** — reaching it on the wire needs two linked
  non-primary devices in one run.
- **The §6.2 reset teardown itself has never run against a live account.** Every part of it is
  unit-proven; the app-proof exercised revocation, not recovery.

**App-proof (account 193, two real devices, DB + logs as ground truth).** It earned its keep: the
revoke button failed live because `revokeDevice` never armed its DAK from the Keystore, and the unit
suite was green because it pre-armed the engine — a test that could not fail. After `43cdc67`:
device 2 kicked with the stated Polish reason, its 2 decrypted rows and 30 Signal key entries intact
across a reload (logout semantics, no remote wipe); device 1 unbroken and still sending; list v2 →
v3; device 2's bundle, OTPs and refresh token gone while device 1 keeps registrationId 10558, 3
sessions and 100 OTPs; and on one conversation, message 698 (pre-revocation) carries envelopes
`(193,2)+(297,1)` while message 775 (post-revocation) carries `(297,1)` ONLY — falsification 7 in
the app.

**Verified at `43cdc67`:** backend **982/61** · ratchet **900** (floor 906, PASS) · analyze clean ·
flutter **1510/10sk** · wire **42/2sk**.

## 12. T7 closure (2026-08-22) — edit re-fan under envelopes

**Settled first, as always: spec §12 (xxx)–(xxxiv), committed at `4a57f74` BEFORE any code.** The owner
ratified all five recommendations. Four filled gaps; **(xxx) fixed a latent bug in the FROZEN text**,
found by reading the receive path rather than the spec: §5.7 permits an edit from any of the sender's
devices, but the receiver keys its Signal session off `messages.originDeviceId`
(`messaging_provider.decrypt.dart:1354-1355`, whose own comment already defines the field as "the
device that PRODUCED this ciphertext"), and the edit receive path kept the row's ORIGINAL value. Any
edit from a second device would therefore have Bad-MAC'd on every receiver — a row that decrypted
fine before the edit. `originDeviceId` is now defined as *the producer of the ciphertext currently
stored*, and an edit updates it. Falsification 24 did NOT cover this: it asserts a non-origin edit
SUCCEEDS, never that a third device DECRYPTS it. T7 adds that assertion.

**The defect was bigger than the ticket's framing.** An edit did not merely miss the peer's other
devices — it wrote the LEGACY `messages.encryptedContent` column and never touched
`message_envelopes` at all. Since a new-model row keeps that column NULL and every device reads its
own envelope, the edited text existed ONLY in the live socket emit: every device, the peer's device 1
included, re-read the ORIGINAL ciphertext after a reload. T7 is a migration of edits onto the envelope
table, not just a wider fan-out.

**Spine:** `4a57f74` settlement → `f3baaf7` backend (DTO + the first UPSERT in this codebase + one
transaction + per-device fan) → `3c9e16e` client (reuse the send fan-out; adopt the producing device;
split the own-row branch) → `3077d06` wire falsification 24 → `febbbae` the stale-refusal divergence
fix + docs → `eaf1e78` review fold → `7c297c2` the second fold.

**Reviewed twice, no P0 and no P1 either time.** The ticket reviewer returned SHIP-WITH-FIXES and
confirmed the conflict clause, the transaction, (xxx) end to end, the guard ordering and the (xxxii)
discriminator; its four findings (two P2, two P3) were folded. The fold reviewer then caught that the
test guarding the retry-budget reset **could not fail** — four bounces trip the exhaustion path, which
clears the counter itself. Three bounces leave it at 3, and the test was then PROVEN to fail with the
production line removed (1518 passing + 1 failing) and pass with it restored (1519).

**Deviations from the literal spec, both recorded as amendments:** (xxxii) the legacy column is written
for LEGACY rows only, because `content === '[encrypted]' && encryptedContent == null` IS the server's
new-model discriminator, so writing it would silently reclassify a row after one edit; and (xxxi) the
staleness bounce reuses the existing `deviceListStale` event rather than inventing an
`editMessageFailed` code, which keeps §5.7's "reject paths unchanged" literally true.

**T7 also created a refusal with no listener, and that is the transferable lesson.** Giving the edit
path a `deviceListStale` answer left the client with no handler: `onDeviceListStale` correlates by
`tempId` and returned early, while an edit refusal carries `messageId` — so the optimistically applied
edit would have sat on the editing device forever while the server and the peer kept the old text,
surviving a reopen. **For every refusal added, name the client code that drives it to a conclusion.**

**Proven live.** Wire falsification 24 passes (43/2sk) and the app-proof ran on account 193 against
peer 297. Message **1012**: sent, DELIVERED (`deliveredAt 04:41:15.544`, `createdAt 04:41:15.511`),
then edited from the app at 04:42:25 (`[edit] … deviceId=1 envelopes=1`). Afterwards the row carries
`editedAt`, its legacy column is still NULL, `deliveryStatus` is still READ, and **the envelope's
`deliveredAt` and `createdAt` are byte-identical to their pre-edit values** — the content-only UPSERT
preserved them, which is durability finding F8 observed on a real row rather than asserted through a
mock. The peer rendered "T7 AFTER refan" with the *edytowano* marker and **still showed it after a
full reload**, which before T7 would have resurrected the pre-edit text from the envelope. Server-side
replacement of the envelope ciphertext is proven separately by the wire run (message **1011**:
`originDeviceId 7` — the EDITING device, not the device 1 that sent it; bob's envelope holds the
edited bytes with `deliveredAt` still set; alice's device 1, which had NO envelope because it was the
origin of the send, has an INSERTED one).

**Owed, recorded not claimed:** the wire suite cannot read envelope stamp columns, so falsification 24
asserts the ROW projection only — its comment now says so explicitly, and the stamp survival rests on
the unit assertion plus the SQL evidence above. **The harness has NO ceremony headroom left**:
`provisioningComplete` is throttled 10 per 15 minutes keyed by USER, every ceremony client adopts
alice's account, and the suite spends exactly that budget — so falsifications 6 and 24 now share one
linked device via a memoized fixture, and any new ceremony-based test in T8 must do the same. Related
product wart, NOT fixed and needing an ask: the throttler guard THROWS instead of emitting, so a user
who burns that cap gets silence and a link UI that hangs with no error, unlike every other refusal in
this codebase.

**Verified at `7c297c2`:** backend **990/61** · ratchet **886** real (floor 906, PASS — typing the edit
handler removed 20 more unsafe-access findings than the ticket added) · analyze clean · flutter
**1519/10sk** · wire **43/2sk**, both count verifiers OK.

## 13. T8 closure (2026-08-22) — the harness sweep

Seven items, every one of them a proof an earlier ticket left owed. Settled BEFORE code as spec §12
amendments **(xxxv)–(xxxviii)** (`343fc1a`), after a seven-scout research round. Spine: `343fc1a`
settlement → `6f746dc` 14f pin refusal → `a85129b` 14e skew-note isolation → `543bd92` 14g stamp
write-half → `0435ea8` 14c `list_device_mismatch` on the wire → `46622dc` 14b real self-sync decrypt →
`af90c77` 14d real §6.2 reset + falsification 12 (and 14a) → `cecdf44` review fold. Reviewed twice —
a ticket reviewer (one P3, folded) and a fresh reviewer on the fold (zero findings) — no P0/P1/P2
either time.

**Three of the seven items were not what the brief said they were, and saying so is the point of this
section.**

- **14c was never blocked on 14a.** The T6 comment claiming `list_device_mismatch` "needs two linked
  non-primary devices" is false: the gauntlet needs the PRIMARY as caller and ONE live non-primary as
  target, and the second device the note asked for is the primary caller every enrolled account already
  has. The rung is pre-write and is checked BEFORE the DAK signature, so the probe submits the
  account's own current signed list — an honest signature over the wrong SET, which is exactly the case
  (xxi) exists for — and mutates nothing. It costs one `revokeDevice` (limit 60) and zero ceremony
  budget.
- **14b needed no second account and no production seam.** It reuses the memoized ceremony fixture and
  separates the two same-account Signal keystores in TIME (snapshot/restore of the static mock map)
  around the shipping `adoptProvisionedIdentity`. A `storagePrefix` parameter on `EncryptionService`
  was considered and rejected: a test-only concept in shipping at-rest key shapes, for no production
  benefit.
- **14a's real constraint is the REGISTER budget, not the ceremony budget.** `/auth/register` is 10 per
  HOUR per IP and — with no nginx locally — the whole `test_e2e/` directory shares one bucket. Measured:
  the default run already spends it to the edge, and adding a third account to `full_stack_e2e_test.dart`
  throttles `takeover_alarm_test.dart` into `ThrottlerException`. So the second enrolled account exists
  **in the opt-in reset probe**, which is its only consumer, rather than in the shared suite. Raising a
  production anti-abuse cap to fit a test was rejected. This is a NEW cliff, sitting beside the ceremony
  cliff T7 found, and it will bite the next person who adds an account anywhere in that directory.

**What is now proven that was not.** A sender's second device DECRYPTS a real self-sync envelope on the
wire (14b) — falsification 6 only ever proved routing, with a synthetic ciphertext. `list_device_mismatch`
is wire-proven (14c). A real §6.2 reset ran END TO END against a live account for the first time in the
program, and falsification 12's per-device epoch claim is proven with TWO real `(identityPublicKey,
deviceId)` partitions (14d): live evidence on user 537 — devices 1 and 2 both `revokedAt`, device 3
primary and live, `nextDeviceId` 3→4 never reusing 1, `key_bundles` reduced to device 3 under the NEW
identity, every old-epoch pre-key gone, and `account_authorizations.listCanonical` BYTE-IDENTICAL across
the reset, which is (xxix).

**A throttled `pinMessage` no longer strands optimistic state (14f).** The obvious fix was a trap and is
forbidden by (xxxvii): the guard refuses pre-handler holding only `{conversationId, messageId}`, so
answering `messagePinned` with a null id would unpin a conversation that had a DIFFERENT message pinned,
and echoing the attempted id would confirm a pin that never happened. The refusal is a dedicated
`messagePinFailed`, and the device restores what it overwrote from a pre-pin snapshot.

That ticket's audit claimed ZERO unreachable `THROTTLE_ANSWERS` entries. **The phase gate corrected
this.** `updateDeviceList` maps to a `deviceListUpdated` answer that NO production client listens for
(zero `socket.on('deviceListUpdated')` in `frontend/lib`), and no production code emits
`updateDeviceList` either — list mutation goes through `provisionDevice`/`revokeDevice`, and only
`test_e2e/support/e2e_test_client.dart` drives it. So the entry is harness-reachable, not
production-reachable: benign today precisely because the request is unreachable too, but it MUST be
wired before Phase 3's device-management UI drives `updateDeviceList`, or that UI stakes state on an
answer it never receives — the same half-a-feature class as T5's confirmed-device-id and T7's
`deviceListStale`.

**14g closes by ACCEPTING evidence, deliberately.** Per-device `deliveredAt`/`readAt` are barred from the
wire — I9 keeps them out of expiry, §5.3 keeps them behind the single §4 projection, and exposing them
would reveal WHICH recipient device read a message, on a public repo. So survival is pinned by the
content-only conflict clause plus the recorded SQL check, per (xxxviii). Two real defects were fixed
while establishing that: the old test's title claimed it protected `readAt`, which is **never written by
any code path** and therefore trivially "survives"; and `stampEnvelope` had no unit test at all, so its
column-scoped `set` and its WRITE-ONCE `IS NULL` predicate — the property that makes the first delivery
time the durable one — were unpinned.

**Every guard added got the two-way proof, in this session, and two of them taught us something.**
Making `adoptProvisionedIdentity` mint a foreign identity did NOT fail at 14b's identity-equality
assertion — it died earlier at `uploadKeyBundle` with `identity_locked`, because the §6.1 registration
lock refuses a linked device publishing an unauthorized identity. Amendment (xxxv) was corrected in
place rather than left standing on a justification now known to be wrong. And the reset probe's first
run revealed that the recovering device MUST rebind to the deviceId-bound token the teardown issues:
without it, 20 fresh-epoch pre-keys landed on the REVOKED device 1's partition.

**✅ APP-PROVEN 2026-08-22 (owner granted the browser), and it is a TWO-WAY proof at the app level.** Account 193 (device 1) in conversation 92, real UI throughout. Pinned message 649 for real, then burned 193's `pinMessage` budget (60/15 min, keyed by USER) from a second authenticated socket, then pinned a DIFFERENT message from the UI while throttled. **With the fix:** the server refused it (`REFUSED event=pinMessage userId=193 answeredWith=messagePinFailed`), the DB stayed at 698, and the banner showed **698** — converged. **With `onPinMessageFailed` neutered to pre-T8 behaviour and the bundle rebuilt:** same operation, same refusal, DB still 698 and ZERO successful pins in the window — but the banner showed **649**, a pin the server never stored. That divergence IS the defect, seen live. Restored, rebuilt, re-verified converged; conversation 92 left unpinned as found.

**⚠️ The app-proof produced a FALSE NEGATIVE first, and it is worth remembering.** The budget was initially burned over a hand-rolled socket.io v4 frame; the token never landed in `handshake.auth`, the gateway disconnected the socket, and the in-flight requests were counted under the ANONYMOUS handshake-address tracker. The throttle log said `userId=anon`, the UI pin then SUCCEEDED, and it looked exactly like the fix failing. **Read the tracker in the log line before believing a throttle result** — and drive the wire with a real `socket.io-client`, not hand-rolled framing.

**✅ FIXED, not just recorded (owner: "please resolve") — the §6.2 recovery ack now has a client half.** The server has always reissued a session bound to the newly allocated device and said so at its own emit site (`chat-key-exchange.service.ts:236-239`): *"the client MUST adopt these before uploading one-time pre-keys, or those keys land in the namespace the teardown just abandoned."* Nothing implemented it — `access_token`/`refresh_token` appeared NOWHERE in the client, and `onKeyBundleUploaded` ignored `deviceId` while immediately replenishing pre-keys on `identityChanged`. A recovering user therefore published their new pool under the device the teardown had just REVOKED: peers were served a bundle with no one-time pre-key (the "half-published" state `encryption_provider.dart` says it exists to prevent), and the next reconnect was refused by the §5.5 gate. `ConnectionProvider` now adopts the session through `onSessionRebound` (wired to `AuthProvider.adoptProvisionedSession` — the same storage path as login and as the §5.1 rebind), reconnects with `immediate: true`, and only THEN delivers the ack. **The contract is an ORDERING one, so the tests pin ordering:** `['adopt','ack']`. Two-way proven — pre-fix ordering yields `['ack','adopt','ack']` and the guard fails. Two adjacent hazards were caught while building it: the connect debounce would have deferred the rebind past the upload (hence `immediate`), and a re-entrancy latch left unreset would have made a SECOND recovery in one session silently skip the rebind. The server half shipped in T6; this was invisible for two tickets because the ceremony had never run end to end until T8's probe.

**Owed, recorded not claimed.** (1) **`setDisappearingTimer` is the same divergence class as 14f** —
throttled 60/15 min, writes optimistic state, absent from `THROTTLE_ANSWERS`, not unwound by `error`.
Found during the 14f audit, deliberately NOT fixed so the ticket stayed single-purpose. (2) The reset
probe is opt-in and therefore defends nothing in CI until the registration budget has room.

**Verified at `cecdf44`:** backend **1007/61** · ratchet **PASS 889** real (floor 906, not lowered) ·
analyze clean · flutter **1530/10sk** · wire **44/3sk** · opt-in reset probe **1/1**
(`--dart-define=RESET_PROBE=true`), both count verifiers OK.

## 14. The T1–T8 phase gate (2026-08-22) — and T9, the four defects it found

**Three independent reviewers over `bf11861...b048ec9`** — 103 commits, 197 files, +38341/−1828 —
each with a distinct lens, because three identical passes would have found one thing three times.
Verdicts: spec conformance **SHIP WITH FIXES**, test integrity **SHIP WITH FIXES**, security/crypto
**SHIP WITH FIXES (one P0, two P1)**. No amendment was found violated; every one (a)–(xxxviii) that
is reachable from code was confirmed implemented.

**The test-integrity findings are folded at `4c0e0bf`.** Four tests could not fail under the mutation
they existed to catch: the §6.2 teardown atomicity was only half-pinned (dropping the
`manager ? … : this.refreshRepo` branch stayed green while the session wipe silently returned to the
autocommit connection); `resolveLoginDeviceId`'s "live rows only" guard survived an
`IsNull()`→`Not(IsNull())` inversion that would have reintroduced the T6 lockout; the `sendToken`
reconcile's cross-conversation refusal and sender scoping were untested — `findBySendToken` was not
even in the mock; and NOTHING asserted `devicesSyncing` is ever RAISED, so deleting the flag-raise
left the suite green while the note silently never appeared. That commit also corrected an
overstated claim in §13 (see the `updateDeviceList` paragraph there).

**The security findings became T9.** Settled first as amendments **(xxxix)–(xliii)** at `27acd86`,
built at `290cacc`. What is worth carrying forward is not the four fixes but the four things the
research and review CHANGED about them:

1. **The P0's obvious anchor was the wrong anchor.** `peerTofuIdentityBase64` reads a hard-coded
   `(peer, device 1)`. Ids are never reused, so a post-§6.2 account has NO device 1 — anchoring
   there finds nothing for exactly the accounts that just survived a takeover. The anchor comes from
   the I7-verified list instead.
2. **The P0 is not cold-cache bypassable, and that is structural, not incidental.** Reaching a
   peer's device >1 requires the verified list (`_resolveFanOut` gates fan-out on
   `recipientList != null`), and that same list supplies the anchor. A cold cache means there is no
   device-2 build to attack. Worth re-deriving before anyone "optimises" `_resolveFanOut`.
3. **Two of the gate's own premises were WRONG and the research caught both.** The teardown does not
   run from a cron — it runs lazily inside `handleUploadKeyBundle`, which already holds the socket
   server, so the eviction needed no new plumbing. And leaving `account_authorizations` untouched is
   spec-MANDATED by (f)(iii)/(xxix), not a bug; the probe already asserts that expecting otherwise
   asserts a spec violation. Also: the reset is NOT silent (push fires on both paths) — only the
   ENROLMENT was — and because a password thief can already run the 72 h ceremony, password re-auth
   defends nothing. The age gate is the control that bites.
4. **The first cut of the eviction would have stranded every recovery**, and the review caught it.
   The recovering client is still authenticated as its PRE-reset device id, so its own socket sits in
   a room the teardown just revoked; evicting before the ack disconnected the caller, and socket.io
   marks a socket disconnected synchronously, so the emit carrying its reissued session silently
   no-oped. Eviction now runs strictly after the ack and never touches the caller. **A test pins the
   ORDER, not just the outcome** — the outcome-only version passed with the bug present.

**Owed, recorded not claimed.** (1) **(xl)** — binding the account identity key into the DAK-signed
list is the durable form of the P0 fix and is deferred: it changes the (d)-governed canonical bytes
and needs a list-version migration on every enrolled account. (2) The peer-reset↔anchor interaction
((xxxix) refusing after a peer's own §6.2 key change) is REASONED from source, not observed by any
test. (3) `setDisappearingTimer` and the opt-in probe's CI gap carry forward from §13 unchanged.

**Verified at `290cacc`:** backend **1029/62** · ratchet **PASS 889** real — the exact pre-change
baseline, so the whole gate fold plus T9 added ZERO lint errors · analyze clean · flutter
**1541/10sk** · both count verifiers OK. **The wire suite was NOT run: Docker was in use by another
agent.** Every guard in both commits is two-way proven, mutation by mutation, restored
byte-identically.
