# 2026-08-30b — Bounded merge-gate review (Option A) ran; ONE blocking finding; fixed as (lxiv)

**Date:** 2026-08-30

## What was done

**The owner chose Option A** ("get it ready to merge and deploy"), so the recommended bounded review
ran: three fresh reviewers (2× `reviewer`, 1× `security-reviewer`), briefed on EXACTLY one question —
*can a normal user, with an honest server and functioning local storage, lose a message, lose access,
or get permanently stuck?* — with hostile-server material explicitly out of scope.

**Verdict: 2× MERGE-SAFE, 1× BLOCKING.** Message lifecycle: safe (the (lx) refusal+repair loop
converges). Stuck states: safe, and all seven (lxiii) residuals were re-judged non-blocking one by
one. Identity lifecycle: **one blocking finding, every hop then re-verified from source first-hand
before acceptance** (never inherit a reviewer claim):

**GATE2-REVOKED-DEVICE-RELOGIN-CLOBBER.** A revoked linked device that signs back in — which
`deviceRevokedNotice` explicitly invited — is resolved by `resolveLoginDeviceId`
(`devices.service.ts:145-152`) onto the LIVE PRIMARY's device id. It still holds the shared account
IK plus its OWN minted signedPreKey/registrationId/OTPs, its material survives logout by design, and
the client re-uploads on every connect. Same identity ⇒ `identityChanged=false` ⇒ no lock, no audit,
no alarm — the upsert silently clobbers the primary's bundle row while the served OTP pool stays the
primary's. A peer's X3DH then needs private halves held by TWO different installs ⇒ **every first
message built on the mixed bundle is permanently undecryptable by every device while the sender sees
"delivered"**. Normal taps, honest server. (xxii) built the door while fixing the post-reset login
lockout; no amendment or residual recorded the shape. Two open-ended review rounds missed it; the one
narrow question found it — evidence the bounded gate is the right instrument.

**Fixed under amendment (lxiv), ratified by the owner BEFORE code, both halves, both falsified:**

1. **Server:** a bundle row's `registrationId` MUST NOT change while its `identityPublicKey` is
   unchanged (minted together, once ⇒ that shape is always a foreign install).
   `DeviceMaterialConflictError` → `keyBundleUploaded { success:false, error:'device_material_conflict' }`,
   refused BEFORE any write. **The first draft's "bundle guard alone closes it" claim was WRONG**
   (caught in review of the amendment itself): the OTP replenishment path bypasses `upsertKeyBundle`,
   so `uploadOneTimePreKeys` now takes an OPTIONAL `registrationId` install proof — refused on
   mismatch, accepted when absent (pre-(lxiv) clients predate linking, so the foreign-install shape
   cannot exist for them). Falsified: each guard disarmed independently → exactly its refusal test
   RED (the bundle reversion resolves to `{identityChanged:false}` — the clobber landing), positive
   controls green, restored byte-exact.
2. **Client:** one durable stamp per account (`e2e_<uid>_material_device_v1`) with a single uniform
   rule — **every authorized re-homing (mint, §5.1 adopt, §6.2 rebind) clears it; the next
   server-confirmed own-device id TOFU-stamps it** — so a contradiction is only reachable by material
   that survived a session-identity change it was never re-homed for. On contradiction:
   `isE2EReady` stays false (which every send/decrypt path already consults), nothing publishes,
   `E2E_DEVICE_MISMATCH` recorded, and a `DeviceMismatchBanner` routes to re-linking. The §6.2
   rebind clears the stamp BEFORE its reconnect — without that, the RECOVERING device would trip its
   own gate (caught at design time, pinned by a positive-control test). Falsified three ways (init
   gate / reconnect verify / OTP proof), each reversion reddening exactly its test.
   **Honesty pass:** clause 2's draft overclaimed the `rebind_failed` shape; the built semantics
   leave that to the server clause, and the spec now says so.

Also: `deviceRevokedNotice` re-worded en+pl (the old text invited the bug), 3 new ARB keys,
`_reenrollAfterReset`'s missing in-flight latch RECORDED as residual 8 under (lxiv) (sixth instance
of the slot root cause — NOT fixed, needs the compare-and-promote primitive residual 1 calls for).

Session start state work: branch was 1 docs-only commit behind master → merged clean as `5efd223`,
pushed (a CONFLICTING PR gets zero CI scheduling — the 08-19 blindness lesson).

## Key files

- `docs/design/multi-device.md` — amendment (lxiv) D16 (two clauses + residual 8); index now (a)–(lxiv)
- `backend/src/key-bundles/key-bundles.service.ts` — `DeviceMaterialConflictError`, bundle guard, OTP guard
- `backend/src/chat/services/chat-key-exchange.service.ts` — WS mapping + registrationId pass-through
- `backend/src/chat/dto/upload-one-time-pre-keys.dto.ts` — optional `registrationId`
- `backend/src/key-bundles/key-bundles.service.spec.ts` (+6), `chat-key-exchange.service.spec.ts` (+1)
- `frontend/lib/services/encryption_service.dart` — stamp primitives + mint-path clears + `currentRegistrationId`
- `frontend/lib/providers/encryption_provider.dart` — init gate, `setOwnDeviceId` re-verify, publish refusals, OTP proofs
- `frontend/lib/providers/connection_provider.dart` — rebind clears the stamp before reconnect
- `frontend/lib/widgets/device_mismatch_banner.dart` (NEW) + `main_shell.dart` stack + ARB en/pl + gen-l10n
- `frontend/test/providers/device_material_mismatch_test.dart` (NEW, 5) + `test/widgets/device_mismatch_banner_test.dart` (NEW, 2)
- `CLAUDE.md` §3 counts + §7 device-material-guard contract

## Verification

- Backend: **1060/62** green (was 1053, +7 exactly the new tests); verifier OK.
- Frontend: analyze **No issues found**; full suite **1658 passed / 10 skipped** (was 1651, +7).
- lint-ratchet: **PASS 906 → 890** (was 889; +1 real error from the new backend code, floor untouched).
- Five falsifications total (2 backend, 3 client), each RED on exactly its target, each restored
  byte-exact (`git diff` clean of `.fbak`/FALSIFY markers).
- ARB integrity: +3 keys en and pl, no dupes; gen-l10n run.

## Notes for next session

- **The merge decision is again the only open item** (task_plan 14j). The bounded gate now answers:
  message lifecycle SAFE, stuck states SAFE, identity lifecycle SAFE **after (lxiv)**. If the owner
  wants the letter of Option A honored, one narrow re-check of (lxiv) itself by a fresh reviewer is
  the remaining formality; otherwise the gate question stands answered.
- Residual 8 (reenroll latch) joins the post-merge queue alongside residual 7 (mocked-query-builder
  tests) — fix 7 first, per the handoff.
- ⚠️ **CI falsified this file's own first draft:** it claimed the wire harness "covers the untouched
  flows" — the first push went 6/7 with `e2e-wire` RED, because
  `full_stack_e2e_test.dart` "an upload lands on the SESSION's device" pinned the PRE-(lxiv)
  contract (same-identity `registrationId+1` accepted). Rewritten (`fbb35e5`): claim-ignoring proven
  with the SAME registrationId, the foreign-registrationId upload asserted REFUSED
  (`device_material_conflict`, row untouched). Full wire run against a live backend: **44/6sk
  green** — the (lxiv) refusal is now OBSERVED on the wire, not only unit-proven. (Ops note: a bare
  `docker compose restart backend` wedged nest again, the 08-22b trap; `down && up` cured it.)
