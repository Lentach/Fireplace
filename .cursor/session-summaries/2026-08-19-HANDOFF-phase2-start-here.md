> ## ⛔ SUPERSEDED 2026-08-20 — read `2026-08-20-HANDOFF-phase2-T3-start-here.md` instead.
> Everything below predates: both owner decisions (now LOCKED), the cooldown carve-out
> (`94d030d`, live-fired), Stage 0 (CLOSED, amendments (a)–(h)), T1 (`584f2d3`) and T2
> (`6101774`). Its §1 owner rules and §5 environment traps remain true and are restated in the
> 08-20 file; its "two open decisions" and repo state are STALE.

# HANDOFF — Fireplace multi-device, Phase 2 starts here (2026-08-19)

**You are picking up a program mid-flight. Read this file to the end before touching anything.**
It supersedes `2026-08-18-HANDOFF-phase2-start-here.md` for everything that changed on
2026-08-19; that file is still the authority for its §1 inherited preconditions, which are
restated in §7 below.

---

## 0. Read order (do not skip)

1. Root `CLAUDE.md` — workflow rules, deploy safety, §3 test counts, §6 migration hazards, §7 wire contracts.
2. The tier file for wherever you touch first: `backend/CLAUDE.md` or `frontend/CLAUDE.md`.
3. `docs/design/multi-device.md` — **v5, FROZEN 2026-08-17**. §5 protocols, §9 phase plan, §10 falsifications, §12 review record.
4. This file.
5. `2026-08-19-session-otp-identity-gate.md` (what landed yesterday and why) and
   `2026-08-18-session-phase1-local-verification.md` (the local verification + the finding that produced it).

Delegating? Subagents inherit **nothing**. Name these files explicitly in every task.

---

## 1. Owner rules — binding, learned the hard way

1. **Investigate and PROVE, then ASK before writing code.** Diagnostics and instrumentation count as code. A fix landed on a symptom (`4beb1bd`) had to be reverted (`409c23a`); do not repeat that.
2. **Ask before opening the browser tool — every time.** Authorization is per-task, and it expires. (I read "launch the app locally and check" as authorization; that is the bar.)
3. **Never merge, never deploy, without an explicit OK.** The whole program accumulates on ONE branch; there is exactly one merge at the end. PR #144 is a review surface, not a merge queue.
4. **Never self-review.** Use `reviewer` subagents with defensive framing (`security-reviewer` gets content-filtered on adversarial wording). **Three independent reviewers at each phase gate** — that is the established pattern and the owner expects it.
5. Anthropic-only subagents. Writer concurrency ≤ 2; read-only reviewers ×3 is fine.
6. **Never** run `dart format lib/` or a `prettier --write src/**` glob — format only the exact files you touched (a glob reformatted three untouched auth files and had to be reverted).
7. **Never** give `flutter test` a file list (per-argument compile cost: 45 files timed out past 11 min vs 170–310 s for the whole suite). One file or one directory or everything.
8. At task end: write `.cursor/session-summaries/YYYY-MM-DD-session.md` and update `LATEST.md`. **`LATEST.md` caps at 5 dated entries** — a pre-commit hook rejects a 6th; rotate the oldest out. Run `git status -sb` before every commit.
9. Code wins over docs. When source and a doc disagree, trust source and fix the doc.

---

## 2. Repo state right now

| Where | What |
|---|---|
| Worktree | `C:/Users/Lentach/Desktop/fireplace-0a`, branch `feat/takeover-alarm-0a` == `origin`, **clean** |
| HEAD | `573458b` — "fix: one-time pre-keys wait for their identity to be published (option A)" |
| Main checkout | `C:/Users/Lentach/Desktop/Fireplace` on `master` (`bf11861`) — pointer only, no program code |
| Side branch | `origin/wip/otp-identity-gate` (`8d61bde`) — **superseded**, server-half-only version of the OTP gate; its `BRANCH-NOTE-otp-identity-gate.md` records the collision that shaped the final fix. Do not merge it. |
| Merged/deployed | **Nothing.** Prod runs frontend `0.1.16` / backend `0.1.11`, none of this program. |

Commit spine (program delta starts at `50434a8`):

```
573458b fix: one-time pre-keys wait for their identity to be published (option A)
6c5c6a4 docs: the OTP gate is built and app-proven, parked on wip/otp-identity-gate
0592946 docs: local verification of the whole program at 49bd92c, plus one unfixed finding
49bd92c/3c8bd31  merges of origin/master (docs-only conflicts; a conflicted PR gets NO CI)
edd3bb4 docs: sendToken is server-side only
8a86169 fix: carry `shortened` into connect-time hydration
e889495 fix: bind key uploads to the session's device
d08d4ab feat: Phase 1 — key material, sessions and messages become per device
2bf60ea fix: stop the recovery path alarming its own user
ed77faa fix: close four 0b defects
50434a8 docs: 0a evidence
```

---

## 3. What is BUILT (and must not regress)

**Phase 0a — takeover alarm (§6.0).** Identity replacement writes a durable `identity_change_audit` row (migration `0013`), notifies the account's other sockets (`ownIdentityReplaced`, uploader excluded), sends a content-free push, and flags conversation peers (`peerIdentityChanged` → in-chat timeline row). Same-identity re-uploads stay silent.

**Phase 0b — registration lock + reset ceremony + recovery key (§6.1/§6.2/§6.2.1).** Replacing a stored identity needs `sig_oldIK(newIK ‖ userId ‖ nonce)` or a completed ceremony (single-use). Ceremony: migration `0014`, 72 h (1 h with a recovery phrase), one pending per account enforced by a PARTIAL UNIQUE INDEX, 24 h post-cancel cooldown, per-minute sweep whose `status='pending'` predicate IS the cancel/expiry serialization. Recovery phrase stored only as an Argon2id verifier (19 MiB/t=2/p=1), single-use, lockout after 5 failures.

**Phase 1 — per-device key material (§4/§5.1/§8).** Migration `0015` in ONE transaction: `devices` table (`userId, deviceId` PK, backfilled so every existing account is its own primary device 1), `key_bundles` unique → `(userId, deviceId)`, OTPs unique → `(userId, deviceId, keyId)`, `refresh_tokens` `+device_id/+device_name` (snake_case — that table's own convention), push tables `+deviceId`, `messages` `+originDeviceId/+sendToken` with a PARTIAL unique index on `(sender_id, sendToken)`. JWTs carry `deviceId`; `consumeAndSlide` returns it; `DevicesService.touch` is update-then-insert (never upsert — an upsert would erase a Phase-2 primary handover and the migration's `platform='legacy'`). Identity epoch re-keyed to `(identityPublicKey, deviceId)` at all three sites (purge / claim / count). `fetchPreKeyBundle` has NO cross-device fallback: absent means absent.

**2026-08-19 — one-time pre-keys belong to a PUBLISHED identity.** Server refuses `uploadOneTimePreKeys` whose `identityPublicKey` is not the account's published one (`error {message:'identity_locked'}`, logged `warn`), with two carve-outs: nothing published yet (fresh registration), and an unspent **COMPLETED** ceremony (authorized rotation in flight; the read never spends the grant). A merely PENDING ceremony authorizes nothing. Client publishes the identity FIRST and releases the keys on `keyBundleUploaded {success:true}`; a refusal DROPS them (`OTP_UPLOAD_DROPPED`); `identityChanged:true` mints a fresh pool immediately, because the epoch purge just emptied it and the ceremony-spending re-upload carries no keys of its own.

### Invariants you can break by accident

- **Every index must be mirrored on its entity.** `synchronize` (dev/CI) DROPS what entities don't declare — it silently removed the 0b one-pending partial index, and mocked specs cannot catch it.
- **New entity → register in BOTH the module's `forFeature` AND `app.module.ts`'s DataSource `entities`.** Missing the second threw `EntityMetadataNotFoundError` live while every unit test was green; the wire harness caught it.
- `repo.query()` on Postgres returns `[rows, rowCount]` for UPDATE/DELETE even with `RETURNING` — destructure or you read the wrong shape (this bug served `oneTimePreKeyId: null` for weeks while burning OTPs).
- Raw SQL must quote camelCase columns, and casing is **per entity** (`refresh_tokens` is snake_case, `messages` mixes: `sender_id`, `conversation_id`, `"originDeviceId"`, `"sendToken"`, `"createdAt"`).
- ⛔ **Migration `0015` is not code-reversible** (root `CLAUDE.md` §6): it drops the account-wide uniques the pre-Phase-1 backend upserts against, so rolling the image back without recreating them fails every key/OTP upload with `42P10`.

---

## 4. Verification — commands and the numbers they must produce

```bash
cd backend && npm test                       # 774 tests / 52 suites
cd backend && node ../scripts/lint-ratchet.mjs               # PASS, held at 906 real errors
cd frontend && cmd /c flutter analyze --no-fatal-infos       # No issues found
cd frontend && cmd /c flutter test                           # 1375 / 10 skipped
# wire harness — needs the stack up AND a throttle reset first:
cd frontend && E2E_BASE_URL=http://127.0.0.1:3000 cmd /c flutter test test_e2e   # 25 / 2 skipped
cd backend && node ../scripts/verify-claude-backend-test-counts.mjs
cd frontend && node ../scripts/verify-claude-frontend-test-counts.mjs --log test-output.txt
# delete frontend/test-output.txt before committing
```

Root `CLAUDE.md` §3 must state those numbers for **each commit's tree** — pre-commit hooks verify it.

**Known pre-existing flake, NOT yours:** `test/widgets/input/chat_input_bar_attachment_test.dart` → "video-then-caption keeps the media-first ordering contract" fails ~2 runs in 3 (proven by stashing all `lib/` changes). It deserves its own session.

---

## 5. Environment — every trap here was paid for in hours

- **Docker Desktop is currently STOPPED** (the daemon pipe is gone; the machine likely slept). Start it, then `docker compose up -d` in `fireplace-0a`, and confirm **both** `db` and `backend`.
- **The local DB is `chatdb`.** `psql -d fireplace` fails.
- **`localhost:3000` is broken on this PC** (stale `wslrelay.exe` on `[::1]:3000`). Always `127.0.0.1:3000`; the harness needs `E2E_BASE_URL=http://127.0.0.1:3000`.
- If `backend` starts before `db` it dies with `getaddrinfo ENOTFOUND db` and reports `unhealthy` forever → `docker compose restart backend`.
- **`nest --watch` recompiles WITHOUT relaunching**: logs "Found 0 errors" while nothing listens on `:3000`. Always poll `curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:3000/health` for up to ~5 min. A hung wire suite is almost always this.
- **`/auth/register` is 10/hr per IP, in memory.** The wire suite spends ~10. `docker compose restart backend` resets it — and takes 3–5 min to answer `/health` again. Budget for that.
- Direct `flutter` spawn fails with **os error 193** → always `cmd /c flutter …`.
- **`flutter run -d web-server` serves exactly ONE debug client.** For multi-device UI work: `cmd /c flutter build web --release --dart-define=BASE_URL=http://127.0.0.1:3000`, then `python3 -m http.server <port>` in `frontend/build/web`. **Each origin is a separate storage**, so `127.0.0.1:8081`, `localhost:8081`, `127.0.0.1:8082`, … give you as many independent "devices" as you need. **Rebuild after any `lib/` change** or you are testing the old bundle (I lost a cycle to exactly that).
- **CanvasKit:** the semantics tree is empty until `document.querySelector('flt-semantics-placeholder').click()`. `tab.click('aria-ref=…')` times out — map `flt-semantics` bounding boxes and use `page.mouse.click`. Screenshots are DPR-scaled (multiply by `viewport/screenshotWidth`).
- **Typing into Flutter web drops every keystroke after the first** with `page.keyboard.type`, and setting `input.value` + dispatching `input` never reaches the framework. **Only CDP `Input.insertText` works** → `page.keyboard.sendCharacter(ch)` per character.
- **Clearing a field by zeroing the DOM `input.value` does NOT clear the framework's controller** — my next typed username APPENDED and created the account `pr8963550rc489731`. Focus the field, then Ctrl+A / Backspace through the framework.
- Transient UI (refusal snackbars) lives ~0.6–2.5 s. **Sample the DOM every ~600 ms** before concluding something was silent; I called a working refusal "silent" once by screenshotting at 5 s.

### Time-based behaviour is testable in seconds, never by waiting

There is **no timer** for either delay:
- **Ceremony deadline (72 h / 1 h):** stored `deadlineAt`, swept by `@Cron(EVERY_MINUTE) completeDueResets` (`identity-reset.service.ts:386`) with `status='pending' AND "deadlineAt" <= now()`. To complete one now:
  `update identity_reset_requests set "deadlineAt" = now() - interval '1 minute' where "userId"=<id> and status='pending';` then wait ≤ 60 s.
- **24 h post-cancel cooldown:** no job at all — a read-time predicate `cancelledAt > now() - 24h` (`:134-142`). To age it out: `update identity_reset_requests set "cancelledAt" = now() - interval '25 hours' where …`.

Clock sources are mixed and worth knowing: `cancelledAt`/`completedAt` are written with DB `now()`, `deadlineAt` with Node `Date.now()`, and each is compared on the other side. Harmless on one host; first suspect if a delay ever misbehaves.

### Where evidence lives

- **Nest logger → stdout → Docker json-file, rotated (`10m` × 3).** `docker compose logs backend --since 3m | grep -iE "identity-lock|identity-reset"`. Prefixes to know: `[identity-lock] REFUSED …`, `[identity-reset] ceremony started|cancelled|delay elapsed, identity replacement authorized|completed ceremony consumed`. **Not durable, not queryable.**
- **Postgres is the durable record:** `identity_reset_requests` is the ceremony audit trail (terminal states, nothing deleted); `identity_change_audit` holds one row per identity replacement and is what a reconnecting session reads.
- **A cooldown refusal currently logs NOTHING** server-side (`:143-145` just returns). If you touch that branch, add a warn line — it is also how you'd verify the change live.
- **Client-side durable diag:** `E2ePersistentDiag` (capped 80, survives restart, visible in Privacy & Safety hacker-mode) carries `KEY_BUNDLE_IDENTITY_LOCKED`, `OTP_UPLOAD_DROPPED`, `OTP_REPLENISHED`, …

---

## 6. Open decisions — ASK, do not choose for the owner

1. **`deviceId` reuse vs §5.3 — BLOCKS Phase 2 schema.** Today a post-reset device is id 1 again; §5.3 requires ids never be reused. Options: reuse + epoch gating, or never-reuse via a per-account high-water mark in `devices`. This decides migration `0016`'s shape. Owner has been asked; resolve it as **item 1 of the Stage 0 spec review**.
2. **Should a password change clear the 24 h post-cancel cooldown?** Fully analysed, not implemented. A password thief can self-arm the cooldown every 24 h and starve a genuine owner out of recovery; `POST /users/reset-password` requires the current password, revokes every refresh row and stamps `passwordChangedAt`, so it is the loop's kill switch — but the cooldown outlives it, and the app's own refusal copy already tells users to change their password. **Recommended shape:** in the cooldown query add `.innerJoin('users','u','u.id = r."userId"')` + `AND (u."passwordChangedAt" IS NULL OR r."cancelledAt" > u."passwordChangedAt")` — no new injection, no writes, no auth→reset coupling. Deliberately does NOT cancel a pending ceremony: `identity_reset_requests` has no requester column, so that would throw away up to 72 h of the owner's own wait. Needs: unit test (mocks can only prove the predicate exists — the real proof is live), a wire test (start→cancel→`cooldown`, change password, re-login, request→`pending`), a dated §12 amendment because the spec is FROZEN, and §3 count updates. ~60–90 min. Independent of Phase 2.

Standing owner blockers (not ours to fix): `FIREBASE_SERVICE_ACCOUNT` absent from `~/fireplace/.env` on the VM (FCM dead in prod, Android notifications too); `.jks` off-PC backup (`docs/runbooks/android-release.md`); owner-iPhone confirmation still owed for 0.1.16.

Accepted-not-fixed (P3): the reset banner is not `Semantics(liveRegion: true)`; an offline recovery-key save shows a generic failure toast after ~6 s.

---

## 7. Inherited landmines Phase 2 builds on top of

1. **`deviceId` 1 is reused across a reset** while §5.3 forbids it — wire the device-gated legacy fallback on top of that and a post-reset device gets served pre-reset ciphertext → foreign-ratchet decrypt. This is decision #1 above; it is the single most dangerous inherited fact.
2. The lock's *"lowest `deviceId` == the account identity"* shortcut (`key-bundles.service.ts`, `order: {deviceId:'ASC'}`) holds **only while all devices share one IK**. The new OTP gate uses the same shortcut. Both must be revisited the moment §5.2 lets devices differ. Keep `purgeSupersededDevices` atomic with the identity upsert.
3. `purgeSupersededDevices` drops `key_bundles` + `one_time_pre_keys` only — **not** `devices`, `refresh_tokens`, or push rows.
4. **`sendToken` is still server-side only** — `grep sendToken frontend/lib` = zero hits; only the wire harness mints one. Wiring it into the real send path is Phase 2 ticket T5 (§5.4).
5. **The registration-lock SIGNATURE path is harness-only too**: a device that lost its keys cannot sign, so the production route is always the ceremony.
6. `devices`, `refresh_tokens.device_id` and push `deviceId` are **written but read by nothing**; `originDeviceId` is not parsed by the Flutter `Message` model.
7. Self-sync is impossible today by construction: own-sender decrypt early-returns and plaintext comes only from the pending-send record. The new decrypt path must coexist with the lost-ack reconcile — the declared bug epicenter (`frontend/CLAUDE.md` §5 lost-ack insurance is required reading before T5).
8. `emitToNewestTab` (used for `newMessage`/`messageEdited`) exists because Signal decrypt is NOT idempotent and tabs share one session store. **Its premise inverts for real devices** — §5.3 replaces it with `device:<uid>:<did>` rooms. Do not room-address ciphertext before that lands.

---

## 8. Three rescues already tried and rejected — do not retry

While closing the OTP finding I tried to let the server tolerate keys arriving before their identity:

1. **Await this socket's in-flight `uploadKeyBundle`** after one macrotask yield — **empirically insufficient**: the trailing bundle frame is dispatched a tick later, so the marker is still unset when the OTP handler checks.
2. **A timed (~500 ms) poll** for that marker — works, but makes a lock's verdict depend on wall-clock latency. Rejected on principle.
3. **Blacklist identities the lock actually refused** — **fails open**: an attacker uploads the OTPs *before* ever attempting a bundle, so no refusal was ever recorded.

The ordering had to be fixed at the source (the client), which is what landed. The `NOTE (open decision …)` comment in `chat-key-exchange.service.ts` documenting the race is now stale in wording only — the client no longer races; leave the history or tighten it, but do not "restore" the back-to-back emit.

---

## 9. The plan for Phase 2

Per §9 the phase is: provisioning §5.1, DAK + signed list + cross-check §5.2, envelopes + history reads §5.3, self-sync §5.4, revocation §5.5, edit re-fan §5.7 — acceptance is a **two-device harness** (link → both receive → self-sync → edit re-fan → revoke → stale bounce) with **all §10 falsifications green**, and **its own spec review first**.

### Stage 0 — Phase-2 spec review (no code)

Agenda, in order:
1. **`deviceId` reuse vs §5.3** (decision #1) — settle this FIRST, because it shapes migration `0016`.
2. Re-ratify every §7 wire delta line by line — spec line 412 requires exactly this at this gate.
3. Confirm §7 landmines above, especially the "lowest deviceId == account identity" shortcut and what `purgeSupersededDevices` must also drop once devices are real.
4. Decide whether §5.1's DH-bound SAS needs a throwaway `/prototype` — a ~20-bit human comparison is a UI you have to see before committing to it.

Output: dated amendments in §12 + a decision record in a session summary. Then **three independent reviewers** on the amended delta, as at every prior gate.

### Stage 1 — tickets with blocking edges

| # | Ticket | Blocked by | §10 falsifications |
|---|---|---|---|
| T1 | Migration `0016`: DAK columns, device enrollment, list version, id-allocation rule | Stage 0 | — |
| T2 | Signed device list: serve, client verify, E2E cross-check (§5.2) | T1 | 16 |
| T3 | Provisioning ceremony, two-round DH-bound SAS (§5.1) | T1, T2 | 15, 17 |
| T4 | Envelopes: one ciphertext per (recipient, device), `device:<uid>:<did>` rooms, history reads (§5.2/§5.3) | T2 | 1, 13 |
| T5 | Self-sync + lost-ack coexistence; wire `sendToken` into the real send path (§5.4) | T4 | 2–8 |
| T6 | Revocation + stale-list bounce (§5.5) | T2, T3 | 9–12 |
| T7 | Edit re-fan under envelopes (§5.7) | T4 | 14 |
| T8 | Two-device harness sweep: every §10 falsification green | T3–T7 | all |

### Stage 2 — build

One ticket per session, context cleared between them. Each: red-first from its §10 falsification → implement → **`/code-review`** (Standards + Spec) on the diff → commit. `/handoff` at each boundary. `/tdd` is the inner loop. Do NOT `/triage` these — they are already agent-ready.

Expect T5 to be the long one. Expect T1 to be the one that must not be rushed: `0015` proved that a migration mistake here is not reversible.

---

## 10. How to work here (rhythm that has been working)

- **Red first, always.** Phase 1 was built by writing falsification 1 first and watching it fail three ways against the single-device server. Owner trusts that pattern; keep producing the same evidence.
- **Live Postgres beats mocks for anything SQL-semantic.** Mocked specs passed while `synchronize` had dropped a partial index; mocked specs cannot prove a predicate's semantics. The collision proof for two devices sharing an account lives in psql for exactly this reason.
- **The wire harness is the only automated check on the §7 contracts.** It caught two disaster-recovery bugs on its first two runs.
- **Prove behaviour in the real app when the change is user-visible.** The OTP gate was app-proven by re-running the exact UI actions that had clobbered a pool and showing 20 rows still tagged the published identity.
- Wire contract reminder: **no socket.io callback acks anywhere** — every pair is request-event → response-event (`uploadKeyBundle` → `keyBundleUploaded`, `resetIdentityRequest` → `identityResetStatus`, `fetchPreKeyBundle` → `preKeyBundleResponse`, …). Signature bytes are `newIK(33, incl. 0x05) ‖ utf8(String(userId)) ‖ nonce(32)`; the server strips `0x05` before `curve25519-js.verify`; **both** Dart `Curve.calculateSignature` and `curve25519-js.verify` MUTATE their buffers — pass copies.
- Keep `LATEST.md` at 5 entries, write the dated session file, and never re-derive test counts by arithmetic across a merge — run the suites.

---

## 11. First five actions for you

1. Start Docker Desktop, `docker compose up -d`, confirm `db` + `backend`, poll `/health` until `200`.
2. Re-run the four suites and confirm 774/52 · 906 · clean · 1375/10sk, then the wire harness at 25/2sk after a `restart backend`. Do not trust my numbers — reproduce them.
3. Read `docs/design/multi-device.md` §5.1–§5.7 + §10 end to end. This is the least-reviewed part of the design.
4. Ask the owner decisions #1 and #2 in §6, and ask whether Stage 0's three reviewers should run before or after the amendments are drafted.
5. Only then: Stage 0. No Phase 2 code until §5.3's id-reuse question is settled and written down.
