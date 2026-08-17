# HANDOFF — Multi-device execution: start at Phase 0a

**Written 2026-08-17 by the design session. You are the implementing agent for the multi-device
program. The design is DONE and FROZEN; your job is execution, phase by phase, starting with 0a.**

## 0. Mandatory reading order (before ANY change)

1. Root `CLAUDE.md` (workflow, deploy safety, §7 wire contracts) + `.cursor/session-summaries/LATEST.md`.
2. Tier file for whatever you touch first: `backend/CLAUDE.md` (0a starts here), `frontend/CLAUDE.md`
   (§5 above all — the E2E invariants; violating them has destroyed user data before).
3. **`docs/design/multi-device.md` — v5, FROZEN. This is the spec.** Threat model, invariants I1–I9,
   key model (IK/DAK), protocols, wire deltas, §9 phase plan, §10's 24 falsification tests,
   §12 review record. Do not re-litigate frozen decisions; deviations require owner OK.
4. This handoff (the HOW + traps the spec doesn't carry).
5. `.cursor/session-summaries/2026-08-17-session-multidevice-research.md` (research provenance).
   NOTE: `.planning/multi-device/` is **gitignored** — on a fresh clone it may not exist; everything
   load-bearing from it is replicated here and in the dated summary.

## 1. Owner rulings — all binding, all dated 2026-08-17

- Multi-device: GO. Architecture: shared identity (IK) + **primary-only DAK-signed device list**;
  possession-only linking; cap 3; 72 h reset; disappear-at-one-deadline; iOS-PWA never primary.
- **Identity-changed timeline row: YES — explicitly supersedes the 2026-08-15 banner-removal
  ruling** for this narrower event-driven row. (History: `PeerIdentityChangedBanner` was deleted by
  owner ruling with pushback recorded; do NOT resurrect the banner — the ratified thing is a
  one-time in-conversation system row.)
- Recovery key: YES, in 0b, spec §6.2.1 exactly (Argon2id, single-use, 1 h still-loud window).
- **Owner process rules (learned the hard way, in LATEST):** investigate and PROVE, then ASK before
  writing code — diagnostics/instrumentation COUNT as code; never merge to master or deploy without
  explicit owner OK; subagents on Anthropic models only; ask before opening the browser tool.
- Phase discipline: 0a → 0b → 1 → 2 → 3 → (4). Each phase independently shippable, reviewed,
  behind the previous. **Phase 2 requires its own spec-level review round before implementation**
  (doc §12 "Next gate"). Doc-level review is CLOSED — further findings go to phase gates.

## 2. Phase 0a — your first deliverable (days, standalone value, no protocol change)

**Goal:** the takeover alarm. Today `upsertKeyBundle` accepts ANY bundle replacement with a valid
JWT (`backend/src/key-bundles/key-bundles.service.ts:41-58`) and only LOGS identity churn
(`[identity-churn]`, `:46-53`). Promote that branch to:

1. **Durable server-side audit row** (new table via numbered migration — check the current highest
   in `backend/migrations/` first; it was `0012_video_message_type` as of 08-16, parallel sessions
   move fast). Log lines die with retention; the 08-16 churn audit burned a day reconstructing
   exactly this from logs.
2. **Notify the account's other live sessions**: WS to `userRoom(userId)` (`chat/utils/user-room.ts`)
   + push via `push-notifications.service.ts` `notify()` (content-free payload, same as message
   push). Wording = the 08-16 consented-recovery framing: "new device/browser sign-in" as the
   common case, wipe as the variant — the branch also fires on every LEGITIMATE reinstall/migration,
   so the copy must not scream "hacked".
3. **Peer-visible corroboration**: server event to the account's conversation peers so their client
   renders the in-conversation timeline row. Client already has the state machinery:
   `EncryptionProvider.peersWithChangedIdentity`, persisted `PEER_IDENTITY_CHANGED` diag,
   `acknowledgePeerIdentity`, and the user-card "Verify security keys" door
   (`user_card_screen.dart` → `showPeerIdentityFingerprintDialog`). The new piece is a timeline row
   in `ChatDetailScreen` fed by that state + the server event. ARB-localized strings, both
   `app_en.arb`/`app_pl.arb` (UI is PL-heavy).

**Acceptance (doc §9):** live-fire on a test account — bundle replace alerts a second session AND a
peer within 5 s. Cross-tier feature → follow root `CLAUDE.md` §8 wiring pattern (DTO +
`@SubscribeMessage`/service emit; frontend `SocketService` listen + `ConnectionProvider` routing +
provider state). New WS events are §7-adjacent: extend the e2e-wire harness with the event
(that harness is the ONLY automated wire check and it fails CI on red).

**0a traps:**
- The upsert telemetry pre-check is deliberately racy ("races with concurrent connections are
  acceptable", `:42`) — keep the audit write idempotent-ish/tolerant of duplicates; do NOT try to
  serialize the upsert.
- The identity-churn branch fires on the client's EVERY-CONNECT re-upload only when the identity
  actually differs — same-identity re-uploads (the normal path, `encryption_provider.dart` L922-950)
  must stay silent. Test both.
- Under Phase-2 shared identity this alarm goes QUIET on legitimate device adds — deliberate,
  recorded in the doc; don't "fix" the future silence.
- 🔴 **`FIREBASE_SERVICE_ACCOUNT` is ABSENT from `~/fireplace/.env` on the VM** — FCM push is dead
  in prod (boot logs "FCM disabled"). Web Push (VAPID) works. 0a's push notify therefore reaches
  PWA sessions only until the owner sets that var (owner task — nag, verify by REAL device push,
  not by the boot warning disappearing). Second owner task: the `.jks` keystore backup
  (single-copy on the dev PC; runbook `docs/runbooks/android-release.md`).

## 3. Phase 0b/1/2 — the knowledge you'll need (spec has the WHAT; this is the WHERE/WHY)

**Backend single-device assumptions (scout-verified, file:line):**
- `KeyBundle.userId` UNIQUE (`key-bundle.entity.ts:15`); OTPs unique `(userId,keyId)`
  (`one-time-pre-key.entity.ts:14`); **identity-epoch invariant at THREE coupled sites**
  (`key-bundles.service.ts:60-189` — upsert purge / fetch claim / count; the comment block says
  change all three or none). Phase 1 re-keys the partition to `(identityPublicKey, deviceId)`.
- `Message.encryptedContent` single ciphertext (`message.entity.ts:38`); single `deliveryStatus`
  enum; `hiddenByUserIds`/reactions per-user (fine as-is).
- `emitToNewestTab` (`chat/utils/user-room.ts:108-118`) — ciphertext to ONE socket because tabs
  share one Signal store; comments call it temporary; Phase 2 demotes it to within-one-web-device.
  Push suppression reads the SAME newest socket (`chat-message.service.ts:594-608`) — they must
  move together (standing LATEST rule).
- `updateDeliveryStatus` does a FULL-ENTITY save (`messages.service.ts:319-320`) — named conversion
  target to a column-scoped UPDATE (doc §4); mark-read at `:568-570` is already scoped.
- Reconcile contract `findServedMessageIds` (`messages.service.ts:194-243`): per-user,
  row-existence, deliberately NO sender/deliveryStatus predicate, with a test asserting the query
  contains neither. **I8: envelopes must NEVER gate this.** Round-1 review killed a v2 design that
  violated it — it would have destroyed senders' own plaintext on every send.
- Auth: JWT `{sub,username,tag}` no device claim (`auth.service.ts:67-71`); refresh tokens
  per-login, non-rotating, device-agnostic (`refresh-tokens.service.ts:57-77`) — the natural
  deviceId anchor; `revokeAllForUser` = only multi-session control today.
- Push already multi-endpoint (`fcm_tokens` per-token + platform; `web_push_subscriptions`
  per-endpoint) — Phase 1 just adds `deviceId`.

**Frontend crypto engine (scout-verified):**
- `libsignal_protocol_dart ^0.8.2`. `static const int _deviceId = 1` (`encryption_service.dart`
  ~L64) threaded into every `SignalProtocolAddress`/`PreKeyBundle`. Stores ALREADY key by device:
  `session_<name>_<deviceId>`, `trusted_identity_<name>_<deviceId>` (`signal_stores.dart`); but
  `getSubDeviceSessions → [1]` and `deleteAllSessions → _1` are hardcoded.
- **FIVE own-sender guards must switch from `senderId == me` to `originDeviceId == myDeviceId`**
  for self-sync (doc §5.4 + falsification 6): `messaging_provider.decrypt.dart:962-963`, `:975`,
  `:1290`, `messaging_provider.history.dart:529`, `decrypt.dart:642`. Missing one silently kills
  self-sync. Line numbers drift — re-locate by the guard pattern, not the number.
- `_sessionTails` keyed by int peerId (`encryption_service.dart` ~L620) → `(peerId, deviceId)`;
  session Web-Lock name `fireplace-e2e-session-<uid>-<peerId>` likewise. Own devices are just
  another peer address to the ratchet layer.
- Pending-send records keyed by EXACT ciphertext (`send.dart:1196-1215`) → Phase 1 adds `sendToken`
  (server-unique per sender; ambiguous match = no-op; see doc §5.4 — a P1 reviewer finding, the
  token guards the ONLY plaintext copy of own messages).
- Prekey replenishment: origin-locked RMW of `next_pre_key_id` (`fireplace-e2e-prekeys-<uid>`);
  uploads tagged with identityPublicKey (`encryption_provider.dart` L1123-1141). Becomes per-device.
- Key upload happens on EVERY socket connect (`encryption_provider.dart` L922-950: fresh upload if
  `needsKeyUpload`, else `getKeyBundleForReupload()` re-upload) — this is why two live devices on
  one account flip-flop today, and why 0b's same-identity re-uploads must stay frictionless.

**Library facts (source-verified in the pub cache, `libsignal_protocol_dart-0.8.2`):**
- `Curve.calculateSignature/verifySignature` = XEdDSA over ARBITRARY bytes (64 B sigs) — DAK
  signing needs no new crypto dep. `Curve.generateKeyPair()` = independent Curve25519 pair.
- `SignalProtocolAddress(name, deviceId)`: free int, no validation; `PreKeyBundle` takes deviceId
  verbatim; registrationId/signedPreKeyId NOT device-tied (two devices may both use
  signedPreKeyId=0 — namespacing is OUR schema's job).
- **`ProvisioningCipher` EXISTS but MINTS ITS OWN EPHEMERAL inside `encrypt()`** — it would bypass
  the SAS-verified DH secret. Doc §5.1 therefore mandates the explicit construction:
  `Curve.calculateAgreement` + `HKDFv3` (info labels `fp-link-sas` / `fp-link-blob`) + AES-CBC+HMAC.
- Caveats: `calculateVrfSignature` is STUBBED (returns empty — never use); XEdDSA sigs are
  nonce-randomized (non-deterministic, fine); **`sign`/`verifySig` MUTATE passed buffers in place**
  — always pass copies of retained key/signature buffers.

**External design provenance (primary sources, if you need to re-derive):** Sesame spec
(signal.org/docs/specifications/sesame — device records, send-time staleness, §3.3), Signal
linked-devices blog 01/2025 (shared IK via provisioning; history-archive transfer = our Phase 4),
WhatsApp/Meta engineering (per-device identity + Account-Signature device lists + ADV — where the
signed-list idea comes from), eprint 2021/626 (the server-trusted device-registration takeover our
DAK design kills), Cremers USENIX'23 (PCS dies in session-handling code, not crypto — why §5.4 is
called the danger zone), ZRTP/Vaudenay SAS literature (why the linking SAS is DH-bound: short auth
strings without commitment/DH binding are offline-grindable; v3 of our own doc had exactly that bug).

## 4. Verification machinery you inherit

- Tests: backend `cd backend && npm test`; frontend `flutter analyze --no-fatal-infos && flutter
  test`. Counts live in root `CLAUDE.md` §3 and are VERIFIED by
  `scripts/verify-claude-*-test-counts.mjs` — update §3 when you add tests, per-commit-true counts.
  **NEVER pass `flutter test` a file list** (per-argument compile cost; run one file, one dir, or
  the full suite). `node scripts/lint-ratchet.mjs` before pushing backend changes (CI-only ratchet).
- e2e-wire harness (`frontend/test_e2e`, needs `docker-compose up`): the ONLY automated §7 wire
  check; red fails CI. It has the seam you need: **`adoptAccountFrom`** (used for reinstall cases)
  — the two-devices-one-account suite (required BEFORE Phase 1 merges, doc §8) extends it. Register
  throttle 10/hr/IP in-memory → `docker compose restart backend` between full runs. A headless
  socket.io peer has NO key bundle — E2E sends to it fail; use real clients.
- On-device: `flutter test integration_test -d <deviceId>` (real Keystore/SQLCipher — DAK custody
  tests belong here). `scripts/impact.mjs` = inner-loop blast-radius hint (not coverage).
- Migrations: numbered SQL in `backend/migrations/`, applied once at boot, failure aborts boot,
  applied files IMMUTABLE. **Phase-1 migration must be ONE transaction, plain (non-CONCURRENTLY)
  index creation** (doc §8 — reviewer finding). Staging dress rehearsal for every schema phase
  (runbook `.cursor/rules/production-vm-deploy.mdc`, "Staging dress rehearsal").
- Deploy is SPLIT (root §4): backend on the VM (`./deploy-backend.sh`), frontend from the PC
  (`.\deploy-web.ps1` — **known exit-21 silent publish halt, 6+ recurrences: build succeeds, log
  ends at the publish banner; re-run/manual staged publish; never pipe to `tail`**). Verify via
  `/version` + `/version.json` gitCommit, never semver. Smoke: `cd scripts/smoke && node
  post-deploy-smoke.mjs`. Deploy order for cross-tier phases: backend BEFORE web.

## 5. Process traps paid for this session (don't re-pay)

- **Shared working tree, parallel sessions:** `git status -sb` before EVERY commit; expect master
  to move under you (rebase, don't panic); `deploy-web.ps1` has been found DELETED from the tree
  repeatedly — restore from HEAD, it's not yours; LATEST.md WILL conflict — resolve additively,
  keep ≤5 dated entries (the pre-commit hook enforces it; the agent adding an entry DELETES the
  oldest; dated files keep the full account). `.planning/` is gitignored. gitleaks pre-commit:
  key-name literals need `// gitleaks:allow`, dummy JWTs must be built at runtime.
- **Subagent harness:** a `security-reviewer`-type agent got a hard content-filter REFUSAL on
  adversarially-framed review prompts — use the plain `reviewer` type with defensive framing
  ("verify our own design's claims"). One reviewer exited 1 AFTER grounding without emitting —
  respawn once, it worked. Keep writer-agent concurrency ≤2 (rate limits, 08-16 lesson).
- **Review economics (owner cares):** the doc went through a measured convergence — round 1
  architecture-level, round 2 mechanism-level (mostly bugs in round 1's patches), round 3
  delta-scoped (2 findings), micro-check zero. The stopping rule is recorded in the doc header:
  further review ONLY at phase gates, delta-scoped, with code in hand. Do NOT relaunch doc-wide
  review rounds; DO run the Phase-2 spec review when you get there.
- Review rounds beat solo design here — round 1 caught a v2 mechanism that would have
  mass-destroyed senders' plaintext (now I8), round 2 caught a grindable SAS (now §5.1), round 3
  caught a fallback ordering that would have `[Decryption failed]`-ed all pre-link history. Budget
  for the phase-gate reviews; they pay.

## 6. Suggested execution shape

0a on a feature branch → PR → owner OK → merge → backend deploy + web deploy → live-fire acceptance
→ session summary + LATEST rotation. Then 0b (includes recovery key §6.2.1 + reset ceremony §6.2 —
red-first falsifications 10/21). Then Phase 1 schema (falsifications 1/13; harness two-device suite
FIRST). Phase 2 only after its spec-gate review. Keep each phase's §10 falsifications red-first —
that's the repo's proven gauntlet (B2b, 0.1.10 precedents).

Good luck. The design is solid because five reviewers and two literature checks beat on it — trust
the frozen spec, verify against code as you go (code wins, fix docs in the same commit), and keep
the owner's prove-then-ask rule sacred.
