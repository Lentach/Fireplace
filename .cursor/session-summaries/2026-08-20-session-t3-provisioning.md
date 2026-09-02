# T3 — provisioning ceremony (two-round DH-bound SAS) built, reviewed, app-proven

**Date:** 2026-08-20 (second session of the day; the first wrote the handoff this one executed)

## What was done

- **Baseline reproduced at `260ddb6`** before any work: backend 850/55, ratchet PASS 906,
  analyze clean, flutter 1405/10sk, wire 32/2sk (restart + ≥20 s settle + alone).
- **Pre-code settlement amendment committed (`69200b2`, spec §12 dated 2026-08-20, items
  (i)–(iv))** per the Stage-0 "settle before code" rule: OOB payload
  `fp-link.v1.<provisioningId>.<b64url ephPubN>.<platform>` + manual-code equivalence (manual
  is the REQUIRED path; camera = Phase 3; T3 writes NO device names so the NFC rider defers to
  the Phase 3 rename UI); byte-exact `fp-link-sas`/`fp-link-blob` derivations — **local
  RFC-5869 HKDF-SHA256 with salt = 32 zero bytes** (libsignal_protocol_dart 0.8.2 does NOT
  export HKDFv3 from its barrel — verified in the pub cache; src/ implementation imports
  forbidden), SAS = first 4 bytes BE uint32 mod 10^6 rendered `XXX XXX`, blob =
  `0x01‖IV16‖AES-256-CBC‖HMAC32` encrypt-then-MAC, constant-time verify BEFORE decrypt; rebind
  tokens travel in `provisioningCompleted` on the opener socket; the stage is in-memory and
  socket-bound (restart = TTL-equivalent abort; NO table, NO migration in T3).
- **T3 writer executed with TWO rate-limit recoveries** (T2 precedent, now twice-proven):
  the writer 429-died before any code → revived with a sequential-stage plan (commit after
  each green stage) → delivered Stage 1 (backend, `f56347b`) and Stage 2 (client crypto + DAK
  store, `2ccc76e`) → stalled ~3 h mid-Stage-3 → orchestrator stood it down, recovered the
  uncommitted Stage 3 from the worktree (analyze clean, suites green), and built Stage 4 (the
  wire tests) itself → `8dc9d20`.
- **Landed:** `ProvisioningStagesService` (allocator memoized at open — FIRST
  `allocateDeviceId` caller; synchronous CAS consume/restore/retire-drops-blob, 10-min TTL,
  multiple stages per account BY DESIGN for falsification 20); `ChatProvisioningService`
  (6 events, T2 refusal conventions, `ephPubN` in no payload/field/log; ONE commit transaction:
  devices row + `applySignedListUpdate(manager)` + `createToken(userId, deviceId)` +
  login-shape JWT); never-activated-upload rejection in BOTH key-exchange handlers
  (`device_not_active`) + `DevicesService.touch` hardened (inserts only device 1; rows ≥ 2 are
  minted solely by the provisioning commit); client `link_crypto.dart` (spec-exact; stock
  ProvisioningCipher unused; buffer-copy discipline), `dak_store.dart` (armed
  write-then-read-back BEFORE the enroll emit), `LinkCeremonyController` (screen-scoped sink
  behind ConnectionProvider's single event-routing seam — NOT an 8th provider),
  `EncryptionService.adoptProvisionedIdentity`/`discardProvisionedIdentity` (atomic identity
  record, parse-everything-first, enumerated abort discard), DevicesScreen +
  LinkDeviceScreen + LinkThisDeviceScreen (RpgTheme tokens, l10n en+pl, Semantics keys;
  `qr_flutter` resolved cleanly so the QR ships beside the required copyable code).
- **Wire tests (in `full_stack_e2e_test.dart`, ZERO new registrations — throttle budget):**
  full ceremony with rebind + device-1-untouched proof; falsification 18 (two-phase kill:
  nothing committed, opener-only blob refetch, cancel → opener notice → stage gone);
  falsification 20 (two stages race one version slot, loser `stale_version`, SAME stage
  re-signed v+2 lands, exactly one device per ceremony); falsification 8 (foreign-session
  complete `not_opener`, duplicate `already_completed`, post-commit refetch `no_blob`,
  cross-account probe indistinguishable `unknown_stage`); amendment (a) idempotency
  (identical hello re-acks with the memoized id, different one
  `ephemeral_already_pinned`, retried provisionDevice overwrites the stage). Harness gained
  6 provisioning helpers + 7 tracked events; the T2 `engine` was hoisted to main() scope
  (the DAK private key exists nowhere else).
- **Per-ticket review: GATE PASS, zero BLOCKER/FIX, one P3 NOTE** — service-level invariant
  locks on adopt/discard (the highest-risk surface; an errant discard destroys a real
  account's keys). FOLDED (`ca9c6ff`) instead of ridden: T4–T8 add callers near that code.
- **App-proven across THREE web origins** (owner granted blanket tool access this session),
  account 193, backend logs + DB as ground truth — the full done-gate:
  primary :8091 (held the account identity) → Enable linking → `[device-list] enrolled
  userId=193 version=1`; keyless N :8093 → Link this device → QR + code → manual entry on the
  primary → **both screens showed SAS `041 588`** → Approve → `[provisioning] committed
  userId=193 deviceId=2 version=2` → N rebound and its SESSION-BOUND upload landed bundle +
  20 OTPs at `(193, 2)` under shared identity `BVVFJ/DuqMwR`; device 1's bundle
  byte-untouched (regId 10558, 100 OTPs); `nextDeviceId` 2→3. **Refusal path** on keyless
  :8094: ceremony to SAS `865 298` → primary CANCEL → opener showed "Łączenie anulowano na
  drugim urządzeniu", list stayed v2, NO device-3 row, `nextDeviceId`=4 (gap only), N2's
  storage held zero identity/DAK/prekey material (abort discard live). Bonus: a mangled code
  hit the strict parser's `invalid_code` failure state.

## Key files

- `docs/design/multi-device.md` §12 2026-08-20 block (i)–(iv) — NORMATIVE T3 settlement.
- `docs/plans/2026-08-19-phase2-stage0-decision-record.md` §8 — T3 closure + deviations.
- Backend: `key-bundles/provisioning-stages.service.ts`, `chat/services/chat-provisioning.service.ts`,
  `chat/dto/provisioning.dto.ts`, `chat/services/chat-key-exchange.service.ts` (gate),
  `key-bundles/devices.service.ts` (touch hardening + isActive), `key-bundles/device-list.service.ts`
  (EntityManager param), `chat/chat.gateway.ts` (wiring + throttles).
- Frontend: `services/device_link/{link_crypto,dak_store,link_ceremony_controller}.dart`,
  `screens/{devices_screen,link_device_screen,link_this_device_screen}.dart`,
  `services/encryption_service.dart` (adopt/discard + invariant locks),
  `providers/{connection_provider,auth_provider,encryption_provider}.dart`,
  `services/socket_service.dart`, l10n en+pl, `test_e2e/full_stack_e2e_test.dart` +
  `test_e2e/support/e2e_test_client.dart`.

## Verification

Backend **885/57** · ratchet **PASS 906** · analyze **clean** · flutter **1424/10sk** ·
wire **35/2sk** (restart + settle + alone) · both count verifiers OK · root `CLAUDE.md` §3
counts updated + §7 provisioning contract bullet added. Reviewer: GATE PASS. App-proof as
above (screenshots taken live; backend log lines and psql row dumps quoted in the decision
record §8).

## Notes for next session

- **Next ticket: T4** (envelopes + `device:<uid>:<did>` rooms + per-device history reads)
  under its decision-record §4 riders; falsifications 16/22 land with T4/T5.
- **Account 193 now has TWO live devices** (1 primary + 2 web-linked at list v2,
  `nextDeviceId`=4). Origins: :8091 primary, :8093 linked device 2, :8094 keyless (aborted).
  Local daemons `t3web8091`/`web8093`/`t3web8094` serve `frontend/build/web`.
- **Never `hub restart` a stale-named static server** — it reuses the RETAINED launch spec
  (an old cwd served a stale bundle for half an hour). Start under a fresh name with an
  explicit cwd. Also: python http.server sends no Cache-Control — force a CDP
  `Network.setCacheDisabled` reload or the browser serves week-old JS with 0 SW registrations.
- **Flutter web release a11y tree LAGS navigation** — ariaSnapshot can show the previous
  screen for minutes; screenshots are ground truth; snapshot-then-click-in-one-cell is the
  only reliable ref pattern; text fields focus reliably only via a fresh textbox ref click,
  then CDP `Input.insertText`.
- The wire-unreachable half of never-activated rejection (live session bound to a revoked id)
  becomes wire-reachable when T6 lands revocation — extend the suite then.
- Cancel is accepted from ANY authenticated session of the account (documented reading of
  "cancel is primary-only" — server cannot identify the primary cryptographically).
