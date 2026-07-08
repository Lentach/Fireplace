# Dependency tier 2 triage + release 0.0.97 (socket_io_client 3, typeorm 0.3.30)

**Date:** 2026-07-08 (same day as harness/staging sessions)

## What was done

Triaged and closed out the 5 remaining Dependabot PRs, then released 0.0.97 to production (backend + frontend), fully verified.

**Merged / landed:**
- #46 `typeorm` 0.3.28→0.3.30 — merged; wire-verified via dev backend recreate + harness 7/7; prod-mode verified via `staging.ps1 up` boot of the release image.
- #41 `eslint` 9→10 — merged after baseline comparison: BOTH eslint 9 (master) and 10 produce the identical 966 problems (726 errors) → behaviorally neutral. (Fact discovered: `npm run lint` has been failing on master all along — pre-existing debt, untouched.)
- `socket_io_client` 2.0.3+1→**3.1.6** — the wire major, landed as a direct master commit (`09b7098`) because dependabot's branch predated the webcrypto pin (conflicting lock). Validation: full frontend suite **601/601** + wire harness **7/7** vs socket.io 4.x dev backend + **7/7 vs the prod-mode staging stack**. PR #43 closed as superseded.

**Rejected (deliberate, with dependabot major-ignores set):**
- #44 `typescript` 5.9→7.0 — `npm ci` fails: ERESOLVE, `ts-jest@29.4.11` rejects TS 7. (First validation attempt was misleading: build+tests "passed" on leftover TS 5.9 node_modules from the failed ci — always verify what's actually installed.)
- #42 `flutter_secure_storage` 9→10 — field-confirmed data-loss reports on exactly this upgrade (upstream #1043: "secure storage contents deleted for some users"; `resetOnError=true` by default). Holds device Signal keys on mobile; web (production surface) doesn't use it. Zero benefit, catastrophic downside.

**Release 0.0.97 (`09b7098`):**
- Backend: `./deploy-backend.sh` on the VPS → `/version` 0.0.97/09b7098, `/health` ok.
- Frontend: `deploy-web.ps1` → published, `/version.json` 0.0.97.
- `scripts/smoke` post-deploy: **ALL PASS** incl. bundle-commit stale-build check + headless boot.

## Deploy trap hit (unresolved root cause, mitigations known)
`deploy-web.ps1` twice halted SILENTLY right after "=== Publish via ssh/scp ===" (exit 21, nothing published), and the script FILE intermittently read as missing across tools (git status `D`, read/eval FileNotFound) while bash `ls` saw it — self-healed minutes later; identical content ran clean. NOT OneDrive (no placeholder attrs), NOT Defender (no detections), NOT the ssh line (works standalone). Best guess: transient file lock (indexer/AV scan) during heavy build IO. Practical rule: **if deploy-web halts at the publish header with no error, check `/version.json` — the publish did NOT run; just re-run the script (`-SkipBuild` re-publishes in ~6 s).** Also: piping deploy output through `tail` masks exit codes — run unpiped when diagnosing.

## Key files
- `frontend/pubspec.yaml` — socket_io_client ^3.1.6, version 0.0.97
- PRs: #46/#41 merged, #43 closed-superseded, #44/#42 closed+major-ignored

## Verification
- Frontend suite 601/601 (socket major), harness 7/7 ×4 (dev, dev post-merge, staging prod-mode, release), staging boot of release image, backend 407/407 via CI on merges, public smoke ALL PASS.

## Notes for next session
- Owner: fully close + reopen the PWA on devices (never uninstall) — footer should read 0.0.97 · 09b7098.
- TS 7: revisit when ts-jest/@nestjs support it. flutter_secure_storage 10: only with a mobile migration plan (migrateWithBackup, device matrix).
- Backend lint debt: 726 pre-existing eslint errors, `npm run lint` effectively broken as a gate.
- deploy-web silent-halt trap: see above; consider adding `$LASTEXITCODE` check after the first ssh (line 112) so a failed staging-dir creation aborts loudly.
