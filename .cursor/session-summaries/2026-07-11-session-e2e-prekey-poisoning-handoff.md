# E2E handoff #2 — poisoned one-time-prekey pool (release blocker), 2026-07-11

**Continues:** `2026-07-10-session-e2e-incident-handoff.md` (read it FIRST — subsystem map §5, fix directions §6, Sara incident). This file supersedes its diagnosis sections where they conflict.
**Also read:** root `CLAUDE.md`, `frontend/CLAUDE.md` §5, `backend/CLAUDE.md`, `docs/runbooks/e2e-decryption-failed.md`.
**State of the world:** research + proof-scenario authoring DONE; harness NOT yet run (Docker was down); fix NOT implemented. Prod untouched. A separate liquid-glass UI agent owns the MAIN worktree and prod frontend deploys — do not touch their tree or redeploy over them.

---

## 0. Status of the two incidents

### Sara (peer 63) — CLOSED, diagnosis confirmed by owner
Multi-device split-brain: she was logged in on Safari AND the reinstalled PWA (separate iOS storage contexts) → two identities fighting the single last-writer-wins `key_bundles` slot. Mechanism fully mapped in handoff #1. Her pre-reinstall history is unrecoverable (old keys only in the Safari context). Fix = handoff #1 §6 (b)(c)(d) — regeneration guard, concurrent-identity rejection. Do NOT re-investigate.

### Owner (bob208, userId 37) cache-wipe cascade — root-caused this session
Timeline 07-11: owner tapped Privacy & Safety "clear local message cache" twice → all history terminal (`duplicate`) — **expected, accepted data loss** (that button deletes the only readable plaintext copy; ratcheted messages can't re-decrypt). BUT the history badMac rows fired `notifyPeer` rebuild requests at peers 48/50/58, and peer 48 (goonboy)'s resulting **fresh PreKey (`ctype:3`) messages failed Bad Mac live** (msgs 15089, 15093) — which a plaintext wipe cannot explain. That live failure led to the discovery below.

## 1. ROOT CAUSE (leading diagnosis, HIGH confidence, conditional — see §3)

**The server's one-time-prekey pool is poisoned fleet-wide.**

Causal chain, each link source/DB-verified:
1. **May–mid-June client bug (historical, apparently stopped ~06-15):** initial prekey generation+upload ran repeatedly per account (owner: 26 times), each run minting NEW keypairs under the SAME keyIds 0–19. Device keeps ONE private per keyId (storage key `e2e_<uid>_pre_key_<id>` — overwritten each re-mint).
2. **Server pool is append-only with no identity/epoch binding** (`one_time_pre_keys`: userId, keyId, publicKey, used — `key-bundles.service.ts:50-61`). Owner's pool: keyId 1 exists in **22 distinct public versions**; 520 rows total, ALL keyIds ≤19 (replenishment NEVER landed for this account in 2 months — separate bug, §5.4).
3. **Dormant until 0.0.96 (07-08):** before it, `fetchPreKeyBundle` served `oneTimePreKeyId:null` while burning rows (the `[rows,rowCount]` bug) — nobody ever consumed a real OTP. The fix armed the poison.
4. **Oldest-first serving** (`ORDER BY id ASC`, `key-bundles.service.ts:75-87`): every session rebuild toward a poisoned account is served the DEADEST public first. Peer builds X3DH against a public whose private no longer exists → recipient Bad Mac → message permanently lost → another rebuild → next dead row. Owner has ~300 dead rows queued.

**Field proof:** goonboy's two failing wires decode to `preKeyId 1` and `2` (ciphertext prefix `3:MwgB`/`3:MwgC` → protobuf field 1 varint); server rows 5642/5643 = keyIds 1,2 from the 05-24 epoch; owner's newest epoch is 06-15. Decode method: base64 body, skip version byte 0x33, read proto field 1.

**Fleet scope (DB-proven pool ambiguity, NOT proven live breakage per-user):** `SELECT "userId", count(*), count(DISTINCT ("keyId","publicKey")), count(DISTINCT "keyId") FROM one_time_pre_keys WHERE used=false GROUP BY "userId" HAVING count(*) > count(DISTINCT "keyId")` → users 43 (1139 rows/119 pairs), 14, 58 (622 pairs), 76, 12, 37, 78, 50, 48, 60, 15… nearly every long-lived account. Only user 41 shows keyIds >19 (healthy replenishment).

## 2. What is PROVEN vs INFERRED (calibration — do not overclaim downstream)

| Claim | Status |
|---|---|
| Pool holds many distinct publics per keyId, served oldest-first, append-only | PROVEN (DB + source) |
| Goonboy's failed wires referenced the two oldest stale rows | PROVEN (decode + DB) |
| Owner's local private mismatches those served publics → Bad Mac | INFERRED (forced by one-slot-per-keyId storage design; not fingerprint-verified — no local-key diagnostic exists yet) |
| Alternative "goonboy's own client state was broken" | NOT EXCLUDED (2 datapoints, 1 peer) — harness scenario 1 is the discriminator |
| OTP-less X3DH works on current code | Code-verified both ends (`key-bundles.service.ts:89-103` serves null; `encryption_service.dart:183-208` builds with null) + months of pre-0.0.96 field behavior; NOT yet exercised on current build — harness scenario 3 pins it |
| Fleet-wide LIVE breakage | NOT claimable from pool stats; claim only "every long-lived account at risk on next rebuild" |

## 3. Proof scenarios — WRITTEN, NOT YET RUN (your first task)

File: `frontend/test_e2e/poisoned_prekey_pool_test.dart` in worktree **`../fireplace-e2e-fix`** (branch `fix/prekey-epoch-poisoning` off `origin/master`, created to avoid the liquid-glass agent's dirty main tree). Three tests, real wire + real libsignal:
1. **Poison repro:** bob uploads epoch-1 keys → `clearAllKeys` (models overwritten privates) → fresh service uploads epoch-2 → alice's fetch must serve epoch-1 OTP + epoch-2 identity → PreKey wire → assert decrypt throws `Bad Mac`. **This passing = causal attribution proven. This failing (message decrypts) = diagnosis wrong, STOP, no purge.**
2. **Recovery:** drain fetches until a live-epoch OTP is served (wire-level equivalent of purging stale rows) → rebuild → assert first-try decrypt.
3. **Empty pool:** drain fully → `oneTimePreKeyId:null` bundle → OTP-less rebuild → assert decrypt.

Run: start Docker Desktop → `docker-compose up` **from the FIX worktree root ONLY** (`C:/Users/Lentach/Desktop/fireplace-e2e-fix`) — the dev compose bind-mounts `./backend`, so the compose project directory decides WHICH backend code runs; starting it from the main worktree runs the UNFIXED backend and would falsely report the epoch fix as ineffective. If the liquid-glass agent's stack might also be up, isolate with `docker compose -p fireplace-e2efix up` and check :3000/:5433 port conflicts first. Then `cd frontend && flutter pub get && flutter test test_e2e/poisoned_prekey_pool_test.dart`. Watch-outs: register throttle 10/hr/IP (`docker compose restart backend` resets); fetch pacing 850ms → tests take minutes; every scenario asserts `wireType == 3` so a ctype-2 bypass fails loudly.

**Verification state of the test file: NONE.** Imports were corrected to `package:fireplace/...` style but neither `flutter analyze` nor a compile has run (Docker daemon and `flutter pub get` were unavailable at handoff time). Expect possible trivial breakage: `getKeysForUpload`/`clearAllKeys` signatures, `E2eEnvelope` visibility, `predicate` typing. Fix mechanically; the scenario LOGIC is the deliverable.

## 4. The fix (design agreed with owner, NOT implemented)

### 4a. Backend: epoch/bundle-version-bound OTPs (the structural kill)
NOT the naive `(userId,keyId)` upsert — overwriting a published public can invalidate in-flight PreKey messages, and keyIds legitimately restart after reinstall. Instead:
- `key_bundles` gets a monotonic **bundleVersion** (or epoch) that increments whenever identityPublicKey OR signedPreKey material changes on upload (explicit version, not inferred).
- Every OTP row stores the bundleVersion it was uploaded under. Duplicate keyId within one version → **reject loudly** (that's the May–June client bug made visible). Same keyId across versions → fine.
- `fetchPreKeyBundle` claims ONLY current-version rows (`AND "bundleVersion" = current` in the atomic UPDATE); prior-version rows are dead by definition — purge on rotation or lazily.
- Migration (numbered SQL in `backend/migrations/`, staging-rehearsed per root CLAUDE.md §6): add column, **retire ALL existing unused rows** (no "keep newest epoch" guessing — no epoch is provably good without local fingerprints), let live clients open version 1 with a fresh batch.
- Also in the same PR: purge unused OTPs when `uploadKeyBundle` changes identity (handoff #1 fix (a) — Sara-class).

### 4b. Prod remediation (AFTER 4a deployed + harness green; owner GO required — destructive)
Canary owner (userId 37) first: retire his unused rows → his client replenishes (VERIFY: new rows with keyIds ≥20 land — his counter is past collision range) → confirm one live `ctype:3 DECRYPT_OK` with goonboy → fleet rollout. Acceptance = the live round trip, not theory.

### 4c. Client hardening (separate PR, before release)
1. **History-pass (`isHistory:true`) decrypt failures must NOT fire `requestSessionRebuild`** — owner's one cache wipe churned sessions across 3+ peers (amplification, reproduced in the field 07-11 04:16).
2. **Prekey fingerprint diagnostic** in hacker mode: list local prekey ids + derived publics (read-only) — closes the §2 inference gap and makes future reports 1-minute diagnosable.
3. **Replenishment reliability** (§5.4) — why did `preKeysLow` never land for user 37? Suspect: notify goes only to the single `onlineUsers` socket (`chat-key-exchange.service.ts:118-123` area) and gets lost; also verify client uploads on receipt.
4. Cache-clear button: destructive confirmation dialog + honest label ("permanently deletes the readable copy of all past messages on this device").
5. Handoff #1 §6 (b)(c)(d): regeneration guard, concurrent-identity rejection, throttle TTL (Sara-class).

## 5. Open questions / loose ends
1. **Which client code caused the May–June re-mints?** Churn stopped ~06-15. Suspect init/upload path re-running `_generateKeys` or re-uploading `_keysForUpload` per connect in old builds. Git-archaeology optional — the epoch fix makes recurrence loud regardless.
2. **Owner's live badMac with peers 50/58**: expected same poisoned-rebuild mechanism; watch after remediation.
3. **Conv 78 (Sara chat) messages deleted server-side 07-10** (msgs 14842–15009 gone, conversation row survives = clear-history shape). Initiator unknown; owner didn't do it knowingly. Low priority.
4. **0.0.106 deploy irregularities**: served bundle has NO `GIT_COMMIT`/`BUILD_TIME` dart-defines (post-deploy smoke's sha-grep cannot pass) though VAPID key IS present; ships a self-destructing Flutter SW (unregister+reload — deliberate cache-bust pattern). Liquid-glass agent's deploy; flag to them, do not redeploy over their work.
5. **The 2-min persistence test** (runbook) — STILL never run; gates the regeneration guard.

## 6. Evidence access
- Prod (read-only investigation established this session): `ssh ubuntu@51.68.138.13`, `cd ~/fireplace`, psql via `docker compose -f docker-compose.prod.yml exec -T db psql -U postgres -d chatdb`. Schema gotchas: `messages.sender_id`/`conversation_id` snake_case, `conversations.user_one_id/user_two_id`, camelCase columns need quotes.
- Owner's durable diag dumps (2×, 07-10 + 07-11) are in the chat transcript of this session; key msgIds: 15089/15093 (goonboy live badMac), 14971-15009 (Sara loop).
- Never run destructive SQL without explicit owner GO. Never advise users to clear data/reinstall. `[Decryption failed]` persisted rows never come back — set expectations.

## 7. Definition of done (release gate)
1. Harness: all 3 poisoned-pool scenarios + existing 7 wire tests green against the fixed backend.
2. Backend: epoch-bound OTP PR merged, migration staging-rehearsed, deployed; backend unit tests updated (+ CLAUDE.md §3 test count + verifier green).
3. Prod: canary (owner) live `ctype:3 DECRYPT_OK` verified, then fleet purge, then spot-check `one_time_pre_keys` shows only current-version rows and fresh keyIds ≥20 appearing.
4. Client: 4c items 1–4 shipped (item 5 may be its own milestone with the owner's sign-off).
5. Runbook updated with the poisoned-pool signature + this fix; session summary + LATEST per CLAUDE.md §1.
