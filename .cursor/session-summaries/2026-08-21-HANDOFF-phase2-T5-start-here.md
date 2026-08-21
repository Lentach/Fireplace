> ## ⛔ SUPERSEDED 2026-08-21 (B) — read `2026-08-21-HANDOFF-phase2-T6-start-here.md` instead
>
> **T5 IS DONE** (built, reviewed twice, wire-proven, self-sync app-proven on two real devices;
> spec §12 gained amendments (xi)–(xx)). This file's account of T1–T4 and its owner rules and
> traps remain accurate and are restated in the T6 handoff — but its **numbers, its brief and its
> line numbers are STALE**, and two of its claims were proven WRONG by T5's research:
>
> 1. It says the send half of self-sync is still to build. **It was already shipped in T4** — T5
>    turned out to be a receive-side ticket.
> 2. Its "five own-sender guards" table is **INCOMPLETE**. The decisive gate,
>    `MessageModel.needsDecryption`, is missing from it, and two guards it does not mention must
>    NEVER be flipped (the receipt emit — falsification 19 — and the edit-echo reconcile).
>
> Keep it for its T1–T4 mechanism detail. Do not follow its instructions.

# HANDOFF 2026-08-21 — Multi-device program: T1–T4 done, T5 (self-sync + lost-ack) is your job

**You are a fresh agent picking up a multi-session program mid-flight. This file is the
authoritative, self-contained entry point.** It SUPERSEDES
`2026-08-20-HANDOFF-phase2-T4-start-here.md` (T4 is DONE; that file's owner rules and traps
remain true and are restated here, plus everything T4's execution paid for).

⚠️ **Read §7 before you touch `messaging_provider.decrypt.dart`.** T4's one review BLOCKER lived
in exactly the code path T5 has to modify, and it was a silent data-loss bug. That path guards
the ONLY plaintext copy of a sent message.

---

## 0. Read order (do this before anything else)

1. This file, fully.
2. Root `CLAUDE.md` (workflow, §3 verification counts, §6 migrations, §7 wire contracts — **§7
   now has a full T4 envelope/fan-out bullet**) and `backend/CLAUDE.md` +
   **`frontend/CLAUDE.md` (§5 lost-ack insurance is REQUIRED for this ticket)** before your
   first change in a tier.
3. The FROZEN spec `docs/design/multi-device.md` — **§5.4 (YOUR ticket)**, §5.2, §5.3, §4, §7,
   §10, and **§12's dated amendment blocks at the end**: three of 2026-08-19 (allocator,
   cooldown carve-out, Stage-0 (a)–(h)), one of 2026-08-20 for T3 (items (i)–(iv)), and the
   **T4 block, items (v)–(x)** — (vii) and (ix) are directly binding on you. All NORMATIVE.
4. `docs/plans/2026-08-19-phase2-stage0-decision-record.md` — finding-to-ticket map; §4 riders
   (T5's row is your requirements); §6/§7/§8/**§9** are the T1/T2/T3/T4 closures.
5. `docs/plans/2026-08-20-t4-envelope-fanout-research.md` — the prior art behind the envelope
   design (Signal-Server, Sesame, libsignal, Matrix). Read §2 if you need to justify a shape.
6. `docs/plans/2026-08-19-multi-device-prior-art-research.md` — older synthesis (~250 lines).
7. Planning files: `C:/Users/Lentach/Desktop/Fireplace/.planning/multi-device/`
   (`task_plan.md`, `findings.md`, `progress.md`) — MAIN checkout, gitignored, the
   cross-session memory. MAINTAIN THEM. Do NOT mint planning files at the worktree root.
8. Subagents inherit NOTHING. Every task brief must name these files explicitly.

## 1. Owner rules (binding; each was earned by an incident)

1. **Investigate and PROVE, then ASK before writing code** — diagnostics count as code
   (`4beb1bd` landed on a symptom, reverted). Ticket work inside the approved T1–T8 DAG is
   pre-authorized; anything OUTSIDE a ticket needs an ask.
2. **Ask before opening the browser tool — every time.** Authorization is per-session and
   EXPIRES. The 2026-08-21 session was granted it for the T4 app-proof; **that grant died with
   that session.** You start under the standing ask-first rule.
3. **Never merge, never deploy.** One branch, one merge at program end. PR #144 = review
   surface only. `gh run list` after pushing; never merge on red.
4. **Never self-review.** Fresh `reviewer` subagent per ticket close; THREE independent
   reviewers at phase gates. Defensive framing ("verify our protections hold") — adversarial
   wording gets content-filtered. **The T4 reviewer earned its keep: GATE FAIL on a P0 the
   author had missed.** Do not skip it and do not argue it down.
5. Writer subagents ≤2 concurrent; read-only reviewers ×3 fine; Anthropic-only.
6. Never `dart format lib/` or prettier globs — format ONLY the exact files you touched.
7. **Never give `flutter test` a file list** (45 files once timed out past 11 min; full suite
   is 170–310 s). Includes `test_e2e` — full suite only.
8. Owner is non-native English; explain mechanics plainly; delays are testable in seconds via
   SQL timestamp updates (never wait out a 24 h/72 h window).
9. Session end: dated `.cursor/session-summaries/YYYY-MM-DD-session-*.md` + `LATEST.md` update
   (**caps at 5 dated entries** — a pre-commit hook rejects a 6th; roll the oldest into a
   "Still binding, from the rolled-off …" line).

## 2. Repo state

- Worktree `C:/Users/Lentach/Desktop/fireplace-0a`, branch `feat/takeover-alarm-0a` == origin,
  clean, HEAD `e56b860`. Main checkout `C:/Users/Lentach/Desktop/Fireplace` on `master`.
- `origin/wip/otp-identity-gate` (`8d61bde`) is SUPERSEDED — never merge it.
- Nothing merged, nothing deployed. T4 spine (new → old):

```
e56b860 docs: T4 closed (decision record §9 + books)
9c42859 fix: T4 review fold — reconcile precedence BLOCKER + 2 P3
8c8b12c test: T4 wire falsifications (amendment (x), 5, per-device delivery, 13)
b28d268 C5 client — decrypt against the ORIGIN device's session
1885038 C4 client — envelopeStatus rendering, placeholder, en+pl l10n
abae48c C3 client — fan-out send, sendToken, stale-list repair (+ amendment (x))
1461e9d C2 client — verified device-list cache
c5ddeed C1 client — per-device Signal addressing
80b6035 B3 backend — per-device history reads, envelopeStatus, scoped projection
bbcfe8b B2 backend — device rooms, per-device delivery/push, preKeysLow, limiter fix
98ad178 B1 backend — envelope ingest, atomic fan-out write, deviceListStale
31ce335 docs: T4 research + settlement (spec §12 (v)-(ix))
fb926a5 docs: T4 handoff (SUPERSEDED by this file) · 82cb06e T3 closed · … see §8 of the T4 handoff
```

## 3. What is BUILT (all app- or wire-proven)

- **Phase 0a** takeover alarm; **0b** registration lock §6.1 + 72 h reset §6.2 + recovery key
  §6.2.1; **Phase 1** per-device schema (migration 0015). **OTP identity gate, option A**
  (`573458b`): publish identity → release keys on `keyBundleUploaded success:true`; refusal
  DROPS them; `identityChanged:true` mints a fresh pool. Do NOT restore back-to-back emits.
- **T1** (`584f2d3`): `users.nextDeviceId` allocator (PRE-increment, never decremented, gaps
  safe); `account_authorizations`; `message_envelopes` (UNIQUE
  `(messageId,recipientUserId,recipientDeviceId)`; `messageId` FK **ON DELETE CASCADE** = the
  SOLE §5.6 destruction mechanism; NO FK on the recipient pair).
- **T2** (`6101774`): enrollment sig_IK `"fp-enroll-v1\0"…`, byte-exact `listCanonical`,
  sig_DAK `"fp-list-v1\0"` list + atomic-CAS version law, wire
  `enrollDeviceAuthority`/`updateDeviceList`/`getDeviceList` + `deviceListChanged`; client I7
  chain verifier + `DeviceAuthorityEngine`; falsification 25 both directions.
- **T3** (`f56347b`+`2ccc76e`+`8dc9d20`+`ca9c6ff`): the §5.1 provisioning ceremony end-to-end —
  in-memory socket-bound stage, deviceId memoized at open, 6 wire events, ONE commit
  transaction, rebind tokens in the `provisioningCompleted` answer, `device_not_active` upload
  gate, client link crypto/DAK store/ceremony controller + 3 screens, en+pl.
- **T4** (this ticket's predecessor — the surface you build on):
  - **Ingest.** `SendMessageDto` accepts `envelopes:[{userId,deviceId,ciphertext}]` +
    `senderListVersion` + `recipientListVersion` + `sendToken`. A legacy `encryptedContent`
    send is normalized AT INGEST to a one-element device-1 envelope **and keeps its column**
    (so legacy rows stay readable all through the §8 rollout); a NEW-MODEL row leaves
    `encryptedContent` NULL. Message row + N envelopes in ONE transaction.
  - **Refusals, all before any write** (zero rows): `duplicate_envelope_device`,
    `unknown_envelope_user`, `self_envelope_for_origin_device`, `unknown_recipient_device`
    (device 1 exempt) on the send path's bare `error` channel; and `deviceListStale
    {success:false, error:'device_list_stale', tempId?, lists:[{userId, version, listCanonical,
    listSignature, enrollment:{dakPub, enrollmentSig, enrollmentCreatedAt}}]}` as its own event.
  - **Rooms.** Every socket joins `user:<uid>` AND `device:<uid>:<did>`. `emitToNewestTab` is
    now `emitToDeviceNewestSocket` (newest socket WITHIN one device). `newMessage` is emitted
    once PER ENVELOPE with that device's own ciphertext. A ciphertext-less send (PING) keeps
    single-target delivery to device 1. Push suppression is per device and skips only when
    EVERY delivered recipient device is focused. `preKeysLow` → device room.
  - **History.** `getMessages` joins envelopes on the requesting `(userId, deviceId)` from the
    JWT; fallback = own envelope → legacy column gated to the row's session owner
    (`deviceId == (originDeviceId ?? 1)` own rows, device 1 received rows) → additive
    `envelopeStatus` `"none_for_device"` | `"own_origin"` with a NULL ciphertext.
  - **`sendToken` is echoed ONLY to a row's origin device** — never to a recipient. The
    `messageSent` ack is a SEPARATE payload from the fan-out base for exactly that reason.
  - **Client.** Per-device Signal addressing in BOTH directions (`_sessionTails` and the
    cross-context lock keyed `(userId, deviceId)`); `DeviceListCache` (I7-verified, rollback pin
    survives invalidation, fail-closed, `authorization:null` = not enrolled = device 1 only);
    fan-out send with one DISTINCT ciphertext per address; `sendToken` minted per tempId and
    reused by retries; `deviceListStale` repair (verify chain → adopt → resolve absent parties →
    resend, cap 3); `envelopeStatus` rendering with an honest placeholder in en+pl;
    `socketReady` echoes `deviceId` so the client knows which device it is.
  - **Amendment (x), read it:** the client fans out ONLY from a list it already holds; the
    SERVER refuses a legacy ciphertext send whenever either party is enrolled. **I5 (never
    silently drop a device) is enforced server-side where a client cannot skip it.**

**Silent-break invariants (each has bitten):** every index mirrored on its entity
(`synchronize` drops undeclared ones); every entity in module `forFeature` AND `app.module.ts`;
`repo.query()` returns `[rows, rowCount]`; column casing per table (refresh_tokens snake_case,
messages mixed, new tables camelCase-quoted); migrations 0015/0016 not code-reversible; **Dart
`Curve.calculateSignature` AND `curve25519-js.verify` MUTATE their buffers — always pass
copies**; wire = request-event → response-event, NO socket.io acks; `listCanonical` is opaque
base64, byte-exact; uploads are SESSION-bound (payload deviceId ignored); **Signal decrypt is
NOT idempotent — never deliver one ciphertext twice to one device, never reuse a ciphertext
across devices**; the delivery projection is RECIPIENT-envelopes-only and written as a
column-scoped UPDATE; envelope `deliveredAt`/`readAt` never feed expiry or the read TTL (I9).

## 4. Verification numbers (root CLAUDE.md §3 — reproduce, don't trust)

```bash
cd backend && npm test                                      # 920 tests / 57 suites
cd backend && node ../scripts/lint-ratchet.mjs              # PASS (baseline 906, now 903)
cd frontend && cmd /c flutter analyze --no-fatal-infos      # clean
cd frontend && cmd /c flutter test                          # 1451 / 10 skipped
cd frontend && E2E_BASE_URL=http://127.0.0.1:3000 cmd /c flutter test test_e2e   # 39 / 2 skipped
cd backend && node ../scripts/verify-claude-backend-test-counts.mjs
cd frontend && node ../scripts/verify-claude-frontend-test-counts.mjs
#   Run the frontend verifier BARE — `--log` PARSES an existing file instead of running.
#   DELETE test-output.txt before committing.
```

The ratchet floor is deliberately still **906** while the real count is **903**. Do not lower it
mid-ticket; if you finish T5 still improved, that is the moment to run `--update` and say so.

**Flake ledger (pre-existing, NOT ours — re-run the FULL suite once, do not chase):**
1. `test/widgets/input/chat_input_bar_attachment_test.dart` "video-then-caption" — ~2/3.
2. `test/services/unread_badge_sync_test.dart` "falls back to the window Badging API".

⚠️ **CI is not currently guarding this branch.** Its `push` trigger is `branches: [master]`
only, so the branch depends on the `pull_request` trigger, which has not fired since 08-19 —
T3's and T4's pushes both missed it. CodeQL IS green on PR #144. Nothing is red; the automated
§7 wire check simply is not running here. Worth fixing before the phase gate; it is outside a
ticket, so **ask before touching the workflow**.

## 5. Environment traps (all paid for — trust this list)

- Docker stack `fireplace-0a-*` (worktree compose). DB **`chatdb`** on :5433
  (`docker compose exec -T db psql -U postgres -d chatdb -c "…"`). **Check `docker ps` for
  squatters first.** A foreign `fpcomposer-*` stack held :3000/:5433 on 08-21 — **ASK before
  stopping a stack that is not yours** (the owner cleared that one).
- **A bare `docker compose restart` does not fix a stale compose network.** After the foreign
  stack was stopped, the backend booted with `getaddrinfo EAI_AGAIN db` and **lost its host
  port binding** (`3000/tcp`, unpublished). `docker compose down && docker compose up -d`
  recreates the network; then poll `/health` patiently — cold boot is 170–240 s.
- **Always `127.0.0.1:3000`** — `localhost` is broken on this PC (stale wslrelay on `[::1]`).
- `nest --watch` recompiles WITHOUT relaunching — restart is the only trustworthy relaunch.
- **Wire suite discipline:** restart backend first, wait ≥20 s after `/health` flips, run
  ALONE, full suite only. **The register throttle is 10/hr/IP and in-memory, so a backend
  restart clears a spent budget** — handy when a browser proof needs a fresh account after the
  wire suite has run. NEVER add registrations to the suite (it spends 2; reuse via
  `E2eClient.adoptAccountFrom`). New ceremony-style tests go INSIDE `full_stack_e2e_test.dart`;
  the shared main()-scope `engine` holds the DAK private key and nothing else does.
- **`_trackedEvents` in `test_e2e/support/e2e_test_client.dart` is a closed list.** EventLog
  records nothing not listed there, so a new server event makes every assert about it pass
  VACUOUSLY until you add it. `EventLog.next` has no cursor — `discard()` before the triggering
  emit. Deliberate refusals must be drained (`takeError`) or the final "no unexpected socket
  errors" guard fails the run.
- Windows: `cmd /c flutter …` (bare = os error 193). Web release:
  `cmd /c flutter build web --release --dart-define=BASE_URL=http://127.0.0.1:3000`, serve
  `frontend/build/web` with `python3 -m http.server <port>` — each port = separate origin =
  separate storage; REBUILD after any lib/ change. Never `hub restart` a stale-named daemon (it
  reuses the RETAINED launch spec and serves an old cwd) — fresh name + explicit cwd.
- python http.server sends NO Cache-Control → Chrome serves week-old JS; evict with a CDP
  `Network.setCacheDisabled` reload.
- **Browser recipes (ASK FIRST):** CanvasKit semantics stay empty until you click
  `flt-semantics-placeholder` after EVERY reload; **the release a11y tree LAGS navigation by
  minutes — screenshots are ground truth**; take a FRESH ariaSnapshot and click its ref in the
  SAME cell (refs renumber every snapshot); text fields focus via a textbox-ref click then CDP
  `Input.insertText`; snackbars live ~0.6–2.5 s so backend logs are ground truth for refusals.
- **Backticks in a `git commit -m` body get shell-expanded and silently delete words.** Write
  the body to a file and use `git commit -F`.
- **CRLF defeats a `$`-anchored codemod** — a `sed` line-end anchor never fires after `\r`
  (silently matched nothing across 7 files). Anchor `\r\?$` or use the edit tool per file.
- Delay testing in seconds:
  `update identity_reset_requests set "deadlineAt"=now()-interval '1 minute' where "userId"=<id> and status='pending';`
  (cron @EVERY_MINUTE); `set "cancelledAt"=now()-interval '25 hours'` ages the cooldown.
- Logs: `docker compose logs backend --since 5m | grep -iE "send|provision|device-list|identity-"`.

### Live test fixtures (local `chatdb`)

- **193 = `pg5802614#6248` / `Fireplace!2620`** — TWO live devices: 1 primary (IK
  `BVVFJ/DuqMwR`, regId 10558), 2 linked (same IK, regId 13585); enrolled, list **v2**,
  `nextDeviceId`=4. Storage lives in origins **:8091** (device 1) and **:8093** (device 2).
- **297 = `t4peer0821#2955` / `FireplaceT4!2026`** — the T4 app-proof peer, fresh identity,
  storage in origin **:8094**. **Conversation 92** joins 297 and 193 and holds message 649,
  whose two envelopes `(193,1)`/`(193,2)` are the T4 proof.
- 205 = `pr8963550rc489731` / `FireplaceFixed!7`. Login DTO field is `identifier`.
- `hub` daemons `t4web8091`/`t4web8093` may still be serving `frontend/build/web`; `t4web8094`
  was stopped. Restart under FRESH names with explicit cwd, and REBUILD first.

## 6. Governance (NORMATIVE for your ticket)

Amendments (a)–(h) (2026-08-19), (i)–(iv) (T3), **(v)–(x) (T4)** all bind Phase 2. The ones
shaping T5:

- **(vii) `senderListInfo` was DEFERRED TO YOU.** The §5.2 layer-2 E2E cross-check field lives
  in E2E plaintext inside the ciphertext; the server never sees, stores or validates it. It is
  a pure client concern, and its falsifications (**16** split-view, **22** false-alarm
  discipline) are recipient-side escalation tests. `E2eEnvelope.parse`
  (`frontend/lib/utils/e2e_envelope.dart`) ignores unknown keys, so adding the field is
  backward-compatible (the `linkPreview` precedent, root `CLAUDE.md` §7).
- **(ix) Lost-ack continuity is HALF-LANDED and the other half is yours.** T4 landed the key:
  the client mints `sendToken` per send, the server echoes it to the row's ORIGIN device, and
  the reconcile keys on it. What T4 did NOT land is §5.4's full matching law —
  `(senderId, originDeviceId, sendToken)` resolving to EXACTLY ONE row, with an ambiguous match
  as a no-op that never consumes the record. Today the match is by record key alone.
- **§4/§5.3 laws you must not break:** the delivery projection is RECIPIENT envelopes only
  (`recipientUserId != senderId`) — a sender's own second device reading its copy must never
  produce a receipt (falsification 19); envelope stamps never feed expiry or the read TTL (I9);
  ciphertext is per-device addressed, never account-broadcast.
- **T5 riders (decision record §4):** preserve **`tempId != null`** in the `history.dart` guard
  flip — dropping it lets a self-sync row consume a pending-send record (durability F6,
  falsification 6); keep **re-ack WITHOUT re-fan** when the retry path goes envelope-shaped
  (durability F7, falsification 14).

## 7. YOUR JOB: T5 — self-sync, lost-ack, `senderListInfo` (spec §5.4 + §5.2 layer 2)

Read §5.4 completely (it is titled "the danger zone" for a reason) plus §5.2's layer-2 bullets.

### 7.1 The five own-sender guards (the core of the ticket)

Own-sent messages arrive on your OTHER devices as envelopes with `senderId == me` and
`originDeviceId != myDeviceId`, and must decrypt like any inbound message (a pairwise session
between your own devices). Every guard that currently means "mine, skip it" must become "MY
DEVICE's, skip it". **Fixing only some of them leaves self-sync dead — that is a red
falsification-6 run.** Current line numbers (verified at `e56b860`):

| File | Line | Guard |
|---|---|---|
| `messaging_provider.decrypt.dart` | **668** | history own-message branch (spec's `decrypt.dart:642`) |
| `messaging_provider.decrypt.dart` | **1002** | live-path queue guard (spec's `:962-963`) |
| `messaging_provider.decrypt.dart` | **1014** | decrypt guard (spec's `:975`) |
| `messaging_provider.decrypt.dart` | **1339** | terminal-duplicate guard (spec's `:1290`) |
| `messaging_provider.history.dart` | **536** | own-message branch, `&& msg.tempId != null` |

`MessageModel.originDeviceId` already exists and is populated (T4/C5), and
`EncryptionProvider.ownDeviceId` already knows which device you are (set from `socketReady`).
So the data you need is in place — this is a predicate change plus its consequences.

### 7.2 Lost-ack, finished properly

T4 left the reconcile matching by record key. Touchpoints, verified at `e56b860`:

- `messaging_provider.send.dart:1151` `_sendTokenFor` (mint, reused by retries),
  `:1367` where the record is saved (`fanOut ? sendToken : legacyCiphertext`).
- `messaging_provider.decrypt.dart:731` `recordKey = msg.encryptedContent ?? msg.sendToken`,
  peek at `:737`, consume at `:789`.
- `messaging_provider.history.dart:593` the success-path consume.

⚠️ **This precedence is load-bearing and was T4's review BLOCKER.** A legacy row carries BOTH a
ciphertext and an echoed token, and its record is saved under the CIPHERTEXT; preferring the
token stranded the only plaintext copy on every lost ack. The regression test is
`messaging_provider_lost_ack_test.dart` "a legacy row that also echoes sendToken still
reconciles" — **do not weaken it.** When you add `(senderId, originDeviceId, sendToken)`
matching, keep exact-ciphertext as the legacy fallback and keep an ambiguous match a NO-OP that
never consumes the record.

Also from §5.4: **a self-sync row must NEVER consume a pending-send record** (origin-device
scoping); the `messageSent` ack goes only to the origin device while other own devices get
envelopes; an EDIT never mints or consumes a `sendToken`; own-device sessions run through the
same `_sessionTails` serialization keyed `(peerId, deviceId)` (already true after C1).

### 7.3 `senderListInfo` (deferred here by amendment (vii))

Add `senderListInfo: {ownVersion, ownListHash, peerVersion, peerListHash}` to the E2E plaintext
envelope at encrypt time, and implement §5.2's escalation discipline on receive: a sender's view
OLDER than the recipient's own list is a candidate freeze signal that renders ONLY after the
recipient independently confirms it against DAK-signed data; a claim NEWER than the recipient
knows triggers at most ONE rate-limited re-fetch and is then DISCARDED; own-device skew renders a
benign "syncing devices…" state, never the identity-changed surface. **A bare peer claim NEVER
alarms (I7).** The client already has `DeviceListCache` + the I7 verifier to confirm against.

### 7.4 Falsifications owed

**6** (every guard flipped; a self-sync row decrypts AND does not consume a pending-send
record — red if any single guard is missed), **14** (lost-ack by token, read-back verified;
duplicate token rejected server-side; an artificially ambiguous match is a no-op),
**16** (split-view: a frozen validly-signed old list is exposed by the first message via
`senderListInfo`; the recipient re-fetches, independently confirms, alarms — red without the
cross-check), **22** (false-alarm discipline: bogus older AND newer claims produce at most one
rate-limited re-fetch and NO alarm; own-device skew shows "syncing").

### 7.5 Done-gate

**T5 is NOT done at green suites.** App-prove on account 193's two live devices (**ASK before
browser**): send from device 1 and watch device 2 decrypt the self-sync copy and render it as
the same message (not a duplicate, not `[Decryption failed]`); kill the ack and prove the
lost-ack path still recovers the plaintext; confirm no delivery/read receipt is produced by the
sender's own device reading its copy (falsification 19). Wire/DB/logs are ground truth.

## 8. After T5: the remaining DAG

**T6** revocation + stale bounce + reset-roster teardown (amendment (e) receive-time origin
check; `purgeSupersededDevices` widening; I6 SILENCE still missing in `handleGetServedMessageIds`
at `chat.gateway.ts`; the wire-unreachable half of never-activated rejection becomes reachable
here — extend the suite) → **T7** edit re-fan (§5.7 UPSERT content-only, `deliveredAt`/`readAt`
stamps SURVIVE, a device linked after the original send gets an INSERTED envelope and upgrades
its placeholder; note T4 currently sends `messageEdited` to the peer's device 1 only, pending
this ticket) → **T8** harness sweep (falsify at RECEIVE time; any falsification not landed in
its ticket). Then the **phase gate: THREE independent reviewers**, and the owner decides the
merge. Phases 3–4 per spec §9.

## 9. Research

- `docs/plans/2026-08-20-t4-envelope-fanout-research.md` (fan-out/marker prior art, cited) and
  `docs/plans/2026-08-19-multi-device-prior-art-research.md` (program-wide synthesis + four
  cited appendices).
- Need more? `librarian` subagents against PRIMARY sources, one topic each, compiled into a
  dated `docs/plans/YYYY-MM-DD-<topic>-research.md`. `scout` for read-only codebase mapping —
  **scouts have NO write tool**, so have them return findings inline and persist them yourself.

## 10. Working rhythm (proven over T1→T4; follow it)

1. One ticket at a time. Settle any spec ambiguity BEFORE code via a dated §12 amendment.
   T4 proved this twice: the pre-code settlement caught a data-loss issue on paper (item (ix)),
   and item (x) had to be added mid-build when the design met the test suite.
2. Dispatch ONE fresh writer per tier with a SELF-CONTAINED brief (it inherits nothing).
   **Instruct SEQUENTIAL stages with a commit after each green stage.**
3. **Rate-limit / stall recovery — three writers died during T4.** Two hit the same 429; a
   third went silent mid-stage while `hub jobs` still reported it RUNNING. **`hub jobs` status
   is NOT liveness.** The reliable test: compare the working files' mtimes against the clock
   (23 minutes of zero writes with no commit = corpse). Stand it down explicitly, `git status`,
   verify what is real with FULL suites, then finish or land it yourself. Recovered work is
   never trusted on the writer's word.
4. You (orchestrator) verify EVERY claim: full suites, counts, verifiers. `completed` ≠ accepted.
5. Fresh `reviewer` per ticket close, defensive framing, hand it the delta commit ids + ground
   truth + review axes. BLOCKER/FIX → fold before push. A P3 may be folded rather than ridden.
6. App-prove user-visible changes (ASK before browser). Wire/DB/logs are ground truth;
   screenshots beat the lagging a11y tree.
7. Push code + closure docs together; update the decision record (closure §), LATEST.md
   (5-entry cap), the dated session summary, and all THREE planning files.

## 11. Standing blockers (owner-side, do not chase)

`FIREBASE_SERVICE_ACCOUNT` absent on the VM (FCM dead in prod); `.jks` off-PC backup owed;
owner-iPhone confirmation for the 0.1.16/0.1.17 attachment popover. Accepted-not-fixed P3s:
reset banner lacks `Semantics(liveRegion:true)`; offline recovery-key save shows a generic
failure toast after ~6 s; I2 UI gating (web must not become primary in prod) is Phase 3. **New:
CI's `pull_request` trigger has not fired on this branch since 08-19 (see §4) — ask before
touching the workflow.**

## First five actions

1. Read order §0 (this file → CLAUDE.mds incl. **`frontend/CLAUDE.md` §5** → spec §5.4 + §5.2
   layer 2 + §12 (v)–(x) → decision record §4 T5 riders + §9 T4 closure).
2. `docker ps` (squatters?) → stack up → poll `/health` patiently → reproduce
   **920/57 · 903 · clean · 1451/10sk · 39/2sk** (restart backend before the wire run; ≥20 s
   settle; alone). Confirm branch == origin at `e56b860`, worktree clean.
3. Read the five guards at the exact lines in §7.1 and write down, before changing anything,
   what each one protects. One of them (`history.dart:536`) must keep its `tempId != null`.
4. Settle any T5 ambiguity as a dated §12 amendment BEFORE code — candidates: the exact
   `senderListInfo` field shape and hash function; whether the ambiguous-match no-op is
   detectable in the client's own store; how "syncing devices…" is surfaced in the UI.
5. Dispatch the writer(s) (sequential stages, commit-per-green-stage); verify; fresh reviewer;
   fold; app-prove on 193's two devices (**ASK first**); push; books (decision record §10 =
   T5 closure, LATEST 5-cap, dated summary, all three planning files).
