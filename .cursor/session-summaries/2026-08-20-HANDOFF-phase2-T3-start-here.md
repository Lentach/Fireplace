> **⚠️ SUPERSEDED 2026-08-22 — DO NOT START HERE.** This handoff is spent: its ticket closed, and every
> line number and count in it has since moved. The current entry point is
> `2026-08-22-HANDOFF-T8-start-here.md`, and the permanent record is `LATEST.md` plus the dated summary it
> names. Kept only for its historical account of the session that wrote it.

> **⛔ SUPERSEDED 2026-08-20 (evening) by `2026-08-20-HANDOFF-phase2-T4-start-here.md`.**
> T3 is DONE (built, gate-reviewed, app-proven — closure in the decision record §8). The
> owner rules and environment traps below remain true and are restated (plus T3's new
> lessons) in the successor file. Read THAT file, not this one.

# HANDOFF 2026-08-20 — Multi-device program: T1+T2 done, T3 (provisioning SAS) is your job

**You are a fresh agent picking up a multi-session program mid-flight. This file is the
authoritative, self-contained entry point.** It SUPERSEDES
`2026-08-19-HANDOFF-phase2-start-here.md` (whose owner rules and environment traps remain true
and are restated here; its "two open decisions" are DECIDED and its repo state is stale).

---

## 0. Read order (do this before anything else)

1. This file, fully.
2. Root `CLAUDE.md` (workflow, §3 verification counts, §6 migrations, §7 wire contract) and
   `backend/CLAUDE.md` + `frontend/CLAUDE.md` before first change in a tier.
3. The FROZEN spec `docs/design/multi-device.md` — §5.1 (your ticket), §3, §7, §10, and **§12's
   dated amendment blocks at the end** (three blocks of 2026-08-19: allocator decision, cooldown
   carve-out, and the Stage-0 amendments (a)–(h) which are NORMATIVE for Phase 2).
4. `docs/plans/2026-08-19-phase2-stage0-decision-record.md` — finding-to-ticket map, §4 riders
   (T3's riders are your requirements), §6/§7 T1/T2 closures.
5. `docs/plans/2026-08-19-multi-device-prior-art-research.md` — synthesis only (~250 lines);
   appendices when you need a primary-source claim.
6. Planning files: `C:/Users/Lentach/Desktop/Fireplace/.planning/multi-device/`
   (`task_plan.md`, `findings.md`, `progress.md`) — MAIN checkout, gitignored, the cross-session
   memory. MAINTAIN THEM as you work (update progress after each phase, findings after each
   discovery). Do NOT mint new planning files at the worktree root.
7. Subagents inherit NOTHING. Every task brief you write must name these files explicitly.

## 1. Owner rules (binding; each was earned by an incident)

1. **Investigate and PROVE, then ASK before writing code** — diagnostics count as code
   (`4beb1bd` landed on a symptom, reverted). Ticket work inside the approved T1–T8 DAG is
   pre-authorized; anything OUTSIDE a ticket needs an ask.
2. **Ask before opening the browser tool — every time.** Authorization is per-task and expires.
3. **Never merge, never deploy.** One branch, one merge at program end. PR #144 = review surface.
4. **Never self-review.** Fresh `reviewer` subagent per ticket close; THREE independent reviewers
   at phase gates. Defensive framing ("verify our protections hold") — adversarial wording gets
   content-filtered.
5. Writer subagents ≤2 concurrent; read-only reviewers ×3 fine; Anthropic-only.
6. Never `dart format lib/` or prettier globs — format ONLY the exact files touched.
7. **Never give `flutter test` a file list** (45 files once timed out past 11 min; full suite is
   170–310 s). This includes `test_e2e` — full suite only.
8. Owner is non-native English; explain mechanics plainly; delays are testable in seconds via
   timestamp updates (never wait out a 24 h/72 h window).
9. Session end: write `.cursor/session-summaries/YYYY-MM-DD-session-*.md` + update `LATEST.md`
   (**caps at 5 dated entries** — a hook rejects a 6th; rotate the oldest into a
   "Still binding, from the rolled-off …" line).

## 2. Repo state

- Worktree `C:/Users/Lentach/Desktop/fireplace-0a`, branch `feat/takeover-alarm-0a` == origin,
  clean. Main checkout `C:/Users/Lentach/Desktop/Fireplace` on `master` (`cc8442b`, 0.1.17).
- `origin/wip/otp-identity-gate` (`8d61bde`) is SUPERSEDED — never merge it.
- Nothing merged, nothing deployed. Commit spine (new → old):

```
7c28e40 docs: T2 closed
6101774 feat: DAK-signed device list (T2)                    ← T2
518a742 docs: T1 closed
584f2d3 feat: migration 0016 (T1)                            ← T1
bddc1b7 docs: live-fire proof of the cooldown carve-out
1d2065d docs: Stage 0 closed PASS-WITH-AMENDMENTS
9c70d5b docs: carve-out session summary
94d030d feat: password change voids the post-cancel cooldown  ← carve-out, wire+app-proven
e697f43 docs: decisions locked
250c619 docs: multi-device prior-art research
0e8d005 … (see the superseded 08-19 handoff for the older spine: 573458b OTP gate option A,
          49bd92c/3c8bd31 master merges, edd3bb4…50434a8 = phases 0a/0b/1)
```

## 3. What is BUILT (all app- or wire-proven)

- **Phase 0a** takeover alarm; **0b** registration lock + 72 h reset ceremony + recovery key
  (Argon2id, single-use, 1 h shortened window); **Phase 1** per-device schema (migration 0015:
  `devices`, per-device `key_bundles`/OTPs, `refresh_tokens.device_id`, push `deviceId`,
  `messages.originDeviceId`/`sendToken` + partial unique).
- **OTP identity gate, option A** (`573458b`): client stashes OTPs, publishes the bundle, releases
  keys only on `keyBundleUploaded success:true`; drops on refusal; `identityChanged:true` mints a
  fresh pool. Server refuses OTPs under an unpublished identity. **Do NOT restore back-to-back
  emits.**
- **Cooldown carve-out** (`94d030d`): a password change voids a 24 h post-cancel cooldown armed
  BEFORE it (`identity-reset.service.ts` ~:143-161, innerJoin users + `passwordChangedAt`
  predicate + warn log). Wire-proven AND live-fired in the real app end-to-end.
- **T1** (`584f2d3`): `users.nextDeviceId` (default 2) + `DevicesService.allocateDeviceId`
  (atomic `UPDATE … RETURNING "nextDeviceId"-1` = PRE-increment; never decremented; NO callers
  yet — **you add the first caller in T3**), `account_authorizations` (lazy, first-write-wins,
  `enrollmentCreatedAt` stores the signed timestamp), `message_envelopes` (UNIQUE
  (messageId,recipientUserId,recipientDeviceId); `messageId` FK **ON DELETE CASCADE** = the sole
  §5.6 destruction mechanism; NO FK on the recipient pair; starts EMPTY, no backfills).
- **T2** (`6101774`): server enrollment (first-write-wins via userId-PK INSERT, 23505 →
  `already_enrolled`), byte-exact `listCanonical` (parse→re-encode→byte-compare; duplicates/
  ambiguity rejected at parse), `fp-list-v1\0` DAK-signed list with atomic-CAS version law
  (`stale_version`), wire events `enrollDeviceAuthority`/`updateDeviceList`/`getDeviceList` →
  `deviceAuthorityEnrolled`/`deviceListUpdated`/`deviceList`, `deviceListChanged` broadcast.
  Client: I7 chain verifier (`frontend/lib/services/device_list/`) + **`DeviceAuthorityEngine`**
  (mints DAK, builds enrollment E + v1 canonical list, signs, emits — harness-driven, NO UI,
  DAK held in memory only). Falsification 25 pinned BOTH directions against the frozen §6.1
  layout with REAL-Dart vectors (`frontend/tool/device_list_vector_generator.dart`).

**Silent-break invariants (each has bitten):** every index mirrored on its entity
(`synchronize` drops undeclared ones); every entity in BOTH module `forFeature` AND
`app.module.ts` entities; `repo.query()` returns `[rows, rowCount]`; column casing per table
(refresh_tokens snake_case, messages mixed, new tables camelCase-quoted); migrations 0015/0016
not code-reversible; **both Dart `Curve.calculateSignature` and `curve25519-js.verify` MUTATE
their buffers — always pass copies**; wire contract = request-event → response-event, NO
socket.io callback acks; `listCanonical` is opaque base64, byte-exact, never re-serialized
before verification.

## 4. Verification numbers (root CLAUDE.md §3 — reproduce, don't trust)

```bash
cd backend && npm test                                      # 850 tests / 55 suites
cd backend && node ../scripts/lint-ratchet.mjs              # PASS at 906
cd frontend && cmd /c flutter analyze --no-fatal-infos      # clean
cd frontend && cmd /c flutter test                          # 1405 / 10 skipped
cd frontend && E2E_BASE_URL=http://127.0.0.1:3000 cmd /c flutter test test_e2e   # 32 / 2 skipped
cd backend && node ../scripts/verify-claude-backend-test-counts.mjs
cd frontend && node ../scripts/verify-claude-frontend-test-counts.mjs --log test-output.txt
#   (that verifier RUNS the suite into the log you give it; DELETE test-output.txt before commit)
```

**Flake ledger (pre-existing, NOT ours — re-run the FULL suite once, do not chase):**
1. `test/widgets/input/chat_input_bar_attachment_test.dart` "video-then-caption" — fails ~2/3.
2. `test/services/unread_badge_sync_test.dart` "falls back to the window Badging API" — seen
   once under back-to-back suite load.

## 5. Environment traps (all paid for — trust this list)

- Docker stack `fireplace-0a-*` (worktree compose). DB is **`chatdb`** on :5433
  (`docker compose exec -T db psql -U postgres -d chatdb -c "…"`). **Check `docker ps` for
  squatter stacks first** — a foreign `fireplace-emu`/`fireplace-repro` stack has grabbed ports
  3000/5433 before. If one is there, ASK the owner before stopping it.
- **Always `127.0.0.1:3000`** — `localhost` is broken on this PC (stale wslrelay on `[::1]`).
- `docker compose restart backend` then poll `curl -s http://127.0.0.1:3000/health` — cold boot
  can take **3.5–7 min** (a 400 s poll once expired seconds before a healthy boot; be patient
  and re-check before diagnosing). `nest --watch` recompiles WITHOUT relaunching ("Found 0
  errors" while :3000 is dead) → restart is the only trustworthy relaunch.
- **Wire suite discipline:** restart backend first (the `/auth/register` throttle is 10/hr/IP
  in-memory and the suite spends ~10 — NEVER add registrations to harness files, reuse suite
  accounts), wait **≥20 s** after `/health` flips, run it ALONE (a parallel run corrupted a
  result), full suite only.
- Windows: `cmd /c flutter …` (bare flutter = os error 193). Web release build:
  `cmd /c flutter build web --release --dart-define=BASE_URL=http://127.0.0.1:3000`, serve
  `frontend/build/web` with `python3 -m http.server <port>` — **each origin/port is a separate
  storage; rebuild after ANY lib/ change**.
- Browser tool (ASK FIRST): CanvasKit semantics are empty until you click
  `flt-semantics-placeholder` — **after EVERY reload**; `tab.click('aria-ref=…')` times out on
  Flutter — map `flt-semantics` bounding boxes + `page.mouse.click`; typing: ONLY CDP
  `Input.insertText` works (`page.keyboard.type` drops chars; setting `input.value` never
  reaches Flutter; zeroing DOM value does NOT clear the controller); screenshots are
  DPR-scaled; transient snackbars live ~0.6–2.5 s — sample every ~600 ms, and prefer backend
  logs as ground truth for refusals.
- Delay testing in seconds (never wait):
  ```sql
  update identity_reset_requests set "deadlineAt"=now()-interval '1 minute'
    where "userId"=<id> and status='pending';   -- cron @EVERY_MINUTE completes it
  update identity_reset_requests set "cancelledAt"=now()-interval '25 hours'
    where "userId"=<id>;                        -- ages out the cooldown (read-time predicate)
  ```
  Mixed clocks: `cancelledAt`/`completedAt` = DB now(); `deadlineAt` = Node Date.now().
- Logs: `docker compose logs backend --since 5m | grep -iE "identity-lock|identity-reset"`.
  Durable: Postgres `identity_reset_requests`, `identity_change_audit`; client
  `E2ePersistentDiag` (cap 80). Docker json-file rotates 10m×3.
- Test accounts (local chatdb): **193 = `pg5802614#6248` / `Fireplace!2620`** (password changed
  2026-08-19; identity `BVVFJ/DuqMwR`, 100 OTPs), 205 = `pr8963550rc489731` / `FireplaceFixed!7`,
  204 password unknown. Login DTO field is `identifier` (`username#tag`).

## 6. Governance: what Stage 0 fixed (NORMATIVE for your ticket)

Stage 0 (three independent reviewers) closed PASS-WITH-AMENDMENTS. The §12 Stage-0 block,
items (a)–(h), is binding. The ones that shape T3:

- **(a) Allocator ordering + idempotency:** the SERVER allocates the deviceId exactly ONCE per
  `provisioningId` (memoized on the stage, at `openProvisioning`) and delivers it to the primary
  BEFORE the primary signs `provisionDevice`. Duplicated/retried `provisionDevice` re-uses the
  memoized id. `provisioningComplete` = atomic compare-and-set stage consumption inside ONE
  transaction; stage retires at commit. Aborts never decrement the counter (gaps are safe).
- **(b) Session rebind:** at `provisioningComplete` the server re-issues N's access+refresh
  tokens BOUND to the assigned deviceId (`refresh_tokens.device_id` + `createToken(userId,
  deviceId)` plumbing already exists); N MUST NOT upload key material until its socket is
  authenticated under that id (every per-device path keys off the JWT deviceId — an early upload
  would land on device 1 and OVERWRITE the primary's bundle). Uploads for never-activated
  deviceIds are REJECTED (today `DevicesService.touch` auto-inserts any presented id — closing
  that is a NAMED T3 deliverable).
- **(c) ephPubN is QR-ONLY:** never echoed in `openProvisioning` responses, relay frames, or
  logs. The no-commitment SAS soundness argument RESTS on this. `provisioningHello` pins the
  FIRST `ephPubP` and is accepted only from an authenticated session of the account.
- **(d) Signature contexts:** `fp-enroll-v1\0` (IK), `fp-list-v1\0` (DAK), `fp-dak-rotate-v1\0`
  (old DAK — T3 §6.3 rotation if in scope, else T6). First byte ≠ 0x05; frozen §6.1 layout
  byte-exact as landed. Falsification 25 already pins cross-construction rejection.
- **(f) Reset × roster:** §6.2 reset allocates the recovering device's id from `nextDeviceId` —
  NEVER re-mints device 1 (implementation lands with T6's purge widening, but never write
  anything in T3 that assumes device 1 is re-mintable).
- CONFIRMED, do not re-litigate: the two-round DH-bound SAS needs NO extra commitment round
  (given (c)); an optional /prototype exists ONLY for the ~20-bit comparison UX.

**T3 riders (decision record §4):** never-activated-deviceId rejection; optional SAS-UX
prototype; from T2's review: client-side NFC normalization of device names (Dart parser
deliberately accepts non-NFC today — the server is the only storage gate), DAK Keystore
persistence (T2 engine holds it in memory), wire `DeviceAuthorityEngine` to the real
enable-linking UI.

## 7. YOUR JOB: T3 — provisioning ceremony (spec §5.1, the biggest ticket)

Two-round DH-bound SAS, secrets-last, two-phase commit. Read §5.1 lines ~164-218 completely;
the mechanism in one breath: new device N `openProvisioning` (server allocates deviceId per (a),
10-min TTL) → N shows QR `{provisioningId, ephPubN}` → primary scans (OOB) → primary
`provisioningHello {ephPubP}` (NO secrets) → both derive
`SAS = HKDF(S_dh, info="fp-link-sas", provisioningId‖ephPubN‖ephPubP)` → humans compare → primary
approves → `provisionDevice` carries the AEAD blob under `HKDF(S_dh, info="fp-link-blob")`
containing `{IK pair, dakPub, enrollment E, assigned deviceId}` + the DAK-signed staged list
mutation v+1 → N `provisioningComplete` → ONE transaction: stage consumed (CAS), device row
committed, list v+1 committed, N's tokens re-issued with the deviceId (b) → N reconnects under
its id and only THEN uploads its per-device bundle/OTPs. Abort hygiene: N discards everything;
TTL expiry/cancel/revoke preempts the stage; blob re-fetchable until TTL, retired at commit.

What exists for you: T1 allocator (`allocateDeviceId` — you are its FIRST caller),
T2 enrollment/list machinery + `DeviceAuthorityEngine` + chain verifier, Signal's provisioning
cipher precedent (Appendix A §5 of the research doc; but OUR construction is the spec's explicit
calculateAgreement+HKDF one — NOT stock ProvisioningCipher, which mints its own ephemeral),
`refresh_tokens.device_id` + `createToken(userId, deviceId)`.

Relevant falsifications (§10): 8 (blob replay/expiry/one-shot/session-bound), 15 (SAS grinding —
DH-bound), 18 (two-phase kill between blob and complete), 20 (concurrent double-link: two staged
mutations at v+1 → second rejected; revoke preempts stage). Extend 8/18/20 with the (a)
idempotency cases (duplicate hello pins first ephPubP; duplicate provisionDevice reuses the
memoized id; duplicate completes commit exactly one device row).

UI: this is the first ticket with real UI (QR display on N, scanner/approve on primary, SAS
comparison screens). Use the `flutter-frontend-design` skill for any new screens. The QR can be
rendered as data (the repo may lack a QR package — check pubspec; adding one needs it to resolve
against the pinned SDK; `bip39` precedent: pick packages that resolve, e.g. `bip39_mnemonic` was
chosen because `bip39` pinned sdk <3.0.0).

**T3 is NOT done at green suites.** It is the first ticket with a user-visible surface, and the
owner's standing rule is app-prove user-visible changes — plan the live-fire INTO the ticket up
front, not after review: release build, TWO storages = two origins (two ports, two
`python3 -m http.server` instances — §5 traps), one as the primary and one as the linking
device N; drive the whole ceremony (QR shown on N → "scanned" on the primary → both SAS screens
show the SAME code → approve → N reconnects under its assigned deviceId → N's bundle lands at
deviceId 2 in `key_bundles`, the list is v2, the primary's bundle UNTOUCHED), plus one refusal
path (SAS mismatch / cancel → nothing committed, counter gap only). ASK the owner before
opening the browser — every time.

## 8. After T3: the remaining DAG

T4 envelopes + `device:<uid>:<did>` rooms + per-device history reads (riders: preKeysLow routing,
`originDeviceId IS NULL` = device 1, landmine-2 red test, stamps never enter expiry, scoped
UPDATE conversion, recipientUserId-FK decision) → T5 self-sync + lost-ack + client `sendToken`
(THE declared bug epicenter; `frontend/CLAUDE.md` §5 lost-ack insurance is required reading;
riders: `tempId != null` survives the guard flip, re-ack-never-re-fan) → T6 revocation + stale
bounce + reset-roster teardown (amendment (e) receive-time origin check; purge widening; I6
silence in `handleGetServedMessageIds`) → T7 edit re-fan (UPSERT content-only, stamps survive) →
T8 harness sweep (falsify at RECEIVE time). Falsifications 16/22 (senderListInfo) land with
T4/T5.

## 9. Research: what exists, how to do more

- `docs/plans/2026-08-19-multi-device-prior-art-research.md`: synthesis keyed to T1–T8 + four
  fully-cited appendices (Signal source @2f482f68, Matrix spec + vodozemac, WhatsApp whitepaper
  v9 + iMessage CKV + RFC 9420 + attack papers, our spec map). Headline: Signal REUSES device
  ids but only survives via registrationId+purge+410 machinery we lack — our never-reuse is
  confirmed; Matrix m.sas.v1 is the SAS reference; WhatsApp's prefix bytes are the
  domain-separation model; nobody has a reset cooldown (we are the strict outlier).
- Need more? Use the `research` skill: spawn `librarian` subagents against PRIMARY sources
  (specs/source code), one topic each, `local://` outputs, then compile a dated file in
  `docs/plans/` (convention: `YYYY-MM-DD-<topic>-research.md`). Batch independent researchers in
  ONE task call. `scout` for read-only codebase mapping. Everything cited or marked UNVERIFIED.

## 10. Working rhythm (how this program is executed)

1. One ticket at a time. Dispatch ONE fresh writer subagent with a SELF-CONTAINED brief (name
   every file/rule — it inherits nothing; include the §5 traps it will hit). Writers ≤2.
2. Writer works red-first, runs its tier's suites, commits on the branch, does NOT push.
3. You (orchestrator) verify EVERY claim: full suites yourself, counts, verifiers. `completed`
   ≠ accepted. If a writer dies mid-flight (rate limits happen — T2's did), its work is in the
   worktree: inspect `git status`, verify what's real, finish the remainder yourself.
4. Fresh `reviewer` subagent per ticket close (defensive framing; give it the delta commit ids +
   ground-truth docs + review axes). BLOCKER/FIX → fold before push; NOTEs → riders in the
   decision record.
5. Push code + closure docs together; update the decision record (closure section per ticket),
   `LATEST.md` (5-entry cap!), the dated session summary, and the planning files.
6. App-prove user-visible changes (ASK before browser). Wire/DB/logs are ground truth.
7. Phase gate (after T8): THREE independent reviewers, then owner decides the merge.

## 11. Standing blockers (owner-side, do not chase)

`FIREBASE_SERVICE_ACCOUNT` absent on the VM (FCM dead in prod; APK push dead until set);
`.jks` off-PC backup owed; owner-iPhone confirmation for 0.1.16/0.1.17 attachment popover.
Accepted-not-fixed P3: reset banner lacks `Semantics(liveRegion:true)`; offline recovery-key
save shows a generic failure toast after ~6 s.

## First five actions

1. Read order §0 (this file → CLAUDE.mds → spec §5.1 + §12 amendments → decision record).
2. `docker ps` (squatters?) → `docker compose up -d` in the worktree → poll `/health`
   (be patient, §5) → reproduce 850/55 · 906 · clean · 1405/10sk · 32/2sk (restart backend
   before the wire run; ≥20 s settle; alone).
3. Confirm branch == origin at `7c28e40`, worktree clean.
4. Design T3 against §5.1 + amendments (a)(b)(c) + riders (§6/§7 of this file). If any spec
   ambiguity blocks a schema/wire choice, settle it BEFORE code (spec amendment via dated §12
   entry, matching the existing precedent) — never guess silently.
5. Dispatch the T3 writer with a self-contained brief; verify; review; fold; push; books.
