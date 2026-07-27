# E2E incident handoff — saraLee dual-login identity split (peer 63 badMac loop)

**Date:** 2026-07-10 (research only — ZERO code changes this session)
**For:** the fresh agent who will FIX the E2E subsystem before release.
**Read first:** root `CLAUDE.md`, `frontend/CLAUDE.md` §5, `backend/CLAUDE.md`, `docs/runbooks/e2e-decryption-failed.md`. Then this file top to bottom. Do NOT re-derive any of this.

---

## 0. Verdict (lead with the conclusion)

**No evidence of a recent-change regression. The LEADING DIAGNOSIS (confidence MEDIUM-HIGH — gated on D1/D3 in §3) is the known, documented, never-built "regeneration guard" gap, made worse by a dual-login (two live clients, one account, two different identity keys).** Every recent E2E-touching commit was audited (§4); none changed decrypt/session classification — but two dependency bumps (libsignal 0.8.2, socket_io 3 browser connector) remain under-verified, so "not a regression" is a strong default, not a proof. Collect D1+D3 BEFORE building; only they move this to certain. The system has THREE structural design gaps (these ARE code-verified facts, independent of the incident attribution) that together make saraLee's scenario (PWA delete+reinstall while a Safari tab stays logged in) unrecoverable:

1. **Server: single last-writer-wins key-bundle slot per userId, no identity versioning** — `backend/src/key-bundles/key-bundles.service.ts:40-48` (`upsert` on `conflictPaths:['userId']`; `key_bundles.userId` is `@Column({unique:true})`). Two live clients with different identities flip-flop the slot on every reconnect.
2. **Server: one-time prekeys are append-only with NO identity binding, served oldest-first** — `key-bundles.service.ts:50-104`. Reinstall uploads fresh OTPs but old-identity OTPs survive (`deleteByUserId` runs only on account deletion) and get served FIRST (`ORDER BY id ASC`). Peers get {NEW identity + STALE OTP} bundles — X3DH the new device can never complete → phantom Bad Mac. **This exact bug was flagged as UNFIXED in the 2026-07-08 wire-harness session summary and never built.**
3. **Client: no peer-identity-regeneration detection.** `hadIdentityReset` is the LOCAL device's own `needsKeyUpload` flag (`frontend/lib/providers/encryption_provider.dart:54`) — it can never detect a PEER regenerating. Worse, `badMac` OUTRANKS `identityReset` in the decision table (`frontend/lib/utils/decryption_failure_policy.dart:86-127`), so even a peer-aware flag would be masked. Identity trust is unconditional TOFU-overwrite (`signal_stores.dart` `isTrustedIdentity` always saves+returns true; `encryption_service.dart:172-193` `buildSession` pre-saves the bundle identity) — identity flips are SILENT.

Result: owner (37) holds ONE inbound session for peer 63 that can match at most ONE of saraLee's two identities; every message from the other context is terminal Bad Mac; outbound rebuilds "succeed" silently against whichever identity currently owns the slot; the `alreadyRequested` throttle wedges recovery within each connection. Livelock, by construction.

---

## 1. The incident, decoded event-by-event

Owner device log (userId 37), window 07-10 21:52–22:37, peer 63 (presumed saraLee):

- `SESSION_REBUILD_RECEIVED` from 63 → owner's next sends do `needsRebuild:true` → `SESSION_ARCHIVED_FOR_REBUILD` → `PREKEY_RESP` → `SESSION_BUILT` → `SEND_EMIT`. This is `encryption_provider.dart:101-140` (`ensureSession` builds OVER the record, archives up to 40 ratchet states). **`SESSION_BUILT` proves nothing about decryptability on 63's side** — `buildSession` blind-trusts whatever identity the slot serves (`encryption_service.dart:191-193`), and the owner never sees a cryptographic ack.
- EVERY inbound from 63 (msgs 14971, 14972, 14976, 14980, 14985, 14986, 14990, 14991, 15009) → `DECRYPT_BAD_MAC` → `kind:badMac, idReset:false, hadSession:true, persist:true, notifyPeer:true`. Inbound-only persistent Bad Mac while outbound rebuilds cleanly **proves the broken state is on the SENDER (63) side**: she encrypts with identity/ratchet material that doesn't match the owner's single peer-63 session. Not owner-side corruption (that would be NoSession and would also break his encrypt).
- Three `SESSION_RESET`s across 45 min + `SESSION_RESET_SKIPPED {alreadyRequested}`: `_rebuildRequestedPeers` throttle (`messaging_provider.decrypt.dart:203-229`) clears per-peer ONLY on a successful decrypt from that peer (`decrypt.dart:718-720` — unreachable here) and wholesale only on FRESH connect (`messaging_provider.dart:471-498`; deliberately KEPT on reconnect). Each fresh connect/relaunch = one new SESSION_RESET, then wedge. The rebuild request is broadcast to the user ROOM server-side (`chat-key-exchange.service.ts:246-260`) → BOTH of saraLee's clients re-key under DIFFERENT identities → ping-pong sustains.
- `E2E_KEYS_REUPLOADED` on every reconnect (`encryption_provider.dart:305-324`): benign on the owner (stable identity), but on saraLee's side this is the slot-thrash driver — Safari re-uploads the OLD identity, the PWA re-uploads (or uploaded) the NEW one, last writer wins.
- Earlier durable entries (07-07..07-10, peers 43/48/58/62/63, `kind:duplicate isHistory:true` and badMac bursts): consistent with pre-fix damage decay + archived-ratchet replays per the runbook dating rule. Orthogonal to the 63 loop; do NOT chase them until 63 is understood.

### Why saraLee sees ALL her messages broken

- **History:** her PWA reinstall wiped `sig_e2e_63_*` localStorage → fresh identity generated (`encryption_service.dart:74-84`: empty storage is the ONLY trigger). All history ciphertext is bound to her OLD identity; the server NEVER re-encrypts (`messages.service.ts:54,71-84` — `encryptedContent` write-once except sender edit). **Cryptographically unrecoverable in the PWA. Data loss, not a bug to "fix".** Her Safari tab (old keys intact) could still read history — those keys are the only surviving copy.
- **New messages:** peers hold sessions to whichever of her identities they last saw; bundles served to them mix identities and stale OTPs → Bad Mac in both directions.

### Owner's hypothesis: CONFIRMED mechanically (confidence MEDIUM-HIGH)

The dual-login walk matches all four observed discriminators: (i) badMac not noSession/idReset, (ii) history duplicates orthogonal, (iii) loop despite rebuilds, (iv) three SESSION_RESETs + alreadyRequested wedge. What's missing is direct evidence from saraLee's side and the DB — see §3. **On iOS, installed-PWA storage and Safari storage are SEPARATE contexts** — that's why reinstall+Safari = two identities on one account.

---

## 2. Runbook status

Matches the runbook `kind:badMac` row, which says "investigate only if looping" — it IS looping and the runbook has no procedure for it. The true cause is the adjacent `idReset` row's "still-unbuilt regeneration guard", but that row can never fire (idReset is self-only + badMac precedence). **This is a NEW signature: "peer identity regenerated / dual-login split-brain → looping inbound badMac, idReset:false, unrecoverable by rebuild machinery."** The fixing agent should add this row to the runbook when the fix ships.

---

## 3. Missing evidence — collect BEFORE building (exact steps)

| # | Evidence | How | Proves |
|---|---|---|---|
| D1 | saraLee's durable diag dumps — from PWA **and** Safari separately | Each context: Settings → Privacy & Safety → hacker mode → Durable failures → Copy | PWA: `E2E_KEYS_UPLOADED`/`needsKeyUpload:true` (fresh identity). Safari: `E2E_KEYS_REUPLOADED`. Two dumps = two identities |
| D2 | Backend key-upload lines for user 63, 07-10 | VM: `docker compose -f docker-compose.prod.yml logs --since 24h backend \| grep -iE "userId=63.*(bundle\|pre-key)"` — CAVEAT: these are `logger.debug`, prod-silent since 0.0.95 log-min; may need a temporary log-level bump | Two identities hitting one slot |
| D3 | DB key state for user 63 — **definitive** | `docker compose -f docker-compose.prod.yml exec db psql -U postgres -d chatdb -c 'SELECT "userId","registrationId",left("identityPublicKey",16),"signedPreKeyId","updatedAt" FROM key_bundles WHERE "userId"=63;'` and `SELECT id,"keyId",used FROM one_time_pre_keys WHERE "userId"=63 ORDER BY id;` | Current slot winner + OTP pool with two upload epochs (id gap) |
| D4 | `SELECT id,"senderId","createdAt" FROM messages WHERE id IN (14971,14976,14980,14985,14986,14990,14991,15009);` | same psql | These are live 63→37 in the window, not pre-fix history (runbook dating rule) |
| D5 | The 2-min persistence test (runbook end) — **STILL never run** | Normal browser profile: fresh account → message once → fully close → reopen → check backend for a new OTP upload | Rules key persistence in/out as a fleet-wide contributor |

Fastest certainty: D3 + D1-Safari. If Safari's registrationId ≠ the `key_bundles` row's registrationId, the dual-identity single-slot mechanism is PROVEN.

**Immediate user remediation (no code):** saraLee must log out of / close ONE context permanently — keep exactly one. If she keeps the PWA (fresh identity), have her fully close Safari's session; then each peer's conversation heals for NEW messages only after one successful rebuild round (old terminal rows never come back — set that expectation). Her pre-reinstall history is recoverable ONLY in the Safari context that still holds the old keys.

---

## 4. Recent-changes audit — what shipped, what's innocent

Full audit by commit (window 06-26 → 07-10). Prod frontend = 0.0.105/`2afdd50`; prod backend = `b7708ed`.

| Change | Where | E2E verdict |
|---|---|---|
| 0.0.75 PR #17 web Signal storage rewrite (`sig_` async namespace, legacy migration, TOFU comment) | `signal_stores.dart` | Substrate, pre-window. Guarantees consistency only WITHIN one storage context — never across Safari vs PWA |
| 0.0.90 `3ac0773` encrypt serialization | `encryption_service.dart` | Sound; shipped for the note-burst race |
| **0.0.94 `ac82a9a` full per-peer session lock (`_sessionTails`)** | `encryption_service.dart` | The most load-bearing change in the window. Independently reviewed sound. Shipped BEFORE the wire harness existed (validated by gated unit probe only) |
| **0.0.96 `bfbbe4e` backend OTP-serve fix** (misdestructured `[rows,rowCount]` → every bundle served `oneTimePreKeyId:null`) | `key-bundles.service.ts`, backend-only deploy `080d660` | Fixed a REAL bug; its own session summary **flagged the unfixed OTP-purge-on-regeneration gap = this incident's server half** |
| **0.0.97 libsignal_protocol_dart 0.7.4→0.8.2** (grouped Dependabot PR #40) + socket_io_client 2→3.1.6 | pubspec | libsignal bump had NO dedicated harness run (implicitly exercised in the 0.0.97 harness, dart:io connector only). Under-verified but no evidence it misbehaves; do not chase unless D-evidence contradicts §0 |
| webcrypto pin 0.6.0 | pubspec | Build-tooling only, zero runtime crypto change |
| 0.0.95/98/99/100/101/103/104/105 | various | Provably NOT decrypt/session: push metadata, typeorm/file_picker, composer/keyboard UI, media-preview envelope metadata, ping glyph/sound |
| **0.0.102 lost-ack pending-send reconcile** | branch `fix/lost-ack-pending-send-reconcile` (`6029bed`) | **NOT MERGED, PR owed.** Fixes a DIFFERENT symptom (own sent message `[encrypted]` after socket drop). Irrelevant to saraLee. The code IS on that branch and HEAD-verified complete |
| Decision table `decryption_failure_policy.dart` | — | UNCHANGED since 0.0.45. No commit in the window altered classification |

**Conclusion: no audited commit supports "we messed it in recent changes."** The recent work fixed real races; the saraLee failure fits a pre-existing architectural gap that reinstall+dual-login finally exercised in the field. Residual uncertainty: libsignal 0.8.2 and the socket_io-3 browser connector were never harness-exercised on the path prod users run — revisit them ONLY if D1/D3 evidence contradicts the leading diagnosis.

---

## 5. Subsystem map (for the fixing agent — file:line verified 2026-07-10)

**Frontend:**
- `frontend/lib/services/encryption_service.dart` — per-user prefix `e2e_${userId}_` (l.68); identity gen ONLY on empty storage (l.74-84, `needsKeyUpload`); `_generateKeys` 20 OTPs ids 0-19 (l.91-129); `buildSession` blind `saveIdentity` (l.172-193); `_sessionTails` lock (all four mutators); `clearAllKeys` (l.603-641, only caller = account deletion); pending-send records (unmerged branch).
- `frontend/lib/services/encryption/signal_stores.dart` — DualStorage: web = SharedPreferencesAsync/localStorage `sig_` prefix, mobile = flutter_secure_storage; `isTrustedIdentity` TOFU-always-accept (~l.314-327); `_sessionKey` deviceId hardcoded 1 = single-device; legacy migration (~l.150-245).
- `frontend/lib/providers/encryption_provider.dart` — `hadIdentityReset => needsKeyUpload` (l.54); `ensureSession` early-return when hasSession && !needsRebuild (l.104), rebuild-over-record (l.101-140); `initializeE2E` upload/reupload with NO server-identity guard (l.305-324); `onSessionRebuildNeeded` → `_forceSessionRebuild` (l.389-394).
- `frontend/lib/utils/decryption_failure_policy.dart` — pure decision table; precedence duplicate/badMac > identityReset > noSession > unknown (l.86-127). Unit-tested.
- `frontend/lib/providers/messaging/messaging_provider.decrypt.dart` — classification by exception string (l.24-28); DECRYPT_DECISION application + durable diag (l.840-871); `_requestSessionRebuildForPeer` + throttle (l.203-229); throttle clear on DECRYPT_OK (l.718-720).
- `frontend/lib/providers/messaging_provider.dart` — throttle wholesale clear on fresh connect (l.492), KEPT on reconnect (l.497-498), cleared on logout (l.551-556).
- Diag: `frontend/lib/utils/e2e_persistent_diag.dart` (durable, cap 80) + in-memory ring.

**Backend (all WS, no REST controller for keys):**
- `backend/src/key-bundles/key-bundles.service.ts` — `upsertKeyBundle` last-writer-wins (l.40-48); `uploadOneTimePreKeys` append-only (l.50-61); `fetchPreKeyBundle` oldest-first atomic claim (l.63-104); `deleteByUserId` account-deletion only (l.110-114).
- `backend/src/key-bundles/*.entity.ts` — `key_bundles.userId` unique (single slot); `one_time_pre_keys` has NO identity/generation marker.
- `backend/src/chat/services/chat-key-exchange.service.ts` — upload handlers (l.32-74); fetch w/ 750ms per-pair limit (l.76-125); `requestSessionRebuild` → user-ROOM broadcast + 24h in-memory pending replay (l.150-168, 246-283).
- `backend/src/chat/chat.gateway.ts` — `onlineUsers Map<userId,socketId>` (l.63): direct emits (`newMessage`, `messageSent`, …) go to the LAST socket only; rooms get rebuild broadcasts — **asymmetric routing, toxic under dual-login** (second live client goes dark for live messages). Guarded disconnect (l.154-165) handles stale sockets, NOT two live ones.

---

## 6. Fix directions (design sketch — owner has NOT approved any; grill before building)

Priority-ordered; (a)+(b) are the minimum credible release gate:

- **(a) Backend: purge OTPs on identity change.** In `upsertKeyBundle`, when the incoming `identityPublicKey` differs from the stored one, delete all that user's unused OTPs in the same transaction (and consider bumping `signedPreKeyId` semantics). Kills the stale-OTP/X3DH poison permanently. Small, migration-free, testable in the wire harness. Also consider binding OTP rows to `registrationId` for defense in depth.
- **(b) Client: peer-identity-change detection on inbound failure.** On Bad Mac (and PreKey messages), compare the sender's identity key against `trusted_identity_<peer>` BEFORE classifying; if changed → new rule `peerIdentityReset` that OUTRANKS badMac: do NOT persist terminal, mark `[encrypted]` recoverable, trigger a throttle-exempt bounded re-key handshake, and surface a UI notice ("contact reinstalled the app — history before this point is unreadable for them"). This is the never-built regeneration guard.
- **(c) Server: reject/flag concurrent second identity.** The app is explicitly single-device. When `uploadKeyBundle` changes the identity while another socket for the same userId is live, either force-disconnect the other socket with a `keyConflict` event (client shows "logged in elsewhere with different keys") or refuse the upload. Without this, dual-login split-brain remains reachable.
- **(d) Throttle repair:** `alreadyRequested` should have a TTL or clear on `PREKEY_RESP`-observed identity change, so a legitimate re-key after slot stabilization isn't wedged for a whole connection.
- **(e) Merge or explicitly park `fix/lost-ack-pending-send-reconcile`** (0.0.102, `6029bed`) — separate symptom, finished code, PR owed. Don't let it rot on a branch during E2E surgery.

**Verification requirements for whatever ships:** extend `frontend/test_e2e/` wire harness with a reinstall scenario (account A messages B; A's client wipes local keys, re-initializes, re-uploads; assert B detects identity change, no stale OTP served, new-message flow converges; assert old history stays failed — that's correct) and a dual-login scenario (two clients, one account). Run the runbook's 2-min persistence test (D5). Staging rehearsal needed only if (a) ships as a schema change (identity column on OTPs → numbered migration in `backend/migrations/`).

## 7. Hard rules (inherited + new)

- Never advise users to clear site data / reinstall / incognito — that MANUFACTURES this incident.
- Persisted-terminal `[Decryption failed]` rows never come back; pre-reinstall history for a wiped identity is unrecoverable BY DESIGN. Set owner expectations before shipping any fix.
- badMac outranks identityReset in the current table — any peer-reset detection MUST be inserted ABOVE badMac or it will never fire.
- All SessionRecord mutations go through `_runSessionSerialized`; never add a second lock (runbook Step 3A/3B).
- Two contexts, one account = two identities is REACHABLE today on iOS (PWA vs Safari storage are separate). Design for it; don't assume single-client.
