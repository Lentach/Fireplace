> **⚠️ SUPERSEDED 2026-08-22 — DO NOT START HERE.** This handoff is spent: its ticket closed, and every
> line number and count in it has since moved. The current entry point is
> `2026-08-22-HANDOFF-T8-start-here.md`, and the permanent record is `LATEST.md` plus the dated summary it
> names. Kept only for its historical account of the session that wrote it.

# HANDOFF 2026-08-21 (B) — Multi-device: T1–T5 done, T6 (revocation) is your job

**You are a fresh agent picking up a multi-session program mid-flight. This file is the
authoritative, self-contained entry point.** It SUPERSEDES
`2026-08-21-HANDOFF-phase2-T5-start-here.md` (T5 is DONE; that file's owner rules and traps remain
true and are restated here, plus everything T5's execution paid for).

⚠️ **Two things from T5 you must not re-learn the hard way.** (1) The handoff you are replacing
told its agent to flip "five own-sender guards" — the list was INCOMPLETE and the decisive gate was
missing, so trust code over any brief, including this one: **re-verify every line number before you
change it.** (2) T5's post-build review found a latent data-loss bug in code that had passed a
first review: a device id confirmed for one account survived into the next login. Treat "reviewed
once" as "reviewed once", not "safe".

---

## 0. Read order (do this before anything else)

1. This file, fully.
2. Root `CLAUDE.md` (workflow, §3 verification counts, §6 migrations, §7 wire contracts — §7 now
   documents `senderListInfo` and `socketReady`'s `deviceId`), then `backend/CLAUDE.md` and
   `frontend/CLAUDE.md` (§5 lost-ack insurance) before your first change in a tier.
3. The FROZEN spec `docs/design/multi-device.md` — **§5.5 (YOUR ticket)**, §5.1, §5.2, §5.3, §5.4,
   §4, §7, §10, and **every dated §12 amendment block**: 2026-08-19 (a)–(h), 2026-08-20 T3
   (i)–(iv), T4 (v)–(x), **T5 (xi)–(xx)**. All NORMATIVE. (e), (xii) and (xx) bind you directly.
4. `docs/plans/2026-08-19-phase2-stage0-decision-record.md` — §4 riders (T6's row is your
   requirements); §6–§10 are the T1–T5 closures. **§10 is the ticket you are building on.**
5. `docs/plans/2026-08-21-t5-self-sync-lost-ack-research.md` — the self-sync/lost-ack prior art and
   the guard map. §3 is the guard inventory you will need again for the revoked-device paths.
6. `docs/plans/2026-08-20-t4-envelope-fanout-research.md` and
   `docs/plans/2026-08-19-multi-device-prior-art-research.md` — envelope and program-wide prior art.
7. Planning files: `C:/Users/Lentach/Desktop/Fireplace/.planning/multi-device/`
   (`task_plan.md`, `findings.md`, `progress.md`) — MAIN checkout, gitignored, the cross-session
   memory. MAINTAIN THEM. Do NOT mint planning files at the worktree root.
8. Subagents inherit NOTHING. Every task brief must name these files explicitly.

## 1. Owner rules (binding; each was earned by an incident)

1. **Investigate and PROVE, then ASK before writing code** — diagnostics count as code
   (`4beb1bd` landed on a symptom, reverted). Ticket work inside the approved T1–T8 DAG is
   pre-authorized; anything OUTSIDE a ticket needs an ask.
2. **Ask before opening the browser tool — every time.** Authorization is per-session and EXPIRES.
   The 2026-08-21 (B) session was granted it for the T5 app-proof only; **that grant died with that
   session.**
3. **Never merge, never deploy.** One branch, one merge at program end. PR #144 = review surface
   only. `gh run list` after pushing; never merge on red.
4. **Never self-review.** Fresh `reviewer` subagent per ticket close; THREE independent reviewers at
   phase gates — and T5 proved they are worth it TWICE: the pre-ticket trio found a P1 that would
   have silently killed self-sync, and the post-build trio found a P1 data-loss path in code that
   had already passed a review. Defensive framing ("verify our protections hold"); adversarial
   wording gets content-filtered.
5. Writer subagents ≤2 concurrent; read-only reviewers ×3 fine; Anthropic-only.
6. Never `dart format lib/` or prettier globs — format ONLY the exact files you touched.
7. **Never give `flutter test` a file list** (45 files once timed out past 11 min; the full suite is
   170–400 s). Includes `test_e2e` — full suite only.
8. Owner is non-native English; explain mechanics plainly; delays are testable in seconds via SQL
   timestamp updates (never wait out a 24 h/72 h window).
9. Session end: dated `.cursor/session-summaries/YYYY-MM-DD-session-*.md` + `LATEST.md` update
   (**caps at 5 dated entries** — a pre-commit hook rejects a 6th; roll the oldest into a
   "Still binding, from the rolled-off …" line).

## 2. Repo state

- Worktree `C:/Users/Lentach/Desktop/fireplace-0a`, branch `feat/takeover-alarm-0a` == origin,
  clean, HEAD **`38a076c`**. Main checkout `C:/Users/Lentach/Desktop/Fireplace` on `master`.
- `origin/wip/otp-identity-gate` (`8d61bde`) is SUPERSEDED — never merge it.
- Nothing merged, nothing deployed. T5 spine (new → old):

```
38a076c docs: T5 re-review recorded
a64fd76 fix(T5-6): fold 3-reviewer findings (session-scoped device id, bounded note, deduped diag)
c937d18 docs: T5 app-proof result (self-sync proven live; killed-ack half NOT)
a05afa0 docs: T5 closure (decision record §10, dated summary, LATEST)
b0d193e fix(T5-5): review fold — no reconcile on an unevaluated origin claim
cb7e1fb test(T5-4): wire falsifications 6 and 14
8a15b4f docs: sync root CLAUDE.md
4fbcda0 feat(T5-1,T5-2): self-sync receive + origin-scoped exactly-once reconcile
2b50e9a fix(T5-0): device-list rollback pin covers enrolled->not-enrolled
64fb6cb docs: T5 settlement (spec §12 (xi)-(xix))
8aa8bd0 docs: T5 research
88636f7 T5 handoff (SUPERSEDED by this file) · e56b860 T4 closed · … see §2 of the T5 handoff
```

## 3. What is BUILT (all app- or wire-proven)

- **Phase 0a** takeover alarm; **0b** registration lock §6.1 + 72 h reset §6.2 + recovery key
  §6.2.1; **Phase 1** per-device schema (migration 0015). **OTP identity gate, option A**
  (`573458b`): publish identity → release keys on `keyBundleUploaded success:true`; refusal DROPS
  them; `identityChanged:true` mints a fresh pool. Do NOT restore back-to-back emits.
- **T1** (`584f2d3`): `users.nextDeviceId` allocator (PRE-increment, never decremented, gaps safe);
  `account_authorizations`; `message_envelopes` (UNIQUE `(messageId,recipientUserId,recipientDeviceId)`;
  `messageId` FK **ON DELETE CASCADE** = the SOLE §5.6 destruction mechanism; NO FK on the
  recipient pair).
- **T2** (`6101774`): enrollment sig_IK `"fp-enroll-v1\0"…`, byte-exact `listCanonical`, sig_DAK
  `"fp-list-v1\0"` list + atomic-CAS version law, wire `enrollDeviceAuthority`/`updateDeviceList`/
  `getDeviceList` + `deviceListChanged`; client I7 chain verifier + `DeviceAuthorityEngine`.
- **T3** (`f56347b`+`2ccc76e`+`8dc9d20`+`ca9c6ff`): the §5.1 provisioning ceremony end-to-end —
  in-memory socket-bound stage, deviceId memoized at open, 6 wire events, ONE commit transaction,
  rebind tokens in the `provisioningCompleted` answer, `device_not_active` upload gate, client link
  crypto/DAK store/ceremony controller + 3 screens, en+pl.
- **T4** (`98ad178`…`9c42859`): send fan-out and per-device delivery. `SendMessageDto` takes
  `envelopes:[{userId,deviceId,ciphertext}]` + `senderListVersion` + `recipientListVersion` +
  `sendToken`; a legacy send is normalized at ingest to a device-1 envelope and KEEPS its column;
  four pre-write refusals (`duplicate_envelope_device`, `unknown_envelope_user`,
  `self_envelope_for_origin_device`, `unknown_recipient_device`) plus `deviceListStale` carrying
  both signed lists; every socket joins `user:<uid>` AND `device:<uid>:<did>`;
  `emitToDeviceNewestSocket`; `newMessage` once PER ENVELOPE; per-device push suppression;
  per-device history join with `envelopeStatus` `own_origin`/`none_for_device`; `sendToken` echoed
  ONLY to a row's origin device. **Amendment (x):** the client fans out only from a list it holds,
  and the SERVER refuses a legacy ciphertext send whenever either party is enrolled — I5 lands
  server-side where a client cannot skip it.
- **T5** (the ticket you build on — spec §12 **(xi)–(xx)**):
  - **The own-row law**, in order, for a row with `senderId == me`: `envelopeStatus == 'own_origin'`
    → NEVER decrypt, reconcile by token; `(originDeviceId ?? 1) == ownDeviceId` → same in legacy
    shape; otherwise → **self-sync**, decrypt as ordinary inbound against `(myUserId,
    originDeviceId)`, and never touch the pending-send record. **Deny-decrypt unless foreign origin
    is PROVEN.**
  - **The master gate** is `MessageModel.needsDecryption` (it feeds every decrypt entry point). The
    guards that were flipped: that gate, the history own-message restore branch, both decrypt entry
    points, the terminal-duplicate rule. The guards deliberately NOT flipped, because they are
    account-scoped by nature: **the receipt emit** (device-scoping it is falsification 19 in red),
    the edit-echo reconcile, and edit eligibility.
  - **`ownDeviceId` is SESSION state** (xii)+(xx): it defaults to 1, is only authoritative once
    `socketReady` echoes it, is RESET to unconfirmed on logout/account switch, and a `socketReady`
    with no `deviceId` leaves it unconfirmed. An unconfirmed id decrypts nothing of ours.
  - **Lost-ack** keeps the precedence `encryptedContent ?? sendToken` at every read site (inverting
    it was T4's review BLOCKER), consumes only after a verified read-back, and nulls the key for a
    self-sync row or an origin claim it cannot yet evaluate. `UNIQUE (senderId, sendToken)` was
    deliberately NOT widened with `originDeviceId` — a wider key would PERMIT a duplicate token.
  - **`senderListInfo`** `{ownVersion, ownListHash, peerVersion, peerListHash}` rides inside the E2E
    plaintext on EVERY message, hashed SHA-256 over the byte-exact transported `listCanonical`. A
    bare claim NEVER alarms or changes trust (I7); newer-than-ours buys at most ONE rate-limited
    re-fetch; older-than-ours (or same version, different bytes) is the split-view signal, recorded
    durably but DEDUPED per sender; own-device skew shows a calm inline en+pl note bounded to the
    re-fetch window, never the identity surface.
  - **Device-list trust** (xix): an `authorization: null` answer for a party we already verified as
    enrolled is refused as `version_rollback` and cached nowhere.

**Silent-break invariants (each has bitten):** every index mirrored on its entity (`synchronize`
drops undeclared ones); every entity in module `forFeature` AND `app.module.ts`; `repo.query()`
returns `[rows, rowCount]`; column casing per table (refresh_tokens snake_case, messages mixed, new
tables camelCase-quoted); migrations 0015/0016 not code-reversible; **Dart
`Curve.calculateSignature` AND `curve25519-js.verify` MUTATE their buffers — always pass copies**;
wire = request-event → response-event, NO socket.io acks; `listCanonical` is opaque base64,
byte-exact; uploads are SESSION-bound (payload deviceId ignored); **Signal decrypt is NOT
idempotent — never deliver one ciphertext twice to one device, never reuse one across devices**;
the delivery projection is RECIPIENT-envelopes-only via a column-scoped UPDATE; envelope
`deliveredAt`/`readAt` never feed expiry or the read TTL (I9); **a sender cannot decrypt its own
ciphertext — its optimistic plaintext is the only copy it will ever have.**

## 4. Verification numbers (root CLAUDE.md §3 — reproduce, don't trust)

```bash
cd backend && npm test                                      # 920 tests / 57 suites
cd backend && node ../scripts/lint-ratchet.mjs              # PASS (floor 906, real 903)
cd frontend && cmd /c flutter analyze --no-fatal-infos      # clean
cd frontend && cmd /c flutter test                          # 1486 / 10 skipped
cd frontend && E2E_BASE_URL=http://127.0.0.1:3000 cmd /c flutter test test_e2e   # 41 / 2 skipped
cd backend && node ../scripts/verify-claude-backend-test-counts.mjs
cd frontend && node ../scripts/verify-claude-frontend-test-counts.mjs
#   Run the frontend verifier BARE — `--log` PARSES an existing file instead of running.
#   DELETE test-output.txt before committing.
```

The ratchet floor is still **906** while the real count is **903**. Do not lower it mid-ticket; if
you finish T6 still improved, that is the moment to run `--update` and say so.

**Flake ledger (pre-existing, NOT ours — re-run the FULL suite once, do not chase):**
1. `test/widgets/input/chat_input_bar_attachment_test.dart` "video-then-caption" — ~2 runs in 3.
2. `test/services/unread_badge_sync_test.dart` "falls back to the window Badging API".

⚠️ **CI is not guarding this branch.** Its `push` trigger is `branches: [master]` only, so the
branch depends on the `pull_request` trigger, which has not fired since 08-19 — T3, T4 and T5
pushes all missed it. CodeQL IS green on PR #144. Nothing is red; the automated §7 wire check simply
is not running here. Worth fixing before the phase gate; it is outside a ticket, so **ask before
touching the workflow.**

## 5. Environment traps (all paid for — trust this list)

- Docker stack `fireplace-0a-*`. DB **`chatdb`** on :5433
  (`docker compose exec -T db psql -U postgres -d chatdb -c "…"`). **Check `docker ps` for squatters
  first**; ASK before stopping a stack that is not yours.
- **A bare `docker compose restart` does not fix a stale compose network** (`EAI_AGAIN db`, host port
  binding lost) — `docker compose down && up`. After any restart poll `/health`; **cold boot is
  ~170 s and I have measured 12 polls at 15 s**. Wire suite: restart, wait ≥20 s after `/health`
  flips, run ALONE, full suite only.
- **Always `127.0.0.1:3000`** — `localhost` is broken on this PC (stale wslrelay on `[::1]`).
- `nest --watch` recompiles WITHOUT relaunching — restart is the only trustworthy relaunch.
- **The register throttle is 10/hr/IP and in-memory, so a backend restart clears a spent budget.**
  NEVER add registrations to `test_e2e` (it spends 2; reuse via `E2eClient.adoptAccountFrom`). New
  ceremony-style tests go INSIDE `full_stack_e2e_test.dart`; the main()-scope `engine` holds ALICE's
  DAK private key and nothing else does — **so a ceremony test must link a device of ALICE, not of
  bob** (a T5 test was written the wrong way round first).
- **`_trackedEvents` in `test_e2e/support/e2e_test_client.dart` is a closed list.** A new server
  event makes every assert about it pass VACUOUSLY until you add it. `EventLog.next` has no cursor —
  `discard()` before the triggering emit. Deliberate refusals must be drained (`takeError`).
- Windows: `cmd /c flutter …` (bare = os error 193). Web release:
  `cmd /c flutter build web --release --dart-define=BASE_URL=http://127.0.0.1:3000`, serve
  `frontend/build/web` with `python3 -m http.server <port>` — each port = separate origin = separate
  storage; REBUILD after any lib/ change. Never `hub restart` a stale-named daemon.
- python http.server sends NO Cache-Control → evict with a CDP `Network.setCacheDisabled` reload.
- **Browser recipes (ASK FIRST) — T5 paid for these:**
  - Two `browser` tab NAMES can resolve to the SAME page. **Assert `location.origin` per page**, and
    create the second page with `browser.newPage()`, then select pages by URL.
  - The shared browser daemon refuses to start while a system Chrome is running. Spawn Chrome with
    `app.path` + `--user-data-dir=C:\Users\Lentach\.omp\run\daemons\9fe300f4492cdc1d\omp.browser.headed.profile`
    — **that profile is where the device identities live**, and the stored origins are
    `127.0.0.1:8091` / `:8093`, NOT `localhost`.
  - CanvasKit semantics stay empty until you click `flt-semantics-placeholder` after EVERY reload;
    the release a11y tree LAGS navigation, so **screenshots are ground truth**; aria refs renumber
    every snapshot, so re-snapshot and act in the SAME cell.
  - **The composer is the hard part.** `tab.click` on an aria ref times out; a blind coordinate click
    hits whatever moved there (it hit the Contacts tab once). What worked: click the conversation via
    `flt-semantics` geometry, then click the composer's geometry, then CDP `Input.insertText`. What
    then STOPPED working for a second send: CanvasKit re-creates its text-editing host, so
    `insertText` lands in a stale `<textarea>` the framework ignores. **`page.keyboard.sendCharacter`
    per character DOES reach the framework**; the Send button appears in semantics as `Wyślij` once
    the field has content. Budget for this or add a test-only send hook.
- **Backticks in a `git commit -m` body get shell-expanded and silently delete words.** Write the
  body to a file OUTSIDE the repo and use `git commit -F` (`.git` is a FILE in a worktree, so you
  cannot put the message inside it).
- **CRLF defeats a `$`-anchored codemod** — anchor `\r\?$` or use the edit tool per file.
- The `edit` tool can mis-anchor into a nested block after a file shifts; read the region back and
  repair with a register move (`CUT @name` / `PUT @name`).
- Delay testing in seconds:
  `update identity_reset_requests set "deadlineAt"=now()-interval '1 minute' where "userId"=<id> and status='pending';`
  (cron @EVERY_MINUTE); `set "cancelledAt"=now()-interval '25 hours'` ages the cooldown.
- Logs: `docker compose logs backend --since 5m | grep -iE "send|provision|device-list|identity-"`.

### Live test fixtures (local `chatdb`)

- **193 = `pg5802614#6248` / `Fireplace!2620`** — TWO live devices: 1 primary (IK `BVVFJ/DuqMwR`),
  2 linked (same IK); enrolled, list **v2**. Storage in origins **:8091** (device 1) and **:8093**
  (device 2).
- **297 = `t4peer0821#2955` / `FireplaceT4!2026`** — the peer, storage in origin **:8094**.
  **Conversation 92** joins them and holds **message 649** (the T4 proof: envelopes `(193,1)` and
  `(193,2)`) and **message 698** (the T5 proof: envelopes `(193,2)` self-sync and `(297,1)`, no
  envelope for the origin, `deliveryStatus` still SENT with both stamps NULL).
- 205 = `pr8963550rc489731` / `FireplaceFixed!7`. Login DTO field is `identifier`.

## 6. Governance (NORMATIVE for your ticket)

Amendments (a)–(h), (i)–(iv), (v)–(x), (xi)–(xx) all bind Phase 2. The ones shaping T6:

- **(e) receive-time origin check** — a revoked device's ciphertext must not be accepted just
  because a session exists.
- **(xii)+(xx) device-id discipline** — `ownDeviceId` is session state, only the server confirms it,
  and silence never confirms. A revocation flow that re-binds or re-connects must not break this.
- **§5.5 is your specification** and is quoted in §7 below.
- **I6 SILENCE** is the one §5.5 clause with a KNOWN gap (see §7.1) — it is currently inert only
  because no revocation exists to produce a revoked device.
- **§4 laws that do not bend:** the delivery projection is RECIPIENT envelopes only; envelope stamps
  never feed expiry or the read TTL (I9); ciphertext is per-device addressed, never
  account-broadcast.

## 7. YOUR JOB: T6 — revocation and the reset-roster teardown (spec §5.5)

Read §5.5 completely. It is short and every clause is a requirement:

> Primary-only action (DAK-signed mutation, `revokedAt` set, version+1, one transaction; preempts
> any pending provisioning stage — §5.1): the server stops routing envelopes to the device, deletes
> its refresh tokens + push rows, kicks its sockets; its still-valid access JWT gets SILENCE from
> `getServedMessageIds` (I6) and rejection from mutating handlers until natural expiry; peers drop
> the device from fan-out on the next staleness bounce (worst case one rejected send), and the §5.2
> cross-check exposes any server attempt to keep serving the pre-revocation list; the revoked
> device's local data is NOT remotely wiped (logout semantics, stated in UI); the revoked device's
> OTPs are purged.

### 7.1 What exists and what does not (verified at `38a076c`)

| Piece | State |
|---|---|
| A `revokeDevice` wire handler | **DOES NOT EXIST** — grep is empty. This is the ticket. |
| `revokedAt` column + `liveDeviceIds` filtering it | EXISTS (T1 schema, T4 send path). A revoked entry is already skipped by the fan-out. |
| DAK-signed list mutation + atomic CAS version bump | EXISTS (`device-list.service.ts`, T2) — reuse it, do not write a second one. |
| Provisioning stage preemption | The stage machine is in `chat-provisioning.service.ts` (T3, in-memory, socket-bound). Revocation must preempt a pending stage. |
| **I6 SILENCE** | **MISSING.** `chat-message.service.ts:642` `handleGetServedMessageIds` → `:657` calls `findServedMessageIds(dto.messageIds, userId)` — **per-USER only, no device scoping**, so a revoked device's still-valid JWT would get a truthful answer and destroy nothing it should keep. Inert today only because nothing can be revoked. |
| OTP purge for one device | `key-bundles.service.ts:230` `purgeSupersededDevices(userId, keepDeviceId)` exists but is keyed the wrong way round for this use (it keeps ONE device). §5.5 needs "purge exactly this device". Widen or add a sibling; do not contort the caller at `:159`. |
| Refresh-token deletion per device | `refresh_tokens.device_id` exists (Phase 1). Check `refresh-tokens.service.ts` for a per-device revoke — `revokeAllForUser` is account-wide and too broad. |
| Push rows per device | Push is already multi-endpoint; the per-device linkage landed in T4's suppression work. Verify before assuming. |
| Socket kick | `emitToDeviceNewestSocket`/`deviceRoom()` give you the device's sockets (T4, `user-room.ts`). |
| The never-activated upload rejection | T3 landed it at BOTH key-exchange handlers, but its wire-unreachable half becomes reachable once revocation exists — extend the suite. |

### 7.2 Falsifications owed

- **7** — concurrent send + revoke: a revoked device receives NO envelope for a message committed
  after the revocation, and the send does not fail for the other devices.
- **12** — per-device epoch after a reset: all three re-keyed sites purge/claim/count strictly
  within the device, so a reset roster teardown cannot destroy a surviving device's material.
- The I6 SILENCE assertion (a revoked device's JWT is answered with silence, and a live device's is
  answered truthfully in the same run).
- Anything §5.5 states that you cannot already point at a test for.

### 7.3 Done-gate

Green suites are not "done". App-prove on account 193's two live devices (**ASK before browser**):
revoke device 2 from device 1, then show that device 2 is kicked and cannot upload or send, that
device 1 keeps working with an unbroken session, that a peer's next send addresses device 1 only,
and that device 2's local history is NOT wiped (logout semantics). Wire/DB/logs are ground truth.

## 8. After T6: the remaining DAG

**T7** edit re-fan (§5.7 + falsification 24): the inbound wire becomes
`editMessage { messageId, envelopes:[…] }`, UPSERT **content-only** so `deliveredAt`/`readAt`
**SURVIVE**, a device linked after the original send gets an INSERTED envelope and upgrades its
`none_for_device` placeholder (never the reverse), and an edit never mints or consumes a
`sendToken`. Today the server emits `messageEdited` to the origin socket
(`chat-message.service.ts:1005`) and then to the peer's **`DEFAULT_DEVICE_ID` only** (`:1014`) —
that is the line T7 replaces. → **T8** harness sweep: falsify at RECEIVE time; land any
falsification not covered in its ticket (the T5 review flagged two: a wire proof that a real
self-envelope DECRYPTS, and a widget test that the calm skew note borrows nothing from the identity
surface). Then the **phase gate: THREE independent reviewers**, and the owner decides the merge.
Phases 3–4 per spec §9.

## 9. Research

- `docs/plans/2026-08-21-t5-self-sync-lost-ack-research.md` (self-sync, idempotency, split-view,
  libsignal self-sessions — all from primary source, with the guard inventory in §3).
- `docs/plans/2026-08-20-t4-envelope-fanout-research.md`, and
  `docs/plans/2026-08-19-multi-device-prior-art-research.md`.
- Need more? `librarian` subagents against PRIMARY sources, one topic each, compiled into a dated
  `docs/plans/YYYY-MM-DD-<topic>-research.md`. `scout` for read-only codebase mapping — **scouts
  have NO write tool**, so have them return findings inline and persist them yourself. For T6 the
  obvious topics are Signal's/Sesame's device-removal semantics, Matrix's device deletion + `left`
  lists, and what other systems do with a still-valid credential after revocation.

## 10. Working rhythm (proven over T1→T5; follow it)

1. One ticket at a time. Settle any spec ambiguity BEFORE code as a dated §12 amendment. T4 and T5
   both proved this pays: T4's settlement caught a data-loss issue on paper, and T5's research
   found the ticket's own brief was wrong about what was left to build.
2. **Research before code when the subject is unfamiliar** — the owner asks for this explicitly.
   One batch, primary sources, compiled into a dated plan file.
3. Dispatch ONE fresh writer per tier with a SELF-CONTAINED brief (it inherits nothing), SEQUENTIAL
   stages, and a commit after each green stage. **⚠️ Writer subagents may be unavailable:** T5's
   writer died instantly to an account-level 429 with a multi-day retry-after, so the orchestrator
   implemented the whole ticket. Plan for that: it works, it is just slower, and every claim ends up
   first-hand. `reviewer` and `librarian` agents were unaffected.
4. **`hub jobs` status is NOT liveness.** A writer went silent mid-stage while the broker still said
   RUNNING; compare working-file mtimes against the clock (23 min of zero writes = corpse). Stand it
   down, verify with FULL suites, finish it yourself. Recovered work is never trusted on its word.
5. You (orchestrator) verify EVERY claim: full suites, counts, verifiers. `completed` ≠ accepted.
6. Fresh `reviewer` per ticket close, defensive framing, hand it the delta commits + ground truth +
   axes. Fold BLOCKER/FIX before push. **Re-review after a fold if the fold was non-trivial** — T5's
   second review found a P1 in already-reviewed code.
7. App-prove user-visible changes (ASK before browser). Wire/DB/logs are ground truth; screenshots
   beat the lagging a11y tree. **Record what you could NOT prove** — do not let a suite stand in for
   a claim about the real app.
8. Push code + closure docs together; update the decision record (closure §), `LATEST.md` (5-entry
   cap), the dated session summary, and all THREE planning files.

## 11. Standing blockers (owner-side, do not chase)

`FIREBASE_SERVICE_ACCOUNT` absent on the VM (FCM dead in prod); `.jks` off-PC backup owed;
owner-iPhone confirmation for the 0.1.16/0.1.17 attachment popover. Accepted-not-fixed P3s: reset
banner lacks `Semantics(liveRegion:true)`; offline recovery-key save shows a generic failure toast
after ~6 s; I2 UI gating (web must not become primary in prod) is Phase 3; `SendMessageDto.envelopes`
has no `@ArrayMaxSize`; the wire suite proves self-envelope ROUTING but not decryptability; the calm
skew note has no widget test. **CI's `pull_request` trigger has not fired on this branch since
08-19 (see §4) — ask before touching the workflow.**

## First five actions

1. Read order §0 (this file → CLAUDE.mds → spec §5.5 + §5.1/§5.2/§5.4 + §12 (a)–(xx) → decision
   record §4 T6 rider + §10 T5 closure).
2. `docker ps` (squatters?) → stack up → poll `/health` patiently → reproduce
   **920/57 · 903 · clean · 1486/10sk · 41/2sk** (restart backend before the wire run; ≥20 s settle;
   alone). Confirm branch == origin at `38a076c`, worktree clean.
3. Walk §7.1 yourself and re-verify every line number in it before trusting it. Write down what
   each existing piece already guarantees, because §5.5 is mostly composition of things that exist.
4. Settle T6's ambiguities as a dated §12 amendment BEFORE code — candidates: whether SILENCE is
   scoped by device id from the JWT or by an explicit revoked-device check; what a revoked device's
   own UI does when its socket is kicked (logout semantics vs a banner); whether the OTP purge is a
   widened `purgeSupersededDevices` or a sibling; how a revocation interacts with a pending
   provisioning stage on the SAME device id.
5. Dispatch (or implement) sequential stages with a commit per green stage; verify; fresh reviewer;
   fold; re-review if the fold was non-trivial; app-prove on 193's two devices (**ASK first**);
   push; books (decision record §11 = T6 closure, LATEST 5-cap, dated summary, all three planning
   files).
