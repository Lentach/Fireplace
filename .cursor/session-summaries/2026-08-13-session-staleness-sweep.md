# 2026-08-13 — Field diagnostics read, staleness sweep, tracker cleared

**No code shipped to production. Two commits pushed to `master` (`f6e4aa8`, `7663047`), CI 4/4 green. `0.1.9` is STILL not deployed — re-verified live, see below.**

Owner returned after ~1.5 weeks and pasted a fresh E2E diagnostic dump, then asked what else had gone stale.

## 1. The diagnostic dump — everything from 08-05 checks out

- **`CANARY_OK {ageDays: 15}` reconciles the 08-05 open question.** Last session I could not explain a dump reading `ageDays: 7` on 08-06 and `9` later. Source settles it: `_checkAndArm` logs `_ageDays(secureRecord)` and **returns without re-arming** on the match path (`content_key_canary.dart:134-142`), so the number is a monotone counter from one arm event. 7 → 07-30, 9 → 07-30, 15 → 07-30. All three agree; the middle dump was simply ~6 days stale when pasted. **One arm, 15 days, zero `CONTENT_KEY_CANARY_LOST`, no silent re-arm.** The caveat is unchanged and still binding: this measures localStorage against localStorage, so a long green run is not clearance to seal key material.
- **`WEB_SEAL_OPEN {sealed: 258, legacy: 0, unreadable: 0, lostRows: 0, ms: 231}`** — up from 184 → 190 → 258 across ~11 unattended days. B2a content sealing has zero field loss. This, not the canary, is the real evidence.
- **The recurring duplicate-decrypt storm STOPPED.** Last durable `DECRYPT_DECISION` is `08-03 17:44:13`; nothing for 08-04→08-14. The newest durable entry is 08-11, so this is not ring eviction hiding recent events. The fixed id sets for peers 60/52/83/49 have retired — terminal-duplicate retirement worked, it just needed more distinct process lifetimes than expected. **Investigation closed by observation, not by a fix.**
- **NEW: `08-11 15:24:47 PEER_IDENTITY_CHANGED {peerId: 92}`** — third one (90, 54, now 92), fired while the owner was away, on the vulnerable build, on a peer with a live session. This does **not** contradict the `3d30b88` finding: detection lives in `isTrustedIdentity` (`signal_stores.dart:511-519`), and the deleted pre-save only poisoned the path where *we* fetch a bundle from the server. Inbound `PreKeySignalMessage` still fires. So **detection works for keys arriving in messages and is blind in exactly the direction an active server MITM attacks.** Peers 90/54/92 remain unverified and CANNOT be verified on `c01317c` — `getPeerIdentityFingerprint` has one UI caller there (the banner). 0.1.9's Safety-section door is the fix.
- Healthy/normal: `STORAGE_PERSIST {supported: true, granted: true}`, `SESSION_INVENTORY {count: 33}` stable across four reconnects, `CONV_LIST {count: 27}`.
- **Minor, unfixed:** `E2E_KEYS_REUPLOADED` fires on **every** socket connect even with `needsKeyUpload: false` and `E2E_RECONNECT_SKIP_INIT` — four reuploads in 35 min. Not a safety issue (same keys), but pointless chatter on a path touching key material. Look after the deploy.

## 2. `0.1.9` IS STILL NOT LIVE — and why

Re-probed live twice this session:

```
/version.json  → {"version":"0.1.8","gitCommit":"c01317c"}
/version       → {"version":"0.1.8","gitCommit":"7a845430","buildTime":"2026-08-05T19:26:33Z"}
served main.dart.js (7,054,561 B):
  fps1: 6   fp_content_key_ 2        ← B2a live
  fpsig1: 0   fp_sig_key_ 0   peerIdentityVerifyMenuAction 0   ← 0.1.9 absent
```

**Cause is procedural, not technical: the frontend and backend deploys are two separate scripts and only one ran.** The frontend deploy was held behind the B2b canary gate; on 08-05 that gate was proven to be non-evidence and the owner approved sealing ON — but the conversation moved to the canary reading and the session ended with `deploy-web.ps1` never executed. `deploy-backend.sh` DID run (19:26:33Z). Nine days passed. Net effect: the backend half of the wave shipped (`8b66325`, unfriend purge) and the client-side crypto fix (`3d30b88`, MITM warning) did not. Nothing blocks it — HEAD `7663047`, tree clean, CI 4/4.

## 3. Staleness sweep — one real find

- **🔴 A high-severity advisory Dependabot silently failed to deliver, twice.** `npm audit` in `backend/`: js-yaml `GHSA-5p4m-2wfm-xmqj` (quadratic CPU in `!!omap`, CVE-2026-59870 not backported). Runs `31519706831` (08-11) and `31573038380` (08-12) both errored in `bin/run update_files`, so **no PR ever appeared**. It cannot bump the requirement because both copies are transitive dev-only (`cosmiconfig` under `@nestjs/cli`, `@istanbuljs/load-nyc-config` under `ts-jest`); a lockfile-level `npm audit fix` resolves it. **0 vulnerabilities after.** Fixed in `f6e4aa8`.
  - **⚠️ NEW TRAP, generalize this:** Dependabot runs on its own schedule under a **different workflow name**, so `gh run list --branch master --limit 1` after your own push never shows it. Two failures went unseen for three days. Check `gh run list --limit 10` without filtering to CI, or the Security tab.
- **A latent flaky test, found by accident** (first full backend run 669/670, second 670/670, green in isolation). `media-cleanup.service.ts:143` computed `nowMs - stat.mtimeMs < graceMs` against a `nowMs` captured before the loop; **NTFS rounds a just-written mtime UP**, so the difference goes NEGATIVE and an orphan reads as "fresh" even with `graceMs=0`. Two consequences: the `graceMs=0` spec flakes on Windows, and a file stamped in the future **leaked the orphan forever**. Age now clamped at 0. New spec proven **RED against the unclamped code (1 failed / 14 passed)**, green with it. Backend **671/671, 49 suites**; ratchet **PASS 912→907**.
- **Doc gate caught me:** first push went red on `verify-claude-backend-test-counts.mjs` (documented 670, Jest 671). Fixed in `7663047`. That verifier earns its keep — a new backend test REQUIRES the `CLAUDE.md` §3 count bump in the same push.
- **Prettier noise is pre-existing:** both `media/` files fail `prettier --check` before my edits too (verified by stashing). Left alone; formatting count 152→153 is inside the ratchet's ±5 tolerance.

## 4. Tracker cleared — both open issues were stale

- **#102 closed** (brace-expansion "4 of 8 copies still vulnerable") — resolved by drift. Only 1.1.18 / 2.1.4 / 5.0.9 remain, all above the advisory floors. `backend/` 0 vulns, `scripts/smoke/` 0 vulns (only dep is playwright), `frontend/` has no npm tree.
- **#105 closed** (deleting a message never removes local plaintext) — fixed by `42603d2` on **2026-07-28 15:55, ~2.5h after it was filed**, and an ancestor of both `master` and the served `c01317c`. Verified the live handler at `messaging_provider.events.dart:321-352`: captures ciphertext **before** `removeWhere` (a sender's own pending-send plaintext is keyed by ciphertext, not id), purges unconditionally so it covers delete-for-me too, durable backlog written first. **It had been fixed in production for over two weeks while the issue sat open.**
- **0 open issues, 0 open PRs, 0 dependabot alerts** as of this session.

## 5. Deploy-delta accounting

| Target | Prod | Behind | Verdict |
|---|---|---|---|
| Backend | `7a845430` | 1 commit (`f6e4aa8`) | Low urgency — dev-dep lockfile + cron clamp, no migration/entity/compose change. Ride along. |
| Frontend | `c01317c` (0.1.8) | 9 commits touching `frontend/lib` | **Ship.** `3d30b88` (MITM + verify door), `13a9fd1` (B2b), `2645e1f` (19 audit findings), `27e9456` (media 60s budget), `b1893c6` (sweep diags). |

## 6. Branches, stashes, deps — decisions pending owner

- **`feat/invitations-hex-ui` @ `c01317c`** — fully merged (0 unique commits), last touched 08-04. **KEEP until 0.1.9 is deployed and verified**: it is the exact tree of the running build and therefore the rollback reference. Delete after.
- **`origin/feat/cosmic-theme` @ `1745a50`** — 1 unmerged commit, 3.5 weeks stale (07-20): `frontend/tool/starfield_preview.dart`, +16/-4, a `?density=` override for starfield A/B. Dev tool, not shipping code. Cherry-pick or delete the branch.
- **5 stashes, all on branches that no longer exist** (`refactor/message-bubble-dedup`, `feature/composer-trailing-send-voice`). May–July WIP against a pre-E2E-merge tree; they will not apply cleanly. Offered to drop twice, no answer yet.
- **Flutter deps deliberately NOT touched.** `flutter pub outdated`: 32 locked to older, 31 constrained below resolvable, `flutter_secure_storage_macos` + `js` discontinued. **No advisories, all patch/minor transitive drift.** Running `pub upgrade` hours before shipping a release that changes at-rest key handling perturbs the crypto-adjacent graph for zero security benefit — do it after 0.1.9 is field-verified, as its own commit. Note: `flutter_secure_storage_web` is still the 1.2.1 that keeps its raw AES master key in `localStorage`; **no upgrade fixes that**, it needs the non-extractable IndexedDB `CryptoKey` rewrite.

## Queue after this (unchanged order)

1. **Deploy `0.1.9`** — `git pull ; .\deploy-web.ps1`; verify `/version.json` → `0.1.9/7663047`, `cd scripts/smoke && node post-deploy-smoke.mjs` (5/5), then watch first boot for `SIG_SEAL_OPEN {legacy: 0}` + one `SIG_SEAL_DRAIN_DONE`. Escalate on `SIG_KEY_UNAVAILABLE` / `SIG_ROWS_UNREADABLE` / `CONTENT_KEY_LOST`. **Owner must fully close + reopen the PWA on every device. Never uninstall, never clear site data.** Rollback to `c01317c` breaks web decryption until roll-forward — non-destructive.
2. Verify peers 90 / 54 / 92 through the new Safety-section door once 0.1.9 is live.
3. App lock (PIN/biometric/timeout) — HIGH, absent on web AND Android.
4. CSP + `X-Frame-Options` + HSTS + `Cache-Control` on the app document; commit the VM's untracked nginx config into `infra/nginx/fireplace.conf`.
5. Non-extractable IndexedDB `CryptoKey` for web key custody.
6. `getServedMessageIds` mass-purge guard; `E2E_KEYS_REUPLOADED` chatter; then the remaining live findings (`deleteConversationOnly` peer purge, FILE filenames cleartext, password change not dropping sockets, signed prekey never rotated, BE-004).
7. Android: owner-only — `.jks` off-PC backup + fingerprint, `FIREBASE_SERVICE_ACCOUNT` on the VM, fresh-clone device smoke. No code tasks remain.
