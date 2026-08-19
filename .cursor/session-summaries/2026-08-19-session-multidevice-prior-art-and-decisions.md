# 2026-08-19 — Multi-device prior-art research; both Phase-2-blocking decisions locked

**Branch:** `feat/takeover-alarm-0a` (worktree `fireplace-0a`). Research pushed at `250c619`; the
cooldown carve-out LANDED at `94d030d`, wire-proven. NOT merged, NOT deployed. This session
follows `2026-08-19-session-otp-identity-gate.md`.

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

## 6. The cooldown carve-out, landed (`94d030d`)

- **Server** (`identity-reset.service.ts:143-155`): the cooldown query now inner-joins `users` and
  adds `(u."passwordChangedAt" IS NULL OR r."cancelledAt" > u."passwordChangedAt")` — a cooldown
  armed BEFORE the last password change no longer binds; one armed AFTER still does. The refusal
  branch logs `warn [identity-reset] request refused by post-cancel cooldown userId=…` (it used to
  log nothing; the wire run showed it firing 4×, once per refusal the tests provoke).
- **Unit spec** (+2; mocks prove predicate presence only): the join + both SQL halves asserted,
  and the warn asserted on refusal. 31/31 in the file.
- **Wire test** (`registration_lock_test.dart`, +1, runs LAST in the file because it retires the
  harness account's original password): cooldown binds → `POST /users/reset-password` (production
  route: revokes every refresh token, stamps `passwordChangedAt`) → 1.5 s guard for the JWT
  one-second `iat` granularity → re-login → new session's request = `pending` → cancel → a FRESH
  cooldown binds again, proving the carve-out is not "password change disables cooldowns forever".
  The re-login session reuses the account (`adoptAccountFrom`) — zero register-throttle spend.
- **Suites on `94d030d`:** backend **776/52** (774+2), ratchet **PASS 906**, analyze clean,
  flutter **1375/10sk** (one run tripped the KNOWN `chat_input_bar_attachment_test` flake; clean on
  re-run), wire **26/2sk** (25+1), both count verifiers OK, root `CLAUDE.md` §3 bumped (776 / 26).
- **Spec:** two dated §12 amendments (deviceId-allocator decision record; cooldown carve-out).
  The doc remains frozen — amendments add mechanism/rationale, change no protocol.

## 7. Environment notes

- Master moved to `cc8442b` — 0.1.17 shipped (PR #148 reverts the #145 popover anchor).
- A `fireplace-emu` stack (`C:\tmp\fp-emu`, detached HEAD at cc8442b) held ports 3000/5433
  mid-session; owner approved stop-and-restore, but it was downed externally before I acted, and a
  `fireplace-repro` stack also came and went. Check `docker ps` for squatters before assuming
  `fireplace-0a-*` owns :3000. Backend took 210 s to reach healthy after `docker compose up -d`.
- Phase 2 Stage 0 review dispatched at session end: three independent reviewers (coherence + §7
  re-ratification / protection incl. the 5 research items / durability incl. migration 0016 shape).
