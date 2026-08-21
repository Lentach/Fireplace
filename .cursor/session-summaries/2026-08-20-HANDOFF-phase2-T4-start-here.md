> ## ⛔ SUPERSEDED — T4 IS DONE (2026-08-21)
>
> **Read `2026-08-21-HANDOFF-phase2-T5-start-here.md` instead.** T4 (envelopes, device rooms,
> per-device history reads) was built, gate-reviewed (GATE FAIL → folded) and app-proven on
> 2026-08-21; closure is decision record §9 and the settlement is spec §12 items (v)–(x),
> including **amendment (x)**, which changed the send path after this file was written.
>
> This file is kept for its account of T1–T3 and its trap list. Its §4 numbers
> (885/57 · 1424/10sk · 35/2sk) and its §7 T4 brief are STALE.

# HANDOFF 2026-08-20 (evening) — Multi-device program: T1+T2+T3 done, T4 (envelopes + device rooms + history reads) is your job

**You are a fresh agent picking up a multi-session program mid-flight. This file is the
authoritative, self-contained entry point.** It SUPERSEDES
`2026-08-20-HANDOFF-phase2-T3-start-here.md` (T3 is DONE; that file's owner rules and traps
remain true and are restated here, plus everything T3's execution paid for).

---

## 0. Read order (do this before anything else)

1. This file, fully.
2. Root `CLAUDE.md` (workflow, §3 verification counts, §6 migrations, §7 wire contracts —
   NOTE §7 now has a full provisioning-ceremony bullet) and `backend/CLAUDE.md` +
   `frontend/CLAUDE.md` before first change in a tier.
3. The FROZEN spec `docs/design/multi-device.md` — §5.2/§5.3 (YOUR ticket), §4, §5.6, §7,
   §10, and **§12's dated amendment blocks at the end**: three of 2026-08-19 (allocator,
   cooldown carve-out, Stage-0 (a)–(h)) + ONE of 2026-08-20 (T3 settlement, items (i)–(iv)).
   All amendments are NORMATIVE.
4. `docs/plans/2026-08-19-phase2-stage0-decision-record.md` — finding-to-ticket map; §4
   riders (T4's riders are your requirements); §6/§7/§8 are the T1/T2/T3 closures.
5. `docs/plans/2026-08-19-multi-device-prior-art-research.md` — synthesis (~250 lines);
   appendices only when you need a primary-source claim.
6. Planning files: `C:/Users/Lentach/Desktop/Fireplace/.planning/multi-device/`
   (`task_plan.md`, `findings.md`, `progress.md`) — MAIN checkout, gitignored, the
   cross-session memory. MAINTAIN THEM as you work. Do NOT mint planning files at the
   worktree root.
7. Subagents inherit NOTHING. Every task brief you write must name these files explicitly.

## 1. Owner rules (binding; each was earned by an incident)

1. **Investigate and PROVE, then ASK before writing code** — diagnostics count as code
   (`4beb1bd` landed on a symptom, reverted). Ticket work inside the approved T1–T8 DAG is
   pre-authorized; anything OUTSIDE a ticket needs an ask.
2. **Ask before opening the browser tool — every time.** Authorization is per-session and
   EXPIRES: the T3 session received a blanket "full access, don't ask" grant mid-session —
   that grant died with that session. You start under the standing ask-first rule.
3. **Never merge, never deploy.** One branch, one merge at program end. PR #144 = review
   surface only. `gh run list` after pushing; never merge on red (CI is detection, no gate).
4. **Never self-review.** Fresh `reviewer` subagent per ticket close; THREE independent
   reviewers at phase gates. Defensive framing ("verify our protections hold") —
   adversarial wording gets content-filtered.
5. Writer subagents ≤2 concurrent; read-only reviewers ×3 fine; Anthropic-only.
6. Never `dart format lib/` or prettier globs — format ONLY the exact files touched.
7. **Never give `flutter test` a file list** (45 files once timed out past 11 min; full
   suite is 170–310 s). Includes `test_e2e` — full suite only.
8. Owner is non-native English; explain mechanics plainly; delays are testable in seconds
   via SQL timestamp updates (never wait out a 24 h/72 h window).
9. Session end: dated `.cursor/session-summaries/YYYY-MM-DD-session-*.md` + `LATEST.md`
   update (**caps at 5 dated entries** — a pre-commit hook rejects a 6th; roll the oldest
   into a "Still binding, from the rolled-off …" line).

## 2. Repo state

- Worktree `C:/Users/Lentach/Desktop/fireplace-0a`, branch `feat/takeover-alarm-0a` ==
  origin, clean, HEAD `82cb06e`. Main checkout `C:/Users/Lentach/Desktop/Fireplace` on
  `master` (`cc8442b`, 0.1.17 — shipped externally, PR #148 reverted #145's popover anchor).
- `origin/wip/otp-identity-gate` (`8d61bde`) is SUPERSEDED — never merge it.
- Nothing merged, nothing deployed. Commit spine (new → old):

```
82cb06e docs: T3 closed (decision record §8 + books)
ca9c6ff fix: T3 review fold — invariant locks on adopt/discardProvisionedIdentity
8dc9d20 feat: T3 controller + link UI + wire tests                ← T3 (3/3)
2ccc76e feat: T3 link crypto + DAK Keystore persistence           ← T3 (2/3)
f56347b feat: T3 backend wire surface + stage machine             ← T3 (1/3)
69200b2 docs: T3 settlement amendment (spec §12 items (i)-(iv))
260ddb6 docs: 08-20 T3 handoff (superseded by THIS file)
7c28e40 docs: T2 closed · 6101774 T2 · 518a742 T1 closed · 584f2d3 T1
bddc1b7 live-fire docs · 1d2065d Stage 0 · 9c70d5b docs · 94d030d carve-out
e697f43 decisions · 250c619 research · 0e8d005… (older spine: see the 08-19 handoff)
```

## 3. What is BUILT (all app- or wire-proven)

- **Phase 0a** takeover alarm; **0b** registration lock §6.1 + 72 h reset ceremony §6.2 +
  recovery key §6.2.1 (Argon2id, single-use, 1 h shortened); **Phase 1** per-device schema
  (migration 0015: `devices`, per-device `key_bundles`/OTPs, `refresh_tokens.device_id`,
  push `deviceId`, `messages.originDeviceId`/`sendToken` + partial unique).
- **OTP identity gate, option A** (`573458b`): client stashes OTPs, publishes the bundle,
  releases keys only on `keyBundleUploaded success:true`; refusal DROPS them;
  `identityChanged:true` mints a fresh pool. Do NOT restore back-to-back emits.
- **Cooldown carve-out** (`94d030d`): a password change voids a 24 h post-cancel cooldown
  armed BEFORE it. Wire- and app-proven.
- **T1** (`584f2d3`): `users.nextDeviceId` (default 2) + `DevicesService.allocateDeviceId`
  (atomic `UPDATE … RETURNING "nextDeviceId"-1`, PRE-increment, never decremented);
  `account_authorizations` (userId PK, first-write-wins, `enrollmentCreatedAt`);
  `message_envelopes` (UNIQUE (messageId,recipientUserId,recipientDeviceId); `messageId` FK
  **ON DELETE CASCADE** = the SOLE §5.6 destruction mechanism; NO FK on the recipient pair;
  still EMPTY — **T4 writes the first rows**).
- **T2** (`6101774`): server enrollment (sig_IK `"fp-enroll-v1\0"…` vs PUBLISHED identity,
  23505 → `already_enrolled`), byte-exact `listCanonical` (parse→re-encode→byte-compare),
  sig_DAK `"fp-list-v1\0"` list + atomic-CAS version law (`stale_version`), wire
  `enrollDeviceAuthority`/`updateDeviceList`/`getDeviceList` + `deviceListChanged`;
  client I7 chain verifier + `DeviceAuthorityEngine`; falsification 25 pinned BOTH
  directions with real-Dart vectors (`frontend/tool/device_list_vector_generator.dart`).
- **T3** (`f56347b`+`2ccc76e`+`8dc9d20`+`ca9c6ff`) — the §5.1 provisioning ceremony,
  END-TO-END and app-proven:
  - Backend: `ProvisioningStagesService` (in-memory, socket-bound, 10-min TTL; deviceId
    allocated ONCE at open and memoized; synchronous CAS `consume`, `restore` after a failed
    commit, `retire` drops the blob after success; MULTIPLE stages per account by design).
    `ChatProvisioningService`: `openProvisioning` (enrolled accounts only) →
    `provisioningOpened {provisioningId, expiresAt}` (NO deviceId in the answer);
    `provisioningHello {provisioningId, ephPubP}` (any session of the account; FIRST ephPubP
    pinned, identical retry idempotent, different → `ephemeral_already_pinned`) →
    `provisioningHelloAck {deviceId}` to caller + relay to the OPENER socket;
    `provisionDevice {blob, listCanonical, listSignature}` (verifies sig/version/diff-adds-
    exactly-the-memoized-id BEFORE staging; retry overwrites) → ack + `provisioningBlob`
    push to opener; `fetchProvisioningBlob` opener-only until TTL/commit;
    `provisioningComplete` (opener socket ONLY, one-shot CAS) → ONE transaction (devices row
    + `applySignedListUpdate(manager)` + `createToken(userId, deviceId)`) →
    `provisioningCompleted {deviceId, access_token, refresh_token}` (login-shape JWT) +
    `deviceListChanged` broadcast; `cancelProvisioning` from ANY session of the account
    (server can't identify "the primary" — documented reading). `ephPubN` appears in NO
    payload, field, or log line.
  - Upload gates (amendment (b)): `uploadKeyBundle`/`uploadOneTimePreKeys` for deviceId ≥ 2
    without a live devices row → `device_not_active` (bundle answer / raw error event
    respectively); `DevicesService.touch` inserts ONLY device 1 — rows ≥ 2 are minted solely
    by the provisioning commit. `DevicesService.isActive(userId, deviceId)` exists.
  - Client: `frontend/lib/services/device_link/link_crypto.dart` (spec §12 item (ii)
    byte-exact: **local RFC-5869 HKDF-SHA256, salt = 32 zero bytes** — libsignal 0.8.2 does
    NOT export HKDFv3 from its barrel and src/ imports are forbidden; SAS = first 4 bytes BE
    uint32 mod 10^6 as `XXX XXX`; blob `0x01‖IV16‖AES-256-CBC‖HMAC32` encrypt-then-MAC,
    constant-time verify BEFORE decrypt; `LinkOobCode`
    `fp-link.v1.<uuid>.<b64url ephPubN>.<platform>` strict parser); `dak_store.dart`
    (ONE atomic JSON record via the signal DualStorage seam, armed write-then-read-back
    GATES the enroll emit); `link_ceremony_controller.dart` (screen-scoped ChangeNotifier,
    registered as ConnectionProvider's single provisioning sink — NOT an 8th provider);
    `EncryptionService.adoptProvisionedIdentity` / `discardProvisionedIdentity` (atomic
    identity record, parse-everything-first, enumerated abort discard, SERVICE-LEVEL
    invariant locks: adopt throws if ANY identity exists; discard throws unless a
    provisional adopt is pending — `ca9c6ff`); `identityKeyPairForLinking()` read-only
    export for the blob; `AuthProvider.adoptProvisionedSession`;
    `EncryptionProvider.encryptionService` getter. UI: `devices_screen.dart` (list via
    verified chain; Enable linking / Link a device / Link this device),
    `link_device_screen.dart` (primary: paste code → SAS → Approve/Cancel),
    `link_this_device_screen.dart` (N: QR via `qr_flutter` + REQUIRED copyable code → SAS →
    auto-complete → rebind → existing OTP-gate upload path). l10n en+pl. Settings "Devices"
    row navigates.
  - **App-proven (3 origins, account 193):** enroll v1 → both screens SAS `041 588` →
    `[provisioning] committed userId=193 deviceId=2 version=2` → rebind → session-bound
    upload landed bundle + 20 OTPs at (193,2), device-1 bundle byte-untouched; refusal path:
    cancel at SAS `865 298` → opener notified, list stayed v2, no row, `nextDeviceId`=4 gap
    only, N2 storage empty. Full account in decision record §8 + the dated session file.

**Silent-break invariants (each has bitten):** every index mirrored on its entity
(`synchronize` drops undeclared ones); every entity in module `forFeature` AND
`app.module.ts`; `repo.query()` returns `[rows, rowCount]`; column casing per table
(refresh_tokens snake_case, messages mixed, new tables camelCase-quoted); migrations
0015/0016 not code-reversible; **Dart `Curve.calculateSignature` AND `curve25519-js.verify`
MUTATE their buffers — always pass copies**; wire = request-event → response-event, NO
socket.io acks; `listCanonical` is opaque base64, byte-exact, never re-serialized before
verification; uploads are SESSION-bound (payload deviceId ignored — pinned by wire tests).

## 4. Verification numbers (root CLAUDE.md §3 — reproduce, don't trust)

```bash
cd backend && npm test                                      # 885 tests / 57 suites
cd backend && node ../scripts/lint-ratchet.mjs              # PASS at 906
cd frontend && cmd /c flutter analyze --no-fatal-infos      # clean
cd frontend && cmd /c flutter test                          # 1424 / 10 skipped
cd frontend && E2E_BASE_URL=http://127.0.0.1:3000 cmd /c flutter test test_e2e   # 35 / 2 skipped
cd backend && node ../scripts/verify-claude-backend-test-counts.mjs
cd frontend && node ../scripts/verify-claude-frontend-test-counts.mjs --log test-output.txt
#   --log PARSES an existing file; run it bare to have it run the suite itself.
#   DELETE test-output.txt before committing.
```

**Flake ledger (pre-existing, NOT ours — re-run the FULL suite once, do not chase):**
1. `test/widgets/input/chat_input_bar_attachment_test.dart` "video-then-caption" — ~2/3.
2. `test/services/unread_badge_sync_test.dart` "falls back to the window Badging API" —
   seen once under back-to-back load.

## 5. Environment traps (all paid for — trust this list)

- Docker stack `fireplace-0a-*` (worktree compose). DB **`chatdb`** on :5433
  (`docker compose exec -T db psql -U postgres -d chatdb -c "…"`). **Check `docker ps` for
  squatter stacks first** (`fireplace-emu`/`fireplace-repro` have grabbed 3000/5433 before;
  ASK before stopping a foreign stack).
- **Always `127.0.0.1:3000`** — `localhost` is broken on this PC (stale wslrelay on `[::1]`).
- `docker compose restart backend` → poll `/health` PATIENTLY: cold boot 3.5–7 min. `nest
  --watch` recompiles WITHOUT relaunching — restart is the only trustworthy relaunch.
- **Wire suite discipline:** restart backend first (register throttle 10/hr/IP in-memory;
  the suite spends ~10 — NEVER add registrations; reuse accounts via
  `E2eClient.adoptAccountFrom`), wait ≥20 s after `/health` flips, run ALONE, full suite
  only. New ceremony-style tests go INSIDE `full_stack_e2e_test.dart` (throttle budget);
  the shared `engine` (T2 DAK) lives at main() scope — the DAK private key exists only there.
- Windows: `cmd /c flutter …` (bare = os error 193). Web release:
  `cmd /c flutter build web --release --dart-define=BASE_URL=http://127.0.0.1:3000`, serve
  `frontend/build/web` with `python3 -m http.server <port>` — each port = separate origin =
  separate storage; REBUILD after any lib/ change.
- **Static-server traps (new, T3-paid):** never `hub restart` a stale-named daemon — it
  reuses the RETAINED launch spec (an old cwd served a stale bundle for 30 min); start
  fresh names with explicit cwd. python http.server sends NO Cache-Control — Chrome's
  heuristic cache serves week-old JS with zero SW registrations; evict with a CDP
  `Network.setCacheDisabled` reload (unregistering SWs is not enough).
- **Browser recipes (ASK FIRST — the T3 blanket grant expired with its session):** CanvasKit
  semantics empty until you click/dispatch on `flt-semantics-placeholder` after EVERY
  reload; **the release a11y tree LAGS navigation by minutes — screenshots are ground
  truth**; take a FRESH ariaSnapshot and click its ref in the SAME cell (stale refs time
  out); text fields focus reliably only via a textbox-ref click, then type ONLY via CDP
  `Input.insertText`; snackbars live ~0.6–2.5 s — backend logs are ground truth for
  refusals; clipboard needs `browserContext().overridePermissions(origin, ['clipboard-read',…])`.
- Delay testing in seconds (never wait):
  `update identity_reset_requests set "deadlineAt"=now()-interval '1 minute' where "userId"=<id> and status='pending';`
  (cron @EVERY_MINUTE); `set "cancelledAt"=now()-interval '25 hours'` ages the cooldown.
  Clocks mixed: cancelledAt/completedAt = DB now(); deadlineAt = Node.
- Logs: `docker compose logs backend --since 5m | grep -iE "provision|device-list|identity-"`.
- **Test accounts (local chatdb):** **193 = `pg5802614#6248` / `Fireplace!2620`** — NOW A
  TWO-DEVICE ACCOUNT: device 1 primary (identity `BVVFJ/DuqMwR`, regId 10558, 100 OTPs,
  lives in origin http://127.0.0.1:8091), device 2 web-linked (regId 13585, 20 OTPs, lives
  in origin http://127.0.0.1:8093), list v2, enrolled,
  `nextDeviceId`=4. Origin :8094 = keyless (aborted ceremony fixture). Daemons
  `t3web8091`/`web8093` may still serve `frontend/build/web`; restart under FRESH names if
  dead. 205 = `pr8963550rc489731` / `FireplaceFixed!7`. Login DTO field is `identifier`.

## 6. Governance (NORMATIVE for your ticket)

- Stage-0 amendments (a)–(h) (spec §12, 2026-08-19) + T3 settlement (i)–(iv) (2026-08-20)
  bind Phase 2. The ones shaping T4:
  - **(g)**: `message_envelopes` starts EMPTY, no backfills; `messageId` FK ON DELETE
    CASCADE is the SOLE §5.6 destruction mechanism; recipient pair carries NO FK.
  - **§4**: `deliveryStatus` is a projection over RECIPIENT envelopes ONLY
    (`recipientUserId != senderId` — self-sync envelopes NEVER count); written ONLY as a
    column-scoped UPDATE; `MessagesService.updateDeliveryStatus` full-entity `save()`
    (`messages.service.ts:319-320`) is a NAMED conversion target. Legacy `encryptedContent`
    is retained for pre-migration rows; legacy-client sends are converted to a device-1
    envelope AT INGEST (§8) so new-model rows have one storage shape.
  - **§5.3**: socket joins `user:<uid>` AND `device:<uid>:<did>`; ciphertext events
    (`newMessage`, `messageEdited`) go to the device room; history reads serve the
    requesting device's envelope → legacy fallback GATED to the session-owner device →
    `envelopeStatus: "none_for_device"` marker; `originDeviceId IS NULL` = device 1.
  - **⛔ Do NOT room-address `newMessage`/`messageEdited` beyond the design**: Signal decrypt
    is not idempotent; today both use `emitToNewestTab` and push suppression reads that same
    socket — the §5.3 device-room design REPLACES that carefully (newest socket WITHIN the
    device), it does not blanket-broadcast.
- **T4 riders (decision record §4):** `preKeysLow` is counted per-device but ROUTED
  per-user — route to `device:<uid>:<did>` (coherence F5); legacy fallback treats
  `originDeviceId IS NULL` as device 1 (durability F5a); RED TEST that a device-2 bundle
  upload under the shared IK does not trip `[identity-churn]` (landmine 2, coherence F7 —
  NOTE: T3's app-proof uploaded a device-2 bundle live and no churn fired, but the red test
  is still owed); envelope stamps never enter expiry/read-TTL (durability F9);
  `updateDeliveryStatus` → column-scoped UPDATE (coherence F6, falsification 19);
  `message_envelopes.recipientUserId` has NO FK to `users` — when the T4 write path lands,
  confirm recipient-user deletion cannot orphan envelopes (their messages must cascade via
  the messageId FK) or add the FK then (T1-review rider).

## 7. YOUR JOB: T4 — send fan-out, envelopes, device rooms, per-device history (spec §5.2 + §5.3)

Read §5.2 (lines ~220-252) and §5.3 (~253-280) completely. The mechanism: `sendMessage` grows
`envelopes: [{userId, deviceId, ciphertext}]` (one per (recipient user, device) AND per own
OTHER device — but self-sync CONSUMPTION is T5; T4 lands storage/routing) + `senderListVersion`
/ `recipientListVersion` stamps + `sendToken`; server cross-checks both list versions against
`account_authorizations` and rejects a stale send ATOMICALLY (`deviceListStale` carrying
`listCanonical` as base64 — falsification 5: zero envelopes written); accepted sends write
`message_envelopes` rows in the SAME transaction as the message row; realtime delivery emits
to `device:<uid>:<did>` rooms (newest socket within the device); history reads serve the
requesting device's envelope ciphertext, the device-gated legacy fallback, or the
`none_for_device` marker; delivery projection per §4. Legacy compat per §8: single-ciphertext
sends from old clients become a device-1 envelope at ingest; new clients against this server
send envelopes.

What exists for you: `message_envelopes` table EMPTY with the exact unique/FK shape (T1);
the signed-list machinery + `getAuthorization` (T2); JWT/socket `deviceId` +
`client.data.user` + `userRoom` (Phase 1/T3); `sendToken` server-side idempotency (Phase 1);
two REAL linked devices on account 193 for app-proof (§5 above). Client: `SocketService` /
ConnectionProvider seams; `senderListInfo` E2E-envelope field is SPEC'd in §7 but lands with
the client fan-out here / T5 (falsifications 16/22 need it).

Relevant falsifications (§10): 4 (invalid chain in `deviceListStale` answer → client refuses
and fails the send), 5 (stale send rejected atomically), 9 (fail-closed inheritance:
list-fetch timeout on send → send FAILS), 13's positive-serve/marker cases at the history
read path, 16 (split-view via senderListInfo — may partially defer to T5), 19 (projection
safety incl. converted updateDeliveryStatus; self-sync envelopes never flip the projection;
read-TTL never starts from envelope stamps), 22 (false-alarm discipline). Plus rider red
test landmine-2.

**T4 is NOT done at green suites**: app-prove with account 193's two live devices (ASK
before browser) — send from a peer (e.g. 205 or a suite-adopted account) to 193 and observe
BOTH devices receive/decrypt their own envelopes; history read on the linked device serves
its envelope (and `none_for_device` for pre-link rows per §5.3's gate — device 2 has no
pre-link sessions, exactly the marker case); delivery projection flips on the recipient's
read, never on self-sync. Wire/DB/logs are ground truth.

## 8. After T4: the remaining DAG

T5 self-sync + lost-ack + client `sendToken` (THE declared bug epicenter;
`frontend/CLAUDE.md` §5 lost-ack insurance is REQUIRED reading; riders: `tempId != null`
survives the `history.dart:529` guard flip; re-ack-never-re-fan) → T6 revocation + stale
bounce + reset-roster teardown (amendment (e) receive-time origin check; `purgeSupersededDevices`
widening; I6 SILENCE in `handleGetServedMessageIds` — `chat.gateway.ts:223`; the
wire-unreachable half of never-activated rejection becomes reachable here — extend the
suite) → T7 edit re-fan (UPSERT content-only, stamps survive) → T8 harness sweep (falsify
at RECEIVE time; falsifications not landed in their tickets). Phase gate after T8: THREE
independent reviewers, then the owner decides the merge.

## 9. Research: what exists, how to do more

- `docs/plans/2026-08-19-multi-device-prior-art-research.md`: synthesis keyed to T1–T8 +
  four cited appendices (Signal @2f482f68, Matrix m.sas.v1 + Synapse #17375, WhatsApp
  whitepaper v9 prefixes + iMessage CKV + RFC 9420 + attack papers, our spec map).
- Need more? `research` skill: `librarian` subagents against PRIMARY sources, one topic
  each, `local://` outputs, compile a dated `docs/plans/YYYY-MM-DD-<topic>-research.md`.
  Batch independent researchers in ONE task call. `scout` for read-only codebase mapping.

## 10. Working rhythm (proven over T1→T3; follow it)

1. One ticket at a time. Settle any spec ambiguity BEFORE code via a dated §12 amendment
   (T3 precedent: the settlement block was committed as docs before the writer started).
2. Dispatch ONE fresh writer with a SELF-CONTAINED brief (name every file/rule/trap — it
   inherits nothing). Writers ≤2. **Instruct SEQUENTIAL stages with a commit after each
   green stage** — T3's writer died twice (429 pre-code, then a 3 h silent stall mid-UI)
   and per-stage commits made both recoveries cheap.
3. **Rate-limit/stall recovery (twice-proven):** a dead writer's work is in the worktree —
   check the transcript's file mtime vs now (a "Re-analyzing" status can be a corpse),
   stand it down explicitly, `git status`, verify what's real with full suites, finish the
   remainder yourself.
4. You (orchestrator) verify EVERY claim: full suites, counts, verifiers. `completed` ≠
   accepted.
5. Fresh `reviewer` per ticket close (defensive framing; hand it the delta commit ids +
   ground-truth docs + review axes). BLOCKER/FIX → fold before push; a P3 NOTE may be
   FOLDED instead of ridden when later tickets add callers near the surface (T3 precedent).
6. App-prove user-visible changes (ASK before browser). Wire/DB/logs are ground truth;
   screenshots beat the lagging a11y tree.
7. Push code + closure docs together; update the decision record (closure §), LATEST.md
   (5-entry cap), the dated session summary, and the planning files.

## 11. Standing blockers (owner-side, do not chase)

`FIREBASE_SERVICE_ACCOUNT` absent on the VM (FCM dead in prod); `.jks` off-PC backup owed;
owner-iPhone confirmation for 0.1.16/0.1.17 attachment popover. Accepted-not-fixed P3s:
reset banner lacks `Semantics(liveRegion:true)`; offline recovery-key save shows a generic
failure toast after ~6 s; I2 UI gating (web must not become primary in prod) is Phase 3.

## First five actions

1. Read order §0 (this file → CLAUDE.mds → spec §5.2/§5.3 + §12 amendments → decision
   record §4 T4 riders + §8 T3 closure).
2. `docker ps` (squatters?) → stack up → poll `/health` patiently → reproduce
   885/57 · 906 · clean · 1424/10sk · 35/2sk (restart backend before the wire run; ≥20 s
   settle; alone).
3. Confirm branch == origin at `82cb06e`, worktree clean.
4. Design T4 against §5.2/§5.3 + §4 + riders. Settle ambiguities BEFORE code (dated §12
   amendment). Known open design points to settle: exact `sendMessage` envelope DTO shape
   vs the legacy single-ciphertext path at ingest; `deviceListStale` reject payload;
   whether `senderListInfo` (client E2E field) lands here or T5; the history-read
   `envelopeStatus` wire shape.
5. Dispatch the T4 writer (sequential stages, commit-per-stage); verify; review; fold;
   app-prove on account 193's two live devices (ASK first); push; books
   (decision record §9 = T4 closure, LATEST 5-cap, dated summary, planning files).
