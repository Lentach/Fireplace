# 2026-08-19 — Multi-device prior-art research; both Phase-2-blocking decisions locked

**Branch:** `feat/takeover-alarm-0a` (worktree `fireplace-0a`). Research committed and pushed at
`250c619`. NOT merged, NOT deployed. This session follows `2026-08-19-session-otp-identity-gate.md`
and precedes the cooldown patch + Phase 2 Stage 0 (see §4).

## 1. What happened

Owner asked for deep research on multi-device/multi-session prior art before answering the two
open decisions from the Phase-2 handoff. Four parallel research agents ran against PRIMARY sources
only (Signal-Server @2f482f68 + libsignal v0.101.0 + Sesame spec; matrix-spec source + vodozemac +
the 2022 disclosures; WhatsApp whitepaper v9 (Feb 2026) + Apple Platform Security/CKV + RFC 9420 +
EuroS&P'18/S&P'23/EUROCRYPT'25 attack papers; plus a faithful map of our own frozen spec).
Compiled into **`docs/plans/2026-08-19-multi-device-prior-art-research.md`** — a synthesis keyed to
our tickets T1–T8 and the two decisions, with the four fully-cited reports as Appendices A–D.

## 2. Headline findings

- **Signal REUSES device ids** (`Account.getNextDeviceId()` returns the lowest unused id ≥2) — but
  reuse is survivable only because of machinery we don't have: per-device random `registrationId`
  (peers bounce 410-stale and re-run X3DH when an id changes hands), total per-id server-state purge
  on relink, and no deviceId-keyed history fallback. Our §5.3 legacy fallback serves ciphertext BY
  deviceId, so for us reuse is actively dangerous — the frozen invariant (L269-272) is confirmed.
- **Matrix documents the reuse disease directly** (Synapse #17375): signatures stored under
  `(user, device_id)` outlive the device and reattach to a reused id's new keys. Our DAK list
  mutations + `identity_change_audit` are the same class of persistent id-keyed artifacts.
- **WhatsApp is the model for T2**: primary-signed device list (`0x0602‖ListData`), bidirectional
  link signatures (`0x0600`/`0x0601`), verified at EVERY fan-out with abort-on-failure; per-type
  prefix bytes = the domain separation whose absence gave Matrix CVE-2022-39250.
- **Matrix `m.sas.v1` is the reference for T3** (commitment-then-keys, HKDF info binds both
  ephemerals + both ids + transaction id; version-tag every MAC/KDF — their `.v2` lesson).
- **No messenger has a reset cooldown at all** — the industry treats proof of account control as
  license to rebuild identity instantly (WhatsApp clients don't even warn by default, EUROCRYPT'25).
  Our 72 h + cancel + cooldown is the strict outlier.

## 3. Decisions locked (owner: "do your recommended", 2026-08-19)

1. **deviceId allocation (unblocks migration 0016 / T1):** ids are NEVER reused, per frozen §5.3.
   Allocator = **`users.nextDeviceId` counter column**, atomic `UPDATE … RETURNING`. Explicitly NOT
   `MAX(deviceId)+1` over `devices` — that turns row retention into a crypto invariant.
2. **Cooldown carve-out: YES, implemented before Phase 2** — a password change voids a 24 h
   post-cancel cooldown armed BEFORE the change (read-time predicate in
   `identity-reset.service.ts:134-142`; deliberately never cancels pending ceremonies). Plus a warn
   log on the cooldown branch, which today logs nothing.

## 4. Stage-0 agenda additions from the research (doc §5)

1. Domain-separation audit of every signature/KDF context in §3/§5 canonical bytes.
2. Peers must drop a revoked device's INBOUND session material (WhatsApp shipped that bug).
3. Consider WhatsApp-style list TTL / in-chat consistency freshness (note, not necessarily adopt).
4. Compare §5.1 SAS against the ZRTP commitment shape (candidate for the owner-flagged /prototype).
5. Provisioning/verification events must be idempotent under duplicate delivery.

## 5. Housekeeping

- Planning files live at **`.planning/multi-device/`** in the MAIN checkout
  (`C:/Users/Lentach/Desktop/Fireplace`, gitignored/local-only) — rediscovered this session and
  upgraded from design-doc scope to program scope (phases, decisions, errors, next steps).
- Next work in order: dated §12 spec amendments for both decisions → cooldown patch (unit + wire
  tests, §3 counts, full suites) → Phase 2 Stage 0 spec review with three independent reviewers.
