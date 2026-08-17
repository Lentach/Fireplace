# HANDOFF — Multi-device program: Phase 0a DONE, continue at 0b (on the branch, not here)

**Date:** 2026-08-18

**⛔ STOP — if you are about to start Phase 0a, don't. It is finished, reviewed (SHIP, 0 mechanism findings), and live-fire verified.** This file exists because master's older handoff (`2026-08-17-HANDOFF-multidevice-execution.md`) still says "start at Phase 0a" — that instruction is superseded for phase sequencing, but the file itself remains REQUIRED reading for its code landmines, library caveats and harness traps, which are all still valid.

## Where the work lives

- **Branch:** `feat/takeover-alarm-0a`, pushed, == origin at `50434a8` (feature `6554fe7` + evidence docs `50434a8`), based on master `b56719f`.
- **Worktree:** `C:/Users/Lentach/Desktop/fireplace-0a` — all multi-device work happens THERE, not in this checkout.
- **PR #144:** open, title `[HOLD until full multi-device]`. **Owner ruling 2026-08-18: do NOT merge until the WHOLE program (0b → 1 → 2 → 3 → optional 4) is done.** All phases accumulate on this one branch; one merge at program end. Phases are still built + verified one at a time, with a phase-gate review each.
- Spec: `docs/design/multi-device.md` (v5 FROZEN). Phase 0a evidence: `2026-08-17-session-phase0a-takeover-alarm.md` + branch LATEST (both on the BRANCH, not master).

## What Phase 0a shipped (identity-replacement alert — detection + recovery surface)

- Backend: migration `0013_identity_change_audit.sql` + `IdentityChangeAudit` entity (registered in BOTH `KeyBundlesModule.forFeature` AND the `app.module.ts` DataSource `entities` list — missing the second is a runtime `EntityMetadataNotFoundError` that all mocked unit tests miss). `upsertKeyBundle` returns `{identityChanged, previousIdentityPublicKey}`; audit row inserted after upsert (non-fatal on failure, loud in logs). `handleUploadKeyBundle` fire-and-forgets: `ownIdentityReplaced {occurredAt}` to the uploader's user room (uploader excluded by construction via `client.to(room)`), content-free push `{type:'identity_changed'}` (bypasses the coalescer), `peerIdentityChanged {userId,occurredAt}` to each conversation peer.
- Frontend: own-identity banner (persisted per user, dismiss = clear) in `main_shell.dart`; peer timeline row in `ChatDetailScreen` reusing the EXISTING `peersWithChangedIdentity` state + fingerprint dialog + acknowledge; ARB en+pl; service-worker + Android FCM local rendering. Wording rule everywhere: "new device/browser sign-in" first — the event also fires on legitimate reinstalls.
- Verified: backend 685/49 + ratchet 906 flat; Flutter 1318/10sk; wire harness 16/2sk live; 3-client visual live-fire in isolated browser contexts.

## Open items a fresh agent must know

1. **CI on PR #144 is phantom-red and it is NOT the code.** Every job dies in 2–4 s with zero steps and no logs. As of 2026-08-18 00:50 CEST this affects ALL branches repo-wide (e.g. `fix/attachment-popover-anchor` fails identically since 15:06Z 08-17; last green run 13:37Z) while githubstatus.com reports all-operational — so the earlier "Actions outage" theory no longer covers it. Leading hypothesis: **Actions minutes/spending limit exhausted on this private repo** (instant-fail-no-logs is the classic symptom; billing API needs a scope `gh` lacks). Owner must check https://github.com/settings/billing. Require 4/4 green once resolved; never merge on red (and not at all until program end).
2. **Next deliverable: Phase 0b** (spec §6.1 registration lock, §6.2 reset ceremony, §6.2.1 recovery key; red-first falsifications 10–21 from §10). Main tooling unknown: server-side (Node) verification of the client's XEdDSA signature over `newIdentityPublicKey ‖ userId ‖ serverNonce` — Dart signs via `Curve.calculateSignature` (64-byte sigs; sign/verify MUTATE passed buffers — pass copies). Research the Node verify path and **ask the owner before adding backend dependencies** (signature lib, `argon2` for the recovery-key hash). The 0a `identityChanged` result from `upsertKeyBundle` is exactly the gate condition. Reset-ceremony state = new table, migration `0014+`, all timer decisions DB-backed (must survive restarts).
3. **Deferred 0a polish (reviewer-acknowledged):** a session offline at event time gets only the OS push — no connect-time replay of the audit row, so its in-app banner never appears. Natural 0b addition (connect-time status fetch, `checkOwnKeyBundle`-style) since the durable audit row already exists.
4. **Owner blockers (keep nagging):** `FIREBASE_SERVICE_ACCOUNT` absent on the VM (FCM dead in prod; verify fix with a REAL device push); `.jks` keystore off-PC backup (`docs/runbooks/android-release.md`).
5. **At final merge only:** PATCH version bump (deliberately NOT bumped on the branch), backend deploy BEFORE web, staging dress rehearsal for schema phases, prod acceptance per spec §9.

## Binding process rules for this program

- Owner rulings: investigate and PROVE, then ASK before writing code (diagnostics count as code; 0b itself is owner-ratified so building it is authorized); ask before opening the browser tool, every time; Anthropic-only subagents, writer concurrency ≤2; never merge/deploy without explicit owner OK.
- Review economics: doc-level review CLOSED; review only at phase gates, delta-scoped, with code in hand. **Phase 2 requires its own spec-level review round before implementation.**
- Rebase the branch onto master periodically (parallel sessions move it) and rerun full suites after every rebase. `git status -sb` before every commit. Root `CLAUDE.md` §3 test counts must be true per-commit-tree.
- Keep security prose defensive/neutral (detection, protection, recovery); adversarially-framed text has tripped provider content filters mid-session twice.

## Reading order for the next agent (in the worktree)

Root `CLAUDE.md` → `backend/CLAUDE.md` → `frontend/CLAUDE.md` (§5) → `docs/design/multi-device.md` → `2026-08-17-HANDOFF-multidevice-execution.md` (landmines; still valid) → branch `2026-08-17-session-phase0a-takeover-alarm.md` → branch LATEST.
